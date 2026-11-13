#include "syntax/lexer.h"
#include "support/limits.h"

namespace mettle {
namespace {
bool wordStart(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
bool digit(unsigned char c) { return c >= '0' && c <= '9'; }
bool horizontalSpace(char c) { return c == ' ' || c == '\t'; }
bool lineEnd(const std::string &s, std::size_t i) {
  return i >= s.size() || s[i] == '\n' || s[i] == '\r';
}
// Position of the `"""` that follows an optional `b` or `f` prefix at `i`.
std::optional<std::size_t> blockQuote(const std::string &s, std::size_t i) {
  if (s[i] == 'b' || s[i] == 'f')
    ++i;
  if (s.compare(i, 3, "\"\"\"") == 0)
    return i;
  return std::nullopt;
}
// Whether a removed `r"`, `r#"`, `br"` or `br#"` literal starts at `i`.
bool removedRawText(const std::string &s, std::size_t i) {
  if (s[i] == 'b')
    ++i;
  if (i >= s.size() || s[i] != 'r')
    return false;
  while (++i < s.size() && s[i] == '#') {
  }
  return i < s.size() && s[i] == '"';
}
} // namespace
std::vector<Token> tokenize(const Source &source, Diagnostics &diagnostics) {
  Diagnostics::SourceContext context(diagnostics, source);
  if (source.text.size() > limits::sourceBytes) {
    diagnostics.error("limit", {}, "source file must be smaller than 4 GiB");
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
  bool afterDot = false;
  // Open `{expression}` holes of f-strings, innermost last; each counts the
  // braces nested inside the hole so only the matching `}` ends it.
  std::vector<std::size_t> holes;
  auto add = [&](TokenKind kind, std::size_t start) {
    tokens.push_back({kind, {start, i, source.id}, s.substr(start, i - start)});
    if (kind != TokenKind::Space && kind != TokenKind::Newline &&
        kind != TokenKind::Comment)
      afterDot = kind == TokenKind::Symbol && tokens.back().text == ".";
  };
  // Scans f-string literal text from `i` up to the next hole or the closing
  // quote; `{{` and `}}` are literal braces.
  auto formatText = [&]() {
    auto start = i;
    std::string piece;
    bool escaped = false;
    auto flush = [&]() {
      if (piece.empty())
        return;
      tokens.push_back({TokenKind::FormatPiece, {start, i, source.id}, piece});
      piece.clear();
    };
    while (i < s.size() && s[i] != '\n' && s[i] != '\r') {
      auto value = s[i];
      if (value == '"' && !escaped) {
        flush();
        tokens.push_back({TokenKind::FormatClose, {i, i + 1, source.id}, "\""});
        ++i;
        return;
      }
      if (!escaped && (value == '{' || value == '}')) {
        if (i + 1 < s.size() && s[i + 1] == value) {
          piece += value;
          i += 2;
          continue;
        }
        if (value == '}') {
          diagnostics.error("lex", {i, i + 1},
                            "a single '}' in an f-string must be written '}}'");
          ++i;
          continue;
        }
        flush();
        tokens.push_back(
            {TokenKind::FormatHoleOpen, {i, i + 1, source.id}, "{"});
        ++i;
        holes.push_back(0);
        return;
      }
      piece += value;
      escaped = value == '\\' && !escaped;
      ++i;
    }
    flush();
    diagnostics.error("lex", {start, i}, "unterminated f-string literal");
    holes.clear();
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
      if (!holes.empty()) {
        diagnostics.error("lex", {start, i}, "unterminated f-string literal");
        holes.clear();
      }
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
    } else if (removedRawText(s, i)) {
      i += c == 'b' ? 2 : 1;
      while (s[i] == '#')
        ++i;
      diagnostics.error(
          "lex", {start, i},
          "raw text literals were removed; use a \"\"\" text block");
      add(TokenKind::Word, start);
    } else if (auto quote = blockQuote(s, i)) {
      i = *quote + 3;
      if (*quote != start)
        diagnostics.error("lex", {start, i},
                          c == 'b' ? "byte text blocks are reserved"
                                   : "interpolated text blocks are reserved");
      while (i < s.size() && horizontalSpace(s[i]))
        ++i;
      bool closed = false;
      if (!lineEnd(s, i)) {
        diagnostics.error("lex", {start, i},
                          "a text block's opening \"\"\" must end its line");
        closed = true;
      }
      while (!closed && i < s.size()) {
        if (s[i++] == '\r' && i < s.size() && s[i] == '\n')
          ++i;
        auto indent = i;
        while (indent < s.size() && horizontalSpace(s[indent]))
          ++indent;
        if (s.compare(indent, 3, "\"\"\"") == 0) {
          i = indent + 3;
          closed = true;
        } else
          while (!lineEnd(s, i))
            ++i;
      }
      if (!closed)
        diagnostics.error("lex", {start, i}, "unterminated text block");
      add(TokenKind::Text, start);
    } else if (c == 'f' && i + 1 < s.size() && s[i + 1] == '"') {
      i += 2;
      tokens.push_back({TokenKind::FormatOpen, {start, i, source.id}, "f\""});
      afterDot = false;
      formatText();
    } else if (c == '"' || (c == 'b' && i + 1 < s.size() && s[i + 1] == '"')) {
      const bool bytes = c == 'b';
      i += bytes ? 2 : 1;
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
      add(bytes ? TokenKind::PrefixedText : TokenKind::Text, start);
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
      if (!afterDot && !based && i + 1 < s.size() && s[i] == '.' &&
          digit(s[i + 1])) {
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
        if (std::string_view("(){}[],;:+-*/%!=<>&|^.?@$").find(c) ==
            std::string_view::npos)
          diagnostics.error(
              c >= 128 || c == '"' || c == '\'' || c == '`' ? "feature" : "lex",
              {start, i},
              c >= 128 ? "Unicode identifiers are not implemented in I02"
                       : "unsupported character or literal");
      }
      add(TokenKind::Symbol, start);
      if (!holes.empty() && tokens.back().text == "{")
        ++holes.back();
      else if (!holes.empty() && tokens.back().text == "}") {
        if (holes.back())
          --holes.back();
        else {
          tokens.back().kind = TokenKind::FormatHoleClose;
          holes.pop_back();
          formatText();
        }
      }
    }
  }
  if (!holes.empty())
    diagnostics.error("lex", {s.size(), s.size()},
                      "unterminated f-string literal");
  if (i != s.size())
    diagnostics.error("limit", {i, i}, "token limit exceeded");
  tokens.push_back({TokenKind::End, {s.size(), s.size(), source.id}, ""});
  for (auto &token : tokens)
    token.context = diagnostics.syntaxContext(token.span);
  return tokens;
}
} // namespace mettle
