#include "sys.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __APPLE__
#include <crt_externs.h>
#include <sys/event.h>
#else
extern char **environ;
#endif

namespace {
constexpr std::int32_t openRead = 1;
constexpr std::int32_t openWrite = 2;
constexpr std::int32_t openAppend = 4;
constexpr std::int32_t openTruncate = 8;
constexpr std::int32_t openCreate = 16;
constexpr std::int32_t openCreateNew = 32;

#ifdef __APPLE__
char **&environment() { return *_NSGetEnviron(); }
#else
char **&environment() { return environ; }
#endif

struct Arguments {
  int count = 0;
  char **values = nullptr;
};

#ifdef __APPLE__
Arguments arguments() { return {*_NSGetArgc(), *_NSGetArgv()}; }
#else
// glibc hands the arguments to initializers that run before `main`.
Arguments captured;
[[gnu::constructor]] void captureArguments(int count, char **values, char **) {
  captured = {count, values};
}
Arguments arguments() { return captured; }
#endif

// Resumes a call that a signal interrupted.
template <typename Call> auto retry(Call call) {
  decltype(call()) result;
  do
    result = call();
  while (result < 0 && errno == EINTR);
  return result;
}

void setCloseOnExec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags >= 0)
    fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

bool socketAddress(std::int32_t family, const std::uint8_t *address,
                   std::size_t addressSize, std::uint16_t port,
                   std::uint32_t flowinfo, std::uint32_t scopeId,
                   sockaddr_storage &storage, socklen_t &size) {
  std::memset(&storage, 0, sizeof storage);
  if (!address) {
    errno = EINVAL;
    return false;
  }
  if (family == 4 && addressSize == 4) {
    auto *value = reinterpret_cast<sockaddr_in *>(&storage);
    value->sin_family = AF_INET;
    value->sin_port = htons(port);
    std::memcpy(&value->sin_addr, address, 4);
#ifdef __APPLE__
    value->sin_len = sizeof *value;
#endif
    size = sizeof *value;
    return true;
  }
  if (family == 6 && addressSize == 16) {
    auto *value = reinterpret_cast<sockaddr_in6 *>(&storage);
    value->sin6_family = AF_INET6;
    value->sin6_port = htons(port);
    value->sin6_flowinfo = htonl(flowinfo);
    value->sin6_scope_id = scopeId;
    std::memcpy(&value->sin6_addr, address, 16);
#ifdef __APPLE__
    value->sin6_len = sizeof *value;
#endif
    size = sizeof *value;
    return true;
  }
  errno = family == 4 || family == 6 ? EINVAL : EAFNOSUPPORT;
  return false;
}

bool readSocketAddress(const sockaddr *raw, socklen_t size,
                       std::int32_t *family, std::uint8_t *address,
                       std::size_t addressCapacity, std::uint16_t *port,
                       std::uint32_t *flowinfo, std::uint32_t *scopeId) {
  if (!raw || !family || !address || !port || !flowinfo || !scopeId) {
    errno = EINVAL;
    return false;
  }
  if (raw->sa_family == AF_INET) {
    if (size < sizeof(sockaddr_in) || addressCapacity < 4) {
      errno = EINVAL;
      return false;
    }
    const auto *value = reinterpret_cast<const sockaddr_in *>(raw);
    *family = 4;
    std::memcpy(address, &value->sin_addr, 4);
    *port = ntohs(value->sin_port);
    *flowinfo = 0;
    *scopeId = 0;
    return true;
  }
  if (raw->sa_family == AF_INET6) {
    if (size < sizeof(sockaddr_in6) || addressCapacity < 16) {
      errno = EINVAL;
      return false;
    }
    const auto *value = reinterpret_cast<const sockaddr_in6 *>(raw);
    *family = 6;
    std::memcpy(address, &value->sin6_addr, 16);
    *port = ntohs(value->sin6_port);
    *flowinfo = ntohl(value->sin6_flowinfo);
    *scopeId = value->sin6_scope_id;
    return true;
  }
  errno = EAFNOSUPPORT;
  return false;
}

struct ResolvedAddress {
  sockaddr_storage value{};
  socklen_t size = 0;
};

struct ResolveHandle {
  std::vector<ResolvedAddress> addresses;
};

std::int32_t timedConnect(std::int32_t fd, const sockaddr *address,
                          socklen_t size, std::uint64_t timeoutMicros) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0)
    return -1;
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
    return -1;

  int result = connect(fd, address, size);
  int failure = errno;
  if (result != 0 &&
      (failure == EINPROGRESS || failure == EWOULDBLOCK || failure == EINTR)) {
    using Clock = std::chrono::steady_clock;
    using Micros = std::chrono::microseconds;
    const auto now = Clock::now();
    const auto maxMicros =
        std::chrono::duration_cast<Micros>(Clock::time_point::max() - now)
            .count();
    const auto boundedMicros =
        std::min(timeoutMicros, static_cast<std::uint64_t>(maxMicros));
    const auto deadline = now + Micros(static_cast<Micros::rep>(boundedMicros));

    while (true) {
      const auto current = Clock::now();
      if (current >= deadline) {
        failure = ETIMEDOUT;
        result = -1;
        break;
      }
      const auto remaining =
          std::chrono::duration_cast<Micros>(deadline - current);
      auto millis = remaining.count() / 1000;
      if (remaining.count() % 1000 != 0)
        ++millis;
      const int waitMillis =
          static_cast<int>(std::min<std::int64_t>(millis, INT_MAX));
      pollfd request{fd, POLLOUT, 0};
      const int ready = poll(&request, 1, waitMillis);
      if (ready < 0 && errno == EINTR)
        continue;
      if (ready < 0) {
        failure = errno;
        result = -1;
        break;
      }
      if (ready == 0)
        continue;

      int socketError = 0;
      socklen_t errorSize = sizeof socketError;
      if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorSize) < 0) {
        failure = errno;
        result = -1;
      } else if (socketError != 0) {
        failure = socketError;
        result = -1;
      } else {
        result = 0;
      }
      break;
    }
  } else if (result != 0) {
    failure = errno;
  }

  const int restore = fcntl(fd, F_SETFL, flags);
  if (restore < 0 && result == 0) {
    result = -1;
    failure = errno;
  }
  if (result < 0)
    errno = failure;
  return result;
}

