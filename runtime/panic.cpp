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
thread_local bool abortPanic = false;
thread_local bool invokingPanicHook = false;
std::atomic<MettlePanicHook> panicHook{nullptr};
class Unwinding {
public:
  Unwinding() { ++unwindDepth; }
  ~Unwinding() { --unwindDepth; }
  Unwinding(const Unwinding &) = delete;
  Unwinding &operator=(const Unwinding &) = delete;
};
class PanicBoundary {
  bool previous;

public:
  explicit PanicBoundary(bool abort)
      : previous(std::exchange(abortPanic, abort)) {}
  ~PanicBoundary() { abortPanic = previous; }
  PanicBoundary(const PanicBoundary &) = delete;
  PanicBoundary &operator=(const PanicBoundary &) = delete;
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
void writePanicBytes(void *, const std::uint8_t *bytes, std::uint64_t length) {
  auto size = static_cast<std::size_t>(length);
  if (static_cast<std::uint64_t>(size) != length || (length && !bytes) ||
      (length && std::fwrite(bytes, 1, size, stderr) != size))
    std::abort();
}
void appendPanicBytes(void *context, const std::uint8_t *bytes,
                      std::uint64_t length) {
  auto size = static_cast<std::size_t>(length);
  if (static_cast<std::uint64_t>(size) != length || (length && !bytes))
    std::abort();
  if (!length)
    return;
  try {
    static_cast<std::string *>(context)->append(
        reinterpret_cast<const char *>(bytes), size);
  } catch (...) {
    std::fputs("fatal: allocation failed while formatting panic\n", stderr);
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

extern "C" void mettle_rt_unwind_begin(void) noexcept {
  // The panic being propagated is the one in flight; another one is nested.
  if (unwindDepth != 0 || std::uncaught_exceptions() > 1)
    std::abort();
  ++unwindDepth;
}

extern "C" void mettle_rt_unwind_end(void) noexcept { --unwindDepth; }

extern "C" void mettle_rt_unwind_failed(void) noexcept { std::abort(); }

extern "C" void mettle_rt_run_c(void *context, MettleAction body,
                                MettleCleanup cleanup) noexcept {
  PanicBoundary policy(true);
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
  PanicBoundary policy(false);
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
  PanicBoundary policy(false);
  if (!payload)
    std::abort();
  *payload = nullptr;
  try {
    body(context);
  } catch (Panic &panic) {
    try {
      *payload = new Panic{panic.code, std::move(panic.message)};
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
mettle_rt_panic_message(const std::uint8_t *message, std::uint64_t length,
                        const std::uint8_t *file, std::uint64_t fileLength,
                        std::uint64_t line, std::uint64_t column) {
  const auto size = static_cast<std::size_t>(length);
  if (panicking() || invokingPanicHook ||
      static_cast<std::uint64_t>(size) != length || (length != 0 && !message) ||
      (fileLength != 0 && !file) || ((line == 0) != (column == 0)) ||
      ((line != 0 || column != 0) && !file))
    std::abort();
  std::string payload;
  if (length)
    payload.assign(reinterpret_cast<const char *>(message), size);
  if (auto *hook = panicHook.load()) {
    try {
      PanicHookInvocation invocation;
      const MettlePanicHookInfo info{message,    length, file,
                                     fileLength, line,   column};
      hook(&info);
    } catch (...) {
      std::abort();
    }
    if (abortPanic)
      std::abort();
    throw Panic{messagePanicCode, std::move(payload)};
  }
  std::fputs("panicked: ", stderr);
  if (length)
    std::fwrite(message, 1, size, stderr);
  std::fputc('\n', stderr);
  std::fflush(stderr);
  if (abortPanic)
    std::abort();
  throw Panic{messagePanicCode, std::move(payload)};
}

extern "C" void mettle_rt_set_panic_hook(MettlePanicHook hook) {
  panicHook.store(hook);
}

extern "C" [[noreturn]] void
mettle_rt_panic_fmt(void *context, MettlePanicRender render,
                    const std::uint8_t *file, std::uint64_t fileLength,
                    std::uint64_t line, std::uint64_t column) {
  if (!render || panicking() || invokingPanicHook || (fileLength && !file) ||
      ((line == 0) != (column == 0)) || ((line || column) && !file))
    std::abort();
  auto hook = panicHook.load();
  if (!hook && abortPanic) {
    PanicHookInvocation invocation;
    try {
      if (std::fputs("panicked: ", stderr) < 0)
        std::abort();
      render(context, writePanicBytes, nullptr);
      if (std::fputc('\n', stderr) == EOF || std::fflush(stderr) != 0)
        std::abort();
    } catch (...) {
      std::abort();
    }
    std::abort();
  }
  std::string payload;
  {
    PanicHookInvocation invocation;
    try {
      render(context, appendPanicBytes, &payload);
      if (hook) {
        const MettlePanicHookInfo info{
            reinterpret_cast<const std::uint8_t *>(payload.data()),
            static_cast<std::uint64_t>(payload.size()),
            file,
            fileLength,
            line,
            column};
        hook(&info);
      } else {
        if (std::fputs("panicked: ", stderr) < 0)
          std::abort();
        writePanicBytes(nullptr,
                        reinterpret_cast<const std::uint8_t *>(payload.data()),
                        static_cast<std::uint64_t>(payload.size()));
        if (std::fputc('\n', stderr) == EOF || std::fflush(stderr) != 0)
          std::abort();
      }
    } catch (...) {
      std::abort();
    }
  }
  if (abortPanic)
    std::abort();
  throw Panic{messagePanicCode, std::move(payload)};
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
