#pragma once

#include <cstddef>
#include <cstdint>

// Thin POSIX shims for the hosted `std` library. Mettle calls libc directly
// wherever the C signature is portable; these cover only what it cannot
// express: `errno`, variadic `open`, platform-specific constants and struct
// layouts, process creation and the process arguments. Each function reports
// failure like the libc call it wraps (negative result, `errno` set) unless
// stated otherwise, and is identical on macOS and Linux.
extern "C" {
std::int32_t mettle_rt_errno();
// Portable error class of an `errno` value, numbered like `std::io::ErrorKind`
// (18 is the catch-all `Other`); platform errno numbers never leak into Mettle.
std::int32_t mettle_rt_errno_kind(std::int32_t code);
std::int32_t mettle_rt_errno_is_range(std::int32_t code);
void mettle_rt_set_errno(std::int32_t value);

// Duplicates with close-on-exec into a descriptor above standard streams.
std::int32_t mettle_rt_dup(std::int32_t fd);
// Portable open flags: 1 read, 2 write, 4 append, 8 truncate, 16 create,
// 32 create-new. The descriptor is close-on-exec.
std::int32_t mettle_rt_open(const char *path, std::int32_t flags,
                            std::uint32_t mode);
// Fills `out` with size, kind (0 file, 1 directory, 2 symlink, 3 other),
// permission bits, modification seconds and nanoseconds. A
// non-negative `fd` selects fstat; otherwise `follow` selects stat or lstat.
std::int32_t mettle_rt_stat(const char *path, std::int32_t fd,
                            std::int32_t follow, std::int64_t *out);
// Next entry name of an open directory, skipping `.` and `..`; null at the end
// (with `errno` zero) or on failure.
const char *mettle_rt_readdir(void *directory);
std::int32_t mettle_rt_remove_dir_all(const char *path);

std::int32_t mettle_rt_argc();
const char *mettle_rt_argv(std::int32_t index);
// The table and strings are borrowed; environment mutation invalidates them.
const char *const *mettle_rt_environ();

// Stdio modes: 0 inherit, 1 pipe, 2 null device. `envp` null inherits the
// environment; `cwd` null inherits the directory. Piped parent ends are
// returned in `fds` (-1 otherwise). Returns the child id, or -1 with the
// `errno` that made the child fail before running the program.
std::int32_t mettle_rt_spawn(const char *program, const char *const *argv,
                             const char *const *envp, const char *cwd,
                             const std::int32_t *modes, std::int32_t *fds);
// Waits until `fd` is readable (or writable when `write` is nonzero) or the
// timeout in milliseconds (negative: none) expires. 1 ready, 0 timeout.
std::int32_t mettle_rt_poll(std::int32_t fd, std::int32_t write,
                            std::int32_t timeoutMillis);
// Blocks until either descriptor (negative ones are ignored) is readable or
// hung up; bit 0 and bit 1 of the result name the ready descriptors.
std::int32_t mettle_rt_poll_pair(std::int32_t first, std::int32_t second);

// POSIX sockets: kind 0 stream, 1 datagram; family is 4 or 6. Address bytes
// are in network order and have explicit lengths (4 for IPv4, 16 for IPv6).
std::int32_t mettle_rt_sock_new(std::int32_t kind, std::int32_t family);
std::int32_t mettle_rt_sock_bind(std::int32_t fd, std::int32_t family,
                                 const std::uint8_t *address,
                                 std::size_t addressSize, std::uint16_t port,
                                 std::uint32_t flowinfo, std::uint32_t scopeId);
std::int32_t mettle_rt_sock_connect(std::int32_t fd, std::int32_t family,
                                    const std::uint8_t *address,
                                    std::size_t addressSize, std::uint16_t port,
                                    std::uint32_t flowinfo,
                                    std::uint32_t scopeId);
// A timed nonblocking connect; timeout is in microseconds.
std::int32_t mettle_rt_sock_connect_timeout(
    std::int32_t fd, std::int32_t family, const std::uint8_t *address,
    std::size_t addressSize, std::uint16_t port, std::uint32_t flowinfo,
    std::uint32_t scopeId, std::uint64_t timeoutMicros);
// Requires O_NONBLOCK; logical blocking expires via timedOut/EAGAIN (<0:
// forever). The returned socket is blocking and close-on-exec.
std::int32_t mettle_rt_sock_accept(std::int32_t fd, std::int32_t timeoutMillis,
                                   std::int32_t nonblocking,
                                   std::int32_t *timedOut, std::int32_t *family,
                                   std::uint8_t *address,
                                   std::size_t addressCapacity,
                                   std::uint16_t *port, std::uint32_t *flowinfo,
                                   std::uint32_t *scopeId);
std::int32_t mettle_rt_sock_name(std::int32_t fd, std::int32_t peer,
                                 std::int32_t *family, std::uint8_t *address,
                                 std::size_t addressCapacity,
                                 std::uint16_t *port, std::uint32_t *flowinfo,
                                 std::uint32_t *scopeId);
std::int64_t mettle_rt_sock_send(std::int32_t fd, const std::uint8_t *data,
                                 std::size_t size);
std::int64_t mettle_rt_sock_sendto(std::int32_t fd, const std::uint8_t *data,
                                   std::size_t size, std::int32_t family,
                                   const std::uint8_t *address,
                                   std::size_t addressSize, std::uint16_t port,
                                   std::uint32_t flowinfo,
                                   std::uint32_t scopeId);
std::int64_t
mettle_rt_sock_recvfrom(std::int32_t fd, std::uint8_t *data, std::size_t size,
                        std::int32_t *family, std::uint8_t *address,
                        std::size_t addressCapacity, std::uint16_t *port,
                        std::uint32_t *flowinfo, std::uint32_t *scopeId);
// Receive (send == 0) or send timeout in microseconds; zero disables it.
std::int32_t mettle_rt_sock_timeout(std::int32_t fd, std::int32_t send,
                                    std::uint64_t micros);
std::int32_t mettle_rt_sock_set_nodelay(std::int32_t fd, std::int32_t enabled);
std::int32_t mettle_rt_sock_get_nodelay(std::int32_t fd, std::int32_t *enabled);
std::int32_t mettle_rt_sock_error(std::int32_t fd, std::int32_t *error);

// Resolution handles own their getaddrinfo-derived address list. The caller
// must release a non-null handle with `mettle_rt_resolve_free`.
std::uint8_t *mettle_rt_resolve(const std::uint8_t *host, std::size_t hostSize,
                                std::uint16_t port, std::size_t *count);
std::int32_t mettle_rt_resolve_get(std::uint8_t *handle, std::size_t index,
                                   std::int32_t *family, std::uint8_t *address,
                                   std::size_t addressCapacity,
                                   std::uint16_t *port, std::uint32_t *flowinfo,
                                   std::uint32_t *scopeId);
void mettle_rt_resolve_free(std::uint8_t *handle);

// Clock 0 monotonic, 1 wall; fills seconds and nanoseconds.
std::int32_t mettle_rt_clock(std::int32_t clock, std::int64_t *out);
// Sleeps the whole duration, resuming after signal interruptions.
void mettle_rt_sleep(std::uint64_t seconds, std::uint32_t nanos);

// Per-executor hosted reactor. A successful registration takes ownership of
// one already-cloned raw waker; readiness or timer expiry calls `wake`, while
// cancellation calls `release`. Token zero is reserved for failure. Closing
// the handle requires the owning executor and all its futures to be quiescent.
void *mettle_rt_reactor_new();
void mettle_rt_reactor_close(void *reactor);
std::uint64_t mettle_rt_reactor_watch(void *reactor, std::int32_t fd,
                                      std::int32_t write, void *data,
                                      void (*wake)(void *),
                                      void (*release)(void *));
std::uint64_t mettle_rt_reactor_timer(void *reactor, std::uint64_t seconds,
                                      std::uint32_t nanos, void *data,
                                      void (*wake)(void *),
                                      void (*release)(void *));
void mettle_rt_reactor_cancel(void *reactor, std::uint64_t token);
void mettle_rt_reactor_wake(void *reactor);
// Blocks until a registered event or timer invokes its waker. Returns zero on
// an executor-control wake and -1 on failure.
std::int32_t mettle_rt_reactor_wait(void *reactor);

// Descriptor blocking-mode operations used by `std.net`.
std::int32_t mettle_rt_sock_is_nonblocking(std::int32_t fd);
std::int32_t mettle_rt_set_nonblocking(std::int32_t fd);
std::int32_t mettle_rt_set_blocking(std::int32_t fd);
std::int32_t mettle_rt_sock_connect_start(std::int32_t fd, std::int32_t family,
                                          const std::uint8_t *address,
                                          std::size_t addressSize,
                                          std::uint16_t port,
                                          std::uint32_t flowinfo,
                                          std::uint32_t scopeId);
std::int32_t mettle_rt_sock_connect_status(std::int32_t fd);
}
