#include "packages/toml.h"
#include <algorithm>
#include <cctype>
#include <set>

namespace mettle::packages::toml {
namespace {
struct Failure {
  Span span;
  std::string message;
};

bool bareKeyCharacter(char c) {
  return std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-';
}

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
    root.span = {0, text.size(), id};
    Value *current = &root;
    while (true) {
      skipBlank();
      if (atEnd())
        break;
      if (peek() == '[') {
        current = header();
        endOfLine();
      } else {
        keyValue(*current);
        endOfLine();
      }
    }
    return std::move(root);
  }

private:
  const std::string &text;
  SourceId id;
  std::size_t pos = 0;
  Value root;
  std::set<std::string> headers;

  bool atEnd() const { return pos >= text.size(); }
  char peek() const { return atEnd() ? '\0' : text[pos]; }
  Span at(std::size_t begin) const {
    return {begin, std::max(pos, begin + 1), id};
  }
  [[noreturn]] void fail(std::size_t begin, std::string message) const {
    throw Failure{at(begin), std::move(message)};
  }

  void skipSpace() {
    while (peek() == ' ' || peek() == '\t')
      ++pos;
  }
  void skipComment() {
    if (peek() == '#')
      while (!atEnd() && peek() != '\n')
        ++pos;
  }
  void skipBlank() {
    while (true) {
      skipSpace();
      skipComment();
      if (peek() == '\n' || peek() == '\r')
        ++pos;
      else
        return;
    }
  }
  void endOfLine() {
    skipSpace();
    skipComment();
    if (atEnd())
      return;
    if (peek() == '\r' && pos + 1 < text.size() && text[pos + 1] == '\n')
      ++pos;
    if (peek() != '\n')
      fail(pos, "expected end of line after value");
    ++pos;
  }

  std::string key() {
    skipSpace();
    auto begin = pos;
    if (peek() == '"' || peek() == '\'')
      return stringLiteral();
    while (bareKeyCharacter(peek()))
      ++pos;
    if (pos == begin)
      fail(begin, "expected a key");
    return text.substr(begin, pos - begin);
  }

  std::vector<std::pair<std::string, Span>> keyPath() {
    std::vector<std::pair<std::string, Span>> path;
    while (true) {
      skipSpace();
      auto begin = pos;
      auto name = key();
      path.emplace_back(std::move(name), Span{begin, pos, id});
      skipSpace();
      if (peek() != '.')
        return path;
      ++pos;
    }
  }

  static Value *member(Value &table, const std::string &name) {
    for (auto &entry : table.table)
      if (entry.first == name)
        return &entry.second;
    return nullptr;
  }

  // Descends into `name`, creating an implicit table; an array of tables
  // continues in its last element.
  Value &descend(Value &table, const std::string &name, Span keySpan) {
    auto *found = member(table, name);
    if (!found) {
      Value created;
      created.span = created.key = keySpan;
      table.table.emplace_back(name, std::move(created));
      return table.table.back().second;
    }
    if (found->kind == Value::Kind::Array && !found->array.empty() &&
        found->array.back().kind == Value::Kind::Table)
      return found->array.back();
    if (found->kind != Value::Kind::Table)
      throw Failure{keySpan, "'" + name + "' is not a table"};
    return *found;
  }

  Value *header() {
    auto begin = pos;
    ++pos;
    bool array = peek() == '[';
    if (array)
      ++pos;
    auto path = keyPath();
    skipSpace();
    for (int i = 0; i < (array ? 2 : 1); ++i) {
      if (peek() != ']')
        fail(pos, "expected ']' to close the table header");
      ++pos;
    }
    std::string joined;
    for (const auto &part : path)
      joined += part.first + '\n';
    Value *table = &root;
    for (std::size_t i = 0; i + 1 < path.size(); ++i)
      table = &descend(*table, path[i].first, path[i].second);
    const auto &last = path.back();
    if (array) {
      auto *found = member(*table, last.first);
      if (!found) {
        Value created;
        created.kind = Value::Kind::Array;
        created.span = created.key = last.second;
        table->table.emplace_back(last.first, std::move(created));
        found = &table->table.back().second;
      }
      if (found->kind != Value::Kind::Array ||
          (!found->array.empty() &&
           found->array.front().kind != Value::Kind::Table))
        throw Failure{last.second,
                      "'" + last.first + "' is not an array of tables"};
      Value element;
      element.span = element.key = Span{begin, pos, id};
      found->array.push_back(std::move(element));
      headers.clear();
      return &found->array.back();
    }
    if (!headers.insert(joined).second)
      throw Failure{Span{begin, pos, id},
                    "table '" + last.first + "' is defined more than once"};
    auto *found = member(*table, last.first);
    if (found && found->kind != Value::Kind::Table)
      throw Failure{last.second, "'" + last.first + "' is already a value"};
    return &descend(*table, last.first, last.second);
  }

  void keyValue(Value &table) {
    auto path = keyPath();
    skipSpace();
    if (peek() != '=')
      fail(pos, "expected '=' after the key");
    ++pos;
    Value *target = &table;
    for (std::size_t i = 0; i + 1 < path.size(); ++i)
      target = &descend(*target, path[i].first, path[i].second);
    const auto &last = path.back();
    if (member(*target, last.first))
      throw Failure{last.second, "duplicate key '" + last.first + "'"};
    auto value = this->value();
    value.key = last.second;
    target->table.emplace_back(last.first, std::move(value));
  }

