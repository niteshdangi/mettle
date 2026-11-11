#include "expansion/macros.h"
#include "expansion/detail.h"
#include "support/limits.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "syntax/token.h"
#include <algorithm>
#include <cstddef>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace mettle::expansion {
namespace {
constexpr std::size_t none = static_cast<std::size_t>(-1);
// Nesting of expansions (a macro whose output invokes macros). Reaching it is
// a diagnostic that names the expansion path, never a crash.
constexpr unsigned recursionLimit = 256;

// One token of macro input or output. `origin` is where the token was written
// in the original source (a template, or an argument at the use site).
struct Piece {
  TokenKind kind = TokenKind::Word;
  std::string text;
  Span origin;
  bool space = false;
  // Written in a template of the expansion being built; only these may be
  // renamed for hygiene.
  bool authored = false;
  // Written directly after the previous token of a procedural macro's output.
  bool glued = false;
  SyntaxContextPtr context{};
};
using Pieces = std::vector<Piece>;

bool symbol(const Piece &piece, std::string_view text) {
  return piece.kind == TokenKind::Symbol && piece.text == text;
}
bool opener(const Piece &piece) {
  return symbol(piece, "(") || symbol(piece, "[") || symbol(piece, "{");
}
bool closer(const Piece &piece) {
  return symbol(piece, ")") || symbol(piece, "]") || symbol(piece, "}");
}
bool newline(const Piece &piece) { return piece.kind == TokenKind::Newline; }

// Index of the closer of each opener; false when the delimiters do not nest.
bool pairing(const Pieces &pieces, std::vector<std::size_t> &close) {
  close.assign(pieces.size(), none);
  std::vector<std::size_t> open;
  for (std::size_t i = 0; i < pieces.size(); ++i) {
    if (opener(pieces[i])) {
      open.push_back(i);
    } else if (closer(pieces[i])) {
      if (open.empty())
        return false;
      auto start = open.back();
      open.pop_back();
      auto expected = pieces[start].text == "("   ? ")"
                      : pieces[start].text == "[" ? "]"
                                                  : "}";
      if (pieces[i].text != expected)
        return false;
      close[start] = i;
    }
  }
  return open.empty();
}

std::size_t itemExtent(const Pieces &in, const std::vector<std::size_t> &close,
                       std::size_t position, std::size_t end) {
  auto j = position;
  while (j < end && symbol(in[j], "@")) {
    ++j;
    if (j < end && in[j].kind == TokenKind::Word)
      ++j;
    if (j < end && symbol(in[j], "("))
      j = close[j] + 1;
    while (j < end && newline(in[j]))
      ++j;
  }
  auto start = j;
  bool field = j + 1 < end && symbol(in[j + 1], ":");
  bool body = false;
  for (auto k = j; k < end && in[k].kind == TokenKind::Word; ++k) {
    const auto &word = in[k].text;
    if (word == "fn" || word == "init" || word == "type" || word == "enum" ||
        word == "union" || word == "interface" || word == "extend" ||
        word == "module" || word == "macro" || word == "extern") {
      body = true;
      break;
    }
    if (word != "pub" && word != "unsafe" && word != "const" &&
        word != "async" && word != "copy")
      break;
  }
  while (j < end && !closer(in[j])) {
    if (symbol(in[j], "=>"))
      body = false;
    if (opener(in[j])) {
      auto last = close[j];
      if (body && symbol(in[j], "{") &&
          (j == start || in[j - 1].text != "const"))
        return last + 1;
      j = last + 1;
      continue;
    }
    if (newline(in[j])) {
      auto next = j;
      while (next < end && newline(in[next]))
        ++next;
      if (body && next < end &&
          (symbol(in[next], "{") || symbol(in[next], "=>"))) {
        j = next;
        continue;
      }
      break;
    }
    if (symbol(in[j], ";") || (field && symbol(in[j], ",")))
      break;
    ++j;
  }
  return j > start ? j : none;
}

std::optional<Pieces> configure(const Pieces &pieces,
                                const Configuration &configuration,
                                Diagnostics &diagnostics,
                                std::vector<Span> *excluded = nullptr) {
  std::vector<std::size_t> close;
  if (!pairing(pieces, close))
    return std::nullopt;
  std::vector<std::pair<std::size_t, std::size_t>> ranges;
  for (std::size_t i = 0; i < pieces.size(); ++i) {
    if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
        i + 2 < pieces.size() && symbol(pieces[i + 2], "{")) {
      i = close[i + 2];
      continue;
    }
    if (!symbol(pieces[i], "@"))
      continue;
    auto j = i;
    bool enabled = true;
    while (j + 1 < pieces.size() && symbol(pieces[j], "@")) {
      Attribute attribute;
      attribute.span = pieces[j].origin;
      attribute.name = pieces[j + 1].text;
      j += 2;
      if (j < pieces.size() && symbol(pieces[j], "(")) {
        attribute.parenthesized = true;
        auto last = close[j];
        attribute.span.end = pieces[last].origin.end;
        for (++j; j < last; ++j)
          attribute.arguments.push_back({pieces[j].kind, pieces[j].origin,
                                         pieces[j].text, pieces[j].context});
        ++j;
      }
      if (attribute.name == "cfg")
        enabled &= evaluateCfg(attribute, configuration, diagnostics);
      while (j < pieces.size() && newline(pieces[j]))
        ++j;
    }
    if (!enabled) {
      auto last = itemExtent(pieces, close, j, pieces.size());
      if (last != none)
        ranges.emplace_back(i, last);
    }
    i = j ? j - 1 : i;
  }
  if (ranges.empty())
    return std::nullopt;
  Pieces active;
  std::size_t cursor = 0;
  for (auto [first, last] : ranges) {
    if (first < cursor)
      continue;
    active.insert(active.end(), pieces.begin() + cursor,
                  pieces.begin() + first);
    if (excluded)
      excluded->push_back({pieces[first].origin.begin,
                           pieces[last - 1].origin.end,
                           pieces[first].origin.source});
    cursor = last;
  }
  active.insert(active.end(), pieces.begin() + cursor, pieces.end());
  return active;
}

Pieces lower(const Source &source, const std::vector<Token> &tokens,
             const Diagnostics &diagnostics) {
  Pieces result;
  bool space = false;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::End)
      break;
    if (token.kind == TokenKind::Space) {
      space = true;
      continue;
    }
    if (token.kind == TokenKind::Comment) {
      space = true;
      for (std::size_t i = 0; i < token.text.size(); ++i)
        if (token.text[i] == '\r' || token.text[i] == '\n') {
          auto size = token.text[i] == '\r' && i + 1 < token.text.size() &&
                              token.text[i + 1] == '\n'
                          ? 2u
                          : 1u;
          result.push_back({TokenKind::Newline,
                            "\n",
                            {token.span.begin + i, token.span.begin + i + size,
                             token.span.source}});
          i += size - 1;
        }
      continue;
    }
    Piece piece;
    piece.kind = token.kind;
    piece.context = diagnostics.syntaxContext(token.span);
    piece.origin = token.span;
    piece.text = token.kind == TokenKind::Newline
                     ? "\n"
                     : source.text.substr(token.span.begin,
                                          token.span.end - token.span.begin);
    piece.space = space;
    space = false;
    result.push_back(std::move(piece));
  }
  return result;
}

// Whether the generated text separates `piece` from its predecessor. Tokens
// that were adjacent in the source stay adjacent; tokens pasted together from
// different places never fuse.
bool separated(const Piece *previous, const Piece &piece) {
  if (!previous || newline(*previous) || newline(piece) || piece.glued)
    return false;
  if (!piece.space) {
    static const std::set<std::string_view> tight{"(", "[", ".", ",", ")",
                                                  "]", ";", "?", "::"};
    if (piece.kind == TokenKind::Symbol && tight.contains(piece.text))
      return false;
    if (previous->kind == TokenKind::Symbol &&
        (previous->text == "(" || previous->text == "[" ||
         previous->text == "." || previous->text == "::" ||
         previous->text == "!"))
      return false;
  }
  if (piece.space)
    return true;
  return !(previous->origin.source == piece.origin.source &&
           previous->origin.end == piece.origin.begin);
}

std::string render(const Pieces &pieces) {
  std::string text;
  const Piece *previous = nullptr;
  for (const auto &piece : pieces) {
    if (separated(previous, piece))
      text += ' ';
    text += piece.text;
    previous = &piece;
  }
  return text;
}

// ---------------------------------------------------------------------------
// Matchers and templates.

enum class Form { Literal, Variable, Repetition, Capture };
struct Node {
  Form form = Form::Literal;
  // The literal token, or the `$` that introduces the other forms.
  Piece piece;
  std::string name, fragment;
  std::vector<Node> body;
  // The repetition separator, or the identifier of `$capture(name)`.
  std::optional<Piece> separator;
  char op = '*';
};

bool knownFragment(const std::string &fragment) {
  static const std::set<std::string> known{
      "expr", "expression", "stmt",  "statement", "pat",        "pattern",
      "ty",   "type",       "path",  "ident",     "identifier", "literal",
      "tt",   "token-tree", "block", "item"};
  return known.contains(fragment);
}

std::string fragmentKind(std::string fragment) {
  if (fragment == "expression")
    return "expr";
  if (fragment == "statement")
    return "stmt";
  if (fragment == "pattern")
    return "pat";
  if (fragment == "type")
    return "ty";
  if (fragment == "identifier")
    return "ident";
  if (fragment == "token-tree")
    return "tt";
  return fragment;
}

bool repetitionOperator(const Pieces &tokens, std::size_t at, std::size_t end) {
  return at < end && tokens[at].kind == TokenKind::Symbol &&
         (tokens[at].text == "*" || tokens[at].text == "+" ||
          tokens[at].text == "?");
}

