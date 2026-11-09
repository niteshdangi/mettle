#include "packages/data.h"
#include "support/limits.h"
#include <algorithm>
#include <charconv>
#include <unordered_set>

namespace mettle::packages::data {
namespace {
struct Failure {
  Span span;
  std::string message;
};

bool digit(char c) { return c >= '0' && c <= '9'; }
bool identifierStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
bool identifierPart(char c) { return identifierStart(c) || digit(c); }

void appendUtf8(std::string &out, std::uint32_t code) {
  if (code < 0x80)
    out += static_cast<char>(code);
  else if (code < 0x800) {
    out += static_cast<char>(0xc0 | (code >> 6));
    out += static_cast<char>(0x80 | (code & 0x3f));
  } else if (code < 0x10000) {
    out += static_cast<char>(0xe0 | (code >> 12));
    out += static_cast<char>(0x80 | ((code >> 6) & 0x3f));
    out += static_cast<char>(0x80 | (code & 0x3f));
  } else {
    out += static_cast<char>(0xf0 | (code >> 18));
    out += static_cast<char>(0x80 | ((code >> 12) & 0x3f));
    out += static_cast<char>(0x80 | ((code >> 6) & 0x3f));
    out += static_cast<char>(0x80 | (code & 0x3f));
  }
}

class Parser {
public:
  explicit Parser(const Source &source) : text(source.text), id(source.id) {}

  Value run() {
    skip();
    auto result = peek() == '{' || peek() == '[' ? value(0) : object(0, false);
    skip();
    if (!atEnd())
      fail(pos, "unexpected text after data");
    return result;
  }

private:
  const std::string &text;
  SourceId id;
  std::size_t pos = 0, values = 0;

  bool atEnd() const { return pos == text.size(); }
  char peek() const { return atEnd() ? '\0' : text[pos]; }
  bool at(std::string_view spelling) const {
    return std::string_view(text).substr(pos).starts_with(spelling);
  }
  [[noreturn]] void fail(std::size_t begin, std::string message) const {
    throw Failure{{begin, std::min(text.size(), std::max(pos, begin + 1)), id},
                  std::move(message)};
  }
  void limit(unsigned depth) const {
    if (depth > limits::parserNesting)
      fail(pos, "data nesting limit exceeded");
  }

  bool skip() {
    bool newline = false;
    while (!atEnd()) {
      auto c = peek();
      if (c == ' ' || c == '\t' || c == '\v' || c == '\f' || c == '\r' ||
          c == '\n') {
        newline |= c == '\r' || c == '\n';
        ++pos;
      } else if (at("//")) {
        while (!atEnd() && peek() != '\n' && peek() != '\r')
          ++pos;
      } else if (at("/*")) {
        auto begin = pos;
        pos += 2;
        std::size_t depth = 1;
        while (!atEnd() && depth) {
          if (at("/*")) {
            ++depth;
            pos += 2;
          } else if (at("*/")) {
            --depth;
            pos += 2;
          } else {
            newline |= peek() == '\n' || peek() == '\r';
            ++pos;
          }
        }
        if (depth)
          fail(begin, "unterminated block comment");
      } else
        break;
    }
    return newline;
  }

  void separator(char close) {
    bool newline = skip();
    if (peek() == ',') {
      ++pos;
      skip();
    } else if (!atEnd() && peek() != close && !newline)
      fail(pos, "expected a newline or ',' between entries");
  }

  std::uint32_t hex(std::size_t begin, unsigned count) {
    std::uint32_t code = 0;
    for (unsigned i = 0; i < count; ++i) {
      char c = peek();
      unsigned n = digit(c)               ? static_cast<unsigned>(c - '0')
                   : c >= 'a' && c <= 'f' ? static_cast<unsigned>(c - 'a' + 10)
                   : c >= 'A' && c <= 'F' ? static_cast<unsigned>(c - 'A' + 10)
                                          : 16;
      if (atEnd() || n == 16)
        fail(begin, "invalid hexadecimal escape");
      code = code * 16 + n;
      ++pos;
    }
    return code;
  }

  std::string string() {
    auto begin = pos++;
    std::string result;
    while (!atEnd()) {
      auto c = text[pos++];
      if (c == '"')
        return result;
      if (static_cast<unsigned char>(c) < 0x20)
        fail(begin, "unescaped control character in string");
      if (c != '\\') {
        result += c;
        continue;
      }
      if (atEnd())
        fail(begin, "unterminated string");
      auto escape = text[pos++];
      switch (escape) {
      case 'n':
        result += '\n';
        break;
      case 'r':
        result += '\r';
        break;
      case 't':
        result += '\t';
        break;
      case '0':
        result += '\0';
        break;
      case '\\':
      case '"':
      case '\'':
        result += escape;
        break;
      case 'x': {
        auto code = hex(pos - 2, 2);
        if (code > 0x7f)
          fail(pos - 4, "text byte escape must not exceed 7f");
        result += static_cast<char>(code);
        break;
      }
      case 'u': {
        auto start = pos - 2;
        if (peek() != '{')
          fail(start, "Unicode escape requires '\\u{hex}'");
        ++pos;
        auto digits = pos;
        while (!atEnd() && peek() != '}' && pos - digits <= 6)
          ++pos;
        auto count = pos - digits;
        if (!count || count > 6 || peek() != '}')
          fail(start, "invalid Unicode scalar escape");
        pos = digits;
        auto code = hex(start, static_cast<unsigned>(count));
        ++pos;
        if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))
          fail(start, "invalid Unicode scalar escape");
        appendUtf8(result, code);
        break;
      }
      default:
        fail(pos - 2, "invalid string escape");
      }
    }
    fail(begin, "unterminated string");
  }

