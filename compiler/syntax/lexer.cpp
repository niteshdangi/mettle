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

  if (source.text.size() > limits::sourceBytes) {
    diagnostics.error("limit", {}, "source file exceeds 8 MiB");
    return {{TokenKind::End, {}, ""}};
  }
  if (auto invalid = invalidUtf8(source.text)) {
    diagnostics.error("lex", {*invalid, *invalid + 1},
                      "source is not valid UTF-8");
    return {{TokenKind::End, {*invalid, *invalid}, ""}};
  }
  const auto &s = source.text;
  std::vector<Token> tokens;
  std::size_t i = 0;
  auto add = [&](TokenKind kind, std::size_t start) {
    tokens.push_back({kind, {start, i}, s.substr(start, i - start)});
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
    } else if (wordStart(c)) {
      while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
        ++i;
      add(TokenKind::Word, start);
    } else if (digit(c)) {
      while (i < s.size() && (wordStart(s[i]) || digit(s[i])))
        ++i;
      add(TokenKind::Integer, start);
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
        if (std::string_view("(){}[],;:+-*/%!=<>&|^.?").find(c) ==
            std::string_view::npos)
          diagnostics.error(
              c >= 128 || c == '"' || c == '\'' || c == '@' || c == '`'
                  ? "feature"
                  : "lex",
              {start, i},
              c >= 128 ? "Unicode identifiers are not implemented in I02"
                       : "unsupported character or literal");
      }
      add(TokenKind::Symbol, start);
    }
  }
  if (i != s.size())
    diagnostics.error("limit", {i, i}, "token limit exceeded");
  tokens.push_back({TokenKind::End, {s.size(), s.size()}, ""});
  return tokens;
}
} // namespace mettle