std::int32_t resolverErrno(int result) {
  if (result == EAI_MEMORY)
    return ENOMEM;
#ifdef EAI_SYSTEM
  if (result == EAI_SYSTEM)
    return errno;
#endif
  if (result == EAI_NONAME || result == EAI_AGAIN)
    return EHOSTUNREACH;
  return EINVAL;
}

void setResolverError(int result) { errno = resolverErrno(result); }

// Closes both ends of a pipe on scope exit unless released.
struct Pipe {
  int ends[2] = {-1, -1};
  bool open() {
    if (pipe(ends) != 0)
      return false;
    setCloseOnExec(ends[0]);
    setCloseOnExec(ends[1]);
    return true;
  }
  void close() {
    for (int &end : ends)
      if (end >= 0) {
        ::close(end);
        end = -1;
      }
  }
  Pipe() = default;
  Pipe(const Pipe &) = delete;
  Pipe &operator=(const Pipe &) = delete;
  ~Pipe() { close(); }
};

[[noreturn]] void childFailure(int report) {
  int code = errno;
  ssize_t ignored = write(report, &code, sizeof code);
  (void)ignored;
  _exit(127);
}

// Runs in the forked child: only async-signal-safe calls.
[[noreturn]] void runChild(const char *program, const char *const *argv,
                           const char *const *envp, const char *cwd,
                           const std::int32_t *modes, const Pipe *standard,
                           int report) {
  for (int i = 0; i < 3; ++i) {
    int source = -1;
    if (modes[i] == 1)
      source = i == 0 ? standard[i].ends[0] : standard[i].ends[1];
    else if (modes[i] == 2)
      source = open("/dev/null", i == 0 ? O_RDONLY : O_WRONLY);
    if (modes[i] != 0 && (source < 0 || dup2(source, i) < 0))
      childFailure(report);
  }
  if (cwd && chdir(cwd) != 0)
    childFailure(report);
  if (envp)
    environment() = const_cast<char **>(envp);
  execvp(program, const_cast<char *const *>(argv));
  childFailure(report);
}

using ReactorCallback = void (*)(void *);

struct ReactorRegistration {
  int fd = -1;
  bool write = false;
  bool timer = false;
  void *data = nullptr;
  ReactorCallback wake = nullptr;
  ReactorCallback release = nullptr;
  std::chrono::steady_clock::time_point deadline;
};

struct ReactorState {
  std::mutex mutex;
  int fd = -1;
  int wakeRead = -1;
  int wakeWrite = -1;
  std::uint64_t nextToken = 1;
  std::unordered_map<std::uint64_t, ReactorRegistration> registrations;
  std::map<std::pair<int, bool>, std::vector<std::uint64_t>> descriptors;
};

bool initializeReactor(ReactorState &state) {
  if (state.fd >= 0)
    return true;
#ifdef __APPLE__
  state.fd = kqueue();
  if (state.fd < 0)
    return false;
  setCloseOnExec(state.fd);
  struct kevent control;
  EV_SET(&control, 1, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, nullptr);
  if (kevent(state.fd, &control, 1, nullptr, 0, nullptr) != 0) {
    const int failure = errno;
    close(state.fd);
    state.fd = -1;
    errno = failure;
    return false;
  }
#else
  int pipeFds[2];
  if (pipe(pipeFds) != 0)
    return false;
  state.wakeRead = pipeFds[0];
  state.wakeWrite = pipeFds[1];
  for (int fd : pipeFds) {
    const int descriptorFlags = fcntl(fd, F_GETFD);
    const int statusFlags = fcntl(fd, F_GETFL);
    if (descriptorFlags < 0 || statusFlags < 0 ||
        fcntl(fd, F_SETFD, descriptorFlags | FD_CLOEXEC) != 0 ||
        fcntl(fd, F_SETFL, statusFlags | O_NONBLOCK) != 0) {
      const int failure = errno;
      close(state.wakeRead);
      close(state.wakeWrite);
      state.wakeRead = -1;
      state.wakeWrite = -1;
      errno = failure;
      return false;
    }
  }
  state.fd = state.wakeRead;
#endif
  return true;
}

