#include "expansion/macros.h"
#include "support/limits.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "syntax/token.h"
#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <string_view>
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

Pieces lower(const Source &source, const std::vector<Token> &tokens) {
  Pieces result;
  bool space = false;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::End)
      break;
    if (token.kind == TokenKind::Space || token.kind == TokenKind::Comment) {
      space = true;
      continue;
    }
    Piece piece;
    piece.kind = token.kind;
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
      if (node.separator)
        inner.push_back({node.separator->text, false});
      else {
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
struct Macro {
  std::string name;
  Span span;
  std::vector<std::string> definitionScope;
  std::vector<Rule> rules;
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
    text = "fn __fragment() { let __value = " + text + "\n}";
  } else if (fragment == "stmt") {
    text = "fn __fragment() { " + text + "\n}";
  } else if (fragment == "pat") {
    text = "fn __fragment() { match 0 { " + text + " => 0 } }";
  } else if (fragment == "ty" || fragment == "path") {
    text = "fn __fragment(__value: " + text + ") { }";
  }
}

// Fragments that are not a single token invoke the native parser on the
// tokens they captured, inside a context that accepts that fragment kind.
bool parses(const std::string &fragment, const Pieces &tokens) {
  auto kind = fragmentKind(fragment);
  if (kind == "ident" || kind == "literal" || kind == "tt")
    return true;
  auto text = render(tokens);
  wrap(kind, text);
  Source probe{"<macro fragment>", std::move(text), 0};
  Diagnostics scratch;
  parseDeclarations(probe, scratch);
  return scratch.empty();
}

bool parsesExpression(const Pieces &tokens) {
  auto text = "fn __fragment() { let __value = (" + render(tokens) + ")\n}";
  Source probe{"<macro expression>", std::move(text), 0};
  Diagnostics scratch;
  parseDeclarations(probe, scratch);
  return scratch.empty();
}

class Recognizer {
public:
  Recognizer(const Pieces &input, const std::vector<std::size_t> &close)
      : in(input), close(close) {}

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

  static bool stops(const std::string &fragment, const Piece &piece) {
    if (fragment == "stmt" && newline(piece))
      return true;
    if (piece.kind != TokenKind::Symbol && piece.kind != TokenKind::Word)
      return false;
    const auto &text = piece.text;
    if (text == "=>" || text == ",")
      return piece.kind == TokenKind::Symbol;
    if (fragment == "expr" || fragment == "stmt")
      return text == ";" && piece.kind == TokenKind::Symbol;
    if (fragment == "pat")
      return text == "=" || text == "if" || text == "in";
    return text == "=" || text == ";" || text == ":" || text == ">" ||
           text == ">>" || text == "{" || text == "[" || text == "where";
  }

  std::size_t itemExtent(std::size_t position, std::size_t end) const {
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
    while (j < end && !closer(in[j])) {
      if (symbol(in[j], "{"))
        return close[j] + 1;
      if (opener(in[j])) {
        j = close[j] + 1;
        continue;
      }
      if (newline(in[j]) || symbol(in[j], ";"))
        break;
      ++j;
    }
    return j > start ? j : none;
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
    bool typed = fragment == "ty" || fragment == "path";
    unsigned angle = 0;
    auto j = position;
    while (j < end && !closer(in[j])) {
      const auto &piece = in[j];
      if (opener(piece) || piece.kind == TokenKind::FormatOpen) {
        j = after(j);
        continue;
      }
      if (typed && symbol(piece, "<")) {
        ++angle;
      } else if (typed && angle && symbol(piece, ">")) {
        --angle;
      } else if (typed && angle > 1 && symbol(piece, ">>")) {
        angle -= 2;
      } else if (angle == 0 && stops(fragment, piece)) {
        break;
      }
      ++j;
    }
    return j > position ? j : none;
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
  Expander(const Source &source, Diagnostics &diagnostics,
           const SourceAllocator &allocate, const Procedures *procedures,
           std::vector<std::string> modulePath)
      : source(source), diagnostics(diagnostics), allocate(allocate),
        procedures(procedures), modulePath(std::move(modulePath)) {}

  std::optional<Source> run() {
    Diagnostics scratch;
    auto tokens = tokenize(source, scratch);
    if (!scratch.empty())
      return std::nullopt;
    pieces = lower(source, tokens);
    if (!pairing(pieces, close))
      return std::nullopt;
    collectModuleScopes(0, pieces.size(), modulePath);
    for (std::size_t i = 0; i + 2 < pieces.size(); ++i)
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
          pieces[i + 1].kind == TokenKind::Word && symbol(pieces[i + 2], "{")) {
        definitions.push_back({i, close[i + 2]});
        i = close[i + 2];
      }
    bool procedural = false;
    for (std::size_t i = 0; i < pieces.size() && !procedural; ++i)
      procedural = procedure(pieces, i);
    if (definitions.empty() && !procedural)
      return std::nullopt;
    Diagnostics::SourceContext context(diagnostics, source);
    for (const auto &definition : definitions)
      define(definition.first, definition.second);
    return expandSource();
  }

private:
  struct ScopeRange {
    std::size_t begin, end;
    std::vector<std::string> path;
  };

