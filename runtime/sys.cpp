#include "sys.h"

#include <cerrno>
#include <cstring>
#include <ctime>

#include <dirent.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __APPLE__
#include <crt_externs.h>
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

sockaddr_in socketAddress(std::uint32_t address, std::uint16_t port) {
  sockaddr_in value;
  std::memset(&value, 0, sizeof value);
  value.sin_family = AF_INET;
  value.sin_port = htons(port);
  value.sin_addr.s_addr = htonl(address);
#ifdef __APPLE__
  value.sin_len = sizeof value;
#endif
  return value;
}

void readAddress(const sockaddr_in &value, std::uint32_t *address,
                 std::uint16_t *port) {
  if (address)
    *address = ntohl(value.sin_addr.s_addr);
  if (port)
    *port = ntohs(value.sin_port);
}

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

extern "C" std::int32_t mettle_rt_sock_new(std::int32_t kind) {
  int fd = socket(AF_INET, kind == 0 ? SOCK_STREAM : SOCK_DGRAM, 0);
  if (fd < 0)
    return -1;
  setCloseOnExec(fd);
#ifdef SO_NOSIGPIPE
  int on = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
  return fd;
}

extern "C" std::int32_t mettle_rt_sock_bind(std::int32_t fd,
                                            std::uint32_t address,
                                            std::uint16_t port) {
  int on = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
  auto value = socketAddress(address, port);
  return bind(fd, reinterpret_cast<sockaddr *>(&value), sizeof value);
}

extern "C" std::int32_t mettle_rt_sock_connect(std::int32_t fd,
                                               std::uint32_t address,
                                               std::uint16_t port) {
  auto value = socketAddress(address, port);
  return retry([&] {
    return connect(fd, reinterpret_cast<sockaddr *>(&value), sizeof value);
  });
}

extern "C" std::int32_t mettle_rt_sock_accept(std::int32_t fd,
                                              std::int32_t timeoutMillis,
                                              std::uint32_t *address,
                                              std::uint16_t *port) {
  if (timeoutMillis >= 0) {
    std::int32_t ready = mettle_rt_poll(fd, 0, timeoutMillis);
    if (ready < 0)
      return -1;
    if (ready == 0) {
      errno = EAGAIN;
      return -1;
    }
  }
  sockaddr_in value;
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
  readAddress(value, address, port);
  return accepted;
}

extern "C" std::int32_t mettle_rt_sock_name(std::int32_t fd, std::int32_t peer,
                                            std::uint32_t *address,
                                            std::uint16_t *port) {
  sockaddr_in value;
  socklen_t size = sizeof value;
  auto *raw = reinterpret_cast<sockaddr *>(&value);
  if ((peer ? getpeername(fd, raw, &size) : getsockname(fd, raw, &size)) != 0)
    return -1;
  readAddress(value, address, port);
  return 0;
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

extern "C" std::int64_t mettle_rt_sock_sendto(std::int32_t fd,
                                              const std::uint8_t *data,
                                              std::size_t size,
                                              std::uint32_t address,
                                              std::uint16_t port) {
  auto value = socketAddress(address, port);
  return retry([&] {
    return sendto(fd, data, size, 0, reinterpret_cast<sockaddr *>(&value),
                  sizeof value);
  });
}

extern "C" std::int64_t
mettle_rt_sock_recvfrom(std::int32_t fd, std::uint8_t *data, std::size_t size,
                        std::uint32_t *address, std::uint16_t *port) {
  sockaddr_in value;
  std::memset(&value, 0, sizeof value);
  socklen_t length = sizeof value;
  auto received = retry([&] {
    return recvfrom(fd, data, size, 0, reinterpret_cast<sockaddr *>(&value),
                    &length);
  });
  if (received >= 0)
    readAddress(value, address, port);
  return received;
}

extern "C" std::int32_t mettle_rt_sock_timeout(std::int32_t fd,
                                               std::int32_t send,
                                               std::uint64_t micros) {
  timeval value;
  value.tv_sec = static_cast<time_t>(micros / 1000000);
  value.tv_usec = static_cast<suseconds_t>(micros % 1000000);
  return setsockopt(fd, SOL_SOCKET, send ? SO_SNDTIMEO : SO_RCVTIMEO, &value,
                    sizeof value);
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
