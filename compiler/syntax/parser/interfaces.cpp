#include "syntax/parser/detail.h"
#include <string>
#include <string_view>
#include <utility>

namespace mettle::parsing {
namespace {
TypeSyntax namedType(std::string name) {
  TypeSyntax result;
  result.name = std::move(name);
  return result;
}

GenericArgument genericArgument(const GenericParameter &parameter) {
  GenericArgument result;
  result.span = parameter.span;
  if (parameter.kind == GenericParameterKind::Type) {
    result.type = std::make_shared<const TypeSyntax>(namedType(parameter.name));
  } else if (parameter.kind == GenericParameterKind::Region) {
    result.region = parameter.name;
  } else {
    auto value = std::make_shared<Node>();
    value->kind = Kind::Name;
    value->span = parameter.span;
    value->text = parameter.name;
    result.value = std::move(value);
  }
  return result;
}

TypeSyntax asyncFutureProjection(const Module::Interface &interface,
                                 const Function &method,
                                 std::string_view family) {
  TypeSyntax subject = namedType("Self");
  TypeSyntax bound = namedType(interface.name);
  for (const auto &parameter : interface.genericParameters)
    bound.arguments.push_back(genericArgument(parameter));

  TypeSyntax result;
  result.form = TypeForm::Projection;
  result.name = family;
  result.elements.push_back(std::move(subject));
  result.elements.push_back(std::move(bound));
  for (const auto &parameter : method.genericParameters)
    result.arguments.push_back(genericArgument(parameter));
  return result;
}
// Companion of an `async(heap) fn m`: a hidden default method with the same
// parameters that pins the future of `self.m(...)` on the heap and returns it
// erased. Each implementation's instance is that implementation's boxing shim,
// so erased calls dispatch to it. Borrowed parameters without a named region
// receive one, and the erased future lives no longer than every region.
Function erasedAsyncCompanion(const Function &method, std::string_view name,
                              const std::string &interface, Span span) {
  Function result;
  result.name = interface + "." + erasedAsyncName(name);
  // Definitions are identified by span; the contract token names this one.
  result.span = span;
  result.item.visibility = method.item.visibility;
  result.owner = method.owner;
  result.interfaceOwner = method.interfaceOwner;
  result.receiver = method.receiver;
  result.explicitReceiver = method.explicitReceiver;
  result.unsafeFunction = method.unsafeFunction;
  result.genericParameters = method.genericParameters;
  result.constraints = method.constraints;
  for (const auto &parameter : method.parameters) {
    result.parameters.push_back(
        {parameter.name, parameter.annotation, parameter.span, parameter.mode});
    auto &copy = result.parameters.back();
    copy.format = parameter.format;
    if ((copy.mode == "read" || copy.mode == "mut") &&
        copy.annotation.sources.empty()) {
      GenericParameter region;
      region.kind = GenericParameterKind::Region;
      region.name = "$erased_" + std::to_string(result.parameters.size());
      region.span = parameter.span;
      copy.annotation.sources.push_back(region.name);
      result.genericParameters.push_back(std::move(region));
    }
  }
  TypeSyntax output = method.asyncOutput;
  if (!method.asyncError.empty()) {
    TypeSyntax outcome;
    outcome.form = TypeForm::Outcome;
    outcome.elements.push_back(std::move(output));
    outcome.elements.push_back(method.asyncError);
    output = std::move(outcome);
  }
  TypeSyntax future = namedType("core::future::Future");
  GenericArgument binding;
  binding.binding = "Output";
  binding.span = method.span;
  binding.type = std::make_shared<const TypeSyntax>(std::move(output));
  future.arguments.push_back(std::move(binding));
  TypeSyntax erased;
  erased.form = TypeForm::Erased;
  erased.elements.push_back(std::move(future));
  for (const auto &parameter : result.genericParameters)
    if (parameter.kind == GenericParameterKind::Region)
      erased.sources.push_back(parameter.name);
  TypeSyntax owner;
  owner.form = TypeForm::Owner;
  owner.ownerKind = OwnerKind::Heap;
  owner.nested = std::make_shared<const TypeSyntax>(std::move(erased));
  result.annotation.form = TypeForm::Pinned;
  result.annotation.elements.push_back(std::move(owner));

  auto make = [&](Kind kind, std::string text = "") {
    auto value = std::make_unique<Node>();
    value->kind = kind;
    value->span = method.span;
    value->text = std::move(text);
    return value;
  };
  auto receiver = make(Kind::Name, "self");
  auto member = make(Kind::Field, std::string(name));
  member->children.push_back(std::move(receiver));
  auto call = make(Kind::Call);
  call->children.push_back(std::move(member));
  for (std::size_t p = 1; p < method.parameters.size(); ++p) {
    const auto &parameter = method.parameters[p];
    auto argument = make(Kind::Name, parameter.name);
    if (parameter.mode == "read" || parameter.mode == "mut") {
      auto borrow = make(Kind::Unary, parameter.mode);
      borrow->children.push_back(std::move(argument));
      argument = std::move(borrow);
    }
    call->children.push_back(std::move(argument));
  }
  auto pin = make(Kind::Call);
  pin->children.push_back(make(Kind::Name, "alloc::boxed::pin"));
  pin->children.push_back(std::move(call));
  auto body = make(Kind::Block);
  body->children.push_back(std::move(pin));
  result.body = NodeOwner(std::move(body));
  return result;
}
} // namespace

TypeSyntax Parser::boundType() {
  TypeSyntax bound;
  if (take("for")) {
    auto parameters = genericParameters();
    for (const auto &parameter : parameters) {
      if (parameter.kind != GenericParameterKind::Region)
        fail("higher-ranked binders may contain only regions");
      bound.binders.push_back(parameter.name);
    }
  }
  auto components = path();
  for (const auto &component : components) {
    if (!bound.name.empty())
      bound.name += "::";
    bound.name += component;
  }
  if (is("<"))
    bound.arguments = genericArguments();
  return bound;
}
Module::Associated Parser::associatedDeclaration() {
  Module::Associated result;
  result.span = peek().span;
  result.constant = take("const");
  if (!result.constant)
    expect("type");
  result.name = name().text;
  result.genericParameters = genericParameters();
  if (take(":")) {
    if (result.constant)
      result.annotation = type(false);
    else
      do {
        result.bounds.push_back(type(false));
      } while (take("+"));
  }
  result.constraints = genericConstraints();
  if (take("=")) {
    if (result.constant)
      result.constantValue = std::shared_ptr<const Node>(expr());
    else
      result.value = type();
  }
  result.span.end = tokens[position - 1].span.end;
  if (!is(";") && peek().kind != TokenKind::Newline && !is("}"))
    fail("expected an associated item separator");
  return result;
}
Module::Interface Parser::interfaceDeclaration() {
  Module::Interface result;
  result.span = expect("interface").span;
  result.name = name().text;
  result.genericParameters = genericParameters();
  if (take(":"))
    do {
      result.superinterfaces.push_back(type(false));
    } while (take("+"));
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto visible = visibility();
    if (is("type") || is("const")) {
      if (!metadata.empty())
        feature("attributes on associated items are not implemented");
      auto associated = associatedDeclaration();
      associated.visibility = std::move(visible);
      result.associated.push_back(std::move(associated));
    } else {
      std::string mode = "read";
      pendingUnsafe = take("unsafe");
      pendingAsync = take("async");
      std::string futureStorage;
      Span storageSpan;
      if (pendingAsync && take("(")) {
        storageSpan = peek().span;
        if (!take("heap"))
          fail("expected `heap`, the supported erased future storage",
               "signature");
        futureStorage = "heap";
        expect(")");
      }
      if (is("mut") || is("take") || is("static"))
        mode = tokens[position++].text;
      auto method = function(true, true);
      if (method.constructor)
        fail("constructors cannot be declared in an interface", "signature");
      method.item.attributes = std::move(metadata);
      method.owner = result.name;
      method.interfaceOwner = result.name;
      method.receiver = mode;
      if (method.explicitReceiver) {
        if (mode != "read")
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.name = result.name + "." + method.name;
      method.item.visibility = std::move(visible);
      if (method.asynchronous) {
        // A default body's future type is always inferred from the body;
        // a written output still binds the family's Future.Output.
        method.asyncDefaultFutureInferred = method.body.get() != nullptr;
        Module::Associated future;
        future.name =
            "$async_future_" + method.name.substr(method.name.rfind('.') + 1);
        future.span = method.span;
        future.visibility = method.item.visibility;
        future.asyncFuture = true;
        future.asyncFutureDefaultInferred = method.asyncDefaultFutureInferred;
        future.genericParameters = method.genericParameters;
        future.constraints = method.constraints;

        TypeSyntax futureBound = namedType("core::future::Future");
        if (!method.asyncOutput.empty() || !method.body.get()) {
          TypeSyntax output = method.asyncOutput;
          if (!method.asyncError.empty()) {
            TypeSyntax outcome;
            outcome.form = TypeForm::Outcome;
            outcome.elements.push_back(std::move(output));
            outcome.elements.push_back(method.asyncError);
            output = std::move(outcome);
          }
          GenericArgument binding;
          binding.binding = "Output";
          binding.span = method.span;
          binding.type = std::make_shared<const TypeSyntax>(std::move(output));
          futureBound.arguments.push_back(std::move(binding));
        }
        future.bounds.push_back(std::move(futureBound));
        if (method.asyncDefaultFutureInferred)
          method.asyncDefaultBodyResult = method.annotation;

        method.asyncFuture = future.name;
        method.annotation =
            asyncFutureProjection(result, method, method.asyncFuture);
        method.error = {};
        result.associated.push_back(std::move(future));
      }
      if (mode != "static" && !method.explicitReceiver)
        method.parameters.insert(
            method.parameters.begin(),
            {"self", TypeSyntax{"Self", "", {}, {}}, method.span, mode});
      if (!futureStorage.empty()) {
        if (mode == "static" || mode == "take")
          fail("an `async(heap)` method needs a read or mut receiver",
               "signature");
        if (method.asyncOutput.empty())
          fail("an `async(heap)` method declares its output type", "signature");
        for (const auto &parameter : method.parameters)
          if (parameter.pattern)
            fail("`async(heap)` method parameters must be named", "signature");
        method.futureStorage = futureStorage;
        auto shortName = method.name.substr(method.name.rfind('.') + 1);
        auto companion =
            erasedAsyncCompanion(method, shortName, result.name, storageSpan);
        result.methods.push_back(std::move(method));
        result.methods.push_back(std::move(companion));
      } else
        result.methods.push_back(std::move(method));
    }
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
Module::Implementation Parser::implementationDeclaration() {
  Module::Implementation result;
  result.unsafeImplementation = take("unsafe");
  result.span = peek().span;
  expect("extend");
  result.genericParameters = genericParameters();
  result.target = type(false);
  if (take("not")) {
    result.negative = true;
    result.interface = type(false);
    result.constraints = genericConstraints();
    result.span.end = tokens[position - 1].span.end;
    endItem("a negative extension");
    return result;
  }
  if (takeContinuation("implements"))
    result.interface = type(false);
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto visible = visibility();
    if (is("type") || (is("const") && peek(1).text != "fn")) {
      if (!metadata.empty())
        feature("attributes on associated items are not implemented");
      auto associated = associatedDeclaration();
      associated.visibility = std::move(visible);
      result.associated.push_back(std::move(associated));
    } else {
      std::string mode = "read";
      pendingUnsafe = take("unsafe");
      pendingAsync = take("async");
      std::string futureStorage;
      Span storageSpan;
      if (pendingAsync && take("(")) {
        storageSpan = peek().span;
        if (!take("heap"))
          fail("expected `heap`, the supported erased future storage",
               "signature");
        futureStorage = "heap";
        expect(")");
      }
      if (is("mut") || is("take") || is("static"))
        mode = tokens[position++].text;
      auto method = function();
      method.item.attributes = std::move(metadata);
      method.owner = result.target.name;
      method.receiver = mode;
      if (method.constructor) {
        if (!result.interface.empty() || mode != "read")
          fail("constructors require an inherent extension without a receiver",
               "signature");
        method.annotation = result.target;
        method.receiver = "static";
      }
      if (method.explicitReceiver) {
        if (mode != "read" || method.constructor)
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.item.visibility = std::move(visible);
      if (!method.constructor && mode != "static" && !method.explicitReceiver)
        method.parameters.insert(method.parameters.begin(),
                                 {"self", result.target, method.span, mode});
      result.methods.push_back(std::move(method));
    }
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
} // namespace mettle::parsing
