#include "semantics/checker.h"
#include "support/limits.h"
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
const std::vector<bool> &Checker::interfacesDeclaring(const std::string &name) {
  auto &definitions = checked.interfaceData->definitions;
  auto &declaring = methodInterfaces[name];
  if (declaring.size() == definitions.size())
    return declaring;
  declaring.assign(definitions.size(), false);
  for (std::size_t root = 0; root < definitions.size(); ++root) {
    std::vector<std::size_t> pending{root};
    std::set<std::size_t> visited{root};
    while (!pending.empty() && !declaring[root]) {
      auto next = pending.back();
      pending.pop_back();
      for (const auto &method : definitions[next].methods)
        if (method.name == name)
          declaring[root] = true;
      for (const auto &parent : definitions[next].superinterfaces)
        if (parent.property == interfaces::Property::Interface &&
            checked.types->isErased(parent.interfaceType)) {
          auto declaration =
              checked.types->erased(parent.interfaceType).declaration;
          if (visited.insert(declaration).second)
            pending.push_back(declaration);
        }
    }
  }
  return declaring;
}
std::optional<std::size_t> Checker::receiverCandidate(
    Type receiver, ParameterMode mode, std::string_view name, const Node &call,
    const std::function<const std::vector<Type> *()> &arguments) {
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
  static const std::set<std::string_view> builtinPinMethods{
      "as_ref",
      "as_mut",
      "get_ref",
      "get_mut",
      "get_unchecked_mut",
      "into_inner",
      "into_inner_unchecked"};
  if (pinned && !builtinPinMethods.contains(name) &&
      !name.starts_with("project_")) {
    pinAsOwner = true;
    auto own = receiverCandidate(receiver, mode, name, call, arguments);
    pinAsOwner = false;
    if (own)
      return own;
  }
  if (pinned)
    self = checked.types->view(checked.types->product(receiver).components[0])
               .payload;
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
    if (auto found = names.find(owner + "." + std::string(name));
        found != names.end() && accepts(found->second))
      inherent.push_back(found->second);
  }
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  for (const auto &implementation : checked.interfaceData->implementations) {
    if (protocol || implementation.interfaceType != Type::Unknown)
      continue;
    auto selected = implementation.inherent.find(std::string(name));
    if (selected == implementation.inherent.end() ||
        !accepts(static_cast<std::size_t>(selected->second.function)))
      continue;
    auto bindings = solver.applicable(implementation, self, call.span);
    if (!bindings)
      continue;
    auto index = static_cast<std::size_t>(selected->second.function);
    inherent.push_back(index);
    for (auto parameter : selected->second.arguments)
      inherentArguments[index].push_back(
          solver.normalize(parameter, *bindings, call.span));
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
  std::vector<std::tuple<std::size_t, Type, int>> candidates;
  auto consider = [&](Type bound) {
    if (!checked.types->isErased(bound))
      return;
    for (auto inherited :
         interfaces::hierarchy(*checked.types, *checked.interfaceData, self,
                               bound, call.span, diagnostics)) {
      const auto &descriptor = checked.types->erased(inherited);
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
    for (const auto &bound : solver.projectionBounds(self, call.span))
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
  if (!checked.types->isErased(self)) {
    auto caller = accessModule(call);
    auto visible = [&](const interfaces::Definition &definition) {
      if (protocol)
        return true;
      if (!checked.symbols->accessible(definition.span, caller))
        return false;
      if (checked.symbols->moduleOf(definition.span) == caller)
        return true;
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
    const auto &declaring = interfacesDeclaring(std::string(name));
    for (const auto &implementation : checked.interfaceData->implementations) {
      if (!checked.types->isErased(implementation.interfaceType) ||
          !declaring[checked.types->erased(implementation.interfaceType)
                         .declaration])
        continue;
      const auto declaration =
          checked.types->erased(implementation.interfaceType).declaration;
      const auto &definition = checked.interfaceData->definitions[declaration];
      if (!visibility.try_emplace(declaration, visible(definition))
               .first->second)
        continue;
      std::vector<RegionBinding> regions;
      const auto targetHead = head(implementation.target);
      auto bindings =
          selfHead != Type::Unknown && targetHead != Type::Unknown &&
                  selfHead != targetHead
              ? std::nullopt
              : solver.applicable(implementation, self, call.span, &regions);
      if (bindings) {
        auto bound = checked.types->substituteRegions(
            checked.types->substitute(implementation.interfaceType, *bindings),
            regions);
        if (solver.prove({self, bound}, call.span, false)) {
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
      if (solver.prove({self, inferred}, call.span, false))
        consider(inferred);
    }
  }
  std::sort(candidates.begin(), candidates.end());
  candidates.erase(std::unique(candidates.begin(), candidates.end()),
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
  auto &environment = functionGenerics.at(&callee);
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
  auto result = normalizeGenericType(
      inference.value(functionVariables.at(&callee)), bindings, span);
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
                           RegionEnvironment &candidateRegions) {
  auto &function = module.functions[index];
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
    auto pattern = checked.types->substitute(
        annotation(parameter.annotation, parameter.span, function.owner),
        solved);
    if (checked.types->isView(actual) && !checked.types->isView(pattern))
      actual = checked.types->view(actual).payload;
    auto open = std::find_if(bindings.begin(), bindings.end(), [&](auto &b) {
      return b.parameter == pattern && b.argument == Type::Unknown;
    });
    if (open != bindings.end())
      open->argument = actual;
    else if (!checked.types->isSymbolic(pattern) &&
             checked.types->eraseRegions(pattern) !=
                 checked.types->eraseRegions(actual))
      fits = false;
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
      if (bound.form == TypeForm::Callable || bound.name == "?Sized" ||
          bound.name == "unsized" ||
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
      auto projection = checked.types->projection(
          subject, checked.types->erasedType(std::move(base)),
          static_cast<std::size_t>(item - definition.associated.begin()));
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
  interfaceType =
      checked.types->substituteRegions(interfaceType, regionBindings);
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
  std::set<Type> visited;
  for (unsigned depth = 0; depth < limits::typeDepth; ++depth) {
    if (!visited.insert(plan.target).second) {
      error("type", call.span, "cyclic receiver dereference");
      return std::nullopt;
    }
    for (auto mode :
         {ParameterMode::Take, ParameterMode::Read, ParameterMode::Mut}) {
      auto before = diagnostics.items.size();
      auto selected = receiverCandidate(
          plan.target, mode, call.children[0]->text, call, arguments);
      if (selected) {
        if (mode == ParameterMode::Take && !plan.steps.empty())
          error("ownership", call.span,
                "cannot move out of a borrowed place for the selected "
                "consuming receiver");
        if (mode == ParameterMode::Mut) {
          requireMutablePlace(*call.children[0]->children[0]);
          mutableReceiverPlan(plan, call.span);
        }
        facts(call).receiverPlan = std::move(plan);
        return selected;
      }
      if (diagnostics.items.size() != before)
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
        !checked.types->isErased(plan.target) &&
        checked.types->isSized(plan.target)) {
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
            "mutable borrowed view handles require an invariant payload type");
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
