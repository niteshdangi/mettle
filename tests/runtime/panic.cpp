#include "../../runtime/panic.h"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <string>
#include <string_view>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace {
enum class Allocation { Allow, Fail, Forbid };
Allocation allocationPolicy = Allocation::Allow;
} // namespace

void *operator new(std::size_t size) {
  if (allocationPolicy == Allocation::Forbid) {
    constexpr char message[] = "unexpected allocation in abort panic\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    std::abort();
  }
  if (allocationPolicy == Allocation::Fail)
    throw std::bad_alloc();
  if (auto *allocation = std::malloc(size ? size : 1))
    return allocation;
  throw std::bad_alloc();
}
void operator delete(void *allocation) noexcept { std::free(allocation); }
void operator delete(void *allocation, std::size_t) noexcept {
  std::free(allocation);
}

namespace {
void require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    std::exit(1);
  }
}
struct Context {
  std::vector<int> events;
  bool oldLive = true, fieldLive = true, pending = true;
  bool panicField = false;
  int value = 1;
  volatile int *installed = nullptr;
};
void destroy(void *raw, std::int32_t unwinding) {
  auto &context = *static_cast<Context *>(raw);
  if (context.oldLive) {
    context.oldLive = false;
    context.events.push_back(1);
    mettle_rt_panic(7);
  }
  if (context.fieldLive) {
    context.fieldLive = false;
    context.events.push_back(2);
    require(unwinding != 0 && mettle_rt_panicking() != 0,
            "missing unwind state");
    if (context.panicField)
      mettle_rt_panic(8);
  }
}
void install(void *raw) {
  auto &context = *static_cast<Context *>(raw);
  require(!context.oldLive && !context.fieldLive,
          "replacement installed before old cleanup");
  require(mettle_rt_panicking() == 0,
          "replacement inherited the completed cleanup's unwind state");
  context.pending = false;
  context.value = 42;
  context.events.push_back(3);
  if (context.installed)
    *context.installed = 1;
}
void replace(void *raw) { mettle_rt_replace(raw, destroy, install); }
void bodyPanic(void *raw) {
  static_cast<Context *>(raw)->events.push_back(4);
  mettle_rt_panic(9);
}
void cleanup(void *raw, std::int32_t unwinding) {
  auto &context = *static_cast<Context *>(raw);
  require(unwinding != 0 && mettle_rt_panicking() != 0,
          "frame cleanup not unwinding");
  context.events.push_back(5);
}
void run(void *raw) { mettle_rt_run(raw, bodyPanic, cleanup); }
constexpr std::string_view formattedMessage =
    "left=1 right={2}; this payload must outgrow the owned string object";
