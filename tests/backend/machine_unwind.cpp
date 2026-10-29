#include <atomic>
#include <cstdint>
#include <thread>

namespace {
struct Guard {
  std::int32_t *counter;
  ~Guard() { ++*counter; }
};
} // namespace

extern "C" std::int32_t
mettle_c_variadic_definition_catch(std::int32_t (*callback)(void *, ...),
                                   void *context) {
  try {
    Guard guard{static_cast<std::int32_t *>(context)};
    callback(context, 42);
  } catch (...) {
    return 1;
  }
  return 0;
}

extern "C" std::int32_t mettle_c_machine_catch(void (*callback)(void *),
                                               void *context) {
  try {
    callback(context);
  } catch (...) {
    return 1;
  }
  return 0;
}

extern "C" std::int32_t mettle_c_catch(void (*callback)(void *),
                                       void *context) {
  try {
    Guard guard{static_cast<std::int32_t *>(context)};
    callback(context);
  } catch (...) {
    return 1;
  }
  return 0;
}
extern "C" std::int32_t mettle_cell_catch(void (*callback)(void *),
                                          void *context) {
  try {
    callback(context);
  } catch (...) {
    return 1;
  }
  return 0;
}
extern "C" std::int32_t
mettle_atomic_publication(void (*store)(void *, std::uint32_t),
                          std::uint32_t (*load)(void *), void *context) {
  std::uint32_t payload = 0, observed = 0;
  std::thread consumer([&] {
    while (load(context) == 0)
      std::this_thread::yield();
    observed = payload;
  });
  std::thread producer([&] {
    payload = 42;
    store(context, 1);
  });
  producer.join();
  consumer.join();
  return observed == 42 ? 0 : 1;
}

extern "C" std::int32_t
mettle_atomic_failed_acquire(void (*store)(void *, std::uint32_t),
                             std::uint32_t (*compare)(void *), void *context) {
  std::uint32_t payload = 0, observed = 0;
  std::thread consumer([&] {
    while (compare(context) == 0)
      std::this_thread::yield();
    observed = payload;
  });
  std::thread producer([&] {
    payload = 42;
    store(context, 1);
  });
  producer.join();
  consumer.join();
  return observed == 42 ? 0 : 1;
}

extern "C" std::int32_t mettle_atomic_sequential_consistency(
    void (*store)(void *, std::uint32_t, std::uint32_t),
    std::uint32_t (*load)(void *, std::uint32_t), void *context) {
  constexpr unsigned rounds = 2000;
  std::uint32_t first = 0, second = 0;
  std::atomic<unsigned> phase{0}, leftDone{0}, rightDone{0};
  std::thread left([&] {
    for (unsigned i = 1; i <= rounds; ++i) {
      while (phase.load(std::memory_order_acquire) != i)
        std::this_thread::yield();
      store(context, 0, 1);
      first = load(context, 1);
      leftDone.store(i, std::memory_order_release);
    }
  });
  std::thread right([&] {
    for (unsigned i = 1; i <= rounds; ++i) {
      while (phase.load(std::memory_order_acquire) != i)
        std::this_thread::yield();
      store(context, 1, 1);
      second = load(context, 0);
      rightDone.store(i, std::memory_order_release);
    }
  });
  bool forbidden = false;
  for (unsigned i = 1; i <= rounds; ++i) {
    store(context, 0, 0);
    store(context, 1, 0);
    phase.store(i, std::memory_order_release);
    while (leftDone.load(std::memory_order_acquire) != i ||
           rightDone.load(std::memory_order_acquire) != i)
      std::this_thread::yield();
    forbidden |= first == 0 && second == 0;
  }
  left.join();
  right.join();
  return forbidden ? 1 : 0;
}
