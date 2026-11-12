#include "../../runtime/thread.h"
#include "../../runtime/sys.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <fcntl.h>
#include <initializer_list>
#include <limits>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace {
void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    std::exit(1);
  }
}

void reentrantMutexCases(bool checkOwnershipErrors = true) {
  void *mutex = mettle_rt_reentrant_mutex_new();
  require(mutex != nullptr, "recursive mutex allocation failed");
  require(mettle_rt_mutex_lock(mutex) == 0 && mettle_rt_mutex_lock(mutex) == 0,
          "recursive mutex did not allow same-thread nesting");
  const auto excluded = [&] {
    std::thread worker([&] {
      require(mettle_rt_mutex_try_lock(mutex) == 1,
              "recursive mutex admitted a different thread while owned");
      if (checkOwnershipErrors)
        require(mettle_rt_mutex_unlock(mutex) != 0,
                "recursive mutex admitted a non-owner unlock");
    });
    worker.join();
  };
  excluded();
  std::atomic<bool> attempting{false}, acquired{false};
  std::thread waiter([&] {
    require(mettle_rt_mutex_try_lock(mutex) == 1,
            "recursive waiter was not initially excluded");
    attempting.store(true, std::memory_order_release);
    require(mettle_rt_mutex_lock(mutex) == 0, "recursive waiter lock failed");
    acquired.store(true, std::memory_order_release);
    require(mettle_rt_mutex_unlock(mutex) == 0,
            "recursive waiter unlock failed");
  });
  while (!attempting.load(std::memory_order_acquire))
    std::this_thread::yield();
  require(!acquired.load(std::memory_order_acquire),
          "recursive waiter acquired at depth two");
  require(mettle_rt_mutex_unlock(mutex) == 0, "recursive inner unlock failed");
  excluded();
  require(!acquired.load(std::memory_order_acquire),
          "recursive waiter acquired before the outermost unlock");
  require(mettle_rt_mutex_unlock(mutex) == 0, "recursive outer unlock failed");
  waiter.join();
  require(acquired.load(std::memory_order_acquire),
          "recursive waiter did not acquire after the outermost unlock");
  int protectedValue = 0;
  std::array<std::thread, 2> workers;
  for (auto &worker : workers)
    worker = std::thread([&] {
      for (int i = 0; i < 1000; ++i) {
        require(mettle_rt_mutex_lock(mutex) == 0 &&
                    mettle_rt_mutex_lock(mutex) == 0,
                "recursive worker lock failed");
        ++protectedValue;
        require(mettle_rt_mutex_unlock(mutex) == 0 &&
                    mettle_rt_mutex_unlock(mutex) == 0,
                "recursive worker unlock failed");
      }
    });
  for (auto &worker : workers)
    worker.join();
  require(protectedValue == 2000, "recursive mutex lost a protected update");
  mettle_rt_mutex_free(mutex);
}

void rwlockDowngradeCases() {
  void *lock = mettle_rt_rwlock_new();
  require(lock != nullptr, "rwlock allocation failed");
  require(mettle_rt_rwlock_downgrade(nullptr) == -EINVAL &&
              mettle_rt_rwlock_downgrade(lock) == -EPERM,
          "downgrade without a writer hold did not report failure");
  require(mettle_rt_rwlock_write(lock) == 0, "downgrade writer lock failed");
  require(mettle_rt_rwlock_read(lock) == EDEADLK &&
              mettle_rt_rwlock_write(lock) == EDEADLK &&
              mettle_rt_rwlock_try_read(lock) == 1 &&
              mettle_rt_rwlock_try_write(lock) == 1,
          "writer relock lost its error or busy result");
  std::thread nonOwner([&] {
    require(mettle_rt_rwlock_downgrade(lock) == -EPERM &&
                mettle_rt_rwlock_unlock(lock) == EPERM &&
                mettle_rt_rwlock_try_read(lock) == 1,
            "non-owner conversion or unlock released the writer");
  });
  nonOwner.join();
  require(mettle_rt_rwlock_downgrade(lock) == 0, "writer downgrade failed");
  require(mettle_rt_rwlock_downgrade(lock) == -EPERM &&
              mettle_rt_rwlock_try_read(lock) == 0 &&
              mettle_rt_rwlock_try_write(lock) == 1,
          "failed second downgrade changed the shared hold");
  require(mettle_rt_rwlock_unlock(lock) == 0 &&
              mettle_rt_rwlock_try_write(lock) == 1 &&
              mettle_rt_rwlock_unlock(lock) == 0 &&
              mettle_rt_rwlock_try_write(lock) == 0 &&
              mettle_rt_rwlock_unlock(lock) == 0,
          "downgrade did not retain exactly one read hold");
  mettle_rt_rwlock_free(lock);

  lock = mettle_rt_rwlock_new();
  require(lock && mettle_rt_rwlock_write(lock) == 0,
          "contended downgrade setup failed");
  int value = 0;
  std::atomic<bool> writerContended{false}, writerAcquired{false};
  std::atomic<bool> readerContended{false}, readerGo{false},
      readerAcquired{false};
  std::atomic<bool> finalRead{false}, finalReadChecked{false},
      releaseRead{false};
  std::thread writer([&] {
    require(mettle_rt_rwlock_try_write(lock) == 1,
            "pending writer did not observe exclusive contention");
    writerContended.store(true, std::memory_order_release);
    require(mettle_rt_rwlock_write(lock) == 0, "pending writer lock failed");
    writerAcquired.store(true, std::memory_order_release);
    require(value == 42, "downgrade did not publish to the next writer");
    value = 84;
    require(mettle_rt_rwlock_unlock(lock) == 0, "pending writer unlock failed");
  });
  std::thread reader([&] {
    require(mettle_rt_rwlock_try_read(lock) == 1,
            "pending reader did not observe exclusive contention");
    readerContended.store(true, std::memory_order_release);
    // This gate schedules acquisition; only the rwlock publishes the payload.
    while (!readerGo.load(std::memory_order_relaxed))
      std::this_thread::yield();
    require(mettle_rt_rwlock_read(lock) == 0, "downgraded reader lock failed");
    require(value == 42, "downgrade did not publish to another reader");
    readerAcquired.store(true, std::memory_order_release);
    while (!finalRead.load(std::memory_order_acquire))
      std::this_thread::yield();
    require(mettle_rt_rwlock_try_write(lock) == 1 && value == 42,
            "writer acquired before the final reader released");
    finalReadChecked.store(true, std::memory_order_release);
    while (!releaseRead.load(std::memory_order_acquire))
      std::this_thread::yield();
    require(mettle_rt_rwlock_unlock(lock) == 0, "final reader unlock failed");
  });
  while (!writerContended.load(std::memory_order_acquire) ||
         !readerContended.load(std::memory_order_acquire))
    std::this_thread::yield();
  value = 42;
  require(mettle_rt_rwlock_downgrade(lock) == 0, "contended downgrade failed");
  require(!writerAcquired.load(std::memory_order_acquire) && value == 42 &&
              mettle_rt_rwlock_try_write(lock) == 1,
          "writer intervened during downgrade");
  readerGo.store(true, std::memory_order_relaxed);
  while (!readerAcquired.load(std::memory_order_acquire))
    std::this_thread::yield();
  require(!writerAcquired.load(std::memory_order_acquire),
          "writer acquired through the downgraded read hold");
  require(mettle_rt_rwlock_unlock(lock) == 0,
          "downgraded reader unlock failed");
  finalRead.store(true, std::memory_order_release);
  while (!finalReadChecked.load(std::memory_order_acquire))
    std::this_thread::yield();
  require(!writerAcquired.load(std::memory_order_acquire),
          "writer acquired with another reader still holding");
  releaseRead.store(true, std::memory_order_release);
  reader.join();
  writer.join();
  require(writerAcquired.load(std::memory_order_acquire) && value == 84,
          "writer did not acquire after the final read release");
  mettle_rt_rwlock_free(lock);
}

