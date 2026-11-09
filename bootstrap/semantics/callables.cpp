#include "semantics/checker.h"
#include "support/limits.h"
#include "types/layout.h"
#include <algorithm>
#include <functional>

namespace mettle {
namespace {
ParameterMode parameterMode(std::string_view spelling, Type type,
                            const TypeStore &types) {
  return spelling == "take"   ? ParameterMode::Take
         : spelling == "read" ? ParameterMode::Read
         : spelling == "mut"  ? ParameterMode::Mut
         : types.isCopy(type) ? ParameterMode::Value
                              : ParameterMode::Read;
}
} // namespace
Type Checker::callableAnnotation(const TypeSyntax &syntax, Span span,
                                 std::string_view owner) {
  const auto &source = *syntax.callable;
  if (source.variadic && source.abi.empty())
    error("signature", span, "variadic callable types require a foreign ABI");
  if (!source.abi.empty() && source.abi != "C" && source.abi != "C-unwind" &&
      source.abi != "system")
    error("feature", span,
          "unsupported foreign callable ABI '" + source.abi + "'");
  CallableType descriptor;
  descriptor.unsafeCall = source.unsafeCall;
  descriptor.abi = source.abi;
  descriptor.variadic = source.variadic;
  descriptor.mode = source.mode == "mut"    ? ParameterMode::Mut
                    : source.mode == "take" ? ParameterMode::Take
                                            : ParameterMode::Read;
  descriptor.regions = source.regions;
  for (const auto &parameter : source.parameters) {
    auto type = annotation(parameter.annotation, span, owner);
    descriptor.parameters.push_back(
        {type, parameterMode(parameter.mode, type, *checked.types),
         parameter.name});
  }
  descriptor.result = annotation(source.result, span, owner);
  if (!source.error.empty())
    descriptor.error = annotation(source.error, span, owner);
  descriptor.abiResult =
      descriptor.error == Type::Unknown
          ? descriptor.result
          : checked.types->structural(AggregateKind::Outcome,
                                      {descriptor.result, descriptor.error});
  if (checked.types->containsViews(descriptor.abiResult)) {
    std::vector<std::size_t> eligible;
    for (std::size_t i = 0; i < descriptor.parameters.size(); ++i) {
      const auto &parameter = descriptor.parameters[i];
      if (parameter.mode == ParameterMode::Read ||
          parameter.mode == ParameterMode::Mut ||
          checked.types->containsViews(parameter.type))
        eligible.push_back(i);
    }
    if (!source.result.sources.empty()) {
      for (const auto &name : source.result.sources) {
        auto found = std::find_if(
            source.parameters.begin(), source.parameters.end(),
            [&](const auto &parameter) { return parameter.name == name; });
        if (found == source.parameters.end()) {
          // A bound region names every input carrying that region.
          bool matched = false;
          for (std::size_t i = 0; i < source.parameters.size(); ++i) {
            const auto &sources = source.parameters[i].annotation.sources;
            if (std::find(sources.begin(), sources.end(), name) !=
                sources.end()) {
              descriptor.resultSources.push_back(i);
              matched = true;
            }
          }
          if (!matched)
            error("name", span,
                  "unknown callable result source '" + name + "'");
        } else {
          auto index =
              static_cast<std::size_t>(found - source.parameters.begin());
          if (std::find(eligible.begin(), eligible.end(), index) ==
              eligible.end())
            error("ownership", span, "callable result source is not borrowed");
          else
            descriptor.resultSources.push_back(index);
        }
      }
    } else if (eligible.size() == 1)
      descriptor.resultSources = eligible;
    else
      error("ownership", span,
            "borrowed callable result requires an unambiguous from contract");
  }
  return checked.types->callableType(std::move(descriptor));
}
Type Checker::callableRegionAnnotation(const TypeSyntax &syntax, Span span,
                                       std::string_view owner) {
  const auto &source = *syntax.callable;
  AnnotationRegions scope;
  if (!annotationRegionScopes.empty())
    scope = annotationRegionScopes.back();
  else if (current)
    scope = functionRegions(*current);
  scope.scope = checked.types->regions().binder(scope.environment.universe);
  scope.environment.universe = scope.scope.universe;
  scope.parameters.clear();
  for (const auto &name : source.regions) {
    auto region = checked.types->regions().bound(scope.scope, name);
    scope.names[name] = region;
    scope.parameters.push_back(region);
  }
  auto depth = annotationRegionScopes.size();
  annotationRegionScopes.push_back(std::move(scope));
  struct Scope {
    std::vector<AnnotationRegions> &scopes;
    std::size_t depth;
    ~Scope() { scopes.resize(depth); }
  } restore{annotationRegionScopes, depth};
  CallableType descriptor;
  descriptor.unsafeCall = source.unsafeCall;
  descriptor.abi = source.abi;
  descriptor.variadic = source.variadic;
  descriptor.mode = source.mode == "mut"    ? ParameterMode::Mut
                    : source.mode == "take" ? ParameterMode::Take
                                            : ParameterMode::Read;
  descriptor.regions = source.regions;
  for (const auto &parameter : source.parameters) {
    auto activeScope = annotationRegionScopes.back().scope;
    auto region =
        parameter.annotation.sources.empty()
            ? checked.types->regions().bound(activeScope, "<parameter>")
            : annotationRegion(parameter.annotation, span);
    annotationRegionScopes.back().fallback = region;
    auto type = semanticAnnotation(parameter.annotation, span, owner);
    auto &active = annotationRegionScopes.back();
    auto mode = parameterMode(parameter.mode, type, *checked.types);
    descriptor.parameters.push_back({type, mode, parameter.name});
    descriptor.parameterRegions.push_back(region);
    if (!parameter.name.empty())
      annotationRegionScopes.back().names[parameter.name] = region;
    if ((mode == ParameterMode::Read || mode == ParameterMode::Mut ||
         checked.types->containsViews(type)) &&
        checked.types->regions().get(region).kind == RegionKind::Bound &&
        checked.types->regions().get(region).binder == active.scope.binder &&
        std::find(active.parameters.begin(), active.parameters.end(), region) ==
            active.parameters.end())
      active.parameters.push_back(region);
  }
  annotationRegionScopes.back().fallback = descriptor.parameters.size() == 1
                                               ? descriptor.parameterRegions[0]
                                               : RegionId::Unspecified;
  descriptor.result = semanticAnnotation(source.result, span, owner);
  if (!source.error.empty())
    descriptor.error = semanticAnnotation(source.error, span, owner);
  descriptor.abiResult =
      descriptor.error == Type::Unknown
          ? descriptor.result
          : checked.types->structural(AggregateKind::Outcome,
                                      {descriptor.result, descriptor.error});
  const auto &active = annotationRegionScopes.back();
  descriptor.regionParameters = active.parameters;
  descriptor.regionUniverse = active.scope.universe;
  descriptor.regionRequirements = active.environment.assumptions;
  if (checked.types->containsViews(descriptor.abiResult)) {
    std::vector<std::size_t> eligible;
    for (std::size_t p = 0; p < descriptor.parameters.size(); ++p)
      if (descriptor.parameters[p].mode == ParameterMode::Read ||
          descriptor.parameters[p].mode == ParameterMode::Mut ||
          checked.types->containsViews(descriptor.parameters[p].type))
        eligible.push_back(p);
    for (const auto &name : source.result.sources) {
      bool matched = false;
      auto region = active.names.find(name);
      for (auto p : eligible) {
        std::set<Type> visited;
        std::function<bool(Type)> carries = [&](Type type) {
          if (!visited.insert(type).second || region == active.names.end())
            return false;
          if (checked.types->isView(type))
            return checked.types->view(type).region == region->second ||
                   carries(checked.types->view(type).payload);
          if (checked.types->isSlice(type))
            return carries(checked.types->slice(type).element);
          if (checked.types->isProduct(type))
            for (const auto &field : checked.types->product(type).fields)
              if (carries(field.type))
                return true;
          if (checked.types->isErased(type)) {
            const auto &erased = checked.types->erased(type);
            if (std::find(erased.regionArguments.begin(),
                          erased.regionArguments.end(),
                          region->second) != erased.regionArguments.end())
              return true;
            for (auto argument : erased.arguments)
              if (carries(argument))
                return true;
          }
          return false;
        };
        if (source.parameters[p].name == name ||
            (region != active.names.end() &&
             descriptor.parameterRegions[p] == region->second) ||
            carries(descriptor.parameters[p].type)) {
          descriptor.resultSources.push_back(p);
          matched = true;
        }
      }
      if (!matched)
        error("name", span, "unknown callable result source '" + name + "'");
    }
    if (source.result.sources.empty()) {
      if (eligible.size() == 1)
        descriptor.resultSources = eligible;
      else
        error("ownership", span,
              "borrowed callable result requires an unambiguous from contract");
    }
    std::sort(descriptor.resultSources.begin(), descriptor.resultSources.end());
    descriptor.resultSources.erase(std::unique(descriptor.resultSources.begin(),
                                               descriptor.resultSources.end()),
                                   descriptor.resultSources.end());
  }
  return checked.types->callableType(std::move(descriptor));
}
CallableType Checker::functionSignature(std::size_t index) {
  auto &function = module.functions[index];
  auto saved = genericEnvironment;
  genericEnvironment = &functionGenerics.at(&function);
  const auto &declaration = facts(function);
  CallableType result;
  result.unsafeCall = function.unsafeFunction;
  result.abi = function.abi;
  result.variadic = function.variadic;
  result.targetFeatures = declaration.targetFeatures;
  result.regions = function.regions;
  result.result = inference.value(functionVariables.at(&function));
  result.error = declaration.error;
  result.abiResult =
      result.error == Type::Unknown
          ? result.result
          : checked.types->structural(AggregateKind::Outcome,
                                      {result.result, result.error});
  result.resultSources = declaration.resultSources;
  for (std::size_t p = 0; p < function.parameters.size(); ++p) {
    const auto &parameter = function.parameters[p];
    auto type =
        p < declaration.locals.size()
            ? inference.value(localVariables.at(&function)[p])
            : annotation(parameter.annotation, parameter.span, function.owner);
    auto mode = p < declaration.locals.size()
                    ? declaration.locals[p].mode
                    : parameterMode(parameter.mode, type, *checked.types);
    result.parameters.push_back({type, mode, parameter.name});
  }
  if (result.resultSources.empty() &&
      checked.types->containsViews(result.abiResult)) {
    for (std::size_t p = 0; p < function.parameters.size(); ++p)
      for (const auto &source : function.annotation.sources) {
        const auto &parameter = function.parameters[p];
        if (source == parameter.name ||
            std::find(parameter.annotation.sources.begin(),
                      parameter.annotation.sources.end(),
                      source) != parameter.annotation.sources.end()) {
          result.resultSources.push_back(p);
          break;
        }
      }
    if (function.annotation.sources.empty()) {
      std::vector<std::size_t> eligible;
      for (std::size_t p = 0; p < result.parameters.size(); ++p)
        if (result.parameters[p].mode == ParameterMode::Read ||
            result.parameters[p].mode == ParameterMode::Mut ||
            checked.types->containsViews(result.parameters[p].type))
          eligible.push_back(p);
      if (eligible.size() == 1)
        result.resultSources = eligible;
    }
  }
  genericEnvironment = saved;
  return result;
}
int Checker::functionValue(Node &node, std::size_t index) {
  auto generic = genericFunctionValue(node, index);
  auto signature = generic ? std::move(*generic) : functionSignature(index);
  if (signature.result == Type::Unknown) {
    error("type", node.span,
          "function value requires its declaration result to be resolved");
    return inference.fresh();
  }
  const auto &function = module.functions[index];
  if (function.destructor) {
    error("ownership", node.span, "cannot form a destructor function pointer");
    return inference.fresh();
  }
  for (const auto &parameter : function.parameters)
    if (parameter.format) {
      error("type", node.span,
            "a function with a 'format' parameter cannot be used as a value");
      return inference.fresh();
    }
  if (!checked.symbols->accessible(function.span,
                                   checked.symbols->moduleOf(node.span)))
    error("name", node.span, "function is inaccessible");
  facts(node).callee = static_cast<int>(index);
  return inference.fresh(checked.types->callableType(std::move(signature)));
}
bool Checker::compatibleCallable(Type source, Type target) const {
  if (checked.types->isParameter(source) ||
      !checked.types->isCallable(source) ||
      !checked.types->isFunctionPointer(target))
    return false;
  const auto &actual = checked.types->callable(source);
  const auto &expected = checked.types->callable(target);
  if (actual.variadic != expected.variadic)
    return false;
  if (!std::includes(
          expected.targetFeatures.begin(), expected.targetFeatures.end(),
          actual.targetFeatures.begin(), actual.targetFeatures.end()))
    return false;
  if ((actual.unsafeCall && !expected.unsafeCall) || actual.abi != expected.abi)
    return false;
  if (actual.environment != Type::Unknown &&
      !checked.types->product(actual.environment).fields.empty())
    return false;
  if (actual.parameters.size() != expected.parameters.size() ||
      actual.result != expected.result || actual.error != expected.error ||
      actual.resultSources != expected.resultSources)
    return false;
  if (actual.mode == ParameterMode::Take &&
      expected.mode != ParameterMode::Take)
    return false;
  if (actual.mode == ParameterMode::Mut && expected.mode == ParameterMode::Read)
    return false;
  for (std::size_t i = 0; i < actual.parameters.size(); ++i)
    if (actual.parameters[i].type != expected.parameters[i].type ||
        actual.parameters[i].mode != expected.parameters[i].mode)
      return false;
  return true;
}
bool Checker::callableObligation(Type actual, Type contract, Span span) {
  if (checked.types->satisfiesCallable(actual, contract))
    return true;
  error("type", span,
        "callable does not satisfy its declared signature or invocation mode");
  return false;
}
void Checker::contextualize(Node &node, Type expected) {
  if (expected == Type::Unknown)
    return;
  expectedTypes[&node] = expected;
  auto fullExpected = expected;
  while (checked.types->isProduct(expected) &&
         checked.types->product(expected).kind == AggregateKind::Optional)
    expected = checked.types->product(expected).components[0];
  if (node.kind == Kind::Closure || node.kind == Kind::Name)
    closureContexts[&node] = expected;
  else if (node.kind == Kind::Group || node.kind == Kind::Unsafe)
    contextualize(*node.children[0], fullExpected);
  else if (node.kind == Kind::Block && !node.children.empty())
    contextualize(*node.children.back(), fullExpected);
  else if (node.kind == Kind::If) {
    contextualize(*node.children[1], fullExpected);
    if (node.children.size() > 2)
      contextualize(*node.children[2], fullExpected);
  } else if (node.kind == Kind::Match) {
    for (std::size_t i = 1; i < node.children.size(); ++i)
      contextualize(*node.children[i]->children.back(), fullExpected);
  } else if ((node.kind == Kind::Tuple || node.kind == Kind::Array) &&
             checked.types->isProduct(expected)) {
    const auto &aggregate = checked.types->product(expected);
    for (std::size_t i = 0; i < node.children.size(); ++i) {
      if (node.kind == Kind::Array && node.flag && i)
        break;
      if (aggregate.kind == AggregateKind::Array)
        contextualize(*node.children[i], aggregate.components[0]);
      else if (aggregate.kind == AggregateKind::Tuple &&
               i < aggregate.fields.size())
        contextualize(*node.children[i], aggregate.fields[i].type);
    }
  }
}
int Checker::indirectCall(Node &node, bool reachable, int calleeVariable) {
  auto variable = calleeVariable >= 0
                      ? calleeVariable
                      : this->node(*node.children[0], reachable);
  fields(false);
  auto type = inference.value(variable);
  auto source = type;
  while (checked.types->isView(type)) {
    type = checked.types->view(type).payload;
    ++facts(node).dereferences;
  }
  // A callable reached through Deref (`Box<fn(i32): i32>`) is called in place.
  if (!checked.types->isCallable(type) && checked.types->isProduct(type)) {
    ReceiverPlan plan{source, source, {}};
    while (checked.types->isView(plan.target)) {
      ReceiverStep step;
      step.source = plan.target;
      step.target = checked.types->view(plan.target).payload;
      plan.target = step.target;
      plan.steps.push_back(std::move(step));
    }
    for (unsigned depth = 0; depth < limits::typeDepth &&
                             !checked.types->isCallable(plan.target);
         ++depth) {
      auto step = dereferenceStep(plan.target, false, node.span);
      if (!step)
        break;
      plan.target = step->target;
      plan.steps.push_back(std::move(*step));
    }
    if (checked.types->isCallable(plan.target)) {
      type = plan.target;
      facts(node).dereferences = 0;
      const auto mode = checked.types->callable(type).mode;
      if (mode == ParameterMode::Mut) {
        requireMutablePlace(*node.children[0]);
        mutableReceiverPlan(plan, node.span);
      } else if (mode != ParameterMode::Read &&
                 !checked.types->isCopy(type))
        error("ownership", node.span,
              "cannot move a consuming callable out of a borrowed place");
      facts(node).receiverPlan = std::move(plan);
    }
  }
  if (!checked.types->isCallable(type)) {
    error("type", node.span, "expression is not callable");
    return inference.fresh();
  }
  const auto signature = checked.types->callable(type);
  requireFeatures(signature.targetFeatures, node.span);
  if (signature.unsafeCall || signature.variadic)
    requireUnsafe(node.span);
  if (signature.mode == ParameterMode::Mut)
    requireMutablePlace(*node.children[0]);
  ClosureFacts *closure =
      checked.types->isProduct(type)
          ? checked.closureBodies.at(signature.function).get()
          : nullptr;
  if (closure && closure->type != type)
    closure = nullptr;
  facts(node).indirect = true;
  facts(node).effect = signature.error;
  if (signature.error != Type::Unknown && !effectContext)
    error("effects", node.span, "throwing call requires try or capture");
  if (signature.variadic
          ? node.children.size() - 1 < signature.parameters.size()
          : node.children.size() - 1 != signature.parameters.size())
    error("type", node.span, "indirect call argument count does not match");
  for (std::size_t i = 1; i < node.children.size(); ++i) {
    auto &argument = *node.children[i];
    if (!argument.name.empty())
      error("type", argument.span,
            "indirect callable arguments are positional");
    auto target = i - 1;
    auto expected = target < signature.parameters.size()
                        ? (closure ? inference.value(localVariables.at(
                                         &closure->declaration)[target + 1])
                                   : signature.parameters[target].type)
                        : Type::Unknown;
    if (target < signature.parameters.size())
      contextualize(argument, expected);
    if (target < signature.parameters.size() &&
        signature.parameters[target].mode == ParameterMode::Mut)
      requireMutablePlace(argument);
    auto actual = this->node(argument, reachable);
    if (signature.variadic && target >= signature.parameters.size()) {
      auto type = inference.value(actual);
      if (!cCompatible(*checked.types, type))
        error("signature", argument.span,
              "variadic argument has no C-compatible representation");
      if (!checked.types->isCopy(type) &&
          (argument.kind == Kind::Name || argument.kind == Kind::Field))
        error("ownership", argument.span,
              "variadic non-Copy arguments require explicit take");
    }
    fields(false);
    reachable &= facts(argument).flow.normal;
    facts(node).argumentOrder.push_back(target);
    if (target >= signature.parameters.size())
      continue;
    const auto &formal = signature.parameters[target];
    if ((formal.mode == ParameterMode::Read ||
         formal.mode == ParameterMode::Mut) &&
        borrowCoercion(argument, actual, expected, formal.mode))
      continue;
    auto value = inference.value(actual);
    if ((formal.mode == ParameterMode::Read ||
         formal.mode == ParameterMode::Mut) &&
        checked.types->isView(value) &&
        checked.types->view(value).payload == expected)
      actual = inference.fresh(expected);
    coerce(argument, actual,
           closure ? localVariables.at(&closure->declaration)[target + 1]
                   : inference.fresh(expected),
           argument.span);
  }
  return closure ? functionVariables.at(&closure->declaration)
                 : inference.fresh(signature.result);
}
} // namespace mettle
