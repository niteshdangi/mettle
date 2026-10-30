#include "documentation/markdown.h"
#include <string_view>

namespace mettle::documentation {
namespace {
std::string_view trimmed(std::string_view text) {
  auto begin = text.find_first_not_of(" \t");
  if (begin == std::string_view::npos)
    return {};
  return text.substr(begin, text.find_last_not_of(" \t") - begin + 1);
}
} // namespace

std::vector<Block> blocks(const Doc &doc) {
  std::vector<Block> result;
  Block current;
  bool open = false;
  auto flush = [&] {
    if (open)
      result.push_back(std::move(current));
    current = {};
    open = false;
  };
  for (std::size_t i = 0; i < doc.lines.size(); ++i) {
    const auto &line = doc.lines[i];
    auto text = trimmed(line);
    if (text.starts_with("```")) {
      flush();
      Block code;
      code.kind = Block::Kind::Code;
      code.info = std::string(trimmed(text.substr(3)));
      for (++i; i < doc.lines.size() && trimmed(doc.lines[i]) != "```"; ++i) {
        code.lines.push_back(doc.lines[i]);
        code.numbers.push_back(doc.numbers[i]);
      }
      result.push_back(std::move(code));
      continue;
    }
    if (text.empty()) {
      flush();
      continue;
    }
    std::size_t hashes = text.find_first_not_of('#');
    if (hashes != 0 && hashes <= 6 && hashes < text.size() &&
        text[hashes] == ' ') {
      flush();
      Block heading;
      heading.kind = Block::Kind::Heading;
      heading.level = static_cast<unsigned>(hashes);
      heading.lines.emplace_back(trimmed(text.substr(hashes)));
      result.push_back(std::move(heading));
      continue;
    }
    if (text.starts_with("- ") || text.starts_with("* ")) {
      if (!open || current.kind != Block::Kind::List) {
        flush();
        current.kind = Block::Kind::List;
        open = true;
      }
      current.lines.emplace_back(trimmed(text.substr(2)));
      continue;
    }
    if (open && current.kind == Block::Kind::List && line.starts_with(' ')) {
      current.lines.back() += ' ';
      current.lines.back() += text;
      continue;
    }
    if (!open || current.kind != Block::Kind::Paragraph) {
      flush();
      current.kind = Block::Kind::Paragraph;
      open = true;
    }
    current.lines.emplace_back(text);
  }
  flush();
  return result;
}
} // namespace mettle::documentation