void filesystemTimeCases() {
  struct File {
    char path[40] = "mettle-runtime-times-XXXXXX";
    char link[48]{};
    int fd = mkstemp(path);
    ~File() {
      if (fd >= 0)
        close(fd);
      if (link[0])
        unlink(link);
      unlink(path);
    }
  } file;
  require(file.fd >= 0 && write(file.fd, "abc", 3) == 3,
          "timestamp fixture creation failed");
  require(mettle_rt_file_set_times(file.fd, 3, 10, 123456700, 20, 987654300) ==
              0,
          "setting both descriptor timestamps failed");
  std::array<std::int64_t, 10> initial{}, updated{};
  const auto snapshot = [&](auto &out) {
    require(mettle_rt_stat_full(nullptr, file.fd, 1, out.data()) == 0,
            "descriptor full metadata failed");
    require((out[9] & 3) == 3 && out[4] >= 0 && out[4] < 1000000000 &&
                out[6] >= 0 && out[6] < 1000000000,
            "full metadata omitted or denormalized a POSIX timestamp");
  };
  snapshot(initial);
  require(initial[0] == 3 && initial[1] == 0 && initial[3] == 20 &&
              initial[4] == 987654300 && initial[5] == 10 &&
              initial[6] == 123456700,
          "full metadata lost size, kind or timestamp precision");
  require(mettle_rt_file_set_times(file.fd, 2, 0, UINT_MAX, -1, 999999900) == 0,
          "modified-only pre-epoch timestamp failed");
  snapshot(updated);
  require(updated[3] == -1 && updated[4] == 999999900 &&
              updated[5] == initial[5] && updated[6] == initial[6],
          "modified-only update changed access time or lost pre-epoch sign");
  require(mettle_rt_file_set_times(file.fd, 1, 30, 456789100, 0, UINT_MAX) == 0,
          "accessed-only timestamp failed");
  snapshot(initial);
  require(initial[5] == 30 && initial[6] == 456789100 &&
              initial[3] == updated[3] && initial[4] == updated[4],
          "accessed-only update changed modification time");
  require(mettle_rt_file_set_times(file.fd, 0, INT64_MIN, UINT_MAX, INT64_MAX,
                                   UINT_MAX) == 0,
          "omitted timestamps were validated or written");
  snapshot(updated);
  require(initial == updated, "empty timestamp update changed metadata");
  for (auto mask : {1u, 2u, 4u}) {
    errno = 0;
    require(mettle_rt_file_set_times(file.fd, mask, 0, 1000000000, 0,
                                     1000000000) == -1 &&
                errno == EINVAL,
            "invalid timestamp fields or mask did not report EINVAL");
  }
  snapshot(updated);
  require(initial == updated, "invalid timestamp request partially updated");
  if (!std::in_range<time_t>(INT64_MIN)) {
    require(mettle_rt_file_set_times(file.fd, 1, INT64_MIN, 0, 0, 0) == -1 &&
                errno == EOVERFLOW,
            "timestamp outside time_t silently narrowed");
  }
  errno = 0;
  require(mettle_rt_file_set_times(-1, 1, 0, 0, 0, 0) == -1 && errno == EBADF,
          "descriptor timestamp failure lost errno");
  std::array<std::int64_t, 5> legacy{};
  require(mettle_rt_stat(file.path, -1, 1, legacy.data()) == 0 &&
              std::equal(legacy.begin(), legacy.end(), initial.begin()),
          "full metadata changed the legacy five-slot ABI");
  std::snprintf(file.link, sizeof file.link, "%s-link", file.path);
  require(symlink(file.path, file.link) == 0, "timestamp symlink setup failed");
  require(mettle_rt_stat_full(file.link, -1, 0, updated.data()) == 0 &&
              updated[1] == 2,
          "full metadata followed a no-follow symlink");
  require(mettle_rt_stat_full(file.link, -1, 1, updated.data()) == 0 &&
              updated == initial,
          "full metadata did not follow a symlink coherently");
#ifdef __linux__
  struct statx native{};
  if (statx(file.fd, "", AT_EMPTY_PATH, STATX_BASIC_STATS | STATX_BTIME,
            &native) == 0) {
    require(((initial[9] & 4) != 0) == ((native.stx_mask & STATX_BTIME) != 0),
            "birth time availability did not match the filesystem");
    if (native.stx_mask & STATX_BTIME)
      require(initial[7] == native.stx_btime.tv_sec &&
                  initial[8] == native.stx_btime.tv_nsec,
              "birth time did not come from the metadata snapshot");
  } else {
    require(errno == ENOSYS && (initial[9] & 4) == 0,
            "stat fallback invented a birth time");
  }
#endif
  errno = 0;
  require(mettle_rt_stat_full(file.path, -1, 1, nullptr) == -1 &&
              errno == EINVAL,
          "null metadata output was accepted");
  require(unlink(file.path) == 0, "timestamp fixture unlink failed");
  updated.fill(-17);
  const auto unchanged = updated;
  errno = 0;
  require(mettle_rt_stat_full(file.path, -1, 1, updated.data()) == -1 &&
              errno == ENOENT && updated == unchanged,
          "failed metadata lookup lost errno or published a partial snapshot");
  snapshot(updated);
  require(updated == initial, "unlinked descriptor metadata changed");
}

#ifdef __linux__
struct DescriptorAudit {
  bool socketSeen = false, pipeSeen = false;
  bool socketSafe = true, pipeSafe = true;
};
thread_local DescriptorAudit *descriptorAudit = nullptr;

bool closesOnExec(int fd) {
  char number[32];
  std::snprintf(number, sizeof number, "%d", fd);
  const pid_t child = fork();
  if (child == 0) {
    execl("/proc/self/exe", "mettle-thread-tests", "--fd-probe", number,
          nullptr);
    _exit(127);
  }
  int status = 0;
  pid_t waited;
  do {
    waited = child < 0 ? -1 : waitpid(child, &status, 0);
  } while (waited < 0 && errno == EINTR && child >= 0);
  return waited == child && child > 0 && WIFEXITED(status) &&
         WEXITSTATUS(status) == 0;
}

