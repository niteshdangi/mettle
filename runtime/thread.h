#pragma once

#include <cstdint>

// Hosted threading and synchronization support for the native `std` library.
// Native pthread object sizes differ between targets, so the library holds
// every primitive behind an opaque heap handle created here. OS operations
// return 0 on success or an errno-style code; thread callbacks run through the
// explicit catch boundary below.
extern "C" {
using MettleThreadEntry = void (*)(void *);
using MettleThreadBody = void (*)(void *);
using MettleTlsDestructor = void (*)(void *);

// Starts a joinable thread running `entry(argument)`. `handle` receives the
// thread identity used by join.
std::int32_t mettle_rt_thread_spawn(MettleThreadEntry entry, void *argument,
                                    std::uintptr_t *handle);
std::int32_t mettle_rt_thread_join(std::uintptr_t handle);
std::int32_t mettle_rt_thread_detach(std::uintptr_t handle);
// Catches a body panic, then catches any panic from this thread's TLS cleanup.
std::int32_t mettle_rt_thread_catch(void *context, MettleThreadBody body);
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
// thread whose slot is non-null. Values are destroyed in reverse order of
// their first non-null assignment on that thread. Returns a nonzero key, or 0
// on failure.
std::uintptr_t mettle_rt_tls_key_new(MettleTlsDestructor destructor);
// Static keys are associated with their immutable descriptor address and live
// for the process lifetime.
std::uintptr_t mettle_rt_tls_static_key_new(const void *identity,
                                            MettleTlsDestructor destructor);
void mettle_rt_tls_key_free(std::uintptr_t key);
void *mettle_rt_tls_get(std::uintptr_t key);
std::int32_t mettle_rt_tls_set(std::uintptr_t key, void *value);
// Runs the current thread's remaining TLS destructors. A destructor panic
// propagates to the surrounding runtime catch boundary. The hosted main entry
// calls this before returning; pthread exit invokes it automatically.
void mettle_rt_tls_thread_exit();

// A process-wide generation condition used by channel selectors. A waiter
// sleeps only while the generation remains unchanged.
std::uint64_t mettle_rt_select_epoch();
void mettle_rt_select_wait(std::uint64_t epoch);
void mettle_rt_select_notify();
}
