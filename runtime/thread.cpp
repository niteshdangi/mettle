#include "thread.h"
#include "panic.h"

#include <bit>
#include <cerrno>
#include <cstddef>
#include <cstdlib>
#include <ctime>
#include <exception>
#include <limits.h>
#include <memory>
#include <new>
#include <pthread.h>
#include <sched.h>
#include <unistd.h>
#include <utility>
#include <vector>

extern "C" void mettleRtTlsThreadDestructor(void *raw);

namespace {
struct Start {
  MettleThreadEntry entry;
  void *argument;
};
extern "C" void *threadMain(void *raw) {
  auto *start = static_cast<Start *>(raw);
  auto entry = start->entry;
  auto *argument = start->argument;
  delete start;
  entry(argument);
  return nullptr;
}
timespec deadline(std::uint64_t nanoseconds) {
  timespec now{};
  clock_gettime(CLOCK_REALTIME, &now);
  const std::uint64_t billion = 1000000000u;
  std::uint64_t seconds =
      static_cast<std::uint64_t>(now.tv_sec) + nanoseconds / billion;
  std::uint64_t rest =
      static_cast<std::uint64_t>(now.tv_nsec) + nanoseconds % billion;
  seconds += rest / billion;
  return {static_cast<time_t>(seconds), static_cast<long>(rest % billion)};
}
template <typename T, typename Init> void *create(Init init) {
  auto *object = new (std::nothrow) T;
  if (!object)
    return nullptr;
  if (init(object) != 0) {
    delete object;
    return nullptr;
  }
  return object;
}

struct TlsKeyInfo {
  std::uintptr_t handle;
  pthread_key_t key;
  MettleTlsDestructor destructor;
  const void *staticIdentity;
  std::size_t activeThreads;
  bool retired;
};

struct TlsThreadState {
  // Contains each key with a live value once, in first-assignment order.
  std::vector<std::uintptr_t> activeKeys;
};

pthread_mutex_t tlsKeyMutex = PTHREAD_MUTEX_INITIALIZER;
std::vector<TlsKeyInfo> tlsKeys;
pthread_once_t tlsStateOnce = PTHREAD_ONCE_INIT;
pthread_key_t tlsStateKey{};
int tlsStateStatus = 0;

pthread_mutex_t selectMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t selectCondition = PTHREAD_COND_INITIALIZER;
std::uint64_t selectGeneration = 0;

void tlsThreadExitBody(void *raw);
void tlsThreadExit(void *raw);

void initializeTlsStateKey() {
  tlsStateStatus =
      pthread_key_create(&tlsStateKey, mettleRtTlsThreadDestructor);
}

TlsThreadState *tlsThreadState(bool create) {
  if (pthread_once(&tlsStateOnce, initializeTlsStateKey) != 0 ||
      tlsStateStatus != 0)
    return nullptr;
  auto *state = static_cast<TlsThreadState *>(pthread_getspecific(tlsStateKey));
  if (state || !create)
    return state;
  std::unique_ptr<TlsThreadState> owned(new (std::nothrow) TlsThreadState);
  if (!owned)
    return nullptr;
  if (pthread_setspecific(tlsStateKey, owned.get()) != 0)
    return nullptr;
  return owned.release();
}

bool findTlsKeyLocked(std::uintptr_t handle, std::size_t &index) {
  for (std::size_t i = 0; i < tlsKeys.size(); ++i) {
    if (tlsKeys[i].handle == handle) {
      index = i;
      return true;
    }
  }
  return false;
}

void removeActiveKey(TlsThreadState &state, std::uintptr_t handle) {
  for (std::size_t i = state.activeKeys.size(); i != 0; --i) {
    if (state.activeKeys[i - 1] == handle) {
      state.activeKeys.erase(state.activeKeys.begin() +
                             static_cast<std::ptrdiff_t>(i - 1));
      return;
    }
  }
}

void tlsThreadExitBody(void *raw) {
  std::unique_ptr<TlsThreadState> state(static_cast<TlsThreadState *>(raw));
  if (!state)
    return;
  if (pthread_setspecific(tlsStateKey, state.get()) != 0)
    return;
  std::exception_ptr failure;
  for (int pass = 0; pass < PTHREAD_DESTRUCTOR_ITERATIONS; ++pass) {
    // Values reinstalled by a destructor are handled in a later pass.
    auto pending = std::move(state->activeKeys);
    state->activeKeys.clear();
    if (pending.empty())
      break;
    for (std::size_t i = pending.size(); i != 0; --i) {
      const auto handle = pending[i - 1];
      TlsKeyInfo info{};
      bool found = false;
      if (pthread_mutex_lock(&tlsKeyMutex) == 0) {
        std::size_t index = 0;
        if (findTlsKeyLocked(handle, index)) {
          info = tlsKeys[index];
          found = true;
        }
        pthread_mutex_unlock(&tlsKeyMutex);
      }
      if (!found)
        continue;
      void *value = pthread_getspecific(info.key);
      if (!value)
        continue;
      if (mettle_rt_tls_set(handle, nullptr) == 0 && info.destructor) {
        try {
          info.destructor(value);
        } catch (...) {
          if (!failure)
            failure = std::current_exception();
        }
      }
    }
  }
  while (!state->activeKeys.empty()) {
    const auto handle = state->activeKeys.back();
    TlsKeyInfo info{};
    bool found = false;
    if (pthread_mutex_lock(&tlsKeyMutex) == 0) {
      std::size_t index = 0;
      if (findTlsKeyLocked(handle, index)) {
        info = tlsKeys[index];
        found = true;
      }
      pthread_mutex_unlock(&tlsKeyMutex);
    }
    if (!found) {
      state->activeKeys.pop_back();
      continue;
    }
    if (mettle_rt_tls_set(handle, nullptr) != 0)
      state->activeKeys.pop_back();
  }
  (void)pthread_setspecific(tlsStateKey, nullptr);
  if (failure)
    std::rethrow_exception(failure);
}

void tlsThreadExit(void *raw) {
  try {
    tlsThreadExitBody(raw);
  } catch (...) {
    std::abort();
  }
}

void tlsThreadExitAction(void *) { mettle_rt_tls_thread_exit(); }
} // namespace

