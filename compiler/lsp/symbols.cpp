#include "lsp/symbols.h"
#include "diagnostics/diagnostics.h"
#include "syntax/lexer.h"
#include <algorithm>
#include <unordered_map>
#include <utility>

namespace mettle::lsp {
namespace {
bool symbol(const Token &token, std::string_view text) {
  return token.kind == TokenKind::Symbol && token.text == text;
}
bool word(const Token &token) { return token.kind == TokenKind::Word; }
bool opener(const Token &token) {
  return symbol(token, "(") || symbol(token, "[") || symbol(token, "{");
}
bool closer(const Token &token) {
  return symbol(token, ")") || symbol(token, "]") || symbol(token, "}");
}
bool breaks(const Token &token) {
  return token.kind == TokenKind::Newline || symbol(token, ";");
}
bool nameable(const Token &token) {
  return word(token) && !isReservedWord(token.text);
}
bool memberAccess(const Token &token) {
  return symbol(token, ".") || symbol(token, "?.") || symbol(token, "::");
}
bool modifier(std::string_view text) {
  return text == "pub" || text == "copy" || text == "unsafe" ||
         text == "extern" || text == "const" || text == "static" ||
         text == "async" || text == "mut" || text == "read" || text == "take";
}
// One line of text for hover and symbol details.
std::string squeeze(std::string_view raw, std::size_t limit = 240) {
  std::string out;
  bool gap = false;
  for (char c : raw) {
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      gap = !out.empty();
      continue;
    }
    if (gap)
      out += ' ';
    gap = false;
    out += c;
  }
  if (out.size() > limit) {
    auto cut = limit;
    while (cut > 0 && (static_cast<unsigned char>(out[cut]) & 0xc0) == 0x80)
      --cut;
    out.resize(cut);
    out += "...";
  }
  return out;
}
bool itemKind(std::string_view spelling, SymbolKind &kind) {
  static const std::pair<std::string_view, SymbolKind> kinds[] = {
      {"fn", SymbolKind::Function},      {"type", SymbolKind::Type},
      {"enum", SymbolKind::Enumeration}, {"interface", SymbolKind::Interface},
      {"union", SymbolKind::Union},      {"alias", SymbolKind::Alias},
      {"static", SymbolKind::Static},    {"const", SymbolKind::Constant},
      {"module", SymbolKind::Module},    {"impl", SymbolKind::Implementation}};
  for (const auto &entry : kinds)
    if (entry.first == spelling) {
      kind = entry.second;
      return true;
    }
  return false;
}
} // namespace

class Builder {
public:
  Builder(const std::string &source, SymbolIndex &result)
      : text(source), index(result), t(result.tokens),
        declarations(result.items) {}
  void run() {
    Diagnostics sink;
    for (auto &token : tokenize(Source{"<document>", text, 0}, sink))
      if (token.kind != TokenKind::Space && token.kind != TokenKind::Comment &&
          token.kind != TokenKind::End)
        t.push_back(std::move(token));
    n = t.size();
    pairBrackets();
    declare();
    classify();
  }

private:
  struct Body {
    int declaration;
    std::size_t open, close;
  };
  const std::string &text;
  SymbolIndex &index;
  std::vector<Token> &t;
  std::vector<Declaration> &declarations;
  std::size_t n = 0;
  std::unordered_map<std::size_t, int> nameTokens;
  std::vector<Body> bodies;
  std::vector<std::size_t> groups;
  // Tokens before this index belong to a declaration header, where a word at
  // the start of an entry is a type or parameter rather than a member.
  std::size_t headerEnd = 0;

  std::size_t beginOf(std::size_t i) const {
    return i < n ? t[i].span.begin : text.size();
  }
  std::size_t endOf(std::size_t i) const {
    return i < n ? t[i].span.end : text.size();
  }
  std::size_t closeOffset(std::size_t open) const {
    return index.match[open] < n ? t[index.match[open]].span.begin
                                 : text.size();
  }
  // The end offset of the last token before `stop` (but not before `floor`).
  std::size_t endBefore(std::size_t stop, std::size_t floor) const {
    stop = std::min(stop, n);
    return stop > floor ? t[stop - 1].span.end : endOf(floor);
  }
  std::string slice(std::size_t begin, std::size_t end) const {
    return squeeze(std::string_view(text).substr(begin, end - begin));
  }

