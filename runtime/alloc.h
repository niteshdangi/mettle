#pragma once

#include <cstddef>
#include <cstdint>

// Global-allocator hook of the native `alloc` library. Hosted builds link this
// runtime; freestanding builds provide the same three symbols themselves.
// Allocation returns null on exhaustion; deallocation and reallocation receive
// the original size and alignment. Sizes are never zero.
extern "C" {
std::uint8_t *mettle_rt_alloc(std::size_t size, std::size_t align);
void mettle_rt_dealloc(std::uint8_t *pointer, std::size_t size,
                       std::size_t align);
std::uint8_t *mettle_rt_realloc(std::uint8_t *pointer, std::size_t oldSize,
                                std::size_t align, std::size_t newSize);
}
