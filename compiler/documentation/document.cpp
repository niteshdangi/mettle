#include "documentation/document.h"
#include "syntax/lexer.h"
#include <algorithm>
#include <initializer_list>
#include <string_view>

namespace mettle::documentation {
namespace {
bool oneOf(std::string_view text, std::initializer_list<std::string_view> set) {
  return std::find(set.begin(), set.end(), text) != set.end();
}

bool allOf(std::string_view text, char c) {
  return !text.empty() && text.find_first_not_of(c) == std::string_view::npos;
}

bool isModifier(std::string_view word) {
  return oneOf(word, {"pub", "copy", "static", "take", "mut", "read", "async",
                      "unsafe", "extern", "const", "heap"});
}

bool isKeyword(std::string_view word) {
  return oneOf(word, {"fn", "type", "enum", "interface", "extend", "alias",
                      "const", "static", "module", "import", "union", "macro"});
}

bool hasBody(Kind kind) {
  return kind == Kind::Function || kind == Kind::Type || kind == Kind::Union ||
         kind == Kind::Enum || kind == Kind::Interface ||
         kind == Kind::Implementation || kind == Kind::Module ||
         kind == Kind::Macro;
}

bool isContainer(Kind kind) {
  return hasBody(kind) && kind != Kind::Function && kind != Kind::Macro;
}

class Extractor {
public:
  Extractor(const Source &source, bool includePrivate)
      : includePrivate(includePrivate), starts{0} {
    Diagnostics ignored;
    tokens = tokenize(source, ignored);
    for (std::size_t i = 0; i < source.text.size(); ++i)
      if (source.text[i] == '\n')
        starts.push_back(i + 1);
  }

  void run(Page &page) {
    while (at < tokens.size() && tokens[at].kind != TokenKind::End) {
      members(page.items, &page.doc, Kind::Module, false);
      if (at < tokens.size() && isSymbol(tokens[at], "}"))
        ++at;
    }
  }

private:
  bool includePrivate;
  std::vector<std::size_t> starts;
  std::vector<Token> tokens;
  std::size_t at = 0;

  static bool isSymbol(const Token &token, std::string_view text) {
    return token.kind == TokenKind::Symbol && token.text == text;
  }
  static bool blank(const Token &token) {
    return token.kind == TokenKind::Space || token.kind == TokenKind::Newline ||
           token.kind == TokenKind::Comment;
  }
  std::size_t lineOf(std::size_t offset) const {
    auto after = std::upper_bound(starts.begin(), starts.end(), offset);
    return static_cast<std::size_t>(after - starts.begin());
  }
  std::size_t skipSpaces(std::size_t i) const {
    while (i < tokens.size() && tokens[i].kind == TokenKind::Space)
      ++i;
    return i;
  }

  // Index after the bracket that closes the one opening at `i`.
  std::size_t closing(std::size_t i) const {
    unsigned depth = 0;
    for (; i < tokens.size(); ++i) {
      if (tokens[i].kind != TokenKind::Symbol)
        continue;
      const auto &text = tokens[i].text;
      if (text == "(" || text == "[" || text == "{")
        ++depth;
      else if ((text == ")" || text == "]" || text == "}") && --depth == 0)
        return i + 1;
    }
    return tokens.size();
  }

  void collect(const Token &token, Doc &outer, Doc *inner) {
    std::string_view text = token.text;
    bool inside = text.starts_with("//!");
    if (!inside && (!text.starts_with("///") || text.starts_with("////")))
      return;
    if (inside && !inner)
      return;
    text.remove_prefix(3);
    if (text.ends_with('\r'))
      text.remove_suffix(1);
    if (text.starts_with(' '))
      text.remove_prefix(1);
    Doc &target = inside ? *inner : outer;
    target.lines.emplace_back(text);
    target.numbers.push_back(lineOf(token.span.begin));
    target.spans.push_back(token.span);
  }

  void skipBlank(Doc &doc) {
    while (at < tokens.size() && blank(tokens[at])) {
      if (tokens[at].kind == TokenKind::Comment)
        collect(tokens[at], doc, nullptr);
      ++at;
    }
  }

  std::string text(std::size_t begin, std::size_t end) const {
    std::string result;
    bool gap = false;
    for (std::size_t i = begin; i < end; ++i) {
      if (blank(tokens[i])) {
        gap = true;
        continue;
      }
      if (gap && !result.empty())
        result += ' ';
      gap = false;
      result += tokens[i].text;
    }
    return result;
  }

  // The token ending the header that starts at `from`: a newline, `;`, `,`, `}`
  // or, when `bodyOpens`, the `{` of a body at bracket depth zero.
  std::size_t headerEnd(std::size_t from, bool bodyOpens) const {
    unsigned parens = 0, angles = 0;
    std::size_t i = from;
    for (; i < tokens.size(); ++i) {
      const auto &token = tokens[i];
      if (token.kind == TokenKind::End)
        break;
      if (token.kind == TokenKind::Newline && parens == 0) {
        auto next = i;
        while (next < tokens.size() && blank(tokens[next]))
          ++next;
        if (next < tokens.size() && tokens[next].kind == TokenKind::Word &&
            tokens[next].text == "where") {
          i = next;
          continue;
        }
        break;
      }
      if (token.kind != TokenKind::Symbol)
        continue;
      const auto &symbol = token.text;
      if (symbol == "(" || symbol == "[")
        ++parens;
      else if (symbol == ")" || symbol == "]") {
        if (parens)
          --parens;
      } else if (parens == 0) {
        if (symbol == ";" || symbol == "}" || (symbol == "," && angles == 0))
          break;
        if (symbol == "{") {
          if (bodyOpens)
            break;
          i = closing(i) - 1;
          continue;
        }
      }
      if (allOf(symbol, '<'))
        angles += static_cast<unsigned>(symbol.size());
      else if (allOf(symbol, '>'))
        angles = symbol.size() >= angles
                     ? 0
                     : angles - static_cast<unsigned>(symbol.size());
    }
    return i;
  }

