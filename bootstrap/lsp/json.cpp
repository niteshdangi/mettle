#include "lsp/json.h"
#include "source/source.h"
#include "support/limits.h"
#include <charconv>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace mettle::lsp {
Json Json::boolean(bool value) {
  Json result;
  result.kind = Type::Boolean;
  result.flag = value;
  return result;
}
Json Json::integer(std::int64_t value) {
  Json result;
  result.kind = Type::Number;
  result.exact = true;
  result.whole = value;
  result.real = static_cast<double>(value);
  return result;
}
Json Json::number(double value) {
  Json result;
  result.kind = Type::Number;
  result.real = value;
  return result;
}
Json Json::string(std::string value) {
  Json result;
  result.kind = Type::String;
  result.text = std::move(value);
  return result;
}
Json Json::array(Array value) {
  Json result;
  result.kind = Type::Array;
  result.elements = std::move(value);
  return result;
}
Json Json::object(Object value) {
  Json result;
  result.kind = Type::Object;
  result.members = std::move(value);
  return result;
}

std::optional<bool> Json::asBoolean() const {
  if (kind != Type::Boolean)
    return std::nullopt;
  return flag;
}
std::optional<std::int64_t> Json::asInteger() const {
  if (kind != Type::Number)
    return std::nullopt;
  if (exact)
    return whole;
  if (std::trunc(real) == real && std::fabs(real) < 9.0e18)
    return static_cast<std::int64_t>(real);
  return std::nullopt;
}
const std::string *Json::asString() const {
  return kind == Type::String ? &text : nullptr;
}
const Json::Array *Json::asArray() const {
  return kind == Type::Array ? &elements : nullptr;
}
const Json::Object *Json::asObject() const {
  return kind == Type::Object ? &members : nullptr;
}
const Json *Json::find(std::string_view key) const {
  if (kind != Type::Object)
    return nullptr;
  for (const auto &member : members)
    if (member.first == key)
      return &member.second;
  return nullptr;
}
void Json::add(std::string key, Json value) {
  members.emplace_back(std::move(key), std::move(value));
}
void Json::push(Json value) { elements.push_back(std::move(value)); }