bool parseNodes(const Pieces &tokens, const std::vector<std::size_t> &close,
                std::size_t i, std::size_t end, bool matcher,
                Diagnostics &diagnostics, std::vector<Node> &nodes) {
  bool ok = true;
  auto fail = [&](const Piece &at, std::string message) {
    diagnostics.error("macro", at.origin, std::move(message));
    ok = false;
  };
  while (i < end) {
    const auto &piece = tokens[i];
    if (matcher && newline(piece)) {
      ++i;
      continue;
    }
    if (!symbol(piece, "$")) {
      Node node;
      node.piece = piece;
      nodes.push_back(std::move(node));
      ++i;
      continue;
    }
    if (i + 1 >= end) {
      fail(piece, "expected a metavariable, a repetition or $capture after "
                  "'$'");
      break;
    }
    const auto &next = tokens[i + 1];
    if (symbol(next, "(")) {
      Node node;
      node.form = Form::Repetition;
      node.piece = piece;
      auto inner = close[i + 1];
      ok &= parseNodes(tokens, close, i + 2, inner, matcher, diagnostics,
                       node.body);
      auto after = inner + 1;
      if (repetitionOperator(tokens, after, end)) {
        node.op = tokens[after].text[0];
        i = after + 1;
      } else if (after < end && !opener(tokens[after]) &&
                 !closer(tokens[after]) && !newline(tokens[after]) &&
                 repetitionOperator(tokens, after + 1, end)) {
        node.separator = tokens[after];
        node.op = tokens[after + 1].text[0];
        if (node.op == '?')
          fail(tokens[after], "an optional repetition cannot have a "
                              "separator");
        i = after + 2;
      } else {
        fail(piece, "a repetition needs '*', '+' or '?', optionally after one "
                    "separator token");
        i = after;
      }
      nodes.push_back(std::move(node));
      continue;
    }
    if (next.kind != TokenKind::Word) {
      fail(piece, "expected a metavariable name after '$'");
      i += 2;
      continue;
    }
    Node node;
    node.piece = piece;
    if (!matcher && next.text == "capture" && i + 4 < end &&
        symbol(tokens[i + 2], "(") && tokens[i + 3].kind == TokenKind::Word &&
        symbol(tokens[i + 4], ")")) {
      node.form = Form::Capture;
      node.separator = tokens[i + 3];
      nodes.push_back(std::move(node));
      i += 5;
      continue;
    }
    node.form = Form::Variable;
    node.name = next.text;
    i += 2;
    if (matcher) {
      if (i + 1 < end && symbol(tokens[i], ":") &&
          tokens[i + 1].kind == TokenKind::Word) {
        auto spelling = tokens[i + 1].text;
        if (!knownFragment(spelling))
          fail(tokens[i + 1],
               "unknown fragment kind '" + spelling +
                   "'; expected expression/expr, statement/stmt, pattern/pat, "
                   "type/ty, path, identifier/ident, literal, token-tree/tt, "
                   "block or item");
        node.fragment = fragmentKind(std::move(spelling));
        i += 2;
      } else {
        fail(next, "metavariable '$" + node.name +
                       "' needs a fragment kind, as in $" + node.name +
                       ":expr");
      }
    }
    nodes.push_back(std::move(node));
  }
  return ok;
}

void trimNewlines(std::vector<Node> &nodes) {
  auto blank = [](const Node &node) {
    return node.form == Form::Literal && newline(node.piece);
  };
  while (!nodes.empty() && blank(nodes.front()))
    nodes.erase(nodes.begin());
  while (!nodes.empty() && blank(nodes.back()))
    nodes.pop_back();
}

// Variables with the repetition depth at which the matcher binds them.
void variables(const std::vector<Node> &nodes, unsigned depth,
               std::map<std::string, unsigned> &found) {
  for (const auto &node : nodes) {
    if (node.form == Form::Variable)
      found[node.name] = depth;
    else if (node.form == Form::Repetition)
      variables(node.body, depth + 1, found);
  }
}

void names(const std::vector<Node> &nodes, std::set<std::string> &found) {
  for (const auto &node : nodes) {
    if (node.form == Form::Variable)
      found.insert(node.name);
    else if (node.form == Form::Repetition)
      names(node.body, found);
  }
}

void verify(const std::string &macro, const std::vector<Node> &nodes,
            unsigned depth, const std::map<std::string, unsigned> &bound,
            Diagnostics &diagnostics, bool &ok) {
  for (const auto &node : nodes) {
    if (node.form == Form::Repetition) {
      verify(macro, node.body, depth + 1, bound, diagnostics, ok);
      continue;
    }
    if (node.form != Form::Variable)
      continue;
    auto found = bound.find(node.name);
    if (found == bound.end()) {
      diagnostics.error("macro", node.piece.origin,
                        "unbound metavariable '$" + node.name +
                            "' in an expansion of macro '" + macro + "'");
      ok = false;
    } else if (found->second > depth) {
      diagnostics.error("macro", node.piece.origin,
                        "metavariable '$" + node.name + "' is bound " +
                            std::to_string(found->second) +
                            " repetition level(s) deep but used at depth " +
                            std::to_string(depth) + "; repeat it with $(...)");
      ok = false;
    }
  }
}

struct Follower {
  std::string text;
  bool variable = false;
};

std::vector<Follower> starts(const std::vector<Node> &nodes, std::size_t index,
                             const std::vector<Follower> &outer) {
  if (index >= nodes.size())
    return outer;
  const auto &node = nodes[index];
  if (node.form == Form::Literal)
    return {{node.piece.text, false}};
  if (node.form == Form::Variable)
    return {{"", true}};
  std::vector<Follower> result;
  if (!node.body.empty())
    result = starts(node.body, 0, {});
  if (node.op != '+') {
    auto skipped = starts(nodes, index + 1, outer);
    result.insert(result.end(), skipped.begin(), skipped.end());
  }
  return result;
}

bool allowedAfter(const std::string &fragment, const Follower &follower) {
  static const std::set<std::string> flexible{"ident", "literal", "tt", "block",
                                              "item"};
  if (flexible.contains(fragment))
    return true;
  if (follower.variable)
    return false;
  const auto &text = follower.text;
  if (text.empty() || text == ")" || text == "]" || text == "}" || text == "=>")
    return true;
  if (fragment == "expr" || fragment == "stmt")
    return text == "," || text == ";";
  if (fragment == "pat")
    return text == "," || text == "=" || text == "if" || text == "in";
  static const std::set<std::string> typed{",",  "=", ";", ":",    ">",
                                           ">>", "{", "[", "where"};
  return typed.contains(text);
}

void checkFollow(const std::vector<Node> &nodes,
                 const std::vector<Follower> &outer, Diagnostics &diagnostics,
                 bool &ok) {
  for (std::size_t i = 0; i < nodes.size(); ++i) {
    const auto &node = nodes[i];
    auto next = starts(nodes, i + 1, outer);
    if (node.form == Form::Variable) {
      for (const auto &follower : next)
        if (!allowedAfter(node.fragment, follower)) {
          diagnostics.error(
              "macro", node.piece.origin,
              "fragment '$" + node.name + ":" + node.fragment +
                  "' cannot be followed by " +
                  (follower.variable ? std::string("another metavariable")
                                     : "'" + follower.text + "'") +
                  "; the follow set of " + node.fragment + " is " +
                  (node.fragment == "pat"
                       ? "'=>', ',', '=', 'if', 'in' or a closing delimiter"
                   : node.fragment == "expr" || node.fragment == "stmt"
                       ? "'=>', ',', ';' or a closing delimiter"
                       : "'=>', ',', '=', ';', ':', '>', '>>', '{', '[', "
                         "'where' or a closing delimiter"));
          ok = false;
          break;
        }
    } else if (node.form == Form::Repetition) {
      std::vector<Follower> inner = next;
      if (node.op != '?' && node.separator)
        inner.push_back({node.separator->text, false});
      else if (node.op != '?') {
        auto again = starts(node.body, 0, {});
        inner.insert(inner.end(), again.begin(), again.end());
      }
      checkFollow(node.body, inner, diagnostics, ok);
    }
  }
}

struct Rule {
  std::vector<Node> matcher, expansion;
};
using MacroSources = std::map<SourceId, MacroSource>;
struct Macro {
  std::string name;
  Span span;
  std::vector<std::string> definitionScope;
  std::vector<std::string> visibilityBoundary;
  bool publicItem = false;
  std::vector<Rule> rules;
  std::shared_ptr<const MacroSources> importedSources{};
  std::string importedOwner{};
};

struct MacroBinding {
  const Macro *macro = nullptr;
  std::vector<std::string> visibilityBoundary;
  bool publicItem = false;
  bool ambiguous = false;
};
using MacroIndex = std::map<std::string, Macro>;
using ImportedMacroIndex = std::map<std::string, std::vector<MacroBinding>>;
using IndexedModules = std::set<std::string>;
struct PendingMacroImport {
  std::vector<std::string> scope, path;
  std::string alias, name;
  VisibilitySyntax visibility;
  bool resolved = false;
  std::shared_ptr<const MacroSources> importedSources{};
};
using PendingMacroImports = std::vector<PendingMacroImport>;
struct ImportedModule {
  std::vector<std::string> definitions;
  std::vector<std::size_t> imports;
  std::vector<std::vector<std::string>> declared;
};
using ImportedModules = std::map<std::string, ImportedModule>;

std::string scopeKey(const std::vector<std::string> &scope) {
  std::string key;
  for (const auto &part : scope)
    key += (key.empty() ? "" : "::") + part;
  return key;
}

std::optional<std::string> owningModule(const std::vector<std::string> &scope,
                                        const IndexedModules &indexed) {
  auto key = scopeKey(scope);
  for (;;) {
    if (indexed.contains(key))
      return key;
    if (key.empty())
      return std::nullopt;
    auto separator = key.rfind("::");
    key.resize(separator == std::string::npos ? 0 : separator);
  }
}

using LogicalLocation =
    std::tuple<std::string, std::uint32_t, std::size_t, std::size_t>;
std::optional<LogicalLocation> logicalLocation(Span span,
                                               const MacroSources &sources) {
  if (span.source == 0 && span.begin == 0 && span.end == 0)
    return LogicalLocation{};
  auto source = sources.find(span.source);
  if (source == sources.end())
    return std::nullopt;
  return LogicalLocation{source->second.identity, source->second.bytes,
                         span.begin, span.end};
}

using ImportKey =
    std::tuple<std::vector<std::string>, std::vector<std::string>, std::string,
               std::string, bool, std::vector<std::string>, LogicalLocation>;
std::optional<ImportKey> importKey(const PendingMacroImport &import) {
  if (!import.importedSources)
    return std::nullopt;
  auto location =
      logicalLocation(import.visibility.span, *import.importedSources);
  if (!location)
    return std::nullopt;
  return ImportKey{import.scope,
                   import.path,
                   import.alias,
                   import.name,
                   import.visibility.publicItem,
                   import.visibility.restriction,
                   std::move(*location)};
}

class MacroEquality {
public:
  bool run(const Macro &left, const Macro &right) {
    if (!left.importedSources || !right.importedSources ||
        left.name != right.name || left.importedOwner != right.importedOwner ||
        left.definitionScope != right.definitionScope ||
        left.visibilityBoundary != right.visibilityBoundary ||
        left.publicItem != right.publicItem ||
        left.rules.size() != right.rules.size())
      return false;
    leftSources = left.importedSources.get();
    rightSources = right.importedSources.get();
    if (!location(left.span, right.span))
      return false;
    for (std::size_t i = 0; i < left.rules.size(); ++i)
      if (!nodes(left.rules[i].matcher, right.rules[i].matcher) ||
          !nodes(left.rules[i].expansion, right.rules[i].expansion))
        return false;
    return true;
  }

