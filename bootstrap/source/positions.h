#pragma once

#include "source/source.h"

namespace mettle {
class SourcePositions {
public:
  explicit SourcePositions(std::string_view text);
  SourcePosition position(std::size_t offset) const;

private:
  std::size_t size;
  std::vector<std::size_t> lines{0}, continuations;
};
} // namespace mettle
