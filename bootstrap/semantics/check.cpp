#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include "types/machine.h"
#include <algorithm>
#include <functional>
#include <map>
#include <stdexcept>
#include <utility>

namespace mettle {
void Checker::error(std::string phase, Span span, std::string message,
                    std::vector<DiagnosticMessage> related) {
  if (phase == "type" && std::any_of(staticStates.begin(), staticStates.end(),
                                     [](auto state) { return state == 1; }))
    phase = "constant";
  ++reportedErrors;
  diagnostics.error(std::move(phase), span, std::move(message),
                    std::move(related));
}

void Checker::prepareFunction(Function &f) {
  current = &f;
  if (imported(f.span)) {
    genericEnvironment = &functionGenerics.at(&f);
    return;
  }
  const auto &parameters = genericBindings(f);
  if (!preparedFunctions.insert(&f).second)
    return;
  facts(f).genericParameters = parameters;
  inference.equal(functionVariables.at(&f),
                  inference.fresh(annotation(f.annotation, f.span, f.owner)),
                  f.span);
  if (f.asyncDefaultFutureInferred)
    asyncDefaultBodyVariables[&f] = inference.fresh();
  facts(f).diverges = inference.value(functionVariables.at(&f)) == Type::Never;
  if (f.explicitReceiver) {
    if (f.owner.empty() && f.implementation < 0)
      error("signature", f.span,
            "explicit receiver requires an owning type or interface");
    else {
      auto self = annotation(f.parameters.front().annotation, f.span, f.owner);
      while (checked.types->isView(self))
        self = checked.types->view(self).payload;
      if (checked.types->isProduct(self) &&
          checked.types->product(self).kind == AggregateKind::Pin)
        self = checked.types->view(checked.types->product(self).components[0])
                   .payload;
      TypeSyntax expected;
      expected.name = "Self";
      if (checked.types->eraseRegions(self) !=
          checked.types->eraseRegions(annotation(expected, f.span, f.owner)))
        error("signature", f.span, "explicit receiver must wrap Self");
    }
  }
  if (!f.error.empty())
    facts(f).error = annotation(f.error, f.span, f.owner);
  if (f.body.get())
    controlFlow(f);
}

std::vector<std::size_t> Checker::functionDependencies(Function &function) {
  std::vector<std::size_t> result;
  auto calls = [&](auto &&self, Node &n) -> void {
    const auto &owner = function.owner;
    if (n.kind == Kind::Name && !facts(n).lexicallyBound) {
      auto found = names.find(callableName(n.text, owner, n.span));
      if (found != names.end())
        result.push_back(found->second);
    } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name &&
               !facts(*n.children[0]).lexicallyBound) {
      auto called = callableName(n.children[0]->text, owner, n.span);
      auto found = names.find(called);
      if (found != names.end())
        result.push_back(found->second);
      Type calledType = Type::Unknown;
      if (auto type = typeNames.find(called); type != typeNames.end())
        calledType = type->second;
      else if (auto alias = aliases.find(called); alias != aliases.end()) {
        const auto &syntax = module.aliases[alias->second];
        auto *saved = genericEnvironment;
        genericEnvironment = &aliasGenerics.at(&syntax);
        calledType = annotation(syntax.target, syntax.span);
        genericEnvironment = saved;
      }
      if (checked.types->isProduct(calledType)) {
        auto origin = checked.types->product(calledType).genericOrigin;
        if (origin == Type::Unknown)
          origin = calledType;
        if (auto candidates = constructors.find(origin);
            candidates != constructors.end())
          for (const auto &candidate : candidates->second)
            result.push_back(candidate.function);
      }
    } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Field) {
      for (std::size_t i = 0; i < module.functions.size(); ++i)
        if (module.functions[i].name.ends_with("." + n.children[0]->text))
          result.push_back(i);
    }
    if (auto plan = checked.iterations.find(&n);
        plan != checked.iterations.end())
      self(self, *plan->second.elaboration);
    for (auto &child : n.children)
      self(self, *child);
  };
  if (function.body.get())
    calls(calls, *function.body);
  for (auto &parameter : function.parameters)
    if (parameter.defaultValue.get())
      calls(calls, *parameter.defaultValue);
  return result;
}

