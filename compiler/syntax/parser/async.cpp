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
// Not lowered here (reported as unsupported): `await` in a loop, in a branch
// that is not last in its block, or in a lazily evaluated operand. They need
// the locals of the enclosing scope carried between iterations or joined
// after the branch, which is a checker/IR-level state-machine transform.
namespace mettle::parsing {
namespace {
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
      reject(current, "`await` inside a loop is not implemented: the loop "
                      "future would have to carry the locals of the scope "
                      "between iterations");
      return;
    case Kind::If:
    case Kind::Match:
      reject(current, "`await` in a branch is supported only when the "
                      "`if`/`match` is the last statement of its block");
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
      if (direct && current.text == "read" &&
          !isAwait(*current.children[0]))
        current.text = "take";
      break;
    }
    case Kind::While:
    case Kind::Loop:
    case Kind::For:
    case Kind::Block:
    case Kind::Unsafe:
      reject(current, "`await` inside a loop or nested block is not "
                      "implemented; the statement must be a whole `await`, "
                      "or the `if`/`match` last in its block");
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
  branchFuture = [&](Node &statement, std::vector<NodeOwner> &rest,
                     const std::vector<std::string> &variables)
      -> std::unique_ptr<Node> {
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
        reject(*source.children[0],
               "`await` is not allowed in a match guard");
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
    enum class Step { Rest, Await, Branch, Exit };
    auto step = Step::Rest;
    std::size_t next = from;
    while (next < stmts.size()) {
      auto &current = *stmts[next];
      if (containsAwait(current)) {
        if (awaitStatement(current)) {
          step = Step::Await;
          break;
        }
        if (isBranch(current) && !containsAwait(*current.children[0])) {
          if (next + 1 != stmts.size())
            reject(current, "`await` in a branch is supported only when the "
                            "`if`/`match` is the last statement of its block");
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
      auto lazyBody = closure(span, asBlock(span, std::move(rest)), {});
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
    auto &statement = stmts[next];
    auto at = statement->span;
    Node *await = &*statement;
    if (statement->kind == Kind::Binding)
      await = &*statement->children[0];
    else if (statement->kind == Kind::Assign)
      await = &*statement->children[1];
    auto operand = std::move(await->children[0]);
    bool tail = next + 1 == stmts.size() && isAwait(*statement) &&
                !statement->semicolon;
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

  bool awaits = std::any_of(statements.begin(), statements.end(),
                            [](const NodeOwner &statement) {
                              return containsAwait(*statement);
                            });
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
