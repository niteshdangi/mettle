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
std::optional<std::size_t> Checker::receiverCandidate(Type receiver,
                                                      ParameterMode mode,
                                                      std::string_view name,
                                                      Node &call) {
  std::vector<std::size_t> inherent;
  std::map<std::size_t, std::vector<Type>> inherentArguments;
  // Compiler-generated iteration calls name their protocol interface in
  // call.text and bypass inherent methods and import visibility.
  const bool protocol = call.kind == Kind::Call && !call.text.empty();
  auto self = receiver;
  bool pinned = checked.types->isProduct(receiver) &&
                checked.types->product(receiver).kind == AggregateKind::Pin;
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
        if (entry.name == name &&
            accepts(static_cast<std::size_t>(entry.function)))
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
  } else {
    auto caller = checked.symbols->moduleOf(call.span);
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
    const auto &declaring = interfacesDeclaring(std::string(name));
    for (const auto &implementation : checked.interfaceData->implementations) {
      if (!checked.types->isErased(implementation.interfaceType) ||
          !declaring[checked.types->erased(implementation.interfaceType)
                         .declaration])
        continue;
      auto bindings = solver.applicable(implementation, self, call.span);
      if (!bindings)
        continue;
      auto bound =
          checked.types->substitute(implementation.interfaceType, *bindings);
      const auto &definition =
          checked.interfaceData
              ->definitions[checked.types->erased(bound).declaration];
      if (visible(definition) && solver.prove({self, bound}, call.span, false))
        consider(bound);
    }
  }
  std::sort(candidates.begin(), candidates.end());
  candidates.erase(std::unique(candidates.begin(), candidates.end()),
                   candidates.end());
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
       callee.annotation.sources != std::vector<std::string>{"self"})) {
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
std::optional<std::size_t> Checker::receiverMethod(Type source, Node &call) {
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
      auto selected =
          receiverCandidate(plan.target, mode, call.children[0]->text, call);
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
    if (checked.types->isErased(target) &&
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
       checked.types->view(source).payload == target))
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