void Checker::inferFunctionResult(Function &f) {
  if (checkedFunctions.contains(&f) || !checkingFunctions.insert(&f).second)
    return;
  auto *savedFunction = current;
  auto *savedEnvironment = genericEnvironment;
  auto savedDepth = std::exchange(unsafeDepth, 0);
  auto savedEffects = std::exchange(effectContext, false);
  auto savedPattern = std::exchange(inOrdinaryMatchPattern, false);
  auto savedPin = std::exchange(pinAsOwner, false);
  auto savedScopes = std::move(scopes);
  auto savedLoops = std::move(loopResults);
  auto savedFeatures = std::move(guardedFeatures);
  auto savedClosures = std::move(closureScopes);
  auto savedRegions = std::move(annotationRegionScopes);
  scopes.clear();
  loopResults.clear();
  guardedFeatures.clear();
  closureScopes.clear();
  annotationRegionScopes.clear();
  prepareFunction(f);
  for (auto dependency : functionDependencies(f))
    inferFunctionResult(module.functions[dependency]);
  if (f.body.get()) {
    auto value = flow(*f.body, f.owner);
    if (f.annotation.empty() && !value.normal && !value.returns) {
      facts(f).diverges = true;
      inference.set(functionVariables.at(&f), Type::Never);
    }
  }
  function(f);
  fields(false);
  facts(f).result = inference.value(functionVariables.at(&f));
  checkedFunctions.insert(&f);
  checkingFunctions.erase(&f);
  current = savedFunction;
  genericEnvironment = savedEnvironment;
  unsafeDepth = savedDepth;
  effectContext = savedEffects;
  inOrdinaryMatchPattern = savedPattern;
  pinAsOwner = savedPin;
  scopes = std::move(savedScopes);
  loopResults = std::move(savedLoops);
  guardedFeatures = std::move(savedFeatures);
  closureScopes = std::move(savedClosures);
  annotationRegionScopes = std::move(savedRegions);
}