  const Source &source;
  Diagnostics &diagnostics;
  const SourceAllocator &allocate;
  const Procedures *procedures;
  std::vector<std::string> modulePath;
  Pieces pieces;
  std::vector<std::size_t> close;
  std::vector<std::pair<std::size_t, std::size_t>> definitions;
  std::vector<ScopeRange> moduleScopes;
  std::map<std::string, Macro> macros;
  std::set<std::string> broken;
  std::vector<std::string> chain;
  std::size_t marks = 0;
  bool failed = false;
  std::string text;
  std::vector<Generation::Mapping> mappings;

  void error(Span span, std::string message) {
    failed = true;
    diagnostics.error("macro", span, std::move(message));
  }

  void collectModuleScopes(std::size_t begin, std::size_t end,
                           const std::vector<std::string> &path) {
    for (auto i = begin; i < end;) {
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
          i + 2 < end && pieces[i + 1].kind == TokenKind::Word &&
          symbol(pieces[i + 2], "{") && close[i + 2] != none) {
        i = close[i + 2] + 1;
        continue;
      }
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "module" &&
          i + 2 < end && pieces[i + 1].kind == TokenKind::Word &&
          symbol(pieces[i + 2], "{") && close[i + 2] != none) {
        auto nested = path;
        nested.push_back(pieces[i + 1].text);
        auto last = close[i + 2];
        moduleScopes.push_back(
            {pieces[i + 2].origin.end, pieces[last].origin.begin, nested});
        collectModuleScopes(i + 3, last, nested);
        i = last + 1;
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
    return selected ? selected->path : std::vector<std::string>{};
  }

