#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
bool CheckedModule::imported(std::size_t function) const {
  return function < tree.functions.size() && importedDeclarations &&
         importedDeclarations->functions.contains(
             static_cast<std::uint32_t>(function));
}

bool CheckedModule::hasBody(std::size_t function) const {
  if (tree.functions.at(function).body.get())
    return true;
  return imported(function) && importedDeclarations->functions
                                   .at(static_cast<std::uint32_t>(function))
                                   .hasBody();
}

bool CheckedModule::hasDefault(std::size_t function,
                               std::size_t parameter) const {
  if (tree.functions.at(function).parameters.at(parameter).defaultValue.get())
    return true;
  return imported(function) && importedDeclarations->functions
                                   .at(static_cast<std::uint32_t>(function))
                                   .hasDefault(parameter);
}

bool Checker::imported(Span span) const {
  const auto key = std::tuple{span.source, span.begin, span.end};
  const auto &imports = checked.importedDeclarations;
  return importedSpans.contains(key) ||
         (imports && imports->index && imports->index->spans.contains(key));
}

Type Checker::functionResult(const Function &function) {
  if (imported(function.span))
    return checked.importedDeclarations->functions
        .at(module.functions.indexOf(&function))
        .resultType();
  return inference.value(functionVariables.at(&function));
}

std::shared_ptr<const ImportedTypeDeclaration>
Checker::importedType(Span span,
                      const ImportedDeclarations::TypeTable &items) const {
  return checked.importedDeclarations->findType(span, items);
}

Checker::GenericEnvironment
Checker::declarationEnvironment(const DeclarationEnvironment &value) {
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
}

Checker::GenericEnvironment &
Checker::functionEnvironment(const Function &function) {
  if (auto found = functionGenerics.find(&function);
      found != functionGenerics.end())
    return found->second;
  const auto &imports = checked.importedDeclarations;
  if (imports && imported(function.span)) {
    const auto &contract =
        imports->functions.at(module.functions.indexOf(&function))
            ->materialize();
    return functionGenerics
        .emplace(&function,
                 declarationEnvironment(contract.contract().generics))
        .first->second;
  }
  return functionGenerics.at(&function);
}

const CheckedExpression *Checker::importedExpression(const Node &node) const {
  if (auto found = importedExpressions.find(&node);
      found != importedExpressions.end())
    return found->second;
  const auto &imports = checked.importedDeclarations;
  if (imports && imports->index)
    if (auto found = imports->index->nodes.find(&node);
        found != imports->index->nodes.end())
      return found->second;
  return nullptr;
}

const CheckedExpression &Checker::importExpression(
    const std::shared_ptr<CheckedExpression> &expression) {
  expression->materialize();
  const auto &imports = checked.importedDeclarations;
  if ((imports && imports->index &&
       imports->index->expressions.contains(expression.get())) ||
      (expression->syntax.get() &&
       importedExpressions.contains(expression->syntax.get())))
    return *expression;
  for (const auto &[node, facts] : expression->facts) {
    importedExpressions.emplace(node, expression.get());
    if (node->kind == Kind::Cast)
      importedAnnotations.emplace(&node->annotation, facts.type);
  }
  return *expression;
}

const evaluation::CheckedFunction &
Checker::evaluationContract(const ImportedFunction &function) {
  const auto &contract = function.materialize();
  const auto &result = contract.checkedFunction(typeStore());
  importExpression(contract.body);
  for (const auto &argument : contract.defaults)
    if (argument)
      importExpression(argument);
  return result;
}

std::optional<Type>
Checker::importedAnnotation(const TypeSyntax &syntax) const {
  if (auto found = importedAnnotations.find(&syntax);
      found != importedAnnotations.end())
    return found->second;
  const auto &imports = checked.importedDeclarations;
  if (imports && imports->index)
    if (auto found = imports->index->annotations.find(&syntax);
        found != imports->index->annotations.end())
      return found->second;
  return std::nullopt;
}