void triggerReactor(ReactorState &state) {
#ifdef __APPLE__
  struct kevent event;
  EV_SET(&event, 1, EVFILT_USER, 0, NOTE_TRIGGER, 0, nullptr);
  if (retry([&] { return kevent(state.fd, &event, 1, nullptr, 0, nullptr); }) !=
      0)
    std::abort();
#else
  const std::uint8_t byte = 1;
  const auto result =
      retry([&] { return write(state.wakeWrite, &byte, sizeof byte); });
  if (result < 0 && errno != EAGAIN)
    std::abort();
#endif
}

std::chrono::nanoseconds timerInterval(std::uint64_t seconds,
                                       std::uint32_t nanos) {
  constexpr auto maxNanos =
      static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
  if (seconds > maxNanos / 1000000000ULL)
    return std::chrono::nanoseconds::max();
  const auto total = seconds * 1000000000ULL + nanos;
  return std::chrono::nanoseconds(
      static_cast<std::int64_t>(std::min(total, maxNanos)));
}

std::uint64_t addReactorRegistration(ReactorState &state,
                                     ReactorRegistration registration,
                                     std::uint64_t seconds,
                                     std::uint32_t nanos) {
  std::lock_guard lock(state.mutex);
  if (!initializeReactor(state))
    return 0;
  const std::uint64_t token = state.nextToken;
  if (token == 0) {
    errno = EOVERFLOW;
    return 0;
  }
  ++state.nextToken;
  if (registration.timer) {
    const auto interval = timerInterval(seconds, nanos);
    const auto now = std::chrono::steady_clock::now();
    const auto maxDelay = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::time_point::max() - now);
    registration.deadline =
        now + std::chrono::duration_cast<std::chrono::steady_clock::duration>(
                  std::min(interval, maxDelay));
  }
#ifdef __APPLE__
  struct kevent change;
  if (registration.timer) {
    const auto interval =
        std::max<std::int64_t>(1, timerInterval(seconds, nanos).count());
    EV_SET(&change, static_cast<std::uintptr_t>(token), EVFILT_TIMER,
           EV_ADD | EV_ONESHOT, NOTE_NSECONDS, interval,
           reinterpret_cast<void *>(static_cast<std::uintptr_t>(token)));
  }
#endif
  bool addDescriptorEvent = false;
  const auto descriptorKey =
      std::make_pair(registration.fd, registration.write);
  try {
    state.registrations.emplace(token, registration);
    if (!registration.timer) {
      auto [descriptor, inserted] =
          state.descriptors.try_emplace(descriptorKey);
      descriptor->second.push_back(token);
      addDescriptorEvent = inserted;
    }
  } catch (...) {
    state.registrations.erase(token);
    auto descriptor = state.descriptors.find(descriptorKey);
    if (descriptor != state.descriptors.end() && descriptor->second.empty())
      state.descriptors.erase(descriptor);
    errno = ENOMEM;
    return 0;
  }
#ifndef __APPLE__
  (void)addDescriptorEvent;
#endif
#ifdef __APPLE__
  if (!registration.timer && addDescriptorEvent) {
    EV_SET(&change, registration.fd,
           registration.write ? EVFILT_WRITE : EVFILT_READ, EV_ADD | EV_ONESHOT,
           0, 0, nullptr);
  }
  if ((registration.timer || addDescriptorEvent) &&
      kevent(state.fd, &change, 1, nullptr, 0, nullptr) != 0) {
    const int failure = errno;
    state.registrations.erase(token);
    if (!registration.timer)
      state.descriptors.erase(descriptorKey);
    errno = failure;
    return 0;
  }
#endif
  triggerReactor(state);
  return token;
}

void eraseReactorRegistration(ReactorState &state, std::uint64_t token,
                              bool releaseWaker) {
  ReactorRegistration registration;
  {
    std::lock_guard lock(state.mutex);
    auto entry = state.registrations.find(token);
    if (entry == state.registrations.end())
      return;
    registration = entry->second;
    state.registrations.erase(entry);
    bool removeDescriptorEvent = false;
    if (!registration.timer) {
      auto descriptor =
          state.descriptors.find({registration.fd, registration.write});
      if (descriptor != state.descriptors.end()) {
        auto &tokens = descriptor->second;
        tokens.erase(std::remove(tokens.begin(), tokens.end(), token),
                     tokens.end());
        if (tokens.empty()) {
          state.descriptors.erase(descriptor);
          removeDescriptorEvent = true;
        }
      }
    }
#ifndef __APPLE__
    (void)removeDescriptorEvent;
#endif
#ifdef __APPLE__
    struct kevent change;
    if (registration.timer || removeDescriptorEvent) {
      EV_SET(&change,
             registration.timer ? static_cast<std::uintptr_t>(token)
                                : static_cast<std::uintptr_t>(registration.fd),
             registration.timer   ? EVFILT_TIMER
             : registration.write ? EVFILT_WRITE
                                  : EVFILT_READ,
             EV_DELETE, 0, 0, nullptr);
      kevent(state.fd, &change, 1, nullptr, 0, nullptr);
    }
#endif
    triggerReactor(state);
  }
  if (releaseWaker && registration.release)
    registration.release(registration.data);
}
} // namespace