  std::string stringLiteral() {
    auto begin = pos;
    char quote = peek();
    ++pos;
    if (peek() == quote && pos + 1 < text.size() && text[pos + 1] == quote)
      fail(begin, "multi-line strings are not supported");
    std::string out;
    while (true) {
      if (atEnd() || peek() == '\n')
        fail(begin, "unterminated string");
      char c = text[pos++];
      if (c == quote)
        return out;
      if (quote == '"' && c == '\\') {
        if (atEnd())
          fail(begin, "unterminated string");
        char escape = text[pos++];
        switch (escape) {
        case 'b':
          out += '\b';
          break;
        case 't':
          out += '\t';
          break;
        case 'n':
          out += '\n';
          break;
        case 'f':
          out += '\f';
          break;
        case 'r':
          out += '\r';
          break;
        case '"':
          out += '"';
          break;
        case '\\':
          out += '\\';
          break;
        case 'u':
        case 'U': {
          std::size_t count = escape == 'u' ? 4 : 8;
          std::uint32_t code = 0;
          for (std::size_t i = 0; i < count; ++i) {
            if (atEnd() || !std::isxdigit(static_cast<unsigned char>(peek())))
              fail(pos - 1, "invalid unicode escape");
            char digit = text[pos++];
            code = code * 16 +
                   (std::isdigit(static_cast<unsigned char>(digit))
                        ? digit - '0'
                        : std::tolower(static_cast<unsigned char>(digit)) -
                              'a' + 10);
          }
          if (code > 0x10ffff || (code >= 0xd800 && code < 0xe000))
            fail(pos - 1, "invalid unicode scalar value in escape");
          appendUtf8(out, code);
          break;
        }
        default:
          fail(pos - 2, "unknown string escape");
        }
      } else
        out += c;
    }
  }

  Value value() {
    skipSpace();
    auto begin = pos;
    Value result;
    char c = peek();
    if (c == '"' || c == '\'') {
      result.kind = Value::Kind::String;
      result.string = stringLiteral();
    } else if (c == '[') {
      ++pos;
      result.kind = Value::Kind::Array;
      while (true) {
        skipBlank();
        if (peek() == ']') {
          ++pos;
          break;
        }
        if (atEnd())
          fail(begin, "unterminated array");
        result.array.push_back(value());
        skipBlank();
        if (peek() == ',')
          ++pos;
        else if (peek() != ']')
          fail(pos, "expected ',' or ']' in the array");
      }
    } else if (c == '{') {
      ++pos;
      result.kind = Value::Kind::Table;
      skipSpace();
      if (peek() == '}')
        ++pos;
      else
        while (true) {
          keyValue(result);
          skipSpace();
          if (peek() == ',') {
            ++pos;
            skipSpace();
          } else if (peek() == '}') {
            ++pos;
            break;
          } else
            fail(pos, "expected ',' or '}' in the inline table");
        }
    } else if (text.compare(pos, 4, "true") == 0 &&
               !bareKeyCharacter(pos + 4 < text.size() ? text[pos + 4] : ' ')) {
      pos += 4;
      result.kind = Value::Kind::Boolean;
      result.boolean = true;
    } else if (text.compare(pos, 5, "false") == 0 &&
               !bareKeyCharacter(pos + 5 < text.size() ? text[pos + 5] : ' ')) {
      pos += 5;
      result.kind = Value::Kind::Boolean;
    } else if (std::isdigit(static_cast<unsigned char>(c)) || c == '-' ||
               c == '+') {
      bool negative = c == '-';
      if (c == '-' || c == '+')
        ++pos;
      auto digits = pos;
      std::int64_t number = 0;
      while (std::isdigit(static_cast<unsigned char>(peek())) ||
             (peek() == '_' && pos > digits)) {
        if (peek() != '_') {
          int digit = peek() - '0';
          if (number > (INT64_MAX - digit) / 10)
            fail(begin, "integer out of range");
          number = number * 10 + digit;
        }
        ++pos;
      }
      if (pos == digits || peek() == '.' || peek() == 'e' || peek() == 'E' ||
          peek() == ':' || (peek() == '-' && pos - digits == 4))
        fail(begin, "only integer, string, boolean, array and table values "
                    "are supported");
      result.kind = Value::Kind::Integer;
      result.integer = negative ? -number : number;
    } else
      fail(begin, "expected a value");
    result.span = Span{begin, pos, id};
    return result;
  }
};
} // namespace

const Value *Value::find(std::string_view name) const {
  for (const auto &entry : table)
    if (entry.first == name)
      return &entry.second;
  return nullptr;
}

std::optional<Value> parse(const Source &source, Diagnostics &diagnostics,
                           const std::string &phase) {
  Diagnostics::SourceContext context(diagnostics, source);
  if (auto bad = invalidUtf8(source.text)) {
    diagnostics.error(phase, Span{*bad, *bad + 1, source.id},
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
  for (char c : text) {
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
      if (static_cast<unsigned char>(c) < 0x20) {
        static constexpr char hex[] = "0123456789abcdef";
        out += "\\u00";
        out += hex[(c >> 4) & 0xf];
        out += hex[c & 0xf];
      } else
        out += c;
    }
  }
  return out + '"';
}
} // namespace mettle::packages::toml