  void define(std::size_t at, std::size_t last) {
    const auto &name = pieces[at + 1];
    auto before = diagnostics.count();
    if (isReservedWord(name.text)) {
      error(name.origin, "'" + name.text + "' cannot name a macro");
      return;
    }
    if (macros.contains(name.text)) {
      error(name.origin, "macro '" + name.text + "' is already defined");
      return;
    }
    Macro macro;
    macro.name = name.text;
    macro.span = {pieces[at].origin.begin, pieces[last].origin.end, source.id};
    macro.definitionScope = scopeAt(pieces[at].origin.begin);
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
      broken.insert(macro.name);
    }
    macros.emplace(macro.name, std::move(macro));
  }

  const Macro *invoked(const Pieces &in, std::size_t i) const {
    if (in[i].kind != TokenKind::Word || i + 2 >= in.size() ||
        !symbol(in[i + 1], "!") || in[i + 1].space || !opener(in[i + 2]))
      return nullptr;
    if (i > 0 && (symbol(in[i - 1], ".") || symbol(in[i - 1], "::")))
      return nullptr;
    auto found = macros.find(in[i].text);
    return found == macros.end() ? nullptr : &found->second;
  }

  // Whether `in[i]` starts an invocation of a procedural macro that no
  // file-local macro shadows.
  bool procedure(const Pieces &in, std::size_t i) const {
    if (!procedures || in[i].kind != TokenKind::Word || i + 2 >= in.size() ||
        !symbol(in[i + 1], "!") || in[i + 1].space || !opener(in[i + 2]))
      return false;
    if (i > 0 && (symbol(in[i - 1], ".") || symbol(in[i - 1], "::")))
      return false;
    return procedures->names.contains(in[i].text) &&
           !macros.contains(in[i].text);
  }

  std::string path() const {
    std::string result;
    for (const auto &name : chain)
      result += (result.empty() ? "" : " -> ") + name + "!";
    return result;
  }

  bool expandPieces(const Pieces &in, Pieces &out, unsigned depth, Span use) {
    std::vector<std::size_t> inner;
    if (!pairing(in, inner)) {
      error(use, "a macro expansion produced unbalanced delimiters");
      return false;
    }
    bool ok = true;
    for (std::size_t i = 0; i < in.size();) {
      const auto *macro = invoked(in, i);
      auto host = !macro && procedure(in, i);
      if (!macro && !host) {
        out.push_back(in[i++]);
        continue;
      }
      auto last = inner[i + 2];
      if (host)
        ok &= invokeProcedure(in, i, last, out, depth, use);
      else if (!broken.contains(macro->name))
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
      if (!instantiate(macro, rule.expansion, environment, produced, use))
        return false;
      hygiene(produced, ++marks, macro.definitionScope, scopeAt(use.begin));
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
    Pieces generated = lower(produced, lexed);
    for (auto &piece : generated) {
      piece.glued = !piece.space;
      piece.origin = use;
    }
    if (!generated.empty())
      generated.front().glued = false;
    return expandPieces(generated, out, depth + 1, use);
  }

  bool instantiate(const Macro &macro, const std::vector<Node> &nodes,
                   const Environment &environment, Pieces &out, Span use) {
    bool ok = true;
    for (const auto &node : nodes) {
      if (node.form == Form::Literal) {
        Piece piece = node.piece;
        piece.authored = true;
        out.push_back(std::move(piece));
      } else if (node.form == Form::Capture) {
        Piece piece = *node.separator;
        piece.space = node.piece.space;
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
        ok &= repeat(macro, node, environment, out, use);
      }
    }
    return ok;
  }

  bool repeat(const Macro &macro, const Node &node,
              const Environment &environment, Pieces &out, Span use) {
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
      ok &= instantiate(macro, node.body, inner, out, use);
    }
    return ok;
  }

  static bool bindable(const Piece &piece) {
    return piece.authored && piece.kind == TokenKind::Word &&
           !isReservedWord(piece.text);
  }

  static void bindPattern(const Pieces &out, std::size_t begin, std::size_t end,
                          std::set<std::size_t> &binders,
                          std::map<std::size_t, std::string> &shorthand) {
    for (auto k = begin; k < end; ++k) {
      if (!bindable(out[k]))
        continue;
      auto pathSegment = (k > begin && symbol(out[k - 1], ".")) ||
                         (k + 1 < end && symbol(out[k + 1], "."));
      auto fieldName = k + 1 < end && symbol(out[k + 1], ":");
      auto constructor =
          k + 1 < end && (symbol(out[k + 1], "(") || symbol(out[k + 1], "{"));
      if (!pathSegment && !fieldName && !constructor) {
        binders.insert(k);
        auto beforeField =
            k > begin && (symbol(out[k - 1], "{") || symbol(out[k - 1], ","));
        auto afterField =
            k + 1 < end && (symbol(out[k + 1], ",") || symbol(out[k + 1], "}"));
        if (beforeField && afterField)
          shorthand.emplace(k, out[k].text);
      }
    }
  }

  static std::size_t patternEnd(const Pieces &out,
                                const std::vector<std::size_t> &close,
                                std::size_t begin, std::size_t end,
                                bool forLoop) {
    for (auto k = begin; k < end;) {
      if (opener(out[k])) {
        if (close[k] == none)
          return end;
        k = close[k] + 1;
        continue;
      }
      if (newline(out[k]) || symbol(out[k], ":") || symbol(out[k], "=") ||
          (forLoop && out[k].kind == TokenKind::Word && out[k].text == "in"))
        return k;
      ++k;
    }
    return end;
  }

  static void bindParameters(const Pieces &out,
                             const std::vector<std::size_t> &close,
                             std::size_t open, std::size_t end,
                             std::set<std::size_t> &binders,
                             std::map<std::size_t, std::string> &shorthand) {
    auto begin = open + 1;
    for (auto k = begin; k <= end;) {
      if (k != end && opener(out[k])) {
        if (close[k] == none)
          break;
        k = close[k] + 1;
        continue;
      }
      if (k != end && !symbol(out[k], ",")) {
        ++k;
        continue;
      }
      auto patternEnd = k;
      for (auto p = begin; p < k;) {
        if (opener(out[p])) {
          if (close[p] == none)
            break;
          p = close[p] + 1;
          continue;
        }
        if (symbol(out[p], ":")) {
          patternEnd = p;
          break;
        }
        ++p;
      }
      bindPattern(out, begin, patternEnd, binders, shorthand);
      begin = k + 1;
      ++k;
    }
  }

  static void bindMatchArms(const Pieces &out,
                            const std::vector<std::size_t> &close,
                            std::set<std::size_t> &binders,
                            std::map<std::size_t, std::string> &shorthand) {
    for (std::size_t i = 0; i + 1 < out.size(); ++i) {
      if (out[i].kind != TokenKind::Word || out[i].text != "match")
        continue;
      auto open = i + 1;
      while (open < out.size() && !symbol(out[open], "{")) {
        if (opener(out[open])) {
          if (close[open] == none)
            break;
          open = close[open] + 1;
        } else {
          ++open;
        }
      }
      if (open >= out.size() || close[open] == none)
        continue;

      auto armStart = open + 1;
      auto patternEnd = none;
      bool inBody = false;
      for (auto j = open + 1; j < close[open];) {
        if (opener(out[j])) {
          if (close[j] == none)
            break;
          j = close[j] + 1;
          continue;
        }
        if (!inBody && patternEnd == none && out[j].kind == TokenKind::Word &&
            out[j].text == "if")
          patternEnd = j;
        if (!inBody && symbol(out[j], "=>")) {
          auto end = patternEnd == none ? j : patternEnd;
          bindPattern(out, armStart, end, binders, shorthand);
          inBody = true;
          ++j;
          continue;
        }
        if (inBody && (symbol(out[j], ",") || newline(out[j]))) {
          armStart = j + 1;
          patternEnd = none;
          inBody = false;
        }
        ++j;
      }
    }
  }

  // Identifiers that the template itself binds get a name unique to this
  // expansion, so they can neither capture nor shadow a name of the caller.
  void hygiene(Pieces &out, std::size_t mark,
               const std::vector<std::string> &definitionScope,
               const std::vector<std::string> &useScope) {
    std::set<std::size_t> binders;
    std::map<std::size_t, std::string> shorthand;
    std::vector<std::size_t> close;
    if (!pairing(out, close))
      return;
    for (std::size_t i = 0; i + 1 < out.size(); ++i) {
      if (!out[i].authored || out[i].kind != TokenKind::Word)
        continue;
      const auto &word = out[i].text;
      if (word == "let" || word == "var" || word == "for") {
        auto begin = i + 1;
        auto end = patternEnd(out, close, begin, out.size(), word == "for");
        bindPattern(out, begin, end, binders, shorthand);
      } else if (word == "fn") {
        auto open = symbol(out[i + 1], "(") ? i + 1
                    : i + 2 < out.size() &&
                            out[i + 1].kind == TokenKind::Word &&
                            symbol(out[i + 2], "(")
                        ? i + 2
                        : none;
        if (open != none) {
          if (close[open] != none)
            bindParameters(out, close, open, close[open], binders, shorthand);
        }
      }
    }
    bindMatchArms(out, close, binders, shorthand);
    std::set<std::string> renamed;
    for (auto index : binders)
      renamed.insert(out[index].text);
    for (std::size_t i = 0; i < out.size(); ++i) {
      if (!bindable(out[i]) || !renamed.contains(out[i].text))
        continue;
      if (i > 0 && (symbol(out[i - 1], ".") || symbol(out[i - 1], "::")))
        continue;
      auto label = i > 0 && i + 1 < out.size() && symbol(out[i + 1], ":") &&
                   (symbol(out[i - 1], "(") || symbol(out[i - 1], ",")) &&
                   !binders.contains(i);
      if (!label)
        out[i].text += "__m" + std::to_string(mark);
    }
    std::set<std::size_t> freeNames;
    if (definitionScope != useScope) {
      std::set<std::string> markedNames;
      for (const auto &name : renamed)
        markedNames.insert(name + "__m" + std::to_string(mark));
      static const std::set<std::string> primitiveTypes{
          "Unit", "Never", "bool", "char", "f32",  "f64",
          "i8",   "i16",   "i32",  "i64",  "i128", "isize",
          "u8",   "u16",   "u32",  "u64",  "u128", "usize"};
      for (std::size_t i = 0; i < out.size(); ++i) {
        const auto &piece = out[i];
        if (!piece.authored || piece.kind != TokenKind::Word ||
            isReservedWord(piece.text) || markedNames.contains(piece.text) ||
            piece.text == "Self" || piece.text == "package" ||
            piece.text == "self" || piece.text == "super" ||
            primitiveTypes.contains(piece.text) ||
            (i > 0 && (symbol(out[i - 1], ".") || symbol(out[i - 1], "::"))) ||
            (i + 1 < out.size() &&
             (symbol(out[i + 1], ":") || symbol(out[i + 1], "!"))))
          continue;
        if (i > 0 && out[i - 1].kind == TokenKind::Word &&
            (out[i - 1].text == "fn" || out[i - 1].text == "type" ||
             out[i - 1].text == "enum" || out[i - 1].text == "alias" ||
             out[i - 1].text == "const" || out[i - 1].text == "static" ||
             out[i - 1].text == "union" || out[i - 1].text == "interface" ||
             out[i - 1].text == "module"))
          continue;
        freeNames.insert(i);
      }
    }
    Pieces hygienic;
    hygienic.reserve(out.size() +
                     freeNames.size() * (2 + 2 * definitionScope.size()) +
                     2 * shorthand.size());
    for (std::size_t i = 0; i < out.size(); ++i) {
      const auto &piece = out[i];
      if (freeNames.contains(i)) {
        hygienic.push_back(
            {TokenKind::Word, "package", piece.origin, piece.space});
        for (const auto &part : definitionScope) {
          hygienic.push_back({TokenKind::Symbol, ".", piece.origin, false});
          hygienic.push_back({TokenKind::Word, part, piece.origin, false});
        }
        hygienic.push_back({TokenKind::Symbol, ".", piece.origin, false});
        auto qualified = piece;
        qualified.space = false;
        hygienic.push_back(std::move(qualified));
      } else if (auto found = shorthand.find(i); found != shorthand.end()) {
        auto field = piece;
        field.text = found->second;
        hygienic.push_back(std::move(field));
        hygienic.push_back({TokenKind::Symbol, ":", piece.origin, false});
        auto binding = piece;
        binding.text = found->second + "__m" + std::to_string(mark);
        binding.space = false;
        hygienic.push_back(std::move(binding));
      } else {
        hygienic.push_back(piece);
      }
    }
    out = std::move(hygienic);
  }

  void copy(std::size_t to) {
    if (to > cursor) {
      auto begin = text.size();
      text.append(source.text, cursor, to - cursor);
      Generation::Mapping mapping;
      mapping.begin = begin;
      mapping.end = text.size();
      mapping.target = {cursor, to, source.id};
      mapping.exact = true;
      mappings.push_back(std::move(mapping));
    }
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
      mappings.push_back(std::move(mapping));
    }
  }

  std::size_t cursor = 0;

  std::optional<Source> expandSource() {
    std::size_t next = 0;
    for (std::size_t i = 0; i < pieces.size();) {
      if (next < definitions.size() && i == definitions[next].first) {
        copy(pieces[i].origin.begin);
        cursor = pieces[definitions[next].second].origin.end;
        i = definitions[next].second + 1;
        ++next;
        continue;
      }
      const auto *macro = invoked(pieces, i);
      auto host = !macro && procedure(pieces, i);
      if (!macro && !host) {
        ++i;
        continue;
      }
      auto name = host ? pieces[i].text : macro->name;
      auto first = i, last = close[i + 2];
      Span use{pieces[first].origin.begin, pieces[last].origin.end, source.id};
      copy(use.begin);
      cursor = use.end;
      i = last + 1;
      if (macro && broken.contains(name))
        continue;
      chain.clear();
      Pieces call(pieces.begin() + first, pieces.begin() + last + 1), result;
      if (expandPieces(call, result, 0, use))
        emit(result, use, name);
    }
    copy(source.text.size());
    if (failed)
      return std::nullopt;
    Source generated{source.path, std::move(text), allocate()};
    diagnostics.generated({generated.id,
                           {0, 0, source.id},
                           "macro expansion",
                           std::move(mappings)});
    return generated;
  }
};
} // namespace

std::optional<Source> expandMacros(const Source &source,
                                   Diagnostics &diagnostics,
                                   const SourceAllocator &allocate,
                                   const Procedures *procedural,
                                   std::vector<std::string> modulePath) {
  return Expander(source, diagnostics, allocate, procedural,
                  std::move(modulePath))
      .run();
}
} // namespace mettle::expansion
