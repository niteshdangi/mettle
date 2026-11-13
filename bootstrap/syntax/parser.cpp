#include "syntax/lexer.h"
#include "syntax/parser/detail.h"
#include <algorithm>

namespace mettle::parsing {
std::optional<std::size_t> Parser::fragmentEnd(std::string_view kind,
                                               std::size_t begin) {
  StateGuard guard(*this);
  position = static_cast<std::size_t>(
      std::lower_bound(tokens.begin(), tokens.end(), begin,
                       [](const Token &token, std::size_t offset) {
                         return token.span.begin < offset;
                       }) -
      tokens.begin());
  parens = nesting = genericExpressionLevel = 0;
  loopHeadParens.reset();
  auto savedAsync = inAsyncBody;
  inAsyncBody = true;
  speculating = true;
  struct Restore {
    Parser &parser;
    bool savedAsync;
    ~Restore() {
      parser.undoTokenEdits(0);
      parser.speculating = false;
      parser.inAsyncBody = savedAsync;
    }
  } restore{*this, savedAsync};
  try {
    if (kind == "expr")
      expr();
    else if (kind == "stmt")
      stmt();
    else if (kind == "pat")
      pattern();
    else if (kind == "ty")
      type();
    else if (kind == "path") {
      do {
        name();
        if (genericOpen())
          genericArguments();
      } while (is(".") && nameToken(peek(1)) && take("."));
    } else
      return std::nullopt;
    return peek().span.begin;
  } catch (ParseFailure &) {
    return std::nullopt;
  }
}

void Parser::run(Module &module, std::vector<std::string> scope, bool nested) {
  separators();
  while (peek().kind != TokenKind::End && !(nested && is("}"))) {
    auto before = position;
    auto savedNesting = nesting;
    try {
      auto metadata = attributes();
      ItemSyntax item{scope, visibility(), std::move(metadata)};
      if ((is("global_asm") && peek(1).text == "!") ||
          (is("core") && peek(1).text == "." && peek(2).text == "arch" &&
           peek(3).text == "." && peek(4).text == "global_asm" &&
           peek(5).text == "!")) {
        if (!item.attributes.empty())
          feature("attributes on global assembly are not implemented");
        module.globalAssembly.push_back(primary());
      } else if (is("extern") || (is("unsafe") && peek(1).text == "extern")) {
        foreignDeclaration(module, std::move(item));
      } else if (is("static") ||
                 (is("const") && nameToken(peek(1)) && peek(1).text != "fn" &&
                  peek(1).text != "unsafe" && peek(1).text != "async")) {
        staticDeclaration(module, std::move(item), false);
      } else if (is("module")) {
        moduleDeclaration(module, std::move(item));
      } else if (is("import")) {
        importDeclaration(module, std::move(item));
      } else if (is("interface") ||
                 (is("unsafe") && peek(1).text == "interface")) {
        auto value = interfaceDeclaration();
        value.item = item;
        for (auto &method : value.methods)
          method.item.scope = item.scope;
        module.interfaces.push_back(std::move(value));
      } else if (isExtension()) {
        auto value = implementationDeclaration();
        value.item = item;
        for (auto &method : value.methods)
          method.item.scope = item.scope;
        module.implementations.push_back(std::move(value));
      } else if (is("type") || is("copy") || is("enum") || is("union")) {
        auto value = is("enum") || (is("copy") && peek(1).text == "enum")
                         ? enumeration()
                         : product();
        value.item = item;
        for (auto &method : value.methods)
          method.item.scope = item.scope;
        module.products.push_back(std::move(value));
        if (module.products.size() > limits::products)
          fail("product declaration limit exceeded", "limit");
      } else if (take("alias")) {
        Module::Alias alias;
        alias.span = tokens[position - 1].span;
        alias.item = item;
        alias.name = name().text;
        alias.genericParameters = genericParameters();
        alias.constraints = genericConstraints();
        expect("=");
        alias.target = type();
        alias.span.end = tokens[position - 1].span.end;
        endItem("an alias");
        module.aliases.push_back(std::move(alias));
        if (module.aliases.size() > limits::products)
          fail("alias declaration limit exceeded", "limit");
      } else {
        if (is("impl"))
          fail("implementation blocks must start with `extend`", "parse",
               {{"help", {}, "write `extend Type implements Interface`"}});
        std::size_t keyword = is("unsafe") ? 1 : 0;
        if (peek(keyword).text == "const")
          ++keyword;
        if (peek(keyword).text == "async")
          ++keyword;
        if (peek(keyword).text != "fn")
          feature("this declaration is not implemented");
        auto value = function();
        value.item = std::move(item);
        module.functions.push_back(std::move(value));
        if (module.functions.size() > limits::functions)
          fail("function limit exceeded", "limit");
      }
    } catch (ParseFailure &) {
      parens = 0;
      nesting = savedNesting;
      if (before == position && peek().kind != TokenKind::End)
        ++position;
      while (peek().kind != TokenKind::End && !is("fn") && !is("type") &&
             !is("copy") && !is("alias") && !is("enum") && !is("union") &&
             !is("pub") && !is("internal") && !is("module") && !is("import") &&
             !is("interface") &&
             !(is("extend") && position && tokens[position - 1].text != "." &&
               tokens[position - 1].text != "fn") &&
             !(nested && is("}")))
        ++position;
    }
    separators();
  }
}
} // namespace mettle::parsing

