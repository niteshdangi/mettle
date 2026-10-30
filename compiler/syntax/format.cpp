#include "syntax/format.h"
#include "syntax/fingerprint.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include <algorithm>
#include <initializer_list>
#include <string_view>
#include <vector>

namespace mettle {
namespace {
constexpr std::size_t indentWidth = 4;

// One significant token of a line with the whitespace that preceded it.
struct Piece {
  TokenKind kind;
  std::string text;
  bool spaced;
  std::string gap;
};
using Line = std::vector<Piece>;

std::string tokenText(const Source &source, const Token &token) {
  auto text =
      source.text.substr(token.span.begin, token.span.end - token.span.begin);
  if (token.kind == TokenKind::Comment && text.starts_with("//"))
    while (!text.empty() && std::string_view(" \t\v\f\r").find(text.back()) !=
                                std::string_view::npos)
      text.pop_back();
  return text;
}

// Splits the tokens at newlines; a multi-line comment or text literal stays
// one piece of the line it starts on.
std::vector<Line> split(const Source &source,
                        const std::vector<Token> &tokens) {
  std::vector<Line> lines(1);
  bool spaced = false;
  std::string gap;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::End)
      break;
    if (token.kind == TokenKind::Space) {
      spaced = true;
      gap = tokenText(source, token);
    } else if (token.kind == TokenKind::Newline) {
      lines.emplace_back();
      spaced = false;
      gap.clear();
    } else {
      lines.back().push_back(
          {token.kind, tokenText(source, token), spaced, gap});
      spaced = false;
      gap.clear();
    }
  }
  return lines;
}

bool oneOf(const Piece &piece, std::initializer_list<std::string_view> texts) {
  return piece.kind == TokenKind::Symbol &&
         std::find(texts.begin(), texts.end(), piece.text) != texts.end();
}
bool symbol(const Piece &piece, std::string_view text) {
  return oneOf(piece, {text});
}
bool numeric(const Piece &piece) {
  return piece.kind == TokenKind::Integer || piece.kind == TokenKind::Floating;
}
bool spacedOperator(const Piece &piece) {
  return oneOf(piece, {"=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=",
                       "%=", "&=", "|=", "^=", "<<=", ">>=", "=>", "->", "??"});
}

// The leading keyword of a line after any visibility and `unsafe` prefix.
std::string_view leadingKeyword(const Line &line) {
  std::size_t k = 0;
  if (k < line.size() && line[k].text == "pub") {
    ++k;
    if (k < line.size() && symbol(line[k], "(")) {
      while (k < line.size() && !symbol(line[k], ")"))
        ++k;
      ++k;
    }
  }
  if (k < line.size() && line[k].text == "unsafe")
    ++k;
  return k < line.size() && line[k].kind == TokenKind::Word
             ? std::string_view(line[k].text)
             : std::string_view();
}

// The index of a line-ending `;` after a one-line item, which a newline
// already terminates; `line.size()` when there is none. Statement `;`s are
// kept: they decide whether a block's last expression is its value.
std::size_t redundantSemicolon(const Line &line, bool itemScope) {
  auto end = line.size();
  while (end && line[end - 1].kind == TokenKind::Comment)
    --end;
  if (!end || !symbol(line[end - 1], ";"))
    return line.size();
  auto keyword = leadingKeyword(line);
  bool item = keyword == "import" || keyword == "module" ||
              keyword == "alias" || keyword == "extend";
  if (itemScope && (keyword == "const" || keyword == "static"))
    item = true;
  return item ? end - 1 : line.size();
}

// The whitespace between two neighbours on one line. Where the rules do not
// decide (`<`, `-`, `&`, ...: operator or prefix, comparison or generic
// bracket) the written choice is kept, collapsed to one space.
std::string gapBefore(const Piece &previous, const Piece &current,
                      unsigned inFormat, bool tokenTree) {
  if (inFormat)
    return current.gap;
  std::string written = current.spaced ? " " : "";
  if (tokenTree)
    return written;
  if (current.kind == TokenKind::Comment)
    return current.text.starts_with("//") ? " " : written;
  if (previous.kind == TokenKind::Comment)
    return written;
  if (oneOf(previous, {"(", "["}) || oneOf(current, {")", "]", ",", ";", ":"}))
    return "";
  if (oneOf(previous, {",", ";", ":"}))
    return " ";
  if (oneOf(current, {".", "?."}))
    return numeric(previous) ? written : "";
  if (oneOf(previous, {".", "?."}))
    return "";
  if (symbol(previous, "{"))
    return symbol(current, "}") ? "" : " ";
  if (symbol(current, "}"))
    return " ";
  if (symbol(current, "{"))
    return oneOf(previous, {"$", "@", "!", "&", "*", "-", "+", "|"}) ? written
                                                                     : " ";
  if (symbol(previous, "}"))
    return oneOf(current, {"?", "!"}) ? written : " ";
  if (spacedOperator(previous) || spacedOperator(current))
    return " ";
  return written;
}

