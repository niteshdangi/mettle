#pragma once

#include "documentation/document.h"
#include <string>
#include <vector>

namespace mettle::documentation {
// A block of documentation text: a paragraph (`lines` are its text lines), a
// heading, a bullet list (`lines` are the entries) or a fenced code block
// (`lines` are the raw code lines, `numbers` their source lines, `info` the
// text after the opening fence).
struct Block {
  enum class Kind { Paragraph, Heading, List, Code } kind = Kind::Paragraph;
  std::vector<std::string> lines;
  std::vector<std::size_t> numbers;
  std::string info;
  unsigned level = 0;
};

// Splits documentation text into blocks. The supported markdown is
// deliberately small: paragraphs, `#` headings, `-`/`*` lists and ``` fences;
// inline code is handled by the renderer.
std::vector<Block> blocks(const Doc &doc);
} // namespace mettle::documentation