  SyntaxContextPtr canonicalContext(const SyntaxContextPtr &context) {
    if (!context || context->identity == 0)
      return context;
    auto known = reverseBinders.find(context->identity);
    if (known == reverseBinders.end())
      return context;
    auto [canonical, inserted] =
        canonicalContexts.try_emplace(context->identity);
    if (inserted)
      canonical->second = std::make_shared<const SyntaxContext>(
          SyntaxContext{context->scope, context->definition, known->second});
    return canonical->second;
  }

private:
  const MacroSources *leftSources = nullptr, *rightSources = nullptr;
  std::map<std::uint64_t, std::uint64_t> binders, reverseBinders;
  std::map<std::uint64_t, SyntaxContextPtr> canonicalContexts;
  bool location(Span left, Span right) const {
    auto first = logicalLocation(left, *leftSources);
    auto second = logicalLocation(right, *rightSources);
    return first && second && *first == *second;
  }
  bool context(const SyntaxContextPtr &left, const SyntaxContextPtr &right) {
    if (!left || !right)
      return !left && !right;
    if (left->scope != right->scope ||
        !location(left->definition, right->definition) ||
        (left->identity == 0) != (right->identity == 0))
      return false;
    if (left->identity == 0)
      return true;
    auto [first, inserted] = binders.emplace(left->identity, right->identity);
    auto [second, reverseInserted] =
        reverseBinders.emplace(right->identity, left->identity);
    return first->second == right->identity &&
           second->second == left->identity && inserted == reverseInserted;
  }
  bool token(const Piece &left, const Piece &right) {
    return left.kind == right.kind && left.text == right.text &&
           left.space == right.space && left.authored == right.authored &&
           left.glued == right.glued && location(left.origin, right.origin) &&
           context(left.context, right.context);
  }
  bool nodes(const std::vector<Node> &left, const std::vector<Node> &right) {
    if (left.size() != right.size())
      return false;
    for (std::size_t i = 0; i < left.size(); ++i) {
      const auto &first = left[i];
      const auto &second = right[i];
      if (first.form != second.form || first.name != second.name ||
          first.fragment != second.fragment || first.op != second.op ||
          !token(first.piece, second.piece) ||
          first.separator.has_value() != second.separator.has_value() ||
          (first.separator && !token(*first.separator, *second.separator)) ||
          !nodes(first.body, second.body))
        return false;
    }
    return true;
  }
};

class LibraryExporter {
public:
  LibraryExporter(Diagnostics &diagnostics, const MacroSourceIdentity &identify)
      : diagnostics(diagnostics), identify(identify) {}

  std::optional<MacroLibrary>
  run(const MacroIndex &macros, const PendingMacroImports &imports,
      const IndexedModules &indexed,
      const std::set<std::vector<std::string>> &declared) {
    if (!identify) {
      fail("macro export requires revision-qualified source identities");
      return std::nullopt;
    }
    for (const auto &[key, macro] : macros) {
      MacroDefinition definition;
      definition.name = macro.name;
      definition.location = location(macro.span);
      definition.scope = macro.definitionScope;
      definition.visibilityBoundary = macro.visibilityBoundary;
      definition.publicItem = macro.publicItem;
      for (const auto &rule : macro.rules)
        definition.rules.push_back(
            {nodes(rule.matcher), nodes(rule.expansion)});
      library.definitions.push_back(std::move(definition));
    }
    for (const auto &import : imports)
      library.imports.push_back({import.scope, import.path, import.alias,
                                 import.name, import.visibility.publicItem,
                                 import.visibility.restriction,
                                 location(import.visibility.span)});
    library.indexedModules.assign(indexed.begin(), indexed.end());
    library.declaredModules.assign(declared.begin(), declared.end());
    if (!good || !validateMacros(library, diagnostics))
      return std::nullopt;
    return std::move(library);
  }

private:
  Diagnostics &diagnostics;
  const MacroSourceIdentity &identify;
  MacroLibrary library;
  std::map<SourceId, std::uint32_t> sources;
  std::map<std::string, std::uint32_t> sourceIdentities;
  std::map<const SyntaxContext *, std::uint32_t> contexts;
  std::map<std::uint64_t, std::uint32_t> hygienicContexts;
  bool good = true;
  void fail(std::string message) {
    good = false;
    diagnostics.error("macro", {}, std::move(message));
  }
  MacroLocation location(Span span) {
    if (span.source == 0 && span.begin == 0 && span.end == 0)
      return {};
    if (span.begin > span.end || span.end > limits::sourceBytes) {
      fail("macro export has an invalid source span");
      return {};
    }
    auto known = sources.find(span.source);
    if (known == sources.end()) {
      const auto &registered = diagnostics.registeredSources();
      auto source = std::find_if(
          registered.begin(), registered.end(),
          [&](const Source &entry) { return entry.id == span.source; });
      if (source == registered.end() ||
          source->text.size() > limits::sourceBytes) {
        fail("macro export requires registered source provenance");
        return {};
      }
      auto identity = identify(*source);
      if (identity.empty()) {
        fail("macro export requires a source revision identity");
        return {};
      }
      auto index = static_cast<std::uint32_t>(library.sources.size());
      auto [existing, inserted] = sourceIdentities.emplace(identity, index);
      if (inserted) {
        library.sources.push_back(
            {std::move(identity), source->path,
             static_cast<std::uint32_t>(source->text.size())});
      } else {
        index = existing->second;
        if (library.sources[index].bytes != source->text.size())
          fail("macro source identity has conflicting byte extents");
      }
      known = sources.emplace(span.source, index).first;
    }
    return {known->second, static_cast<std::uint32_t>(span.begin),
            static_cast<std::uint32_t>(span.end)};
  }
  MacroToken token(const Piece &piece) {
    MacroToken result{piece.kind,  piece.text,     location(piece.origin),
                      piece.space, piece.authored, piece.glued,
                      {}};
    if (piece.context) {
      auto found = contexts.find(piece.context.get());
      if (found == contexts.end()) {
        auto index = static_cast<std::uint32_t>(library.contexts.size());
        bool inserted = true;
        if (piece.context->identity != 0) {
          auto [group, fresh] =
              hygienicContexts.emplace(piece.context->identity, index);
          index = group->second;
          inserted = fresh;
        }
        if (inserted)
          library.contexts.push_back({piece.context->scope,
                                      location(piece.context->definition),
                                      piece.context->identity != 0});
        found = contexts.emplace(piece.context.get(), index).first;
      }
      result.context = found->second;
    }
    return result;
  }
  std::vector<MacroNode> nodes(const std::vector<Node> &input,
                               unsigned depth = 0) {
    std::vector<MacroNode> result;
    if (input.empty())
      return result;
    if (depth >= limits::syntaxDepth) {
      fail("macro export exceeds the syntax nesting limit");
      return result;
    }
    for (const auto &node : input) {
      MacroNode converted;
      converted.kind = static_cast<MacroNodeKind>(node.form);
      converted.token = token(node.piece);
      converted.name = node.name;
      converted.fragment = node.fragment;
      converted.body = nodes(node.body, depth + 1);
      if (node.separator)
        converted.separator = token(*node.separator);
      converted.repetition = node.op;
      result.push_back(std::move(converted));
    }
    return result;
  }
};

class LibraryImporter {
  struct ModuleCandidate {
    std::vector<std::string> definitions;
    std::vector<PendingMacroImport> imports;
    std::vector<std::vector<std::string>> declared;
  };

public:
  LibraryImporter(const MacroLibrary &library, Diagnostics &diagnostics,
                  const MacroSourceRemap &remap)
      : library(library), diagnostics(diagnostics), remap(remap) {}

  bool run(MacroIndex &macros, PendingMacroImports &imports,
           IndexedModules &indexed,
           std::set<std::vector<std::string>> &declared,
           ImportedModules &importedModules) {
    if (!validateMacros(library, diagnostics))
      return false;
    IndexedModules moduleRoots(library.indexedModules.begin(),
                               library.indexedModules.end());
    std::map<std::string, ModuleCandidate> modules;
    for (const auto &root : moduleRoots)
      modules.emplace(root, ModuleCandidate{});
    std::set<SourceId> identities;
    auto origins = std::make_shared<MacroSources>();
    for (const auto &source : library.sources) {
      auto id = remap ? remap(source) : std::nullopt;
      if (!id || !identities.insert(*id).second)
        return fail("compiled macro source identity could not be remapped");
      sources.push_back(*id);
      origins->emplace(*id, source);
    }
    for (const auto &context : library.contexts) {
      auto definition = location(context.definition);
      contexts.push_back(
          context.hygienic
              ? diagnostics.makeSyntaxContext(context.scope, definition)
              : std::make_shared<const SyntaxContext>(
                    SyntaxContext{context.scope, definition, 0}));
    }
    MacroIndex incoming;
    for (const auto &definition : library.definitions) {
      std::string key;
      for (const auto &part : definition.scope)
        key += part + "::";
      key += definition.name;
      auto owner = owningModule(definition.scope, moduleRoots);
      if (!owner)
        return fail("compiled macro definition has no owning module");
      Macro macro{definition.name,       location(definition.location),
                  definition.scope,      definition.visibilityBoundary,
                  definition.publicItem, {}};
      macro.importedSources = origins;
      macro.importedOwner = *owner;
      for (const auto &rule : definition.rules) {
        Rule converted{nodes(rule.matcher), nodes(rule.expansion)};
        if (!good)
          return false;
        std::map<std::string, unsigned> bound;
        variables(converted.matcher, 0, bound);
        verify(macro.name, converted.expansion, 0, bound, diagnostics, good);
        checkFollow(converted.matcher, {{"", false}}, diagnostics, good);
        if (!good)
          return false;
        macro.rules.push_back(std::move(converted));
      }
      modules[*owner].definitions.push_back(key);
      incoming.emplace(std::move(key), std::move(macro));
    }
    for (const auto &import : library.imports) {
      auto owner = owningModule(import.scope, moduleRoots);
      if (!owner)
        return fail("compiled macro import has no owning module");
      VisibilitySyntax visibility;
      visibility.publicItem = import.publicItem;
      visibility.restriction = import.restriction;
      visibility.span = location(import.location);
      modules[*owner].imports.push_back(
          {import.scope, import.path, import.alias, import.name,
           std::move(visibility), false, origins});
    }
    for (const auto &module : library.declaredModules) {
      if (module.empty())
        return fail("compiled macro module declaration has no name");
      auto parent = module;
      parent.pop_back();
      auto owner = owningModule(parent, moduleRoots);
      if (!owner)
        return fail("compiled macro module declaration has no owner");
      modules[*owner].declared.push_back(module);
    }
    for (auto &[owner, candidate] : modules) {
      std::sort(candidate.definitions.begin(), candidate.definitions.end());
      std::sort(candidate.declared.begin(), candidate.declared.end());
      auto known = importedModules.find(owner);
      if (known == importedModules.end())
        continue;
      if (candidate.definitions != known->second.definitions ||
          candidate.declared != known->second.declared)
        return fail("compiled macro module conflicts with an existing module");
      std::map<ImportKey, std::size_t> oldImports, newImports;
      for (auto index : known->second.imports) {
        if (index >= imports.size())
          return fail("compiled macro import index is invalid");
        auto key = importKey(imports[index]);
        if (!key)
          return fail("compiled macro import provenance is invalid");
        ++oldImports[*key];
      }
      for (const auto &import : candidate.imports) {
        auto key = importKey(import);
        if (!key)
          return fail("compiled macro import provenance is invalid");
        ++newImports[*key];
      }
      if (oldImports != newImports)
        return fail(
            "compiled macro reexports conflict with an existing module");
    }
    MacroEquality equality;
    for (const auto &[key, macro] : incoming) {
      auto known = macros.find(key);
      if (known != macros.end() && !equality.run(known->second, macro))
        return fail("compiled macro conflicts with an existing definition");
    }
    for (auto next = incoming.begin(); next != incoming.end();) {
      if (macros.contains(next->first))
        next = incoming.erase(next);
      else {
        for (auto &rule : next->second.rules) {
          canonicalContexts(rule.matcher, equality);
          canonicalContexts(rule.expansion, equality);
        }
        ++next;
      }
    }
    macros.merge(incoming);
    for (auto &[owner, candidate] : modules) {
      if (importedModules.contains(owner))
        continue;
      ImportedModule admitted;
      admitted.definitions = std::move(candidate.definitions);
      admitted.declared = std::move(candidate.declared);
      for (auto &import : candidate.imports) {
        admitted.imports.push_back(imports.size());
        imports.push_back(std::move(import));
      }
      importedModules.emplace(owner, std::move(admitted));
    }
    indexed.insert(library.indexedModules.begin(),
                   library.indexedModules.end());
    declared.insert(library.declaredModules.begin(),
                    library.declaredModules.end());
    return true;
  }

private:
  const MacroLibrary &library;
  Diagnostics &diagnostics;
  const MacroSourceRemap &remap;
  std::vector<SourceId> sources;
  std::vector<SyntaxContextPtr> contexts;
  bool good = true;
  void canonicalContexts(std::vector<Node> &nodes, MacroEquality &equality) {
    for (auto &node : nodes) {
      node.piece.context = equality.canonicalContext(node.piece.context);
      if (node.separator)
        node.separator->context =
            equality.canonicalContext(node.separator->context);
      canonicalContexts(node.body, equality);
    }
  }
  bool fail(std::string message) {
    diagnostics.error("macro", {}, std::move(message));
    good = false;
    return false;
  }
  Span location(const MacroLocation &value) const {
    return value.source == UINT32_MAX
               ? Span{}
               : Span{value.begin, value.end, sources[value.source]};
  }
  Piece token(const MacroToken &value) const {
    return {value.kind,
            value.text,
            location(value.origin),
            value.space,
            value.authored,
            value.glued,
            value.context ? contexts[*value.context] : SyntaxContextPtr{}};
  }
  std::vector<Node> nodes(const std::vector<MacroNode> &input) {
    std::vector<Node> result;
    for (const auto &node : input) {
      if (node.kind == MacroNodeKind::Variable && !node.fragment.empty() &&
          !knownFragment(node.fragment)) {
        fail("compiled macro contains an unknown fragment kind");
        return {};
      }
      Node converted;
      converted.form = static_cast<Form>(node.kind);
      converted.piece = token(node.token);
      converted.name = node.name;
      converted.fragment = node.fragment;
      converted.body = nodes(node.body);
      if (node.separator)
        converted.separator = token(*node.separator);
      converted.op = node.repetition;
      result.push_back(std::move(converted));
    }
    return result;
  }
};

