#pragma once
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

namespace mettle {
struct Span {
  std::size_t begin = 0;
  std::size_t end = 0;
};

struct Source {
  std::string path;
  std::string text;
};

std::optional<std::size_t> invalidUtf8(std::string_view text);
std::string printableUtf8(std::string_view text);
} // namespace mettle