  void pairBrackets() {
    index.match.assign(n, n);
    std::vector<std::size_t> open;
    for (std::size_t i = 0; i < n; ++i) {
      if (opener(t[i])) {
        open.push_back(i);
      } else if (closer(t[i]) && !open.empty()) {
        index.match[open.back()] = i;
        open.pop_back();
      }
    }
  }
  // The first statement break or enclosing close at or after `from`.
  std::size_t statementEnd(std::size_t from, bool commas = false) const {
    for (auto j = from; j < n; ++j) {
      if (opener(t[j])) {
        if (index.match[j] >= n)
          return n;
        j = index.match[j];
        continue;
      }
      if (breaks(t[j]) || closer(t[j]) || (commas && symbol(t[j], ",")))
        return j;
    }
    return n;
  }
  std::size_t add(Declaration declaration, std::size_t nameToken) {
    declarations.push_back(std::move(declaration));
    nameTokens[nameToken] = static_cast<int>(declarations.size() - 1);
    return declarations.size() - 1;
  }
  int parentDeclaration() const {
    return bodies.empty() ? -1 : bodies.back().declaration;
  }
  std::size_t enclosingBlockEnd() const {
    for (auto g = groups.rbegin(); g != groups.rend(); ++g)
      if (symbol(t[*g], "{"))
        return closeOffset(*g);
    return text.size();
  }

  void declare() {
    for (std::size_t i = 0; i < n; ++i) {
      while (!bodies.empty() && i > bodies.back().close)
        bodies.pop_back();
      const Token &token = t[i];
      if (opener(token)) {
        groups.push_back(i);
        continue;
      }
      if (closer(token)) {
        if (!groups.empty())
          groups.pop_back();
        continue;
      }
      if (!word(token) || (i > 0 && memberAccess(t[i - 1])))
        continue;
      if (declareItem(i))
        continue;
      if (token.text == "let" || token.text == "var")
        declareLocal(i);
      else if (token.text == "for")
        declareLoop(i);
      else if (i >= headerEnd && !bodies.empty() && !groups.empty() &&
               groups.back() == bodies.back().open)
        declareMember(i);
    }
  }

  bool declareItem(std::size_t i) {
    SymbolKind kind = SymbolKind::Function;
    if (!itemKind(t[i].text, kind))
      return false;
    std::size_t nameToken = i + 1;
    if (kind == SymbolKind::Implementation) {
      nameToken = i;
    } else {
      if (kind == SymbolKind::Static || kind == SymbolKind::Constant) {
        // `static fn` and `const fn` are modifiers of a function.
        if (nameToken < n && word(t[nameToken]) && t[nameToken].text == "fn")
          return false;
        while (nameToken < n && word(t[nameToken]) &&
               (t[nameToken].text == "mut" || t[nameToken].text == "var"))
          ++nameToken;
      }
      if (nameToken >= n || !nameable(t[nameToken]))
        return false;
    }
    auto first = i;
    while (first > 0 && word(t[first - 1]) && modifier(t[first - 1].text))
      --first;
    std::size_t body = n, stop = n;
    if (kind == SymbolKind::Alias || kind == SymbolKind::Static ||
        kind == SymbolKind::Constant) {
      stop = statementEnd(nameToken);
    } else {
      for (auto k = nameToken + 1; k < n; ++k) {
        if (symbol(t[k], "{")) {
          body = stop = k;
          break;
        }
        if (opener(t[k])) {
          if (index.match[k] >= n)
            break;
          k = index.match[k];
          continue;
        }
        if (breaks(t[k]) || closer(t[k])) {
          stop = k;
          break;
        }
      }
    }
    Declaration declaration;
    declaration.kind = kind;
    declaration.begin = t[first].span.begin;
    declaration.nameBegin = t[nameToken].span.begin;
    declaration.nameEnd = t[nameToken].span.end;
    if (body < n)
      declaration.end =
          index.match[body] < n ? t[index.match[body]].span.end : text.size();
    else
      declaration.end = endBefore(stop, nameToken);
    auto header = slice(declaration.begin,
                        body < n ? t[body].span.begin : declaration.end);
    declaration.signature = header;
    declaration.name =
        kind == SymbolKind::Implementation ? header : t[nameToken].text;
    declaration.parent = parentDeclaration();
    auto id = add(std::move(declaration), nameToken);
    headerEnd = std::max(headerEnd, stop);
    if (kind == SymbolKind::Function && body < n)
      declareParameters(id, nameToken, body);
    if (body < n)
      bodies.push_back({static_cast<int>(id), body, index.match[body]});
    return true;
  }

