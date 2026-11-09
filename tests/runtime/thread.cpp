#include "../../runtime/sys.h"
#include "../../runtime/thread.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <sys/time.h>
#include <unistd.h>

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
void identify(void *raw) {
  *static_cast<std::uintptr_t *>(raw) = mettle_rt_thread_current();
}
void interruptPoll(int) {}
} // namespace

int main() {
  std::uintptr_t previous = mettle_rt_thread_current();
  require(previous == mettle_rt_thread_current(), "current identity is stable");
  for (int i = 0; i < 128; ++i) {
    std::uintptr_t observed = 0, handle = 0;
    require(mettle_rt_thread_spawn(identify, &observed, &handle) == 0,
            "spawn identity");
    require(mettle_rt_thread_join(handle) == 0, "join identity");
    require(handle == observed && handle != previous, "thread identity reused");
    mettle_rt_thread_unpark(previous);
    char name[64]{};
    if (i != 0)
      require(mettle_rt_thread_name(previous, name, sizeof name) < 0,
              "exited thread name must not access a recycled pthread");
    previous = handle;
  }
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
  // Signals may interrupt poll, but must not restart its finite deadline.
  struct sigaction action{}, previousAction{};
  action.sa_handler = interruptPoll;
  sigemptyset(&action.sa_mask);
  require(sigaction(SIGALRM, &action, &previousAction) == 0, "install signal");
  int pipeEnds[2];
  require(pipe(pipeEnds) == 0, "poll pipe");
  itimerval timer{{0, 5000}, {0, 5000}}, previousTimer{};
  require(setitimer(ITIMER_REAL, &timer, &previousTimer) == 0, "start signals");
  const auto start = std::chrono::steady_clock::now();
  const auto ready = mettle_rt_poll(pipeEnds[0], 0, 30);
  const auto elapsed = std::chrono::steady_clock::now() - start;
  itimerval stopped{};
  require(setitimer(ITIMER_REAL, &stopped, nullptr) == 0, "stop signals");
  require(sigaction(SIGALRM, &previousAction, nullptr) == 0, "restore signal");
  require(setitimer(ITIMER_REAL, &previousTimer, nullptr) == 0, "restore timer");
  close(pipeEnds[0]);
  close(pipeEnds[1]);
  require(ready == 0 && elapsed >= std::chrono::milliseconds(20) &&
              elapsed < std::chrono::seconds(2),
          "interruption extended poll deadline");
  mettle_rt_cond_free(shared.cond);
  mettle_rt_mutex_free(shared.mutex);
  mettle_rt_rwlock_free(shared.rwlock);
  return 0;
}
