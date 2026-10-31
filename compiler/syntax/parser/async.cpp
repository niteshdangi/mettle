#include "syntax/parser/detail.h"
#include <string>

// Lowers `async fn`, `async { .. }` and `async fn(..) { .. }` onto coroutine
// closures:
//
//   async fn f(a: A): T { body }
//
// becomes `fn f(a: A): some Future<Output = T>` returning
//
//   core::future::coroutine(take fn(): T { body })
//
// where the closure is marked as a coroutine body (`throwing_coroutine` and a
// throwing closure when the body throws). Every `await e` in the body becomes
//
//   { var <await-n> = e
//     loop {
//       match take core::future::poll_await(mut <await-n>,
//                                           core::intrinsics::coroutine_context())
//                                           {
//         present(<ready-n>) => { break <ready-n> },
//         none => core::intrinsics::coroutine_suspend()
//       } } }
//
// The backend keeps the body's frame inline in the returned future and resumes
// it at the suspension point, so `await` composes with every statement form.
namespace mettle::parsing {
std::unique_ptr<Node> Parser::awaitExpression(NodeOwner operand, Span span) {
  auto id = std::to_string(awaitTemporaries++);
  auto pending = "<await-" + id + ">", ready = "<ready-" + id + ">";
  auto make = [&](Kind kind, std::string text = {}) {
    return node(kind, span, std::move(text));
  };
  auto call = [&](const char *callee, std::vector<NodeOwner> arguments) {
    auto value = make(Kind::Call);
    value->children.push_back(make(Kind::Name, callee));
    for (auto &argument : arguments)
      value->children.push_back(std::move(argument));
    finish(*value);
    return value;
  };
  auto block = [&](std::vector<NodeOwner> children) {
    auto value = make(Kind::Block);
    value->children = std::move(children);
    finish(*value);
    return value;
  };

  auto binding = make(Kind::Binding, pending);
  binding->flag = true;
  binding->children.push_back(std::move(operand));
  finish(*binding);

  auto place = make(Kind::Unary, "mut");
  place->children.push_back(make(Kind::Name, pending));
  finish(*place);
  std::vector<NodeOwner> arguments;
  arguments.push_back(std::move(place));
  arguments.push_back(call("core::intrinsics::coroutine_context", {}));
  auto poll = make(Kind::Match, "take");
  poll->children.push_back(
      call("core::future::poll_await", std::move(arguments)));

  auto present = make(Kind::Arm);
  present->patterns.push_back({PatternKind::Variant, span, "present"});
  present->patterns.back().children.push_back(
      {PatternKind::Binding, span, ready});
  auto leave = make(Kind::Break);
  leave->children.push_back(make(Kind::Name, ready));
  finish(*leave);
  std::vector<NodeOwner> body;
  body.push_back(std::move(leave));
  present->children.push_back(block(std::move(body)));
  finish(*present);
  poll->children.push_back(std::move(present));

  auto absent = make(Kind::Arm);
  absent->patterns.push_back({PatternKind::Variant, span, "none"});
  absent->children.push_back(call("core::intrinsics::coroutine_suspend", {}));
  finish(*absent);
  poll->children.push_back(std::move(absent));
  finish(*poll);

  std::vector<NodeOwner> iteration;
  iteration.push_back(std::move(poll));
  auto loop = make(Kind::Loop);
  loop->children.push_back(block(std::move(iteration)));
  finish(*loop);

  std::vector<NodeOwner> statements;
  statements.push_back(std::move(binding));
  statements.push_back(std::move(loop));
  return block(std::move(statements));
}

TypeSyntax Parser::asyncResult(TypeSyntax result, bool unitIfEmpty) {
  if (result.empty() && unitIfEmpty)
    result.name = "Unit";
  return result;
}

std::unique_ptr<Node> Parser::asyncBody(NodeOwner body, TypeSyntax result,
                                        Span span, TypeSyntax error) {
  auto closure = node(Kind::Closure, span, "coroutine");
  closure->flag = true;
  closure->annotation = std::move(result);
  closure->error = std::move(error);
  bool throwing = !closure->error.empty();
  closure->children.push_back(std::move(body));
  finish(*closure);
  auto call = node(Kind::Call, span);
  call->children.push_back(node(Kind::Name, span,
                                throwing ? "core::future::throwing_coroutine"
                                         : "core::future::coroutine"));
  call->children.push_back(std::move(closure));
  finish(*call);
  return call;
}

void Parser::lowerAsync(Function &function) {
  auto bodySpan = function.body->span;
  auto result = asyncResult(function.annotation, true);
  TypeSyntax output = result;
  if (!function.error.empty()) {
    TypeSyntax outcome;
    outcome.form = TypeForm::Outcome;
    outcome.elements.push_back(result);
    outcome.elements.push_back(function.error);
    output = std::move(outcome);
  }
  auto future = asyncBody(std::move(function.body), std::move(result),
                          function.span, std::move(function.error));
  TypeSyntax interface;
  interface.name = "core::future::Future";
  GenericArgument binding;
  binding.binding = "Output";
  binding.span = function.span;
  binding.type = std::make_shared<const TypeSyntax>(std::move(output));
  interface.arguments.push_back(std::move(binding));
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
