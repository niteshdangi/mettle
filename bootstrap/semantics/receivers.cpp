#include "semantics/checker.h"
#include "support/limits.h"
#include "types/machine.h"
#include <algorithm>
#include <map>
#include <set>
#include <tuple>

namespace mettle {
namespace {
ParameterMode receiverMode(const Function &function) {
  return function.receiver == "mut"    ? ParameterMode::Mut
         : function.receiver == "take" ? ParameterMode::Take
                                       : ParameterMode::Read;
}
} // namespace
const Checker::ReceiverImplementationCandidates &
Checker::receiverCandidates(std::string_view name, bool includeInterfaces) {
  const auto &database = std::as_const(*checked.interfaceData);
  const auto &implementations = database.implementations;
  while (indexedReceiverImplementations < implementations.size()) {
    auto index = indexedReceiverImplementations++;
    const auto &implementation = implementations[index];
    if (implementation.interfaceType != Type::Unknown)
      continue;
    for (const auto &[method, entry] : implementation.inherent)
      receiverImplementationCandidates[method].inherent.push_back(index);
  }
  if (includeInterfaces) {
    if (!database.argumentsReady || !receiverInterfacesReady) {
      receiverInterfaceChildren.clear();
      indexedReceiverDefinitions = 0;
      for (auto &[method, indexed] : receiverImplementationCandidates) {
        indexed.declarations.clear();
        indexed.interfaces.clear();
        indexed.interfacesIndexed = 0;
        indexed.definitionsIndexed = 0;
      }
      receiverInterfacesReady = database.argumentsReady;
    }
    receiverInterfaceChildren.resize(database.definitions.size());
    while (indexedReceiverDefinitions < database.definitions.size()) {
      auto index = indexedReceiverDefinitions++;
      const auto &definition = database.definitions[index];
      for (const auto &method : definition.methods)
        receiverImplementationCandidates[method.name].declarations.push_back(
            index);
      for (const auto &parent : definition.superinterfaces)
        if (parent.property == interfaces::Property::Interface &&
            checked.types->isErased(parent.interfaceType))
          receiverInterfaceChildren[checked.types->erasedDeclaration(
                                        parent.interfaceType)]
              .push_back(index);
    }
  }
  auto found = receiverImplementationCandidates.find(name);
  if (found == receiverImplementationCandidates.end())
    found =
        receiverImplementationCandidates.try_emplace(std::string(name)).first;
  auto &candidates = found->second;
  if (includeInterfaces &&
      (candidates.interfacesIndexed != implementations.size() ||
       candidates.definitionsIndexed != database.definitions.size())) {
    std::vector<std::size_t> declaring;
    std::unordered_set<std::size_t> visited;
    for (auto declaration : candidates.declarations)
      if (visited.insert(declaration).second)
        declaring.push_back(declaration);
    for (std::size_t next = 0; next < declaring.size(); ++next)
      for (auto child : receiverInterfaceChildren[declaring[next]])
        if (visited.insert(child).second)
          declaring.push_back(child);
    candidates.interfaces.clear();
    for (auto declaration : declaring) {
      const auto &selected =
          database.implementationsFor(*checked.types, declaration);
      candidates.interfaces.insert(candidates.interfaces.end(),
                                   selected.begin(), selected.end());
    }
    std::sort(candidates.interfaces.begin(), candidates.interfaces.end());
    candidates.interfacesIndexed = implementations.size();
    candidates.definitionsIndexed = database.definitions.size();
  }
  return candidates;
}
static bool builtinPinMethod(std::string_view name) {
  static const std::set<std::string_view> methods{"as_ref",
                                                  "as_mut",
                                                  "get_ref",
                                                  "get_mut",
                                                  "get_unchecked_mut",
                                                  "into_inner",
                                                  "into_inner_unchecked"};
  return methods.contains(name);
}
std::optional<std::size_t> Checker::receiverCandidate(
    Type receiver, ParameterMode mode, std::string_view name, const Node &call,
    const std::function<const std::vector<Type> *()> &arguments,
    bool viewExtension) {
  std::vector<std::size_t> inherent;
  std::map<std::size_t, std::vector<Type>> inherentArguments;
  // Compiler-generated iteration calls name their protocol interface in
  // call.text and bypass inherent methods and import visibility.
  const bool protocol = call.kind == Kind::Call && !call.text.empty();
  auto self = receiver;
  bool pinned = !pinAsOwner && checked.types->isProduct(receiver) &&
                checked.types->product(receiver).kind == AggregateKind::Pin;
  // A pin's own methods (`extend pinned read T`) precede its target's;
  // its builtin methods precede both.
  if (pinned && !builtinPinMethod(name) && !name.starts_with("project_")) {
    pinAsOwner = true;
    auto own =
        receiverCandidate(receiver, mode, name, call, arguments, viewExtension);
    pinAsOwner = false;
    if (own)
      return own;
  }
  if (pinned)
    self = checked.types->view(checked.types->product(receiver).components[0])
               .payload;
  const std::string methodName(name);
  const auto &indexed = receiverCandidates(name, false);
  auto accepts = [&](std::size_t index) {
    const auto &function = module.functions[index];
    bool expectsPinned =
        function.explicitReceiver &&
        function.parameters[0].annotation.form == TypeForm::Pinned;
    return function.receiver != "static" && receiverMode(function) == mode &&
           pinned == expectsPinned;
  };
  if (!protocol && checked.types->isProduct(self)) {
    const auto &record = checked.types->product(self);
    auto owner = record.genericOrigin == Type::Unknown
                     ? record.name
                     : checked.types->product(record.genericOrigin).name;
    if (auto found = names.find(owner + "." + methodName);
        found != names.end() && accepts(found->second))
      inherent.push_back(found->second);
  }
  std::optional<interfaces::Solver> solver;
  auto query = [&]() -> interfaces::Solver & {
    if (!solver) {
      solver.emplace(*checked.types, *checked.interfaceData, diagnostics,
                     interfaceAssumptions(), regionEnvironment());
      solver->setCallableProof([&](Type parameter, Type actual,
                                   const std::vector<TypeBinding> &bindings,
                                   std::span<const RegionBinding>, Span span) {
        auto expected = solver->normalize(
            checked.types->substitute(
                checked.types->parameter(parameter).erasedCallableConstraint,
                bindings),
            {}, span);
        actual = solver->normalize(actual, {}, span);
        if (!checked.types->isCallable(actual))
          return false;
        return checked.types->satisfiesCallable(
            checked.types->eraseRegions(
                checked.types->callableType(checked.types->callable(actual))),
            checked.types->eraseRegions(expected));
      });
    }
    return *solver;
  };
  for (std::size_t position = 0, count = indexed.inherent.size();
       position < count; ++position) {
    auto implIndex = indexed.inherent[position];
    const auto &implementation =
        std::as_const(*checked.interfaceData).implementations[implIndex];
    if (protocol ||
        (viewExtension && !checked.types->isView(implementation.target)))
      continue;
    auto selected = implementation.inherent.find(methodName);
    if (selected == implementation.inherent.end() ||
        !accepts(static_cast<std::size_t>(selected->second.function)))
      continue;
    auto bindings = query().applicable(implementation, self, call.span);
    if (!bindings)
      continue;
    auto index = static_cast<std::size_t>(selected->second.function);
    inherent.push_back(index);
    for (auto parameter : selected->second.arguments)
      inherentArguments[index].push_back(
          query().normalize(parameter, *bindings, call.span));
  }
  std::sort(inherent.begin(), inherent.end());
  inherent.erase(std::unique(inherent.begin(), inherent.end()), inherent.end());
  if (inherent.size() > 1) {
    error("type", call.span, "ambiguous inherent receiver method");
    return std::nullopt;
  }
  if (!inherent.empty()) {
    facts(call).interfaceSelf = self;
    if (auto found = inherentArguments.find(inherent[0]);
        found != inherentArguments.end())
      facts(call).implementationArguments = found->second;
    return inherent[0];
  }
  if (viewExtension)
    return std::nullopt;
  std::vector<std::tuple<std::size_t, Type, int>> candidates;
  std::set<std::uint32_t> suppliedByBounds;
  auto consider = [&](Type bound) {
    if (!checked.types->isErased(bound))
      return;
    for (auto inherited :
         interfaces::hierarchy(*checked.types, *checked.interfaceData, self,
                               bound, call.span, diagnostics)) {
      const auto &descriptor = checked.types->erased(inherited);
      if (suppliedByBounds.contains(descriptor.declaration))
        continue;
      const auto &definition =
          checked.interfaceData->definitions[descriptor.declaration];
      if (protocol && definition.name != call.text)
        continue;
      for (std::size_t method = 0; method < definition.methods.size();
           ++method) {
        const auto &entry = definition.methods[method];
        if (entry.name != name ||
            !accepts(static_cast<std::size_t>(entry.function)))
          continue;
        const auto &source = module.functions[entry.function];
        if (checked.types->isErased(self) && source.asynchronous) {
          auto companion =
              std::find_if(definition.methods.begin(), definition.methods.end(),
                           [&](const auto &other) {
                             return other.name == erasedAsyncName(name);
                           });
          if (companion == definition.methods.end()) {
            error("type", call.span,
                  "async method '" + std::string(name) +
                      "' is not available through '" +
                      displayType(*checked.types, self) +
                      "'; declare it `async(heap)` to return a pinned heap "
                      "future");
            continue;
          }
          candidates.emplace_back(
              companion->function, inherited,
              static_cast<int>(companion - definition.methods.begin()));
          continue;
        }
        candidates.emplace_back(entry.function, inherited,
                                static_cast<int>(method));
      }
    }
  };
  if (checked.types->isErased(self))
    consider(self);
  else if (checked.types->isProjection(self)) {
    for (const auto &bound : query().projectionBounds(self, call.span))
      if (bound.property == interfaces::Property::Interface)
        consider(bound.interfaceType);
    for (const auto &bound : interfaceAssumptions())
      if (bound.subject == self &&
          bound.property == interfaces::Property::Interface)
        consider(bound.interfaceType);
  } else if (checked.types->isOpaque(self))
    for (auto bound : checked.types->product(self).opaqueBounds)
      consider(bound);
  else if (genericEnvironment && genericEnvironment->bounds.contains(self)) {
    for (const auto &bound : genericEnvironment->bounds.at(self))
      if (bound.form != TypeForm::Callable && bound.name != "unsized" &&
          !propertyBound(bound, call.span))
        consider(interfaceBound(bound, call.span, {}, self));
  }
  // A where-clause bound shadows blanket implementations of its own interface
  // (`T: AsMut<P>` versus `AsMut<T> for T`); other interfaces stay candidates.
  if (checked.types->isParameter(self))
    for (const auto &candidate : candidates)
      suppliedByBounds.insert(
          checked.types->erased(std::get<1>(candidate)).declaration);
  if (!checked.types->isErased(self)) {
    auto caller = accessModule(call);
    auto visible = [&](const interfaces::Definition &definition) {
      if (protocol)
        return true;
      if (!checked.symbols->accessible(definition.span, caller))
        return false;
      if (checked.symbols->moduleOf(definition.span) == caller)
        return true;
      // Interfaces of the receiver type's own package are candidates; a
      // builtin type has no package, so the compiled package's interfaces are.
      // (Not while the library itself is built: its packages share one id.)
      if (!imported(definition.span) && checked.types->isProduct(self)) {
        const auto &record = checked.types->product(self);
        if (record.kind == AggregateKind::Optional ||
            record.kind == AggregateKind::Outcome)
          return true;
        const auto &origin = record.genericOrigin == Type::Unknown
                                 ? record
                                 : checked.types->product(record.genericOrigin);
        auto modulePath = [](std::string_view name) {
          auto separator = name.rfind("::");
          return separator == std::string_view::npos
                     ? std::string_view{}
                     : name.substr(0, separator);
        };
        // Declared at or below the receiver type's own module.
        const auto owner = modulePath(origin.name);
        const auto declared = modulePath(definition.name);
        if ((record.kind == AggregateKind::Product ||
             record.kind == AggregateKind::Enumeration) &&
            declared.starts_with(owner) &&
            (declared.size() == owner.size() || owner.empty() ||
             declared.substr(owner.size()).starts_with("::")))
          return true;
      }
      auto separator = definition.name.rfind("::");
      auto shortName = definition.name.substr(
          separator == std::string::npos ? 0 : separator + 2);
      auto resolves = [&](std::string_view spelling) {
        auto found = checked.symbols->lookup(
            caller, spelling, resolution::Namespace::Type, call.span);
        return found && *found == definition.name;
      };
      if (resolves(shortName))
        return true;
      for (const auto &import : module.imports) {
        if (checked.symbols->moduleOf(import.span) != caller)
          continue;
        if (!import.alias.empty() && resolves(import.alias))
          return true;
        for (const auto &entry : import.names)
          if (resolves(entry.alias.empty() ? entry.name : entry.alias))
            return true;
      }
      return false;
    };
    // The nominal head a concrete type must share with an implementation
    // target for them to match; Unknown when either side is still generic.
    auto head = [&](Type type) {
      const auto &types = *checked.types;
      if (types.isProduct(type)) {
        while (types.product(type).regionOrigin != Type::Unknown)
          type = types.product(type).regionOrigin;
        if (types.product(type).genericOrigin != Type::Unknown)
          type = types.product(type).genericOrigin;
        // Built-in aggregates are structural, so only declared types compare.
        const auto kind = types.product(type).kind;
        return kind == AggregateKind::Product ||
                       kind == AggregateKind::Enumeration
                   ? type
                   : Type::Unknown;
      }
      return types.isParameter(type) || types.isProjection(type) ||
                     types.isView(type) || types.isPointer(type) ||
                     types.isSlice(type) || types.isErased(type) ||
                     types.isFunctionPointer(type) || type == Type::Unknown
                 ? Type::Unknown
                 : type;
    };
    const auto selfHead = head(self);
    std::set<std::uint32_t> inferredConversions;
    std::map<std::uint32_t, bool> visibility;
    const auto &interfaceCandidates = receiverCandidates(name, true).interfaces;
    for (std::size_t position = 0, count = interfaceCandidates.size();
         position < count; ++position) {
      auto index = interfaceCandidates[position];
      const auto &implementation =
          std::as_const(*checked.interfaceData).implementations[index];
      const auto declaration =
          checked.types->erased(implementation.interfaceType).declaration;
      const auto &definition = checked.interfaceData->definitions[declaration];
      auto [cachedVisibility, inserted] = visibility.try_emplace(declaration);
      if (inserted)
        cachedVisibility->second = visible(definition);
      if (!cachedVisibility->second)
        continue;
      std::vector<RegionBinding> regions;
      const auto targetHead = head(implementation.target);
      auto bindings =
          selfHead != Type::Unknown && targetHead != Type::Unknown &&
                  selfHead != targetHead
              ? std::nullopt
              : query().applicable(implementation, self, call.span, &regions,
                                   false,
                                   arguments && call.children.size() > 1);
      if (bindings) {
        auto bound = checked.types->substituteRegions(
            checked.types->substitute(implementation.interfaceType, *bindings),
            regions);
        auto parameters = checked.types->typeParameters(bound);
        // A region-only argument (`PartialEq<read CStr from r>`) still fixes
        // the argument type the call must supply.
        bool needsArguments =
            (checked.types->isErased(bound) &&
             !checked.types->erased(bound).arguments.empty()) ||
            std::any_of(implementation.parameters.begin(),
                        implementation.parameters.end(), [&](Type parameter) {
                          return std::find(parameters.begin(), parameters.end(),
                                           parameter) != parameters.end();
                        });
        if (needsArguments && arguments) {
          if (const auto *types = arguments()) {
            auto method = std::find_if(
                definition.methods.begin(), definition.methods.end(),
                [&](const auto &method) {
                  return method.name == name &&
                         accepts(static_cast<std::size_t>(method.function));
                });
            if (method != definition.methods.end()) {
              auto candidateRegions = regionEnvironment();
              bool fit =
                  argumentsFit(static_cast<std::size_t>(method->function),
                               bound, self, *types, call.span, candidateRegions,
                               implementation.parameters);
              if (!fit)
                continue;
            }
          }
        }
        if (query().prove({self, bound}, call.span, false)) {
          consider(bound);
          continue;
        }
      }
      // A conversion whose interface parameter is only the method's result
      // (Into<U>.into(): U, TryInto<U>.try_into(): (U throws E)) takes that
      // parameter from the type the call's context expects; the blanket's
      // where clause is then proven for that type.
      if (definition.parameters.size() != 1 || !expectedTypes.contains(&call) ||
          !inferredConversions.insert(declaration).second)
        continue;
      auto declared =
          std::find_if(definition.methods.begin(), definition.methods.end(),
                       [&](const auto &method) { return method.name == name; });
      if (declared == definition.methods.end() || declared->function < 0)
        continue;
      const auto &result = module.functions[declared->function].annotation;
      auto parameterName = checked.types->name(definition.parameters[0]);
      auto expected = expectedTypes.at(&call);
      std::optional<Type> argument;
      if (result.form == TypeForm::Named && result.arguments.empty() &&
          result.name == parameterName)
        argument = expected;
      else if (result.form == TypeForm::Outcome && !result.elements.empty() &&
               result.elements[0].form == TypeForm::Named &&
               result.elements[0].name == parameterName &&
               checked.types->isProduct(expected) &&
               checked.types->product(expected).kind == AggregateKind::Outcome)
        argument = checked.types->product(expected).components[0];
      if (!argument || *argument == Type::Unknown)
        continue;
      auto inferred =
          checked.types->erasedType({definition.name,
                                     static_cast<std::uint32_t>(declaration),
                                     {*argument}});
      if (query().prove({self, inferred}, call.span, false))
        consider(inferred);
    }
  }
  std::sort(candidates.begin(), candidates.end());
  // One interface instance reached through its own implementation and through
  // a subinterface's parent differs only in regions.
  candidates.erase(
      std::unique(candidates.begin(), candidates.end(),
                  [&](const auto &a, const auto &b) {
                    if (std::get<0>(a) != std::get<0>(b) ||
                        std::get<2>(a) != std::get<2>(b))
                      return false;
                    if (std::get<1>(a) == std::get<1>(b))
                      return true;
                    if (!checked.types->isErased(std::get<1>(a)) ||
                        !checked.types->isErased(std::get<1>(b)))
                      return false;
                    const auto &left = checked.types->erased(std::get<1>(a));
                    const auto &right = checked.types->erased(std::get<1>(b));
                    if (left.declaration != right.declaration ||
                        left.arguments.size() != right.arguments.size())
                      return false;
                    for (std::size_t i = 0; i < left.arguments.size(); ++i)
                      if (checked.types->eraseRegions(left.arguments[i]) !=
                          checked.types->eraseRegions(right.arguments[i]))
                        return false;
                    return true;
                  }),
      candidates.end());
  auto sameMethod = [&](const auto &candidate) {
    const auto &first = candidates.front();
    return std::get<0>(candidate) == std::get<0>(first) &&
           std::get<2>(candidate) == std::get<2>(first) &&
           checked.types->isErased(std::get<1>(candidate)) &&
           checked.types->isErased(std::get<1>(first)) &&
           checked.types->erased(std::get<1>(candidate)).declaration ==
               checked.types->erased(std::get<1>(first)).declaration;
  };
  if (candidates.size() > 1 && arguments &&
      std::all_of(candidates.begin(), candidates.end(), sameMethod))
    if (const auto *types = arguments()) {
      using Candidate = std::tuple<std::size_t, Type, int>;
      struct FittingCandidate {
        Candidate candidate;
        RegionEnvironment regions;
      };
      std::vector<FittingCandidate> fitting;
      for (auto candidate : candidates) {
        auto candidateRegions = regionEnvironment();
        if (argumentsFit(std::get<0>(candidate), std::get<1>(candidate), self,
                         *types, call.span, candidateRegions))
          fitting.push_back(
              {std::move(candidate), std::move(candidateRegions)});
      }
      if (fitting.size() == 1) {
        candidates.clear();
        candidates.push_back(std::move(fitting.front().candidate));
        commitRegionEnvironment(std::move(fitting.front().regions));
      }
    }
  if (candidates.size() > 1) {
    error("type", call.span,
          "ambiguous interface method; use explicit disambiguation");
    return std::nullopt;
  }
  if (candidates.empty())
    return std::nullopt;
  auto [function, bound, method] = candidates[0];
  facts(call).interfaceSelf = self;
  facts(call).interfaceType = bound;
  facts(call).interfaceMethod = method;
  return function;
}
std::optional<ReceiverStep>
Checker::dereferenceStep(Type source, bool exclusive, Span span) {
  auto protocol = interfaceNames.find(exclusive ? "core::ops::DerefMut"
                                                : "core::ops::Deref");
  if (protocol == interfaceNames.end())
    return std::nullopt;
  const auto &definition = checked.interfaceData->definitions[protocol->second];
  ErasedType descriptor{definition.name,
                        static_cast<std::uint32_t>(protocol->second)};
  auto bound = checked.types->erasedType(std::move(descriptor));
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (!solver.prove({source, bound}, span, false))
    return std::nullopt;
  auto name = exclusive ? "deref_mut" : "deref";
  auto method =
      std::find_if(definition.methods.begin(), definition.methods.end(),
                   [&](const auto &entry) { return entry.name == name; });
  if (method == definition.methods.end()) {
    error("type", span,
          "native dereference interface has no projection method");
    return std::nullopt;
  }
  auto &callee = module.functions[method->function];
  auto &environment = functionEnvironment(callee);
  auto mode = exclusive ? ParameterMode::Mut : ParameterMode::Read;
  if (callee.parameters.size() != 1 || receiverMode(callee) != mode ||
      environment.parameters.empty() ||
      environment.parameters.size() != method->implicitParameters ||
      !callee.constraints.empty()) {
    error("type", span,
          "native dereference projection has an incompatible signature");
    return std::nullopt;
  }
  std::vector<TypeBinding> bindings{{environment.parameters[0], source}};
  auto *saved = genericEnvironment;
  genericEnvironment = &environment;
  auto parameter =
      annotation(callee.parameters[0].annotation, span, callee.owner);
  auto effect = callee.error.empty()
                    ? Type::Unknown
                    : annotation(callee.error, span, callee.owner);
  completeGenericBindings(environment, bindings, span);
  genericEnvironment = saved;
  auto result = normalizeGenericType(functionResult(callee), bindings, span);
  parameter = normalizeGenericType(parameter, bindings, span);
  if (parameter != source || effect != Type::Unknown ||
      !checked.types->isView(result) ||
      checked.types->view(result).mode != mode ||
      (!callee.annotation.sources.empty() &&
       (callee.annotation.sources.size() != 1 ||
        nameKey(callee.annotation.sources.front()) !=
            nameKey(callee.parameters[0].name,
                    callee.parameters[0].context)))) {
    error("type", span,
          "native dereference must return a matching view from its receiver");
    return std::nullopt;
  }
  ReceiverStep step;
  step.kind = ReceiverStep::Kind::Projection;
  step.source = source;
  step.target = checked.types->view(result).payload;
  step.resultView = result;
  step.mode = mode;
  step.callee = method->function;
  step.interfaceSelf = source;
  step.interfaceType = bound;
  step.interfaceMethod = static_cast<int>(method - definition.methods.begin());
  for (auto parameter : environment.parameters) {
    auto found =
        std::find_if(bindings.begin(), bindings.end(), [&](auto binding) {
          return binding.parameter == parameter;
        });
    step.typeArguments.push_back(found == bindings.end() ? Type::Unknown
                                                         : found->argument);
  }
  return step;
}
bool Checker::mutableReceiverPlan(ReceiverPlan &plan, Span span, bool report) {
  for (auto &step : plan.steps) {
    if (step.kind == ReceiverStep::Kind::Native) {
      if (checked.types->view(step.source).mode == ParameterMode::Read) {
        if (report)
          error("ownership", span,
                "selected mutable receiver is behind a read view");
        return false;
      }
    } else if (step.kind == ReceiverStep::Kind::Unsize ||
               step.kind == ReceiverStep::Kind::Erase) {
      step.mode = ParameterMode::Mut;
      step.resultView =
          checked.types->viewType(step.target, ParameterMode::Mut);
    } else {
      auto projection = dereferenceStep(step.source, true, span);
      if (!projection || projection->target != step.target) {
        if (report)
          error("ownership", span,
                "selected mutable receiver requires matching DerefMut");
        return false;
      }
      step = std::move(*projection);
    }
  }
  return true;
}
bool Checker::argumentsFit(std::size_t index, Type &interfaceType, Type self,
                           std::span<const Type> arguments, Span span,
                           RegionEnvironment &candidateRegions,
                           std::span<const Type> inferredParameters) {
  auto &function = module.functions[index];
  if (imported(function.span))
    functionEnvironment(function);
  auto found = functionGenerics.find(&function);
  if (found == functionGenerics.end())
    return true;
  const auto &environment = found->second;
  std::vector<TypeBinding> bindings;
  for (auto parameter : environment.parameters)
    bindings.push_back({parameter, Type::Unknown});
  seedInterfaceBindings(self, interfaceType, environment, bindings);
  auto caller = genericEnvironment;
  genericEnvironment = const_cast<GenericEnvironment *>(&environment);
  annotationRegionScopes.push_back(functionRegions(function));
  bool fits = true;
  for (std::size_t i = 0; i < arguments.size() && fits; ++i) {
    if (i + 1 >= function.parameters.size())
      break;
    const auto &parameter = function.parameters[i + 1];
    auto actual = arguments[i];
    if (actual == Type::Unknown || partialType(actual))
      continue;
    std::vector<TypeBinding> solved;
    for (const auto &binding : bindings)
      if (binding.argument != Type::Unknown)
        solved.push_back(binding);
    auto pattern = normalizeCallType(
        annotation(parameter.annotation, parameter.span, function.owner),
        solved, function, span);
    if (checked.types->isView(actual) && !checked.types->isView(pattern))
      actual = checked.types->view(actual).payload;
    if (checked.types->isSlice(pattern) && checked.types->isProduct(actual) &&
        checked.types->product(actual).kind == AggregateKind::Array)
      actual = checked.types->sliceType(
          checked.types->product(actual).components[0]);
    interfaces::Solver matching(*checked.types, *checked.interfaceData,
                                diagnostics, interfaceAssumptions(),
                                candidateRegions);
    auto matched = matching.match(pattern, actual, false, &candidateRegions);
    if (!matched) {
      fits = false;
      continue;
    }
    for (const auto &binding : *matched) {
      auto open = std::find_if(bindings.begin(), bindings.end(), [&](auto &b) {
        return b.parameter == binding.parameter && b.argument == Type::Unknown;
      });
      if (open != bindings.end())
        open->argument = binding.argument;
      else if (std::find(inferredParameters.begin(), inferredParameters.end(),
                         binding.parameter) != inferredParameters.end())
        bindings.push_back(binding);
      else
        fits = false;
    }
  }
  std::vector<std::pair<Type, Type>> obligations;
  for (const auto &binding : bindings) {
    if (!fits || binding.argument == Type::Unknown ||
        !checked.types->isParameter(binding.parameter))
      continue;
    auto bounds = environment.bounds.find(binding.parameter);
    if (bounds == environment.bounds.end())
      continue;
    for (const auto &bound : bounds->second) {
      if (bound.form == TypeForm::Callable || bound.name == "unsized" ||
          propertyBound(bound, environment.declarationSpan))
        continue;
      auto required = checked.types->substitute(
          interfaceBound(bound, environment.declarationSpan, {},
                         binding.parameter),
          bindings);
      if (!checked.types->isSymbolic(required))
        obligations.push_back({binding.argument, required});
    }
  }
  annotationRegionScopes.pop_back();
  genericEnvironment = caller;
  interfaces::Solver projectionProof(*checked.types, *checked.interfaceData,
                                     diagnostics, interfaceAssumptions(),
                                     candidateRegions);
  for (auto [subject, required] : obligations) {
    if (!checked.types->isErased(required))
      continue;
    const auto descriptor = checked.types->erased(required);
    for (const auto &binding : descriptor.associated) {
      const auto &definition =
          checked.interfaceData->definitions[descriptor.declaration];
      auto item = std::find_if(
          definition.associated.begin(), definition.associated.end(),
          [&](const auto &associated) {
            return associated.parameter == binding.parameter;
          });
      if (item == definition.associated.end() || item->constant ||
          !item->parameters.empty() || !item->regions.empty())
        continue;
      auto base = descriptor;
      base.associated.clear();
      const auto &associatedType = checked.types->parameter(item->parameter);
      auto projection = checked.types->projection(
          subject, checked.types->erasedType(std::move(base)),
          static_cast<std::size_t>(item - definition.associated.begin()), {},
          associatedType.valueType, associatedType.copyRequested,
          associatedType.sized, associatedType.regionArguments,
          associatedType.thin);
      auto actual = projectionProof.normalize(projection, {}, span);
      if (actual == projection || actual == Type::Unknown ||
          checked.types->isSymbolic(actual))
        continue;
      if (checked.types->eraseRegions(binding.argument) !=
          checked.types->eraseRegions(actual)) {
        fits = false;
        break;
      }
      auto matched = projectionProof.match(binding.argument, actual, false,
                                           &candidateRegions);
      if (!matched || !matched->empty()) {
        fits = false;
        break;
      }
    }
    if (!fits)
      break;
  }
  std::vector<RegionBinding> regionBindings;
  for (const auto &[parameter, argument] : candidateRegions.substitutions)
    regionBindings.push_back({parameter, argument});
  interfaceType = checked.types->substituteRegions(
      checked.types->substitute(interfaceType, bindings), regionBindings);
  for (auto &[subject, required] : obligations)
    required = checked.types->substituteRegions(required, regionBindings);
  interfaces::Solver proof(*checked.types, *checked.interfaceData, diagnostics,
                           interfaceAssumptions(), candidateRegions);
  for (auto [subject, required] : obligations)
    fits = fits && proof.prove({subject, required}, span, false);
  return fits;
}
std::optional<std::size_t> Checker::receiverMethod(Type source, Node &call,
                                                   bool reachable) {
  auto native = source;
  while (checked.types->isView(native))
    native = checked.types->view(native).payload;
  if (checked.types->isProduct(native) &&
      (checked.types->product(native).kind == AggregateKind::Ref ||
       checked.types->product(native).kind == AggregateKind::RefMut)) {
    const Type operands[] = {
        checked.types->viewType(native, ParameterMode::Mut)};
    if (machineSignature(*checked.types, "cell." + call.children[0]->text,
                         operands, native))
      return std::nullopt;
  }
  // Arguments are checked early only to resolve an otherwise ambiguous
  // choice; the call reuses their results.
  std::optional<std::vector<Type>> argumentTypes;
  auto arguments = [&]() -> const std::vector<Type> * {
    if (!argumentTypes) {
      argumentTypes.emplace();
      bool positional = std::all_of(
          call.children.begin() + 1, call.children.end(),
          [](const auto &argument) { return argument->name.empty(); });
      for (std::size_t i = 1; positional && i < call.children.size(); ++i) {
        auto &argument = *call.children[i];
        auto variable = node(argument, reachable);
        reusedNodes.insert(&argument);
        argumentTypes->push_back(inference.value(variable));
      }
    }
    return argumentTypes->empty() ? nullptr : &*argumentTypes;
  };
  ReceiverPlan plan{source, source, {}};
  auto selectedPlan = [&](ReceiverPlan selected, ParameterMode mode) {
    bool borrowed = !selected.steps.empty() &&
                    selected.steps.back().kind == ReceiverStep::Kind::Borrow;
    if (borrowed) {
      auto borrow = selected.steps.back();
      if (borrow.mode == ParameterMode::Mut) {
        requireMutablePlace(*call.children[0]->children[0]);
        selected.steps.pop_back();
        mutableReceiverPlan(selected, call.span);
        selected.steps.push_back(borrow);
      }
    } else {
      if (mode == ParameterMode::Take && !selected.steps.empty())
        error("ownership", call.span,
              "cannot move out of a viewed place for the selected "
              "consuming receiver");
      if (mode == ParameterMode::Mut) {
        requireMutablePlace(*call.children[0]->children[0]);
        mutableReceiverPlan(selected, call.span);
      }
    }
    facts(call).receiverPlan = std::move(selected);
  };
  std::set<Type> visited;
  for (unsigned depth = 0; depth < limits::typeDepth; ++depth) {
    if (!visited.insert(plan.target).second) {
      error("type", call.span, "cyclic receiver dereference");
      return std::nullopt;
    }
    // A pin's builtin methods shadow same-named methods of its target.
    if (checked.types->isProduct(plan.target) &&
        checked.types->product(plan.target).kind == AggregateKind::Pin &&
        builtinPinMethod(call.children[0]->text))
      return std::nullopt;
    // A view receiver already is the borrow of its referent, so the referent's
    // own methods are by-value candidates that precede blanket implementations
    // for the view type itself (`read CStr`.to_owned() is a `CString`).
    if (checked.types->isView(plan.target)) {
      // Methods declared directly on the view type come first.
      for (auto mode :
           {ParameterMode::Take, ParameterMode::Read, ParameterMode::Mut}) {
        auto before = diagnostics.items.size();
        auto own = receiverCandidate(plan.target, mode, call.children[0]->text,
                                     call, arguments, true);
        if (own) {
          selectedPlan(plan, mode);
          return own;
        }
        if (diagnostics.items.size() != before)
          return std::nullopt;
      }
      auto referent = plan;
      ReceiverStep step;
      step.source = plan.target;
      step.target = checked.types->view(plan.target).payload;
      referent.target = step.target;
      referent.steps.push_back(std::move(step));
      const auto viewMode = checked.types->view(plan.target).mode;
      for (auto mode : {ParameterMode::Take, viewMode}) {
        auto before = diagnostics.items.size();
        auto selected = receiverCandidate(
            referent.target, mode, call.children[0]->text, call, arguments);
        // A consuming interface method of the referent must not preempt the
        // view's own implementation (`mut I`.fold); only an inherent one does.
        if (selected && mode == ParameterMode::Take &&
            facts(call).interfaceType != Type::Unknown) {
          facts(call).interfaceType = Type::Unknown;
          facts(call).interfaceSelf = Type::Unknown;
          selected.reset();
        }
        if (selected) {
          selectedPlan(std::move(referent), mode);
          return selected;
        }
        if (diagnostics.items.size() != before)
          return std::nullopt;
      }
    }
    for (auto mode :
         {ParameterMode::Take, ParameterMode::Read, ParameterMode::Mut}) {
      auto before = diagnostics.items.size();
      auto selected = receiverCandidate(
          plan.target, mode, call.children[0]->text, call, arguments);
      if (selected) {
        selectedPlan(plan, mode);
        return selected;
      }
      if (diagnostics.items.size() != before)
        return std::nullopt;
    }
    for (auto borrow : {ParameterMode::Read, ParameterMode::Mut}) {
      auto borrowed = checked.types->viewType(plan.target, borrow);
      for (auto mode :
           {ParameterMode::Take, ParameterMode::Read, ParameterMode::Mut}) {
        auto before = diagnostics.items.size();
        auto selected = receiverCandidate(
            borrowed, mode, call.children[0]->text, call, arguments, true);
        if (selected) {
          auto converted = plan;
          ReceiverStep step;
          step.kind = ReceiverStep::Kind::Borrow;
          step.source = plan.target;
          step.target = borrowed;
          step.mode = borrow;
          converted.steps.push_back(step);
          converted.target = borrowed;
          selectedPlan(std::move(converted), mode);
          return selected;
        }
        if (diagnostics.items.size() != before)
          return std::nullopt;
      }
    }
    if (checked.types->isSlice(plan.target) &&
        call.children[0]->text == "len") {
      if (!plan.steps.empty())
        facts(call).receiverPlan = std::move(plan);
      return std::nullopt;
    }
    ReceiverStep step;
    if (checked.types->isView(plan.target)) {
      step.source = plan.target;
      step.target = checked.types->view(plan.target).payload;
    } else if (checked.types->isProduct(plan.target) &&
               checked.types->product(plan.target).kind ==
                   AggregateKind::Array) {
      auto array = checked.types->product(plan.target);
      step.kind = ReceiverStep::Kind::Unsize;
      step.source = plan.target;
      step.target = checked.types->sliceType(array.components[0]);
      step.resultView =
          checked.types->viewType(step.target, ParameterMode::Read);
      step.count = array.arrayCount == Type::Unknown
                       ? checked.types->constant(Type::I32, array.fields.size())
                       : array.arrayCount;
    } else {
      auto projection = dereferenceStep(plan.target, false, call.span);
      if (!projection)
        return std::nullopt;
      step = std::move(*projection);
    }
    plan.target = step.target;
    plan.steps.push_back(std::move(step));
  }
  error("limit", call.span, "receiver dereference search limit exceeded");
  return std::nullopt;
}
std::optional<ReceiverPlan>
Checker::receiverConversion(Type source, Type target, ParameterMode mode,
                            Span span, bool report) {
  ReceiverPlan plan{source, source, {}};
  std::set<Type> visited;
  for (unsigned depth = 0; depth < limits::typeDepth; ++depth) {
    if (plan.target == target) {
      if (mode == ParameterMode::Mut &&
          !mutableReceiverPlan(plan, span, report))
        return std::nullopt;
      return plan;
    }
    // The source's own outer view is the borrow being converted, so erasure
    // starts at its referent even when the view type itself implements the
    // interface (as with a blanket implementation).
    const bool borrowView = plan.steps.empty() && checked.types->isView(source);
    if (!borrowView && checked.types->isErased(target) &&
        (checked.types->isErased(plan.target) ||
         checked.types->isSized(plan.target))) {
      interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                diagnostics, interfaceAssumptions(),
                                regionEnvironment());
      if (solver.prove({plan.target, target}, span, false)) {
        ReceiverStep step;
        step.kind = ReceiverStep::Kind::Erase;
        step.source = plan.target;
        step.target = target;
        step.mode = mode;
        step.resultView = checked.types->viewType(target, mode);
        plan.steps.push_back(std::move(step));
        plan.target = target;
        erasedUses.emplace(target, span);
        if (mode == ParameterMode::Mut &&
            !mutableReceiverPlan(plan, span, report))
          return std::nullopt;
        return plan;
      }
    }
    if (auto array = checked.types->unsizedArray(plan.target, target)) {
      ReceiverStep step;
      step.kind = ReceiverStep::Kind::Unsize;
      step.source = plan.target;
      step.target = target;
      step.mode = mode;
      step.resultView = checked.types->viewType(target, mode);
      const auto &record = checked.types->product(*array);
      step.count =
          record.arrayCount == Type::Unknown
              ? checked.types->constant(Type::I32, record.fields.size())
              : record.arrayCount;
      plan.steps.push_back(std::move(step));
      plan.target = target;
      if (mode == ParameterMode::Mut &&
          !mutableReceiverPlan(plan, span, report))
        return std::nullopt;
      return plan;
    }
    if (!visited.insert(plan.target).second) {
      if (report)
        error("type", span, "cyclic dereference coercion");
      return std::nullopt;
    }
    ReceiverStep step;
    if (checked.types->isView(plan.target)) {
      step.source = plan.target;
      step.target = checked.types->view(plan.target).payload;
    } else {
      auto projection = dereferenceStep(plan.target, false, span);
      if (!projection)
        return std::nullopt;
      step = std::move(*projection);
    }
    plan.target = step.target;
    plan.steps.push_back(std::move(step));
  }
  error("limit", span, "dereference coercion search limit exceeded");
  return std::nullopt;
}
bool Checker::borrowCoercion(Node &node, int actual, Type target,
                             ParameterMode mode) {
  auto source = inference.value(actual);
  if (source == target || source == Type::Unknown || target == Type::Unknown ||
      source == Type::Never ||
      (checked.types->isView(source) &&
       checked.types->view(source).payload == target &&
       !checked.types->isView(target)))
    return false;
  auto native = checked.types->isView(source)
                    ? checked.types->view(source).payload
                    : source;
  if (checked.types->unsizedArray(native, target))
    return false;
  if (!checked.types->isView(source) && checked.types->isErased(target)) {
    interfaces::Solver solver(*checked.types, *checked.interfaceData,
                              diagnostics, interfaceAssumptions(),
                              regionEnvironment());
    if (solver.prove({source, target}, node.span, false))
      return false;
  }
  auto plan = receiverConversion(source, target, mode, node.span);
  if (!plan) {
    if (mode == ParameterMode::Mut && checked.types->isView(source) &&
        checked.types->isView(target)) {
      error("type", node.span,
            "mutable view handles require an invariant payload type");
      return true;
    }
    return false;
  }
  if (mode == ParameterMode::Mut)
    requireMutablePlace(node);
  facts(node).borrowConversion = std::move(*plan);
  return true;
}
} // namespace mettle
