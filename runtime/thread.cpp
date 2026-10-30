#include "thread.h"

#include <bit>
#include <cerrno>
#include <ctime>
#include <new>
#include <pthread.h>
#include <sched.h>
#include <unistd.h>

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
} // namespace

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
  pthread_key_t key{};
  if (pthread_key_create(&key, destructor) != 0)
    return 0;
  // Keys are offset so a valid key is never zero.
  return static_cast<std::uintptr_t>(key) + 1;
}
void mettle_rt_tls_key_free(std::uintptr_t key) {
  pthread_key_delete(static_cast<pthread_key_t>(key - 1));
}
void *mettle_rt_tls_get(std::uintptr_t key) {
  return pthread_getspecific(static_cast<pthread_key_t>(key - 1));
}
std::int32_t mettle_rt_tls_set(std::uintptr_t key, void *value) {
  return pthread_setspecific(static_cast<pthread_key_t>(key - 1), value);
}
}