struct MacroDiscovery {
  using Request =
      std::tuple<std::vector<std::string>, std::vector<std::string>, bool>;
  std::map<Request, std::optional<std::vector<std::string>>> modules;
  std::set<std::string> requested;
  bool resolving = false;
};

struct Binding {
  bool list = false;
  std::string fragment;
  Pieces tokens;
  std::vector<Binding> items;
};
using Scope = std::map<std::string, Binding>;
using Environment = std::map<std::string, const Binding *>;

void wrap(const std::string &fragment, std::string &text) {
  if (fragment == "expr" || fragment == "block") {
    text = "async fn __fragment() { let __value = " + text + "\n}";
  } else if (fragment == "stmt") {
    text = "async fn __fragment() { " + text + "\n}";
  } else if (fragment == "pat") {
    text = "fn __fragment() { match 0 { " + text + " => 0 } }";
  } else if (fragment == "ty") {
    text = "fn __fragment(__value: " + text + ") { }";
  }
}

// Fragments that are not a single token invoke the native parser on the
// tokens they captured, inside a context that accepts that fragment kind.
bool parses(const std::string &fragment, const Pieces &tokens) {
  auto kind = fragmentKind(fragment);
  if (kind == "ident" || kind == "literal" || kind == "tt" || kind == "path")
    return true;
  auto text = render(tokens);
  wrap(kind, text);
  Source probe{"<macro fragment>", std::move(text), 0};
  Diagnostics scratch;
  parseDeclarations(probe, scratch);
  return scratch.empty();
}

bool parsesExpression(const Pieces &tokens) {
  auto text =
      "async fn __fragment() { let __value = (" + render(tokens) + ")\n}";
  Source probe{"<macro expression>", std::move(text), 0};
  Diagnostics scratch;
  parseDeclarations(probe, scratch);
  return scratch.empty();
}

class Recognizer {
public:
  Recognizer(const Pieces &input, const std::vector<std::size_t> &close)
      : in(input), close(close) {
    std::string text;
    const Piece *previous = nullptr;
    for (const auto &piece : input) {
      if (separated(previous, piece))
        text += ' ';
      offsets.push_back(text.size());
      text += piece.text;
      previous = &piece;
    }
    offsets.push_back(text.size());
    parser = std::make_unique<FragmentParser>(std::move(text));
  }

  bool run(const std::vector<Node> &nodes) {
    std::size_t position = 0;
    if (!match(nodes, position, in.size(), scope))
      return false;
    skip(position, in.size());
    return position == in.size();
  }
  Scope scope;

private:
  const Pieces &in;
  const std::vector<std::size_t> &close;
  std::vector<std::size_t> offsets;
  std::unique_ptr<FragmentParser> parser;

  void skip(std::size_t &position, std::size_t end) const {
    while (position < end && newline(in[position]))
      ++position;
  }

  bool token(const Piece &wanted, std::size_t &position,
             std::size_t end) const {
    if (symbol(wanted, ";")) {
      if (position < end && symbol(in[position], ";")) {
        ++position;
        return true;
      }
      if (position < end && newline(in[position])) {
        skip(position, end);
        return true;
      }
      return false;
    }
    skip(position, end);
    if (position < end && in[position].kind == wanted.kind &&
        in[position].text == wanted.text) {
      ++position;
      return true;
    }
    return false;
  }

  std::size_t after(std::size_t at) const {
    if (opener(in[at]))
      return close[at] + 1;
    if (in[at].kind == TokenKind::FormatOpen) {
      unsigned depth = 0;
      for (std::size_t j = at; j < in.size(); ++j) {
        if (in[j].kind == TokenKind::FormatOpen)
          ++depth;
        else if (in[j].kind == TokenKind::FormatClose && --depth == 0)
          return j + 1;
      }
      return in.size();
    }
    return at + 1;
  }

  std::size_t itemExtent(std::size_t position, std::size_t end) const {
    return expansion::itemExtent(in, close, position, end);
  }

  std::size_t extent(const std::string &fragment, std::size_t position,
                     std::size_t end) const {
    if (position >= end)
      return none;
    const auto &first = in[position];
    if (fragment == "ident")
      return (first.kind == TokenKind::Word && !isReservedWord(first.text)) ||
                     first.kind == TokenKind::QuotedWord
                 ? position + 1
                 : none;
    if (fragment == "literal") {
      auto j = position;
      if (symbol(first, "-") && j + 1 < end &&
          (in[j + 1].kind == TokenKind::Integer ||
           in[j + 1].kind == TokenKind::Floating))
        ++j;
      auto kind = in[j].kind;
      bool literal = kind == TokenKind::Integer ||
                     kind == TokenKind::Floating || kind == TokenKind::Text ||
                     kind == TokenKind::PrefixedText ||
                     kind == TokenKind::Character || kind == TokenKind::Byte ||
                     (j == position && kind == TokenKind::Word &&
                      (in[j].text == "true" || in[j].text == "false"));
      return literal ? j + 1 : none;
    }
    if (fragment == "tt")
      return closer(first) ? none : after(position);
    if (fragment == "block")
      return symbol(first, "{") ? close[position] + 1 : none;
    if (fragment == "item")
      return itemExtent(position, end);
    auto parsed = parser->end(fragment, offsets[position]);
    if (!parsed)
      return none;
    auto boundary = std::lower_bound(offsets.begin() + position,
                                     offsets.begin() + end + 1, *parsed);
    if (boundary == offsets.begin() + end + 1 || *boundary != *parsed)
      return none;
    auto stop = static_cast<std::size_t>(boundary - offsets.begin());
    return stop > position ? stop : none;
  }

  bool match(const std::vector<Node> &nodes, std::size_t &position,
             std::size_t end, Scope &bound) {
    for (const auto &node : nodes) {
      if (node.form == Form::Literal) {
        if (!token(node.piece, position, end))
          return false;
      } else if (node.form == Form::Variable) {
        skip(position, end);
        auto stop = extent(node.fragment, position, end);
        if (stop == none)
          return false;
        Pieces taken(in.begin() + position, in.begin() + stop);
        while (!taken.empty() && newline(taken.back()))
          taken.pop_back();
        if (taken.empty() || !parses(node.fragment, taken))
          return false;
        bound[node.name] = Binding{false, node.fragment, std::move(taken), {}};
        position = stop;
      } else if (node.form == Form::Repetition) {
        if (!repeat(node, position, end, bound))
          return false;
      }
    }
    return true;
  }

  bool repeat(const Node &node, std::size_t &position, std::size_t end,
              Scope &bound) {
    std::vector<Scope> iterations;
    while (!(node.op == '?' && iterations.size() == 1)) {
      auto saved = position;
      if (!iterations.empty() && node.separator &&
          !token(*node.separator, position, end))
        break;
      skip(position, end);
      if (position >= end) {
        position = saved;
        break;
      }
      Scope inner;
      auto started = position;
      if (!match(node.body, position, end, inner) || position == started) {
        position = saved;
        break;
      }
      iterations.push_back(std::move(inner));
    }
    if (node.op == '+' && iterations.empty())
      return false;
    std::set<std::string> inside;
    names(node.body, inside);
    for (const auto &name : inside) {
      Binding list;
      list.list = true;
      for (auto &iteration : iterations)
        list.items.push_back(std::move(iteration[name]));
      bound[name] = std::move(list);
    }
    return true;
  }
};

class Expander {
public:
  Expander(
      const Source &source, Diagnostics &diagnostics,
      const SourceAllocator &allocate, const Procedures *procedures,
      std::vector<std::string> modulePath,
      const MacroModuleProvider &modules = {},
      std::shared_ptr<MacroIndex> macroIndex = {},
      std::shared_ptr<ImportedMacroIndex> importIndex = {},
      std::shared_ptr<IndexedModules> indexedIndex = {},
      std::shared_ptr<PendingMacroImports> pendingIndex = {},
      std::vector<Module::MacroDeclaration> *declarations = nullptr,
      const MacroModuleProvider &importModules = {},
      std::shared_ptr<std::set<std::vector<std::string>>> declaredIndex = {},
      std::shared_ptr<MacroDiscovery> discoveryIndex = {},
      const Configuration *configuration = nullptr,
      std::shared_ptr<ImportedModules> compiledIndex = {},
      std::shared_ptr<std::set<std::vector<std::string>>> inlineIndex = {})
      : source(source), diagnostics(diagnostics), allocate(allocate),
        procedures(procedures), modulePath(std::move(modulePath)),
        modules(modules), importModules(importModules),
        configuration(configuration),
        macros(macroIndex ? std::move(macroIndex)
                          : std::make_shared<MacroIndex>()),
        importedMacros(importIndex ? std::move(importIndex)
                                   : std::make_shared<ImportedMacroIndex>()),
        indexedModules(indexedIndex ? std::move(indexedIndex)
                                    : std::make_shared<IndexedModules>()),
        pendingImports(pendingIndex ? std::move(pendingIndex)
                                    : std::make_shared<PendingMacroImports>()),
        declarations(declarations),
        declaredModules(
            declaredIndex
                ? std::move(declaredIndex)
                : std::make_shared<std::set<std::vector<std::string>>>()),
        discovery(discoveryIndex ? std::move(discoveryIndex)
                                 : std::make_shared<MacroDiscovery>()),
        compiledModules(compiledIndex ? std::move(compiledIndex)
                                      : std::make_shared<ImportedModules>()),
        inlineModules(
            inlineIndex
                ? std::move(inlineIndex)
                : std::make_shared<std::set<std::vector<std::string>>>()) {}

