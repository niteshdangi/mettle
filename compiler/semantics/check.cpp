#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include "types/machine.h"
#include <algorithm>
#include <functional>
#include <map>
#include <stdexcept>

namespace mettle {
void Checker::error(std::string phase, Span span, std::string message) {
  if (phase == "type" && std::any_of(staticStates.begin(), staticStates.end(),
                                     [](auto state) { return state == 1; }))
    phase = "constant";
  ++reportedErrors;
  diagnostics.error(std::move(phase), span, std::move(message));
}

std::optional<CheckedModule> Checker::run() {
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
  checked.functions.resize(module.functions.size());
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &f = module.functions[i];
    current = &f;
    facts(f).genericParameters = genericBindings(f);
    auto name = definitionName(f.span, f.name);
    facts(f).canonicalName =
        f.constructor ? name + "$init" + std::to_string(i) : name;
    auto [existing, inserted] = names.emplace(name, i);
    if (!inserted &&
        !(f.constructor && module.functions[existing->second].constructor))
      error("name", f.span, "duplicate function '" + displayPath(f.name) + "'");
    if (auto type = typeNames.find(name);
        type != typeNames.end() && checked.types->isProduct(type->second) &&
        !checked.types->isSum(type->second))
      error("name", f.span,
            "function conflicts with type constructor '" + displayPath(f.name) +
                "'");
    functionVariables[&f] =
        inference.fresh(annotation(f.annotation, f.span, f.owner));
    facts(f).diverges = inference.value(functionVariables[&f]) == Type::Never;
    if (f.explicitReceiver) {
      if (f.owner.empty() && f.implementation < 0)
        error("signature", f.span,
              "explicit receiver requires an owning type or interface");
      else {
        auto self =
            annotation(f.parameters.front().annotation, f.span, f.owner);
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
    if (f.destructor)
      checked.types->setDestructor(typeNames.at(typeName(f.owner, f.span)),
                                   static_cast<int>(i));
    if (f.body.get())
      if (f.body.get())
        controlFlow(f);
  }
  targetDeclarations();
  staticNamesAndTypes();
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
    std::function<void(const Node &, bool)>
        collect = [&](const Node &node, bool awaited) {
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
              auto name =
                  callableName(callee.text, function.owner, callee.span);
              if (auto found = names.find(name); found != names.end() &&
                  module.functions[found->second].asynchronous)
                asyncCalls[caller].push_back({found->second, node.span});
            } else if (callee.kind == Kind::Field &&
                       !callee.children.empty()) {
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
                for (std::size_t candidate = 0;
                     candidate < module.functions.size(); ++candidate) {
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
        asyncLow[caller] =
            std::min(asyncLow[caller], asyncIndex[call.target]);
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

  std::vector<std::vector<std::size_t>> edges(module.functions.size());
  std::function<void(Node &, std::vector<std::size_t> &, std::string_view)>
      calls = [&](Node &n, std::vector<std::size_t> &out,
                  std::string_view owner) {
        if (n.kind == Kind::Name && !facts(n).lexicallyBound) {
          auto found = names.find(callableName(n.text, owner, n.span));
          if (found != names.end())
            out.push_back(found->second);
        } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name &&
                   !facts(*n.children[0]).lexicallyBound) {
          auto called = callableName(n.children[0]->text, owner, n.span);
          auto found = names.find(called);
          if (found != names.end())
            out.push_back(found->second);
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
                out.push_back(candidate.function);
          }
        } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Field) {
          for (std::size_t i = 0; i < module.functions.size(); ++i)
            if (module.functions[i].name.ends_with("." + n.children[0]->text))
              out.push_back(i);
        }
        if (auto plan = checked.iterations.find(&n);
            plan != checked.iterations.end())
          calls(*plan->second.elaboration, out, owner);
        for (auto &child : n.children)
          calls(*child, out, owner);
      };
  for (std::size_t i = 0; i < edges.size(); ++i) {
    if (module.functions[i].body.get())
      if (module.functions[i].body.get())
        calls(*module.functions[i].body, edges[i], module.functions[i].owner);
    for (auto &parameter : module.functions[i].parameters)
      if (parameter.defaultValue.get())
        calls(*parameter.defaultValue, edges[i], module.functions[i].owner);
  }
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
    for (auto w : component)
      function(module.functions[w]);
    resolveGenericCalls();
    fields();
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
  auto futureInterface = std::find_if(
      checked.interfaceData->definitions.begin(),
      checked.interfaceData->definitions.end(), [](const auto &definition) {
        return definition.name == "core::future::Future";
      });
  if (futureInterface != checked.interfaceData->definitions.end()) {
    const auto futureDeclaration = static_cast<std::uint32_t>(
        futureInterface - checked.interfaceData->definitions.begin());
    auto outputItem = std::find_if(
        futureInterface->associated.begin(), futureInterface->associated.end(),
        [](const auto &associated) { return associated.name == "Output"; });
    if (outputItem != futureInterface->associated.end()) {
      auto bindOutput = [&](Type interfaceType, Type output) {
        if (!checked.types->isErased(interfaceType))
          return interfaceType;
        auto descriptor = checked.types->erased(interfaceType);
        if (descriptor.declaration != futureDeclaration)
          return interfaceType;
        auto binding = std::find_if(
            descriptor.associated.begin(), descriptor.associated.end(),
            [&](const auto &associated) {
              return associated.parameter == outputItem->parameter;
            });
        if (binding == descriptor.associated.end())
          descriptor.associated.push_back({outputItem->parameter, output});
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
      for (std::size_t i = 0; i < module.functions.size(); ++i) {
        const auto &function = module.functions[i];
        if (!function.asynchronous || !function.asyncOutput.empty() ||
            !function.body.get())
          continue;
        const Node *future = function.body.get();
        if (future->kind == Kind::Block && future->children.size() == 1)
          future = future->children[0].get();
        if (future->kind != Kind::Call || future->children.size() < 2 ||
            future->children[1]->kind != Kind::Closure)
          continue;
        const auto &closure = *future->children[1];
        if (facts(closure).closure < 0 ||
            static_cast<std::size_t>(facts(closure).closure) >=
                checked.closureBodies.size())
          continue;
        auto output =
            checked.closureBodies[facts(closure).closure]->function.abiResult;
        if (output == Type::Unknown)
          continue;
        updateOpaqueOutput(facts(function).opaqueResult, output);
        if (function.asyncFuture.empty())
          continue;
        auto interfaceName =
            typeName(function.interfaceOwner, function.span, function.owner);
        auto interface = interfaceNames.find(interfaceName);
        if (interface == interfaceNames.end())
          continue;
        auto &definition =
            checked.interfaceData->definitions[interface->second];
        auto family = std::find_if(
            definition.associated.begin(), definition.associated.end(),
            [&](const auto &associated) {
              return associated.name == function.asyncFuture;
            });
        if (family == definition.associated.end())
          continue;
        for (auto &bound : family->bounds)
          if (bound.property == interfaces::Property::Interface) {
            auto updated = bindOutput(bound.interfaceType, output);
            bound.interfaceType = updated;
          }
        updateOpaqueOutput(family->defaultValue, output);
      }
    }
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
    for (std::size_t p = 0;
         p < f.parameters.size() && p < facts(f).locals.size(); ++p) {
      auto parameters = checked.types->typeParameters(facts(f).locals[p].type);
      bool transported = false;
      for (auto parameter : parameters)
        if (checked.types->isParameter(parameter) &&
            std::find(resultParameters.begin(), resultParameters.end(),
                      parameter) != resultParameters.end())
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
                displayPath(checked.types->name(resolved.type)) + " range");
    if (syntax->kind == Kind::Cast) {
      auto source = checked.nodes.at(syntax->children[0].get()).type;
      if (source != Type::Never && source != Type::Unknown &&
          !machineCastAllowed(*checked.types, source, resolved.type))
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
                                   bool requireEntry, TargetFacts target) {
  if (!diagnostics.empty())
    return std::nullopt;
  auto symbols = resolution::resolve(module, diagnostics);
  return check(std::move(module), diagnostics, std::move(symbols), requireEntry,
               std::move(target));
}
std::optional<CheckedModule>
check(Module module, Diagnostics &diagnostics,
      std::shared_ptr<const resolution::Resolution> symbols, bool requireEntry,
      TargetFacts target) {
  if (!diagnostics.empty() || !symbols)
    return std::nullopt;
  try {
    return Checker(std::move(module), diagnostics, std::move(symbols),
                   requireEntry, std::move(target))
        .run();
  } catch (const std::length_error &failure) {
    diagnostics.error("limit", {}, failure.what());
    return std::nullopt;
  }
}

} // namespace mettle
