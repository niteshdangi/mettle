#include "../../runtime/panic.h"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

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
} // namespace

int main() {
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