void Checker::importDeclarations() {
  const auto &imports = checked.importedDeclarations;
  if (!imports)
    return;
  auto remember = [&](Span span) {
    if (!imported(span))
      importedSpans.emplace(span.source, span.begin, span.end);
  };
  auto expressions = [&](const std::shared_ptr<CheckedExpression> &expression) {
    if (!expression || expression->load)
      return;
    importExpression(expression);
  };
  for (const auto &[index, retained] : imports->functions) {
    if (imports->index && index < module.functions.size())
      if (auto validated = imports->index->functions.find(index);
          validated != imports->index->functions.end() &&
          validated->second.get() == &module.functions[index])
        continue;
    const auto &contract = *retained;
    if (index >= module.functions.size() ||
        module.functions[index].span.source != contract.span.source ||
        module.functions[index].span.begin != contract.span.begin ||
        module.functions[index].span.end != contract.span.end) {
      error("metadata", contract.span,
            "checked function does not match its mounted declaration");
      continue;
    }
    if (!module.functions[index].item.checkedImport)
      module.functions.edit(index).item.checkedImport = true;
    const auto &function = module.functions[index];
    if (function.body.get()) {
      error("metadata", function.span,
            "imported runtime declaration unexpectedly has a source body");
      continue;
    }
    remember(function.span);
    if (!importedAnnotation(function.annotation)) {
      importedAnnotations.emplace(&function.annotation, contract.resultType());
      importedAnnotations.emplace(&function.error, contract.errorType());
      for (std::size_t p = 0;
           p < function.parameters.size() && p < contract.localCount(); ++p)
        importedAnnotations.emplace(&function.parameters[p].annotation,
                                    contract.parameterType(p));
    }
    if (contract.defaults.size() != function.parameters.size() ||
        contract.localCount() < function.parameters.size()) {
      error("metadata", function.span, "checked parameter contract is invalid");
      continue;
    }
    for (std::size_t p = 0; p < contract.defaults.size(); ++p)
      if (bool(contract.defaults[p]) != function.parameters[p].compiledDefault)
        error("metadata", function.parameters[p].span,
              "checked default does not match its mounted declaration");
    expressions(contract.body);
    for (const auto &value : contract.defaults)
      expressions(value);
  }
  auto seed = [&](auto &syntax, const auto &contracts) {
    for (std::size_t i = 0; i < syntax.size(); ++i) {
      const auto &item = syntax[i];
      if (importedType(item.span, contracts)) {
        remember(item.span);
        if (!item.item.checkedImport)
          syntax.edit(i).item.checkedImport = true;
      }
    }
  };
  seed(module.products, imports->products);
  seed(module.aliases, imports->aliases);
  seed(module.interfaces, imports->interfaces);
  seed(module.implementations, imports->implementations);
  for (const auto &item : imports->products)
    typeNames.emplace(item->name, item->type);
  for (const auto &item : imports->aliases)
    typeNames.emplace(item->name, item->type);
  for (const auto &alias : module.aliases)
    if (!importedAnnotation(alias.target))
      if (auto contract = importedType(alias.span, imports->aliases))
        importedAnnotations.emplace(&alias.target, contract->type);
  for (const auto &constant : imports->inherentConstants)
    expressions(constant.initializer);
  auto bindConstant = [&](const ImportedInherentConstant &constant,
                          const Module::Implementation &owner,
                          const Module::Associated &declaration) {
    inherentConstantNames.emplace(constant.name, inherentConstants.size());
    inherentConstants.push_back(
        {&owner,
         &declaration,
         constant.target,
         constant.declaredType,
         constant.value,
         static_cast<unsigned char>(constant.initializer ? 0 : 2),
         constant.materialized,
         constant.initializer,
         {}});
  };
  for (std::size_t c = 0; c < imports->inherentConstants.size(); ++c) {
    const auto &constant = imports->inherentConstants[c];
    if (imports->index && c < imports->index->constants.size()) {
      const auto &binding = imports->index->constants[c];
      if (binding.owner &&
          binding.implementation < module.implementations.size() &&
          binding.owner.get() ==
              &module.implementations[binding.implementation]) {
        bindConstant(constant, *binding.owner,
                     binding.owner->associated[binding.declaration]);
        continue;
      }
    }
    for (std::size_t o = 0; o < module.implementations.size(); ++o)
      if (module.implementations[o].span.source ==
              constant.implementation.source &&
          module.implementations[o].span.begin ==
              constant.implementation.begin &&
          module.implementations[o].span.end == constant.implementation.end) {
        const auto &owner = module.implementations[o];
        for (const auto &declaration : owner.associated)
          if (declaration.span.source == constant.declaration.source &&
              declaration.span.begin == constant.declaration.begin &&
              declaration.span.end == constant.declaration.end) {
            if (constant.initializer &&
                (!declaration.constant ||
                 (declaration.constantValue &&
                  (declaration.constantValue->span.source !=
                       constant.initializer->span.source ||
                   declaration.constantValue->span.begin !=
                       constant.initializer->span.begin ||
                   declaration.constantValue->span.end !=
                       constant.initializer->span.end)))) {
              error("metadata", declaration.span,
                    "checked associated constant does not match "
                    "its initializer");
              continue;
            }
            bindConstant(constant, owner, declaration);
          }
      }
  }
  for (const auto &[index, facts] : imports->statics) {
    if (index >= module.statics.size()) {
      error("metadata", {}, "checked static index is invalid");
      continue;
    }
    remember(module.statics[index].span);
    if (!module.statics[index].item.checkedImport)
      module.statics.edit(index).item.checkedImport = true;
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
  std::map<std::tuple<SourceId, std::size_t, std::size_t>, std::size_t>
      implementationIndices;
  for (std::size_t i = 0; i < module.implementations.size(); ++i) {
    auto span = module.implementations[i].span;
    implementationIndices.emplace(std::tuple{span.source, span.begin, span.end},
                                  i);
  }
  for (std::size_t i = 0; i < checked.interfaceData->implementations.size();
       ++i) {
    const auto &rule = std::as_const(*checked.interfaceData).implementations[i];
    if (auto found = implementationIndices.find(
            {rule.span.source, rule.span.begin, rule.span.end});
        found != implementationIndices.end()) {
      if (!rule.checkedImport || rule.declaration != found->second) {
        auto &local = checked.interfaceData->implementations[i];
        local.checkedImport = true;
        local.declaration = found->second;
      }
    }
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
    result->span = node->span;
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
    // Imported contracts remain owned by checked.importedDeclarations.
    if (checked.imported(i))
      continue;
    ImportedFunction contract;
    contract.span = source.span;
    contract.unsafeFunction = source.unsafeFunction;
    contract.hasBody = source.body.get() != nullptr;
    contract.contract().facts = checked.functions[i];
    contract.contract().generics = environment(functionGenerics.at(&source));
    const auto &regions = functionRegions(source);
    contract.contract().regions = {regions.names, regions.parameters,
                                   regions.environment.assumptions};
    // Destructors are retained so constant evaluation can drop owners.
    if (source.constFunction || source.destructor)
      contract.body = expression(source.body.get());
    for (const auto &parameter : source.parameters)
      contract.defaults.push_back(expression(parameter.defaultValue.get()));
    contract.prepareEvaluation();
    // Importers read only signature slots unless they evaluate exported syntax;
    // runtime bodies come from the archived IR.
    if (!contract.body &&
        std::none_of(contract.defaults.begin(), contract.defaults.end(),
                     [](const auto &value) { return value; })) {
      auto &facts = contract.contract().facts;
      auto keep = std::max<std::size_t>(source.parameters.size(),
                                        facts.variadicCursor + 1);
      keep = std::max<std::size_t>(keep, facts.constructorSelfSlot + 1);
      for (const auto &[slot, parameter] : facts.parameterBindings)
        keep = std::max<std::size_t>(keep, slot + 1);
      for (const auto &[slot, views] : facts.parameterViewTypes)
        keep = std::max<std::size_t>(keep, slot + 1);
      if (keep < facts.locals.size())
        facts.locals.resize(keep);
    }
    result->functions.emplace(
        static_cast<std::uint32_t>(i),
        std::make_shared<const ImportedFunction>(std::move(contract)));
  }
  for (std::size_t i = 0; i < checked.staticStorage.size(); ++i)
    result->statics.emplace(static_cast<std::uint32_t>(i),
                            checked.staticStorage[i]);
  const auto &imports = checked.importedDeclarations;
  auto retain = [&](const auto &syntax, const auto &environments,
                    auto &destination, bool named,
                    const ImportedDeclarations::TypeTable *imported) {
    for (const auto &item : syntax) {
      if (imported)
        if (auto contract = importedType(item.span, *imported)) {
          destination.push_back(std::move(contract));
          continue;
        }
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
      if constexpr (std::is_same_v<std::decay_t<decltype(item)>, Module::Alias>)
        if (contract.type == Type::Unknown) {
          auto *saved = genericEnvironment;
          genericEnvironment = &typeEnvironment(item);
          contract.type = annotation(item.target, item.span);
          genericEnvironment = saved;
        }
      if constexpr (std::is_same_v<std::decay_t<decltype(item)>,
                                   Module::Associated>)
        contract.name = item.name;
      destination.push_back(
          std::make_shared<const ImportedTypeDeclaration>(std::move(contract)));
    }
  };
  retain(module.products, productGenerics, result->products, true,
         imports ? &imports->products : nullptr);
  retain(module.aliases, aliasGenerics, result->aliases, true,
         imports ? &imports->aliases : nullptr);
  retain(module.interfaces, interfaceGenerics, result->interfaces, false,
         imports ? &imports->interfaces : nullptr);
  retain(module.implementations, implementationGenerics,
         result->implementations, false,
         imports ? &imports->implementations : nullptr);
  for (const auto &owner : module.interfaces)
    retain(owner.associated, associatedGenerics, result->associated, false,
           imports ? &imports->associated : nullptr);
  for (const auto &owner : module.implementations)
    retain(owner.associated, associatedGenerics, result->associated, false,
           imports ? &imports->associated : nullptr);
  for (const auto &[name, index] : inherentConstantNames) {
    const auto &constant = inherentConstants[index];
    const auto &implementation = typeEnvironment(*constant.implementation);
    const bool genericNominal =
        checked.types->isProduct(constant.declaredType) &&
        (!implementation.parameters.empty() ||
         checked.types->isSymbolic(constant.target) ||
         checked.types->isSymbolic(constant.declaredType));
    auto initializer = constant.initializer;
    if (genericNominal && !initializer)
      initializer = expression(constant.declaration->constantValue.get());
    result->inherentConstants.push_back(
        {constant.implementation->span, constant.declaration->span, name,
         constant.target, constant.declaredType, constant.value,
         constant.materialized, std::move(initializer)});
  }
  std::map<const Function *, std::string> owners;
  for (std::size_t i = 0; i < module.functions.size(); ++i)
    if (!checked.imported(i))
      owners.emplace(&module.functions[i], checked.function(i).canonicalName);
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
