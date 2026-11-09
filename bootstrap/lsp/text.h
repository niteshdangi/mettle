#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mettle::lsp {
// A zero-based LSP position: `character` counts UTF-16 code units.
struct Position {
  std::size_t line = 0;
  std::size_t character = 0;
};

// A UTF-8 document with its line table; maps between byte offsets and LSP
// positions. Lines end at `\n`; a `\r` before it is not part of the line's
// columns. Out-of-range positions clamp to the nearest valid offset.
class LineIndex {
public:
  explicit LineIndex(std::string text);
  const std::string &contents() const { return text; }
  std::size_t offset(Position position) const;
  Position position(std::size_t offset) const;
  // The 1-based line and column (in characters) of `offset`.
  std::pair<std::size_t, std::size_t> lineColumn(std::size_t offset) const;

private:
  std::string text;
  std::vector<std::size_t> starts;
  std::size_t lineEnd(std::size_t line) const;
};

// `file:///a%20b.mt` -> `/a b.mt`; any other URI is returned unchanged.
std::string pathFromUri(std::string_view uri);
} // namespace mettle::lsp