void descriptorCases() {
  DescriptorAudit audit;
  descriptorAudit = &audit;
  int socket = mettle_rt_sock_new(0, 4);
  const char *args[] = {"/bin/true", nullptr};
  const std::int32_t modes[] = {0, 0, 0};
  std::int32_t fds[3];
  int child = mettle_rt_spawn(args[0], args, nullptr, nullptr, modes, fds);
  descriptorAudit = nullptr;
  require(socket >= 0, "socket creation failed");
  ::close(socket);
  int status = 0;
  require(child > 0 && waitpid(child, &status, 0) == child &&
              WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "process creation failed");
  require(audit.socketSeen && audit.socketSafe,
          "new socket was inherited before close-on-exec was set");
  require(audit.pipeSeen && audit.pipeSafe,
          "new process pipe was inherited before close-on-exec was set");
}

enum class AcceptKind { Theft, Interrupted, PollInterrupted, Notify, Error };
struct AcceptScript {
  AcceptKind kind = AcceptKind::Theft;
  int fd = -1, thief = -1, calls = 0, polls = 0, clockReads = 0;
  int lastAccepted = -1;
  bool clockFailure = false;
  sockaddr_in address{};
  timespec now{40, 0};
  std::array<int, 4> waits{};
};
thread_local AcceptScript *activeAccept = nullptr;
struct AcceptScope {
  AcceptScript *previous = activeAccept;
  explicit AcceptScope(AcceptScript &script) { activeAccept = &script; }
  ~AcceptScope() { activeAccept = previous; }
};
void advanceAccept(AcceptScript &script, int millis) {
  require(millis >= 0, "accept used an unexpected infinite wait");
  script.now.tv_sec += millis / 1000;
  script.now.tv_nsec += (millis % 1000) * 1000000L;
  script.now.tv_sec += script.now.tv_nsec / 1000000000L;
  script.now.tv_nsec %= 1000000000L;
}

enum class InitFailure { None, Mutex, Attributes, Clock, Condition };
struct Script {
  InitFailure failure = InitFailure::None;
  int mutexInits = 0, mutexDestroys = 0;
  int attributeInits = 0, attributeDestroys = 0;
  int conditionInits = 0, conditionDestroys = 0;
  int clockSelections = 0, clockReads = 0;
  timespec now{20, 900000000};
  pthread_mutex_t *mutex = nullptr;
  pthread_cond_t *condition = nullptr;
  std::array<int, 4> statuses{0, ETIMEDOUT, EIO, ETIMEDOUT};
  std::array<timespec, 4> limits{};
  std::size_t waits = 0;
  bool sleep = false, stopAfterChunk = false;
  std::size_t sleepCalls = 0;
  timespec remainder{};
  std::uint64_t sleptSeconds = 0;
  long sleptNanos = 0;
};
thread_local Script *activeScript = nullptr;
struct ScriptScope {
  Script *previous = activeScript;
  explicit ScriptScope(Script &script) { activeScript = &script; }
  ~ScriptScope() { activeScript = previous; }
};
struct SleepPrefixComplete {};

bool sameTime(timespec first, timespec second) {
  return first.tv_sec == second.tv_sec && first.tv_nsec == second.tv_nsec;
}
void recordSleep(Script &script, timespec elapsed) {
  const auto seconds = static_cast<std::uint64_t>(elapsed.tv_sec);
  const auto nanos = script.sleptNanos + elapsed.tv_nsec;
  const auto carry = static_cast<std::uint64_t>(nanos / 1000000000);
  const auto maximum = std::numeric_limits<std::uint64_t>::max();
  require(seconds <= maximum - script.sleptSeconds &&
              carry <= maximum - script.sleptSeconds - seconds,
          "sleep duration accounting overflowed");
  script.sleptSeconds += seconds + carry;
  script.sleptNanos = nanos % 1000000000;
}
void sleepCases() {
  for (auto seconds :
       {std::uint64_t{0}, std::uint64_t{1}, std::uint64_t{INT_MAX} * 2 + 5}) {
    Script script;
    script.sleep = true;
    ScriptScope scope(script);
    mettle_rt_sleep(seconds, 987654321);
    require(script.sleepCalls >= 3 && script.sleptSeconds == seconds &&
                script.sleptNanos == 987654321,
            "interrupted sleep lost or duplicated duration");
  }
  // Stop the wide prefix before INT_MAX chunking requires billions of calls.
  for (auto seconds :
       {std::uint64_t{1} << 63, std::numeric_limits<std::uint64_t>::max()}) {
    Script script;
    script.sleep = script.stopAfterChunk = true;
    ScriptScope scope(script);
    bool stopped = false;
    try {
      mettle_rt_sleep(seconds, 123);
    } catch (const SleepPrefixComplete &) {
      stopped = true;
    }
    require(stopped && script.sleepCalls == 4 && script.sleptSeconds > 0 &&
                script.sleptNanos == 123,
            "full-width sleep did not resume and advance to its next chunk");
  }
  Script script;
  script.sleep = true;
  ScriptScope scope(script);
  const auto nanos = std::numeric_limits<std::uint64_t>::max();
  mettle_rt_thread_sleep(nanos);
  require(script.sleepCalls == 3 && script.sleptSeconds == nanos / 1000000000 &&
              script.sleptNanos == static_cast<long>(nanos % 1000000000),
          "thread sleep lost its interrupted remainder");
}

