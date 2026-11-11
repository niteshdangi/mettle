#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mettle {
using SourceId = std::uint32_t;
struct Span {
  std::size_t begin = 0;
  std::size_t end = 0;
  SourceId source = 0;
};

struct SyntaxContext {
  std::vector<std::string> scope;
  Span definition;
  // Zero marks ordinary invocation syntax; an empty scope still names root.
  std::uint64_t identity = 0;
};
using SyntaxContextPtr = std::shared_ptr<const SyntaxContext>;

struct Source {
  std::string path;
  std::string text;
  SourceId id = 0;
};

std::optional<std::size_t> invalidUtf8(std::string_view text);
std::string printableUtf8(std::string_view text);
} // namespace mettle
