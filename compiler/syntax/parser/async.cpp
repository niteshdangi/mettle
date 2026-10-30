#include "syntax/parser/detail.h"
#include <algorithm>
#include <functional>
#include <iterator>

// Lowers `async fn`, `async { .. }` and `async fn(..) { .. }` onto the typed
// state machines of `core::future`:
//
//   async fn f(a: A): T { s1; let x = await e1; s2; await e2 }
//
// becomes `fn f(a: A): some Future<Output = T>` returning
//
//   defer(take fn() { s1; then(e1, take fn(x) { s2; e2 }) })
//
// Nothing of the body runs before the first poll, the awaited futures and the
// continuation closures are inline state of the returned type, and the
// current segment's locals are the closure captures. Without allocation the
// lowering handles:
//
// - `await` as a whole statement (`await e`, `let x = await e`,
//   `var x = await e`, `x = await e`);
// - `await` in any eagerly evaluated subexpression (`f(await a) + 1`,
//   `let (p, q) = await e`, `if await c { .. }`): the awaits are hoisted into
//   temporaries in evaluation order, and operands evaluated before an await
//   are hoisted with it so the order is preserved;
// - `await` inside the branches of an `if`/`else if`/`match` that is the last
//   statement of its block: every branch becomes its own future and the
//   branches join in `core::future::Either`;
// - `return` before the last await when it is the last statement of a branch
//   of an `if`/`match` with exactly one branch that continues: the statements
//   after it move into that branch, the returning branch becomes a ready
//   future.
//
// - `await` inside `while`, `loop` and `for` statements: the body becomes a
//   step closure over the loop-carried state, a tuple of the enclosing `var`
//   locals, run by `core::future::repeat`; `break`/`continue` (labeled or not)
//   become `return`s of `finish_loop`/`next_iteration` (the existing early
//   return lowering then places the statements after them), and the statements
//   after the loop continue from the final state. `for` keeps the iterator of
//   an owned source in the state as one more `var`;
// - `await` in a nested block or in a branch that is not last in its block:
//   the block or the joined branches become a sub-future yielding the state,
//   and the following statements continue from it.
//
// - `return value` inside an awaiting loop of an async function that does not
//   throw: the loop's result becomes `core::future::Exit`, `return` finishes
//   the loop with `give_up` and the statements after the loop run only for
//   `Exit::Leave`; `while let p = e` becomes `loop { match e { p => .., _ =>
//   break } }`.
//
// Not lowered here (reported as unsupported): `await` in a lazily evaluated
// operand, `throw`/`?` inside an awaiting loop, `return`/`throw`/`?` inside an
// awaiting block or branch or nested awaiting loops, `for` over a borrowed
// place, an inner
// binding that shadows a carried `var`, and a loop used as a value other than
// as a statement. Immutable locals used by a loop are captured, so values used
// both inside and after it must be copyable.
namespace mettle::parsing {
namespace {
bool isLoop(const Node &node) {
  return node.kind == Kind::While || node.kind == Kind::Loop ||
         node.kind == Kind::For;
}
// A `return`, `throw` or `?` leaves the whole function, which a nested
// sub-future cannot do.
const Node *findExit(const Node &node) {
  if (node.kind == Kind::Closure)
    return nullptr;
  if (node.kind == Kind::Return || node.kind == Kind::Throw ||
      node.kind == Kind::Try)
    return &node;
  for (const auto &child : node.children)
    if (child.get())
      if (auto *found = findExit(*child))
        return found;
  return nullptr;
}
// A `throw` or `?`, which leaves the function with an error outcome.
const Node *findThrowOrTry(const Node &node) {
  if (node.kind == Kind::Closure)
    return nullptr;
  if (node.kind == Kind::Throw || node.kind == Kind::Try)
    return &node;
  for (const auto &child : node.children)
    if (child.get())
      if (auto *found = findThrowOrTry(*child))
        return found;
  return nullptr;
}
bool bindsName(const Pattern &pattern, const std::string &name) {
  if ((pattern.kind == PatternKind::Binding ||
       pattern.kind == PatternKind::At) &&
      pattern.text == name)
    return true;
  return std::any_of(
      pattern.children.begin(), pattern.children.end(),
      [&](const Pattern &child) { return bindsName(child, name); });
}
bool declares(const Node &node, const std::string &name) {
  if (node.kind == Kind::Closure)
    return false;
  if (node.kind == Kind::Binding && node.text == name)
    return true;
  for (const auto &pattern : node.patterns)
    if (bindsName(pattern, name))
      return true;
  return std::any_of(node.children.begin(), node.children.end(),
                     [&](const NodeOwner &child) {
                       return child.get() && declares(*child, name);
                     });
}
// A `for` source that the checker would iterate by borrowing.
bool borrowedSource(const Node &node) {
  const Node *current = &node;
  while (current->kind == Kind::Group)
    current = current->children[0].get();
  return current->kind == Kind::Name || current->kind == Kind::Field ||
         current->kind == Kind::Index ||
         (current->kind == Kind::Unary &&
          (current->text == "*" || current->text == "mut" ||
           current->text == "read"));
}
bool isAwait(const Node &node) {
  return node.kind == Kind::Unary && node.text == "await";
}
bool containsAwait(const Node &node) {
  if (node.kind == Kind::Closure)
    return false;
  if (isAwait(node))
    return true;
  return std::any_of(node.children.begin(), node.children.end(),
                     [](const NodeOwner &child) {
                       return child.get() && containsAwait(*child);
                     });
}
const Node *findReturn(const Node &node) {
  if (node.kind == Kind::Closure)
    return nullptr;
  if (node.kind == Kind::Return)
    return &node;
  for (const auto &child : node.children)
    if (child.get())
      if (auto *found = findReturn(*child))
        return found;
  return nullptr;
}
const Node *findAwait(const Node &node) {
  if (node.kind == Kind::Closure)
    return nullptr;
  if (isAwait(node))
    return &node;
  for (const auto &child : node.children)
    if (child.get())
      if (auto *found = findAwait(*child))
        return found;
  return nullptr;
}
bool usesName(const Node &node, const std::string &name) {
  if (node.kind == Kind::Name && node.text == name)
    return true;
  return std::any_of(node.children.begin(), node.children.end(),
                     [&](const NodeOwner &child) {
                       return child.get() && usesName(*child, name);
                     });
}
bool isBranch(const Node &node) {
  return node.kind == Kind::If || node.kind == Kind::Match;
}
bool endsWithReturn(const std::vector<NodeOwner> &statements) {
  return !statements.empty() && statements.back().get() &&
         statements.back()->kind == Kind::Return;
}
// A statement whose await is the whole statement or the whole initializer.
bool awaitStatement(const Node &node) {
  if (isAwait(node))
    return !containsAwait(*node.children[0]);
  if (node.kind == Kind::Binding && node.patterns.empty() &&
      node.children.size() == 1 && node.text != "<pattern>")
    return isAwait(*node.children[0]) &&
           !containsAwait(*node.children[0]->children[0]);
  if (node.kind == Kind::Assign && node.text == "=" &&
      node.children[0]->kind == Kind::Name &&
      node.children[0]->text.find("::") == std::string::npos)
    return isAwait(*node.children[1]) &&
           !containsAwait(*node.children[1]->children[0]);
  return false;
}
bool simple(const Node &node);
// Reading a place has no effect an await can reorder: locals are owned by the
// function and nothing borrowed lives across the await.
bool placeLike(const Node &node) {
  if (node.kind == Kind::Name)
    return true;
  if (node.kind == Kind::Field)
    return !node.children.empty() && placeLike(*node.children[0]);
  if (node.kind == Kind::Index)
    return node.children.size() == 2 && placeLike(*node.children[0]) &&
           simple(*node.children[1]);
  return false;
}
bool simple(const Node &node) {
  if (node.children.empty() || node.kind == Kind::Closure || placeLike(node))
    return true;
  return node.kind == Kind::Unary &&
         (node.text == "read" || node.text == "mut" || node.text == "take") &&
         placeLike(*node.children[0]);
}
// An effectful operand that may be evaluated into a temporary of its own.
bool valueKind(const Node &node) {
  switch (node.kind) {
  case Kind::Call:
  case Kind::Binary:
  case Kind::Cast:
  case Kind::Tuple:
  case Kind::Array:
  case Kind::Group:
  case Kind::Coalesce:
  case Kind::Try:
  case Kind::Range:
    return true;
  case Kind::Unary:
    return node.text == "-" || node.text == "!" || node.text == "*";
  default:
    return false;
  }
}
// Number of paths of an if/match that continue after it instead of ending in
// a `return`.
int continuing(const Node &node);
int continuingPath(const Node &path) {
  if (isBranch(path))
    return continuing(path);
  if (path.kind == Kind::Block)
    return !path.children.empty() && path.children.back()->kind == Kind::Return
               ? 0
               : 1;
  return 1;
}
int continuing(const Node &node) {
  if (node.kind == Kind::If)
    return continuingPath(*node.children[1]) +
           (node.children.size() > 2 ? continuingPath(*node.children[2]) : 1);
  int total = 0;
  for (std::size_t i = 1; i < node.children.size(); ++i)
    total += continuingPath(*node.children[i]->children.back());
  return total;
}
} // namespace

TypeSyntax Parser::asyncResult(TypeSyntax result, TypeSyntax error,
                               bool unitIfEmpty) {
  if (result.empty() && (unitIfEmpty || !error.empty()))
    result.name = "Unit";
  if (!error.empty()) {
    TypeSyntax outcome;
    outcome.form = TypeForm::Outcome;
    outcome.elements.push_back(std::move(result));
    outcome.elements.push_back(std::move(error));
    result = std::move(outcome);
  }
  return result;
}

std::unique_ptr<Node> Parser::asyncBody(Node &body, TypeSyntax result,
                                        Span span) {
  auto &statements = body.children;
  auto reject = [&](const Node &at, const std::string &message) {
    auto *inner = findAwait(at);
    diagnostics.error("feature", inner ? inner->span : at.span, message);
    throw ParseFailure{};
  };
  auto name = [&](std::string text, Span at) {
    return node(Kind::Name, at, std::move(text));
  };
  auto call = [&](const char *callee, Span at,
                  std::vector<NodeOwner> arguments) {
    auto value = node(Kind::Call, at);
    value->children.push_back(name(callee, at));
    for (auto &argument : arguments)
      value->children.push_back(std::move(argument));
    finish(*value);
    return value;
  };
  auto closure = [&](Span at, std::unique_ptr<Node> block,
                     std::vector<ClosureParameter> parameters) {
    auto value = node(Kind::Closure, at);
    value->flag = true;
    value->parameters = std::move(parameters);
    value->children.push_back(std::move(block));
    finish(*value);
    return value;
  };
  auto asBlock = [&](Span at, std::vector<NodeOwner> children) {
    auto value = node(Kind::Block, at);
    value->children = std::move(children);
    finish(*value);
    return value;
  };
  auto wrap = [&](const char *callee, std::unique_ptr<Node> future) {
    auto at = future->span;
    std::vector<NodeOwner> arguments;
    arguments.push_back(std::move(future));
    return call(callee, at, std::move(arguments));
  };

  // Evaluates `slot` into a fresh `let` temporary placed in `out`.
  auto bind = [&](NodeOwner &slot, std::vector<NodeOwner> &out) {
    auto at = slot->span;
    auto label = slot->name;
    auto temporary = "<await-" + std::to_string(awaitTemporaries++) + ">";
    auto binding = node(Kind::Binding, at, temporary);
    binding->children.push_back(std::move(slot));
    finish(*binding);
    out.push_back(std::move(binding));
    slot = name(temporary, at);
    slot->name = label;
  };

  // Moves every await in the eagerly evaluated part of `slot` into temporaries
  // appended to `out`, together with the effectful operands evaluated before
  // it, so the evaluation order is preserved.
  std::function<void(NodeOwner &, std::vector<NodeOwner> &)> hoist;
  hoist = [&](NodeOwner &slot, std::vector<NodeOwner> &out) {
    Node &current = *slot;
    if (!containsAwait(current))
      return;
    if (isAwait(current)) {
      hoist(current.children[0], out);
      bind(slot, out);
      return;
    }
    std::size_t eager = current.children.size();
    switch (current.kind) {
    case Kind::Binary:
      if (current.text == "&&" || current.text == "||")
        eager = 1;
      break;
    case Kind::Coalesce:
      eager = 1;
      break;
    case Kind::Unary:
      if (current.text != "-" && current.text != "!" && current.text != "*")
        eager = 0;
      break;
    case Kind::Call:
    case Kind::Group:
    case Kind::Tuple:
    case Kind::Array:
    case Kind::Field:
    case Kind::Index:
    case Kind::Cast:
    case Kind::Try:
    case Kind::Range:
      break;
    case Kind::While:
    case Kind::Loop:
    case Kind::For:
      reject(current, "`await` in a loop is supported only when the loop is "
                      "a statement of its own, not inside an expression");
      return;
    case Kind::If:
    case Kind::Match:
      reject(current, "`await` in a branch is supported only when the "
                      "`if`/`match` is a statement of its own, not inside an "
                      "expression");
      return;
    default:
      eager = 0;
      break;
    }
    std::size_t last = 0;
    for (std::size_t i = 0; i < current.children.size(); ++i)
      if (current.children[i].get() && containsAwait(*current.children[i]))
        last = i;
    if (last >= eager) {
      reject(current, "`await` is not allowed in a lazily evaluated operand "
                      "(a closure, the right side of `&&`, `||` or `??`, a "
                      "borrow); bind the awaited value to a local first");
      return;
    }
    for (std::size_t i = 0; i <= last; ++i) {
      auto &child = current.children[i];
      if (!child.get())
        continue;
      if (containsAwait(*child))
        hoist(child, out);
      else if (!simple(*child)) {
        if (!valueKind(*child) || (current.kind == Kind::Call && i == 0)) {
          reject(current, "an operand evaluated before an `await` cannot be "
                          "reordered around it; bind it to a local first");
          return;
        }
        bind(child, out);
      }
    }
  };
  // An await that is itself the value is bound to a temporary; when its
  // operand awaits too, only the operand is hoisted first.
  auto hoistValue = [&](NodeOwner &value, std::vector<NodeOwner> &out) {
    if (isAwait(*value) && containsAwait(*value->children[0]))
      hoist(value->children[0], out);
    else
      hoist(value, out);
  };
  auto hoistStatement = [&](NodeOwner &slot, std::vector<NodeOwner> &out) {
    Node &current = *slot;
    switch (current.kind) {
    case Kind::Binding:
      if (current.children.size() > 1 && containsAwait(*current.children[1]))
        reject(current, "`await` is not allowed in a `let .. else` block");
      hoistValue(current.children[0], out);
      break;
    case Kind::Assign:
      if (containsAwait(*current.children[0]))
        reject(current, "`await` is not allowed in an assignment target");
      hoistValue(current.children[1], out);
      break;
    case Kind::Return:
    case Kind::Throw:
    case Kind::If:
      hoistValue(current.children[0], out);
      break;
    case Kind::Match: {
      bool direct = isAwait(*current.children[0]);
      hoistValue(current.children[0], out);
      if (direct && current.text == "read" && !isAwait(*current.children[0]))
        current.text = "take";
      break;
    }
    case Kind::While:
    case Kind::Loop:
    case Kind::For:
    case Kind::Block:
    case Kind::Unsafe:
      reject(current, "`await` inside an `unsafe` block is not implemented; "
                      "await before or after it");
      break;
    default:
      if (isAwait(current)) {
        hoist(current.children[0], out);
        break;
      }
      hoist(slot, out);
      break;
    }
  };

  // A borrow bound by `let r = read x` / `mut x` would have to stay valid in
  // the future state while the continuation owns `x`.
  auto checkBorrows = [&](std::vector<NodeOwner> &list) {
    for (std::size_t i = 0; i < list.size(); ++i) {
      auto &statement = *list[i];
      if (statement.kind != Kind::Binding || statement.text == "<pattern>" ||
          statement.children.empty())
        continue;
      auto &initializer = *statement.children[0];
      if (initializer.kind != Kind::Unary ||
          (initializer.text != "read" && initializer.text != "mut") ||
          containsAwait(initializer))
        continue;
      auto suspend = i + 1;
      while (suspend < list.size() && !containsAwait(*list[suspend]))
        ++suspend;
      for (auto k = suspend + 1; k < list.size(); ++k) {
        if (usesName(*list[k], statement.text)) {
          diagnostics.error(
              "feature", statement.span,
              "`" + statement.text +
                  "` is a borrow that is still used after an `await`; a "
                  "borrow of a local cannot live in the future state, so "
                  "borrow again after the await");
          throw ParseFailure{};
        }
        if (list[k]->kind == Kind::Binding && list[k]->text == statement.text)
          break;
      }
    }
  };

  std::function<std::unique_ptr<Node>(std::vector<NodeOwner> &, std::size_t,
                                      std::vector<NodeOwner>,
                                      std::vector<std::string>)>
      build;
  std::function<std::unique_ptr<Node>(Node &, std::vector<NodeOwner> &,
                                      const std::vector<std::string> &)>
      branchFuture;
  // Builds the statement that ends a sub-future (the next loop iteration, or
  // the carried state of a block or joined branch); unset outside of those.
  std::function<std::unique_ptr<Node>(Span)> tailExit;

  auto refuse = [&](Span at, const std::string &message) {
    diagnostics.error("feature", at, message);
    throw ParseFailure{};
  };
  // The `var` locals in scope, each once: the state a sub-future carries.
  auto carriedOf = [&](const std::vector<std::string> &variables) {
    std::vector<std::string> result;
    for (auto it = variables.rbegin(); it != variables.rend(); ++it)
      if (std::find(result.begin(), result.end(), *it) == result.end())
        result.push_back(*it);
    return result;
  };
  // At least two elements, so the state is always a real tuple.
  auto stateOf = [&](const std::vector<std::string> &carried, Span at) {
    auto value = node(Kind::Tuple, at);
    for (auto &variable : carried)
      value->children.push_back(name(variable, at));
    value->children.push_back(node(Kind::Unit, at));
    if (value->children.size() < 2)
      value->children.push_back(node(Kind::Unit, at));
    finish(*value);
    return value;
  };
  // `let (<carry-0>, .., _) = <source>` (with the loop result when
  // `withResult`) followed by `var x = <carry-i>` for every carried local.
  auto unpack = [&](const std::vector<std::string> &carried, Span at,
                    const char *source, bool withResult,
                    std::vector<NodeOwner> &out) {
    Pattern state;
    state.kind = PatternKind::Tuple;
    state.span = at;
    for (std::size_t i = 0; i < carried.size(); ++i)
      state.children.push_back(Pattern{PatternKind::Binding, at,
                                       "<carry-" + std::to_string(i) + ">"});
    state.children.push_back(Pattern{PatternKind::Wildcard, at});
    if (state.children.size() < 2)
      state.children.push_back(Pattern{PatternKind::Wildcard, at});
    Pattern whole = state;
    if (withResult) {
      whole = Pattern{PatternKind::Tuple, at};
      whole.children.push_back(std::move(state));
      whole.children.push_back(
          Pattern{PatternKind::Binding, at, "<loop-result>"});
    }
    auto binding = node(Kind::Binding, at, "<pattern>");
    binding->patterns.push_back(std::move(whole));
    binding->children.push_back(name(source, at));
    finish(*binding);
    out.push_back(std::move(binding));
    for (std::size_t i = 0; i < carried.size(); ++i) {
      auto rebinding = node(Kind::Binding, at, carried[i]);
      rebinding->flag = true;
      rebinding->children.push_back(
          name("<carry-" + std::to_string(i) + ">", at));
      finish(*rebinding);
      out.push_back(std::move(rebinding));
    }
  };
  // The sub-future `first` followed by `after`, which continues from the
  // carried state (and the loop result) that `first` produced.
  auto sequel = [&](std::unique_ptr<Node> first,
                    const std::vector<std::string> &carried, bool withResult,
                    std::vector<NodeOwner> &after,
                    const std::vector<std::string> &variables, Span at) {
    ClosureParameter parameter;
    parameter.span = at;
    parameter.name = "<joined>";
    std::vector<NodeOwner> lead;
    unpack(carried, at, "<joined>", withResult, lead);
    std::vector<ClosureParameter> parameters;
    parameters.push_back(std::move(parameter));
    auto continuation = closure(at, build(after, 0, std::move(lead), variables),
                                std::move(parameters));
    std::vector<NodeOwner> arguments;
    arguments.push_back(std::move(first));
    arguments.push_back(std::move(continuation));
    return call("core::future::then", at, std::move(arguments));
  };
  // Turns the `break`/`continue` that leave the loop labeled `label` into
  // returns of the loop step; `inner` holds the labels of loops nested in the
  // body, `nested` whether an unlabeled exit would target one of them.
  // The name of the `LoopKind` witness of the loop whose exits are rewritten.
  std::string loopKind;
  // Whether the loop being lowered contains a `return`, so its result is a
  // `core::future::Exit` that either leaves the loop or the whole function.
  bool loopExits = false;
  std::function<void(Node &, const std::string &, bool,
                     std::vector<std::string> &,
                     const std::vector<std::string> &)>
      rewriteExits;
  rewriteExits = [&](Node &parent, const std::string &label, bool nested,
                     std::vector<std::string> &inner,
                     const std::vector<std::string> &carried) {
    for (auto &slot : parent.children) {
      if (!slot.get() || slot->kind == Kind::Closure)
        continue;
      Node &child = *slot;
      if (child.kind == Kind::Return && loopExits) {
        auto at = child.span;
        std::vector<NodeOwner> give;
        if (child.children.empty())
          give.push_back(node(Kind::Unit, at));
        else
          give.push_back(std::move(child.children[0]));
        give.push_back(name(loopKind, at));
        std::vector<NodeOwner> arguments;
        arguments.push_back(stateOf(carried, at));
        arguments.push_back(call("core::future::give_up", at, std::move(give)));
        auto exit = node(Kind::Return, at);
        exit->children.push_back(
            call("core::future::finish_loop", at, std::move(arguments)));
        finish(*exit);
        slot = NodeOwner(std::move(exit));
        continue;
      }
      if (child.kind == Kind::Break || child.kind == Kind::Continue) {
        bool mine =
            child.label.empty()
                ? !nested
                : child.label == label && std::find(inner.begin(), inner.end(),
                                                    child.label) == inner.end();
        if (mine) {
          auto at = child.span;
          std::vector<NodeOwner> arguments;
          arguments.push_back(stateOf(carried, at));
          const char *callee = "core::future::next_iteration";
          if (child.kind == Kind::Continue)
            arguments.push_back(name(loopKind, at));
          if (child.kind == Kind::Break) {
            callee = "core::future::finish_loop";
            NodeOwner value = child.children.empty()
                                  ? NodeOwner(node(Kind::Unit, at))
                                  : std::move(child.children[0]);
            if (loopExits) {
              std::vector<NodeOwner> leave;
              leave.push_back(std::move(value));
              leave.push_back(name(loopKind, at));
              value = call("core::future::leave", at, std::move(leave));
            }
            arguments.push_back(std::move(value));
          }
          auto exit = node(Kind::Return, at);
          exit->children.push_back(call(callee, at, std::move(arguments)));
          finish(*exit);
          slot = NodeOwner(std::move(exit));
          continue;
        }
      }
      if (isLoop(child)) {
        if (loopExits && containsAwait(child) && findReturn(child))
          refuse(child.span, "`return` inside a loop that awaits within "
                             "another awaiting loop is not implemented");
        bool labeled = !child.label.empty();
        if (labeled)
          inner.push_back(child.label);
        rewriteExits(child, label, true, inner, carried);
        if (labeled)
          inner.pop_back();
      } else
        rewriteExits(child, label, nested, inner, carried);
    }
  };
  // `for p in source { body }` over an owned source becomes
  //   var <for-iter> = into_iterator(source)
  //   loop { match take <for-iter>.next() {
  //     present(p) => body, none => break } }
  // spliced in place of the `for`. A built-in `lo..hi` / `lo..=hi` range
  // (not an iterator) instead counts a carried `var`:
  //   var <for-next> = lo; let <for-end> = hi; [var <for-done> = false]
  //   loop { if !(<for-next> < <for-end>) { break }   // `..=`: done/`>`
  //          let p = <for-next>; <for-next> = <for-next> + 1; body }
  // and `..=` sets <for-done> instead of stepping past `hi`.
  auto desugarFor = [&](std::vector<NodeOwner> &list, std::size_t at) {
    Node &source = *list[at];
    auto span = source.span;
    if (auto &range = *source.children[0];
        range.kind == Kind::Range && range.children.size() == 2) {
      bool inclusive = range.text == "..=";
      auto suffix = std::to_string(awaitTemporaries++) + ">";
      auto next = "<for-next-" + suffix, end = "<for-end-" + suffix,
           done = "<for-done-" + suffix;
      auto bind = [&](const std::string &text, bool mutable_, NodeOwner value) {
        auto binding = node(Kind::Binding, span, text);
        binding->flag = mutable_;
        binding->children.push_back(std::move(value));
        finish(*binding);
        return binding;
      };
      auto binary = [&](const char *op, NodeOwner left, NodeOwner right) {
        auto value = node(Kind::Binary, span, op);
        value->children.push_back(std::move(left));
        value->children.push_back(std::move(right));
        finish(*value);
        return value;
      };
      auto assign = [&](const std::string &target, NodeOwner value) {
        auto assignment = node(Kind::Assign, span, "=");
        assignment->children.push_back(name(target, span));
        assignment->children.push_back(std::move(value));
        finish(*assignment);
        return assignment;
      };
      auto one = [&] { return node(Kind::Integer, span, "1"); };
      auto conditional = [&](NodeOwner condition, std::vector<NodeOwner> then,
                             std::vector<NodeOwner> otherwise) {
        auto guard = node(Kind::If, span);
        guard->children.push_back(std::move(condition));
        guard->children.push_back(asBlock(span, std::move(then)));
        if (!otherwise.empty())
          guard->children.push_back(asBlock(span, std::move(otherwise)));
        finish(*guard);
        return guard;
      };
      std::vector<NodeOwner> prelude;
      prelude.push_back(bind(next, true, std::move(range.children[0])));
      prelude.push_back(bind(end, false, std::move(range.children[1])));
      if (inclusive)
        prelude.push_back(bind(done, true, node(Kind::Boolean, span, "false")));
      std::vector<NodeOwner> body;
      std::vector<NodeOwner> leave;
      leave.push_back(node(Kind::Break, span));
      auto stop = inclusive
                      ? binary("||", name(done, span),
                               binary(">", name(next, span), name(end, span)))
                      : binary(">=", name(next, span), name(end, span));
      body.push_back(conditional(std::move(stop), std::move(leave), {}));
      auto &pattern = source.patterns[0];
      auto element = node(Kind::Binding, span,
                          pattern.kind == PatternKind::Binding ? pattern.text
                                                               : "<pattern>");
      if (pattern.kind != PatternKind::Binding)
        element->patterns.push_back(std::move(pattern));
      element->children.push_back(name(next, span));
      finish(*element);
      body.push_back(std::move(element));
      if (inclusive) {
        std::vector<NodeOwner> last, step;
        last.push_back(assign(done, node(Kind::Boolean, span, "true")));
        step.push_back(assign(next, binary("+", name(next, span), one())));
        body.push_back(
            conditional(binary("==", name(next, span), name(end, span)),
                        std::move(last), std::move(step)));
      } else
        body.push_back(assign(next, binary("+", name(next, span), one())));
      for (auto &statement : source.children[1]->children)
        body.push_back(std::move(statement));
      auto iteration = node(Kind::Loop, span);
      iteration->label = source.label;
      iteration->semicolon = source.semicolon;
      iteration->children.push_back(asBlock(span, std::move(body)));
      finish(*iteration);
      prelude.push_back(std::move(iteration));
      list.erase(list.begin() + static_cast<std::ptrdiff_t>(at));
      list.insert(list.begin() + static_cast<std::ptrdiff_t>(at),
                  std::make_move_iterator(prelude.begin()),
                  std::make_move_iterator(prelude.end()));
      return;
    }
    if (borrowedSource(*source.children[0]))
      refuse(span, "`await` in a `for` over a borrowed place is not "
                   "implemented: the iterator would borrow across the "
                   "await; iterate an owned value (`for x in take v`, "
                   "`v.into_iter()`)");
    auto iterator = "<for-iter-" + std::to_string(awaitTemporaries++) + ">";
    std::vector<NodeOwner> arguments;
    arguments.push_back(std::move(source.children[0]));
    auto binding = node(Kind::Binding, span, iterator);
    binding->flag = true;
    binding->children.push_back(
        call("core::iter::into_iterator", span, std::move(arguments)));
    finish(*binding);
    auto next = node(Kind::Field, span, "next");
    next->children.push_back(name(iterator, span));
    finish(*next);
    auto advance = node(Kind::Call, span);
    advance->children.push_back(std::move(next));
    finish(*advance);
    auto present = node(Kind::Arm, span);
    present->patterns.push_back(Pattern{PatternKind::Variant, span, "present"});
    present->patterns[0].children.push_back(std::move(source.patterns[0]));
    present->children.push_back(std::move(source.children[1]));
    finish(*present);
    std::vector<NodeOwner> leave;
    leave.push_back(node(Kind::Break, span));
    auto done = node(Kind::Arm, span);
    done->patterns.push_back(Pattern{PatternKind::Variant, span, "none"});
    done->children.push_back(asBlock(span, std::move(leave)));
    finish(*done);
    auto match = node(Kind::Match, span, "take");
    match->children.push_back(std::move(advance));
    match->children.push_back(std::move(present));
    match->children.push_back(std::move(done));
    finish(*match);
    std::vector<NodeOwner> body;
    body.push_back(std::move(match));
    auto iteration = node(Kind::Loop, span);
    iteration->label = source.label;
    iteration->semicolon = source.semicolon;
    iteration->children.push_back(asBlock(span, std::move(body)));
    finish(*iteration);
    list[at] = NodeOwner(std::move(binding));
    list.insert(list.begin() + static_cast<std::ptrdiff_t>(at) + 1,
                NodeOwner(std::move(iteration)));
  };

  // The future of one branch; `rest` (statements that followed an early-exit
  // branch statement) joins the branch that continues.
  auto pathFuture = [&](std::vector<NodeOwner> path,
                        std::vector<NodeOwner> &rest,
                        const std::vector<std::string> &variables) {
    if (!rest.empty() && !endsWithReturn(path)) {
      for (auto &statement : rest)
        path.push_back(std::move(statement));
      rest.clear();
    }
    return build(path, 0, {}, variables);
  };
  auto futureOf = [&](NodeOwner &path, std::vector<NodeOwner> &rest,
                      const std::vector<std::string> &variables) {
    if (isBranch(*path))
      return branchFuture(*path, rest, variables);
    if (path->kind == Kind::Block)
      return pathFuture(std::move(path->children), rest, variables);
    std::vector<NodeOwner> single;
    single.push_back(std::move(path));
    return pathFuture(std::move(single), rest, variables);
  };

  // `if c { A } else { B }` becomes `if c { left(A) } else { right(B) }` over
  // the futures of the branches; `match` nests the pair to the right.
  branchFuture =
      [&](Node &statement, std::vector<NodeOwner> &rest,
          const std::vector<std::string> &variables) -> std::unique_ptr<Node> {
    auto at = statement.span;
    auto result = node(statement.kind, at, statement.text);
    result->patterns = std::move(statement.patterns);
    if (statement.kind == Kind::If) {
      auto thenFuture = futureOf(statement.children[1], rest, variables);
      std::unique_ptr<Node> elseFuture;
      if (statement.children.size() > 2)
        elseFuture = futureOf(statement.children[2], rest, variables);
      else {
        NodeOwner empty = asBlock(at, {});
        elseFuture = futureOf(empty, rest, variables);
      }
      result->children.push_back(std::move(statement.children[0]));
      std::vector<NodeOwner> first, second;
      first.push_back(wrap("core::future::left", std::move(thenFuture)));
      second.push_back(wrap("core::future::right", std::move(elseFuture)));
      result->children.push_back(asBlock(at, std::move(first)));
      result->children.push_back(asBlock(at, std::move(second)));
      finish(*result);
      return result;
    }
    result->children.push_back(std::move(statement.children[0]));
    auto arms = statement.children.size() - 1;
    for (std::size_t i = 0; i < arms; ++i) {
      auto &source = *statement.children[i + 1];
      if (source.flag && containsAwait(*source.children[0]))
        reject(*source.children[0], "`await` is not allowed in a match guard");
      auto future = futureOf(source.children.back(), rest, variables);
      if (i + 1 < arms)
        future = wrap("core::future::left", std::move(future));
      for (std::size_t j = 0; j < i; ++j)
        future = wrap("core::future::right", std::move(future));
      auto arm = node(Kind::Arm, source.span);
      arm->patterns = std::move(source.patterns);
      arm->flag = source.flag;
      if (source.flag)
        arm->children.push_back(std::move(source.children[0]));
      arm->children.push_back(std::move(future));
      finish(*arm);
      result->children.push_back(std::move(arm));
    }
    finish(*result);
    return result;
  };

  // The future for stmts[from..): leading statements, then either the single
  // `lazy` of the remainder or the next await/branch.
  build = [&](std::vector<NodeOwner> &stmts, std::size_t from,
              std::vector<NodeOwner> block,
              std::vector<std::string> variables) -> std::unique_ptr<Node> {
    if (from == 0)
      checkBorrows(stmts);
    enum class Step { Rest, Await, Branch, Exit, Loop, Join, Nest };
    auto step = Step::Rest;
    std::size_t next = from;
    while (next < stmts.size()) {
      auto &current = *stmts[next];
      if (containsAwait(current)) {
        if (awaitStatement(current)) {
          step = Step::Await;
          break;
        }
        if (current.kind == Kind::For) {
          desugarFor(stmts, next);
          continue;
        }
        if (current.kind == Kind::While || current.kind == Kind::Loop) {
          step = Step::Loop;
          break;
        }
        if (current.kind == Kind::Block) {
          if (next + 1 == stmts.size() && !tailExit) {
            auto inner = std::move(current.children);
            stmts.erase(stmts.begin() + static_cast<std::ptrdiff_t>(next));
            stmts.insert(stmts.begin() + static_cast<std::ptrdiff_t>(next),
                         std::make_move_iterator(inner.begin()),
                         std::make_move_iterator(inner.end()));
            continue;
          }
          step = Step::Nest;
          break;
        }
        if (isBranch(current) && !containsAwait(*current.children[0])) {
          if (next + 1 != stmts.size()) {
            if (findReturn(current))
              reject(current, "`await` in a branch that is not last in its "
                              "block cannot also contain `return`, `break` "
                              "or `continue`");
            step = Step::Join;
            break;
          }
          step = Step::Branch;
          break;
        }
        std::vector<NodeOwner> prelude;
        hoistStatement(stmts[next], prelude);
        if (prelude.empty())
          reject(*stmts[next], "this use of `await` is not supported");
        stmts.insert(stmts.begin() + static_cast<std::ptrdiff_t>(next),
                     std::make_move_iterator(prelude.begin()),
                     std::make_move_iterator(prelude.end()));
        continue;
      }
      if (auto *found = findReturn(current)) {
        bool awaitAfter = false;
        for (auto i = next + 1; i < stmts.size(); ++i)
          awaitAfter = awaitAfter || containsAwait(*stmts[i]);
        if (awaitAfter) {
          if (!isBranch(current) || continuing(current) > 1) {
            diagnostics.error(
                "feature", found->span,
                "`return` before the last `await` is supported only as the "
                "last statement of an `if`/`match` branch with a single "
                "branch that continues");
            throw ParseFailure{};
          }
          step = Step::Exit;
          break;
        }
      }
      ++next;
    }
    if (step == Step::Rest) {
      std::vector<NodeOwner> rest;
      for (auto i = from; i < stmts.size(); ++i)
        rest.push_back(std::move(stmts[i]));
      if (tailExit && !endsWithReturn(rest))
        rest.push_back(tailExit(span));
      auto lazyBody = closure(span, asBlock(span, std::move(rest)), {});
      if (!tailExit)
        lazyBody->annotation = result;
      std::vector<NodeOwner> arguments;
      arguments.push_back(std::move(lazyBody));
      block.push_back(call("core::future::lazy", span, std::move(arguments)));
      return asBlock(span, std::move(block));
    }
    for (auto i = from; i < next; ++i) {
      if (stmts[i]->kind == Kind::Binding && stmts[i]->flag &&
          stmts[i]->text != "<pattern>")
        variables.push_back(stmts[i]->text);
      block.push_back(std::move(stmts[i]));
    }
    if (step == Step::Branch || step == Step::Exit) {
      std::vector<NodeOwner> rest;
      for (auto i = next + 1; i < stmts.size(); ++i)
        rest.push_back(std::move(stmts[i]));
      block.push_back(branchFuture(*stmts[next], rest, variables));
      return asBlock(span, std::move(block));
    }
    if (step == Step::Loop || step == Step::Join || step == Step::Nest) {
      auto &subject = *stmts[next];
      auto at = subject.span;
      bool exits = false;
      if (auto *exit = findExit(subject)) {
        // Only `return` of a plain result leaves an awaiting loop, and only
        // when no enclosing sub-future has to be left as well.
        bool supported = step == Step::Loop && !tailExit && !result.empty() &&
                         result.form != TypeForm::Outcome &&
                         !findThrowOrTry(subject);
        if (!supported)
          refuse(exit->span,
                 "`return`, `throw` and `?` are not supported inside a "
                 "block or branch that awaits, nor inside an awaiting loop "
                 "of an `async` function that throws or is nested in "
                 "another awaiting construct; `return` of a plain result is "
                 "supported directly inside a loop");
        exits = findReturn(subject) != nullptr;
      }
      auto carried = carriedOf(variables);
      for (auto &variable : carried)
        if (declares(subject, variable))
          refuse(subject.span,
                 "`" + variable +
                     "` is declared again inside an `await`ing loop, block "
                     "or branch; its state is carried by name, so use "
                     "another name");
      bool valueTail = subject.kind == Kind::Loop && next + 1 == stmts.size() &&
                       !tailExit && !subject.semicolon;
      std::vector<NodeOwner> after;
      for (auto i = next + 1; i < stmts.size(); ++i)
        after.push_back(std::move(stmts[i]));
      auto outer = tailExit;
      auto state = [&stateOf, carried](Span here) {
        return stateOf(carried, here);
      };
      std::unique_ptr<Node> first;
      if (step == Step::Loop) {
        std::vector<NodeOwner> body;
        if (subject.kind == Kind::While && !subject.patterns.empty()) {
          // `while let p = e { body }` is `loop { match e { p => body,
          // _ => break } }`.
          bool place = borrowedSource(*subject.children[0]);
          auto match = node(Kind::Match, at, place ? "read" : "take");
          match->children.push_back(std::move(subject.children[0]));
          auto matched = node(Kind::Arm, at);
          matched->patterns.push_back(std::move(subject.patterns[0]));
          matched->children.push_back(std::move(subject.children[1]));
          finish(*matched);
          std::vector<NodeOwner> leave;
          leave.push_back(node(Kind::Break, at));
          auto stop = node(Kind::Arm, at);
          stop->patterns.push_back(Pattern{PatternKind::Wildcard, at});
          stop->children.push_back(asBlock(at, std::move(leave)));
          finish(*stop);
          match->children.push_back(std::move(matched));
          match->children.push_back(std::move(stop));
          finish(*match);
          body.push_back(std::move(match));
        } else if (subject.kind == Kind::While) {
          auto negation = node(Kind::Unary, at, "!");
          negation->children.push_back(std::move(subject.children[0]));
          finish(*negation);
          std::vector<NodeOwner> leave;
          leave.push_back(node(Kind::Break, at));
          auto guard = node(Kind::If, at);
          guard->children.push_back(std::move(negation));
          guard->children.push_back(asBlock(at, std::move(leave)));
          finish(*guard);
          body.push_back(std::move(guard));
        }
        if (subject.patterns.empty())
          for (auto &statement : subject.children.back()->children)
            body.push_back(std::move(statement));
        auto holder = asBlock(at, std::move(body));
        // `let <loop-kind-N>: LoopKind<R> = LoopKind()`: R is the async
        // function's result for a loop that is its value, otherwise Unit.
        auto kindName =
            "<loop-kind-" + std::to_string(awaitTemporaries++) + ">";
        TypeSyntax loopResult;
        loopResult.name = "Unit";
        if (valueTail && !result.empty())
          loopResult =
              result.form == TypeForm::Outcome ? result.elements[0] : result;
        if (exits) {
          TypeSyntax exitType;
          exitType.name = "core::future::Exit";
          exitType.arguments.push_back(GenericArgument{
              std::make_shared<const TypeSyntax>(std::move(loopResult)),
              {},
              {},
              at,
              {}});
          exitType.arguments.push_back(GenericArgument{
              std::make_shared<const TypeSyntax>(result), {}, {}, at, {}});
          loopResult = std::move(exitType);
        }
        TypeSyntax kindType;
        kindType.name = "core::future::LoopKind";
        kindType.arguments.push_back(GenericArgument{
            std::make_shared<const TypeSyntax>(std::move(loopResult)),
            {},
            {},
            at,
            {}});
        auto witness = node(Kind::Binding, at, kindName);
        witness->annotation = std::move(kindType);
        witness->children.push_back(
            call("core::future::LoopKind", at, std::vector<NodeOwner>{}));
        finish(*witness);
        block.push_back(std::move(witness));
        loopKind = kindName;
        loopExits = exits;
        std::vector<std::string> inner;
        rewriteExits(*holder, subject.label, false, inner, carried);
        loopExits = false;
        tailExit = [&stateOf, &call, &name, carried, kindName](Span here) {
          std::vector<NodeOwner> arguments;
          arguments.push_back(stateOf(carried, here));
          arguments.push_back(name(kindName, here));
          return call("core::future::next_iteration", here,
                      std::move(arguments));
        };
        std::vector<NodeOwner> lead;
        unpack(carried, at, "<state>", false, lead);
        auto iteration = build(holder->children, 0, std::move(lead), carried);
        tailExit = outer;
        ClosureParameter parameter;
        parameter.span = at;
        parameter.name = "<state>";
        std::vector<ClosureParameter> parameters;
        parameters.push_back(std::move(parameter));
        std::vector<NodeOwner> arguments;
        arguments.push_back(stateOf(carried, at));
        arguments.push_back(
            closure(at, std::move(iteration), std::move(parameters)));
        arguments.push_back(name(kindName, at));
        first = call("core::future::repeat", at, std::move(arguments));
      } else {
        tailExit = state;
        if (step == Step::Nest) {
          std::vector<NodeOwner> inner = std::move(subject.children);
          first = build(inner, 0, {}, variables);
        } else {
          std::vector<NodeOwner> nothing;
          first = branchFuture(subject, nothing, variables);
        }
        tailExit = outer;
      }
      if (valueTail)
        after.push_back(name(exits ? "<loop-payload>" : "<loop-result>", at));
      if (exits) {
        // `match take <loop-result> { Return(v) => return v, Leave(r) =>
        // after }`: the statements after the loop continue only when the loop
        // was left normally.
        auto match = node(Kind::Match, at, "take");
        match->children.push_back(name("<loop-result>", at));
        auto leave = node(Kind::Arm, at);
        leave->patterns.push_back(
            Pattern{PatternKind::Variant, at, "core::future::Exit::Leave"});
        leave->patterns[0].children.push_back(
            valueTail ? Pattern{PatternKind::Binding, at, "<loop-payload>"}
                      : Pattern{PatternKind::Wildcard, at});
        leave->children.push_back(asBlock(at, std::move(after)));
        finish(*leave);
        auto give = node(Kind::Return, at);
        give->children.push_back(name("<loop-return>", at));
        finish(*give);
        std::vector<NodeOwner> giveUp;
        giveUp.push_back(std::move(give));
        auto abandon = node(Kind::Arm, at);
        abandon->patterns.push_back(
            Pattern{PatternKind::Variant, at, "core::future::Exit::Return"});
        abandon->patterns[0].children.push_back(
            Pattern{PatternKind::Binding, at, "<loop-return>"});
        abandon->children.push_back(asBlock(at, std::move(giveUp)));
        finish(*abandon);
        match->children.push_back(std::move(leave));
        match->children.push_back(std::move(abandon));
        finish(*match);
        after.clear();
        after.push_back(std::move(match));
      }
      block.push_back(sequel(std::move(first), carried, step == Step::Loop,
                             after, variables, at));
      return asBlock(span, std::move(block));
    }
    auto &statement = stmts[next];
    auto at = statement->span;
    Node *await = &*statement;
    if (statement->kind == Kind::Binding)
      await = &*statement->children[0];
    else if (statement->kind == Kind::Assign)
      await = &*statement->children[1];
    auto operand = std::move(await->children[0]);
    bool tail = next + 1 == stmts.size() && isAwait(*statement) &&
                !statement->semicolon && !tailExit;
    if (tail) {
      block.push_back(std::move(operand));
      return asBlock(span, std::move(block));
    }
    ClosureParameter parameter;
    parameter.span = at;
    std::vector<NodeOwner> leading;
    std::vector<std::string> seen;
    for (auto it = variables.rbegin(); it != variables.rend(); ++it) {
      if (std::find(seen.begin(), seen.end(), *it) != seen.end())
        continue;
      seen.push_back(*it);
      auto rebinding = node(Kind::Binding, at, *it);
      rebinding->flag = true;
      rebinding->children.push_back(name(*it, at));
      finish(*rebinding);
      leading.push_back(std::move(rebinding));
    }
    if (statement->kind == Kind::Binding && !statement->flag &&
        statement->text != "_") {
      parameter.name = statement->text;
      parameter.annotation = statement->annotation;
    } else {
      parameter.name = "<awaited>";
      if (statement->kind == Kind::Binding && statement->text != "_") {
        auto binding = node(Kind::Binding, at, statement->text);
        binding->flag = true;
        binding->annotation = statement->annotation;
        binding->children.push_back(name("<awaited>", at));
        finish(*binding);
        leading.push_back(std::move(binding));
        variables.push_back(statement->text);
      } else if (statement->kind == Kind::Assign) {
        auto assignment = node(Kind::Assign, at, "=");
        assignment->children.push_back(std::move(statement->children[0]));
        assignment->children.push_back(name("<awaited>", at));
        finish(*assignment);
        leading.push_back(std::move(assignment));
      }
    }
    std::vector<ClosureParameter> parameters;
    parameters.push_back(std::move(parameter));
    auto continuation =
        closure(at, build(stmts, next + 1, std::move(leading), variables),
                std::move(parameters));
    std::vector<NodeOwner> arguments;
    arguments.push_back(std::move(operand));
    arguments.push_back(std::move(continuation));
    block.push_back(call("core::future::then", at, std::move(arguments)));
    return asBlock(span, std::move(block));
  };

  bool awaits = std::any_of(
      statements.begin(), statements.end(),
      [](const NodeOwner &statement) { return containsAwait(*statement); });
  if (!awaits) {
    std::vector<NodeOwner> all;
    for (auto &statement : statements)
      all.push_back(std::move(statement));
    auto lazyBody = closure(span, asBlock(span, std::move(all)), {});
    lazyBody->annotation = result;
    std::vector<NodeOwner> arguments;
    arguments.push_back(std::move(lazyBody));
    return call("core::future::lazy", span, std::move(arguments));
  }
  std::vector<NodeOwner> arguments;
  arguments.push_back(closure(span, build(statements, 0, {}, {}), {}));
  return call("core::future::defer", span, std::move(arguments));
}

void Parser::lowerAsync(Function &function) {
  auto bodySpan = function.body->span;
  auto result = asyncResult(function.annotation, function.error, true);
  auto future = asyncBody(*function.body, result, function.span);
  TypeSyntax interface;
  interface.name = "core::future::Future";
  GenericArgument output;
  output.binding = "Output";
  output.span = function.span;
  output.type = std::make_shared<const TypeSyntax>(std::move(result));
  interface.arguments.push_back(std::move(output));
  TypeSyntax opaque;
  opaque.form = TypeForm::Opaque;
  opaque.elements.push_back(std::move(interface));
  function.annotation = std::move(opaque);
  function.error = {};
  auto body = node(Kind::Block, bodySpan);
  body->children.push_back(std::move(future));
  finish(*body);
  function.body = std::move(body);
}
} // namespace mettle::parsing
