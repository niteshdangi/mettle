#include "semantics/checker.h"
#include "support/limits.h"
#include <functional>
#include <set>

namespace mettle {
void Checker::declarations() {
  for (const auto &product : module.products) {
    if (imported(product.span))
      continue;
    auto name = definitionName(product.span, product.name);
    if (typeNames.contains(name))
      error("name", product.span, "duplicate type '" + product.name + "'");
    else {
      auto type = checked.types->declareProduct(name, product.copyRequested);
      auto package = checked.namespaces().packageOf(product.span);
      checked.types->setProductPackage(type, package.value_or(unknownPackage));
      typeNames.emplace(name, type);
    }
  }
  aliasStates.resize(module.aliases.size());
  for (std::size_t i = 0; i < module.aliases.size(); ++i) {
    const auto &alias = module.aliases[i];
    if (imported(alias.span)) {
      aliases.emplace(definitionName(alias.span, alias.name), i);
      aliasStates[i] = 2;
      continue;
    }
    std::set<NameKey> regions;
    for (const auto &parameter : alias.genericParameters)
      if (parameter.kind == GenericParameterKind::Region)
        regions.insert(nameKey(parameter.name, parameter.context));
    std::function<void(const TypeSyntax &, std::set<NameKey>)> validate =
        [&](const TypeSyntax &syntax, std::set<NameKey> names) {
          for (const auto &binder : syntax.binders)
            names.insert(nameKey(binder));
          if (syntax.callable) {
            for (const auto &region : syntax.callable->regions)
              names.insert(nameKey(region));
            for (const auto &parameter : syntax.callable->parameters)
              if (!parameter.name.empty())
                names.insert(
                    nameKey(parameter.name, parameter.annotation.context));
          }
          auto reference = [&](const LexicalNameSyntax &name) {
            if (name.spelling != "static" && !names.contains(nameKey(name)))
              error("name", alias.span,
                    "unknown region argument '" + name.spelling + "'");
          };
          for (const auto &source : syntax.sources)
            reference(source);
          for (const auto &region : syntax.regions)
            reference(region);
          if (syntax.nested)
            validate(*syntax.nested, names);
          for (const auto &element : syntax.elements)
            validate(element, names);
          for (const auto &argument : syntax.arguments) {
            if (!argument.region.empty())
              reference(argument.region);
            if (argument.type)
              validate(*argument.type, names);
          }
          if (syntax.callable) {
            for (const auto &parameter : syntax.callable->parameters)
              validate(parameter.annotation, names);
            validate(syntax.callable->result, names);
            validate(syntax.callable->error, names);
          }
        };
    validate(alias.target, std::move(regions));
    auto name = definitionName(alias.span, alias.name);
    if (typeNames.contains(name) || !aliases.emplace(name, i).second)
      error("name", alias.span, "duplicate type '" + alias.name + "'");
  }
  if (!diagnostics.empty())
    return;
  prepareGenerics();
  for (std::size_t i = 0; i < module.aliases.size(); ++i)
    if (imported(module.aliases[i].span))
      continue;
    else if (aliasGenerics.at(&module.aliases[i]).parameters.empty())
      resolveAlias(i);
    else {
      auto saved = genericEnvironment;
      genericEnvironment = &aliasGenerics.at(&module.aliases[i]);
      annotation(module.aliases[i].target, module.aliases[i].span);
      genericEnvironment = saved;
    }
}

Type Checker::resolveAlias(std::size_t index, unsigned depth) {
  const auto &alias = module.aliases[index];
  auto name = definitionName(alias.span, alias.name);
  if (aliasStates[index] == 2)
    return typeNames.at(name);
  if (aliasStates[index] == 1) {
    error("type", alias.span,
          "cyclic type alias '" + alias.name + "' has no concrete target");
    return Type::Unknown;
  }
  if (depth > limits::typeDepth) {
    error("limit", alias.span, "type alias expansion limit exceeded");
    return Type::Unknown;
  }
  aliasStates[index] = 1;
  auto saved = aliasDepth;
  aliasDepth = depth + 1;
  auto type = annotation(alias.target, alias.span);
  aliasDepth = saved;
  aliasStates[index] = 2;
  typeNames.emplace(name, type);
  return type;
}
} // namespace mettle