extern "C" std::int32_t mettle_rt_errno() { return errno; }
extern "C" std::int32_t mettle_rt_errno_kind(std::int32_t code) {
  switch (code) {
  case ENOENT:
    return 0;
  case EACCES:
  case EPERM:
    return 1;
  case ECONNREFUSED:
    return 2;
  case ECONNRESET:
    return 3;
  case ECONNABORTED:
    return 4;
  case ENOTCONN:
    return 5;
  case EADDRINUSE:
    return 6;
  case EADDRNOTAVAIL:
    return 7;
  case EPIPE:
    return 8;
  case EEXIST:
    return 9;
  case EAGAIN:
    return 10;
  case EINVAL:
    return 11;
  case ETIMEDOUT:
    return 12;
  case EINTR:
    return 13;
  case ENOMEM:
    return 14;
  case EISDIR:
    return 15;
  case ENOTDIR:
    return 16;
  case ENOTEMPTY:
    return 17;
  default:
    return 18;
  }
}

extern "C" void mettle_rt_set_errno(std::int32_t value) { errno = value; }

extern "C" std::int32_t mettle_rt_open(const char *path, std::int32_t flags,
                                       std::uint32_t mode) {
  int native = O_CLOEXEC;
  bool read = (flags & openRead) != 0;
  bool write = (flags & (openWrite | openAppend)) != 0;
  native |= read && write ? O_RDWR : write ? O_WRONLY : O_RDONLY;
  if (flags & openAppend)
    native |= O_APPEND;
  if (flags & openTruncate)
    native |= O_TRUNC;
  if (flags & openCreateNew)
    native |= O_CREAT | O_EXCL;
  else if (flags & openCreate)
    native |= O_CREAT;
  return retry([&] { return open(path, native, static_cast<mode_t>(mode)); });
}

extern "C" std::int32_t mettle_rt_stat(const char *path, std::int32_t fd,
                                       std::int32_t follow, std::int64_t *out) {
  struct stat info;
  int result = fd >= 0       ? fstat(fd, &info)
               : follow != 0 ? stat(path, &info)
                             : lstat(path, &info);
  if (result != 0)
    return -1;
  out[0] = static_cast<std::int64_t>(info.st_size);
  out[1] = S_ISREG(info.st_mode)   ? 0
           : S_ISDIR(info.st_mode) ? 1
           : S_ISLNK(info.st_mode) ? 2
                                   : 3;
  out[2] = static_cast<std::int64_t>(info.st_mode & 07777);
#ifdef __APPLE__
  out[3] = info.st_mtimespec.tv_sec;
  out[4] = info.st_mtimespec.tv_nsec;
#else
  out[3] = info.st_mtim.tv_sec;
  out[4] = info.st_mtim.tv_nsec;
#endif
  return 0;
}

extern "C" const char *mettle_rt_readdir(void *directory) {
  errno = 0;
  while (dirent *entry = readdir(static_cast<DIR *>(directory))) {
    const char *name = entry->d_name;
    if (std::strcmp(name, ".") != 0 && std::strcmp(name, "..") != 0)
      return name;
  }
  return nullptr;
}

extern "C" std::int32_t mettle_rt_argc() { return arguments().count; }

extern "C" const char *mettle_rt_argv(std::int32_t index) {
  auto args = arguments();
  return index >= 0 && index < args.count ? args.values[index] : nullptr;
}

extern "C" const char *mettle_rt_environ_at(std::int32_t index) {
  char **values = environment();
  if (!values || index < 0)
    return nullptr;
  for (std::int32_t i = 0; values[i]; ++i)
    if (i == index)
      return values[i];
  return nullptr;
}

extern "C" std::int32_t
mettle_rt_spawn(const char *program, const char *const *argv,
                const char *const *envp, const char *cwd,
                const std::int32_t *modes, std::int32_t *fds) {
  Pipe standard[3];
  Pipe report;
  for (int i = 0; i < 3; ++i) {
    fds[i] = -1;
    if (modes[i] == 1 && !standard[i].open())
      return -1;
  }
  if (!report.open())
    return -1;
  pid_t child = fork();
  if (child < 0)
    return -1;
  if (child == 0)
    runChild(program, argv, envp, cwd, modes, standard, report.ends[1]);
  ::close(report.ends[1]);
  report.ends[1] = -1;
  int code = 0;
  ssize_t got = retry([&] { return read(report.ends[0], &code, sizeof code); });
  if (got == static_cast<ssize_t>(sizeof code)) {
    int status = 0;
    retry([&] { return waitpid(child, &status, 0); });
    errno = code;
    return -1;
  }
  for (int i = 0; i < 3; ++i)
    if (modes[i] == 1) {
      int &keep = i == 0 ? standard[i].ends[1] : standard[i].ends[0];
      fds[i] = keep;
      keep = -1;
    }
  return child;
}

extern "C" std::int32_t mettle_rt_poll(std::int32_t fd, std::int32_t write,
                                       std::int32_t timeoutMillis) {
  pollfd request{fd, static_cast<short>(write ? POLLOUT : POLLIN), 0};
  int result = retry([&] { return poll(&request, 1, timeoutMillis); });
  return result < 0 ? -1 : result > 0 ? 1 : 0;
}

extern "C" std::int32_t mettle_rt_poll_pair(std::int32_t first,
                                            std::int32_t second) {
  pollfd requests[2] = {{first, POLLIN, 0}, {second, POLLIN, 0}};
  int result = retry([&] { return poll(requests, 2, -1); });
  if (result < 0)
    return -1;
  return (requests[0].revents != 0 && first >= 0 ? 1 : 0) |
         (requests[1].revents != 0 && second >= 0 ? 2 : 0);
}

