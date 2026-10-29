#include "syntax/lexer.h"
#include <charconv>

namespace mettle {
std::optional<std::uint32_t> characterLiteral(std::string_view text, bool byte,
                                              Diagnostics &diagnostics,
                                              Span span) {
  auto fail = [&](std::string message) -> std::optional<std::uint32_t> {
    diagnostics.error("lex", span, std::move(message));
    return std::nullopt;
  };
  if (byte)
    text.remove_prefix(1);
  if (text.size() < 3 || text.front() != '\'' || text.back() != '\'')
    return fail("unterminated character literal");
  text.remove_prefix(1);
  text.remove_suffix(1);
  std::uint32_t value = 0;
  if (text.front() == '\\') {
    if (text.size() < 2)
      return fail("incomplete character escape");
    auto escape = text[1];
    if (escape == 'u' && !byte) {
      if (text.size() < 5 || text[2] != '{' || text.back() != '}')
        return fail("Unicode escape requires '\\u{hex}'");
      auto digits = text.substr(3, text.size() - 4);
      auto parsed = std::from_chars(digits.data(),
                                    digits.data() + digits.size(), value, 16);
      if (digits.empty() || digits.size() > 6 || parsed.ec != std::errc{} ||
          parsed.ptr != digits.data() + digits.size())
        return fail("invalid Unicode scalar escape");
    } else if (escape == 'x' && byte) {
      if (text.size() != 4)
        return fail("byte escape requires two hexadecimal digits");
      auto digits = text.substr(2);
      auto parsed = std::from_chars(digits.data(),
                                    digits.data() + digits.size(), value, 16);
      if (parsed.ec != std::errc{} ||
          parsed.ptr != digits.data() + digits.size())
        return fail("invalid byte escape");
    } else {
      if (text.size() != 2)
        return fail("character literal must contain exactly one scalar");
      if (escape == 'n')
        value = '\n';
      else if (escape == 'r')
        value = '\r';
      else if (escape == 't')
        value = '\t';
      else if (escape == '0')
        value = 0;
      else if (escape == '\\' || escape == '\'')
        value = escape;
      else
        return fail("invalid character escape");
    }
  } else {
    unsigned char first = text[0];
    std::size_t width = first < 0x80   ? 1
                        : first < 0xe0 ? 2
                        : first < 0xf0 ? 3
                                       : 4;
    if (text.size() != width)
      return fail("character literal must contain exactly one scalar");
    if (byte && width != 1)
      return fail("byte literal must contain exactly one ASCII byte");
    value = width == 1 ? first : first & (0x7f >> width);
    for (std::size_t i = 1; i < width; ++i)
      value = (value << 6) | (static_cast<unsigned char>(text[i]) & 0x3f);
  }
  if (value > (byte ? 255u : 0x10ffffu) ||
      (!byte && value >= 0xd800 && value <= 0xdfff))
    return fail("literal is not a valid Unicode scalar");
  return value;
}
} // namespace mettle
