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

namespace mettle {
namespace {
void appendScalar(std::string &out, std::uint32_t value) {
  if (value < 0x80) {
    out.push_back(static_cast<char>(value));
  } else if (value < 0x800) {
    out.push_back(static_cast<char>(0xc0 | (value >> 6)));
    out.push_back(static_cast<char>(0x80 | (value & 0x3f)));
  } else if (value < 0x10000) {
    out.push_back(static_cast<char>(0xe0 | (value >> 12)));
    out.push_back(static_cast<char>(0x80 | ((value >> 6) & 0x3f)));
    out.push_back(static_cast<char>(0x80 | (value & 0x3f)));
  } else {
    out.push_back(static_cast<char>(0xf0 | (value >> 18)));
    out.push_back(static_cast<char>(0x80 | ((value >> 12) & 0x3f)));
    out.push_back(static_cast<char>(0x80 | ((value >> 6) & 0x3f)));
    out.push_back(static_cast<char>(0x80 | (value & 0x3f)));
  }
}
} // namespace

std::optional<std::string> textLiteral(std::string_view text,
                                       Diagnostics &diagnostics, Span span) {
  auto fail = [&](std::string message) -> std::optional<std::string> {
    diagnostics.error("lex", span, std::move(message));
    return std::nullopt;
  };
  const bool bytes = !text.empty() && text.front() == 'b';
  if (bytes)
    text.remove_prefix(1);
  if (text.starts_with("\"\"\"")) {
    if (bytes)
      return fail("byte text blocks are reserved");
    if (text.size() < 6 || !text.ends_with("\"\"\""))
      return fail("unterminated text block");
    text = text.substr(3, text.size() - 6);
    constexpr auto terminators = std::string_view("\r\n");
    auto first = text.find_first_of(terminators);
    if (first == std::string_view::npos)
      return fail("unterminated text block");
    text.remove_prefix(first + (text.compare(first, 2, "\r\n") == 0 ? 2 : 1));
    auto last = text.find_last_of(terminators);
    if (last == std::string_view::npos)
      return std::string();
    auto indent = text.substr(last + 1);
    if (indent.find_first_not_of(" \t") != std::string_view::npos)
      return fail("unterminated text block");
    auto content = text.substr(0, last);
    if (content.ends_with('\r') && text[last] == '\n')
      content.remove_suffix(1);
    std::string result;
    for (bool firstLine = true; true; firstLine = false) {
      auto end = content.find_first_of(terminators);
      auto line = content.substr(0, end);
      if (!firstLine)
        result.push_back('\n');
      if (line.starts_with(indent))
        line.remove_prefix(indent.size());
      else if (line.find_first_not_of(" \t") == std::string_view::npos)
        line = {};
      else
        return fail("text block line is indented less than its closing "
                    "\"\"\"");
      result.append(line);
      if (end == std::string_view::npos)
        break;
      content.remove_prefix(end +
                            (content.compare(end, 2, "\r\n") == 0 ? 2 : 1));
    }
    return result;
  }
  if (text.size() < 2 || text.front() != '"' || text.back() != '"')
    return fail("unterminated text literal");
  text = text.substr(1, text.size() - 2);
  std::string result;
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] != '\\') {
      if (bytes && static_cast<unsigned char>(text[i]) >= 0x80)
        return fail("byte text must contain only ASCII characters");
      result.push_back(text[i]);
      continue;
    }
    if (++i == text.size())
      return fail("incomplete text escape");
    switch (text[i]) {
    case 'n':
      result.push_back('\n');
      break;
    case 'r':
      result.push_back('\r');
      break;
    case 't':
      result.push_back('\t');
      break;
    case '0':
      result.push_back('\0');
      break;
    case '\\':
    case '"':
    case '\'':
      result.push_back(text[i]);
      break;
    case 'x': {
      std::uint32_t value = 0;
      auto digits = text.substr(i + 1, 2);
      auto parsed = std::from_chars(digits.data(),
                                    digits.data() + digits.size(), value, 16);
      if (digits.size() != 2 || parsed.ec != std::errc{} ||
          parsed.ptr != digits.data() + 2 || (!bytes && value > 0x7f))
        return fail(bytes ? "byte escape requires two hexadecimal digits"
                          : "text byte escape requires two hexadecimal digits "
                            "no greater than 7f");
      result.push_back(static_cast<char>(value));
      i += 2;
      break;
    }
    case 'u': {
      if (bytes)
        return fail("invalid text escape");
      auto close = text.find('}', i);
      if (i + 1 >= text.size() || text[i + 1] != '{' ||
          close == std::string_view::npos)
        return fail("Unicode escape requires '\\u{hex}'");
      std::uint32_t value = 0;
      auto digits = text.substr(i + 2, close - i - 2);
      auto parsed = std::from_chars(digits.data(),
                                    digits.data() + digits.size(), value, 16);
      if (digits.empty() || digits.size() > 6 || parsed.ec != std::errc{} ||
          parsed.ptr != digits.data() + digits.size() || value > 0x10ffff ||
          (value >= 0xd800 && value <= 0xdfff))
        return fail("invalid Unicode scalar escape");
      appendScalar(result, value);
      i = close;
      break;
    }
    default:
      return fail("invalid text escape");
    }
  }
  return result;
}
} // namespace mettle