extern "C" std::int32_t mettle_rt_sock_new(std::int32_t kind,
                                           std::int32_t family) {
  const int nativeFamily = family == 4   ? AF_INET
                           : family == 6 ? AF_INET6
                                         : AF_UNSPEC;
  if (nativeFamily == AF_UNSPEC) {
    errno = EAFNOSUPPORT;
    return -1;
  }
  int fd = socket(nativeFamily, kind == 0 ? SOCK_STREAM : SOCK_DGRAM, 0);
  if (fd < 0)
    return -1;
  setCloseOnExec(fd);
#ifdef SO_NOSIGPIPE
  int on = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
  return fd;
}

extern "C" std::int32_t
mettle_rt_sock_bind(std::int32_t fd, std::int32_t family,
                    const std::uint8_t *address, std::size_t addressSize,
                    std::uint16_t port, std::uint32_t flowinfo,
                    std::uint32_t scopeId) {
  int on = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
  sockaddr_storage value;
  socklen_t size = 0;
  if (!socketAddress(family, address, addressSize, port, flowinfo, scopeId,
                     value, size))
    return -1;
  return bind(fd, reinterpret_cast<sockaddr *>(&value), size);
}

extern "C" std::int32_t
mettle_rt_sock_connect(std::int32_t fd, std::int32_t family,
                       const std::uint8_t *address, std::size_t addressSize,
                       std::uint16_t port, std::uint32_t flowinfo,
                       std::uint32_t scopeId) {
  sockaddr_storage value;
  socklen_t size = 0;
  if (!socketAddress(family, address, addressSize, port, flowinfo, scopeId,
                     value, size))
    return -1;
  return retry(
      [&] { return connect(fd, reinterpret_cast<sockaddr *>(&value), size); });
}

extern "C" std::int32_t mettle_rt_sock_connect_timeout(
    std::int32_t fd, std::int32_t family, const std::uint8_t *address,
    std::size_t addressSize, std::uint16_t port, std::uint32_t flowinfo,
    std::uint32_t scopeId, std::uint64_t timeoutMicros) {
  sockaddr_storage value;
  socklen_t size = 0;
  if (!socketAddress(family, address, addressSize, port, flowinfo, scopeId,
                     value, size))
    return -1;
  return timedConnect(fd, reinterpret_cast<sockaddr *>(&value), size,
                      timeoutMicros);
}

extern "C" std::int32_t
mettle_rt_sock_accept(std::int32_t fd, std::int32_t timeoutMillis,
                      std::int32_t *family, std::uint8_t *address,
                      std::size_t addressCapacity, std::uint16_t *port,
                      std::uint32_t *flowinfo, std::uint32_t *scopeId) {
  if (timeoutMillis >= 0) {
    std::int32_t ready = mettle_rt_poll(fd, 0, timeoutMillis);
    if (ready < 0)
      return -1;
    if (ready == 0) {
      errno = EAGAIN;
      return -1;
    }
  }
  sockaddr_storage value;
  socklen_t size = sizeof value;
  int accepted = retry(
      [&] { return accept(fd, reinterpret_cast<sockaddr *>(&value), &size); });
  if (accepted < 0)
    return -1;
  setCloseOnExec(accepted);
#ifdef SO_NOSIGPIPE
  int on = 1;
  setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
  if (!readSocketAddress(reinterpret_cast<sockaddr *>(&value), size, family,
                         address, addressCapacity, port, flowinfo, scopeId)) {
    const int failure = errno;
    close(accepted);
    errno = failure;
    return -1;
  }
  return accepted;
}

extern "C" std::int32_t
mettle_rt_sock_name(std::int32_t fd, std::int32_t peer, std::int32_t *family,
                    std::uint8_t *address, std::size_t addressCapacity,
                    std::uint16_t *port, std::uint32_t *flowinfo,
                    std::uint32_t *scopeId) {
  sockaddr_storage value;
  socklen_t size = sizeof value;
  auto *raw = reinterpret_cast<sockaddr *>(&value);
  if ((peer ? getpeername(fd, raw, &size) : getsockname(fd, raw, &size)) != 0)
    return -1;
  return readSocketAddress(raw, size, family, address, addressCapacity, port,
                           flowinfo, scopeId)
             ? 0
             : -1;
}

extern "C" std::int64_t mettle_rt_sock_send(std::int32_t fd,
                                            const std::uint8_t *data,
                                            std::size_t size) {
#ifdef MSG_NOSIGNAL
  constexpr int flags = MSG_NOSIGNAL;
#else
  constexpr int flags = 0;
#endif
  return retry([&] { return send(fd, data, size, flags); });
}

extern "C" std::int64_t mettle_rt_sock_sendto(
    std::int32_t fd, const std::uint8_t *data, std::size_t size,
    std::int32_t family, const std::uint8_t *address, std::size_t addressSize,
    std::uint16_t port, std::uint32_t flowinfo, std::uint32_t scopeId) {
  sockaddr_storage value;
  socklen_t addressLength = 0;
  if (!socketAddress(family, address, addressSize, port, flowinfo, scopeId,
                     value, addressLength))
    return -1;
  return retry([&] {
    return sendto(fd, data, size, 0, reinterpret_cast<sockaddr *>(&value),
                  addressLength);
  });
}