  std::optional<Source> run(bool definitionsOnly = false) {
    std::string moduleKey;
    for (const auto &part : modulePath)
      moduleKey += (moduleKey.empty() ? "" : "::") + part;
    // Recursive import indexing must not redefine this source's macros.
    indexedModules->insert(std::move(moduleKey));
    Diagnostics scratch;
    auto tokens = tokenize(source, scratch);
    if (!scratch.empty())
      return std::nullopt;
    pieces = lower(source, tokens, diagnostics);
    if (!pairing(pieces, close))
      return std::nullopt;
    Diagnostics::SourceContext context(diagnostics, source);
    if (configuration)
      if (auto active =
              configure(pieces, *configuration, diagnostics, &excluded)) {
        pieces = std::move(*active);
        pairing(pieces, close);
      }
    collectModuleScopes(0, pieces.size(), modulePath);
    if (failed)
      return std::nullopt;
    std::map<std::vector<std::string>, SyntaxContextPtr> invocationContexts;
    for (auto &piece : pieces) {
      if (piece.context || (piece.kind != TokenKind::Word &&
                            piece.kind != TokenKind::QuotedWord))
        continue;
      auto scope = scopeAt(piece.origin.begin);
      auto [found, inserted] = invocationContexts.try_emplace(scope);
      if (inserted)
        found->second = std::make_shared<const SyntaxContext>(SyntaxContext{
            std::move(scope), {0, source.text.size(), source.id}, 0});
      piece.context = found->second;
    }
    for (std::size_t i = 0; i + 2 < pieces.size(); ++i)
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
          pieces[i + 1].kind == TokenKind::Word && symbol(pieces[i + 2], "{")) {
        auto begin = i;
        auto prefix = begin;
        if (prefix > 0 && symbol(pieces[prefix - 1], ")")) {
          std::size_t depth = 1;
          auto open = prefix - 1;
          while (open > 0 && depth != 0) {
            --open;
            if (symbol(pieces[open], ")"))
              ++depth;
            else if (symbol(pieces[open], "("))
              --depth;
          }
          if (depth == 0)
            prefix = open;
        }
        if (prefix > 0 && pieces[prefix - 1].kind == TokenKind::Word &&
            pieces[prefix - 1].text == "pub")
          begin = prefix - 1;
        auto attribute = begin;
        while (attribute > 0) {
          while (attribute > 0 && newline(pieces[attribute - 1]))
            --attribute;
          if (attribute > 0 && symbol(pieces[attribute - 1], ")")) {
            std::size_t depth = 1;
            --attribute;
            while (attribute > 0 && depth) {
              --attribute;
              if (symbol(pieces[attribute], ")"))
                ++depth;
              else if (symbol(pieces[attribute], "("))
                --depth;
            }
          }
          if (attribute < 2 || !symbol(pieces[attribute - 2], "@") ||
              pieces[attribute - 1].kind != TokenKind::Word)
            break;
          begin = attribute -= 2;
        }
        definitions.push_back({begin, i, close[i + 2]});
        i = close[i + 2];
      }
    for (const auto &definition : definitions)
      define(definition.begin, definition.macro, definition.end);
    collectImports(0, pieces.size(), modulePath);
    ready = !failed;
    if (definitionsOnly)
      return std::nullopt;
    if (definitions.empty() && excluded.empty()) {
      bool invocation = false;
      for (std::size_t i = 0; i < pieces.size(); ++i)
        invocation |= invocationAt(pieces, i);
      if (!invocation)
        return std::nullopt;
    }
    return expandSource();
  }

  std::optional<MacroLibrary>
  exportLibrary(const MacroSourceIdentity &identify) {
    if (!ready || failed) {
      error({}, "cannot export an invalid macro source");
      return std::nullopt;
    }
    return LibraryExporter(diagnostics, identify)
        .run(*macros, *pendingImports, *indexedModules, *declaredModules);
  }