static_assert(formattedMessage.size() > sizeof(std::string));
struct FormattedContext {
  int renders = 0;
  std::string hookMessage;
};
FormattedContext *hookContext = nullptr;
void render(void *raw, MettlePanicWrite write, void *sink) {
  ++static_cast<FormattedContext *>(raw)->renders;
  constexpr std::string_view parts[]{
      "left=1 ",
      "right={2}; this payload must outgrow the owned string object"};
  for (auto part : parts)
    write(sink, reinterpret_cast<const std::uint8_t *>(part.data()),
          part.size());
}
void formattedPanic(void *raw) {
  constexpr std::string_view file = "format.mt";
  mettle_rt_panic_fmt(raw, render,
                      reinterpret_cast<const std::uint8_t *>(file.data()),
                      file.size(), 7, 9);
}
void observeHook(const MettlePanicHookInfo *info) {
  require(hookContext && hookContext->renders == 1,
          "hook ran before rendering or message rendered repeatedly");
  require(mettle_rt_panicking() == 0, "hook ran after unwinding started");
  require(std::string_view(reinterpret_cast<const char *>(info->file),
                           info->fileLength) == "format.mt" &&
              info->line == 7 && info->column == 9,
          "formatted panic lost source location");
  hookContext->hookMessage.assign(reinterpret_cast<const char *>(info->payload),
                                  info->payloadLength);
}
void caughtFormattedPanic(void *raw) {
  auto &context = *static_cast<FormattedContext *>(raw);
  void *payload = nullptr;
  require(mettle_rt_catch_payload(raw, formattedPanic, &payload) == 101,
          "formatted panic did not retain status 101");
  std::uint64_t length = 0;
  auto *message = mettle_rt_panic_payload_message(payload, &length);
  require(context.renders == 1 && context.hookMessage == formattedMessage &&
              std::string_view(reinterpret_cast<const char *>(message),
                               length) == context.hookMessage,
          "hook and catch did not receive the same rendered message");
  mettle_rt_panic_payload_free(payload);
}
void formattedPanics() {
  FormattedContext context;
  hookContext = &context;
  mettle_rt_set_panic_hook(observeHook);
  caughtFormattedPanic(&context);
  context.renders = 0;
  mettle_rt_run_c(&context, caughtFormattedPanic, [](void *, std::int32_t) {});
  mettle_rt_clear_panic_hook();
  hookContext = nullptr;
  for (auto policy :
       {Allocation::Allow, Allocation::Forbid, Allocation::Fail}) {
    int output[2];
    require(pipe(output) == 0, "panic output pipe failed");
    auto child = fork();
    require(child >= 0, "formatted panic fork failed");
    if (child == 0) {
      close(output[0]);
      if (dup2(output[1], STDERR_FILENO) < 0)
        _exit(98);
      close(output[1]);
      FormattedContext childContext;
      allocationPolicy = policy;
      if (policy == Allocation::Forbid) {
        mettle_rt_run_c(&childContext, formattedPanic,
                        [](void *, std::int32_t) {});
      }
      _exit(mettle_rt_main(&childContext, formattedPanic));
    }
    close(output[1]);
    std::string report;
    char bytes[128];
    ssize_t count;
    while ((count = read(output[0], bytes, sizeof(bytes))) > 0)
      report.append(bytes, static_cast<std::size_t>(count));
    require(count == 0, "reading formatted panic output failed");
    close(output[0]);
    int status;
    require(waitpid(child, &status, 0) == child, "formatted panic wait failed");
    const auto expected =
        policy == Allocation::Fail
            ? "fatal: allocation failed while formatting panic\n"
            : "panicked: " + std::string(formattedMessage) + "\n";
    require(report == expected,
            "default hook did not report exact formatted text");
    require(policy != Allocation::Allow
                ? WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT
                : WIFEXITED(status) && WEXITSTATUS(status) == 101,
            "formatted panic used the wrong termination strategy");
  }
}
} // namespace

int main() {
  formattedPanics();
  Context replacement;
  require(mettle_rt_catch(&replacement, replace) == 7,
          "lost original replacement panic");
  require(replacement.events == std::vector<int>({1, 2, 3}),
          "wrong replacement cleanup order");
  require(replacement.value == 42 && !replacement.pending,
          "catch observed invalid replacement");
  require(mettle_rt_panicking() == 0, "unwind state leaked beyond catch");
  Context frame;
  require(mettle_rt_catch(&frame, run) == 9, "lost frame panic");
  require(frame.events == std::vector<int>({4, 5}),
          "frame cleanup not run exactly once");
  auto *installed = static_cast<volatile int *>(
      mmap(nullptr, sizeof(int), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON,
           -1, 0));
  require(installed != MAP_FAILED, "shared observation allocation failed");
  *installed = 0;
  auto child = fork();
  require(child >= 0, "fork failed");
  if (child == 0) {
    Context second;
    second.panicField = true;
    second.installed = installed;
    mettle_rt_catch(&second, replace);
    _exit(99);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child, "wait failed");
  require(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT,
          "double panic did not abort");
  require(*installed == 0, "double-panic path installed replacement");
  munmap(const_cast<int *>(installed), sizeof(int));
  std::puts(
      "native unwind, replacement restoration and double-panic abort passed");
}