extern "C" std::int64_t
mettle_rt_sock_recvfrom(std::int32_t fd, std::uint8_t *data, std::size_t size,
                        std::int32_t *family, std::uint8_t *address,
                        std::size_t addressCapacity, std::uint16_t *port,
                        std::uint32_t *flowinfo, std::uint32_t *scopeId) {
  sockaddr_storage value;
  std::memset(&value, 0, sizeof value);
  socklen_t length = sizeof value;
  auto received = retry([&] {
    return recvfrom(fd, data, size, 0, reinterpret_cast<sockaddr *>(&value),
                    &length);
  });
  if (received >= 0 &&
      !readSocketAddress(reinterpret_cast<sockaddr *>(&value), length, family,
                         address, addressCapacity, port, flowinfo, scopeId))
    return -1;
  return received;
}

extern "C" std::int32_t mettle_rt_sock_timeout(std::int32_t fd,
                                               std::int32_t send,
                                               std::uint64_t micros) {
  const auto seconds = micros / 1000000;
  if (seconds >
      static_cast<std::uint64_t>(std::numeric_limits<time_t>::max())) {
    errno = EINVAL;
    return -1;
  }

  timeval value;
  value.tv_sec = static_cast<time_t>(seconds);
  value.tv_usec = static_cast<suseconds_t>(micros % 1000000);
  return setsockopt(fd, SOL_SOCKET, send ? SO_SNDTIMEO : SO_RCVTIMEO, &value,
                    sizeof value);
}

extern "C" std::int32_t mettle_rt_sock_set_nodelay(std::int32_t fd,
                                                    std::int32_t enabled) {
  const int value = enabled != 0;
  return retry([&] {
    return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &value, sizeof(value));
  });
}

extern "C" std::int32_t mettle_rt_sock_get_nodelay(std::int32_t fd,
                                                    std::int32_t *enabled) {
  if (!enabled) {
    errno = EINVAL;
    return -1;
  }
  int value = 0;
  socklen_t size = sizeof(value);
  if (retry([&] {
        return getsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &value, &size);
      }) != 0)
    return -1;
  *enabled = value != 0;
  return 0;
}

extern "C" std::int32_t mettle_rt_sock_error(std::int32_t fd,
                                              std::int32_t *error) {
  if (!error) {
    errno = EINVAL;
    return -1;
  }
  socklen_t size = sizeof(*error);
  return retry([&] {
    return getsockopt(fd, SOL_SOCKET, SO_ERROR, error, &size);
  });
}

extern "C" std::uint8_t *mettle_rt_resolve(const std::uint8_t *host,
                                           std::size_t hostSize,
                                           std::uint16_t port,
                                           std::size_t *count) {
  if (!count || (!host && hostSize != 0) ||
      (hostSize != 0 && std::memchr(host, 0, hostSize) != nullptr)) {
    errno = EINVAL;
    return nullptr;
  }
  *count = 0;
  try {
    std::string name;
    if (hostSize != 0)
      name.assign(reinterpret_cast<const char *>(host), hostSize);
    const std::string service = std::to_string(port);
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo *rawResults = nullptr;
    const int status =
        getaddrinfo(name.c_str(), service.c_str(), &hints, &rawResults);
    std::unique_ptr<addrinfo, decltype(&freeaddrinfo)> results(rawResults,
                                                               freeaddrinfo);
    if (status != 0) {
      setResolverError(status);
      return nullptr;
    }

    std::unique_ptr<ResolveHandle> handle(new (std::nothrow) ResolveHandle);
    if (!handle) {
      errno = ENOMEM;
      return nullptr;
    }
    for (const addrinfo *entry = results.get(); entry; entry = entry->ai_next) {
      if ((entry->ai_family != AF_INET && entry->ai_family != AF_INET6) ||
          entry->ai_addrlen > sizeof(sockaddr_storage))
        continue;
      ResolvedAddress address;
      address.size = static_cast<socklen_t>(entry->ai_addrlen);
      std::memcpy(&address.value, entry->ai_addr, address.size);
      handle->addresses.push_back(address);
    }
    *count = handle->addresses.size();
    return reinterpret_cast<std::uint8_t *>(handle.release());
  } catch (const std::bad_alloc &) {
    errno = ENOMEM;
    return nullptr;
  } catch (...) {
    errno = EINVAL;
    return nullptr;
  }
}

extern "C" std::int32_t
mettle_rt_resolve_get(std::uint8_t *rawHandle, std::size_t index,
                      std::int32_t *family, std::uint8_t *address,
                      std::size_t addressCapacity, std::uint16_t *port,
                      std::uint32_t *flowinfo, std::uint32_t *scopeId) {
  if (!rawHandle) {
    errno = EINVAL;
    return -1;
  }
  const auto *handle = reinterpret_cast<const ResolveHandle *>(rawHandle);
  if (index >= handle->addresses.size()) {
    errno = EINVAL;
    return -1;
  }
  const auto &entry = handle->addresses[index];
  return readSocketAddress(reinterpret_cast<const sockaddr *>(&entry.value),
                           entry.size, family, address, addressCapacity, port,
                           flowinfo, scopeId)
             ? 0
             : -1;
}

extern "C" void mettle_rt_resolve_free(std::uint8_t *rawHandle) {
  delete reinterpret_cast<ResolveHandle *>(rawHandle);
}

