#include <atomic>
#include <cstdint>
#include <thread>

namespace {
struct Guard {
  std::int32_t *counter;
  ~Guard() { ++*counter; }
};
} // namespace

extern "C" [[noreturn]] void mettle_cpp_throw() { throw 42; }

extern "C" std::int32_t
mettle_cpp_indirect_throw_catch(void (*callback)(void *),
                                std::int32_t *context) {
  try {
    Guard guard{context};
    callback(context);
  } catch (...) {
    return 1;
  }
  return 0;
}

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

extern "C" std::int32_t mettle_atomic_bitwise_contention(
    void (*reset)(void *, std::uint32_t),
    std::uintptr_t (*modify)(void *, std::uint32_t, std::uint32_t),
    std::uintptr_t (*load)(void *, std::uint32_t), void *context,
    std::uintptr_t base, std::uint32_t operation) {
  constexpr unsigned rounds = 2000;
  std::uintptr_t observed[2]{};
  std::atomic<unsigned> phase{0}, done[2]{};
  auto worker = [&](unsigned index) {
    for (unsigned round = 1; round <= rounds; ++round) {
      while (phase.load(std::memory_order_acquire) != round)
        std::this_thread::yield();
      observed[index] = modify(context, operation, index);
      done[index].store(round, std::memory_order_release);
    }
  };
  auto change = [&](std::uintptr_t value, unsigned index) {
    auto bit = std::uintptr_t{1} << index;
    switch (operation) {
    case 0:
      return value ^ std::uintptr_t{1};
    case 1:
      return value | bit;
    case 2:
      return value & ~bit;
    default:
      return value ^ bit;
    }
  };
  auto initial = operation == 0 ? 0 : operation == 2 ? base | 3 : base;
  auto expected = change(change(initial, 0), 1);
  std::thread left(worker, 0), right(worker, 1);
  bool failed = false;
  for (unsigned round = 1; round <= rounds; ++round) {
    // Phase/completion edges separate callbacks from resets and checks.
    reset(context, operation);
    phase.store(round, std::memory_order_release);
    while (done[0].load(std::memory_order_acquire) != round ||
           done[1].load(std::memory_order_acquire) != round)
      std::this_thread::yield();
    bool linear =
        (observed[0] == initial && observed[1] == change(initial, 0)) ||
        (observed[1] == initial && observed[0] == change(initial, 1));
    failed |= !linear || load(context, operation) != expected;
  }
  left.join();
  right.join();
  return failed ? 1 : 0;
}