std::optional<CheckedModule> Checker::run() {
  auto needsConstantTypeCheck = [&](auto &&self, const Node &node) -> bool {
    if (node.kind == Kind::If || node.kind == Kind::Match ||
        node.kind == Kind::Block || node.kind == Kind::While ||
        node.kind == Kind::Loop || node.kind == Kind::For ||
        (node.kind == Kind::Binary && (node.text == "&&" || node.text == "||")))
      return true;
    return std::any_of(node.children.begin(), node.children.end(),
                       [&](const auto &child) { return self(self, *child); });
  };
  auto sourceFunctionCount = module.functions.size();
  module.functions.reserve(sourceFunctionCount + module.statics.size());
  for (auto &storage : module.statics) {
    if (storage.foreignDeclaration || !storage.initializer.get() ||
        !needsConstantTypeCheck(needsConstantTypeCheck, *storage.initializer))
      continue;
    Function initializer;
    initializer.name =
        "<static." + std::to_string(module.functions.size()) + ">";
    initializer.span = storage.initializer->span;
    initializer.annotation = storage.annotation;
    initializer.item.scope = storage.item.scope;
    initializer.constFunction = true;
    initializer.body = NodeOwner::borrow(*storage.initializer);
    module.functions.push_back(std::move(initializer));
  }
  checked.functions.resize(module.functions.size());
  std::unordered_map<std::string, std::size_t> constructorOrdinals;
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &f = module.functions[i];
    auto name = definitionName(f.span, f.name);
    facts(f).canonicalName =
        f.constructor
            ? name + "$init" + std::to_string(constructorOrdinals[name]++)
            : name;
    auto [existing, inserted] = names.emplace(name, i);
    if (!inserted &&
        !(f.constructor && module.functions[existing->second].constructor))
      error("name", f.span, "duplicate function '" + displayPath(f.name) + "'");
    functionVariables[&f] = inference.fresh();
  }
  checked.staticStorage.resize(module.statics.size());
  staticStates.resize(module.statics.size());
  staticTypeStates.resize(module.statics.size());
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    auto &storage = checked.staticStorage[i];
    storage.identity = i;
    storage.name =
        definitionName(module.statics[i].span, module.statics[i].name);
    staticNames.emplace(storage.name, i);
  }
  importDeclarations();
  if (!diagnostics.empty())
    return std::nullopt;
  interfaceHeaders();
  if (!diagnostics.empty())
    return std::nullopt;
  declarations();
  if (!diagnostics.empty())
    return std::nullopt;
  products();
  if (!diagnostics.empty())
    return std::nullopt;
  interfaceSignatures();
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &f = module.functions[i];
    auto name = definitionName(f.span, f.name);
    if (auto type = typeNames.find(name);
        type != typeNames.end() && checked.types->isProduct(type->second) &&
        !checked.types->isSum(type->second))
      error("name", f.span,
            "function conflicts with type constructor '" + displayPath(f.name) +
                "'");
    prepareFunction(f);
    if (f.destructor && !imported(f.span))
      checked.types->setDestructor(typeNames.at(typeName(f.owner, f.span)),
                                   static_cast<int>(i));
  }
  targetDeclarations();
  staticNamesAndTypes();
  for (auto &f : module.functions)
    if (!imported(f.span) && checkedFunctions.contains(&f))
      for (std::size_t i = 0; i < facts(f).locals.size(); ++i) {
        const auto &local = facts(f).locals[i];
        if (local.storage == StorageDuration::Static)
          inference.equal(
              localVariables[&f][i],
              inference.fresh(checked.staticStorage[local.staticIndex].type),
              local.span);
      }
  for (const auto *product : deferredLayouts)
    checked.types->setProductLayout(
        typeNames.at(definitionName(product->span, product->name)),
        productLayout(*product));
  interfaceImplementations();
  if (diagnostics.empty())
    registerConstructors();
  proveDeferredObligations();
  staticDeclarations();
  if (diagnostics.empty())
    resolveRegionProjections();
  if (!diagnostics.empty())
    return std::nullopt;
  struct AsyncCall {
    std::size_t target;
    Span span;
  };
  std::vector<std::vector<AsyncCall>> asyncCalls(module.functions.size());
  for (std::size_t caller = 0; caller < module.functions.size(); ++caller) {
    const auto &function = module.functions[caller];
    if (!function.asynchronous || !function.body.get())
      continue;
    std::function<void(const Node &, bool)> collect = [&](const Node &node,
                                                          bool awaited) {
      if (node.kind == Kind::Closure)
        return;
      if (node.kind == Kind::Binding && node.text.starts_with("<await-")) {
        for (const auto &child : node.children)
          collect(*child, true);
        return;
      }
      if (awaited && node.kind == Kind::Call && !node.children.empty()) {
        const auto &callee = *node.children[0];
        if (callee.kind == Kind::Name) {
          auto name = callableName(callee.text, function.owner, callee.span);
          if (auto found = names.find(name);
              found != names.end() &&
              module.functions[found->second].asynchronous)
            asyncCalls[caller].push_back({found->second, node.span});
        } else if (callee.kind == Kind::Field && !callee.children.empty()) {
          std::optional<std::size_t> selected;
          if (!function.owner.empty()) {
            auto name = callableName(function.owner + "::" + callee.text,
                                     function.owner, callee.span);
            if (auto found = names.find(name);
                found != names.end() &&
                module.functions[found->second].asynchronous)
              selected = found->second;
          }
          if (!selected) {
            for (std::size_t candidate = 0; candidate < module.functions.size();
                 ++candidate) {
              const auto &method = module.functions[candidate];
              if (!method.asynchronous ||
                  !method.name.ends_with("." + callee.text))
                continue;
              if (selected) {
                selected.reset();
                break;
              }
              selected = candidate;
            }
          }
          if (selected)
            asyncCalls[caller].push_back({*selected, node.span});
        }
      }
      for (const auto &child : node.children)
        collect(*child, awaited);
    };
    const Node *body = function.body.get();
    if (body->kind == Kind::Block && body->children.size() == 1) {
      const auto &future = *body->children[0];
      if (future.kind == Kind::Call && future.children.size() > 1 &&
          future.children[1]->kind == Kind::Closure)
        body = future.children[1]->children[0].get();
    }
    collect(*body, false);
  }
  std::vector<int> asyncIndex(asyncCalls.size(), -1),
      asyncLow(asyncCalls.size());
  std::vector<std::size_t> asyncStack;
  std::vector<bool> asyncActive(asyncCalls.size());
  int nextAsyncIndex = 0;
  std::function<void(std::size_t)> visitAsync = [&](std::size_t caller) {
    asyncIndex[caller] = asyncLow[caller] = nextAsyncIndex++;
    asyncStack.push_back(caller);
    asyncActive[caller] = true;
    for (const auto &call : asyncCalls[caller]) {
      if (asyncIndex[call.target] == -1) {
        visitAsync(call.target);
        asyncLow[caller] = std::min(asyncLow[caller], asyncLow[call.target]);
      } else if (asyncActive[call.target])
        asyncLow[caller] = std::min(asyncLow[caller], asyncIndex[call.target]);
    }
    if (asyncLow[caller] != asyncIndex[caller])
      return;
    std::vector<std::size_t> component;
    while (true) {
      auto member = asyncStack.back();
      asyncStack.pop_back();
      asyncActive[member] = false;
      component.push_back(member);
      if (member == caller)
        break;
    }
    std::vector<bool> inComponent(asyncCalls.size());
    for (auto member : component)
      inComponent[member] = true;
    std::optional<std::pair<std::size_t, AsyncCall>> recursive;
    for (auto member : component)
      for (const auto &call : asyncCalls[member])
        if (inComponent[call.target] &&
            (component.size() > 1 || call.target == member)) {
          recursive = std::make_pair(member, call);
          break;
        }
    if (!recursive)
      return;
    auto [start, firstCall] = *recursive;
    std::vector<std::size_t> cycle{start, firstCall.target};
    std::vector<bool> seen(asyncCalls.size());
    std::function<bool(std::size_t)> findCycle = [&](std::size_t current) {
      if (current == start)
        return true;
      seen[current] = true;
      for (const auto &call : asyncCalls[current]) {
        if (!inComponent[call.target] || seen[call.target])
          continue;
        cycle.push_back(call.target);
        if (findCycle(call.target))
          return true;
        cycle.pop_back();
      }
      return false;
    };
    if (firstCall.target != start)
      findCycle(firstCall.target);
    std::string description;
    for (auto member : cycle) {
      if (!description.empty())
        description += " -> ";
      description += displayPath(module.functions[member].name);
    }
    error("type", firstCall.span,
          "recursive async future cycle " + description +
              " would make the future contain itself");
  };
  for (std::size_t function = 0; function < asyncCalls.size(); ++function)
    if (asyncIndex[function] == -1)
      visitAsync(function);
  if (!diagnostics.empty())
    return std::nullopt;
  bool changed;
  do {
    changed = false;
    for (auto &f : module.functions) {
      if (imported(f.span))
        continue;
      if (!f.body.get())
        continue;
      genericBindings(f);
      if (!f.body.get())
        continue;
      auto value = flow(*f.body, f.owner);
      if (f.annotation.empty() && !facts(f).diverges && !value.normal &&
          !value.returns) {
        facts(f).diverges = true;
        inference.set(functionVariables[&f], Type::Never);
        changed = true;
      }
    }
  } while (changed);
  for (auto &f : module.functions)
    if (f.body.get())
      flow(*f.body, f.owner);

  auto canonicalAsyncDefault = [&](const Function &function,
                                   const interfaces::Definition &definition,
                                   const interfaces::Associated &family,
                                   const Module::Interface &interfaceSyntax,
                                   Type future) {
    auto familySyntax = std::find_if(
        interfaceSyntax.associated.begin(), interfaceSyntax.associated.end(),
        [&](const auto &item) { return item.name == function.asyncFuture; });
    std::vector<TypeBinding> typeBindings;
    const auto &environment = functionGenerics.at(&function);
    auto bindType = [&](const NameKey &name, Type target) {
      auto found = environment.names.find(name);
      if (found != environment.names.end())
        typeBindings.push_back({found->second, target});
    };
    bindType(nameKey("Self", function.lexicalContext), definition.self);
    std::size_t parameter = 0;
    for (const auto &generic : interfaceSyntax.genericParameters)
      if (generic.kind != GenericParameterKind::Region &&
          parameter < definition.parameters.size())
        bindType(nameKey(generic.name, generic.context),
                 definition.parameters[parameter++]);
    parameter = 0;
    if (familySyntax != interfaceSyntax.associated.end())
      for (const auto &generic : familySyntax->genericParameters)
        if (generic.kind != GenericParameterKind::Region &&
            parameter < family.parameters.size())
          bindType(nameKey(generic.name, generic.context),
                   family.parameters[parameter++]);
    future = checked.types->substitute(future, typeBindings);

    std::vector<RegionBinding> regionBindings;
    const auto &functionRegionsValue = functionRegions(function);
    std::size_t region = 0;
    for (const auto &generic : interfaceSyntax.genericParameters)
      if (generic.kind == GenericParameterKind::Region &&
          region < definition.regions.size()) {
        auto found = functionRegionsValue.names.find(
            nameKey(generic.name, generic.context));
        if (found != functionRegionsValue.names.end())
          regionBindings.push_back({found->second, definition.regions[region]});
        ++region;
      }
    region = 0;
    if (familySyntax != interfaceSyntax.associated.end())
      for (const auto &generic : familySyntax->genericParameters)
        if (generic.kind == GenericParameterKind::Region &&
            region < family.regions.size()) {
          auto found = functionRegionsValue.names.find(
              nameKey(generic.name, generic.context));
          if (found != functionRegionsValue.names.end())
            regionBindings.push_back({found->second, family.regions[region]});
          ++region;
        }
    return checked.types->substituteRegions(future, regionBindings);
  };
  auto publishAsyncDefault = [&](const Function &function) {
    if (!function.asyncDefaultFutureInferred)
      return;
    const Node *futureNode = function.body.get();
    if (!futureNode)
      return;
    if (futureNode->kind == Kind::Block && futureNode->children.size() == 1)
      futureNode = futureNode->children[0].get();
    if (futureNode->kind != Kind::Call || futureNode->children.size() < 2 ||
        futureNode->children[1]->kind != Kind::Closure)
      return;
    const auto &closure = *futureNode->children[1];
    if (facts(closure).closure < 0 ||
        static_cast<std::size_t>(facts(closure).closure) >=
            checked.closureBodies.size())
      return;
    auto output =
        checked.closureBodies[facts(closure).closure]->function.abiResult;
    auto defaultFuture =
        inference.value(asyncDefaultBodyVariables.at(&function));
    if (output == Type::Unknown || defaultFuture == Type::Unknown)
      return;
    auto interfaceName =
        typeName(function.interfaceOwner, function.span, function.owner);
    auto interface = interfaceNames.find(interfaceName);
    if (interface == interfaceNames.end())
      return;
    auto &definition = checked.interfaceData->definitions[interface->second];
    auto family =
        std::find_if(definition.associated.begin(), definition.associated.end(),
                     [&](const auto &associated) {
                       return associated.name == function.asyncFuture;
                     });
    if (family == definition.associated.end())
      return;
    auto futureInterface = std::find_if(
        checked.interfaceData->definitions.begin(),
        checked.interfaceData->definitions.end(), [](const auto &candidate) {
          return candidate.name == "core::future::Future";
        });
    if (futureInterface != checked.interfaceData->definitions.end()) {
      const auto declaration = static_cast<std::uint32_t>(
          futureInterface - checked.interfaceData->definitions.begin());
      auto outputItem = std::find_if(
          futureInterface->associated.begin(),
          futureInterface->associated.end(),
          [](const auto &associated) { return associated.name == "Output"; });
      if (outputItem != futureInterface->associated.end())
        for (auto &bound : family->bounds)
          if (bound.property == interfaces::Property::Interface &&
              checked.types->isErased(bound.interfaceType)) {
            auto descriptor = checked.types->erased(bound.interfaceType);
            if (descriptor.declaration != declaration)
              continue;
            auto binding = std::find_if(
                descriptor.associated.begin(), descriptor.associated.end(),
                [&](const auto &associated) {
                  return associated.parameter == outputItem->parameter;
                });
            if (binding == descriptor.associated.end())
              descriptor.associated.push_back({outputItem->parameter, output});
            else
              binding->argument = output;
            bound.interfaceType =
                checked.types->erasedType(std::move(descriptor));
          }
    }
    family->defaultValue = canonicalAsyncDefault(
        function, definition, *family, module.interfaces[interface->second],
        defaultFuture);
  };

  std::vector<std::vector<std::size_t>> edges(module.functions.size());
  for (std::size_t i = 0; i < edges.size(); ++i)
    edges[i] = functionDependencies(module.functions[i]);
  auto futureInterface = std::find_if(
      checked.interfaceData->definitions.begin(),
      checked.interfaceData->definitions.end(), [](const auto &definition) {
        return definition.name == "core::future::Future";
      });
  std::uint32_t futureDeclaration = 0;
  Type outputParameter = Type::Unknown;
  if (futureInterface != checked.interfaceData->definitions.end()) {
    futureDeclaration = static_cast<std::uint32_t>(
        futureInterface - checked.interfaceData->definitions.begin());
    if (auto output = std::find_if(
            futureInterface->associated.begin(),
            futureInterface->associated.end(),
            [](const auto &associated) { return associated.name == "Output"; });
        output != futureInterface->associated.end())
      outputParameter = output->parameter;
  }
  auto bindOutput = [&](Type interfaceType, Type output) {
    if (!checked.types->isErased(interfaceType))
      return interfaceType;
    auto descriptor = checked.types->erased(interfaceType);
    if (descriptor.declaration != futureDeclaration)
      return interfaceType;
    auto binding =
        std::find_if(descriptor.associated.begin(), descriptor.associated.end(),
                     [&](const auto &associated) {
                       return associated.parameter == outputParameter;
                     });
    if (binding == descriptor.associated.end())
      descriptor.associated.push_back({outputParameter, output});
    else
      binding->argument = output;
    return checked.types->erasedType(std::move(descriptor));
  };
  auto updateOpaqueOutput = [&](Type opaque, Type output) {
    if (!checked.types->isOpaque(opaque))
      return;
    auto bounds = checked.types->product(opaque).opaqueBounds;
    bool changed = false;
    for (auto &bound : bounds) {
      auto updated = bindOutput(bound, output);
      changed |= updated != bound;
      bound = updated;
    }
    if (changed)
      checked.types->setOpaqueBounds(opaque, std::move(bounds));
  };
  // The output an async body inferred, once its coroutine closure is complete.
  auto asyncBodyOutput = [&](const Function &function) {
    const Node *future = function.body.get();
    if (future->kind == Kind::Block && future->children.size() == 1)
      future = future->children[0].get();
    if (future->kind != Kind::Call || future->children.size() < 2 ||
        future->children[1]->kind != Kind::Closure)
      return Type::Unknown;
    const auto &closure = *future->children[1];
    if (facts(closure).closure < 0 ||
        static_cast<std::size_t>(facts(closure).closure) >=
            checked.closureBodies.size())
      return Type::Unknown;
    return checked.closureBodies[facts(closure).closure]->function.abiResult;
  };
  // Callers checked later see an inferred async output as soon as it exists.
  auto bindInferredAsyncOutput = [&](const Function &function) {
    if (outputParameter == Type::Unknown || !function.asynchronous ||
        !function.body.get() || !function.asyncOutput.empty())
      return;
    if (auto output = asyncBodyOutput(function); output != Type::Unknown)
      updateOpaqueOutput(facts(function).opaqueResult, output);
  };
  std::vector<int> index(edges.size(), -1), low(edges.size());
  std::vector<std::size_t> stack;
  std::vector<bool> active(edges.size());
  int next = 0;
  std::function<void(std::size_t)> visit = [&](std::size_t v) {
    index[v] = low[v] = next++;
    stack.push_back(v);
    active[v] = true;
    for (auto w : edges[v]) {
      if (index[w] == -1) {
        visit(w);
        low[v] = std::min(low[v], low[w]);
      } else if (active[w])
        low[v] = std::min(low[v], index[w]);
    }
    if (low[v] != index[v])
      return;
    std::vector<std::size_t> component;
    while (true) {
      auto w = stack.back();
      stack.pop_back();
      active[w] = false;
      component.push_back(w);
      if (w == v)
        break;
    }
    for (auto w : component) {
      auto &f = module.functions[w];
      if (!checkedFunctions.contains(&f)) {
        checkingFunctions.insert(&f);
        function(f);
        checkingFunctions.erase(&f);
        checkedFunctions.insert(&f);
      }
    }
    resolveGenericCalls();
    fields();
    for (auto w : component) {
      publishAsyncDefault(module.functions[w]);
      bindInferredAsyncOutput(module.functions[w]);
    }
    for (auto w : component) {
      auto &f = module.functions[w];
      facts(f).result = inference.value(functionVariables[&f]);
      facts(f).abiResult =
          facts(f).error == Type::Unknown
              ? facts(f).result
              : checked.types->structural(AggregateKind::Outcome,
                                          {facts(f).result, facts(f).error});
      if (facts(f).result == Type::Unknown && diagnostics.empty())
        error("type", f.span, "cannot infer recursive result; add ': Type'");
    }
  };
  for (std::size_t i = 0; i < edges.size(); ++i)
    if (index[i] == -1)
      visit(i);
  resolveGenericCalls();

  finishClosures();
  if (outputParameter != Type::Unknown) {
    for (std::size_t i = 0; i < module.functions.size(); ++i) {
      const auto &function = module.functions[i];
      bool outputInferred = function.asyncOutput.empty();
      if (!function.asynchronous || !function.body.get() ||
          (!outputInferred && !function.asyncDefaultFutureInferred))
        continue;
      auto output = asyncBodyOutput(function);
      if (output == Type::Unknown)
        continue;
      if (outputInferred)
        updateOpaqueOutput(facts(function).opaqueResult, output);
      if (function.asyncFuture.empty())
        continue;
      auto interfaceName =
          typeName(function.interfaceOwner, function.span, function.owner);
      auto interface = interfaceNames.find(interfaceName);
      if (interface == interfaceNames.end())
        continue;
      auto &definition = checked.interfaceData->definitions[interface->second];
      auto family = std::find_if(
          definition.associated.begin(), definition.associated.end(),
          [&](const auto &associated) {
            return associated.name == function.asyncFuture;
          });
      if (family == definition.associated.end())
        continue;
      if (outputInferred) {
        for (auto &bound : family->bounds)
          if (bound.property == interfaces::Property::Interface)
            bound.interfaceType = bindOutput(bound.interfaceType, output);
        updateOpaqueOutput(family->defaultValue, output);
      }
      if (function.asyncDefaultFutureInferred) {
        auto defaultFuture =
            inference.value(asyncDefaultBodyVariables.at(&function));
        if (defaultFuture == Type::Unknown) {
          error("type", function.span,
                "cannot infer async interface default future");
          continue;
        }
        defaultFuture = canonicalAsyncDefault(
            function, definition, *family, module.interfaces[interface->second],
            defaultFuture);
        family->defaultValue = defaultFuture;
        if (checked.types->isSized(family->parameter) &&
            !checked.types->isSized(defaultFuture))
          error("type", function.span,
                "async interface default future does not satisfy Sized");
      }
    }
  }
  for (auto &implementation : checked.interfaceData->implementations) {
    if (!checked.types->isErased(implementation.interfaceType))
      continue;
    const auto descriptor = checked.types->erased(implementation.interfaceType);
    if (descriptor.declaration >= checked.interfaceData->definitions.size())
      continue;
    const auto &definition =
        checked.interfaceData->definitions[descriptor.declaration];
    std::vector<TypeBinding> substitutions{
        {definition.self, implementation.target}};
    for (std::size_t p = 0;
         p < descriptor.arguments.size() && p < definition.parameters.size();
         ++p)
      substitutions.push_back(
          {definition.parameters[p], descriptor.arguments[p]});
    for (auto &[ordinal, value] : implementation.associated) {
      if (!value.fromDefault || ordinal >= definition.associated.size())
        continue;
      const auto &associated = definition.associated[ordinal];
      if (associated.defaultValue == Type::Unknown)
        continue;
      value.value =
          checked.types->substitute(associated.defaultValue, substitutions);
      if (checked.types->isSized(associated.parameter) &&
          !checked.types->isSized(value.value))
        error("type", implementation.span,
              "associated default type does not satisfy Sized");
      if (checked.types->isCopy(associated.parameter) &&
          !checked.types->isCopy(value.value))
        error("type", implementation.span,
              "associated default type does not satisfy Copy");
      if (checked.types->isUnpin(associated.parameter) &&
          !unpinObligation(value.value, implementation.span))
        error("type", implementation.span,
              "associated default type does not satisfy Unpin");
    }
  }
  for (const auto &function : module.functions)
    if (function.asyncDefaultFutureInferred) {
      auto body = inference.value(asyncDefaultBodyVariables.at(&function));
      if (body != Type::Unknown)
        facts(function).asyncDefaultBodyResult = body;
    }
  for (auto [variable, span] : integerOrBoolean) {
    auto t = inference.value(variable);
    if (t != Type::Bool && !isInteger(t) && t != Type::Never)
      error("type", span, "operation requires a resolved bool or integer type");
  }
  for (const auto &operation : numericOperations) {
    auto type = inference.value(operation.variable);
    bool valid = operation.operation == "arithmetic" ? isNumeric(type)
                 : operation.operation == "negate"
                     ? isSignedInteger(type) || isFloating(type)
                     : isInteger(type);
    if (!valid && type != Type::Never)
      error("type", operation.span,
            "operator is not available for this scalar type");
  }
  for (auto [variable, span] : comparisons)
    if (checked.types->isView(inference.value(variable)))
      error("type", span,
            "view comparisons require explicitly comparing the referenced "
            "values");
    else if (checked.types->isProduct(inference.value(variable)))
      error("type", span,
            "product comparisons require a declared comparison interface");
  for (auto &f : module.functions) {
    if (imported(f.span))
      continue;
    facts(f).result = inference.value(functionVariables[&f]);
    std::function<void(Node &)> resolve = [&](Node &n) {
      if (n.kind != Kind::Closure) {
        if (auto plan = checked.iterations.find(&n);
            plan != checked.iterations.end())
          resolve(*plan->second.elaboration);
        for (auto &child : n.children)
          resolve(*child);
      }
      if (nodeVariables.contains(&n))
        facts(n).type = inference.value(nodeVariables[&n]);
      if (facts(n).rebuiltType != Type::Unknown)
        facts(n).type = facts(n).rebuiltType;
      if (n.kind == Kind::Name && facts(n).slot >= 0) {
        facts(n).place = Place{facts(n).slot, {}};
        if (facts(f).locals[facts(n).slot].patternView)
          facts(n).place->fields.push_back(Projection::dereference());
      } else if (n.kind == Kind::Group) {
        const auto &child = facts(*n.children[0]);
        if (facts(n).rebuiltType != Type::Unknown || child.viewConversion ||
            child.rebuiltType != Type::Unknown || !child.injections.empty())
          facts(n).place.reset();
        else
          facts(n).place = child.place;
      } else if (n.kind == Kind::Unary && n.text == "*" &&
                 facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        facts(n).place->fields.push_back(Projection::dereference());
      } else if ((n.kind == Kind::Field || n.kind == Kind::Index) &&
                 !facts(n).optional && facts(n).field >= 0 &&
                 facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        for (unsigned i = 0; i < facts(n).dereferences; ++i)
          facts(n).place->fields.push_back(Projection::dereference());
        facts(n).place->fields.push_back(
            Projection::field(static_cast<std::uint32_t>(facts(n).field)));
      }
    };
    if (f.body.get())
      if (f.body.get())
        resolve(*f.body);
    for (auto &parameter : f.parameters)
      if (parameter.defaultValue.get())
        resolve(*parameter.defaultValue);
    std::optional<std::set<int>> poisonedRoots;
    auto poisoned = [&](std::size_t local) {
      if (!poisonedRoots) {
        poisonedRoots.emplace();
        for (auto variable : poisonedVariables)
          poisonedRoots->insert(inference.representative(variable));
      }
      return inference.depends(localVariables[&f][local], *poisonedRoots);
    };
    for (std::size_t i = 0; i < facts(f).locals.size(); ++i) {
      facts(f).locals[i].type = inference.value(localVariables[&f][i]);
      // A parameter's annotation is mandatory, so its failure is already
      // reported.
      if (facts(f).locals[i].type == Type::Unknown &&
          i >= f.parameters.size() && !poisoned(i))
        error("type", facts(f).locals[i].span,
              "cannot infer local type; add ': Type'");
      if (facts(f).locals[i].patternView) {
        facts(f).locals[i].type = checked.types->viewType(
            facts(f).locals[i].type, facts(f).locals[i].mode);
        facts(f).locals[i].mode = ParameterMode::Value;
      }
    }
    auto resultParameters = checked.types->typeParameters(facts(f).abiResult);
    std::map<Type, std::set<Type>> associatedCarriers;
    for (const auto &[subject, bound] : facts(f).interfaceBounds) {
      if (!checked.types->isErased(bound))
        continue;
      auto subjects = checked.types->typeParameters(subject);
      for (const auto &binding : checked.types->erased(bound).associated)
        for (auto parameter : checked.types->typeParameters(binding.argument))
          for (auto carrier : subjects)
            if (checked.types->isParameter(carrier))
              associatedCarriers[parameter].insert(carrier);
    }
    // Associated results carry views through their implementing input, too.
    std::set<Type> carriers(resultParameters.begin(), resultParameters.end());
    for (std::size_t p = 0; p < resultParameters.size(); ++p)
      if (auto found = associatedCarriers.find(resultParameters[p]);
          found != associatedCarriers.end())
        for (auto carrier : found->second)
          if (carriers.insert(carrier).second)
            resultParameters.push_back(carrier);
    for (std::size_t p = 0;
         p < f.parameters.size() && p < facts(f).locals.size(); ++p) {
      auto parameters = checked.types->typeParameters(facts(f).locals[p].type);
      bool transported = false;
      for (auto parameter : parameters)
        if (checked.types->isParameter(parameter) &&
            carriers.contains(parameter))
          transported = true;
      if (transported)
        facts(f).genericResultSources.push_back(p);
    }
  }
  resolvePatterns();
  if (diagnostics.empty())
    staticInitializers();
  std::map<Type, bool> varArgs;
  auto holdsVarArgs = [&](Type type) {
    auto [entry, inserted] = varArgs.try_emplace(type, false);
    if (inserted)
      entry->second = containsVarArgs(*checked.types, type);
    return entry->second;
  };
  for (const auto &[syntax, resolved] : checked.nodes) {
    if (resolved.opaqueSource != Type::Unknown &&
        !checked.types->isSized(resolved.opaqueSource))
      error("type", syntax->span,
            "opaque hidden type does not satisfy its Sized contract");
    if (syntax->kind == Kind::Array && syntax->flag &&
        (resolved.constantCount != Type::Unknown || resolved.number > 1)) {
      auto element = nodeVariables.find(syntax->children[0].get());
      if (element != nodeVariables.end()) {
        auto type = inference.value(element->second);
        if (type != Type::Unknown && !checked.types->isCopy(type))
          error("ownership", syntax->span,
                "array repetition requires Copy elements");
      }
    }
    if (holdsVarArgs(resolved.type) && !checked.types->isView(resolved.type) &&
        !(checked.types->isProduct(resolved.type) &&
          checked.types->product(resolved.type).kind == AggregateKind::VarArgs))
      error(
          "ownership", syntax->span,
          "a variadic cursor cannot escape into aggregate or closure storage");
    if (syntax->kind == Kind::Call && resolved.machineOperation.empty())
      for (std::size_t i = 1; i < syntax->children.size(); ++i)
        if (auto argument = checked.nodes.find(syntax->children[i].get());
            argument != checked.nodes.end() &&
            holdsVarArgs(argument->second.type))
          error("ownership", syntax->children[i]->span,
                "a variadic cursor cannot be passed outside its invocation");
    if (syntax->kind == Kind::Integer && resolved.numeric &&
        !integerLiteralFits(*resolved.numeric, resolved.type, pointerBits()))
      error("type", syntax->span,
            "integer literal is outside the " +
                displayType(*checked.types, resolved.type) + " range");
    if (syntax->kind == Kind::Cast) {
      auto source = checked.nodes.at(syntax->children[0].get()).type;
      if (source != Type::Never &&
          (source == Type::Unknown
               ? diagnostics.empty()
               : !machineCastAllowed(*checked.types, source, resolved.type)))
        error("type", syntax->span, "invalid scalar conversion");
    }
  }
  for (const auto &function : module.functions)
    if (holdsVarArgs(facts(function).result))
      error("ownership", function.span,
            "a variadic cursor cannot escape its invocation");
  if (diagnostics.empty())
    checkBorrowAlignment();
  if (diagnostics.empty())
    checkInterfaceContracts();
  if (diagnostics.empty())
    checkRegions();
  if (!diagnostics.empty())
    return std::nullopt;
  machineDeclarations();
  finishAssembly();
  if (!diagnostics.empty())
    return std::nullopt;
  finalizeInterfaces();
  exhaustiveness();
  module.functions.resize(sourceFunctionCount);
  checked.functions.resize(sourceFunctionCount);
  retainDeclarations();
  if (!requireEntry)
    return diagnostics.empty()
               ? std::optional<CheckedModule>(std::move(checked))
               : std::nullopt;
  auto main = names.find("main");
  if (main == names.end())
    error("name", {}, "missing entry function 'main'");
  else {
    auto &f = module.functions[main->second];
    if (!facts(f).targetFeatures.empty() &&
        !featuresAvailable(checked.targetDescription, {},
                           facts(f).targetFeatures))
      error("feature", f.span,
            "hosted entry requires baseline target feature availability");
    if (!f.parameters.empty() || facts(f).result != Type::I32)
      error("type", f.span,
            "entry function must have no parameters and return i32");
    if (facts(f).error != Type::Unknown)
      error("effects", f.span,
            "entry function cannot expose an unhandled typed failure");
  }
  if (!diagnostics.empty())
    return std::nullopt;
  return std::move(checked);
}
std::optional<CheckedModule> check(Module module, Diagnostics &diagnostics,
                                   bool requireEntry, TargetFacts target,
                                   NumericEvaluator numericEvaluator) {
  if (!diagnostics.empty())
    return std::nullopt;
  auto symbols = resolution::resolve(module, diagnostics);
  return check(std::move(module), diagnostics, std::move(symbols), requireEntry,
               std::move(target), numericEvaluator);
}
std::optional<CheckedModule>
check(Module module, Diagnostics &diagnostics,
      std::shared_ptr<const resolution::Resolution> symbols, bool requireEntry,
      TargetFacts target, NumericEvaluator numericEvaluator,
      std::shared_ptr<const ImportedDeclarations> imported) {
  if (!diagnostics.empty() || !symbols)
    return std::nullopt;
  try {
    return Checker(std::move(module), diagnostics, std::move(symbols),
                   requireEntry, std::move(target), numericEvaluator,
                   std::move(imported))
        .run();
  } catch (const std::length_error &failure) {
    diagnostics.error("limit", {}, failure.what());
    return std::nullopt;
  }
}

} // namespace mettle
