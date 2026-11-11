#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
bool Checker::imported(Span span) const {
  return importedSpans.contains({span.source, span.begin, span.end});
}

const ImportedTypeDeclaration *
Checker::importedType(Span span,
                      const std::vector<ImportedTypeDeclaration> &items) const {
  auto found = std::find_if(items.begin(), items.end(), [&](const auto &item) {
    return item.span.source == span.source && item.span.begin == span.begin &&
           item.span.end == span.end;
  });
  return found == items.end() ? nullptr : &*found;
}

void Checker::importDeclarations() {
  const auto &imports = checked.importedDeclarations;
  if (!imports)
    return;
  auto remember = [&](Span span) {
    importedSpans.emplace(span.source, span.begin, span.end);
  };
  auto environment = [&](const DeclarationEnvironment &value) {
    GenericEnvironment result;
    result.names = value.names;
    result.bounds = value.bounds;
    result.parameters = value.parameters;
    result.defaults = value.defaults;
    result.equalities = value.equalities;
    result.declarationSpan = value.declarationSpan;
    for (const auto &[name, type] : result.names)
      genericNames.emplace(type, name);
    return result;
  };
  for (const auto &[index, contract] : imports->functions) {
    if (index >= module.functions.size() ||
        module.functions[index].span.source != contract.span.source ||
        module.functions[index].span.begin != contract.span.begin ||
        module.functions[index].span.end != contract.span.end) {
      error("metadata", contract.span,
            "checked function does not match its mounted declaration");
      continue;
    }
    auto &function = module.functions[index];
    if (function.body.get()) {
      error("metadata", function.span,
            "imported runtime declaration unexpectedly has a source body");
      continue;
    }
    remember(function.span);
    function.item.checkedImport = true;
    checked.importedFunctions.insert(index);
    if (contract.hasBody)
      checked.importedBodies.insert(index);
    facts(function) = contract.facts;
    importedAnnotations.emplace(&function.annotation, contract.facts.result);
    importedAnnotations.emplace(&function.error, contract.facts.error);
    for (std::size_t p = 0;
         p < function.parameters.size() && p < contract.facts.locals.size();
         ++p)
      importedAnnotations.emplace(&function.parameters[p].annotation,
                                  contract.facts.locals[p].type);
    inference.set(functionVariables.at(&function), contract.facts.result);
    for (const auto &local : contract.facts.locals)
      localVariables[&function].push_back(inference.fresh(local.type));
    preparedFunctions.insert(&function);
    checkedFunctions.insert(&function);
    functionGenerics.emplace(&function, environment(contract.generics));
    AnnotationRegions regions;
    regions.names = contract.regions.names;
    regions.parameters = contract.regions.parameters;
    regions.environment.assumptions = contract.regions.assumptions;
    regions.scope = checked.types->regions().binder();
    if (!regions.parameters.empty()) {
      const auto &region =
          checked.types->regions().get(regions.parameters.front());
      regions.scope = {region.binder, region.universe};
      regions.environment.universe = region.universe;
    }
    functionRegionScopes.emplace(&function, std::move(regions));
    if (contract.defaults.size() != function.parameters.size() ||
        contract.facts.locals.size() < function.parameters.size()) {
      error("metadata", function.span, "checked parameter contract is invalid");
      continue;
    }
    for (std::size_t p = 0; p < contract.defaults.size(); ++p)
      if (bool(contract.defaults[p]) != function.parameters[p].compiledDefault)
        error("metadata", function.parameters[p].span,
              "checked default does not match its mounted declaration");
      else if (contract.defaults[p])
        checked.importedDefaults.emplace(index, p);
    auto expressions =
        [&](const std::shared_ptr<CheckedExpression> &expression) {
          if (!expression)
            return;
          for (const auto &[node, facts] : expression->facts) {
            importedExpressions.emplace(node, expression.get());
            if (node->kind == Kind::Cast)
              importedAnnotations.emplace(&node->annotation, facts.type);
          }
        };
    expressions(contract.body);
    for (const auto &value : contract.defaults)
      expressions(value);
  }
  auto seed = [&](auto &syntax, const auto &contracts, auto &destination) {
    for (auto &item : syntax)
      if (const auto *contract = importedType(item.span, contracts)) {
        remember(item.span);
        item.item.checkedImport = true;
        destination.emplace(&item, environment(contract->generics));
      }
  };
  seed(module.products, imports->products, productGenerics);
  seed(module.aliases, imports->aliases, aliasGenerics);
  seed(module.interfaces, imports->interfaces, interfaceGenerics);
  seed(module.implementations, imports->implementations,
       implementationGenerics);
  for (const auto &owner : module.interfaces)
    for (const auto &item : owner.associated)
      if (const auto *contract = importedType(item.span, imports->associated))
        associatedGenerics.emplace(&item, environment(contract->generics));
  for (const auto &owner : module.implementations)
    for (const auto &item : owner.associated)
      if (const auto *contract = importedType(item.span, imports->associated))
        associatedGenerics.emplace(&item, environment(contract->generics));
  for (const auto &item : imports->products)
    typeNames.emplace(item.name, item.type);
  for (const auto &item : imports->aliases)
    typeNames.emplace(item.name, item.type);
  for (const auto &alias : module.aliases)
    if (const auto *contract = importedType(alias.span, imports->aliases))
      importedAnnotations.emplace(&alias.target, contract->type);
  for (const auto &constant : imports->inherentConstants)
    for (const auto &owner : module.implementations)
      if (owner.span.source == constant.implementation.source &&
          owner.span.begin == constant.implementation.begin &&
          owner.span.end == constant.implementation.end)
        for (const auto &declaration : owner.associated)
          if (declaration.span.source == constant.declaration.source &&
              declaration.span.begin == constant.declaration.begin &&
              declaration.span.end == constant.declaration.end) {
            inherentConstantNames.emplace(constant.name,
                                          inherentConstants.size());
            inherentConstants.push_back({&owner, &declaration, constant.target,
                                         constant.declaredType, constant.value,
                                         2});
          }
  for (const auto &[index, facts] : imports->statics) {
    if (index >= module.statics.size()) {
      error("metadata", {}, "checked static index is invalid");
      continue;
    }
    remember(module.statics[index].span);
    module.statics[index].item.checkedImport = true;
    checked.staticStorage[index] = facts;
    staticStates[index] = 2;
    staticTypeStates[index] = 2;
  }
  for (const auto &[index, contract] : imports->closures) {
    if (checked.closureBodies.size() <= index)
      checked.closureBodies.resize(std::size_t(index) + 1);
    auto closure = std::make_unique<ClosureFacts>();
    closure->imported = true;
    closure->type = contract.type;
    closure->declaration.span = contract.span;
    closure->function = contract.facts;
    for (const auto &local : contract.facts.locals)
      localVariables[&closure->declaration].push_back(
          inference.fresh(local.type));
    checked.closureBodies[index] = std::move(closure);
  }
  if (std::any_of(checked.closureBodies.begin(), checked.closureBodies.end(),
                  [](const auto &closure) { return !closure; }))
    error("metadata", {}, "imported closure inventory is not contiguous");
  *checked.interfaceData = imports->checkingDatabase;
  for (auto &rule : checked.interfaceData->implementations)
    for (std::size_t i = 0; i < module.implementations.size(); ++i)
      if (rule.span.source == module.implementations[i].span.source &&
          rule.span.begin == module.implementations[i].span.begin &&
          rule.span.end == module.implementations[i].span.end) {
        rule.declaration = i;
        break;
      }
  for (std::size_t i = 0; i < module.interfaces.size(); ++i)
    if (imported(module.interfaces[i].span) &&
        (i >= checked.interfaceData->definitions.size() ||
         checked.interfaceData->definitions[i].name !=
             definitionName(module.interfaces[i].span,
                            module.interfaces[i].name)))
      error("metadata", module.interfaces[i].span,
            "checked interface does not match its resolved declaration index");
}

