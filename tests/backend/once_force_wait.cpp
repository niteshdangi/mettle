#include <atomic>
#include <cstdint>
#include <thread>

namespace {
std::atomic<std::int32_t> phase{0}, released{0};
thread_local int nextPhase = 0;
} // namespace

extern "C" void __real_mettle_rt_thread_yield();

extern "C" void mettle_once_wait_begin() { nextPhase = 1; }

extern "C" void mettle_once_wait_end() {
  nextPhase = 0;
  phase.store(3, std::memory_order_release);
}

extern "C" std::int32_t mettle_once_wait_phase() {
  return phase.load(std::memory_order_acquire);
}

extern "C" void mettle_once_wait_release(std::int32_t value) {
  released.store(value, std::memory_order_release);
}

extern "C" void __wrap_mettle_rt_thread_yield() {
  if (nextPhase == 1 || nextPhase == 2) {
    const auto waiting = nextPhase++;
    phase.store(waiting, std::memory_order_release);
    while (released.load(std::memory_order_acquire) < waiting)
      std::this_thread::yield();
  }
  __real_mettle_rt_thread_yield();
}