extern "C" std::int32_t mettle_rt_clock(std::int32_t clock, std::int64_t *out) {
  timespec value;
  if (clock_gettime(clock == 0 ? CLOCK_MONOTONIC : CLOCK_REALTIME, &value) != 0)
    return -1;
  out[0] = value.tv_sec;
  out[1] = value.tv_nsec;
  return 0;
}

extern "C" void mettle_rt_sleep(std::uint64_t seconds, std::uint32_t nanos) {
  timespec request{static_cast<time_t>(seconds), static_cast<long>(nanos)};
  timespec remaining;
  while (nanosleep(&request, &remaining) != 0 && errno == EINTR)
    request = remaining;
}

extern "C" void *mettle_rt_reactor_new() {
  auto state = std::unique_ptr<ReactorState>(new (std::nothrow) ReactorState);
  if (!state)
    return nullptr;
  {
    std::lock_guard lock(state->mutex);
    if (!initializeReactor(*state))
      return nullptr;
  }
  return state.release();
}

extern "C" void mettle_rt_reactor_close(void *rawReactor) {
  if (!rawReactor)
    return;
  auto *state = static_cast<ReactorState *>(rawReactor);
  for (;;) {
    ReactorRegistration registration;
    {
      std::lock_guard lock(state->mutex);
      if (state->registrations.empty())
        break;
      auto entry = state->registrations.begin();
      registration = entry->second;
      const auto token = entry->first;
      state->registrations.erase(entry);
      if (!registration.timer) {
        auto descriptor =
            state->descriptors.find({registration.fd, registration.write});
        if (descriptor != state->descriptors.end()) {
          auto &tokens = descriptor->second;
          tokens.erase(std::remove(tokens.begin(), tokens.end(), token),
                       tokens.end());
          if (tokens.empty())
            state->descriptors.erase(descriptor);
        }
      }
    }
    if (registration.release)
      registration.release(registration.data);
  }
  if (state->fd >= 0)
    close(state->fd);
#ifndef __APPLE__
  if (state->wakeWrite >= 0)
    close(state->wakeWrite);
#endif
  delete state;
}

extern "C" std::uint64_t mettle_rt_reactor_watch(void *rawReactor,
                                                 std::int32_t fd,
                                                 std::int32_t write, void *data,
                                                 void (*wake)(void *),
                                                 void (*release)(void *)) {
  if (!rawReactor || fd < 0 || !wake || !release) {
    errno = EINVAL;
    return 0;
  }
  ReactorRegistration registration;
  registration.fd = fd;
  registration.write = write != 0;
  registration.data = data;
  registration.wake = wake;
  registration.release = release;
  return addReactorRegistration(*static_cast<ReactorState *>(rawReactor),
                                registration, 0, 0);
}

extern "C" std::uint64_t
mettle_rt_reactor_timer(void *rawReactor, std::uint64_t seconds,
                        std::uint32_t nanos, void *data, void (*wake)(void *),
                        void (*release)(void *)) {
  if (!rawReactor || !wake || !release || nanos >= 1000000000U) {
    errno = EINVAL;
    return 0;
  }
  ReactorRegistration registration;
  registration.timer = true;
  registration.data = data;
  registration.wake = wake;
  registration.release = release;
  return addReactorRegistration(*static_cast<ReactorState *>(rawReactor),
                                registration, seconds, nanos);
}

extern "C" void mettle_rt_reactor_cancel(void *rawReactor,
                                         std::uint64_t token) {
  if (!rawReactor)
    return;
  if (token != 0)
    eraseReactorRegistration(*static_cast<ReactorState *>(rawReactor), token,
                             true);
}

extern "C" void mettle_rt_reactor_wake(void *rawReactor) {
  if (!rawReactor)
    return;
  auto &state = *static_cast<ReactorState *>(rawReactor);
  std::lock_guard lock(state.mutex);
  if (initializeReactor(state))
    triggerReactor(state);
}