void conditionCases() {
  for (auto failure :
       {InitFailure::Attributes, InitFailure::Clock, InitFailure::Condition}) {
    Script script;
    script.failure = failure;
    ScriptScope scope(script);
    require(mettle_rt_cond_new() == nullptr,
            "condition initialization failure was ignored");
    require(
        script.attributeInits == 1 &&
            script.attributeDestroys ==
                (failure == InitFailure::Attributes ? 0 : 1) &&
            script.clockSelections ==
                (failure == InitFailure::Attributes ? 0 : 1) &&
            script.conditionInits ==
                (failure == InitFailure::Condition ? 1 : 0) &&
            script.conditionDestroys == 0,
        "failed condition initialization leaked or destroyed invalid state");
  }
  Script script;
  ScriptScope scope(script);
  auto *condition = mettle_rt_cond_new();
  auto *mutex = mettle_rt_mutex_new();
  require(condition && mutex && mettle_rt_mutex_lock(mutex) == 0,
          "condition script setup failed");
  require(mettle_rt_cond_wait_timeout(condition, mutex, 200000001) == 0,
          "condition notification/spurious return was not successful");
  require(mettle_rt_cond_wait_timeout(condition, mutex, 0) == 1,
          "zero condition timeout did not report timeout");
  require(mettle_rt_cond_wait_timeout(condition, mutex, 1) == -1,
          "condition wait error was not propagated");
  require(mettle_rt_mutex_unlock(mutex) == 0, "condition mutex lost ownership");
  mettle_rt_cond_free(condition);
  mettle_rt_mutex_free(mutex);
  require(script.clockReads > 0 && script.waits == 3 &&
              sameTime(script.limits[0], {21, 100000001}) &&
              sameTime(script.limits[1], {21, 0}) &&
              sameTime(script.limits[2], {21, 1}) &&
              script.clockSelections == 1 && script.attributeDestroys == 1 &&
              script.conditionInits == 1 && script.conditionDestroys == 1 &&
              script.mutexInits == 1 && script.mutexDestroys == 1,
          "condition deadline normalization or resource cleanup changed");
}
void rwlockInitializationCases() {
  for (auto failure : {InitFailure::Mutex, InitFailure::Attributes,
                       InitFailure::Clock, InitFailure::Condition}) {
    Script script;
    script.failure = failure;
    ScriptScope scope(script);
    require(mettle_rt_rwlock_new() == nullptr,
            "rwlock initialization failure published a handle");
    require(
        script.mutexInits == 1 &&
            script.mutexDestroys == (failure == InitFailure::Mutex ? 0 : 1) &&
            script.attributeInits == (failure == InitFailure::Mutex ? 0 : 1) &&
            script.attributeDestroys ==
                (failure == InitFailure::Clock ||
                         failure == InitFailure::Condition
                     ? 1
                     : 0) &&
            script.conditionInits ==
                (failure == InitFailure::Condition ? 1 : 0) &&
            script.conditionDestroys == 0,
        "failed rwlock initialization leaked or destroyed partial state");
  }
  Script script;
  ScriptScope scope(script);
  void *lock = mettle_rt_rwlock_new();
  require(lock != nullptr, "rwlock monitor initialization failed");
  mettle_rt_rwlock_free(lock);
  require(script.mutexInits == 1 && script.mutexDestroys == 1 &&
              script.conditionInits == 1 && script.conditionDestroys == 1 &&
              script.attributeInits == 1 && script.attributeDestroys == 1,
          "rwlock destruction did not release its monitor exactly once");
}

void parkingCases() {
  for (auto failure : {InitFailure::Mutex, InitFailure::Attributes,
                       InitFailure::Clock, InitFailure::Condition}) {
    Script script;
    script.failure = failure;
    std::thread worker([&] {
      activeScript = &script;
      mettle_rt_thread_park_timeout(1);
    });
    worker.join();
    require(
        script.mutexInits == 1 &&
            script.mutexDestroys == (failure == InitFailure::Mutex ? 0 : 1) &&
            script.attributeInits == (failure == InitFailure::Mutex ? 0 : 1) &&
            script.attributeDestroys ==
                (failure == InitFailure::Clock ||
                         failure == InitFailure::Condition
                     ? 1
                     : 0) &&
            script.conditionInits ==
                (failure == InitFailure::Condition ? 1 : 0) &&
            script.conditionDestroys == 0 && script.waits == 0,
        "failed parking initialization leaked or used partial state");
  }
  Script script;
  std::thread worker([&] {
    activeScript = &script;
    auto identity = mettle_rt_thread_current();
    mettle_rt_thread_unpark(identity);
    mettle_rt_thread_park_timeout(0);
    require(script.waits == 0,
            "preexisting park token did not bypass the wait");
    mettle_rt_thread_park_timeout(200000001);
    mettle_rt_thread_park_timeout(1);
    mettle_rt_thread_park_timeout(0);
  });
  worker.join();
  require(script.waits == 4 && script.clockReads > 0 &&
              sameTime(script.limits[0], {21, 100000001}) &&
              sameTime(script.limits[1], script.limits[0]) &&
              sameTime(script.limits[2], {21, 100000002}) &&
              sameTime(script.limits[3], {21, 100000001}) &&
              script.attributeInits == 1 && script.clockSelections == 1 &&
              script.attributeDestroys == 1 && script.conditionInits == 1 &&
              script.conditionDestroys == 1 && script.mutexInits == 1 &&
              script.mutexDestroys == 1,
          "parking retried with a fresh deadline or leaked thread-local state");
}