  void declareParameters(std::size_t function, std::size_t nameToken,
                         std::size_t body) {
    auto p = nameToken + 1;
    if (p < n && symbol(t[p], "<")) {
      int depth = 0;
      for (; p < n && !symbol(t[p], "{"); ++p) {
        depth += symbol(t[p], "<") ? 1 : 0;
        depth -= symbol(t[p], ">") ? 1 : 0;
        depth -= symbol(t[p], ">>") ? 2 : 0;
        if (depth <= 0) {
          ++p;
          break;
        }
      }
    }
    if (p >= n || !symbol(t[p], "(") || index.match[p] >= n)
      return;
    for (auto q = p + 1; q < index.match[p]; ++q) {
      if (opener(t[q])) {
        if (index.match[q] >= n)
          return;
        q = index.match[q];
        continue;
      }
      if (!nameable(t[q]) || q + 1 >= n || !symbol(t[q + 1], ":"))
        continue;
      Declaration parameter;
      parameter.kind = SymbolKind::Parameter;
      parameter.name = t[q].text;
      parameter.nameBegin = parameter.begin = t[q].span.begin;
      parameter.nameEnd = t[q].span.end;
      parameter.end = endBefore(statementEnd(q, true), q);
      parameter.signature =
          "(parameter) " + slice(parameter.begin, parameter.end);
      parameter.scopeBegin = t[body].span.begin;
      parameter.scopeEnd = closeOffset(body);
      parameter.owner = static_cast<int>(function);
      parameter.parent = static_cast<int>(function);
      add(std::move(parameter), q);
    }
  }

  void declareLocal(std::size_t i) {
    std::vector<std::size_t> names;
    auto j = i + 1;
    if (j < n && nameable(t[j])) {
      names.push_back(j);
    } else if (j < n && symbol(t[j], "(") && index.match[j] < n) {
      for (auto q = j + 1; q < index.match[j]; ++q)
        if (nameable(t[q]) &&
            (symbol(t[q - 1], "(") || symbol(t[q - 1], ",")) && q + 1 < n &&
            (symbol(t[q + 1], ",") || symbol(t[q + 1], ")")))
          names.push_back(q);
    }
    if (names.empty())
      return;
    auto stop = statementEnd(i);
    auto scopeEnd = enclosingBlockEnd();
    auto end = endBefore(stop, i);
    auto signature = slice(t[i].span.begin, end);
    for (auto name : names) {
      Declaration local;
      local.kind = SymbolKind::Local;
      local.name = t[name].text;
      local.nameBegin = t[name].span.begin;
      local.nameEnd = t[name].span.end;
      local.begin = t[i].span.begin;
      local.end = end;
      local.signature = signature;
      local.scopeBegin = beginOf(stop);
      local.scopeEnd = scopeEnd;
      local.parent = parentDeclaration();
      add(std::move(local), name);
    }
  }

  void declareLoop(std::size_t i) {
    std::vector<std::size_t> names;
    auto j = i + 1;
    for (; j < n; ++j) {
      if (word(t[j]) && t[j].text == "in")
        break;
      if (symbol(t[j], "{") || breaks(t[j])) {
        j = n;
        break;
      }
      if (nameable(t[j]) &&
          ((word(t[j - 1]) && t[j - 1].text == "for") ||
           symbol(t[j - 1], "(") || symbol(t[j - 1], ",")) &&
          j + 1 < n &&
          ((word(t[j + 1]) && t[j + 1].text == "in") || symbol(t[j + 1], ",") ||
           symbol(t[j + 1], ")")))
        names.push_back(j);
    }
    if (j >= n || names.empty())
      return;
    auto body = j + 1;
    for (; body < n; ++body) {
      if (symbol(t[body], "{"))
        break;
      if (opener(t[body])) {
        if (index.match[body] >= n)
          return;
        body = index.match[body];
        continue;
      }
      if (breaks(t[body]) || closer(t[body]))
        return;
    }
    if (body >= n)
      return;
    auto signature = slice(t[i].span.begin, t[body].span.begin);
    for (auto name : names) {
      Declaration local;
      local.kind = SymbolKind::Local;
      local.name = t[name].text;
      local.nameBegin = t[name].span.begin;
      local.nameEnd = t[name].span.end;
      local.begin = t[i].span.begin;
      local.end = t[body].span.begin;
      local.signature = signature;
      local.scopeBegin = t[body].span.begin;
      local.scopeEnd = closeOffset(body);
      local.parent = parentDeclaration();
      add(std::move(local), name);
    }
  }