  // Parses the items up to the `}` closing the enclosing body (not consumed)
  // or the end of the source. `inner` receives `//!` text.
  void members(std::vector<Item> &out, Doc *inner, Kind container, bool open) {
    Doc pending;
    while (at < tokens.size()) {
      const auto &token = tokens[at];
      if (token.kind == TokenKind::End)
        return;
      if (token.kind == TokenKind::Space || token.kind == TokenKind::Newline ||
          isSymbol(token, ";") || isSymbol(token, ",")) {
        ++at;
        continue;
      }
      if (token.kind == TokenKind::Comment) {
        collect(token, pending, inner);
        ++at;
        continue;
      }
      if (isSymbol(token, "}"))
        return;
      Item item;
      item.doc = std::move(pending);
      pending = {};
      auto start = at;
      if (parseItem(item, container, open))
        out.push_back(std::move(item));
      if (at == start)
        ++at;
    }
  }

  // Parses one item at `at`. Returns whether it belongs in the documentation.
  bool parseItem(Item &item, Kind container, bool open) {
    bool omitted = false;
    while (at < tokens.size() && isSymbol(tokens[at], "@")) {
      auto begin = at++;
      if (at < tokens.size() && tokens[at].kind == TokenKind::Word) {
        omitted |= tokens[at].text == "test" || tokens[at].text == "bench";
        ++at;
      }
      if (at < tokens.size() && isSymbol(tokens[at], "("))
        at = closing(at);
      item.attributes.push_back(text(begin, at));
      skipBlank(item.doc);
    }
    if (at >= tokens.size())
      return false;
    auto begin = at;
    std::vector<std::string_view> lead;
    bool exported = false;
    auto j = at;
    while (j < tokens.size()) {
      j = skipSpaces(j);
      if (j >= tokens.size() || tokens[j].kind != TokenKind::Word ||
          (!isModifier(tokens[j].text) && !isKeyword(tokens[j].text)))
        break;
      lead.push_back(tokens[j].text);
      exported |= tokens[j].text == "pub";
      ++j;
      auto next = skipSpaces(j);
      if (lead.back() == "pub" && next < tokens.size() &&
          isSymbol(tokens[next], "("))
        j = closing(next);
    }
    j = skipSpaces(j);
    auto has = [&](std::string_view word) {
      return std::find(lead.begin(), lead.end(), word) != lead.end();
    };
    bool member = false;
    if (has("fn"))
      item.kind = Kind::Function;
    else if (has("type"))
      item.kind = Kind::Type;
    else if (has("enum"))
      item.kind = Kind::Enum;
    else if (has("interface"))
      item.kind = Kind::Interface;
    else if (has("extend"))
      item.kind = Kind::Implementation;
    else if (has("alias"))
      item.kind = Kind::Alias;
    else if (has("const") || has("static"))
      item.kind = Kind::Constant;
    else if (has("module"))
      item.kind = Kind::Module;
    else if (has("union"))
      item.kind = Kind::Union;
    else if (has("macro"))
      item.kind = Kind::Macro;
    else if (has("import")) {
      at = headerEnd(begin, false);
      return false;
    } else if (container == Kind::Enum || container == Kind::Type ||
               container == Kind::Union) {
      member = true;
      item.kind = container == Kind::Enum ? Kind::Variant : Kind::Field;
    } else {
      at = headerEnd(begin, true);
      if (at < tokens.size() && isSymbol(tokens[at], "{"))
        at = closing(at);
      return false;
    }
    auto end = headerEnd(begin, hasBody(item.kind) && !member);
    item.signature = text(begin, end);
    auto signatureEnd =
        end > begin ? tokens[end - 1].span.end : tokens[begin].span.end;
    item.span = {tokens[begin].span.begin, signatureEnd,
                 tokens[begin].span.source};
    item.line = lineOf(tokens[begin].span.begin);
    bool plain = item.kind != Kind::Implementation;
    item.name = j < tokens.size() && tokens[j].kind == TokenKind::Word && plain
                    ? tokens[j].text
                    : item.signature;
    bool visible = member || exported || includePrivate || open ||
                   item.kind == Kind::Implementation;
    if (end < tokens.size() && isSymbol(tokens[end], "{") && !member) {
      if (isContainer(item.kind)) {
        at = end + 1;
        bool opens = item.kind == Kind::Interface ||
                     (item.kind == Kind::Implementation &&
                      item.signature.find(" implements ") != std::string::npos);
        members(item.members, item.kind == Kind::Module ? &item.doc : nullptr,
                item.kind, opens);
        if (at < tokens.size() && isSymbol(tokens[at], "}"))
          ++at;
      } else
        at = closing(end);
    } else
      at = end;
    if (omitted || !visible)
      return false;
    return item.kind != Kind::Implementation || !item.members.empty() ||
           !item.doc.empty();
  }
};
} // namespace

Page extract(const Source &source, std::string name, bool includePrivate) {
  Page page;
  page.name = std::move(name);
  page.path = source.path;
  page.span = {0, source.text.size(), source.id};
  Extractor(source, includePrivate).run(page);
  return page;
}
} // namespace mettle::documentation
