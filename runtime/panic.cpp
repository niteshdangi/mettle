#include "panic.h"

#include <cstdlib>
#include <exception>

namespace {
struct Panic {
  std::int32_t code;
};
thread_local unsigned unwindDepth = 0;
class Unwinding {
public:
  Unwinding() { ++unwindDepth; }
  ~Unwinding() { --unwindDepth; }
  Unwinding(const Unwinding &) = delete;
  Unwinding &operator=(const Unwinding &) = delete;
};
bool panicking() { return unwindDepth != 0 || std::uncaught_exceptions() != 0; }
void installReplacement(void *context, MettleAction install) noexcept {
  try {
    install(context);
  } catch (...) {
    std::abort();
  }
}
} // namespace

extern "C" void mettle_rt_run(void *context, MettleAction body,
                              MettleCleanup cleanup) {
  try {
    body(context);
  } catch (...) {
    if (panicking())
      std::abort();
    Unwinding state;
    try {
      cleanup(context, 1);
    } catch (...) {
      std::abort();
    }
    throw;
  }
}

extern "C" void mettle_rt_run_c(void *context, MettleAction body,
                                MettleCleanup cleanup) noexcept {
  try {
    mettle_rt_run(context, body, cleanup);
  } catch (...) {
    std::abort();
  }
}

extern "C" void mettle_rt_cleanup(void *context, MettleCleanup cleanup,
                                  std::int32_t unwinding) {
  bool alreadyUnwinding = unwinding != 0 || panicking();
  if (alreadyUnwinding) {
    Unwinding state;
    try {
      cleanup(context, 1);
    } catch (...) {
      std::abort();
    }
    return;
  }
  try {
    cleanup(context, 0);
  } catch (...) {
    Unwinding state;
    // Generated glue clears each flag before destruction; re-entry finishes
    // only fields that remain initialized, without repeating the destructor.
    try {
      cleanup(context, 1);
    } catch (...) {
      std::abort();
    }
    throw;
  }
}

extern "C" void mettle_rt_replace(void *context, MettleCleanup destroyOld,
                                  MettleAction install) {
  try {
    mettle_rt_cleanup(context, destroyOld, mettle_rt_panicking());
  } catch (...) {
    installReplacement(context, install);
    throw;
  }
  installReplacement(context, install);
}

extern "C" std::int32_t mettle_rt_catch(void *context, MettleAction body) {
  try {
    body(context);
  } catch (const Panic &panic) {
    return panic.code;
  } catch (...) {
    std::abort();
  }
  return 0;
}

extern "C" [[noreturn]] void mettle_rt_panic(std::int32_t code) {
  if (panicking())
    std::abort();
  throw Panic{code == 0 ? 1 : code};
}

extern "C" std::int32_t mettle_rt_panicking() { return panicking() ? 1 : 0; }

extern "C" std::int32_t mettle_rt_main(void *context, MettleAction body) {
  try {
    body(context);
  } catch (...) {
    std::abort();
  }
  return 0;
}
