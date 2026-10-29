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
[[noreturn]] void mettle_rt_panic(std::int32_t code);
std::int32_t mettle_rt_panicking();
std::int32_t mettle_rt_main(void *context, MettleAction body);
}
