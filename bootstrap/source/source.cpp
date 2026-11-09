#include "source/source.h"

namespace mettle {
namespace {
std::size_t width(std::string_view text, std::size_t offset) {
  auto byte = [&](std::size_t index) {
    return static_cast<unsigned char>(text[index]);
  };
  unsigned first = byte(offset);
  if (first < 128)
    return 1;
  unsigned count = first >= 0xc2 && first <= 0xdf   ? 2
                   : first >= 0xe0 && first <= 0xef ? 3
                   : first >= 0xf0 && first <= 0xf4 ? 4
                                                    : 0;
  if (!count || offset + count > text.size())
    return 0;
  for (unsigned i = 1; i < count; ++i)
    if ((byte(offset + i) & 0xc0) != 0x80)
      return 0;
  unsigned second = byte(offset + 1);
  if ((first == 0xe0 && second < 0xa0) || (first == 0xed && second >= 0xa0) ||
      (first == 0xf0 && second < 0x90) || (first == 0xf4 && second >= 0x90))
    return 0;
  return count;
}
} // namespace
std::optional<std::size_t> invalidUtf8(std::string_view text) {
  for (std::size_t offset = 0; offset < text.size();) {
    auto count = width(text, offset);
    if (!count)
      return offset;
    offset += count;
  }
  return std::nullopt;
}
std::string printableUtf8(std::string_view text) {
  std::string result;
  for (std::size_t offset = 0; offset < text.size();) {
    auto count = width(text, offset);
    if (!count) {
      result += '?';
      ++offset;
    } else {
      result.append(text.substr(offset, count));
      offset += count;
    }
  }
  return result;
}
} // namespace mettle
