#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
void Parser::run(Module &module, std::vector<std::string> scope, bool nested) {
  separators();
  while (peek().kind != TokenKind::End && !(nested && is("}"))) {
    auto before = position;
    auto savedNesting = nesting;
    try {
      auto metadata = attributes();
      ItemSyntax item{scope, visibility(), std::move(metadata)};
      if (!item.attributes.empty() && (is("import") || is("alias")))
        feature("attributes on this declaration require its compile-time "
                "implementation");
      if ((is("global_asm") && peek(1).text == "!") ||
          (is("core") && peek(1).text == "::" && peek(2).text == "arch" &&
           peek(3).text == "::" && peek(4).text == "global_asm" &&
           peek(5).text == "!")) {
        if (!item.attributes.empty())
          feature("attributes on global assembly are not implemented");
        module.globalAssembly.push_back(primary());
      } else if (is("extern") || (is("unsafe") && peek(1).text == "extern")) {
        foreignDeclaration(module, std::move(item));
      } else if (is("static")) {
        staticDeclaration(module, std::move(item), false);
      } else if (is("module")) {
        moduleDeclaration(module, std::move(item));
      } else if (is("import")) {
        importDeclaration(module, std::move(item));
      } else if (is("interface")) {
        auto value = interfaceDeclaration();
        value.item = item;
        for (auto &method : value.methods)
          method.item.scope = item.scope;
        module.interfaces.push_back(std::move(value));
      } else if (is("impl") || (is("unsafe") && peek(1).text == "impl")) {
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
        if (peek().kind != TokenKind::Newline && !is(";") &&
            peek().kind != TokenKind::End && !(nested && is("}")))
          fail("expected a newline or ';' after an alias");
        module.aliases.push_back(std::move(alias));
        if (module.aliases.size() > limits::products)
          fail("alias declaration limit exceeded", "limit");
      } else {
        if (!is("fn") && !(is("unsafe") && peek(1).text == "fn"))
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
             !is("pub") && !is("module") && !is("import") && !is("interface") &&
             !is("impl") && !(nested && is("}")))
        ++position;
    }
    separators();
  }
}
} // namespace mettle::parsing

namespace mettle {
Module parse(const Source &source, Diagnostics &diagnostics) {
  Diagnostics::SourceContext context(diagnostics, source);
  Module module;
  module.tokens = tokenize(source, diagnostics);
  if (diagnostics.empty())
    parsing::Parser(module.tokens, diagnostics).run(module);
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
      implementation.target.regions = product.regions;
      for (const auto &parameter : product.genericParameters)
        if (parameter.kind != GenericParameterKind::Region) {
          GenericArgument argument;
          auto type = std::make_shared<TypeSyntax>();
          type->name = parameter.name;
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
      TypeSyntax bound;
      bound.name = interface.name;
      for (const auto &parameter : interface.genericParameters) {
        GenericArgument argument;
        if (parameter.kind == GenericParameterKind::Type)
          argument.type = std::make_shared<const TypeSyntax>(
              TypeSyntax{parameter.name, "", {}, {}});
        else if (parameter.kind == GenericParameterKind::Region)
          argument.region = parameter.name;
        else {
          auto value = std::make_shared<Node>();
          value->kind = Kind::Name;
          value->span = parameter.span;
          value->text = parameter.name;
          argument.value = std::move(value);
        }
        bound.arguments.push_back(std::move(argument));
      }
      self.bounds.push_back(std::move(bound));
      TypeSyntax unsized;
      unsized.name = "unsized";
      self.bounds.push_back(std::move(unsized));
      method.genericParameters.insert(method.genericParameters.begin(),
                                      interface.genericParameters.begin(),
                                      interface.genericParameters.end());
      method.genericParameters.insert(method.genericParameters.begin(),
                                      std::move(self));
      method.constraints.insert(method.constraints.begin(),
                                interface.constraints.begin(),
                                interface.constraints.end());
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
      method.genericParameters.insert(method.genericParameters.begin(),
                                      implementation.genericParameters.begin(),
                                      implementation.genericParameters.end());
      method.implicitGenericParameters =
          implementation.genericParameters.size();
      method.constraints.insert(method.constraints.begin(),
                                implementation.constraints.begin(),
                                implementation.constraints.end());
      module.functions.push_back(std::move(method));
    }
    implementation.methods.clear();
  }
  return module;
}
} // namespace mettle
