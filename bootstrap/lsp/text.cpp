#include "lsp/text.h"
#include <algorithm>

namespace mettle::lsp {
namespace {
std::size_t sequenceLength(unsigned char lead) {
  if (lead < 0xc0)
    return 1;
  if (lead < 0xe0)
    return 2;
  return lead < 0xf0 ? 3 : 4;
}
std::size_t utf16Units(unsigned char lead) { return lead >= 0xf0 ? 2 : 1; }
int hexValue(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}
} // namespace

LineIndex::LineIndex(std::string contents) : text(std::move(contents)) {
  starts.push_back(0);
  for (std::size_t i = 0; i < text.size(); ++i)
    if (text[i] == '\n')
      starts.push_back(i + 1);
}

std::size_t LineIndex::lineEnd(std::size_t line) const {
  auto end = line + 1 < starts.size() ? starts[line + 1] - 1 : text.size();
  if (end > starts[line] && text[end - 1] == '\r')
    --end;
  return end;
}

std::size_t LineIndex::offset(Position position) const {
  if (position.line >= starts.size())
    return text.size();
  auto at = starts[position.line];
  auto end = lineEnd(position.line);
  std::size_t units = 0;
  while (at < end && units < position.character) {
    auto lead = static_cast<unsigned char>(text[at]);
    units += utf16Units(lead);
    at = std::min(end, at + sequenceLength(lead));
  }
  return at;
}

Position LineIndex::position(std::size_t offset) const {
  offset = std::min(offset, text.size());
  auto line = static_cast<std::size_t>(
      std::upper_bound(starts.begin(), starts.end(), offset) - starts.begin() -
      1);
  std::size_t units = 0;
  for (auto at = starts[line]; at < offset;) {
    auto lead = static_cast<unsigned char>(text[at]);
    units += utf16Units(lead);
    at += sequenceLength(lead);
  }
  return {line, units};
}

std::pair<std::size_t, std::size_t>
LineIndex::lineColumn(std::size_t offset) const {
  offset = std::min(offset, text.size());
  auto line = static_cast<std::size_t>(
      std::upper_bound(starts.begin(), starts.end(), offset) - starts.begin() -
      1);
  std::size_t column = 1;
  for (auto at = starts[line]; at < offset; ++at)
    if ((static_cast<unsigned char>(text[at]) & 0xc0) != 0x80)
      ++column;
  return {line + 1, column};
}

std::string pathFromUri(std::string_view uri) {
  constexpr std::string_view scheme = "file://";
  if (!uri.starts_with(scheme))
    return std::string(uri);
  auto rest = uri.substr(scheme.size());
  // `file://host/path`: the authority is not part of the path.
  if (!rest.empty() && rest.front() != '/') {
    auto slash = rest.find('/');
    rest = slash == std::string_view::npos ? std::string_view()
                                           : rest.substr(slash);
  }
  std::string path;
  for (std::size_t i = 0; i < rest.size(); ++i) {
    if (rest[i] == '%' && i + 2 < rest.size() && hexValue(rest[i + 1]) >= 0 &&
        hexValue(rest[i + 2]) >= 0) {
      path +=
          static_cast<char>(hexValue(rest[i + 1]) * 16 + hexValue(rest[i + 2]));
      i += 2;
    } else {
      path += rest[i];
    }
  }
  return path;
}
} // namespace mettle::lsp