private:
  struct Definition {
    std::size_t begin, macro, end;
  };

  struct ScopeRange {
    std::size_t begin, end;
    std::vector<std::string> path;
  };

  const Source &source;
  Diagnostics &diagnostics;
  const SourceAllocator &allocate;
  const Procedures *procedures;
  std::vector<std::string> modulePath;
  const MacroModuleProvider &modules;
  const MacroModuleProvider &importModules;
  const Configuration *configuration;
  std::vector<Span> excluded;
  std::size_t nextExcluded = 0;
  Pieces pieces;
  std::vector<std::size_t> close;
  std::vector<Definition> definitions;
  std::vector<ScopeRange> moduleScopes;
  std::shared_ptr<MacroIndex> macros;
  std::shared_ptr<ImportedMacroIndex> importedMacros;
  std::shared_ptr<IndexedModules> indexedModules;
  std::shared_ptr<PendingMacroImports> pendingImports;
  std::vector<Module::MacroDeclaration> *declarations;
  std::shared_ptr<std::set<std::vector<std::string>>> declaredModules;
  std::shared_ptr<MacroDiscovery> discovery;
  std::shared_ptr<ImportedModules> compiledModules;
  std::shared_ptr<std::set<std::vector<std::string>>> inlineModules;
  std::set<std::string> broken;
  std::vector<std::string> chain;
  bool failed = false;
  bool ready = false;
  std::string text;
  std::vector<Generation::Mapping> mappings;

  void error(Span span, std::string message) {
    failed = true;
    diagnostics.error("macro", span, std::move(message));
  }

  std::size_t moduleBody(std::size_t position, std::size_t end) const {
    if (pieces[position].kind != TokenKind::Word ||
        pieces[position].text != "module" || position + 1 >= end ||
        (pieces[position + 1].kind != TokenKind::Word &&
         pieces[position + 1].kind != TokenKind::QuotedWord))
      return none;
    auto open = position + 2;
    while (open < end && newline(pieces[open]))
      ++open;
    return open < end && symbol(pieces[open], "{") && close[open] != none
               ? open
               : none;
  }

  static std::string moduleName(const Piece &piece) {
    return piece.kind == TokenKind::QuotedWord
               ? piece.text.substr(1, piece.text.size() - 2)
               : piece.text;
  }

  void collectModuleScopes(std::size_t begin, std::size_t end,
                           const std::vector<std::string> &path,
                           unsigned depth = 0) {
    for (auto i = begin; i < end;) {
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
          i + 2 < end && pieces[i + 1].kind == TokenKind::Word &&
          symbol(pieces[i + 2], "{") && close[i + 2] != none) {
        i = close[i + 2] + 1;
        continue;
      }
      if (auto open = moduleBody(i, end); open != none) {
        if (depth >= limits::parserNesting) {
          failed = true;
          diagnostics.error("limit", pieces[i].origin,
                            "module nesting limit exceeded");
          return;
        }
        auto nested = path;
        nested.push_back(moduleName(pieces[i + 1]));
        inlineModules->insert(nested);
        auto last = close[open];
        moduleScopes.push_back(
            {pieces[open].origin.end, pieces[last].origin.begin, nested});
        collectModuleScopes(open + 1, last, nested, depth + 1);
        if (failed)
          return;
        i = last + 1;
        continue;
      }
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "module" &&
          i + 1 < end &&
          (pieces[i + 1].kind == TokenKind::Word ||
           pieces[i + 1].kind == TokenKind::QuotedWord)) {
        auto external = path;
        external.push_back(moduleName(pieces[i + 1]));
        declaredModules->insert(std::move(external));
        i += 2;
        continue;
      }
      if (opener(pieces[i]) && close[i] != none) {
        i = close[i] + 1;
        continue;
      }
      ++i;
    }
  }

  std::vector<std::string> scopeAt(std::size_t offset) const {
    const ScopeRange *selected = nullptr;
    for (const auto &range : moduleScopes)
      if (range.begin <= offset && offset < range.end &&
          (!selected || range.path.size() > selected->path.size()))
        selected = &range;
    return selected ? selected->path : modulePath;
  }

  static std::string macroKey(const std::vector<std::string> &scope,
                              std::string_view name) {
    std::string result;
    for (const auto &part : scope) {
      if (!result.empty())
        result += "::";
      result += part;
    }
    if (!result.empty())
      result += "::";
    result += name;
    return result;
  }

  bool startsWith(const std::vector<std::string> &path,
                  const std::vector<std::string> &prefix) const {
    return path.size() >= prefix.size() &&
           std::equal(prefix.begin(), prefix.end(), path.begin());
  }

  bool visibilityBoundary(const std::vector<std::string> &scope,
                          const VisibilitySyntax &visibility,
                          std::vector<std::string> &boundary) {
    boundary = scope;
    if (!visibility.publicItem || visibility.restriction.empty())
      return true;
    auto package = scope;
    if (!package.empty() && package.front().starts_with("mettle_pkg_"))
      package.resize(1);
    else
      package.clear();
    boundary = scope;
    std::size_t position = 0;
    if (visibility.restriction.front() == "package") {
      boundary = package;
      ++position;
    } else if (visibility.restriction.front() == "self") {
      ++position;
    } else if (visibility.restriction.front() != "super") {
      boundary = package;
    }
    while (position < visibility.restriction.size()) {
      const auto &part = visibility.restriction[position++];
      if (part == "super") {
        if (boundary == package)
          return false;
        boundary.pop_back();
      } else {
        boundary.push_back(part);
      }
    }
    return !visibility.restriction.empty() && startsWith(scope, boundary);
  }

  void define(std::size_t begin, std::size_t at, std::size_t last) {
    const auto &name = pieces[at + 1];
    auto before = diagnostics.count();
    if (isReservedWord(name.text)) {
      error(name.origin, "'" + name.text + "' cannot name a macro");
      return;
    }
    auto definitionScope = scopeAt(pieces[at].origin.begin);
    auto key = macroKey(definitionScope, name.text);
    if (macros->contains(key)) {
      error(name.origin, "macro '" + name.text + "' is already defined");
      return;
    }
    Macro macro;
    macro.name = name.text;
    macro.span = {pieces[at].origin.begin, pieces[last].origin.end, source.id};
    macro.definitionScope = std::move(definitionScope);
    macro.visibilityBoundary = macro.definitionScope;
    Module::MacroDeclaration declaration;
    declaration.name = name.text;
    declaration.span = macro.span;
    declaration.item.scope = macro.definitionScope;
    if (startsWith(declaration.item.scope, modulePath))
      declaration.item.scope.erase(
          declaration.item.scope.begin(),
          declaration.item.scope.begin() +
              static_cast<std::ptrdiff_t>(modulePath.size()));
    if (begin < at && pieces[begin].text == "pub") {
      declaration.item.visibility.publicItem = true;
      declaration.item.visibility.span = pieces[begin].origin;
      if (begin + 1 == at) {
        macro.publicItem = true;
      } else {
        auto position = begin + 2;
        auto end = at - 1;
        bool valid = symbol(pieces[begin + 1], "(") &&
                     symbol(pieces[end], ")") && position < end;
        if (symbol(pieces[end], ")"))
          declaration.item.visibility.span.end = pieces[end].origin.end;
        bool separator = false;
        while (valid && position < end) {
          if (separator) {
            if (!symbol(pieces[position], ".")) {
              valid = false;
              break;
            }
            ++position;
          }
          if (position == end || pieces[position].kind != TokenKind::Word) {
            valid = false;
            break;
          }
          declaration.item.visibility.restriction.push_back(
              pieces[position].text);
          ++position;
          separator = true;
        }
        std::vector<std::string> boundary;
        if (!valid ||
            !visibilityBoundary(macro.definitionScope,
                                declaration.item.visibility, boundary)) {
          failed = true;
          diagnostics.error("name", pieces[begin].origin,
                            "restricted visibility must name an enclosing "
                            "module");
        } else {
          macro.visibilityBoundary = std::move(boundary);
        }
      }
    }
    if (declarations)
      declarations->push_back(declaration);
    auto i = at + 3;
    auto expect = [&](bool condition, const Piece &where, const char *message) {
      if (!condition)
        error(where.origin, message);
      return condition;
    };
    while (i < last) {
      while (i < last && (newline(pieces[i]) || symbol(pieces[i], ";")))
        ++i;
      if (i >= last)
        break;
      if (!expect(opener(pieces[i]), pieces[i],
                  "expected a '(matcher) => { expansion }' rule"))
        break;
      auto matcherEnd = close[i];
      Rule rule;
      auto ok = parseNodes(pieces, close, i + 1, matcherEnd, true, diagnostics,
                           rule.matcher);
      i = matcherEnd + 1;
      while (i < last && newline(pieces[i]))
        ++i;
      if (!expect(i < last && symbol(pieces[i], "=>"),
                  pieces[std::min(i, last)], "expected '=>' after the matcher"))
        break;
      ++i;
      while (i < last && newline(pieces[i]))
        ++i;
      if (!expect(i < last && opener(pieces[i]), pieces[std::min(i, last)],
                  "expected a delimited expansion after '=>'"))
        break;
      auto templateEnd = close[i];
      ok &= parseNodes(pieces, close, i + 1, templateEnd, false, diagnostics,
                       rule.expansion);
      i = templateEnd + 1;
      trimNewlines(rule.expansion);
      std::map<std::string, unsigned> bound;
      variables(rule.matcher, 0, bound);
      verify(macro.name, rule.expansion, 0, bound, diagnostics, ok);
      checkFollow(rule.matcher, {{"", false}}, diagnostics, ok);
      if (!ok)
        failed = true;
      macro.rules.push_back(std::move(rule));
    }
    if (macro.rules.empty() && diagnostics.count() == before)
      error(name.origin, "macro '" + macro.name + "' has no rules");
    if (diagnostics.count() != before) {
      failed = true;
      broken.insert(key);
    }
    macros->emplace(std::move(key), std::move(macro));
  }

  struct Invocation {
    const Macro *macro = nullptr;
    std::vector<std::string> visibilityBoundary;
    bool publicItem = false;
    bool privateAccess = false;
    bool ambiguous = false;
  };

  std::optional<MacroBinding>
  bindingInIndex(const std::vector<std::string> &path, std::string_view name) {
    auto key = macroKey(path, name);
    std::vector<MacroBinding> matches;
    if (auto found = macros->find(key); found != macros->end())
      matches.push_back({&found->second, found->second.visibilityBoundary,
                         found->second.publicItem});
    if (auto found = importedMacros->find(key); found != importedMacros->end())
      matches.insert(matches.end(), found->second.begin(), found->second.end());
    if (matches.empty())
      return std::nullopt;
    auto binding = matches.front();
    binding.ambiguous |= matches.size() > 1;
    return binding;
  }

  std::optional<MacroBinding>
  bindingAtPath(std::vector<std::string> &path, std::string_view name,
                const std::vector<std::string> &from, bool imported = false) {
    // Like item imports, paths are relative to the current module and
    // `super` climbs from it.
    if (!path.empty() && path.front() == "super") {
      auto scope = from;
      auto first = path.begin();
      for (; first != path.end() && *first == "super"; ++first) {
        if (scope.empty())
          return std::nullopt;
        scope.pop_back();
      }
      scope.insert(scope.end(), first, path.end());
      path = std::move(scope);
    } else if (!from.empty()) {
      auto local = from;
      local.insert(local.end(), path.begin(), path.end());
      resolveMacroImports(local, name);
      if (auto binding = bindingInIndex(local, name)) {
        path = std::move(local);
        return binding;
      }
    }
    resolveMacroImports(path, name);
    if (auto binding = bindingInIndex(path, name))
      return binding;
    if (!modules && !importModules)
      return std::nullopt;
    auto loaded = modulesForPath(path, from, imported);
    if (!loaded)
      return std::nullopt;
    path = std::move(*loaded);
    resolveMacroImports(path, name);
    return bindingInIndex(path, name);
  }

  std::vector<std::string> importBoundary(const std::vector<std::string> &scope,
                                          const VisibilitySyntax &visibility,
                                          bool &valid) {
    std::vector<std::string> boundary;
    valid = visibilityBoundary(scope, visibility, boundary);
    return boundary;
  }

  MacroBinding reexportedBinding(const MacroBinding &target,
                                 const std::vector<std::string> &scope,
                                 const VisibilitySyntax &visibility) {
    bool valid = true;
    auto visible = importBoundary(scope, visibility, valid);
    bool unrestricted = visibility.publicItem && visibility.restriction.empty();
    if (target.publicItem && unrestricted)
      return {target.macro, {}, true, target.ambiguous};
    if (target.publicItem)
      return {target.macro, std::move(visible), false,
              target.ambiguous || !valid};
    if (unrestricted)
      return target;
    if (startsWith(visible, target.visibilityBoundary))
      return {target.macro, std::move(visible), false,
              target.ambiguous || !valid};
    if (startsWith(target.visibilityBoundary, visible))
      return {target.macro, target.visibilityBoundary, false,
              target.ambiguous || !valid};
    return {target.macro, {"__inaccessible_macro_import__"}, false, true};
  }

  void addMacroImport(const std::vector<std::string> &scope, std::string alias,
                      std::vector<std::string> path, std::string name,
                      const VisibilitySyntax &visibility) {
    pendingImports->push_back({scope, std::move(path), std::move(alias),
                               std::move(name), visibility});
  }

  void resolveMacroImports(const std::vector<std::string> &scope,
                           std::string_view name) {
    discovery->requested.insert(macroKey(scope, name));
    if (discovery->resolving)
      return;
    discovery->resolving = true;
    struct Restore {
      bool &resolving;
      ~Restore() { resolving = false; }
    } restore{discovery->resolving};
    bool changed;
    do {
      changed = false;
      auto requested = discovery->requested.size();
      auto indexed = indexedModules->size();
      for (std::size_t i = 0; i < pendingImports->size(); ++i) {
        if ((*pendingImports)[i].resolved ||
            !discovery->requested.contains(macroKey(
                (*pendingImports)[i].scope, (*pendingImports)[i].alias)))
          continue;
        auto pending = (*pendingImports)[i];
        auto path = pending.path;
        auto target = bindingAtPath(path, pending.name, pending.scope, true);
        if (!target || (*pendingImports)[i].resolved)
          continue;
        auto key = macroKey(pending.scope, pending.alias);
        (*importedMacros)[key].push_back(
            reexportedBinding(*target, pending.scope, pending.visibility));
        (*pendingImports)[i].resolved = true;
        changed = true;
      }
      changed |= discovery->requested.size() != requested ||
                 indexedModules->size() != indexed;
    } while (changed);
  }

  static std::vector<std::string> tokenPath(const Pieces &in, std::size_t begin,
                                            std::size_t end, bool &valid) {
    std::vector<std::string> result;
    valid = begin < end && in[begin].kind == TokenKind::Word;
    if (!valid)
      return result;
    result.push_back(in[begin++].text);
    while (begin < end) {
      if (!symbol(in[begin], ".") || begin + 1 == end ||
          in[begin + 1].kind != TokenKind::Word) {
        valid = false;
        return {};
      }
      result.push_back(in[begin + 1].text);
      begin += 2;
    }
    return result;
  }

  void importDeclaration(std::size_t at, const std::vector<std::string> &scope,
                         std::size_t &after) {
    VisibilitySyntax visibility;
    visibility.span = pieces[at].origin;
    auto import = at;
    if (pieces[at].kind == TokenKind::Word && pieces[at].text == "pub") {
      visibility.publicItem = true;
      visibility.span = pieces[at].origin;
      ++import;
      if (import < pieces.size() && symbol(pieces[import], "(") &&
          close[import] != none) {
        bool valid = false;
        auto restriction = tokenPath(pieces, import + 1, close[import], valid);
        if (valid)
          visibility.restriction = std::move(restriction);
        else
          visibility.restriction.push_back("__invalid_visibility__");
        import = close[import] + 1;
      }
    }
    if (import >= pieces.size() || pieces[import].kind != TokenKind::Word ||
        pieces[import].text != "import")
      return;
    auto position = import + 1;
    bool pathValid = false;
    std::vector<std::string> path;
    if (position < pieces.size() && pieces[position].kind == TokenKind::Word) {
      path.push_back(pieces[position++].text);
      pathValid = true;
    }
    while (pathValid && position + 1 < pieces.size() &&
           symbol(pieces[position], ".")) {
      if (symbol(pieces[position + 1], "{") ||
          symbol(pieces[position + 1], "*"))
        break;
      if (pieces[position + 1].kind != TokenKind::Word) {
        pathValid = false;
        break;
      }
      path.push_back(pieces[position + 1].text);
      position += 2;
    }
    if (!pathValid)
      return;
    if (position + 1 < pieces.size() && symbol(pieces[position], ".") &&
        symbol(pieces[position + 1], "{") && close[position + 1] != none) {
      auto end = close[position + 1];
      auto item = position + 2;
      while (item < end) {
        if (newline(pieces[item]) || symbol(pieces[item], ",")) {
          ++item;
          continue;
        }
        if (pieces[item].kind != TokenKind::Word)
          break;
        auto name = pieces[item++].text;
        auto alias = name;
        if (item + 1 < end && pieces[item].kind == TokenKind::Word &&
            pieces[item].text == "as" &&
            pieces[item + 1].kind == TokenKind::Word) {
          alias = pieces[item + 1].text;
          item += 2;
        }
        addMacroImport(scope, std::move(alias), path, std::move(name),
                       visibility);
        while (item < end && !symbol(pieces[item], ","))
          ++item;
      }
      after = end + 1;
      return;
    }
    if (position + 1 < pieces.size() && symbol(pieces[position], ".") &&
        symbol(pieces[position + 1], "*")) {
      after = position + 2;
      return;
    }
    auto alias = path.back();
    if (position + 1 < pieces.size() &&
        pieces[position].kind == TokenKind::Word &&
        pieces[position].text == "as" &&
        pieces[position + 1].kind == TokenKind::Word) {
      alias = pieces[position + 1].text;
      position += 2;
    }
    if (path.size() > 1) {
      auto macro = path.back();
      path.pop_back();
      addMacroImport(scope, std::move(alias), path, std::move(macro),
                     visibility);
    }
    after = position;
  }

  void collectImports(std::size_t begin, std::size_t end,
                      const std::vector<std::string> &path) {
    for (auto i = begin; i < end;) {
      if (auto open = moduleBody(i, end); open != none) {
        auto nested = path;
        nested.push_back(moduleName(pieces[i + 1]));
        auto last = close[open];
        collectImports(open + 1, last, nested);
        i = last + 1;
        continue;
      }
      if (pieces[i].kind == TokenKind::Word &&
          (pieces[i].text == "import" || pieces[i].text == "pub")) {
        auto after = i;
        importDeclaration(i, scopeAt(pieces[i].origin.begin), after);
        if (after > i) {
          i = after;
          continue;
        }
      }
      if (opener(pieces[i]) && close[i] != none) {
        i = close[i] + 1;
        continue;
      }
      ++i;
    }
  }

  std::optional<MacroBinding>
  macroAtPath(std::vector<std::string> &path, std::string_view name,
              const std::vector<std::string> &from) {
    return bindingAtPath(path, name, from);
  }

  // First token of the `a.b.` qualifier written before the macro name at `i`.
  static std::size_t qualifierStart(const Pieces &in, std::size_t i) {
    auto first = i;
    while (first >= 2 && symbol(in[first - 1], ".") &&
           (in[first - 2].kind == TokenKind::Word ||
            in[first - 2].kind == TokenKind::QuotedWord))
      first -= 2;
    return first;
  }

  std::optional<MacroBinding>
  qualifiedMacro(const Pieces &in, std::size_t i,
                 std::vector<std::string> &path,
                 const std::vector<std::string> &from) {
    if (i < 2 || !symbol(in[i - 1], "."))
      return std::nullopt;
    auto first = i - 2;
    while (first >= 2 && symbol(in[first - 1], "."))
      first -= 2;
    if (in[first].kind != TokenKind::Word &&
        in[first].kind != TokenKind::QuotedWord)
      return std::nullopt;
    path.clear();
    for (auto part = first; part <= i - 2; part += 2) {
      if ((in[part].kind != TokenKind::Word &&
           in[part].kind != TokenKind::QuotedWord) ||
          (part != i - 2 && !symbol(in[part + 1], ".")))
        return std::nullopt;
      path.push_back(moduleName(in[part]));
    }
    return macroAtPath(path, in[i].text, from);
  }

  std::optional<std::vector<std::string>>
  modulesForPath(const std::vector<std::string> &path,
                 const std::vector<std::string> &from, bool imported) {
    auto relative = from;
    relative.insert(relative.end(), path.begin(), path.end());
    bool declared = std::any_of(
        declaredModules->begin(), declaredModules->end(),
        [&](const auto &module) {
          return startsWith(path, module) || startsWith(relative, module);
        });
    if (!declared && std::any_of(inlineModules->begin(), inlineModules->end(),
                                 [&](const auto &module) {
                                   return startsWith(path, module) ||
                                          (module.size() > from.size() &&
                                           startsWith(relative, module));
                                 }))
      return std::nullopt;
    bool native =
        !path.empty() && (path.front() == "core" || path.front() == "alloc" ||
                          path.front() == "std");
    imported =
        (imported || native) && !declared && static_cast<bool>(importModules);
    const auto &provider = imported ? importModules : modules;
    if (!provider)
      return std::nullopt;
    MacroDiscovery::Request request{path, from, imported};
    if (auto found = discovery->modules.find(request);
        found != discovery->modules.end())
      return found->second;
    auto module = provider(path, from);
    if (!module) {
      discovery->modules.emplace(std::move(request), std::nullopt);
      return std::nullopt;
    }
    discovery->modules.emplace(std::move(request), module->path);
    std::string key;
    for (const auto &part : module->sourcePath)
      key += (key.empty() ? "" : "::") + part;
    // An inline module of the source being expanded is already indexed.
    if (module->compiled) {
      if (std::find(module->compiled->indexedModules.begin(),
                    module->compiled->indexedModules.end(),
                    key) == module->compiled->indexedModules.end()) {
        error({}, "compiled macro library does not own the requested module");
        return std::nullopt;
      }
      if ((!indexedModules->contains(key) || compiledModules->contains(key)) &&
          !LibraryImporter(*module->compiled, diagnostics, module->remapSources)
               .run(*macros, *pendingImports, *indexedModules, *declaredModules,
                    *compiledModules)) {
        failed = true;
        return std::nullopt;
      }
      indexedModules->insert(std::move(key));
    } else if (module->source.id != source.id &&
               indexedModules->insert(key).second) {
      Expander indexer(
          module->source, diagnostics, allocate, nullptr, module->sourcePath,
          modules, macros, importedMacros, indexedModules, pendingImports,
          nullptr, importModules, declaredModules, discovery,
          module->configuration ? &*module->configuration : configuration,
          compiledModules, inlineModules);
      indexer.run(true);
    }
    return module->path;
  }

  static bool invocationAt(const Pieces &in, std::size_t i) {
    return in[i].kind == TokenKind::Word && i + 2 < in.size() &&
           symbol(in[i + 1], "!") && !in[i + 1].space && opener(in[i + 2]) &&
           !(i > 0 && symbol(in[i - 1], "::"));
  }

  Invocation invoked(const Pieces &in, std::size_t i) {
    if (!invocationAt(in, i))
      return {};
    auto caller =
        in[i].context ? in[i].context->scope : scopeAt(in[i].origin.begin);
    std::vector<std::string> path;
    std::optional<MacroBinding> binding;
    if (i > 0 && symbol(in[i - 1], "."))
      binding = qualifiedMacro(in, i, path, caller);
    else {
      auto scope = caller;
      for (;;) {
        resolveMacroImports(scope, in[i].text);
        binding = bindingInIndex(scope, in[i].text);
        if (binding)
          break;
        if (scope.empty())
          break;
        scope.pop_back();
      }
    }
    if (!binding)
      return {};
    auto privateAccess = !binding->publicItem &&
                         !startsWith(caller, binding->visibilityBoundary);
    return {binding->macro, binding->visibilityBoundary, binding->publicItem,
            privateAccess, binding->ambiguous};
  }

  void nameError(Span span, const Macro &macro) {
    failed = true;
    diagnostics.error("name", span,
                      "private macro '" + macro.name +
                          "' is not visible from this module");
  }

  void ambiguousMacroError(Span span, const Macro &macro) {
    failed = true;
    diagnostics.error("name", span,
                      "ambiguous macro import for '" + macro.name + "'");
  }

  bool procedure(const Pieces &in, std::size_t i) {
    if (!procedures || !invocationAt(in, i) ||
        (i > 0 && symbol(in[i - 1], ".")))
      return false;
    return procedures->names.contains(in[i].text) && !invoked(in, i).macro;
  }

  std::string path() const {
    std::string result;
    for (const auto &name : chain)
      result += (result.empty() ? "" : " -> ") + name + "!";
    return result;
  }

  bool expandPieces(const Pieces &in, Pieces &out, unsigned depth, Span use) {
    if (configuration) {
      if (auto active = configure(in, *configuration, diagnostics))
        return expandPieces(*active, out, depth, use);
    }
    std::vector<std::size_t> inner;
    if (!pairing(in, inner)) {
      error(use, "a macro expansion produced unbalanced delimiters");
      return false;
    }
    bool ok = true;
    for (std::size_t i = 0; i < in.size();) {
      auto invocation = invoked(in, i);
      const auto *macro = invocation.macro;
      auto host = !macro && procedure(in, i);
      if (!macro && !host) {
        out.push_back(in[i++]);
        continue;
      }
      auto last = inner[i + 2];
      if (macro) {
        // The qualifier was already copied token by token; it names the
        // macro, not a value the expansion is applied to.
        auto prefix = i - qualifierStart(in, i);
        out.resize(out.size() - std::min(prefix, out.size()));
      }
      if (invocation.privateAccess) {
        nameError(
            {in[i].origin.begin, in[last].origin.end, in[i].origin.source},
            *macro);
        i = last + 1;
        ok = false;
        continue;
      }
      if (invocation.ambiguous) {
        ambiguousMacroError(
            {in[i].origin.begin, in[last].origin.end, in[i].origin.source},
            *macro);
        i = last + 1;
        ok = false;
        continue;
      }
      if (host)
        ok &= invokeProcedure(in, i, last, out, depth, use);
      else if (!broken.contains(macroKey(macro->definitionScope, macro->name)))
        ok &= invoke(*macro, in, i, last, out, depth, use);
      i = last + 1;
      if (out.size() > limits::tokens) {
        error(use, "macro expansion limit exceeded");
        return false;
      }
    }
    return ok;
  }

  bool invoke(const Macro &macro, const Pieces &in, std::size_t at,
              std::size_t last, Pieces &out, unsigned depth, Span use) {
    if (depth >= recursionLimit) {
      error(use, "macro recursion limit of " + std::to_string(recursionLimit) +
                     " exceeded while expanding '" + macro.name +
                     "!'; expansion path: " + path());
      return false;
    }
    chain.push_back(macro.name);
    struct Pop {
      std::vector<std::string> &chain;
      ~Pop() { chain.pop_back(); }
    } pop{chain};
    Pieces arguments(in.begin() + at + 3, in.begin() + last);
    for (auto &piece : arguments)
      piece.authored = false;
    // Arguments are expanded first so nested invocations are ordinary
    // expressions when a fragment is parsed.
    Pieces expanded;
    if (!expandPieces(arguments, expanded, depth + 1, use))
      return false;
    std::vector<std::size_t> grouping;
    if (!pairing(expanded, grouping)) {
      error(use,
            "unbalanced delimiters in the arguments of '" + macro.name + "!'");
      return false;
    }
    for (const auto &rule : macro.rules) {
      Recognizer recognizer(expanded, grouping);
      if (!recognizer.run(rule.matcher))
        continue;
      Environment environment;
      for (const auto &entry : recognizer.scope)
        environment[entry.first] = &entry.second;
      Pieces produced;
      if (!instantiate(macro, rule.expansion, environment, produced, use,
                       in[at].context))
        return false;
      auto context =
          diagnostics.makeSyntaxContext(macro.definitionScope, macro.span);
      for (auto &piece : produced)
        if (piece.authored)
          piece.context = context;
      Pieces expanded;
      if (!expandPieces(produced, expanded, depth + 1, use))
        return false;
      if (parsesExpression(expanded)) {
        out.push_back({TokenKind::Symbol, "(", use, false});
        out.insert(out.end(), expanded.begin(), expanded.end());
        out.push_back({TokenKind::Symbol, ")", use, false});
      } else {
        out.insert(out.end(), expanded.begin(), expanded.end());
      }
      return true;
    }
    error(use, "no rule of macro '" + macro.name +
                   "' matches this invocation (" +
                   std::to_string(macro.rules.size()) + " rule(s) tried)");
    return false;
  }

  static const char *kindName(TokenKind kind) {
    switch (kind) {
    case TokenKind::Word:
      return "word";
    case TokenKind::Integer:
      return "integer";
    case TokenKind::Symbol:
      return "symbol";
    case TokenKind::Newline:
      return "newline";
    case TokenKind::Character:
      return "character";
    case TokenKind::Byte:
      return "byte";
    case TokenKind::Floating:
      return "floating";
    case TokenKind::QuotedWord:
      return "quoted-word";
    case TokenKind::Text:
      return "text";
    case TokenKind::PrefixedText:
      return "prefixed-text";
    case TokenKind::FormatOpen:
      return "format-open";
    case TokenKind::FormatPiece:
      return "format-piece";
    case TokenKind::FormatHoleOpen:
      return "format-hole-open";
    case TokenKind::FormatHoleClose:
      return "format-hole-close";
    case TokenKind::FormatClose:
      return "format-close";
    default:
      return "other";
    }
  }

  // Runs a host-program macro on the invocation `in[at..last]` and expands the
  // tokens it produced. Every produced token is attributed to the invocation.
  bool invokeProcedure(const Pieces &in, std::size_t at, std::size_t last,
                       Pieces &out, unsigned depth, Span use) {
    const auto &name = in[at].text;
    if (depth >= recursionLimit) {
      error(use, "macro recursion limit of " + std::to_string(recursionLimit) +
                     " exceeded while expanding '" + name +
                     "!'; expansion path: " + path());
      return false;
    }
    chain.push_back(name);
    struct Pop {
      std::vector<std::string> &chain;
      ~Pop() { chain.pop_back(); }
    } pop{chain};
    Pieces arguments(in.begin() + at + 3, in.begin() + last);
    for (auto &piece : arguments)
      piece.authored = false;
    Pieces expanded;
    if (!expandPieces(arguments, expanded, depth + 1, use))
      return false;
    std::vector<ProcedureToken> tokens;
    for (const auto &piece : expanded)
      tokens.push_back({kindName(piece.kind), piece.text, piece.space});
    auto response = procedures->run(name, encodeRequest(name, tokens));
    auto prefix = "procedural macro '" + name + "!'";
    if (!response.fault.empty()) {
      error(use, prefix + " failed: " + response.fault);
      return false;
    }
    if (!response.errors.empty()) {
      for (const auto &message : response.errors)
        error(use, prefix + ": " + message);
      return false;
    }
    Source produced{source.path, response.text, source.id};
    Diagnostics scratch;
    auto lexed = tokenize(produced, scratch);
    if (!scratch.empty()) {
      error(use, prefix + " produced text that does not lex");
      return false;
    }
    Pieces generated = lower(produced, lexed, diagnostics);
    for (auto &piece : generated) {
      piece.glued = !piece.space;
      piece.origin = use;
      piece.context = in[at].context;
    }
    if (!generated.empty())
      generated.front().glued = false;
    return expandPieces(generated, out, depth + 1, use);
  }

  bool instantiate(const Macro &macro, const std::vector<Node> &nodes,
                   const Environment &environment, Pieces &out, Span use,
                   const SyntaxContextPtr &invocationContext) {
    bool ok = true;
    for (const auto &node : nodes) {
      if (node.form == Form::Literal) {
        Piece piece = node.piece;
        piece.authored = true;
        out.push_back(std::move(piece));
      } else if (node.form == Form::Capture) {
        Piece piece = *node.separator;
        piece.space = node.piece.space;
        piece.context = invocationContext;
        out.push_back(std::move(piece));
      } else if (node.form == Form::Variable) {
        auto found = environment.find(node.name);
        if (found == environment.end())
          continue;
        const auto &binding = *found->second;
        if (binding.list) {
          error(use, "metavariable '$" + node.name + "' of macro '" +
                         macro.name +
                         "' repeats and must be used inside $(...)");
          ok = false;
          continue;
        }
        auto grouped = binding.fragment == "expr" && binding.tokens.size() > 1;
        if (grouped) {
          Piece open{TokenKind::Symbol, "(", binding.tokens.front().origin,
                     node.piece.space};
          out.push_back(std::move(open));
        }
        for (std::size_t i = 0; i < binding.tokens.size(); ++i) {
          Piece piece = binding.tokens[i];
          piece.authored = false;
          if (i == 0)
            piece.space = !grouped && node.piece.space;
          out.push_back(std::move(piece));
        }
        if (grouped)
          out.push_back(
              {TokenKind::Symbol, ")", binding.tokens.back().origin, false});
      } else {
        ok &= repeat(macro, node, environment, out, use, invocationContext);
      }
    }
    return ok;
  }

  bool repeat(const Macro &macro, const Node &node,
              const Environment &environment, Pieces &out, Span use,
              const SyntaxContextPtr &invocationContext) {
    std::set<std::string> used;
    names(node.body, used);
    std::vector<std::string> repeating;
    std::size_t count = none;
    for (const auto &name : used) {
      auto found = environment.find(name);
      if (found == environment.end() || !found->second->list)
        continue;
      repeating.push_back(name);
      auto size = found->second->items.size();
      if (count == none)
        count = size;
      else if (count != size) {
        error(use, "macro '" + macro.name + "': metavariables '$" +
                       repeating.front() + "' and '$" + name +
                       "' repeat a different number of times (" +
                       std::to_string(count) + " and " + std::to_string(size) +
                       ")");
        return false;
      }
    }
    if (repeating.empty()) {
      error(node.piece.origin, "a repetition in an expansion of macro '" +
                                   macro.name +
                                   "' contains no repeating metavariable");
      return false;
    }
    if (node.op == '?' && count > 1) {
      error(use, "optional macro repetition has more than one element");
      return false;
    }
    if (node.op == '+' && count == 0) {
      error(use, "nonempty macro repetition has no elements");
      return false;
    }
    bool ok = true;
    for (std::size_t k = 0; k < count; ++k) {
      Environment inner = environment;
      for (const auto &name : repeating)
        inner[name] = &environment.at(name)->items[k];
      if (k > 0 && node.separator) {
        Piece separator = *node.separator;
        separator.authored = true;
        out.push_back(std::move(separator));
      }
      ok &= instantiate(macro, node.body, inner, out, use, invocationContext);
    }
    return ok;
  }

  void copy(std::size_t to) {
    auto append = [&](std::size_t end) {
      if (end <= cursor)
        return;
      auto begin = text.size();
      text.append(source.text, cursor, end - cursor);
      Generation::Mapping mapping;
      mapping.begin = begin;
      mapping.end = text.size();
      mapping.target = {cursor, end, source.id};
      mapping.exact = true;
      mappings.push_back(std::move(mapping));
      cursor = end;
    };
    while (nextExcluded < excluded.size() &&
           excluded[nextExcluded].begin < to) {
      append(excluded[nextExcluded].begin);
      cursor = std::max(cursor, excluded[nextExcluded].end);
      ++nextExcluded;
    }
    append(to);
    cursor = to;
  }

  void emit(const Pieces &result, Span use, const std::string &name) {
    const Piece *previous = nullptr;
    for (const auto &piece : result) {
      if (separated(previous, piece))
        text += ' ';
      auto begin = text.size();
      text += piece.text;
      previous = &piece;
      if (newline(piece))
        continue;
      Generation::Mapping mapping;
      mapping.begin = begin;
      mapping.end = text.size();
      mapping.target = piece.origin;
      mapping.origin = use;
      mapping.description = "macro '" + name + "!'";
      mapping.syntaxContext = piece.context;
      mappings.push_back(std::move(mapping));
    }
  }

  std::size_t cursor = 0;

  std::optional<Source> expandSource() {
    bool changed = !definitions.empty() || !excluded.empty();
    std::size_t next = 0;
    for (std::size_t i = 0; i < pieces.size();) {
      if (next < definitions.size() && i == definitions[next].begin) {
        copy(pieces[definitions[next].begin].origin.begin);
        cursor = pieces[definitions[next].end].origin.end;
        i = definitions[next].end + 1;
        ++next;
        continue;
      }
      auto invocation = invoked(pieces, i);
      const auto *macro = invocation.macro;
      auto host = !macro && procedure(pieces, i);
      if (!macro && !host) {
        ++i;
        continue;
      }
      changed = true;
      auto name = host ? pieces[i].text : macro->name;
      auto first = macro ? qualifierStart(pieces, i) : i, last = close[i + 2];
      Span use{pieces[first].origin.begin, pieces[last].origin.end, source.id};
      copy(use.begin);
      cursor = use.end;
      i = last + 1;
      if (invocation.privateAccess) {
        nameError(use, *macro);
        continue;
      }
      if (invocation.ambiguous) {
        ambiguousMacroError(use, *macro);
        continue;
      }
      if (macro &&
          broken.contains(macroKey(macro->definitionScope, macro->name)))
        continue;
      chain.clear();
      Pieces call(pieces.begin() + first, pieces.begin() + last + 1), result;
      if (expandPieces(call, result, 0, use))
        emit(result, use, name);
    }
    if (failed || !changed)
      return std::nullopt;
    copy(source.text.size());
    Source generated{source.path, std::move(text), allocate()};
    diagnostics.generated({generated.id,
                           {0, 0, source.id},
                           "macro expansion",
                           std::move(mappings)});
    return generated;
  }
};
} // namespace

