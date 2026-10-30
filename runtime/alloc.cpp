#include "alloc.h"

#include <cstdint>
#include <cstdlib>

namespace {
// malloc already honors the fundamental alignment; larger requests use the
// aligned entry point, whose result is also released with free.
constexpr std::size_t fundamentalAlignment = alignof(std::max_align_t);

void *allocateAligned(std::size_t size, std::size_t align) {
  if (align <= fundamentalAlignment)
    return std::malloc(size);
  void *result = nullptr;
  if (posix_memalign(&result, align, size) != 0)
    return nullptr;
  return result;
}
} // namespace

extern "C" std::uint8_t *mettle_rt_alloc(std::size_t size, std::size_t align) {
  return static_cast<std::uint8_t *>(allocateAligned(size, align));
}

extern "C" void mettle_rt_dealloc(std::uint8_t *pointer, std::size_t,
                                  std::size_t) {
  std::free(pointer);
}

extern "C" std::uint8_t *mettle_rt_realloc(std::uint8_t *pointer,
                                           std::size_t oldSize,
                                           std::size_t align,
                                           std::size_t newSize) {
  if (align <= fundamentalAlignment)
    return static_cast<std::uint8_t *>(std::realloc(pointer, newSize));
  auto *fresh = static_cast<std::uint8_t *>(allocateAligned(newSize, align));
  if (fresh == nullptr)
    return nullptr;
  auto count = oldSize < newSize ? oldSize : newSize;
  for (std::size_t i = 0; i < count; ++i)
    fresh[i] = pointer[i];
  std::free(pointer);
  return fresh;
}
