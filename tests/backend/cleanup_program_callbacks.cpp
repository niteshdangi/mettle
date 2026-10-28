#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <memory>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

namespace {
struct Leaf {
  std::int32_t tag;
};
struct Resource {
  Leaf first, second;
};
Resource *target = nullptr;
std::vector<std::int32_t> trace;

[[noreturn]] void fail(const char *operation) {
  std::perror(operation);
  std::exit(44);
}
} // namespace

extern "C" void *mettle_test_cleanup_target(std::int32_t mode) {
  const char *path = std::getenv("METTLE_CLEANUP_STATE_FILE");
  if (!path)
    fail("METTLE_CLEANUP_STATE_FILE");
  int descriptor = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
  if (descriptor < 0)
    fail("open cleanup state");
  if (ftruncate(descriptor, sizeof(Resource)) != 0)
    fail("resize cleanup state");
  void *memory = mmap(nullptr, sizeof(Resource), PROT_READ | PROT_WRITE,
                      MAP_SHARED, descriptor, 0);
  if (memory == MAP_FAILED)
    fail("map cleanup state");
  if (close(descriptor) != 0)
    fail("close cleanup state");
  // Shared backing lets the runner inspect referent bytes after SIGABRT,
  // without running unsafe inspection code inside a signal handler.
  target = std::construct_at(static_cast<Resource *>(memory),
                             Resource{{20}, {mode == 0 ? 21 : 99}});
  return target;
}

extern "C" void mettle_test_cleanup_leaf(Leaf *value) {
  trace.push_back(value->tag);
}

extern "C" void mettle_test_cleanup_parent(Resource *value) {
  trace.push_back(1000 + value->first.tag);
}

extern "C" std::int32_t mettle_test_cleanup_result(std::int32_t code,
                                                   const Resource *value) {
  constexpr std::array<std::int32_t, 3> expected{1020, 20, 21};
  bool valid =
      value == target && code == 1 && value->first.tag == 30 &&
      value->second.tag == 31 &&
      trace == std::vector<std::int32_t>(expected.begin(), expected.end());
  if (!valid) {
    std::fprintf(stderr, "catch=%d, installed=(%d,%d), drops:", code,
                 value->first.tag, value->second.tag);
    for (auto tag : trace)
      std::fprintf(stderr, " %d", tag);
    std::fprintf(stderr, "\n");
  }
  if (msync(target, sizeof(Resource), MS_SYNC) != 0)
    fail("sync cleanup state");
  if (munmap(target, sizeof(Resource)) != 0)
    fail("unmap cleanup state");
  target = nullptr;
  return valid ? 0 : 45;
}