struct Descriptor {
  int value = -1;
  explicit Descriptor(int fd = -1) : value(fd) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  void close() {
    if (value >= 0)
      ::close(value);
    value = -1;
  }
  ~Descriptor() { close(); }
};
struct AcceptPeer {
  std::int32_t timedOut = -1, family = 0;
  std::array<std::uint8_t, 16> address{};
  std::uint16_t port = 0;
  std::uint32_t flowinfo = 0, scopeId = 0;
};
int acceptWithScript(AcceptScript &script, int timeout, int nonblocking,
                     AcceptPeer &peer, std::size_t capacity = 16) {
  AcceptScope scope(script);
  return mettle_rt_sock_accept(script.fd, timeout, nonblocking, &peer.timedOut,
                               &peer.family, peer.address.data(), capacity,
                               &peer.port, &peer.flowinfo, &peer.scopeId);
}
void acceptCases() {
  Descriptor listener(mettle_rt_sock_new(0, 4));
  require(listener.value >= 0 && mettle_rt_set_nonblocking(listener.value) == 0,
          "accept listener setup failed");
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  require(bind(listener.value, reinterpret_cast<sockaddr *>(&address),
               sizeof address) == 0 &&
              listen(listener.value, 8) == 0,
          "accept listener bind failed");
  socklen_t size = sizeof address;
  require(getsockname(listener.value, reinterpret_cast<sockaddr *>(&address),
                      &size) == 0,
          "accept listener address failed");
  Descriptor thief(mettle_rt_dup(listener.value));
  require(thief.value >= 3, "accept listener clone failed");
  const int initialFlags = fcntl(listener.value, F_GETFL);
  auto fresh = [&](AcceptKind kind) {
    AcceptScript script;
    script.kind = kind;
    script.fd = listener.value;
    script.thief = thief.value;
    script.address = address;
    return script;
  };
  for (int budget : {80, 130}) {
    auto script = fresh(AcceptKind::Theft);
    AcceptPeer peer;
    Descriptor result(acceptWithScript(script, budget, 0, peer));
    const int code = errno;
    require(result.value == -1 && code == EAGAIN && peer.timedOut == 1 &&
                script.polls == 2 && script.waits[0] == budget &&
                script.waits[1] == budget - 25 && script.now.tv_sec == 40 &&
                script.now.tv_nsec == budget * 1000000L,
            "stolen accept readiness returned early or reset the deadline");
  }
  for (auto kind : {AcceptKind::Interrupted, AcceptKind::PollInterrupted}) {
    auto script = fresh(kind);
    AcceptPeer peer;
    Descriptor result(acceptWithScript(script, 80, 0, peer));
    const int code = errno;
    require(result.value == -1 && code == EAGAIN && peer.timedOut == 1 &&
                script.polls > 0 && script.waits[script.polls - 1] == 60 &&
                script.now.tv_sec == 40 && script.now.tv_nsec == 80000000,
            "accept interruption restarted its deadline");
  }
  {
    auto script = fresh(AcceptKind::Notify);
    script.clockFailure = true;
    AcceptPeer peer;
    Descriptor result(acceptWithScript(script, 80, 1, peer));
    const int code = errno;
    require(result.value == -1 && (code == EAGAIN || code == EWOULDBLOCK) &&
                peer.timedOut == 0 && script.polls == 0 &&
                script.clockReads == 0,
            "logical nonblocking accept waited or became a timeout");
  }
  {
    auto script = fresh(AcceptKind::Notify);
    script.clockFailure = true;
    AcceptPeer peer;
    require(acceptWithScript(script, 80, 0, peer) == -1 && errno == EIO &&
                peer.timedOut == 0 && script.calls == 0,
            "accept clock failure was hidden as a timeout");
  }
  {
    auto script = fresh(AcceptKind::Error);
    AcceptPeer peer;
    require(acceptWithScript(script, 80, 0, peer) == -1 &&
                errno == ECONNABORTED && peer.timedOut == 0 &&
                script.polls == 0,
            "terminal accept error lost its raw cause");
  }
  {
    auto script = fresh(AcceptKind::Notify);
    AcceptPeer peer;
    Descriptor result(acceptWithScript(script, -1, 0, peer));
    require(result.value >= 0 && peer.timedOut == 0 && peer.family == 4 &&
                peer.port != 0 && script.polls == 1 && script.waits[0] == -1 &&
                script.clockReads == 0 &&
                (fcntl(result.value, F_GETFL) & O_NONBLOCK) == 0 &&
                (fcntl(result.value, F_GETFD) & FD_CLOEXEC) != 0,
            "untimed accept or accepted-stream mode/ownership changed");
  }
  {
    auto script = fresh(AcceptKind::Notify);
    AcceptPeer peer;
    require(acceptWithScript(script, 80, 0, peer, 0) == -1 && errno == EINVAL &&
                peer.timedOut == 0 && script.lastAccepted >= 0,
            "invalid accept output did not retain its raw error");
    require(fcntl(script.lastAccepted, F_GETFD) == -1 && errno == EBADF,
            "accept output failure leaked the accepted descriptor");
  }
  require(initialFlags >= 0 && fcntl(listener.value, F_GETFL) == initialFlags &&
              fcntl(thief.value, F_GETFL) == initialFlags &&
              (initialFlags & O_NONBLOCK) != 0 &&
              (fcntl(listener.value, F_GETFD) & FD_CLOEXEC) != 0 &&
              (fcntl(thief.value, F_GETFD) & FD_CLOEXEC) != 0,
          "accept changed shared listener flags or clone inheritance");
}
struct Child {
  pid_t pid;
  bool group = false;
  ~Child() {
    if (pid <= 0)
      return;
    if (!group || kill(-pid, SIGKILL) < 0)
      kill(pid, SIGKILL);
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
  }
  bool finish() {
    int status = 0;
    pid_t result;
    do {
      result = waitpid(pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result != pid)
      return false;
    pid = -1;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
  }
};
int stdioProbe(const char *mode) {
  if (mode[0] == 'b') {
    int input = -1, output = -1;
    if (std::sscanf(mode + 1, "%d,%d", &input, &output) != 2 ||
        fcntl(input, F_GETFD) != -1 || errno != EBADF ||
        fcntl(output, F_GETFD) != -1 || errno != EBADF)
      return 1;
  }
  if (mode[0] == 'i') {
    const auto mask = mode[1] - '0';
    for (int fd = 0; fd < 3; ++fd)
      if ((fcntl(fd, F_GETFD) < 0) != ((mask & (1 << fd)) != 0))
        return 1;
    return 0;
  }
  char byte = 0;
  if (mode[0] == 'n')
    return read(0, &byte, 1) != 0 || write(1, "n", 1) != 1 ||
                   write(2, "n", 1) != 1
               ? 1
               : 0;
  return read(0, &byte, 1) != 1 || byte != 'q' || write(1, &byte, 1) != 1 ||
                 write(2, "e", 1) != 1
             ? 1
             : 0;
}
bool spawnModes(const char *executable, int mask,
                std::array<std::int32_t, 3> modes, const char *mode) {
  char inherited[] = {'i', static_cast<char>('0' + mask), '\0'};
  const char *arguments[] = {executable, "--stdio-probe",
                             mode[0] == 'i' ? inherited : mode, nullptr};
  std::int32_t fds[3]{-2, -2, -2};
  const auto pid = mettle_rt_spawn(executable, arguments, nullptr, nullptr,
                                   modes.data(), fds);
  if (pid < 0)
    return false;
  Child child{pid};
  Descriptor input(fds[0]), output(fds[1]), error(fds[2]);
  for (int i = 0; i < 3; ++i)
    if ((modes[i] == 1 && fds[i] <= 2) || (modes[i] != 1 && fds[i] != -1))
      return false;
  if (modes[0] == 1) {
    if (write(input.value, "q", 1) != 1)
      return false;
    input.close();
    char byte = 0;
    if (read(output.value, &byte, 1) != 1 || byte != 'q')
      return false;
    if (modes[2] == 1 && (read(error.value, &byte, 1) != 1 || byte != 'e'))
      return false;
  }
  return child.finish();
}
int openDescriptorCount() {
  DIR *directory = opendir("/proc/self/fd");
  if (!directory)
    return -1;
  int count = 0;
  while (const auto *entry = readdir(directory))
    if (entry->d_name[0] != '.')
      ++count;
  closedir(directory);
  return count;
}
bool borrowedStdio(const char *executable) {
  int inputEnds[2], outputEnds[2];
  if (pipe(inputEnds) != 0)
    return false;
  Descriptor input(inputEnds[0]), feed(inputEnds[1]);
  if (pipe(outputEnds) != 0)
    return false;
  Descriptor output(outputEnds[0]), sink(outputEnds[1]);
  const std::int32_t modes[] = {3, 3, 3};
  const std::int32_t sources[] = {input.value, sink.value, sink.value};
  char probe[64];
  std::snprintf(probe, sizeof probe, "b%d,%d", input.value, sink.value);
  const char *arguments[] = {executable, "--stdio-probe", probe, nullptr};
  const int initialCount = openDescriptorCount();
  if (initialCount < 0)
    return false;
  for (int flags : {0, FD_CLOEXEC}) {
    if (fcntl(input.value, F_SETFD, flags) != 0 ||
        fcntl(sink.value, F_SETFD, flags) != 0)
      return false;
    for (int attempt = 0; attempt < 2; ++attempt) {
      if (write(feed.value, "q", 1) != 1)
        return false;
      std::int32_t fds[3]{-2, -2, -2};
      Child child{mettle_rt_spawn_with_sources(executable, arguments, nullptr,
                                               nullptr, modes, sources, fds)};
      if (child.pid <= 0 || !child.finish() || fds[0] != -1 || fds[1] != -1 ||
          fds[2] != -1 || fcntl(input.value, F_GETFD) != flags ||
          fcntl(sink.value, F_GETFD) != flags)
        return false;
      char bytes[2]{};
      if (read(output.value, bytes, 2) != 2 || bytes[0] != 'q' ||
          bytes[1] != 'e' || openDescriptorCount() != initialCount)
        return false;
    }
  }
  Descriptor hole(mettle_rt_dup(input.value));
  const int invalid = hole.value;
  if (invalid < 0)
    return false;
  hole.close();
  for (const auto failureModes : {std::array<std::int32_t, 3>{1, 3, 1},
                                  std::array<std::int32_t, 3>{3, 3, 1}}) {
    const std::int32_t invalidSources[] = {input.value, invalid, -1};
    std::int32_t fds[3]{-2, -2, -2};
    Child child{mettle_rt_spawn_with_sources(executable, arguments, nullptr,
                                             nullptr, failureModes.data(),
                                             invalidSources, fds)};
    const int failure = errno;
    if (child.pid != -1 || failure != EBADF || fds[0] != -1 || fds[1] != -1 ||
        fds[2] != -1 || openDescriptorCount() != initialCount ||
        fcntl(invalid, F_GETFD) != -1 || errno != EBADF)
      return false;
  }
  for (bool badDirectory : {false, true}) {
    const char *program =
        badDirectory ? executable : "/proc/self/mettle-test-missing";
    const char *cwd = badDirectory ? "/proc/self/mettle-test-missing" : nullptr;
    const std::int32_t failureModes[] = {1, 3, 1};
    std::int32_t fds[3]{-2, -2, -2};
    Child child{mettle_rt_spawn_with_sources(program, arguments, nullptr, cwd,
                                             failureModes, sources, fds)};
    const int failure = errno;
    if (child.pid != -1 || failure != ENOENT || fds[0] != -1 || fds[1] != -1 ||
        fds[2] != -1 || openDescriptorCount() != initialCount ||
        fcntl(input.value, F_GETFD) != FD_CLOEXEC ||
        fcntl(sink.value, F_GETFD) != FD_CLOEXEC)
      return false;
    int status = 0;
    if (waitpid(-1, &status, WNOHANG) != -1 || errno != ECHILD)
      return false;
  }
  int errorEnds[2];
  if (pipe(errorEnds) != 0)
    return false;
  Descriptor error(errorEnds[0]), errorSink(errorEnds[1]);
  Descriptor savedInput(mettle_rt_dup(0)), savedOutput(mettle_rt_dup(1)),
      savedError(mettle_rt_dup(2));
  if (savedInput.value < 0 || savedOutput.value < 0 || savedError.value < 0 ||
      dup2(input.value, 0) < 0 || dup2(sink.value, 1) < 0 ||
      dup2(errorSink.value, 2) < 0)
    return false;
  for (const auto standardSources : {std::array<std::int32_t, 3>{0, 1, 2},
                                     std::array<std::int32_t, 3>{0, 2, 1},
                                     std::array<std::int32_t, 3>{0, 1, 1},
                                     std::array<std::int32_t, 3>{0, 2, 2}}) {
    if (write(feed.value, "q", 1) != 1)
      return false;
    const char *standardArguments[] = {executable, "--stdio-probe", "p",
                                       nullptr};
    std::int32_t fds[3]{-2, -2, -2};
    Child child{mettle_rt_spawn_with_sources(executable, standardArguments,
                                             nullptr, nullptr, modes,
                                             standardSources.data(), fds)};
    if (child.pid <= 0 || !child.finish() || fds[0] != -1 || fds[1] != -1 ||
        fds[2] != -1)
      return false;
    char byte = 0;
    if (standardSources[1] != standardSources[2]) {
      const int out = standardSources[1] == 1 ? output.value : error.value;
      const int err = standardSources[2] == 1 ? output.value : error.value;
      if (read(out, &byte, 1) != 1 || byte != 'q' || read(err, &byte, 1) != 1 ||
          byte != 'e')
        return false;
    } else {
      char bytes[2]{};
      const int combined = standardSources[1] == 1 ? output.value : error.value;
      if (read(combined, bytes, 2) != 2 || bytes[0] != 'q' || bytes[1] != 'e')
        return false;
    }
    if (write(1, "o", 1) != 1 || write(2, "e", 1) != 1 ||
        read(output.value, &byte, 1) != 1 || byte != 'o' ||
        read(error.value, &byte, 1) != 1 || byte != 'e' ||
        fcntl(0, F_GETFD) != 0 || fcntl(1, F_GETFD) != 0 ||
        fcntl(2, F_GETFD) != 0)
      return false;
  }
  return dup2(savedInput.value, 0) == 0 && dup2(savedOutput.value, 1) == 1 &&
         dup2(savedError.value, 2) == 2;
}
bool closedStdio(const char *executable, int mask) {
  struct sigaction action{};
  action.sa_handler = SIG_IGN;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGPIPE, &action, nullptr) != 0)
    return false;
  for (int fd = 0; fd < 3; ++fd) {
    if (fcntl(fd, F_GETFD) < 0) {
      Descriptor null(open("/dev/null", O_RDWR));
      if (null.value < 0 || dup2(null.value, fd) < 0)
        return false;
      if (null.value == fd)
        null.value = -1;
    }
    const int flags = fcntl(fd, F_GETFD);
    if (flags < 0 || fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC) < 0)
      return false;
  }
  if (mask == 0 && !borrowedStdio(executable))
    return false;
  for (int fd = 0; fd < 3; ++fd)
    if (mask & (1 << fd))
      ::close(fd);
  if (!spawnModes(executable, mask, {1, 1, 1}, "p") ||
      !spawnModes(executable, mask, {1, 1, 2}, "p") ||
      !spawnModes(executable, mask, {2, 2, 2}, "n") ||
      !spawnModes(executable, mask, {0, 0, 0}, "i"))
    return false;
  for (auto modes : {std::array<std::int32_t, 3>{2, 2, 2},
                     std::array<std::int32_t, 3>{1, 1, 1},
                     std::array<std::int32_t, 3>{0, 0, 0}}) {
    const char *missing[] = {"/proc/self/mettle-test-missing", nullptr};
    std::int32_t fds[3]{-2, -2, -2};
    errno = 0;
    const auto pid = mettle_rt_spawn(missing[0], missing, nullptr, nullptr,
                                     modes.data(), fds);
    const auto failure = errno;
    Child unexpected{pid};
    Descriptor input(fds[0]), output(fds[1]), error(fds[2]);
    if (pid != -1 || failure != ENOENT || fds[0] != -1 || fds[1] != -1 ||
        fds[2] != -1)
      return false;
  }
  return true;
}
bool isolatedStdio(int mask) {
  int ends[2];
  if (pipe(ends) != 0)
    return false;
  Descriptor reader(ends[0]), writer(ends[1]);
  Descriptor highReader(fcntl(reader.value, F_DUPFD_CLOEXEC, 3));
  Descriptor highWriter(fcntl(writer.value, F_DUPFD_CLOEXEC, 3));
  reader.close();
  writer.close();
  if (highReader.value < 0 || highWriter.value < 0)
    return false;
  const auto pid = fork();
  if (pid < 0)
    return false;
  if (pid == 0) {
    highReader.close();
    const char result =
        setpgid(0, 0) == 0 && closedStdio("/proc/self/exe", mask) ? 0 : 1;
    const auto written = write(highWriter.value, &result, 1);
    _exit(written == 1 && result == 0 ? 0 : 1);
  }
  Child child{pid, true};
  (void)setpgid(pid, pid);
  highWriter.close();
  pollfd request{highReader.value, POLLIN, 0};
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(30);
  int ready = 0;
  do {
    const auto remaining = std::chrono::ceil<std::chrono::milliseconds>(
        deadline - std::chrono::steady_clock::now());
    if (remaining.count() <= 0)
      break;
    ready = poll(&request, 1, static_cast<int>(remaining.count()));
  } while (ready < 0 && errno == EINTR);
  char result = 1;
  return ready == 1 && read(highReader.value, &result, 1) == 1 && result == 0 &&
         child.finish();
}
#endif

