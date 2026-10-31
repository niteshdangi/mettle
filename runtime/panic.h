#pragma once

#include <cstdint>

extern "C" {
using MettleAction = void (*)(void *);
using MettleCleanup = void (*)(void *, std::int32_t);
void mettle_rt_run(void *context, MettleAction body, MettleCleanup cleanup);
void mettle_rt_run_c(void *context, MettleAction body,
                     MettleCleanup cleanup) noexcept;
void mettle_rt_cleanup(void *context, MettleCleanup cleanup,
                       std::int32_t unwinding);
void mettle_rt_replace(void *context, MettleCleanup destroyOld,
                       MettleAction install);
std::int32_t mettle_rt_catch(void *context, MettleAction body);
// Returns zero on normal return, or the panic code and an owned opaque payload.
std::int32_t mettle_rt_catch_payload(void *context, MettleAction body,
                                     void **payload);
std::int32_t mettle_rt_panic_payload_code(void *payload);
// The message view stays valid until the opaque payload is freed.
const std::uint8_t *mettle_rt_panic_payload_message(void *payload,
                                                    std::uint64_t *length);
void mettle_rt_panic_payload_free(void *payload);
[[noreturn]] void mettle_rt_panic(std::int32_t code);
// Source-level panic hook: reports `message` on stderr, then unwinds with the
// message panic code that `mettle_rt_main` maps to status 101 if uncaught.
[[noreturn]] void mettle_rt_panic_message(const std::uint8_t *message,
                                          std::uint64_t length);
// Replaces the default stderr report of `mettle_rt_panic_message` (clearing
// restores it). The hook runs before unwinding starts, must not panic, and
// does not change the exit status.
using MettlePanicHook = void (*)(const std::uint8_t *, std::uint64_t);
void mettle_rt_set_panic_hook(MettlePanicHook hook);
// Atomically takes the custom hook and restores the default reporter.
MettlePanicHook mettle_rt_take_panic_hook();
void mettle_rt_clear_panic_hook();
std::int32_t mettle_rt_panicking();
std::int32_t mettle_rt_main(void *context, MettleAction body);
}