void Checker::retainDeclarations() {
  auto result = std::make_shared<ImportedDeclarations>();
  result->types = checked.types;
  result->checkingDatabase = std::move(checkingInterfaces);
  result->database = *checked.interfaceData;
  auto environment = [](const GenericEnvironment &value) {
    return DeclarationEnvironment{value.names,      value.bounds,
                                  value.parameters, value.defaults,
                                  value.equalities, value.declarationSpan};
  };
  auto expression = [&](const Node *node) {
    if (!node)
      return std::shared_ptr<CheckedExpression>{};
    auto result = std::make_shared<CheckedExpression>();
    result->syntax = NodeOwner::borrow(*const_cast<Node *>(node));
    auto collect = [&](auto &&self, const Node &value) -> void {
      if (const auto *facts = checked.find(value))
        result->facts.emplace(&value, *facts);
      for (const auto &child : value.children)
        self(self, *child);
      if (value.kind == Kind::Call && !value.children.empty()) {
        auto found = result->facts.find(&value);
        if (found != result->facts.end() && found->second.callee >= 0)
          result->facts[value.children[0].get()].callee = found->second.callee;
      }
      if (value.kind == Kind::Name && !result->facts[&value].lexicallyBound)
        if (auto storage = staticName(value.text, value.span, value.context);
            storage && checked.staticStorage[*storage].initializer)
          result->constants.emplace(
              &value, *checked.staticStorage[*storage].initializer);
      if (value.kind == Kind::Name) {
        auto &facts = result->facts[&value];
        if (facts.type == Type::Unknown && facts.slot < 0 && facts.callee < 0) {
          facts.type = builtinType(value.text);
          if (facts.type == Type::Unknown)
            if (auto name = checked.namespaces().lookup(
                    nameModule(value.span, value.context), value.text,
                    resolution::Namespace::Type, value.span))
              if (auto type = typeNames.find(*name); type != typeNames.end())
                facts.type = type->second;
        }
      }
    };
    collect(collect, *node);
    return result;
  };
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    const auto &source = module.functions[i];
    if (checked.importedFunctions.contains(i)) {
      result->functions.emplace(static_cast<std::uint32_t>(i),
                                checked.importedDeclarations->functions.at(i));
      continue;
    }
    ImportedFunction contract;
    contract.span = source.span;
    contract.unsafeFunction = source.unsafeFunction;
    contract.hasBody = source.body.get() != nullptr;
    contract.facts = checked.functions[i];
    contract.generics = environment(functionGenerics.at(&source));
    const auto &regions = functionRegions(source);
    contract.regions = {regions.names, regions.parameters,
                        regions.environment.assumptions};
    if (source.constFunction)
      contract.body = expression(source.body.get());
    for (const auto &parameter : source.parameters)
      contract.defaults.push_back(expression(parameter.defaultValue.get()));
    result->functions.emplace(static_cast<std::uint32_t>(i),
                              std::move(contract));
  }
  for (std::size_t i = 0; i < checked.staticStorage.size(); ++i)
    result->statics.emplace(static_cast<std::uint32_t>(i),
                            checked.staticStorage[i]);
  auto retain = [&](const auto &syntax, const auto &environments,
                    auto &destination, bool named) {
    for (const auto &item : syntax) {
      auto found = environments.find(&item);
      if (found == environments.end())
        continue;
      ImportedTypeDeclaration contract;
      contract.span = item.span;
      contract.generics = environment(found->second);
      if constexpr (requires { item.name; }) {
        if (named) {
          contract.name = definitionName(item.span, item.name);
          if (auto type = typeNames.find(contract.name);
              type != typeNames.end())
            contract.type = type->second;
        }
      }
      destination.push_back(std::move(contract));
    }
  };
  retain(module.products, productGenerics, result->products, true);
  retain(module.aliases, aliasGenerics, result->aliases, true);
  for (std::size_t i = 0; i < module.aliases.size(); ++i)
    if (result->aliases[i].type == Type::Unknown) {
      auto *saved = genericEnvironment;
      genericEnvironment = &aliasGenerics.at(&module.aliases[i]);
      result->aliases[i].type =
          annotation(module.aliases[i].target, module.aliases[i].span);
      genericEnvironment = saved;
    }
  retain(module.interfaces, interfaceGenerics, result->interfaces, false);
  retain(module.implementations, implementationGenerics,
         result->implementations, false);
  for (const auto &[syntax, generic] : associatedGenerics)
    result->associated.push_back(
        {syntax->span, syntax->name, Type::Unknown, environment(generic)});
  for (const auto &[name, index] : inherentConstantNames) {
    const auto &constant = inherentConstants[index];
    result->inherentConstants.push_back(
        {constant.implementation->span, constant.declaration->span, name,
         constant.target, constant.declaredType, constant.value});
  }
  std::map<const Function *, std::string> owners;
  for (std::size_t i = 0; i < module.functions.size(); ++i)
    owners.emplace(&module.functions[i], checked.functions[i].canonicalName);
  std::map<const Function *, unsigned> ordinals;
  for (std::size_t i = 0; i < checked.closureBodies.size(); ++i) {
    const auto &closure = *checked.closureBodies[i];
    if (closure.imported) {
      result->closures.emplace(std::uint32_t(i),
                               checked.importedDeclarations->closures.at(i));
      continue;
    }
    auto owner = owners.find(closure.parent);
    auto name =
        (owner == owners.end() ? std::string("<closure>") : owner->second) +
        "::<closure." + std::to_string(ordinals[closure.parent]++) + ">";
    owners.emplace(&closure.declaration, name);
    result->closures.emplace(std::uint32_t(i),
                             ImportedClosure{closure.declaration.span,
                                             std::move(name), closure.function,
                                             closure.type});
  }
  checked.declarationContracts = std::move(result);
}
} // namespace mettle