  // A field or enumeration variant: the first word of an entry directly in the
  // body of a product, union or enumeration.
  void declareMember(std::size_t i) {
    auto owner =
        declarations[static_cast<std::size_t>(bodies.back().declaration)].kind;
    bool field = owner == SymbolKind::Type || owner == SymbolKind::Union;
    if ((!field && owner != SymbolKind::Enumeration) || !nameable(t[i]))
      return;
    const Token &before = t[i - 1];
    if (!(symbol(before, "{") || symbol(before, ";") || symbol(before, ",") ||
          before.kind == TokenKind::Newline ||
          (word(before) && before.text == "pub")))
      return;
    if (field && !(i + 1 < n && symbol(t[i + 1], ":")))
      return;
    Declaration member;
    member.kind = field ? SymbolKind::Field : SymbolKind::Variant;
    member.name = t[i].text;
    member.nameBegin = member.begin = t[i].span.begin;
    member.nameEnd = t[i].span.end;
    member.end = endBefore(statementEnd(i, true), i);
    member.signature = slice(member.begin, member.end);
    member.parent = bodies.back().declaration;
    add(std::move(member), i);
  }

  void classify() {
    std::unordered_map<std::string, std::vector<int>> scoped;
    for (std::size_t d = 0; d < declarations.size(); ++d)
      if (declarations[d].scoped())
        scoped[declarations[d].name].push_back(static_cast<int>(d));
    index.byToken.assign(n, -1);
    for (std::size_t i = 0; i < n; ++i) {
      if (!nameable(t[i]))
        continue;
      Occurrence use;
      use.token = i;
      use.begin = t[i].span.begin;
      use.end = t[i].span.end;
      use.name = t[i].text;
      if (auto named = nameTokens.find(i); named != nameTokens.end()) {
        use.role = Role::Declaration;
        use.declaration = named->second;
      } else if (i > 0 && memberAccess(t[i - 1])) {
        use.role = Role::Member;
      } else if (i + 1 < n && symbol(t[i + 1], ":")) {
        use.role = Role::Label;
      } else if (auto found = scoped.find(use.name); found != scoped.end()) {
        // The innermost visible declaration starts its scope last.
        for (int d : found->second) {
          const auto &candidate = declarations[static_cast<std::size_t>(d)];
          if (candidate.scopeBegin > use.begin ||
              use.begin >= candidate.scopeEnd)
            continue;
          if (use.declaration < 0 ||
              candidate.scopeBegin >
                  declarations[static_cast<std::size_t>(use.declaration)]
                      .scopeBegin)
            use.declaration = d;
        }
      }
      index.byToken[i] = static_cast<int>(index.uses.size());
      index.uses.push_back(std::move(use));
    }
  }
};

SymbolIndex::SymbolIndex(const std::string &text) {
  Builder(text, *this).run();
}

const Occurrence *SymbolIndex::occurrenceAt(std::size_t offset) const {
  auto after = std::upper_bound(uses.begin(), uses.end(), offset,
                                [](std::size_t value, const Occurrence &use) {
                                  return value < use.begin;
                                });
  if (after == uses.begin())
    return nullptr;
  const auto &use = *(after - 1);
  return offset <= use.end ? &use : nullptr;
}

std::vector<const Occurrence *>
SymbolIndex::argumentLabels(const Occurrence &callee,
                            const std::string &name) const {
  std::vector<const Occurrence *> labels;
  auto open = callee.token + 1;
  if (open >= tokens.size() || !symbol(tokens[open], "(") ||
      match[open] >= tokens.size())
    return labels;
  for (auto q = open + 1; q < match[open]; ++q) {
    if (opener(tokens[q])) {
      if (match[q] >= tokens.size())
        break;
      q = match[q];
      continue;
    }
    if (tokens[q].text != name || q + 1 >= tokens.size() ||
        !symbol(tokens[q + 1], ":") || byToken[q] < 0)
      continue;
    const auto &before = tokens[q - 1];
    if (symbol(before, "(") || symbol(before, ",") ||
        before.kind == TokenKind::Newline)
      labels.push_back(&uses[static_cast<std::size_t>(byToken[q])]);
  }
  return labels;
}
} // namespace mettle::lsp