// Whether `first` continues the statement of the preceding line: a member
// access starting the line or an operator ending the previous one.
bool continued(const Line &previous, const Piece &first) {
  if (oneOf(first, {".", "?."}))
    return true;
  for (auto piece = previous.rbegin(); piece != previous.rend(); ++piece) {
    if (piece->kind == TokenKind::Comment)
      continue;
    return oneOf(*piece, {"=",  "==", "!=", "<=", ">=", "+=", "-=", "*=",
                          "/=", "%=", "&=", "|=", "^=", "&&", "||", "+",
                          "-",  "*",  "/",  "%",  "=>", "??"});
  }
  return false;
}

std::string layout(const Source &source, const std::vector<Token> &tokens) {
  struct Open {
    std::size_t indent, line;
    bool brace, macro, items;
  };
  auto lines = split(source, tokens);
  std::vector<Open> stack;
  std::string out;
  std::size_t blanks = 0;
  const Line *last = nullptr;
  // Declarative macro bodies are token trees whose matchers may depend on
  // token adjacency, so their gaps are kept as written.
  std::size_t macros = 0;
  for (std::size_t n = 0; n < lines.size(); ++n) {
    const auto &line = lines[n];
    if (line.empty()) {
      ++blanks;
      continue;
    }
    const auto &first = line.front();
    // A blank line is kept (once) between lines, but not at the start of
    // the file, after an opening brace or before a closing one.
    if (blanks && last && !symbol(last->back(), "{") && !symbol(first, "}"))
      out += '\n';
    blanks = 0;
    std::size_t indent;
    if (oneOf(first, {")", "]", "}"}) && !stack.empty())
      indent = stack.back().indent;
    else {
      indent = stack.empty() ? 0 : stack.back().indent + 1;
      if (n && !lines[n - 1].empty() && (stack.empty() || stack.back().brace) &&
          continued(lines[n - 1], first))
        ++indent;
    }
    out.append(indent * indentWidth, ' ');
    unsigned inFormat = 0;
    auto drop =
        macros ? line.size()
               : redundantSemicolon(line, stack.empty() || stack.back().items);
    for (std::size_t k = 0; k < line.size(); ++k) {
      if (k == drop)
        continue;
      const auto &piece = line[k];
      if (k)
        out += gapBefore(line[k - 1], piece, inFormat, macros != 0);
      out += piece.text;
      if (piece.kind == TokenKind::FormatOpen)
        ++inFormat;
      else if (piece.kind == TokenKind::FormatClose && inFormat)
        --inFormat;
      if (oneOf(piece, {"(", "[", "{"})) {
        // A block opened after its brackets closed on a continuation line
        // belongs to the enclosing level, not to the continuation.
        auto entry = indent;
        if (piece.text == "{") {
          if (stack.empty())
            entry = 0;
          else if (stack.back().line != n)
            entry = stack.back().indent + 1;
        }
        bool macro = piece.text == "{" && k >= 2 &&
                     line[k - 2].kind == TokenKind::Word &&
                     line[k - 2].text == "macro" &&
                     line[k - 1].kind == TokenKind::Word;
        macros += macro;
        bool items = piece.text == "{" && leadingKeyword(line) == "module";
        stack.push_back({entry, n, piece.text == "{", macro, items});
      } else if (oneOf(piece, {")", "]", "}"}) && !stack.empty()) {
        macros -= stack.back().macro;
        stack.pop_back();
      }
    }
    out += '\n';
    last = &line;
  }
  return out;
}

struct Signature {
  TokenKind kind;
  std::string text;
  bool operator==(const Signature &) const = default;
};
// A line-ending `;` is left out; the syntax fingerprint keeps the ones that
// matter. The fingerprint also checks that inserted line breaks are safe.
std::vector<Signature> signature(const Source &source,
                                 const std::vector<Token> &tokens) {
  std::vector<Signature> result;
  for (std::size_t n = 0; n < tokens.size(); ++n) {
    const auto &token = tokens[n];
    if (token.kind == TokenKind::Space || token.kind == TokenKind::End)
      continue;
    if (token.kind == TokenKind::Symbol && tokenText(source, token) == ";") {
      auto next = n + 1;
      while (next < tokens.size() && (tokens[next].kind == TokenKind::Space ||
                                      tokens[next].kind == TokenKind::Comment))
        ++next;
      if (next == tokens.size() || tokens[next].kind == TokenKind::Newline ||
          tokens[next].kind == TokenKind::End)
        continue;
    }
    if (token.kind == TokenKind::Newline) {
      continue;
    }
    result.push_back({token.kind, tokenText(source, token)});
  }
  return result;
}