namespace {
void appendUtf8(std::string &out, std::uint32_t code) {
  if (code < 0x80) {
    out += static_cast<char>(code);
  } else if (code < 0x800) {
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

void quote(std::string &out, const std::string &text) {
  out += '"';
  for (unsigned char c : text) {
    switch (c) {
    case '"':
      out += "\\\"";
      break;
    case '\\':
      out += "\\\\";
      break;
    case '\b':
      out += "\\b";
      break;
    case '\f':
      out += "\\f";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\r':
      out += "\\r";
      break;
    case '\t':
      out += "\\t";
      break;
    default:
      if (c < 0x20) {
        char buffer[8];
        std::snprintf(buffer, sizeof buffer, "\\u%04x", c);
        out += buffer;
      } else {
        out += static_cast<char>(c);
      }
    }
  }
  out += '"';
}

class Parser {
public:
  explicit Parser(std::string_view text) : text(text) {}
  std::optional<Json> document() {
    if (invalidUtf8(text))
      return std::nullopt;
    auto value = parseValue(0);
    skip();
    if (!value || position != text.size())
      return std::nullopt;
    return value;
  }

private:
  std::string_view text;
  std::size_t position = 0;

  void skip() {
    while (position < text.size() &&
           (text[position] == ' ' || text[position] == '\t' ||
            text[position] == '\n' || text[position] == '\r'))
      ++position;
  }
  bool consume(char expected) {
    skip();
    if (position < text.size() && text[position] == expected) {
      ++position;
      return true;
    }
    return false;
  }
  bool literal(std::string_view word) {
    if (text.substr(position, word.size()) != word)
      return false;
    position += word.size();
    return true;
  }
  std::optional<std::uint32_t> hex4() {
    if (position + 4 > text.size())
      return std::nullopt;
    std::uint32_t value = 0;
    for (int i = 0; i < 4; ++i) {
      char c = text[position + static_cast<std::size_t>(i)];
      value <<= 4;
      if (c >= '0' && c <= '9')
        value |= static_cast<std::uint32_t>(c - '0');
      else if (c >= 'a' && c <= 'f')
        value |= static_cast<std::uint32_t>(c - 'a' + 10);
      else if (c >= 'A' && c <= 'F')
        value |= static_cast<std::uint32_t>(c - 'A' + 10);
      else
        return std::nullopt;
    }
    position += 4;
    return value;
  }
  std::optional<std::string> parseString() {
    if (!consume('"'))
      return std::nullopt;
    std::string out;
    while (position < text.size()) {
      auto c = static_cast<unsigned char>(text[position++]);
      if (c == '"')
        return out;
      if (c < 0x20)
        return std::nullopt;
      if (c != '\\') {
        out += static_cast<char>(c);
        continue;
      }
      if (position >= text.size())
        return std::nullopt;
      char escape = text[position++];
      switch (escape) {
      case '"':
      case '\\':
      case '/':
        out += escape;
        break;
      case 'b':
        out += '\b';
        break;
      case 'f':
        out += '\f';
        break;
      case 'n':
        out += '\n';
        break;
      case 'r':
        out += '\r';
        break;
      case 't':
        out += '\t';
        break;
      case 'u': {
        auto unit = hex4();
        if (!unit)
          return std::nullopt;
        std::uint32_t code = *unit;
        if (code >= 0xd800 && code < 0xdc00) {
          // A high surrogate needs its low half; a lone one is replaced.
          auto saved = position;
          std::optional<std::uint32_t> low;
          if (literal("\\u"))
            low = hex4();
          if (low && *low >= 0xdc00 && *low < 0xe000) {
            code = 0x10000 + ((code - 0xd800) << 10) + (*low - 0xdc00);
          } else {
            position = saved;
            code = 0xfffd;
          }
        } else if (code >= 0xdc00 && code < 0xe000) {
          code = 0xfffd;
        }
        appendUtf8(out, code);
        break;
      }
      default:
        return std::nullopt;
      }
    }
    return std::nullopt;
  }
  std::optional<Json> parseNumber() {
    auto begin = position;
    bool integral = true;
    if (position < text.size() && text[position] == '-')
      ++position;
    auto digits = [&] {
      auto start = position;
      while (position < text.size() && text[position] >= '0' &&
             text[position] <= '9')
        ++position;
      return position - start;
    };
    if (position < text.size() && text[position] == '0')
      ++position;
    else if (!digits())
      return std::nullopt;
    if (position < text.size() && text[position] == '.') {
      integral = false;
      ++position;
      if (!digits())
        return std::nullopt;
    }
    if (position < text.size() &&
        (text[position] == 'e' || text[position] == 'E')) {
      integral = false;
      ++position;
      if (position < text.size() &&
          (text[position] == '+' || text[position] == '-'))
        ++position;
      if (!digits())
        return std::nullopt;
    }
    auto spelled = text.substr(begin, position - begin);
    if (integral) {
      std::int64_t value = 0;
      auto [end, error] = std::from_chars(
          spelled.data(), spelled.data() + spelled.size(), value);
      if (error == std::errc() && end == spelled.data() + spelled.size())
        return Json::integer(value);
    }
    return Json::number(std::strtod(std::string(spelled).c_str(), nullptr));
  }
  std::optional<Json> parseValue(unsigned depth) {
    if (depth > limits::syntaxDepth)
      return std::nullopt;
    skip();
    if (position >= text.size())
      return std::nullopt;
    char c = text[position];
    if (c == '{') {
      ++position;
      Json result = Json::object();
      if (consume('}'))
        return result;
      do {
        skip();
        auto key = parseString();
        if (!key || !consume(':'))
          return std::nullopt;
        auto value = parseValue(depth + 1);
        if (!value)
          return std::nullopt;
        result.add(std::move(*key), std::move(*value));
      } while (consume(','));
      if (!consume('}'))
        return std::nullopt;
      return result;
    }
    if (c == '[') {
      ++position;
      Json result = Json::array();
      if (consume(']'))
        return result;
      do {
        auto value = parseValue(depth + 1);
        if (!value)
          return std::nullopt;
        result.push(std::move(*value));
      } while (consume(','));
      if (!consume(']'))
        return std::nullopt;
      return result;
    }
    if (c == '"') {
      auto value = parseString();
      if (!value)
        return std::nullopt;
      return Json::string(std::move(*value));
    }
    if (literal("true"))
      return Json::boolean(true);
    if (literal("false"))
      return Json::boolean(false);
    if (literal("null"))
      return Json();
    return parseNumber();
  }
};
} // namespace

void Json::write(std::string &out) const {
  switch (kind) {
  case Type::Null:
    out += "null";
    break;
  case Type::Boolean:
    out += flag ? "true" : "false";
    break;
  case Type::Number:
    if (exact) {
      out += std::to_string(whole);
    } else if (std::isfinite(real)) {
      char buffer[32];
      std::snprintf(buffer, sizeof buffer, "%.17g", real);
      out += buffer;
    } else {
      out += "null";
    }
    break;
  case Type::String:
    quote(out, text);
    break;
  case Type::Array: {
    out += '[';
    bool first = true;
    for (const auto &element : elements) {
      if (!first)
        out += ',';
      first = false;
      element.write(out);
    }
    out += ']';
    break;
  }
  case Type::Object: {
    out += '{';
    bool first = true;
    for (const auto &member : members) {
      if (!first)
        out += ',';
      first = false;
      quote(out, member.first);
      out += ':';
      member.second.write(out);
    }
    out += '}';
    break;
  }
  }
}
std::string Json::dump() const {
  std::string out;
  write(out);
  return out;
}
std::optional<Json> Json::parse(std::string_view text) {
  return Parser(text).document();
}
} // namespace mettle::lsp