extern "C" void mettleRtTlsThreadDestructor(void *raw) { tlsThreadExit(raw); }

extern "C" {
std::int32_t mettle_rt_thread_spawn(MettleThreadEntry entry, void *argument,
                                    std::uintptr_t *handle) {
  auto *start = new (std::nothrow) Start{entry, argument};
  if (!start)
    return ENOMEM;
  pthread_t thread{};
  int status = pthread_create(&thread, nullptr, threadMain, start);
  if (status != 0) {
    delete start;
    return status;
  }
  *handle = std::bit_cast<std::uintptr_t>(thread);
  return 0;
}
std::int32_t mettle_rt_thread_join(std::uintptr_t handle) {
  return pthread_join(std::bit_cast<pthread_t>(handle), nullptr);
}
std::int32_t mettle_rt_thread_detach(std::uintptr_t handle) {
  return pthread_detach(std::bit_cast<pthread_t>(handle));
}
std::int32_t mettle_rt_thread_catch(void *context, MettleThreadBody body) {
  const auto status = mettle_rt_catch(context, body);
  const auto tlsStatus = mettle_rt_catch(nullptr, tlsThreadExitAction);
  if (status != 0 && tlsStatus != 0)
    std::abort();
  return status == 0 ? tlsStatus : status;
}
std::uintptr_t mettle_rt_thread_current() {
  return std::bit_cast<std::uintptr_t>(pthread_self());
}
void mettle_rt_thread_yield() { sched_yield(); }
void mettle_rt_thread_sleep(std::uint64_t nanoseconds) {
  timespec request{static_cast<time_t>(nanoseconds / 1000000000u),
                   static_cast<long>(nanoseconds % 1000000000u)};
  while (nanosleep(&request, &request) != 0 && errno == EINTR) {
  }
}
std::uint64_t mettle_rt_thread_parallelism() {
  long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 ? static_cast<std::uint64_t>(count) : 1;
}

void *mettle_rt_mutex_new() {
  return create<pthread_mutex_t>([](pthread_mutex_t *mutex) {
    pthread_mutexattr_t attributes;
    if (pthread_mutexattr_init(&attributes) != 0)
      return EINVAL;
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_ERRORCHECK);
    int status = pthread_mutex_init(mutex, &attributes);
    pthread_mutexattr_destroy(&attributes);
    return status;
  });
}
void mettle_rt_mutex_free(void *mutex) {
  auto *object = static_cast<pthread_mutex_t *>(mutex);
  pthread_mutex_destroy(object);
  delete object;
}
std::int32_t mettle_rt_mutex_lock(void *mutex) {
  return pthread_mutex_lock(static_cast<pthread_mutex_t *>(mutex));
}
std::int32_t mettle_rt_mutex_try_lock(void *mutex) {
  return pthread_mutex_trylock(static_cast<pthread_mutex_t *>(mutex));
}
std::int32_t mettle_rt_mutex_unlock(void *mutex) {
  return pthread_mutex_unlock(static_cast<pthread_mutex_t *>(mutex));
}