bool mergeMacros(MacroLibrary &target, const MacroLibrary &source,
                 Diagnostics &diagnostics, const MacroSourceRemap &remap,
                 const MacroSourceIdentity &identify) {
  MacroIndex macros;
  PendingMacroImports imports;
  IndexedModules indexed;
  std::set<std::vector<std::string>> declared;
  ImportedModules imported;
  if (!LibraryImporter(target, diagnostics, remap)
           .run(macros, imports, indexed, declared, imported) ||
      !LibraryImporter(source, diagnostics, remap)
           .run(macros, imports, indexed, declared, imported))
    return false;
  auto merged = LibraryExporter(diagnostics, identify)
                    .run(macros, imports, indexed, declared);
  if (!merged)
    return false;
  target = std::move(*merged);
  return true;
}

std::optional<Source>
expandMacros(const Source &source, Diagnostics &diagnostics,
             const SourceAllocator &allocate, const Procedures *procedural,
             std::vector<std::string> modulePath,
             const MacroModuleProvider &modules,
             std::vector<Module::MacroDeclaration> *declarations,
             const MacroModuleProvider &importModules,
             const Configuration *configuration, MacroLibrary *exports,
             const MacroSourceIdentity &identify) {
  Expander expander(source, diagnostics, allocate, procedural,
                    std::move(modulePath), modules, {}, {}, {}, {},
                    declarations, importModules, {}, {}, configuration);
  auto result = expander.run();
  if (exports && diagnostics.empty()) {
    auto library = expander.exportLibrary(identify);
    if (library)
      *exports = std::move(*library);
  }
  if (!diagnostics.empty())
    return std::nullopt;
  return result;
}
} // namespace mettle::expansion
