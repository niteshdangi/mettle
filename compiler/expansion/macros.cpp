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
      auto expected = pieces[start].text == "(" ? ")"
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
  if (!previous || newline(*previous) || newline(piece))
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
  static const std::set<std::string> known{"expr", "stmt", "pat",  "ty",
                                           "path", "ident", "literal", "tt",
                                           "block", "item"};
  return known.contains(fragment);
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
        node.fragment = tokens[i + 1].text;
        if (!knownFragment(node.fragment))
          fail(tokens[i + 1],
               "unknown fragment kind '" + node.fragment +
                   "'; expected expr, stmt, pat, ty, path, ident, literal, "
                   "tt, block or item");
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
      diagnostics.error(
          "macro", node.piece.origin,
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
  if (text.empty() || text == ")" || text == "]" || text == "}" ||
      text == "=>")
    return true;
  if (fragment == "expr" || fragment == "stmt")
    return text == "," || text == ";";
  if (fragment == "pat")
    return text == "," || text == "=" || text == "if" || text == "in";
  static const std::set<std::string> typed{",", "=", ";", ":", ">", ">>",
                                           "{", "[", "where"};
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
  if (fragment == "ident" || fragment == "literal" || fragment == "tt")
    return true;
  auto text = render(tokens);
  wrap(fragment, text);
  Source probe{"<macro fragment>", std::move(text), 0};
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
      bool literal = kind == TokenKind::Integer || kind == TokenKind::Floating ||
                     kind == TokenKind::Text ||
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
           const SourceAllocator &allocate)
      : source(source), diagnostics(diagnostics), allocate(allocate) {}

  std::optional<Source> run() {
    Diagnostics scratch;
    auto tokens = tokenize(source, scratch);
    if (!scratch.empty())
      return std::nullopt;
    pieces = lower(source, tokens);
    if (!pairing(pieces, close))
      return std::nullopt;
    for (std::size_t i = 0; i + 2 < pieces.size(); ++i)
      if (pieces[i].kind == TokenKind::Word && pieces[i].text == "macro" &&
          pieces[i + 1].kind == TokenKind::Word &&
          symbol(pieces[i + 2], "{")) {
        definitions.push_back({i, close[i + 2]});
        i = close[i + 2];
      }
    if (definitions.empty())
      return std::nullopt;
    Diagnostics::SourceContext context(diagnostics, source);
    for (const auto &definition : definitions)
      define(definition.first, definition.second);
    return expandSource();
  }

private:
  const Source &source;
  Diagnostics &diagnostics;
  const SourceAllocator &allocate;
  Pieces pieces;
  std::vector<std::size_t> close;
  std::vector<std::pair<std::size_t, std::size_t>> definitions;
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
    macro.span = {pieces[at].origin.begin, pieces[last].origin.end,
                  source.id};
    auto i = at + 3;
    auto expect = [&](bool condition, const Piece &where,
                      const char *message) {
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
      auto ok = parseNodes(pieces, close, i + 1, matcherEnd, true,
                           diagnostics, rule.matcher);
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
      if (!macro) {
        out.push_back(in[i++]);
        continue;
      }
      auto last = inner[i + 2];
      if (!broken.contains(macro->name))
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
      error(use, "unbalanced delimiters in the arguments of '" + macro.name +
                     "!'");
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
      hygiene(produced, ++marks);
      return expandPieces(produced, out, depth + 1, use);
    }
    error(use, "no rule of macro '" + macro.name +
                   "' matches this invocation (" +
                   std::to_string(macro.rules.size()) + " rule(s) tried)");
    return false;
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
                         macro.name + "' repeats and must be used inside $(...)");
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
                       std::to_string(count) + " and " +
                       std::to_string(size) + ")");
        return false;
      }
    }
    if (repeating.empty()) {
      error(node.piece.origin,
            "a repetition in an expansion of macro '" + macro.name +
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

  // Names a group binds: tuple patterns after `let`, `var` or `for`, and
  // closure parameters. `parameters` restricts the scan to the group's own
  // level.
  static void bindGroup(const Pieces &out, std::size_t open, bool parameters,
                        std::set<std::size_t> &binders) {
    unsigned depth = 0;
    for (std::size_t k = open; k < out.size(); ++k) {
      if (opener(out[k]))
        ++depth;
      else if (closer(out[k]) && --depth == 0)
        return;
      if (!bindable(out[k]) || (parameters && depth != 1) || k + 1 >= out.size())
        continue;
      auto before = k > 0 && (symbol(out[k - 1], "(") || symbol(out[k - 1], ","));
      auto next = symbol(out[k + 1], ",") || symbol(out[k + 1], ")") ||
                  symbol(out[k + 1], ":");
      if (before && next)
        binders.insert(k);
    }
  }

  // Identifiers that the template itself binds get a name unique to this
  // expansion, so they can neither capture nor shadow a name of the caller.
  void hygiene(Pieces &out, std::size_t mark) {
    std::set<std::size_t> binders;
    for (std::size_t i = 0; i + 1 < out.size(); ++i) {
      if (!out[i].authored || out[i].kind != TokenKind::Word)
        continue;
      const auto &word = out[i].text;
      if (word == "let" || word == "var" || word == "for") {
        if (bindable(out[i + 1]))
          binders.insert(i + 1);
        else if (symbol(out[i + 1], "(") && out[i + 1].authored)
          bindGroup(out, i + 1, false, binders);
      } else if (word == "fn" && symbol(out[i + 1], "(")) {
        bindGroup(out, i + 1, true, binders);
      }
    }
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
      if (!macro) {
        ++i;
        continue;
      }
      auto first = i, last = close[i + 2];
      Span use{pieces[first].origin.begin, pieces[last].origin.end, source.id};
      copy(use.begin);
      cursor = use.end;
      i = last + 1;
      if (broken.contains(macro->name))
        continue;
      chain.clear();
      Pieces call(pieces.begin() + first, pieces.begin() + last + 1), result;
      if (expandPieces(call, result, 0, use))
        emit(result, use, macro->name);
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
                                   const SourceAllocator &allocate) {
  return Expander(source, diagnostics, allocate).run();
}
} // namespace mettle::expansion
