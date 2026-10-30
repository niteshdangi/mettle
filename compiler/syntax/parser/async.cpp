#include "syntax/parser/detail.h"
#include <algorithm>

// Lowers `async fn` onto the typed state machines of `core::future`:
//
//   async fn f(a: A): T { s1; let x = await e1; s2; await e2 }
//
// becomes `fn f(a: A): some Future<Output = T>` returning
//
//   defer(take fn() { s1; then(e1, take fn(x) { s2; e2 }) })
//
// Nothing of the body runs before the first poll, the awaited futures and the
// continuation closures are inline state of the returned type, and the
// current segment's locals are the closure captures. Every `await` must be a
// whole statement (`await e`, `let x = await e`, `var x = await e`,
// `x = await e`) of the function's top-level block; other positions are
// reported as unsupported.
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
} // namespace

void Parser::lowerAsync(Function &function) {
  auto &statements = function.body->children;
  auto span = function.span;
  std::size_t lastAwait = statements.size();
  for (std::size_t i = 0; i < statements.size(); ++i)
    if (containsAwait(*statements[i])) {
      if (!awaitStatement(*statements[i])) {
        auto *inner = findAwait(*statements[i]);
        diagnostics.error(
            "feature", inner->span,
            "`await` is supported as a whole statement (`await e`, `let x = "
            "await e`, `var x = await e`, `x = await e`) of the async "
            "function body");
        throw ParseFailure{};
      }
      lastAwait = i;
    }
  for (std::size_t i = 0; i < lastAwait && lastAwait < statements.size(); ++i)
    if (auto *found = findReturn(*statements[i])) {
      diagnostics.error("feature", found->span,
                        "`return` before the last `await` of an async "
                        "function is not implemented");
      throw ParseFailure{};
    }

  auto result = function.annotation;
  if (result.empty())
    result.name = "Unit";
  if (!function.error.empty()) {
    TypeSyntax outcome;
    outcome.form = TypeForm::Outcome;
    outcome.elements.push_back(result);
    outcome.elements.push_back(function.error);
    result = std::move(outcome);
  }
  auto name = [&](std::string text, Span at) {
    return node(Kind::Name, at, std::move(text));
  };
  auto call = [&](const char *callee, Span at,
                  std::vector<std::unique_ptr<Node>> arguments) {
    auto value = node(Kind::Call, at);
    value->children.push_back(name(callee, at));
    for (auto &argument : arguments)
      value->children.push_back(std::move(argument));
    finish(*value);
    return value;
  };
  auto closure = [&](Span at, std::unique_ptr<Node> body,
                     std::vector<ClosureParameter> parameters) {
    auto value = node(Kind::Closure, at);
    value->flag = true;
    value->parameters = std::move(parameters);
    value->children.push_back(std::move(body));
    finish(*value);
    return value;
  };
  auto asBlock = [&](Span at, std::vector<NodeOwner> children) {
    auto value = node(Kind::Block, at);
    value->children = std::move(children);
    finish(*value);
    return value;
  };

  // The future for statements[from..): leading statements, then either the
  // single `lazy` of the remainder or the next await.
  std::vector<std::string> variables;
  auto build = [&](auto &&self, std::size_t from,
                   std::vector<NodeOwner> block) -> std::unique_ptr<Node> {
    std::size_t next = from;
    while (next < statements.size() && !containsAwait(*statements[next]))
      ++next;
    if (next == statements.size()) {
      std::vector<NodeOwner> rest;
      for (auto i = from; i < statements.size(); ++i)
        rest.push_back(std::move(statements[i]));
      auto body = closure(span, asBlock(span, std::move(rest)), {});
      body->annotation = result;
      std::vector<std::unique_ptr<Node>> arguments;
      arguments.push_back(std::move(body));
      block.push_back(call("core::future::lazy", span, std::move(arguments)));
      return asBlock(span, std::move(block));
    }
    for (auto i = from; i < next; ++i) {
      if (statements[i]->kind == Kind::Binding && statements[i]->flag &&
          statements[i]->text != "<pattern>")
        variables.push_back(statements[i]->text);
      block.push_back(std::move(statements[i]));
    }
    auto &statement = statements[next];
    auto at = statement->span;
    Node *await = &*statement;
    if (statement->kind == Kind::Binding)
      await = &*statement->children[0];
    else if (statement->kind == Kind::Assign)
      await = &*statement->children[1];
    auto operand = std::move(await->children[0]);
    bool tail = next + 1 == statements.size() && isAwait(*statement) &&
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
    auto continuation = closure(
        at, self(self, next + 1, std::move(leading)), std::move(parameters));
    std::vector<std::unique_ptr<Node>> arguments;
    arguments.push_back(std::move(operand));
    arguments.push_back(std::move(continuation));
    block.push_back(call("core::future::then", at, std::move(arguments)));
    return asBlock(span, std::move(block));
  };

  std::unique_ptr<Node> future;
  if (lastAwait == statements.size()) {
    std::vector<NodeOwner> body;
    for (auto &statement : statements)
      body.push_back(std::move(statement));
    auto lazy = closure(span, asBlock(span, std::move(body)), {});
    lazy->annotation = result;
    std::vector<std::unique_ptr<Node>> arguments;
    arguments.push_back(std::move(lazy));
    future = call("core::future::lazy", span, std::move(arguments));
  } else {
    std::vector<std::unique_ptr<Node>> arguments;
    arguments.push_back(closure(span, build(build, 0, {}), {}));
    future = call("core::future::defer", span, std::move(arguments));
  }

  TypeSyntax interface;
  interface.name = "core::future::Future";
  GenericArgument output;
  output.binding = "Output";
  output.span = span;
  output.type = std::make_shared<const TypeSyntax>(std::move(result));
  interface.arguments.push_back(std::move(output));
  TypeSyntax opaque;
  opaque.form = TypeForm::Opaque;
  opaque.elements.push_back(std::move(interface));
  function.annotation = std::move(opaque);
  function.error = {};
  std::vector<NodeOwner> body;
  body.push_back(std::move(future));
  function.body = asBlock(function.body->span, std::move(body));
}
} // namespace mettle::parsing
