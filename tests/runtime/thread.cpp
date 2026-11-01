#include "../../runtime/thread.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>

namespace {
void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    std::exit(1);
  }
}

struct Shared {
  void *mutex = mettle_rt_mutex_new();
  void *cond = mettle_rt_cond_new();
  void *rwlock = mettle_rt_rwlock_new();
  long counter = 0;
  bool ready = false;
  std::atomic<int> woken{0};
};

void count(void *raw) {
  auto &shared = *static_cast<Shared *>(raw);
  for (int i = 0; i < 20000; ++i) {
    require(mettle_rt_mutex_lock(shared.mutex) == 0, "lock failed");
    ++shared.counter;
    require(mettle_rt_mutex_unlock(shared.mutex) == 0, "unlock failed");
  }
}

void wait_ready(void *raw) {
  auto &shared = *static_cast<Shared *>(raw);
  mettle_rt_mutex_lock(shared.mutex);
  while (!shared.ready)
    mettle_rt_cond_wait(shared.cond, shared.mutex);
  mettle_rt_mutex_unlock(shared.mutex);
  shared.woken.fetch_add(1);
}

std::atomic<int> destroyed{0};
void destroy_slot(void *) { destroyed.fetch_add(1); }
void set_slot(void *raw) {
  auto key = *static_cast<std::uintptr_t *>(raw);
  require(mettle_rt_tls_get(key) == nullptr, "slot is per thread");
  static int token;
  require(mettle_rt_tls_set(key, &token) == 0, "set slot");
}
} // namespace

int main() {
  Shared shared;
  require(shared.mutex && shared.cond && shared.rwlock, "allocation failed");

  std::uintptr_t workers[4];
  for (auto &worker : workers)
    require(mettle_rt_thread_spawn(count, &shared, &worker) == 0, "spawn");
  for (auto worker : workers)
    require(mettle_rt_thread_join(worker) == 0, "join");
  require(shared.counter == 4 * 20000, "lost update under the mutex");

  // The error-checking mutex reports a relock instead of deadlocking.
  require(mettle_rt_mutex_lock(shared.mutex) == 0, "lock");
  require(mettle_rt_mutex_lock(shared.mutex) != 0, "relock must fail");
  require(mettle_rt_mutex_try_lock(shared.mutex) != 0, "try_lock while held");
  require(mettle_rt_mutex_unlock(shared.mutex) == 0, "unlock");

  std::uintptr_t waiters[3];
  for (auto &waiter : waiters)
    require(mettle_rt_thread_spawn(wait_ready, &shared, &waiter) == 0, "spawn");
  mettle_rt_mutex_lock(shared.mutex);
  shared.ready = true;
  mettle_rt_cond_notify_all(shared.cond);
  mettle_rt_mutex_unlock(shared.mutex);
  for (auto waiter : waiters)
    mettle_rt_thread_join(waiter);
  require(shared.woken.load() == 3, "waiters missed the broadcast");

  mettle_rt_mutex_lock(shared.mutex);
  require(mettle_rt_cond_wait_timeout(shared.cond, shared.mutex, 1000000) == 1,
          "timed wait must time out");
  mettle_rt_mutex_unlock(shared.mutex);

  require(mettle_rt_rwlock_read(shared.rwlock) == 0, "read");
  require(mettle_rt_rwlock_try_read(shared.rwlock) == 0, "second reader");
  require(mettle_rt_rwlock_try_write(shared.rwlock) == 1, "writer excluded");
  mettle_rt_rwlock_unlock(shared.rwlock);
  mettle_rt_rwlock_unlock(shared.rwlock);
  require(mettle_rt_rwlock_write(shared.rwlock) == 0, "write");
  require(mettle_rt_rwlock_try_read(shared.rwlock) == 1, "reader excluded");
  require(mettle_rt_rwlock_try_write(shared.rwlock) == 1,
          "recursive writer excluded");
  mettle_rt_rwlock_unlock(shared.rwlock);

  auto key = mettle_rt_tls_key_new(destroy_slot);
  require(key != 0, "tls key");
  std::uintptr_t other;
  require(mettle_rt_thread_spawn(set_slot, &key, &other) == 0, "spawn");
  mettle_rt_thread_join(other);
  require(destroyed.load() == 1, "thread exit must run the slot destructor");
  require(mettle_rt_tls_get(key) == nullptr, "main slot is independent");
  mettle_rt_tls_key_free(key);

  require(mettle_rt_thread_parallelism() >= 1, "parallelism");
  mettle_rt_cond_free(shared.cond);
  mettle_rt_mutex_free(shared.mutex);
  mettle_rt_rwlock_free(shared.rwlock);
  return 0;
}