// Wrap only at token boundaries where the parser may continue. Macro token
// trees and multiline tokens are left untouched because their trivia matters.
std::string wrap(const Source &source, const std::vector<Token> &tokens) {
  for (std::size_t i = 0; i < tokens.size(); ++i) {
    const auto &token = tokens[i];
    if ((token.kind == TokenKind::Word && token.text == "macro") ||
        token.kind == TokenKind::FormatOpen ||
        (token.kind != TokenKind::Newline &&
         token.text.find('\n') != std::string::npos))
      return source.text;
    if (token.kind == TokenKind::Symbol && token.text == "!") {
      auto previous = i;
      while (previous && tokens[previous - 1].kind == TokenKind::Space)
        --previous;
      if (previous && tokens[previous - 1].kind == TokenKind::Word)
        return source.text;
    }
  }
  std::vector<std::size_t> breaks, candidates;
  std::size_t start = 0, parens = 0;
  bool comment = false;
  auto line = [&](std::size_t end) {
    if (!comment && end - start > 100 && !candidates.empty()) {
      std::size_t indent = 0;
      while (start + indent < end && source.text[start + indent] == ' ')
        ++indent;
      auto segment = start;
      auto target = start + 100;
      std::size_t candidate = 0;
      while (candidate < candidates.size() && end > target) {
        std::size_t chosen = candidate;
        while (chosen + 1 < candidates.size() &&
               candidates[chosen + 1] <= target)
          ++chosen;
        auto position = candidates[chosen];
        if (position <= segment || position >= end)
          break;
        breaks.push_back(position);
        segment = position;
        target = position +
                 (100 > indent + indentWidth ? 100 - indent - indentWidth : 1);
        candidate = chosen + 1;
      }
    }
    candidates.clear();
    comment = false;
    start = end + 1;
  };
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::Newline) {
      line(token.span.begin);
      continue;
    }
    if (token.kind == TokenKind::Comment)
      comment = true;
    if (token.kind != TokenKind::Symbol)
      continue;
    if (token.text == "(")
      ++parens;
    else if (token.text == ")" && parens)
      --parens;
    else if ((token.text == "," && parens) || token.text == "&&" ||
             token.text == "||" || token.text == "+" || token.text == "-" ||
             token.text == "*" || token.text == "/" || token.text == "??")
      candidates.push_back(token.span.end);
  }
  std::string result;
  std::size_t at = 0;
  for (auto position : breaks) {
    result.append(source.text, at, position - at);
    result += '\n';
    at = position;
  }
  result.append(source.text, at, std::string::npos);
  return result;
}
} // namespace

std::optional<std::string> format(const Source &source,
                                  Diagnostics &diagnostics,
                                  const SourceExpander &expand) {
  auto parsed = [&](const Source &input, Diagnostics &sink) {
    if (expand)
      if (auto expanded = expand(input, sink); expanded && sink.empty())
        return parse(*expanded, sink);
    return parse(input, sink);
  };
  auto tokens = tokenize(source, diagnostics);
  if (!diagnostics.empty())
    return std::nullopt;
  auto before = parsed(source, diagnostics);
  if (!diagnostics.empty())
    return std::nullopt;
  auto text = layout(source, tokens);
  const auto unwrapped = text;
  // Every iteration adds at least one break; layout canonicalizes its
  // indentation before deciding whether another break is needed.
  for (;;) {
    Source current{source.path, text, source.id};
    Diagnostics scratch;
    auto currentTokens = tokenize(current, scratch);
    auto broken = wrap(current, currentTokens);
    if (broken == text)
      break;
    Source next{source.path, broken, source.id};
    auto nextTokens = tokenize(next, scratch);
    text = layout(next, nextTokens);
  }
  if (text != unwrapped) {
    Source candidate{source.path, text, source.id};
    Diagnostics scratch;
    auto candidateTokens = tokenize(candidate, scratch);
    auto candidateTree = parsed(candidate, scratch);
    if (!scratch.empty() ||
        signature(source, tokens) != signature(candidate, candidateTokens) ||
        fingerprint(before) != fingerprint(candidateTree))
      text = unwrapped;
  }
  Source result{source.path, text, source.id};
  Diagnostics check;
  auto after = tokenize(result, check);
  auto refuse = [&](const std::string &reason) {
    diagnostics.error("format", {},
                      "the formatted source " + reason +
                          "; no output produced");
    return std::nullopt;
  };
  if (!check.empty())
    return refuse("does not lex");
  if (signature(source, tokens) != signature(result, after))
    return refuse("has a different token sequence");
  auto tree = parsed(result, check);
  if (!check.empty())
    return refuse("does not parse");
  if (fingerprint(before) != fingerprint(tree))
    return refuse("parses to a different syntax tree");
  if (layout(result, after) != text)
    return refuse("is not a fixed point of the formatter");
  return text;
}
} // namespace mettle
