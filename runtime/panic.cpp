#include "panic.h"
#include "thread.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <new>
#include <string>
#include <utility>

namespace {
constexpr std::int32_t messagePanicCode = 101;
struct Panic {
  std::int32_t code;
  std::string message;
};
thread_local unsigned unwindDepth = 0;
thread_local bool invokingPanicHook = false;
std::atomic<MettlePanicHook> panicHook{nullptr};
class Unwinding {
public:
  Unwinding() { ++unwindDepth; }
  ~Unwinding() { --unwindDepth; }
  Unwinding(const Unwinding &) = delete;
  Unwinding &operator=(const Unwinding &) = delete;
};
bool panicking() { return unwindDepth != 0 || std::uncaught_exceptions() != 0; }
class PanicHookInvocation {
public:
  PanicHookInvocation() {
    if (invokingPanicHook)
      std::abort();
    invokingPanicHook = true;
  }
  ~PanicHookInvocation() { invokingPanicHook = false; }
  PanicHookInvocation(const PanicHookInvocation &) = delete;
  PanicHookInvocation &operator=(const PanicHookInvocation &) = delete;
};
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

extern "C" std::int32_t
mettle_rt_catch_payload(void *context, MettleAction body, void **payload) {
  if (!payload)
    std::abort();
  *payload = nullptr;
  try {
    body(context);
  } catch (const Panic &panic) {
    try {
      *payload = new Panic{panic.code, panic.message};
    } catch (...) {
      std::abort();
    }
    return panic.code;
  } catch (...) {
    std::abort();
  }
  return 0;
}

extern "C" std::int32_t mettle_rt_panic_payload_code(void *raw) {
  if (!raw)
    std::abort();
  return static_cast<Panic *>(raw)->code;
}

extern "C" const std::uint8_t *
mettle_rt_panic_payload_message(void *raw, std::uint64_t *length) {
  if (!raw || !length)
    std::abort();
  const auto &message = static_cast<Panic *>(raw)->message;
  *length = static_cast<std::uint64_t>(message.size());
  return reinterpret_cast<const std::uint8_t *>(message.data());
}

extern "C" void mettle_rt_panic_payload_free(void *raw) {
  delete static_cast<Panic *>(raw);
}

extern "C" [[noreturn]] void mettle_rt_panic(std::int32_t code) {
  if (panicking() || invokingPanicHook)
    std::abort();
  throw Panic{code == 0 ? 1 : code, {}};
}

extern "C" [[noreturn]] void
mettle_rt_panic_message(const std::uint8_t *message, std::uint64_t length) {
  const auto size = static_cast<std::size_t>(length);
  if (panicking() || invokingPanicHook ||
      static_cast<std::uint64_t>(size) != length || (length != 0 && !message))
    std::abort();
  std::string payload;
  if (length)
    payload.assign(reinterpret_cast<const char *>(message), size);
  if (auto *hook = panicHook.load()) {
    try {
      PanicHookInvocation invocation;
      hook(message, length);
    } catch (...) {
      std::abort();
    }
    throw Panic{messagePanicCode, std::move(payload)};
  }
  std::fputs("panicked: ", stderr);
  if (length)
    std::fwrite(message, 1, size, stderr);
  std::fputc('\n', stderr);
  std::fflush(stderr);
  throw Panic{messagePanicCode, std::move(payload)};
}

extern "C" void mettle_rt_set_panic_hook(MettlePanicHook hook) {
  panicHook.store(hook);
}

extern "C" MettlePanicHook mettle_rt_take_panic_hook() {
  return panicHook.exchange(nullptr);
}

extern "C" void mettle_rt_clear_panic_hook() { panicHook.store(nullptr); }

extern "C" std::int32_t mettle_rt_panicking() { return panicking() ? 1 : 0; }

extern "C" std::int32_t mettle_rt_main(void *context, MettleAction body) {
  std::int32_t status = 0;
  try {
    body(context);
  } catch (const Panic &panic) {
    if (panic.code != messagePanicCode)
      std::abort();
    status = messagePanicCode;
  } catch (...) {
    std::abort();
  }
  try {
    mettle_rt_tls_thread_exit();
  } catch (const Panic &panic) {
    if (panic.code != messagePanicCode || status != 0)
      std::abort();
    status = messagePanicCode;
  } catch (...) {
    std::abort();
  }
  return status;
}
