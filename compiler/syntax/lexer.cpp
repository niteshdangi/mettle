#include "syntax/lexer.h"
#include "support/limits.h"

namespace mettle {
namespace {
bool wordStart(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
bool digit(unsigned char c) { return c >= '0' && c <= '9'; }
} // namespace
std::vector<Token> tokenize(const Source &source, Diagnostics &diagnostics) {
  Diagnostics::SourceContext context(diagnostics, source);
  if (source.text.size() > limits::sourceBytes) {
    diagnostics.error("limit", {}, "source file exceeds 8 MiB");
    return {{TokenKind::End, {0, 0, source.id}, ""}};
  }
  if (auto invalid = invalidUtf8(source.text)) {
    diagnostics.error("lex", {*invalid, *invalid + 1},
                      "source is not valid UTF-8");
    return {{TokenKind::End, {*invalid, *invalid, source.id}, ""}};
  }
  const auto &s = source.text;
  std::vector<Token> tokens;
  std::size_t i = 0;
  auto add = [&](TokenKind kind, std::size_t start) {
    tokens.push_back({kind, {start, i, source.id}, s.substr(start, i - start)});
  };
  while (i < s.size() && tokens.size() < limits::tokens) {
    auto start = i;
    auto c = static_cast<unsigned char>(s[i]);
    if (c == ' ' || c == '\t' || c == '\v' || c == '\f') {
      while (i < s.size() &&
             (s[i] == ' ' || s[i] == '\t' || s[i] == '\v' || s[i] == '\f'))
        ++i;
      add(TokenKind::Space, start);
    } else if (c == '\n' || c == '\r') {
      ++i;
      if (c == '\r' && i < s.size() && s[i] == '\n')
        ++i;
      add(TokenKind::Newline, start);
    } else if (s.compare(i, 2, "//") == 0) {
      while (i < s.size() && s[i] != '\n' && s[i] != '\r')
        ++i;
      add(TokenKind::Comment, start);
    } else if (s.compare(i, 2, "/*") == 0) {
      i += 2;
      unsigned depth = 1;
      while (i < s.size() && depth) {
        if (s.compare(i, 2, "/*") == 0) {
          ++depth;
          i += 2;
        } else if (s.compare(i, 2, "*/") == 0) {
          --depth;
          i += 2;
        } else
          ++i;
      }
      add(TokenKind::Comment, start);
      if (depth)
        diagnostics.error("lex", {start, i}, "unterminated block comment");
    } else if (c == '`') {
      ++i;
      auto begin = i;
      while (i < s.size() && s[i] != '`' && s[i] != '\n' && s[i] != '\r')
        ++i;
      bool valid = begin < i && wordStart(static_cast<unsigned char>(s[begin]));
      for (auto position = begin; position < i; ++position)
        valid &= wordStart(static_cast<unsigned char>(s[position])) ||
                 digit(s[position]);
      if (i == s.size() || s[i] != '`')
        diagnostics.error("lex", {start, i},
                          "unterminated backtick identifier");
      else
        ++i;
      if (!valid)
        diagnostics.error("lex", {start, i},
                          "backtick contents must be an identifier");
      add(TokenKind::QuotedWord, start);
    } else if (c == '"') {
      ++i;
      bool escaped = false, closed = false;
      while (i < s.size() && s[i] != '\n' && s[i] != '\r') {
        auto value = s[i++];
        if (value == '"' && !escaped) {
          closed = true;
          break;
        }
        escaped = value == '\\' && !escaped;
      }
      if (!closed)
        diagnostics.error("lex", {start, i}, "unterminated text literal");
      add(TokenKind::Text, start);
    } else if (c == '\'' ||
               (c == 'b' && i + 1 < s.size() && s[i + 1] == '\'')) {
      bool byte = c == 'b';
      i += byte ? 2 : 1;
      bool escaped = false;
      while (i < s.size() && s[i] != '\n' && s[i] != '\r') {
        char next = s[i++];
        if (next == '\'' && !escaped)
          break;
        if (next == '\\' && !escaped)
          escaped = true;
        else
          escaped = false;
      }
      add(byte ? TokenKind::Byte : TokenKind::Character, start);
      characterLiteral(tokens.back().text, byte, diagnostics,
                       tokens.back().span);
    } else if (wordStart(c)) {
      while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
        ++i;
      add(TokenKind::Word, start);
    } else if (digit(c)) {
      bool based = s.compare(i, 2, "0x") == 0 || s.compare(i, 2, "0o") == 0 ||
                   s.compare(i, 2, "0b") == 0;
      while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
        ++i;
      bool floating = false;
      if (!based && i + 1 < s.size() && s[i] == '.' && digit(s[i + 1])) {
        floating = true;
        ++i;
        while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
          ++i;
      }
      if (!based && i > start &&
          s.find_first_not_of("0123456789_.", start) == i - 1 &&
          (s[i - 1] == 'e' || s[i - 1] == 'E') && i < s.size() &&
          (s[i] == '+' || s[i] == '-')) {
        floating = true;
        ++i;
        while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
          ++i;
      }
      auto spelling = std::string_view(s).substr(start, i - start);
      auto exponent = spelling.find_first_not_of("0123456789_.");
      floating |= !based &&
                  ((exponent != std::string_view::npos &&
                    (spelling[exponent] == 'e' || spelling[exponent] == 'E')) ||
                   spelling.ends_with("f32") || spelling.ends_with("f64"));
      add(floating ? TokenKind::Floating : TokenKind::Integer, start);
    } else if (c >= 128) {
      i += c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : 2;
      add(TokenKind::Word, start);
      diagnostics.error("feature", {start, i},
                        "Unicode identifiers are not implemented in I02");
    } else {
      auto symbol = compoundSymbol(std::string_view(s).substr(i));
      bool found = !symbol.empty();
      if (found)
        i += symbol.size();
      if (!found) {
        ++i;
        if (std::string_view("(){}[],;:+-*/%!=<>&|^.?@").find(c) ==
            std::string_view::npos)
          diagnostics.error(
              c >= 128 || c == '"' || c == '\'' || c == '`' ? "feature" : "lex",
              {start, i},
              c >= 128 ? "Unicode identifiers are not implemented in I02"
                       : "unsupported character or literal");
      }
      add(TokenKind::Symbol, start);
    }
  }
  if (i != s.size())
    diagnostics.error("limit", {i, i}, "token limit exceeded");
  tokens.push_back({TokenKind::End, {s.size(), s.size(), source.id}, ""});
  return tokens;
}
} // namespace mettle