struct Shared {
  void *mutex = mettle_rt_mutex_new();
  void *cond = mettle_rt_cond_new();
  void *rwlock = mettle_rt_rwlock_new();
  long counter = 0;
  bool ready = false;
  std::atomic<int> waiting{0};
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
  shared.waiting.fetch_add(1, std::memory_order_release);
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

#ifdef __linux__
extern "C" {
int __real_socket(int, int, int) noexcept;
int __real_pipe(int *) noexcept;
int __real_pipe2(int *, int) noexcept;
int __wrap_socket(int domain, int type, int protocol) noexcept {
  const int fd = __real_socket(domain, type, protocol);
  if (fd >= 0 && descriptorAudit) {
    const int saved = errno;
    descriptorAudit->socketSeen = true;
    descriptorAudit->socketSafe &= closesOnExec(fd);
    errno = saved;
  }
  return fd;
}
int __wrap_pipe(int *ends) noexcept {
  const int status = __real_pipe(ends);
  if (status == 0 && descriptorAudit) {
    const int saved = errno;
    descriptorAudit->pipeSeen = true;
    descriptorAudit->pipeSafe &= closesOnExec(ends[0]) && closesOnExec(ends[1]);
    errno = saved;
  }
  return status;
}
int __wrap_pipe2(int *ends, int flags) noexcept {
  const int status = __real_pipe2(ends, flags);
  if (status == 0 && descriptorAudit) {
    const int saved = errno;
    descriptorAudit->pipeSeen = true;
    descriptorAudit->pipeSafe &= closesOnExec(ends[0]) && closesOnExec(ends[1]);
    errno = saved;
  }
  return status;
}
int __real_nanosleep(const timespec *, timespec *);
int __real_clock_gettime(clockid_t, timespec *) noexcept;
int __real_accept4(int, sockaddr *, socklen_t *, int);
int __real_poll(pollfd *, nfds_t, int);
int __real_pthread_mutex_init(pthread_mutex_t *,
                              const pthread_mutexattr_t *) noexcept;
int __real_pthread_mutex_destroy(pthread_mutex_t *) noexcept;
int __real_pthread_condattr_init(pthread_condattr_t *) noexcept;
int __real_pthread_condattr_setclock(pthread_condattr_t *, clockid_t) noexcept;
int __real_pthread_condattr_destroy(pthread_condattr_t *) noexcept;
int __real_pthread_cond_init(pthread_cond_t *,
                             const pthread_condattr_t *) noexcept;
int __real_pthread_cond_destroy(pthread_cond_t *) noexcept;
int __real_pthread_cond_timedwait(pthread_cond_t *, pthread_mutex_t *,
                                  const timespec *);

int __wrap_accept4(int fd, sockaddr *address, socklen_t *size, int flags) {
  auto *script = activeAccept;
  if (!script || fd != script->fd)
    return __real_accept4(fd, address, size, flags);
  require((flags & SOCK_CLOEXEC) != 0, "accept omitted atomic close-on-exec");
  const auto call = script->calls++;
  if (script->kind == AcceptKind::Error) {
    errno = ECONNABORTED;
    return -1;
  }
  if (script->kind == AcceptKind::Interrupted && call < 2) {
    advanceAccept(*script, 10);
    errno = EINTR;
    return -1;
  }
  const int result = __real_accept4(fd, address, size, flags);
  if (result >= 0)
    script->lastAccepted = result;
  return result;
}
int __wrap_poll(pollfd *requests, nfds_t count, int timeout) {
  auto *script = activeAccept;
  if (!script || count != 1 || requests[0].fd != script->fd)
    return __real_poll(requests, count, timeout);
  require(script->polls < static_cast<int>(script->waits.size()),
          "accept exhausted its deadline without finishing");
  const auto call = script->polls++;
  script->waits[call] = timeout;
  if (script->kind == AcceptKind::PollInterrupted && call == 0) {
    advanceAccept(*script, 20);
    errno = EINTR;
    return -1;
  }
  if ((script->kind == AcceptKind::Theft && call == 0) ||
      script->kind == AcceptKind::Notify) {
    Descriptor client(socket(AF_INET, SOCK_STREAM, 0));
    require(client.value >= 0 &&
                connect(client.value,
                        reinterpret_cast<sockaddr *>(&script->address),
                        sizeof script->address) == 0 &&
                __real_poll(requests, count, 0) == 1,
            "accept readiness setup failed");
    if (script->kind == AcceptKind::Theft) {
      Descriptor stolen(accept(script->thief, nullptr, nullptr));
      require(stolen.value >= 0, "raw clone did not consume readiness");
      advanceAccept(*script, 25);
    }
    return 1;
  }
  advanceAccept(*script, timeout);
  requests[0].revents = 0;
  return 0;
}
int __wrap_nanosleep(const timespec *request, timespec *remaining) {
  auto *script = activeScript;
  if (!script || !script->sleep)
    return __real_nanosleep(request, remaining);
  const auto value = *request;
  require(value.tv_sec >= 0 && value.tv_nsec >= 0 && value.tv_nsec < 1000000000,
          "sleep produced a negative or unnormalized request");
  const auto call = script->sleepCalls++;
  if (script->stopAfterChunk && call == 3) {
    require(value.tv_sec > 0, "full-width sleep lost its remaining seconds");
    throw SleepPrefixComplete{};
  }
  if (call > 0 && call <= 2)
    require(sameTime(value, script->remainder),
            "sleep retried the original duration instead of the remainder");
  if (call < 2) {
    require(!script->stopAfterChunk || value.tv_sec > 0,
            "full-width sleep truncated to zero");
    script->remainder = value.tv_sec > 0
                            ? timespec{value.tv_sec - 1, value.tv_nsec}
                            : timespec{0, value.tv_nsec / 2};
    *remaining = script->remainder;
    recordSleep(*script, {value.tv_sec - script->remainder.tv_sec,
                          value.tv_nsec - script->remainder.tv_nsec});
    errno = EINTR;
    return -1;
  }
  recordSleep(*script, value);
  return 0;
}
int __wrap_clock_gettime(clockid_t clock, timespec *value) noexcept {
  if (activeAccept) {
    require(clock == CLOCK_MONOTONIC, "accept deadline used wall time");
    ++activeAccept->clockReads;
    if (activeAccept->clockFailure) {
      errno = EIO;
      return -1;
    }
    *value = activeAccept->now;
    return 0;
  }
  if (!activeScript || activeScript->sleep)
    return __real_clock_gettime(clock, value);
  require(clock == CLOCK_MONOTONIC, "deadline used wall time");
  ++activeScript->clockReads;
  *value = activeScript->now;
  return 0;
}
int __wrap_pthread_mutex_init(pthread_mutex_t *mutex,
                              const pthread_mutexattr_t *attributes) noexcept {
  if (activeScript) {
    ++activeScript->mutexInits;
    if (activeScript->failure == InitFailure::Mutex)
      return EAGAIN;
  }
  const int status = __real_pthread_mutex_init(mutex, attributes);
  if (activeScript && status == 0)
    activeScript->mutex = mutex;
  return status;
}
int __wrap_pthread_mutex_destroy(pthread_mutex_t *mutex) noexcept {
  if (activeScript)
    require(mutex == activeScript->mutex, "destroyed the wrong mutex");
  const int status = __real_pthread_mutex_destroy(mutex);
  if (activeScript) {
    ++activeScript->mutexDestroys;
    require(status == 0, "mutex cleanup failed");
    activeScript->mutex = nullptr;
  }
  return status;
}
int __wrap_pthread_condattr_init(pthread_condattr_t *attributes) noexcept {
  if (activeScript) {
    ++activeScript->attributeInits;
    if (activeScript->failure == InitFailure::Attributes)
      return EAGAIN;
  }
  return __real_pthread_condattr_init(attributes);
}
int __wrap_pthread_condattr_setclock(pthread_condattr_t *attributes,
                                     clockid_t clock) noexcept {
  if (activeScript) {
    ++activeScript->clockSelections;
    require(clock == CLOCK_MONOTONIC, "condition selected a wall clock");
    if (activeScript->failure == InitFailure::Clock)
      return EINVAL;
  }
  return __real_pthread_condattr_setclock(attributes, clock);
}
int __wrap_pthread_condattr_destroy(pthread_condattr_t *attributes) noexcept {
  const int status = __real_pthread_condattr_destroy(attributes);
  if (activeScript) {
    ++activeScript->attributeDestroys;
    require(status == 0, "condition attribute cleanup failed");
  }
  return status;
}
int __wrap_pthread_cond_init(pthread_cond_t *condition,
                             const pthread_condattr_t *attributes) noexcept {
  if (activeScript) {
    ++activeScript->conditionInits;
    clockid_t clock = CLOCK_REALTIME;
    require(attributes && pthread_condattr_getclock(attributes, &clock) == 0 &&
                clock == CLOCK_MONOTONIC,
            "condition did not receive monotonic attributes");
    if (activeScript->failure == InitFailure::Condition)
      return EAGAIN;
  }
  const int status = __real_pthread_cond_init(condition, attributes);
  if (activeScript && status == 0)
    activeScript->condition = condition;
  return status;
}
int __wrap_pthread_cond_destroy(pthread_cond_t *condition) noexcept {
  if (activeScript)
    require(condition == activeScript->condition,
            "destroyed the wrong condition");
  const int status = __real_pthread_cond_destroy(condition);
  if (activeScript) {
    ++activeScript->conditionDestroys;
    require(status == 0, "condition cleanup failed");
    activeScript->condition = nullptr;
  }
  return status;
}
int __wrap_pthread_cond_timedwait(pthread_cond_t *condition,
                                  pthread_mutex_t *mutex,
                                  const timespec *limit) {
  if (!activeScript || activeScript->sleep)
    return __real_pthread_cond_timedwait(condition, mutex, limit);
  auto &script = *activeScript;
  require(condition == script.condition && mutex == script.mutex,
          "timed wait did not use the initialized monotonic objects");
  require(script.waits < script.statuses.size(),
          "parking retried a completed/error wait");
  script.limits[script.waits] = *limit;
  const int status = script.statuses[script.waits++];
  if (status == 0) {
    script.now.tv_nsec += 100000000;
    script.now.tv_sec += script.now.tv_nsec / 1000000000;
    script.now.tv_nsec %= 1000000000;
  } else if (status == ETIMEDOUT && (limit->tv_sec > script.now.tv_sec ||
                                     (limit->tv_sec == script.now.tv_sec &&
                                      limit->tv_nsec > script.now.tv_nsec))) {
    script.now = *limit;
  }
  return status;
}
}
#endif

int main(int argc, char **argv) {
  if (argc == 2 && std::strcmp(argv[1], "--rwlock-downgrade") == 0) {
#ifdef __linux__
    rwlockInitializationCases();
#endif
    rwlockDowngradeCases();
    return 0;
  }
#ifdef __linux__
  if (argc == 3 && std::strcmp(argv[1], "--fd-probe") == 0) {
    const int fd = std::atoi(argv[2]);
    return fcntl(fd, F_GETFD) < 0 && errno == EBADF ? 0 : 1;
  }
  if (argc == 3 && std::strcmp(argv[1], "--stdio-probe") == 0)
    return stdioProbe(argv[2]);
  if (argc == 2 && std::strcmp(argv[1], "--spawn-sources") == 0) {
    require(isolatedStdio(0), "borrowed spawn descriptor ownership failed");
    return 0;
  }
  // TSan diagnoses wrong-owner unlocks even when pthread rejects them.
  if (argc == 2 && std::strcmp(argv[1], "--recursive-contention") == 0) {
    reentrantMutexCases(false);
    return 0;
  }

  descriptorCases();
  for (int mask = 0; mask < 8; ++mask)
    require(isolatedStdio(mask), "spawn lost a stream or child failure report");
  sleepCases();
  {
    Script script;
    script.failure = InitFailure::Mutex;
    ScriptScope scope(script);
    require(mettle_rt_reentrant_mutex_new() == nullptr &&
                script.mutexInits == 1 && script.mutexDestroys == 0,
            "recursive mutex initialization failure published invalid state");
  }
  conditionCases();
  rwlockInitializationCases();
  parkingCases();
  acceptCases();
#else
  (void)argc;
  (void)argv;
#endif
  reentrantMutexCases();
  rwlockDowngradeCases();
  filesystemTimeCases();
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
  while (shared.waiting.load(std::memory_order_acquire) != 3)
    std::this_thread::yield();
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
  require(setitimer(ITIMER_REAL, &previousTimer, nullptr) == 0,
          "restore timer");
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