void *mettle_rt_cond_new() {
  return create<pthread_cond_t>(
      [](pthread_cond_t *cond) { return pthread_cond_init(cond, nullptr); });
}
void mettle_rt_cond_free(void *cond) {
  auto *object = static_cast<pthread_cond_t *>(cond);
  pthread_cond_destroy(object);
  delete object;
}
std::int32_t mettle_rt_cond_wait(void *cond, void *mutex) {
  return pthread_cond_wait(static_cast<pthread_cond_t *>(cond),
                           static_cast<pthread_mutex_t *>(mutex));
}
std::int32_t mettle_rt_cond_wait_timeout(void *cond, void *mutex,
                                         std::uint64_t nanoseconds) {
  auto limit = deadline(nanoseconds);
  int status =
      pthread_cond_timedwait(static_cast<pthread_cond_t *>(cond),
                             static_cast<pthread_mutex_t *>(mutex), &limit);
  return status == ETIMEDOUT ? 1 : 0;
}
std::int32_t mettle_rt_cond_notify_one(void *cond) {
  return pthread_cond_signal(static_cast<pthread_cond_t *>(cond));
}
std::int32_t mettle_rt_cond_notify_all(void *cond) {
  return pthread_cond_broadcast(static_cast<pthread_cond_t *>(cond));
}

void *mettle_rt_rwlock_new() {
  return create<pthread_rwlock_t>([](pthread_rwlock_t *lock) {
    return pthread_rwlock_init(lock, nullptr);
  });
}
void mettle_rt_rwlock_free(void *lock) {
  auto *object = static_cast<pthread_rwlock_t *>(lock);
  pthread_rwlock_destroy(object);
  delete object;
}
std::int32_t mettle_rt_rwlock_read(void *lock) {
  return pthread_rwlock_rdlock(static_cast<pthread_rwlock_t *>(lock));
}
std::int32_t mettle_rt_rwlock_try_read(void *lock) {
  return pthread_rwlock_tryrdlock(static_cast<pthread_rwlock_t *>(lock));
}
std::int32_t mettle_rt_rwlock_write(void *lock) {
  return pthread_rwlock_wrlock(static_cast<pthread_rwlock_t *>(lock));
}
std::int32_t mettle_rt_rwlock_try_write(void *lock) {
  return pthread_rwlock_trywrlock(static_cast<pthread_rwlock_t *>(lock));
}
std::int32_t mettle_rt_rwlock_unlock(void *lock) {
  return pthread_rwlock_unlock(static_cast<pthread_rwlock_t *>(lock));
}