  std::string key() {
    if (peek() == '"')
      return string();
    auto begin = pos;
    if (!identifierStart(peek()))
      fail(pos, "expected an identifier or quoted key");
    while (identifierPart(peek()))
      ++pos;
    return text.substr(begin, pos - begin);
  }

  Value object(unsigned depth, bool braced) {
    limit(depth);
    auto begin = pos;
    if (braced)
      ++pos;
    Value result;
    std::unordered_set<std::string> keys;
    skip();
    while (!atEnd() && (!braced || peek() != '}')) {
      auto keyBegin = pos;
      auto name = key();
      Span keySpan{keyBegin, pos, id};
      if (!keys.insert(name).second)
        throw Failure{keySpan, "duplicate key '" + name + "'"};
      skip();
      Value item;
      if (peek() == '{')
        item = value(depth + 1);
      else {
        if (peek() != ':')
          fail(pos, "expected ':' or '{' after key");
        ++pos;
        skip();
        item = value(depth + 1);
      }
      item.key = keySpan;
      result.object.emplace_back(std::move(name), std::move(item));
      separator(braced ? '}' : '\0');
    }
    if (braced) {
      if (atEnd())
        fail(begin, "unterminated object");
      ++pos;
    }
    result.span = {begin, pos, id};
    return result;
  }

  Value value(unsigned depth) {
    limit(depth);
    if (++values > limits::tokens)
      fail(pos, "data value limit exceeded");
    auto begin = pos;
    Value result;
    if (peek() == '{')
      return object(depth, true);
    if (peek() == '"') {
      result.kind = Value::Kind::String;
      result.string = string();
    } else if (peek() == '[') {
      ++pos;
      result.kind = Value::Kind::Array;
      skip();
      while (!atEnd() && peek() != ']') {
        result.array.push_back(value(depth + 1));
        separator(']');
      }
      if (atEnd())
        fail(begin, "unterminated list");
      ++pos;
    } else if (digit(peek()) || peek() == '-') {
      if (peek() == '-')
        ++pos;
      auto start = pos;
      while (digit(peek()))
        ++pos;
      if (start == pos || (text[start] == '0' && pos > start + 1))
        fail(begin, "invalid decimal number");
      bool fractional = false;
      if (peek() == '.') {
        fractional = true;
        auto digits = ++pos;
        while (digit(peek()))
          ++pos;
        if (digits == pos)
          fail(begin, "expected digits after decimal point");
      }
      if (peek() == 'e' || peek() == 'E') {
        fractional = true;
        ++pos;
        if (peek() == '+' || peek() == '-')
          ++pos;
        auto digits = pos;
        while (digit(peek()))
          ++pos;
        if (digits == pos)
          fail(begin, "expected exponent digits");
      }
      result.kind = fractional ? Value::Kind::Number : Value::Kind::Integer;
      result.string = text.substr(begin, pos - begin);
      if (!fractional) {
        auto parsed = std::from_chars(text.data() + begin, text.data() + pos,
                                      result.integer);
        if (parsed.ec != std::errc{})
          fail(begin, "integer out of range");
      }
    } else {
      while (identifierPart(peek()))
        ++pos;
      auto word = std::string_view(text).substr(begin, pos - begin);
      if (word == "true" || word == "false") {
        result.kind = Value::Kind::Boolean;
        result.boolean = word == "true";
      } else if (word == "none")
        result.kind = Value::Kind::None;
      else
        fail(begin, "expected a data value");
    }
    result.span = {begin, pos, id};
    return result;
  }
};
} // namespace

const Value *Value::find(std::string_view name) const {
  for (const auto &entry : object)
    if (entry.first == name)
      return &entry.second;
  return nullptr;
}

std::optional<Value> parse(const Source &source, Diagnostics &diagnostics,
                           const std::string &phase) {
  Diagnostics::SourceContext context(diagnostics, source);
  if (source.text.size() > limits::sourceBytes) {
    diagnostics.error(phase, {0, 0, source.id}, "data file exceeds 1 GiB");
    return std::nullopt;
  }
  if (auto bad = invalidUtf8(source.text)) {
    diagnostics.error(phase, {*bad, *bad + 1, source.id},
                      "file is not valid UTF-8");
    return std::nullopt;
  }
  try {
    return Parser(source).run();
  } catch (const Failure &failure) {
    diagnostics.error(phase, failure.span, failure.message);
    return std::nullopt;
  }
}

std::string quote(std::string_view text) {
  std::string out = "\"";
  for (unsigned char c : text) {
    switch (c) {
    case '"':
      out += "\\\"";
      break;
    case '\\':
      out += "\\\\";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\t':
      out += "\\t";
      break;
    case '\r':
      out += "\\r";
      break;
    default:
      if (c < 0x20) {
        static constexpr char hex[] = "0123456789abcdef";
        out += "\\x";
        out += hex[c >> 4];
        out += hex[c & 0xf];
      } else
        out += static_cast<char>(c);
    }
  }
  return out + '"';
}
} // namespace mettle::packages::data