namespace mettle {
struct FragmentParser::Impl {
  Diagnostics diagnostics;
  parsing::Parser parser;

  explicit Impl(const Source &source)
      : parser(tokenize(source, diagnostics), diagnostics) {}
};

FragmentParser::FragmentParser(std::string text)
    : impl(std::make_unique<Impl>(
          Source{"<macro fragment>", std::move(text), 0})) {}
FragmentParser::~FragmentParser() = default;
std::optional<std::size_t> FragmentParser::end(std::string_view kind,
                                               std::size_t begin) {
  return impl->diagnostics.empty() ? impl->parser.fragmentEnd(kind, begin)
                                   : std::nullopt;
}

namespace {
// Semantic facts are keyed by syntax identity, so each method needs its own
// copy of the inherited generic syntax rather than shared callable/nested
// nodes.
TypeSyntax distinctType(const TypeSyntax &source);
std::shared_ptr<const TypeSyntax>
distinctType(const std::shared_ptr<const TypeSyntax> &source) {
  return source ? std::make_shared<TypeSyntax>(distinctType(*source)) : source;
}
TypeSyntax distinctType(const TypeSyntax &source) {
  auto copy = source;
  copy.nested = distinctType(source.nested);
  for (auto &element : copy.elements)
    element = distinctType(element);
  for (auto &argument : copy.arguments)
    argument.type = distinctType(argument.type);
  if (source.callable) {
    auto callable = std::make_shared<CallableTypeSyntax>(*source.callable);
    for (auto &parameter : callable->parameters)
      parameter.annotation = distinctType(parameter.annotation);
    callable->result = distinctType(callable->result);
    callable->error = distinctType(callable->error);
    copy.callable = std::move(callable);
  }
  return copy;
}
std::vector<GenericParameter>
distinctParameters(std::vector<GenericParameter> parameters) {
  for (auto &parameter : parameters) {
    for (auto &bound : parameter.bounds)
      bound = distinctType(bound);
    parameter.annotation = distinctType(parameter.annotation);
    parameter.defaultType = distinctType(parameter.defaultType);
  }
  return parameters;
}
std::vector<GenericConstraint>
distinctConstraints(std::vector<GenericConstraint> constraints) {
  for (auto &constraint : constraints) {
    constraint.subject = distinctType(constraint.subject);
    for (auto &bound : constraint.bounds)
      bound = distinctType(bound);
    if (constraint.equality)
      constraint.equality = distinctType(*constraint.equality);
  }
  return constraints;
}
} // namespace
Module parseDeclarations(const Source &source, Diagnostics &diagnostics) {
  Diagnostics::SourceContext context(diagnostics, source);
  Module module;
  module.tokens = tokenize(source, diagnostics);
  if (diagnostics.empty()) {
    parsing::Parser parser(module.tokens, diagnostics);
    parser.run(module);
    module.textLiterals = parser.textLiterals();
  }
  return module;
}

Module parse(const Source &source, Diagnostics &diagnostics) {
  auto module = parseDeclarations(source, diagnostics);
  completeDeclarations(module);
  return module;
}

void completeDeclarations(Module &module) {
  for (auto &product : module.products) {
    std::vector<std::size_t> methods;
    for (auto &method : product.methods) {
      if (!method.destructor && !method.constructor)
        methods.push_back(module.functions.size());
      module.functions.push_back(std::move(method));
    }
    for (const auto &interface : product.interfaces) {
      Module::Implementation implementation;
      implementation.target.name = product.name;
      implementation.target.context = product.nameContext;
      implementation.target.regions = regionNames(product.genericParameters);
      for (const auto &parameter : product.genericParameters)
        if (parameter.kind != GenericParameterKind::Region) {
          GenericArgument argument;
          auto type = std::make_shared<TypeSyntax>();
          type->name = parameter.name;
          type->context = parameter.context;
          argument.type = std::move(type);
          implementation.target.arguments.push_back(std::move(argument));
        }
      implementation.interface = interface;
      implementation.span = product.span;
      implementation.item = product.item;
      implementation.genericParameters = product.genericParameters;
      implementation.constraints = product.constraints;
      implementation.associated = product.associated;
      implementation.methodFunctions = methods;
      implementation.shorthand = true;
      module.implementations.push_back(std::move(implementation));
    }
    product.methods.clear();
  }
  for (auto &interface : module.interfaces) {
    for (auto &method : interface.methods) {
      GenericParameter self;
      self.name = "Self";
      self.span = interface.span;
      self.context = method.lexicalContext;
      TypeSyntax bound;
      bound.name = interface.name;
      bound.context = interface.nameContext;
      for (const auto &parameter : interface.genericParameters) {
        GenericArgument argument;
        if (parameter.kind == GenericParameterKind::Type) {
          TypeSyntax type{parameter.name, "", {}, {}};
          type.context = parameter.context;
          argument.type = std::make_shared<const TypeSyntax>(std::move(type));
        } else if (parameter.kind == GenericParameterKind::Region)
          argument.region = {parameter.name, parameter.nameSpan,
                             parameter.context};
        else {
          auto value = std::make_shared<Node>();
          value->kind = Kind::Name;
          value->span = parameter.span;
          value->text = parameter.name;
          value->context = parameter.context;
          argument.value = std::move(value);
        }
        bound.arguments.push_back(std::move(argument));
      }
      self.bounds.push_back(std::move(bound));
      TypeSyntax unsized;
      unsized.name = "unsized";
      self.bounds.push_back(std::move(unsized));
      auto inherited = distinctParameters(interface.genericParameters);
      method.genericParameters.insert(method.genericParameters.begin(),
                                      inherited.begin(), inherited.end());
      method.genericParameters.insert(method.genericParameters.begin(),
                                      std::move(self));
      auto constraints = distinctConstraints(interface.constraints);
      method.constraints.insert(method.constraints.begin(), constraints.begin(),
                                constraints.end());
      method.implicitGenericParameters = interface.genericParameters.size() + 1;
      if (!method.item.visibility.publicItem)
        method.item.visibility = interface.item.visibility;
      module.functions.push_back(std::move(method));
    }
    interface.methods.clear();
  }
  for (std::size_t i = 0; i < module.implementations.size(); ++i) {
    auto &implementation = module.implementations[i];
    for (auto &method : implementation.methods) {
      method.implementation = static_cast<int>(i);
      method.interfaceOwner = implementation.interface.name;
      method.name = "<impl." + std::to_string(i) + ">." + method.name;
      auto inherited = distinctParameters(implementation.genericParameters);
      method.genericParameters.insert(method.genericParameters.begin(),
                                      inherited.begin(), inherited.end());
      method.implicitGenericParameters =
          implementation.genericParameters.size();
      auto constraints = distinctConstraints(implementation.constraints);
      method.constraints.insert(method.constraints.begin(), constraints.begin(),
                                constraints.end());
      module.functions.push_back(std::move(method));
    }
    implementation.methods.clear();
  }
}
} // namespace mettle