extern "C" std::int32_t mettle_rt_reactor_wait(void *rawReactor) {
  if (!rawReactor) {
    errno = EINVAL;
    return -1;
  }
  auto &state = *static_cast<ReactorState *>(rawReactor);
  {
    std::lock_guard lock(state.mutex);
    if (!initializeReactor(state))
      return -1;
  }
#ifdef __APPLE__
  for (;;) {
    struct kevent event;
    const int count = kevent(state.fd, nullptr, 0, &event, 1, nullptr);
    if (count < 0 && errno == EINTR)
      continue;
    if (count < 0)
      return -1;
    if (count == 0 || event.filter == EVFILT_USER)
      return 0;
    if (event.filter == EVFILT_TIMER) {
      const auto token = static_cast<std::uint64_t>(
          reinterpret_cast<std::uintptr_t>(event.udata));
      ReactorRegistration registration;
      {
        std::lock_guard lock(state.mutex);
        auto entry = state.registrations.find(token);
        if (entry == state.registrations.end())
          return 0;
        registration = entry->second;
        state.registrations.erase(entry);
      }
      if (registration.wake)
        registration.wake(registration.data);
      return 1;
    }

    const auto key = std::make_pair(static_cast<int>(event.ident),
                                    event.filter == EVFILT_WRITE);
    std::vector<std::uint64_t> tokens;
    {
      std::lock_guard lock(state.mutex);
      auto descriptor = state.descriptors.find(key);
      if (descriptor == state.descriptors.end())
        return 0;
      tokens = std::move(descriptor->second);
      state.descriptors.erase(descriptor);
    }
    bool woke = false;
    for (const auto token : tokens) {
      ReactorRegistration registration;
      bool found = false;
      {
        std::lock_guard lock(state.mutex);
        auto entry = state.registrations.find(token);
        if (entry != state.registrations.end()) {
          registration = entry->second;
          state.registrations.erase(entry);
          found = true;
        }
      }
      if (found && registration.wake) {
        registration.wake(registration.data);
        woke = true;
      }
    }
    return woke ? 1 : 0;
  }
#else
  try {
    for (;;) {
      std::vector<pollfd> requests;
      std::vector<std::uint64_t> tokens;
      int timeout = -1;
      {
        std::lock_guard lock(state.mutex);
        const auto now = std::chrono::steady_clock::now();
        requests.push_back({state.wakeRead, POLLIN, 0});
        tokens.push_back(0);
        for (const auto &[token, registration] : state.registrations) {
          if (registration.timer) {
            if (registration.deadline <= now) {
              timeout = 0;
            } else if (timeout != 0) {
              const auto remaining = registration.deadline - now;
              auto millis =
                  std::chrono::duration_cast<std::chrono::milliseconds>(
                      remaining);
              if (std::chrono::duration_cast<
                      std::chrono::steady_clock::duration>(millis) < remaining)
                millis += std::chrono::milliseconds(1);
              const int bounded = static_cast<int>(std::min<std::int64_t>(
                  static_cast<std::int64_t>(millis.count()),
                  std::numeric_limits<int>::max()));
              if (timeout < 0 || bounded < timeout)
                timeout = bounded;
            }
            continue;
          }
          requests.push_back(
              {registration.fd,
               static_cast<short>(registration.write ? POLLOUT : POLLIN), 0});
          tokens.push_back(token);
        }
      }
      const int result =
          poll(requests.data(), static_cast<nfds_t>(requests.size()), timeout);
      if (result < 0 && errno == EINTR)
        continue;
      if (result < 0)
        return -1;
      if (requests[0].revents != 0) {
        std::uint8_t bytes[64];
        while (read(state.wakeRead, bytes, sizeof bytes) > 0) {
        }
        return 0;
      }
      std::uint64_t token = 0;
      if (result > 0) {
        for (std::size_t i = 1; i < requests.size(); ++i)
          if (requests[i].revents != 0) {
            token = tokens[i];
            break;
          }
      }
      ReactorRegistration registration;
      bool found = false;
      {
        std::lock_guard lock(state.mutex);
        if (token == 0) {
          const auto now = std::chrono::steady_clock::now();
          for (const auto &[candidate, entry] : state.registrations)
            if (entry.timer && entry.deadline <= now) {
              token = candidate;
              break;
            }
        }
        auto entry = state.registrations.find(token);
        if (token != 0 && entry != state.registrations.end()) {
          registration = entry->second;
          state.registrations.erase(entry);
          if (!registration.timer) {
            auto descriptor =
                state.descriptors.find({registration.fd, registration.write});
            if (descriptor != state.descriptors.end()) {
              auto &registered = descriptor->second;
              registered.erase(
                  std::remove(registered.begin(), registered.end(), token),
                  registered.end());
              if (registered.empty())
                state.descriptors.erase(descriptor);
            }
          }
          found = true;
        }
      }
      if (!found)
        continue;
      if (registration.wake)
        registration.wake(registration.data);
      return 1;
    }
  } catch (...) {
    errno = ENOMEM;
    return -1;
  }
#endif
}

extern "C" std::int32_t mettle_rt_set_nonblocking(std::int32_t fd) {
  const int flags = retry([&] { return fcntl(fd, F_GETFL); });
  if (flags < 0)
    return -1;
  return retry([&] { return fcntl(fd, F_SETFL, flags | O_NONBLOCK); });
}

extern "C" std::int32_t mettle_rt_set_blocking(std::int32_t fd) {
  const int flags = retry([&] { return fcntl(fd, F_GETFL); });
  if (flags < 0)
    return -1;
  return retry([&] { return fcntl(fd, F_SETFL, flags & ~O_NONBLOCK); });
}

extern "C" std::int32_t
mettle_rt_sock_connect_start(std::int32_t fd, std::int32_t family,
                             const std::uint8_t *address,
                             std::size_t addressSize, std::uint16_t port,
                             std::uint32_t flowinfo, std::uint32_t scopeId) {
  sockaddr_storage value;
  socklen_t size = 0;
  if (!socketAddress(family, address, addressSize, port, flowinfo, scopeId,
                     value, size))
    return -1;
  const int result = retry(
      [&] { return connect(fd, reinterpret_cast<sockaddr *>(&value), size); });
  if (result == 0)
    return 0;
  if (errno == EISCONN)
    return 0;
  if (errno == EINPROGRESS || errno == EALREADY || errno == EWOULDBLOCK)
    return 1;
  return -1;
}

extern "C" std::int32_t mettle_rt_sock_connect_status(std::int32_t fd) {
  int failure = 0;
  socklen_t size = sizeof failure;
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size) != 0)
    return -1;
  if (failure != 0) {
    errno = failure;
    return -1;
  }
  return 0;
}
