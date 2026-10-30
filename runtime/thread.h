#pragma once

#include <cstdint>

// Hosted threading and synchronization support for the native `std` library.
// Native pthread object sizes differ between targets, so the library holds
// every primitive behind an opaque heap handle created here. Operations return
// 0 on success or an errno-style code; none of them unwinds.
extern "C" {
using MettleThreadEntry = void (*)(void *);
using MettleTlsDestructor = void (*)(void *);

// Starts a joinable thread running `entry(argument)`. `handle` receives the
// thread identity used by join.
std::int32_t mettle_rt_thread_spawn(MettleThreadEntry entry, void *argument,
                                    std::uintptr_t *handle);
std::int32_t mettle_rt_thread_join(std::uintptr_t handle);
std::int32_t mettle_rt_thread_detach(std::uintptr_t handle);
std::uintptr_t mettle_rt_thread_current();
void mettle_rt_thread_yield();
void mettle_rt_thread_sleep(std::uint64_t nanoseconds);
std::uint64_t mettle_rt_thread_parallelism();

// Non-recursive, error-checking mutex: relocking on the owning thread and
// unlocking from another thread are reported instead of being undefined.
void *mettle_rt_mutex_new();
void mettle_rt_mutex_free(void *mutex);
std::int32_t mettle_rt_mutex_lock(void *mutex);
std::int32_t mettle_rt_mutex_try_lock(void *mutex);
std::int32_t mettle_rt_mutex_unlock(void *mutex);

void *mettle_rt_cond_new();
void mettle_rt_cond_free(void *cond);
std::int32_t mettle_rt_cond_wait(void *cond, void *mutex);
// Returns 0 when signalled (or spuriously woken) and 1 on timeout.
std::int32_t mettle_rt_cond_wait_timeout(void *cond, void *mutex,
                                         std::uint64_t nanoseconds);
std::int32_t mettle_rt_cond_notify_one(void *cond);
std::int32_t mettle_rt_cond_notify_all(void *cond);

void *mettle_rt_rwlock_new();
void mettle_rt_rwlock_free(void *lock);
std::int32_t mettle_rt_rwlock_read(void *lock);
std::int32_t mettle_rt_rwlock_try_read(void *lock);
std::int32_t mettle_rt_rwlock_write(void *lock);
std::int32_t mettle_rt_rwlock_try_write(void *lock);
std::int32_t mettle_rt_rwlock_unlock(void *lock);

// Thread-local storage keys; the destructor runs at thread exit for each
// thread whose slot is non-null. Returns a nonzero key, or 0 on failure.
std::uintptr_t mettle_rt_tls_key_new(MettleTlsDestructor destructor);
void mettle_rt_tls_key_free(std::uintptr_t key);
void *mettle_rt_tls_get(std::uintptr_t key);
std::int32_t mettle_rt_tls_set(std::uintptr_t key, void *value);
}