std::uintptr_t mettle_rt_tls_key_new(MettleTlsDestructor destructor) {
  if (pthread_once(&tlsStateOnce, initializeTlsStateKey) != 0 ||
      tlsStateStatus != 0)
    return 0;
  pthread_key_t key{};
  if (pthread_key_create(&key, nullptr) != 0)
    return 0;
  const auto handle = static_cast<std::uintptr_t>(key) + 1;
  if (pthread_mutex_lock(&tlsKeyMutex) != 0) {
    pthread_key_delete(key);
    return 0;
  }
  try {
    tlsKeys.push_back(TlsKeyInfo{handle, key, destructor, nullptr, 0, false});
  } catch (...) {
    pthread_mutex_unlock(&tlsKeyMutex);
    pthread_key_delete(key);
    return 0;
  }
  pthread_mutex_unlock(&tlsKeyMutex);
  return handle;
}
std::uintptr_t mettle_rt_tls_static_key_new(const void *identity,
                                            MettleTlsDestructor destructor) {
  if (!identity || pthread_once(&tlsStateOnce, initializeTlsStateKey) != 0 ||
      tlsStateStatus != 0)
    return 0;
  if (pthread_mutex_lock(&tlsKeyMutex) != 0)
    return 0;
  for (const auto &info : tlsKeys) {
    if (info.staticIdentity == identity) {
      const auto handle = info.destructor == destructor ? info.handle : 0;
      pthread_mutex_unlock(&tlsKeyMutex);
      return handle;
    }
  }
  pthread_key_t key{};
  if (pthread_key_create(&key, nullptr) != 0) {
    pthread_mutex_unlock(&tlsKeyMutex);
    return 0;
  }
  const auto handle = static_cast<std::uintptr_t>(key) + 1;
  try {
    tlsKeys.push_back(TlsKeyInfo{handle, key, destructor, identity, 0, false});
  } catch (...) {
    pthread_mutex_unlock(&tlsKeyMutex);
    pthread_key_delete(key);
    return 0;
  }
  pthread_mutex_unlock(&tlsKeyMutex);
  return handle;
}
void mettle_rt_tls_key_free(std::uintptr_t key) {
  if (pthread_mutex_lock(&tlsKeyMutex) != 0)
    return;
  std::size_t index = 0;
  if (!findTlsKeyLocked(key, index)) {
    pthread_mutex_unlock(&tlsKeyMutex);
    return;
  }
  auto &info = tlsKeys[index];
  info.retired = true;
  if (info.activeThreads != 0) {
    pthread_mutex_unlock(&tlsKeyMutex);
    return;
  }
  const auto nativeKey = info.key;
  tlsKeys.erase(tlsKeys.begin() + static_cast<std::ptrdiff_t>(index));
  pthread_mutex_unlock(&tlsKeyMutex);
  pthread_key_delete(nativeKey);
}
void *mettle_rt_tls_get(std::uintptr_t key) {
  TlsKeyInfo info{};
  bool found = false;
  if (pthread_mutex_lock(&tlsKeyMutex) != 0)
    return nullptr;
  std::size_t index = 0;
  if (findTlsKeyLocked(key, index)) {
    info = tlsKeys[index];
    found = true;
  }
  pthread_mutex_unlock(&tlsKeyMutex);
  return found ? pthread_getspecific(info.key) : nullptr;
}
std::int32_t mettle_rt_tls_set(std::uintptr_t key, void *value) {
  if (pthread_mutex_lock(&tlsKeyMutex) != 0)
    return EINVAL;
  std::size_t index = 0;
  if (!findTlsKeyLocked(key, index)) {
    pthread_mutex_unlock(&tlsKeyMutex);
    return EINVAL;
  }
  auto &info = tlsKeys[index];
  void *previous = pthread_getspecific(info.key);
  if (value && !previous && info.retired) {
    pthread_mutex_unlock(&tlsKeyMutex);
    return EINVAL;
  }
  TlsThreadState *state = nullptr;
  if (value && !previous) {
    state = tlsThreadState(true);
    if (!state) {
      pthread_mutex_unlock(&tlsKeyMutex);
      return ENOMEM;
    }
    try {
      state->activeKeys.push_back(key);
    } catch (...) {
      pthread_mutex_unlock(&tlsKeyMutex);
      return ENOMEM;
    }
  }
  const int status = pthread_setspecific(info.key, value);
  if (status != 0) {
    if (value && !previous)
      state->activeKeys.pop_back();
    pthread_mutex_unlock(&tlsKeyMutex);
    return status;
  }
  if (value && !previous) {
    ++info.activeThreads;
  } else if (!value && previous) {
    state = tlsThreadState(false);
    if (state)
      removeActiveKey(*state, key);
    --info.activeThreads;
  }
  const bool releaseKey = info.retired && info.activeThreads == 0;
  const auto nativeKey = info.key;
  if (releaseKey)
    tlsKeys.erase(tlsKeys.begin() + static_cast<std::ptrdiff_t>(index));
  pthread_mutex_unlock(&tlsKeyMutex);
  if (releaseKey)
    pthread_key_delete(nativeKey);
  return 0;
}

void mettle_rt_tls_thread_exit() {
  auto *state = tlsThreadState(false);
  if (state)
    tlsThreadExitBody(state);
}

std::uint64_t mettle_rt_select_epoch() {
  if (pthread_mutex_lock(&selectMutex) != 0)
    return 0;
  const auto epoch = selectGeneration;
  pthread_mutex_unlock(&selectMutex);
  return epoch;
}
void mettle_rt_select_wait(std::uint64_t epoch) {
  if (pthread_mutex_lock(&selectMutex) != 0)
    return;
  while (selectGeneration == epoch) {
    if (pthread_cond_wait(&selectCondition, &selectMutex) != 0)
      break;
  }
  pthread_mutex_unlock(&selectMutex);
}
void mettle_rt_select_notify() {
  if (pthread_mutex_lock(&selectMutex) != 0)
    return;
  ++selectGeneration;
  pthread_mutex_unlock(&selectMutex);
  pthread_cond_broadcast(&selectCondition);
}
}
