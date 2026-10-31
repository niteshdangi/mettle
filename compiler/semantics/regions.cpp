#include "semantics/checker.h"
#include "semantics/region_solver.h"
#include "support/limits.h"
#include "support/path.h"
#include <algorithm>
#include <functional>
#include <regex>
#include <set>
#include <stdexcept>
#include <unordered_set>

namespace mettle {
Type Checker::annotation(const TypeSyntax &syntax, Span span,
                         std::string_view owner) {
  if (syntax.empty())
    return Type::Unknown;
  if (syntax.form == TypeForm::Pinned) {
    auto value = annotation(syntax.elements.at(0), span, owner);
    if (!checked.types->isView(value)) {
      error("feature", span,
            "pinned owning handles require the allocation library; use a "
            "pinned view or inline pinned storage");
      return Type::Unknown;
    }
    return checked.types->structural(AggregateKind::Pin, {value});
  }
  if (syntax.form == TypeForm::Owner) {
    auto payload = annotation(*syntax.nested, span, owner);
    if (payload == Type::Unknown)
      return Type::Unknown;
    if (!checked.types->isSized(payload)) {
      error("feature", span,
            "unsized owner payloads are not implemented yet");
      return Type::Unknown;
    }
    TypeSyntax nominal;
    switch (syntax.ownerKind) {
    case OwnerKind::Heap:
      nominal.name = "alloc::boxed::Box";
      break;
    case OwnerKind::Shared:
      nominal.name = "alloc::arc::Arc";
      break;
    case OwnerKind::LocalShared:
      nominal.name = "alloc::rc::Rc";
      break;
    case OwnerKind::Weak:
      nominal.name = "alloc::arc::Weak";
      break;
    case OwnerKind::LocalWeak:
      nominal.name = "alloc::rc::Weak";
      break;
    }
    GenericArgument argument;
    argument.type = syntax.nested;
    argument.span = span;
    nominal.arguments.push_back(std::move(argument));
    return annotation(nominal, span, owner);
  }
  if (syntax.form == TypeForm::Pointer)
    return checked.types->pointerType(
        annotation(syntax.elements.at(0), span, owner),
        syntax.name == "mut" ? ParameterMode::Mut : ParameterMode::Read);
  if (auto primitive = machineAnnotation(syntax, span, owner))
    return *primitive;
  if (syntax.form == TypeForm::Callable) {
    if (semanticAnnotationDepth)
      return callableRegionAnnotation(syntax, span, owner);
    auto depth = annotationRegionScopes.size();
    if (depth && syntax.callable && !syntax.callable->regions.empty()) {
      auto scope = annotationRegionScopes.back();
      for (const auto &name : syntax.callable->regions)
        scope.names[name] = RegionId::Unspecified;
      annotationRegionScopes.push_back(std::move(scope));
    }
    struct Scope {
      std::vector<AnnotationRegions> &scopes;
      std::size_t depth;
      ~Scope() { scopes.resize(depth); }
    } scope{annotationRegionScopes, depth};
    return callableAnnotation(syntax, span, owner);
  }
  if (auto interface = interfaceAnnotation(syntax, span, owner)) {
    if (checked.types->isConstant(*interface)) {
      error("type", span, "an associated constant cannot be used as a type");
      return Type::Unknown;
    }
    if (annotationRegionScopes.empty())
      semanticRegionAnnotations[&syntax] = *interface;
    return annotationRegionScopes.empty()
               ? checked.types->eraseRegions(*interface)
               : *interface;
  }
  if (syntax.form == TypeForm::Slice)
    return checked.types->sliceType(
        annotation(syntax.elements.at(0), span, owner));
  if (syntax.form != TypeForm::Named) {
    std::vector<Type> components;
    if (syntax.form == TypeForm::Optional)
      components.push_back(annotation(*syntax.nested, span, owner));
    else
      for (const auto &element : syntax.elements)
        components.push_back(annotation(element, span, owner));
    if (syntax.form == TypeForm::Array && syntax.countExpression) {
      auto count = constantType(*syntax.countExpression);
      if (count != Type::Unknown) {
        if (!isInteger(checked.types->parameter(count).valueType)) {
          error("type", span, "array length requires an integer constant");
          return Type::Unknown;
        }
        auto value = checked.types->constantValue(count);
        if ((checked.types->scalarConstantValue(count) && !value) ||
            (value && *value < 0)) {
          error("limit", span, "array length limit exceeded");
          return Type::Unknown;
        }
        return checked.types->arrayType(components.at(0), count);
      }
      return Type::Unknown;
    }
    auto kind = syntax.form == TypeForm::Optional  ? AggregateKind::Optional
                : syntax.form == TypeForm::Outcome ? AggregateKind::Outcome
                : syntax.form == TypeForm::Tuple   ? AggregateKind::Tuple
                                                   : AggregateKind::Array;
    return checked.types->structural(kind, std::move(components), syntax.count);
  }
  if (syntax.nested) {
    auto payload = annotation(*syntax.nested, span, owner);
    return syntax.view.empty()
               ? payload
               : checked.types->viewType(payload,
                                         syntax.view == "read"
                                             ? ParameterMode::Read
                                             : ParameterMode::Mut,
                                         annotationRegion(syntax, span));
  }
  if (auto generic = genericAnnotation(syntax, span, owner))
    return *generic;
  auto resolved = typeName(syntax.name, span, owner);
  if (!typeNames.contains(resolved))
    if (auto alias = aliases.find(resolved); alias != aliases.end()) {
      auto errorsBefore = reportedErrors;
      resolveAlias(alias->second, aliasDepth);
      // The alias already reported why it has no target.
      if (reportedErrors != errorsBefore && !typeNames.contains(resolved))
        return Type::Unknown;
    }
  if (auto type = typeNames.find(resolved); type != typeNames.end()) {
    if (!syntax.view.empty())
      return checked.types->viewType(type->second,
                                     syntax.view == "read" ? ParameterMode::Read
                                                           : ParameterMode::Mut,
                                     annotationRegion(syntax, span));
    return type->second;
  }
  static const std::regex unsupported("([iu](8|16|32|64|128|size)|f(32|64))");
  error(std::regex_match(syntax.name, unsupported) ? "feature" : "name", span,
        "unresolved or inaccessible type '" + displayPath(syntax.name) + "'");
  return Type::Unknown;
}
Type Checker::semanticAnnotation(const TypeSyntax &syntax, Span span,
                                 std::string_view owner) {
  ++semanticAnnotationDepth;
  struct Scope {
    unsigned &depth;
    ~Scope() { --depth; }
  } scope{semanticAnnotationDepth};
  return annotation(syntax, span, owner);
}
std::vector<RegionId>
Checker::pushRegionParameters(const std::vector<GenericParameter> &parameters,
                              Span span) {
  AnnotationRegions scope;
  if (!annotationRegionScopes.empty()) {
    scope.names = annotationRegionScopes.back().names;
    scope.environment = annotationRegionScopes.back().environment;
  } else if (current) {
    const auto &outer = functionRegions(*current);
    scope.names = outer.names;
    scope.environment = outer.environment;
  }
  scope.scope =
      checked.types->regions().binder(scope.environment.universe, true);
  scope.environment.universe = scope.scope.universe;
  std::unordered_set<std::string> names;
  for (const auto &parameter : parameters) {
    if (parameter.kind != GenericParameterKind::Region)
      continue;
    if (!names.insert(parameter.name).second)
      error("name", span,
            "duplicate region parameter '" + parameter.name + "'");
    auto identity = checked.types->regions().rigid(scope.scope, parameter.name);
    scope.names[parameter.name] = identity;
    scope.parameters.push_back(identity);
  }
  annotationRegionScopes.push_back(std::move(scope));
  for (const auto &parameter : parameters) {
    if (parameter.kind != GenericParameterKind::Region)
      continue;
    for (const auto &bound : parameter.bounds) {
      TypeSyntax source;
      source.sources.push_back(bound.name);
      annotationRegionScopes.back().environment.assumptions.push_back(
          {annotationRegionScopes.back().names.at(parameter.name),
           annotationRegion(source, span)});
    }
  }
  return annotationRegionScopes.back().parameters;
}
void Checker::popRegionParameters() {
  if (annotationRegionScopes.empty())
    throw std::logic_error("unbalanced annotation region scope");
  annotationRegionScopes.pop_back();
}
const RegionEnvironment &Checker::regionEnvironment() const {
  if (!annotationRegionScopes.empty())
    return annotationRegionScopes.back().environment;
  if (current)
    if (auto found = functionRegionScopes.find(current);
        found != functionRegionScopes.end())
      return found->second.environment;
  return emptyRegionEnvironment;
}
RegionId Checker::annotationRegion(const TypeSyntax &syntax, Span span) {
  if (annotationRegionScopes.empty())
    return RegionId::Unspecified;
  auto &scope = annotationRegionScopes.back();
  if (syntax.sources.empty()) {
    if (scope.fallback != RegionId::Unspecified)
      return scope.fallback;
    if (scope.boundElision) {
      auto region = checked.types->regions().bound(scope.scope, "<elided>");
      scope.parameters.push_back(region);
      return region;
    }
    return checked.types->regions().inference(scope.scope);
  }
  std::vector<RegionId> sources;
  for (const auto &source : syntax.sources) {
    if (source == "static")
      sources.push_back(RegionId::Static);
    else if (auto found = scope.names.find(source); found != scope.names.end())
      sources.push_back(found->second);
    else {
      error("name", span, "unknown associated region '" + source + "'");
      sources.push_back(RegionId::Unspecified);
    }
  }
  return checked.types->regions().intersection(std::move(sources));
}
RegionId Checker::regionReference(std::string_view name, Span span) {
  if (name == "static")
    return RegionId::Static;
  const AnnotationRegions *scope = nullptr;
  if (!annotationRegionScopes.empty())
    scope = &annotationRegionScopes.back();
  else if (current)
    scope = &functionRegions(*current);
  if (scope)
    if (auto found = scope->names.find(std::string(name));
        found != scope->names.end())
      return found->second;
  if (current && !annotationRegionScopes.empty())
    if (const auto &outer = functionRegions(*current);
        outer.names.contains(std::string(name)))
      return outer.names.at(std::string(name));
  for (const auto &function : module.functions)
    if (&function != current && function.span.source == span.source &&
        function.span.begin <= span.begin && span.end <= function.span.end &&
        functionRegions(function).names.contains(std::string(name))) {
      return functionRegions(function).names.at(std::string(name));
    }
  error("name", span, "unknown region argument '" + std::string(name) + "'");
  return RegionId::Unspecified;
}
void Checker::assumeRegionConstraints(
    const std::vector<GenericConstraint> &constraints, Span span) {
  if (annotationRegionScopes.empty())
    return;
  auto &scope = annotationRegionScopes.back();
  for (const auto &constraint : constraints) {
    auto subject = scope.names.find(constraint.subject.name);
    if (subject == scope.names.end())
      continue;
    for (const auto &bound : constraint.bounds)
      scope.environment.assumptions.push_back(
          {subject->second, regionReference(bound.name, span)});
  }
}
Checker::AnnotationRegions &Checker::functionRegions(const Function &function) {
  if (auto found = functionRegionScopes.find(&function);
      found != functionRegionScopes.end())
    return found->second;
  AnnotationRegions scope;
  // A closure inherits its parent's regions; its copied generic parameters
  // name the same regions and are not new declarations.
  std::unordered_set<std::string> inherited;
  if (auto closure = closureFunctions.find(&function);
      closure != closureFunctions.end()) {
    if (const auto *parent = checked.closureBodies[closure->second]->parent) {
      scope = functionRegions(*parent);
      for (const auto &[name, region] : scope.names)
        inherited.insert(name);
    }
  }
  scope.scope = checked.types->regions().binder(scope.environment.universe);
  auto add = [&](const std::vector<GenericParameter> &parameters,
                 const std::vector<GenericConstraint> &constraints) {
    for (const auto &parameter : parameters) {
      if (parameter.kind != GenericParameterKind::Region ||
          inherited.contains(parameter.name))
        continue;
      auto identity =
          checked.types->regions().bound(scope.scope, parameter.name);
      if (!scope.names.emplace(parameter.name, identity).second)
        error("name", function.span,
              "duplicate region parameter '" + parameter.name + "'");
      else
        scope.parameters.push_back(identity);
    }
    auto reference = [&](const std::string &name) {
      if (name == "static")
        return RegionId::Static;
      if (auto found = scope.names.find(name); found != scope.names.end())
        return found->second;
      error("name", function.span, "unknown outlives region '" + name + "'");
      return RegionId::Unspecified;
    };
    for (const auto &parameter : parameters)
      if (parameter.kind == GenericParameterKind::Region)
        for (const auto &bound : parameter.bounds)
          scope.environment.assumptions.push_back(
              {scope.names.at(parameter.name), reference(bound.name)});
    for (const auto &constraint : constraints)
      if (auto found = scope.names.find(constraint.subject.name);
          found != scope.names.end())
        for (const auto &bound : constraint.bounds)
          scope.environment.assumptions.push_back(
              {found->second, reference(bound.name)});
  };
  bool copiedParameters =
      function.implicitGenericParameters != 0 &&
      (function.implementation >= 0 || !function.interfaceOwner.empty());
  if (copiedParameters)
    add(function.genericParameters, function.constraints);
  if (!copiedParameters && function.implementation >= 0 &&
      static_cast<std::size_t>(function.implementation) <
          module.implementations.size()) {
    const auto &owner = module.implementations[function.implementation];
    add(owner.genericParameters, owner.constraints);
  } else if (function.implementation < 0 && !function.interfaceOwner.empty()) {
    for (const auto &owner : module.interfaces)
      if (owner.name == function.interfaceOwner ||
          definitionName(owner.span, owner.name) ==
              typeName(function.interfaceOwner, function.span)) {
        if (copiedParameters)
          add({}, owner.constraints);
        else
          add(owner.genericParameters, owner.constraints);
        break;
      }
  } else if (!copiedParameters && !function.owner.empty())
    for (const auto &owner : module.products)
      if (owner.name == function.owner ||
          definitionName(owner.span, owner.name) ==
              typeName(function.owner, function.span)) {
        add(owner.genericParameters, owner.constraints);
        break;
      }
  if (!copiedParameters)
    add(function.genericParameters, function.constraints);
  for (const auto &name : function.regions)
    if (!scope.names.contains(name)) {
      auto identity = checked.types->regions().bound(scope.scope, name);
      scope.names.emplace(name, identity);
      scope.parameters.push_back(identity);
    }
  return functionRegionScopes.emplace(&function, std::move(scope))
      .first->second;
}
namespace {
struct RegionContext {
  RegionScope scope;
  RegionEnvironment environment;
  std::unordered_map<std::string, RegionId> names;
  std::unordered_map<std::string, Type> types;
  std::map<Type, Type> arguments{};
};
struct RegionSignature {
  RegionContext context;
  std::vector<Type> parameters;
  std::vector<RegionId> backing;
  Type result = Type::Unknown;
  Type error = Type::Unknown;
  std::vector<RegionId> quantified;
  std::vector<RegionOutlives> obligations;
  bool strict = false;
  Span span;
};
struct RegionSeed {
  RegionScope scope;
  RegionEnvironment environment;
  std::unordered_map<std::string, RegionId> names;
  std::vector<RegionId> parameters;
};
class RegionPass {
public:
  RegionPass(
      const Module &module, std::vector<FunctionFacts> &functions,
      std::unordered_map<const Node *, NodeFacts> &nodes,
      const std::unordered_map<const Pattern *, PatternFacts> &patterns,
      const std::unordered_map<const Node *, IterationPlan> &iterations,
      const std::vector<std::unique_ptr<ClosureFacts>> &closures,
      TypeStore &types, Diagnostics &diagnostics,
      interfaces::Database &interfaceData,
      std::vector<std::pair<Type, const Module::Product *>> products,
      const std::vector<RegionContract> &contracts,
      const std::unordered_map<const TypeSyntax *, Type> &annotations,
      std::vector<RegionSeed> seeds,
      std::function<Type(Type, std::span<const TypeBinding>, std::size_t, Span,
                         const RegionEnvironment &)>
          normalizeContract,
      std::function<Type(Type, Type, Span, const RegionEnvironment &)>
          eraseContract,
      std::function<bool(Type, std::size_t, Span, const RegionEnvironment &)>
          unpinContract)
      : module(module), functions(functions), nodes(nodes), patterns(patterns),
        iterations(iterations), closures(closures), types(types),
        store(types.regions()), solver(store), relations(types, solver),
        diagnostics(diagnostics), interfaceData(interfaceData),
        products(std::move(products)), contracts(contracts),
        annotations(annotations), seeds(std::move(seeds)),
        normalizeContract(std::move(normalizeContract)),
        eraseContract(std::move(eraseContract)),
        unpinContract(std::move(unpinContract)) {}
  void run();

private:
  const Module &module;
  std::vector<FunctionFacts> &functions;
  std::unordered_map<const Node *, NodeFacts> &nodes;
  const std::unordered_map<const Pattern *, PatternFacts> &patterns;
  const std::unordered_map<const Node *, IterationPlan> &iterations;
  const std::vector<std::unique_ptr<ClosureFacts>> &closures;
  TypeStore &types;
  RegionStore &store;
  RegionSolver solver;
  RegionTypeSolver relations;
  Diagnostics &diagnostics;
  interfaces::Database &interfaceData;
  std::vector<std::pair<Type, const Module::Product *>> products;
  const std::vector<RegionContract> &contracts;
  const std::unordered_map<const TypeSyntax *, Type> &annotations;
  std::vector<RegionSeed> seeds;
  std::function<Type(Type, std::span<const TypeBinding>, std::size_t, Span,
                     const RegionEnvironment &)>
      normalizeContract;
  std::function<Type(Type, Type, Span, const RegionEnvironment &)>
      eraseContract;
  std::function<bool(Type, std::size_t, Span, const RegionEnvironment &)>
      unpinContract;
  std::vector<RegionSignature> signatures;
  RegionSignature *current = nullptr;
  const FunctionFacts *currentFacts = nullptr;
  std::size_t currentFunction = 0;
  std::vector<Type> locals;
  std::vector<RegionId> storage;
  std::unordered_map<const Node *, Type> expressions;
  std::unordered_map<const Node *, Type> expressionErrors;
  std::unordered_map<const Node *, Type> expectedClosures;
  std::unordered_map<const Node *, Type> callableAdaptations;
  std::unordered_map<std::uint32_t, CallableType> closureDescriptors;
  std::vector<Type> *inferredReturns = nullptr;
  unsigned captureDepth = 0;
  std::vector<Type> decorating;
  std::vector<Type> substituting;
  std::vector<Type> wellformedActive;
  std::vector<RegionId> protectedInference;
  std::vector<std::pair<Type, Type>> inferringTypes;
  std::vector<std::pair<Type, Type>> inferringArguments;
  using NominalKey = std::tuple<Type, std::vector<RegionId>, std::vector<Type>>;
  struct NominalRegion {
    Type type;
    unsigned state = 0;
  };
  std::map<NominalKey, NominalRegion> nominalRegions;
  std::map<Type, Type> nominalPatterns;
  const NodeFacts &facts(const Node &node) const { return nodes.at(&node); }
  Type originalType(const Node &node) const {
    if (facts(node).opaqueSource != Type::Unknown)
      return facts(node).opaqueSource;
    if (facts(node).erasedSource != Type::Unknown)
      return facts(node).erasedSource;
    if (facts(node).unsizedSource != Type::Unknown)
      return facts(node).unsizedSource;
    if (facts(node).reborrowSource != Type::Unknown)
      return facts(node).reborrowSource;
    return facts(node).type;
  }
  void error(Span span, std::string message, bool limit = false) {
    diagnostics.error(limit ? "limit" : "region", span, std::move(message));
  }
  RegionId source(std::string_view name, RegionContext &context, Span span);
  RegionId sources(const TypeSyntax &syntax, RegionContext &context, Span span,
                   RegionId fallback);
  void declare(RegionContext &context, const std::vector<std::string> &names,
               Span span, std::vector<RegionId> *quantified = nullptr);
  void assumptions(RegionContext &context,
                   const std::vector<GenericParameter> &parameters,
                   const std::vector<GenericConstraint> &constraints,
                   Span span);
  const Module::Product *declaration(Type type) const;
  Type decorate(Type type, const TypeSyntax &syntax, RegionContext &context,
                Span span, RegionId fallback = RegionId::Unspecified,
                bool stored = false);
  Type inferred(Type type, RegionId region);
  Type replace(Type type,
               const std::vector<std::pair<RegionId, RegionId>> &map);
  RegionId replace(RegionId region,
                   const std::vector<std::pair<RegionId, RegionId>> &map);
  void infer(Type actual, Type formal,
             std::vector<std::pair<RegionId, RegionId>> &bindings);
  void infer(RegionId actual, RegionId formal,
             std::vector<std::pair<RegionId, RegionId>> &bindings);
  bool require(Type actual, Type expected, Span span, bool enforce = false,
               Type contract = Type::Unknown);
  void requireArgument(Type actual, Type expected, bool exclusive, Span span,
                       bool enforce, Type contract = Type::Unknown);
  void require(RegionId longer, RegionId shorter, Span span);
  Type merge(Type left, Type right, Span span);
  RegionId backing(const Node &node);
  Type expression(const Node &node);
  Type call(const Node &node, bool operatorIndex = false);
  Type receiver(Type actual, RegionId &location, const ReceiverPlan &plan,
                Span span, bool bounded = false);
  Type closure(const Node &node);
  void expectClosure(const Node &node, Type expected);
  void pattern(const Pattern &pattern, Type type, RegionId region);
  void resultSources(std::size_t index);
  std::vector<RegionId> contained(Type type) const;
  Type signatureType(std::size_t index);
  Type callableBound(Type type, RegionContext &context, Span span);
  void withinBounds(const std::vector<GenericParameter> &parameters,
                    const std::vector<GenericConstraint> &constraints,
                    const std::vector<TypeBinding> &arguments,
                    const RegionContext &declaration,
                    const std::vector<std::pair<RegionId, RegionId>> &bindings,
                    Span span);
  void callableArguments(const std::vector<GenericParameter> &parameters,
                         const std::vector<GenericConstraint> &constraints,
                         const std::vector<TypeBinding> &arguments,
                         RegionContext &declaration, RegionContext &caller,
                         Span span,
                         std::vector<std::pair<RegionId, RegionId>> &bindings);
  void inferArguments(Type pattern, Type actual,
                      std::vector<TypeBinding> &bindings,
                      std::set<Type> &inferred, const std::set<Type> &fixed,
                      Span span);
  Type unsized(Type source, Type target);
  Type erased(Type source, Type target, Span span);
  void wellformed(Type type, Span span, bool indirect = false,
                  bool tail = false, unsigned depth = 0);
};
RegionId RegionPass::source(std::string_view name, RegionContext &context,
                            Span span) {
  if (name == "static")
    return RegionId::Static;
  auto found = context.names.find(std::string(name));
  if (found != context.names.end())
    return found->second;
  error(span, "unknown region or borrowed source '" + std::string(name) + "'");
  return RegionId::Unspecified;
}
RegionId RegionPass::sources(const TypeSyntax &syntax, RegionContext &context,
                             Span span, RegionId fallback) {
  if (syntax.sources.empty())
    return fallback;
  std::vector<RegionId> dependencies;
  for (const auto &name : syntax.sources)
    dependencies.push_back(source(name, context, span));
  return store.intersection(std::move(dependencies));
}
void RegionPass::declare(RegionContext &context,
                         const std::vector<std::string> &names, Span span,
                         std::vector<RegionId> *quantified) {
  for (const auto &name : names) {
    auto region = store.bound(context.scope, name);
    if (!context.names.emplace(name, region).second)
      error(span, "duplicate region parameter '" + name + "'");
    else if (quantified)
      quantified->push_back(region);
  }
}
void RegionPass::assumptions(RegionContext &context,
                             const std::vector<GenericParameter> &parameters,
                             const std::vector<GenericConstraint> &constraints,
                             Span span) {
  auto add = [&](const std::string &name,
                 const std::vector<TypeSyntax> &bounds) {
    auto found = context.names.find(name);
    if (found == context.names.end())
      return;
    for (const auto &bound : bounds)
      context.environment.assumptions.push_back(
          {found->second, source(bound.name, context, span)});
  };
  for (const auto &parameter : parameters)
    if (parameter.kind == GenericParameterKind::Region)
      add(parameter.name, parameter.bounds);
  for (const auto &constraint : constraints)
    add(constraint.subject.name, constraint.bounds);
}
const Module::Product *RegionPass::declaration(Type type) const {
  while (types.isProduct(type)) {
    const auto &record = types.product(type);
    auto next = record.regionOrigin != Type::Unknown ? record.regionOrigin
                                                     : record.genericOrigin;
    if (next == Type::Unknown)
      break;
    type = next;
  }
  for (const auto &[identity, syntax] : products)
    if (identity == type)
      return syntax;
  return nullptr;
}
Type RegionPass::decorate(Type type, const TypeSyntax &syntax,
                          RegionContext &context, Span span, RegionId fallback,
                          bool stored) {
  if (auto found = annotations.find(&syntax); found != annotations.end())
    type = found->second;
  if (type == Type::Unknown || type == Type::Never)
    return type;
  if (!types.isView(type) && !syntax.sources.empty())
    fallback = sources(syntax, context, span, fallback);
  if (syntax.form == TypeForm::Named && !syntax.name.empty()) {
    auto found = context.types.find(syntax.name);
    if (found != context.types.end() && !syntax.nested)
      return found->second;
  }
  if (types.isPointer(type)) {
    auto record = types.pointer(type);
    auto payload = syntax.elements.empty() ? TypeSyntax{} : syntax.elements[0];
    return types.pointerType(
        decorate(record.payload, payload, context, span, fallback, false),
        record.mode);
  }
  if (types.isView(type)) {
    auto record = types.view(type);
    const auto &payload = syntax.nested ? *syntax.nested : TypeSyntax{};
    auto region = sources(
        syntax, context, span,
        record.region == RegionId::Unspecified ? fallback : record.region);
    if (region == RegionId::Unspecified) {
      if (stored)
        diagnostics.error(
            "type", span,
            "nested stored view field requires a declared region source");
      region = store.inference(context.scope);
    }
    record.payload =
        decorate(record.payload, payload, context, span, region, stored);
    return types.viewType(record.payload, record.mode, region);
  }
  if (types.isFunctionPointer(type) && syntax.callable) {
    auto descriptor = types.callable(type);
    if (descriptor.parameters.size() != syntax.callable->parameters.size()) {
      error(span, "incompatible callable bound parameter counts");
      return type;
    }
    auto nested = context;
    nested.scope = store.binder(context.scope.universe);
    nested.environment.universe = nested.scope.universe;
    descriptor.regionParameters.clear();
    descriptor.parameterRegions.clear();
    for (const auto &name : syntax.callable->regions) {
      auto region = store.bound(nested.scope, name);
      nested.names[name] = region;
      descriptor.regionParameters.push_back(region);
    }
    descriptor.regionUniverse = nested.scope.universe;
    for (std::size_t i = 0; i < descriptor.parameters.size(); ++i) {
      auto region = sources(syntax.callable->parameters[i].annotation, nested,
                            span, store.bound(nested.scope, "<parameter>"));
      descriptor.parameterRegions.push_back(region);
      if (!syntax.callable->parameters[i].name.empty())
        nested.names[syntax.callable->parameters[i].name] = region;
      descriptor.parameters[i].type =
          decorate(descriptor.parameters[i].type,
                   syntax.callable->parameters[i].annotation, nested, span,
                   region, stored);
      if ((descriptor.parameters[i].mode == ParameterMode::Read ||
           descriptor.parameters[i].mode == ParameterMode::Mut ||
           types.containsViews(descriptor.parameters[i].type)) &&
          store.get(region).kind == RegionKind::Bound &&
          store.get(region).binder == nested.scope.binder &&
          std::find(descriptor.regionParameters.begin(),
                    descriptor.regionParameters.end(),
                    region) == descriptor.regionParameters.end())
        descriptor.regionParameters.push_back(region);
    }
    descriptor.result = decorate(
        descriptor.result, syntax.callable->result, nested, span,
        descriptor.parameterRegions.size() == 1 ? descriptor.parameterRegions[0]
                                                : fallback,
        stored);
    descriptor.error = decorate(
        descriptor.error, syntax.callable->error, nested, span,
        descriptor.parameterRegions.size() == 1 ? descriptor.parameterRegions[0]
                                                : fallback,
        stored);
    descriptor.abiResult = descriptor.result;
    return types.callableType(std::move(descriptor));
  }
  if (types.isSlice(type)) {
    const auto &element =
        syntax.elements.empty() ? TypeSyntax{} : syntax.elements[0];
    return types.sliceType(decorate(types.slice(type).element, element, context,
                                    span, fallback, stored));
  }
  if (!types.isProduct(type))
    return type;
  if (types.product(type).kind == AggregateKind::Ref ||
      types.product(type).kind == AggregateKind::RefMut) {
    auto kind = types.product(type).kind;
    auto owner = types.view(types.product(type).fields[0].type).payload;
    auto payload = types.product(owner)
                       .fields[cellPayloadField(types.product(owner).kind)]
                       .type;
    const auto *argument =
        syntax.arguments.empty() ? nullptr : syntax.arguments[0].type.get();
    payload = decorate(payload, argument ? *argument : TypeSyntax{}, context,
                       span, fallback, stored);
    auto lifetime = sources(syntax, context, span, fallback);
    if (lifetime == RegionId::Unspecified) {
      if (stored)
        diagnostics.error(
            "type", span,
            "stored borrow guard requires a declared region source");
      lifetime = store.inference(context.scope);
    }
    return types.structural(
        kind,
        {types.viewType(types.structural(AggregateKind::RefCell, {payload}),
                        ParameterMode::Read, lifetime)});
  }
  if (decorating.size() > limits::typeDepth) {
    error(span, "region well-formedness nesting limit exceeded", true);
    return type;
  }
  decorating.push_back(type);
  auto record = types.product(type);
  auto fields = record.fields;
  std::vector<RegionId> arguments;
  Type result = Type::Unknown;
  if (const auto *product = declaration(type)) {
    auto origin = type;
    while (types.product(origin).regionOrigin != Type::Unknown)
      origin = types.product(origin).regionOrigin;
    if (types.product(origin).genericOrigin != Type::Unknown)
      origin = types.product(origin).genericOrigin;
    auto nested = context;
    for (const auto &name : product->regions)
      nested.names.erase(name);
    std::vector<std::string> regionNames = syntax.regions;
    if (regionNames.empty())
      for (const auto &argument : syntax.arguments)
        if (!argument.region.empty())
          regionNames.push_back(argument.region);
    if (!regionNames.empty() && regionNames.size() != product->regions.size()) {
      error(span, "region argument count does not match type '" +
                      product->name + "'");
    }
    for (std::size_t i = 0; i < product->regions.size(); ++i) {
      auto argument =
          i < regionNames.size() ? source(regionNames[i], context, span)
          : fallback != RegionId::Unspecified ? fallback
                                              : store.inference(context.scope);
      arguments.push_back(argument);
      nested.names[product->regions[i]] = argument;
    }
    std::size_t argumentIndex = 0, typeIndex = 0;
    std::vector<Type> typeArguments;
    auto parameters = types.product(origin).genericParameters;
    for (const auto &parameter : product->genericParameters) {
      if (parameter.kind == GenericParameterKind::Region)
        continue;
      while (argumentIndex < syntax.arguments.size() &&
             !syntax.arguments[argumentIndex].region.empty())
        ++argumentIndex;
      if (typeIndex < parameters.size()) {
        auto argument = typeIndex < record.genericArguments.size()
                            ? record.genericArguments[typeIndex]
                            : parameters[typeIndex];
        if (auto actual = context.arguments.find(parameters[typeIndex]);
            actual != context.arguments.end())
          argument = actual->second;
        else if (argumentIndex < syntax.arguments.size() &&
                 syntax.arguments[argumentIndex].type)
          argument = decorate(argument, *syntax.arguments[argumentIndex].type,
                              context, span, fallback, stored);
        else if (syntax.form == TypeForm::Owner && typeIndex == 0 &&
                 syntax.nested)
          argument =
              decorate(argument, *syntax.nested, context, span, fallback,
                       stored);
        else
          argument = inferred(argument, store.inference(context.scope));
        nested.types[parameter.name] = argument;
        typeArguments.push_back(argument);
      }
      ++typeIndex;
      ++argumentIndex;
    }
    auto base = type;
    while (types.product(base).regionOrigin != Type::Unknown)
      base = types.product(base).regionOrigin;
    NominalKey key{base, arguments, typeArguments};
    auto found = nominalRegions.find(key);
    if (found != nominalRegions.end() && found->second.state != 0) {
      decorating.pop_back();
      return found->second.type;
    }
    if (found == nominalRegions.end()) {
      auto pattern = nominalPatterns.find(origin);
      auto shell = types.regionalShell(
          base, arguments, typeArguments,
          pattern == nominalPatterns.end() ? Type::Unknown : pattern->second);
      found =
          nominalRegions.emplace(std::move(key), NominalRegion{shell}).first;
    }
    found->second.state = 1;
    result = found->second.type;
    nested.types["Self"] = result;
    std::size_t field = product->enumeration ? 1 : 0;
    auto member = [&](const Parameter &parameter) {
      if (field < fields.size()) {
        fields[field].type = decorate(fields[field].type, parameter.annotation,
                                      nested, parameter.span, fallback, true);
        ++field;
      }
    };
    if (product->enumeration) {
      for (const auto &variant : product->variants)
        for (const auto &parameter : variant.fields)
          member(parameter);
    } else
      for (const auto &parameter : product->fields)
        member(parameter);
    auto obligations = nested;
    obligations.environment.assumptions.clear();
    assumptions(obligations, product->genericParameters, product->constraints,
                span);
    for (const auto &edge : obligations.environment.assumptions) {
      auto answer =
          solver.outlives(edge.longer, edge.shorter, context.environment);
      if (answer != RegionAnswer::Proven)
        error(span,
              "type region arguments do not satisfy declared outlives "
              "constraints",
              answer == RegionAnswer::Inconclusive);
    }
    types.defineProduct(result, std::move(fields));
    found->second.state = 2;
    std::vector<TypeBinding> bindings;
    for (std::size_t i = 0; i < parameters.size() && i < typeArguments.size();
         ++i)
      bindings.push_back({parameters[i], typeArguments[i]});
    std::vector<std::pair<RegionId, RegionId>> regions;
    callableArguments(product->genericParameters, product->constraints,
                      bindings, nested, context, span, regions);
    if (!regions.empty())
      result = replace(result, regions);
    decorating.pop_back();
    return result;
  } else {
    std::vector<Type> components;
    for (std::size_t index = 0; index < record.components.size(); ++index) {
      const TypeSyntax *element = nullptr;
      if (syntax.form == TypeForm::Optional && syntax.nested)
        element = syntax.nested.get();
      else if (!syntax.elements.empty())
        element =
            &syntax.elements[record.kind == AggregateKind::Array
                                 ? 0
                                 : std::min(index, syntax.elements.size() - 1)];
      else if (index < syntax.arguments.size() && syntax.arguments[index].type)
        element = syntax.arguments[index].type.get();
      components.push_back(decorate(record.components[index],
                                    element ? *element : TypeSyntax{}, context,
                                    span, fallback, stored));
    }
    if (!components.empty() && record.kind != AggregateKind::Opaque) {
      result = record.kind == AggregateKind::Array &&
                       record.arrayCount != Type::Unknown
                   ? types.arrayType(components[0], record.arrayCount)
                   : types.structural(
                         record.kind, std::move(components),
                         static_cast<std::uint32_t>(record.fields.size()));
    } else {
      for (auto &field : fields)
        if (field.name != "<tag>")
          field.type = decorate(field.type, TypeSyntax{}, context, span,
                                fallback, stored);
    }
  }
  decorating.pop_back();
  return result == Type::Unknown
             ? types.regionalProduct(type, std::move(fields),
                                     std::move(arguments))
             : result;
}
Type RegionPass::inferred(Type type, RegionId region) {
  if (!requiresRegionProof(type, types))
    return type;
  if (std::find(decorating.begin(), decorating.end(), type) != decorating.end())
    return type;
  decorating.push_back(type);
  auto result = type;
  if (types.isView(type)) {
    auto view = types.view(type);
    result = types.viewType(inferred(view.payload, region), view.mode, region);
  } else if (types.isProduct(type)) {
    const auto record = types.product(type);
    if (record.kind == AggregateKind::Array && !record.components.empty()) {
      auto element = inferred(record.components[0], region);
      result = record.arrayCount == Type::Unknown
                   ? types.structural(AggregateKind::Array, {element},
                                      record.fields.size())
                   : types.arrayType(element, record.arrayCount);
    } else {
      auto fields = record.fields;
      for (auto &field : fields)
        field.type = inferred(field.type, region);
      result = types.regionalProduct(type, std::move(fields), {});
    }
  }
  decorating.pop_back();
  return result;
}
RegionId
RegionPass::replace(RegionId region,
                    const std::vector<std::pair<RegionId, RegionId>> &map) {
  for (const auto &[parameter, argument] : map)
    if (parameter == region)
      return argument;
  const auto &record = store.get(region);
  if (record.kind == RegionKind::Intersection) {
    auto sources = record.sources;
    for (auto &source : sources)
      source = replace(source, map);
    return store.intersection(std::move(sources));
  }
  return region;
}
Type RegionPass::replace(
    Type type, const std::vector<std::pair<RegionId, RegionId>> &map) {
  if (map.empty())
    return type;
  if (!types.isFunctionPointer(type)) {
    std::vector<RegionBinding> bindings;
    for (const auto &[parameter, argument] : map)
      bindings.push_back({parameter, argument});
    return types.substituteRegions(type, bindings);
  }
  if (std::find(substituting.begin(), substituting.end(), type) !=
      substituting.end())
    return type;
  substituting.push_back(type);
  auto result = type;
  if (types.isProjection(type)) {
    std::vector<RegionBinding> bindings;
    for (const auto &[parameter, argument] : map)
      bindings.push_back({parameter, argument});
    result = types.substituteRegions(type, bindings);
  } else if (types.isView(type)) {
    auto view = types.view(type);
    result = types.viewType(replace(view.payload, map), view.mode,
                            replace(view.region, map));
  } else if (types.isProduct(type)) {
    auto record = types.product(type);
    for (auto &field : record.fields)
      field.type = replace(field.type, map);
    for (auto &argument : record.regionArguments)
      argument = replace(argument, map);
    auto origin =
        record.regionOrigin == Type::Unknown ? type : record.regionOrigin;
    result = types.regionalProduct(origin, std::move(record.fields),
                                   std::move(record.regionArguments));
  } else if (types.isFunctionPointer(type)) {
    auto descriptor = types.callable(type);
    for (auto &parameter : descriptor.parameters)
      parameter.type = replace(parameter.type, map);
    descriptor.result = replace(descriptor.result, map);
    descriptor.error = replace(descriptor.error, map);
    for (auto &region : descriptor.parameterRegions)
      region = replace(region, map);
    for (auto &requirement : descriptor.regionRequirements) {
      requirement.longer = replace(requirement.longer, map);
      requirement.shorter = replace(requirement.shorter, map);
    }
    descriptor.abiResult = descriptor.result;
    result = types.callableType(std::move(descriptor));
  }
  substituting.pop_back();
  return result;
}
void RegionPass::infer(RegionId actual, RegionId formal,
                       std::vector<std::pair<RegionId, RegionId>> &bindings) {
  if (store.get(formal).kind != RegionKind::Inference ||
      actual == RegionId::Unspecified ||
      std::find(protectedInference.begin(), protectedInference.end(), actual) !=
          protectedInference.end())
    return;
  for (auto &binding : bindings)
    if (binding.first == formal) {
      binding.second = store.intersection({binding.second, actual});
      return;
    }
  bindings.emplace_back(formal, actual);
}
void RegionPass::infer(Type actual, Type formal,
                       std::vector<std::pair<RegionId, RegionId>> &bindings) {
  if (actual == formal)
    return;
  auto pair = std::pair{actual, formal};
  if (std::find(inferringTypes.begin(), inferringTypes.end(), pair) !=
      inferringTypes.end())
    // A cycle through a recursive type (a function-pointer result naming its
    // own aggregate) revisits a pair whose bindings are already being
    // collected by the active frame; repeating it adds nothing.
    return;
  inferringTypes.push_back(pair);
  struct Pop {
    std::vector<std::pair<Type, Type>> &active;
    ~Pop() { active.pop_back(); }
  } pop{inferringTypes};
  if (types.isView(actual) && types.isView(formal)) {
    auto from = types.view(actual), to = types.view(formal);
    infer(from.region, to.region, bindings);
    infer(from.payload, to.payload, bindings);
  } else if (types.isErased(actual) && types.isErased(formal)) {
    const auto from = types.erased(actual), to = types.erased(formal);
    if (from.declaration == to.declaration) {
      for (std::size_t p = 0;
           p < from.regionArguments.size() && p < to.regionArguments.size();
           ++p)
        infer(from.regionArguments[p], to.regionArguments[p], bindings);
      for (std::size_t p = 0;
           p < from.arguments.size() && p < to.arguments.size(); ++p)
        infer(from.arguments[p], to.arguments[p], bindings);
    }
  } else if (types.isProduct(actual) && types.isProduct(formal)) {
    auto from = types.product(actual), to = types.product(formal);
    if (from.kind == AggregateKind::Array && to.kind == AggregateKind::Array &&
        from.components.size() == 1 && to.components.size() == 1) {
      infer(from.components[0], to.components[0], bindings);
      return;
    }
    // Same nominal origins keep their region arguments aligned even when a
    // specialization has a different erased region pattern.
    const bool sameOrigin = from.regionOrigin != Type::Unknown &&
                            from.regionOrigin == to.regionOrigin;
    const bool samePattern = from.regionPattern != Type::Unknown &&
                             from.regionPattern == to.regionPattern;
    if ((sameOrigin || samePattern) &&
        from.regionArguments.size() == to.regionArguments.size() &&
        from.genericArguments.size() == to.genericArguments.size()) {
      for (std::size_t i = 0; i < from.regionArguments.size(); ++i)
        infer(from.regionArguments[i], to.regionArguments[i], bindings);
      for (std::size_t i = 0; i < from.genericArguments.size(); ++i)
        infer(from.genericArguments[i], to.genericArguments[i], bindings);
      return;
    }
    if (from.fields.size() == to.fields.size())
      for (std::size_t i = 0; i < from.fields.size(); ++i)
        infer(from.fields[i].type, to.fields[i].type, bindings);
  } else if (types.isFunctionPointer(actual) &&
             types.isFunctionPointer(formal)) {
    auto from = types.callable(actual), to = types.callable(formal);
    auto protectedCount = protectedInference.size();
    protectedInference.insert(protectedInference.end(),
                              from.regionParameters.begin(),
                              from.regionParameters.end());
    for (std::size_t i = 0;
         i < from.parameters.size() && i < to.parameters.size(); ++i) {
      infer(from.parameters[i].type, to.parameters[i].type, bindings);
      if (i < from.parameterRegions.size() && i < to.parameterRegions.size())
        infer(from.parameterRegions[i], to.parameterRegions[i], bindings);
    }
    infer(from.result, to.result, bindings);
    infer(from.error, to.error, bindings);
    protectedInference.resize(protectedCount);
  }
}
// `contract` is the declared type before call-site region bindings: a region
// inferred as `static` from an argument is not a declared `static` contract.
bool RegionPass::require(Type actual, Type expected, Span span, bool enforce,
                         Type contract) {
  bool callable = types.isFunctionPointer(expected);
  auto dependencies =
      contained(contract == Type::Unknown ? expected : contract);
  bool staticContract = std::find(dependencies.begin(), dependencies.end(),
                                  RegionId::Static) != dependencies.end();
  if (!current->strict && !enforce && !callable && !staticContract)
    return true;
  auto result =
      relations.coerce(actual, expected, current->context.environment);
  if (result != RegionAnswer::Proven)
    error(span,
          result == RegionAnswer::Inconclusive
              ? "region constraint solving is inconclusive"
              : "view region or invariant payload does not satisfy its "
                "declared relationship",
          result == RegionAnswer::Inconclusive);
  return result == RegionAnswer::Proven;
}
// An exclusive argument is invariant: the reverse relation is checked only
// once the forward one holds, so a violation is reported a single time.
void RegionPass::requireArgument(Type actual, Type expected, bool exclusive,
                                 Span span, bool enforce, Type contract) {
  if (require(actual, expected, span, enforce, contract) && exclusive)
    require(expected, actual, span, enforce, contract);
}
void RegionPass::require(RegionId longer, RegionId shorter, Span span) {
  auto result = solver.outlives(longer, shorter, current->context.environment);
  if (result != RegionAnswer::Proven)
    error(span,
          result == RegionAnswer::Inconclusive
              ? "outlives constraint solving is inconclusive"
              : "borrowed source does not outlive the required region",
          result == RegionAnswer::Inconclusive);
}
Type RegionPass::merge(Type left, Type right, Span span) {
  if (left == right || right == Type::Never)
    return left;
  if (left == Type::Never)
    return right;
  if (types.isView(left) && types.isView(right)) {
    auto a = types.view(left), b = types.view(right);
    auto payload = a.payload;
    if (a.mode == ParameterMode::Mut) {
      require(a.payload, b.payload, span);
      require(b.payload, a.payload, span);
    } else
      payload = merge(a.payload, b.payload, span);
    return types.viewType(payload, a.mode,
                          store.intersection({a.region, b.region}));
  }
  if (types.isProduct(left) && types.isProduct(right)) {
    auto a = types.product(left), b = types.product(right);
    if (a.kind == AggregateKind::Array && b.kind == AggregateKind::Array &&
        a.arrayCount == b.arrayCount && a.fields.size() == b.fields.size()) {
      auto element = merge(a.components[0], b.components[0], span);
      return a.arrayCount == Type::Unknown
                 ? types.structural(AggregateKind::Array, {element},
                                    a.fields.size())
                 : types.arrayType(element, a.arrayCount);
    }
    if (a.fields.size() == b.fields.size()) {
      for (std::size_t i = 0; i < a.fields.size(); ++i)
        a.fields[i].type = merge(a.fields[i].type, b.fields[i].type, span);
      auto origin = a.regionOrigin == Type::Unknown ? left : a.regionOrigin;
      return types.regionalProduct(origin, std::move(a.fields), {});
    }
  }
  return left;
}
RegionId RegionPass::backing(const Node &node) {
  if (node.kind == Kind::Group || node.kind == Kind::Field ||
      node.kind == Kind::Index) {
    auto type = expression(*node.children[0]);
    if (types.isView(type))
      return types.view(type).region;
    return backing(*node.children[0]);
  }
  if (node.kind == Kind::Unary && node.text == "*") {
    auto type = expression(*node.children[0]);
    if (types.isView(type))
      return types.view(type).region;
    // A dereferenced raw pointer is unbounded: the unsafe code asserts that
    // the referent lives as long as the borrow it creates.
    if (types.isPointer(type))
      return RegionId::Static;
  }
  if (facts(node).slot >= 0 &&
      static_cast<std::size_t>(facts(node).slot) < storage.size())
    return storage[facts(node).slot];
  return store.local(current->context.scope);
}
void RegionPass::pattern(const Pattern &syntax, Type type, RegionId region) {
  auto found = patterns.find(&syntax);
  if (found == patterns.end())
    return;
  if (found->second.slot >= 0 &&
      static_cast<std::size_t>(found->second.slot) < locals.size()) {
    auto slot = static_cast<std::size_t>(found->second.slot);
    locals[slot] = type;
    if (types.isView(currentFacts->locals[slot].type) && !types.isView(type))
      locals[slot] = types.viewType(
          type, types.view(currentFacts->locals[slot].type).mode, region);
    storage[slot] = region;
  }
  for (std::size_t i = 0; i < syntax.children.size(); ++i) {
    auto child = type;
    while (types.isView(child))
      child = types.view(child).payload;
    if (types.isProduct(child)) {
      auto field = i < found->second.fields.size()
                       ? found->second.fields[i]
                       : static_cast<std::uint32_t>(i);
      if (field < types.product(child).fields.size())
        child = types.product(child).fields[field].type;
    }
    pattern(syntax.children[i], child, region);
  }
}
Type RegionPass::receiver(Type actual, RegionId &location,
                          const ReceiverPlan &plan, Span span, bool bounded) {
  while (types.isView(actual) &&
         types.eraseRegions(actual) != types.eraseRegions(plan.source)) {
    location = types.view(actual).region;
    actual = types.view(actual).payload;
    bounded = true;
  }
  for (const auto &step : plan.steps) {
    if (step.kind == ReceiverStep::Kind::Native) {
      if (!types.isView(actual)) {
        error(span, "receiver plan requires a view at its native dereference");
        return inferred(plan.target, location);
      }
      const auto view = types.view(actual);
      location =
          bounded ? store.intersection({location, view.region}) : view.region;
      actual = view.payload;
      bounded = true;
      continue;
    }
    if (step.kind == ReceiverStep::Kind::Unsize) {
      actual = unsized(actual, step.target);
      bounded = true;
      continue;
    }
    if (step.kind == ReceiverStep::Kind::Erase) {
      actual = step.target;
      bounded = true;
      continue;
    }
    if (step.callee < 0 ||
        static_cast<std::size_t>(step.callee) >= signatures.size()) {
      error(span, "receiver projection has no checked signature");
      return inferred(plan.target, location);
    }
    auto callee = static_cast<std::size_t>(step.callee);
    const auto &signature = signatures[callee];
    if (signature.parameters.size() != 1 || signature.backing.empty()) {
      error(span, "receiver projection has an incompatible checked signature");
      return inferred(plan.target, location);
    }
    std::vector<std::pair<RegionId, RegionId>> substitution, bindings;
    for (auto region : signature.quantified)
      substitution.emplace_back(region,
                                store.inference(current->context.scope));
    for (auto region : signature.backing)
      if (store.get(region).kind == RegionKind::Bound &&
          std::none_of(substitution.begin(), substitution.end(),
                       [&](auto entry) { return entry.first == region; }))
        substitution.emplace_back(region,
                                  store.inference(current->context.scope));
    std::vector<TypeBinding> typesBound;
    for (std::size_t i = 0; i < functions[callee].genericParameters.size() &&
                            i < step.typeArguments.size();
         ++i)
      typesBound.push_back(
          {functions[callee].genericParameters[i], step.typeArguments[i]});
    std::set<Type> inferredParameters, fixedParameters;
    inferArguments(signature.parameters[0], actual, typesBound,
                   inferredParameters, fixedParameters, span);
    auto descriptor = types.substitute(
        replace(signatureType(callee), substitution), typesBound);
    descriptor = normalizeContract(descriptor, {}, currentFunction, span,
                                   current->context.environment);
    const auto call = types.callable(descriptor);
    auto formal = call.parameters[0].type;
    infer(actual, formal, bindings);
    infer(location, replace(signature.backing[0], substitution), bindings);
    for (std::size_t pass = 0; pass <= signature.obligations.size(); ++pass) {
      bool changed = false;
      for (auto edge : signature.obligations) {
        auto shorter = replace(edge.shorter, substitution);
        auto longer = replace(replace(edge.longer, substitution), bindings);
        if (store.get(shorter).kind == RegionKind::Inference &&
            store.get(longer).kind != RegionKind::Inference) {
          auto previous = replace(shorter, bindings);
          infer(longer, shorter, bindings);
          changed |= previous != replace(shorter, bindings);
        }
      }
      if (!changed)
        break;
    }
    for (const auto &[variable, value] : bindings) {
      auto environment = current->context.environment;
      auto answer = solver.instantiate(variable, value, environment);
      if (answer != RegionAnswer::Proven)
        error(span, "receiver projection region would escape its binder",
              answer == RegionAnswer::Inconclusive);
    }
    for (auto edge : signature.obligations)
      require(replace(replace(edge.longer, substitution), bindings),
              replace(replace(edge.shorter, substitution), bindings), span);
    require(location,
            replace(replace(signature.backing[0], substitution), bindings),
            span);
    formal = replace(formal, bindings);
    require(actual, formal, span, true);
    if (step.mode == ParameterMode::Mut)
      require(formal, actual, span, true);
    auto result = replace(call.result, bindings);
    if (!types.isView(result)) {
      error(span, "receiver projection does not return a view");
      return inferred(plan.target, location);
    }
    const auto view = types.view(result);
    location = view.region;
    actual = view.payload;
    bounded = true;
  }
  return actual;
}
Type RegionPass::call(const Node &node, bool operatorIndex) {
  const bool receiverCall = facts(node).method || operatorIndex;
  const auto parameterForArgument = [&](std::size_t argument) {
    if (operatorIndex)
      return argument + 1;
    return argument < facts(node).argumentOrder.size()
               ? facts(node).argumentOrder[argument]
               : argument;
  };
  std::optional<Type> methodReceiver;
  RegionId methodLocation = RegionId::Unspecified;
  if (receiverCall && !node.children.empty() &&
      (operatorIndex || !node.children[0]->children.empty())) {
    const auto &syntax =
        operatorIndex ? *node.children[0] : *node.children[0]->children[0];
    auto actual = expression(syntax);
    methodLocation = backing(syntax);
    if (facts(node).optional) {
      while (types.isView(actual)) {
        methodLocation = types.view(actual).region;
        actual = types.view(actual).payload;
      }
      if (types.isProduct(actual) &&
          types.product(actual).kind == AggregateKind::Optional &&
          types.product(actual).fields.size() > 1)
        actual = types.product(actual).fields[1].type;
      if (actual == Type::Never && facts(node).receiverPlan)
        actual = inferred(facts(node).receiverPlan->source, methodLocation);
    }
    if (facts(node).receiverPlan)
      actual = receiver(actual, methodLocation, *facts(node).receiverPlan,
                        node.span);
    methodReceiver = actual;
  }
  if (facts(node).callee >= 0 &&
      static_cast<std::size_t>(facts(node).callee) < signatures.size()) {
    const auto &signature = signatures[facts(node).callee];
    std::vector<TypeBinding> checkedArguments;
    const auto &generics =
        functions[static_cast<std::size_t>(facts(node).callee)]
            .genericParameters;
    for (std::size_t i = 0;
         i < generics.size() && i < facts(node).typeArguments.size(); ++i)
      checkedArguments.push_back({generics[i], facts(node).typeArguments[i]});
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      auto parameter = operatorIndex ? i
                       : i - 1 < facts(node).argumentOrder.size()
                           ? facts(node).argumentOrder[i - 1]
                           : i - 1;
      if (parameter >= signature.parameters.size())
        continue;
      auto formal = signature.parameters[parameter];
      // A higher-ranked callable bound gives the closure its binder.
      if (types.isParameter(formal) &&
          types.parameter(formal).callableConstraint != Type::Unknown) {
        const auto &callee = module.functions[facts(node).callee];
        const auto &name = types.parameter(formal).name;
        const TypeSyntax *found = nullptr;
        auto scan = [&](const std::vector<TypeSyntax> &bounds) {
          for (const auto &bound : bounds)
            if (bound.form == TypeForm::Callable && bound.callable &&
                !bound.callable->regions.empty())
              found = &bound;
        };
        for (const auto &generic : callee.genericParameters)
          if (generic.name == name)
            scan(generic.bounds);
        for (const auto &constraint : callee.constraints)
          if (constraint.subject.name == name)
            scan(constraint.bounds);
        if (found) {
          auto context = signature.context;
          formal = decorate(types.parameter(formal).callableConstraint, *found,
                            context, node.span);
        }
      }
      expectClosure(*node.children[i],
                    types.substitute(formal, checkedArguments));
    }
  } else if (facts(node).indirect) {
    auto callable = expression(*node.children[0]);
    while (types.isView(callable))
      callable = types.view(callable).payload;
    if (types.isCallable(callable)) {
      auto descriptor = types.callable(callable);
      if (auto found = closureDescriptors.find(callable.index());
          found != closureDescriptors.end())
        descriptor = found->second;
      for (std::size_t i = 1;
           i < node.children.size() && i <= descriptor.parameters.size(); ++i)
        expectClosure(*node.children[i], descriptor.parameters[i - 1].type);
    }
  }
  std::vector<Type> arguments;
  std::vector<RegionId> argumentLocations;
  for (std::size_t i = 1; i < node.children.size(); ++i) {
    auto actual = expression(*node.children[i]);
    auto location = backing(*node.children[i]);
    if (facts(*node.children[i]).borrowConversion)
      actual =
          receiver(actual, location, *facts(*node.children[i]).borrowConversion,
                   node.children[i]->span);
    arguments.push_back(actual);
    argumentLocations.push_back(location);
  }
  if (facts(node).machineOperation.starts_with("pin.")) {
    auto method = std::string_view(facts(node).machineOperation).substr(4);
    auto validate = [&](Type subject) {
      if (types.isUnpin(subject))
        return;
      if (!unpinContract(subject, currentFunction, node.span,
                         current->context.environment))
        diagnostics.error("type", node.span,
                          "unsatisfied Unpin condition after region checking");
      nodes.at(&node).unpinRequirements = {subject};
    };
    if (method == "inline")
      return types.structural(
          AggregateKind::Pin,
          {types.viewType(arguments.at(0), ParameterMode::Mut,
                          store.local(current->context.scope))});
    if (method == "new" || method == "new_unchecked") {
      auto view = arguments.at(0);
      if (method == "new")
        validate(types.view(view).payload);
      return types.structural(AggregateKind::Pin, {view});
    }
    auto owner = methodReceiver.value_or(Type::Unknown);
    while (types.isView(owner))
      owner = types.view(owner).payload;
    if (!types.isProduct(owner) ||
        types.product(owner).kind != AggregateKind::Pin)
      return originalType(node);
    auto view = types.product(owner).fields[0].type;
    auto payload = types.view(view).payload;
    if (method == "get_mut" || method == "into_inner")
      validate(payload);
    if (method == "into_inner" || method == "into_inner_unchecked")
      return view;
    if (method.starts_with("project.") && types.isProduct(payload))
      payload = types.product(payload).fields.at(facts(node).field).type;
    auto result = originalType(node);
    bool wrapped = types.isProduct(result);
    auto mode =
        types.view(wrapped ? types.product(result).fields[0].type : result)
            .mode;
    auto projected = types.viewType(payload, mode, types.view(view).region);
    return wrapped ? types.structural(AggregateKind::Pin, {projected})
                   : projected;
  }
  if (facts(node).machineOperation.starts_with("cell.")) {
    auto method = std::string_view(facts(node).machineOperation).substr(5);
    if (method == "new")
      return types.structural(types.product(originalType(node)).kind,
                              {arguments.at(0)});
    auto owner = methodReceiver.value_or(Type::Unknown);
    while (types.isView(owner)) {
      methodLocation = types.view(owner).region;
      owner = types.view(owner).payload;
    }
    if (!types.isProduct(owner))
      return originalType(node);
    auto kind = types.product(owner).kind;
    bool guard = kind == AggregateKind::Ref || kind == AggregateKind::RefMut;
    if (guard && method == "clone")
      return types.structural(AggregateKind::Ref,
                              {types.product(owner).fields[0].type});
    auto cell =
        guard ? types.view(types.product(owner).fields[0].type).payload : owner;
    auto payload = types.product(cell)
                       .fields[cellPayloadField(types.product(cell).kind)]
                       .type;
    if (method == "get_ref" || method == "get_mut")
      return types.viewType(payload,
                            method == "get_mut" ? ParameterMode::Mut
                                                : ParameterMode::Read,
                            methodLocation);
    if (method == "as_ptr")
      return types.pointerType(payload, ParameterMode::Mut);
    if (method == "get" || method == "into_inner")
      return payload;
    if (method == "replace" || method == "set") {
      require(arguments.at(0), payload, node.span);
      return method == "replace" ? payload : Type::Unit;
    }
    if (method == "swap") {
      auto other = arguments.at(0);
      while (types.isView(other))
        other = types.view(other).payload;
      require(other, cell, node.span);
      return Type::Unit;
    }
    bool exclusive = method.ends_with("_mut");
    auto result = types.structural(
        exclusive ? AggregateKind::RefMut : AggregateKind::Ref,
        {types.viewType(cell, ParameterMode::Read, methodLocation)});
    if (method.starts_with("try_"))
      result = types.structural(
          AggregateKind::Outcome,
          {result, types.structural(exclusive ? AggregateKind::BorrowMutError
                                              : AggregateKind::BorrowError,
                                    {})});
    return result;
  }
  if (facts(node).indirect) {
    auto callable = expression(*node.children[0]);
    while (types.isView(callable))
      callable = types.view(callable).payload;
    if (types.isParameter(callable) && types.isCallable(callable))
      callable = callableBound(callable, current->context, node.span);
    if (!types.isCallable(callable))
      return facts(node).type;
    auto descriptor = types.callable(callable);
    bool semanticClosure = false;
    if (auto found = closureDescriptors.find(callable.index());
        found != closureDescriptors.end()) {
      descriptor = found->second;
      semanticClosure = true;
    }
    std::vector<std::pair<RegionId, RegionId>> substitution, bindings;
    std::vector<RegionOutlives> argumentLifetimes;
    for (auto parameter : descriptor.regionParameters)
      substitution.emplace_back(parameter,
                                store.inference(current->context.scope));
    for (auto &formal : descriptor.parameters)
      formal.type = replace(formal.type, substitution);
    descriptor.result = replace(descriptor.result, substitution);
    descriptor.error = replace(descriptor.error, substitution);
    for (auto &region : descriptor.parameterRegions)
      region = replace(region, substitution);
    for (std::size_t i = 0;
         i < arguments.size() && i < descriptor.parameters.size(); ++i) {
      auto actual = arguments[i];
      auto region = argumentLocations[i];
      bool borrowed = descriptor.parameters[i].mode == ParameterMode::Read ||
                      descriptor.parameters[i].mode == ParameterMode::Mut;
      if (!facts(*node.children[i + 1]).borrowConversion && borrowed &&
          types.isView(actual) &&
          !types.isView(descriptor.parameters[i].type)) {
        region = types.view(actual).region;
        actual = types.view(actual).payload;
      }
      infer(actual, descriptor.parameters[i].type, bindings);
      if (i < descriptor.parameterRegions.size())
        infer(region, descriptor.parameterRegions[i], bindings);
      if (borrowed && i < descriptor.parameterRegions.size())
        argumentLifetimes.push_back({region, descriptor.parameterRegions[i]});
    }
    for (const auto &[variable, value] : bindings) {
      auto environment = current->context.environment;
      auto answer = solver.instantiate(variable, value, environment);
      if (answer != RegionAnswer::Proven)
        error(node.span,
              "higher-ranked callable region would escape its binder",
              answer == RegionAnswer::Inconclusive);
    }
    for (const auto &edge : argumentLifetimes)
      require(edge.longer, replace(edge.shorter, bindings), node.span);
    for (const auto &requirement : descriptor.regionRequirements) {
      auto longer =
          replace(replace(requirement.longer, substitution), bindings);
      auto shorter =
          replace(replace(requirement.shorter, substitution), bindings);
      require(longer, shorter, node.span);
    }
    for (std::size_t i = 0;
         i < arguments.size() && i < descriptor.parameters.size(); ++i) {
      auto actual = arguments[i];
      if (!facts(*node.children[i + 1]).borrowConversion &&
          (descriptor.parameters[i].mode == ParameterMode::Read ||
           descriptor.parameters[i].mode == ParameterMode::Mut) &&
          types.isView(actual) && !types.isView(descriptor.parameters[i].type))
        actual = types.view(actual).payload;
      requireArgument(actual, replace(descriptor.parameters[i].type, bindings),
                      descriptor.parameters[i].mode == ParameterMode::Mut,
                      node.children[i + 1]->span,
                      !descriptor.regionParameters.empty());
    }
    if (descriptor.parameterRegions.empty() && !semanticClosure) {
      std::vector<RegionId> sources;
      for (auto index : descriptor.resultSources)
        if (index < arguments.size()) {
          auto nested = contained(arguments[index]);
          sources.insert(sources.end(), nested.begin(), nested.end());
          sources.push_back(backing(*node.children[index + 1]));
        }
      return inferred(facts(node).type,
                      sources.empty() ? store.local(current->context.scope)
                                      : store.intersection(std::move(sources)));
    }
    expressionErrors[&node] = replace(descriptor.error, bindings);
    return replace(descriptor.result, bindings);
  }
  if (facts(node).callee < 0) {
    auto result = originalType(node);
    if (facts(node).variant >= 0 && types.isProduct(result)) {
      auto record = types.product(result);
      auto variant = static_cast<std::size_t>(facts(node).variant);
      if (variant < record.variants.size()) {
        auto fields = record.fields;
        for (auto &field : fields)
          if (field.name != "<tag>")
            field.type = Type::Never;
        for (std::size_t i = 0;
             i < arguments.size() && i < record.variants[variant].fields.size();
             ++i)
          fields[record.variants[variant].fields[i]].type = arguments[i];
        return types.regionalProduct(result, std::move(fields), {});
      }
    }
    if (!facts(node).constructor || !types.isProduct(result))
      return inferred(result, store.local(current->context.scope));
    const auto *product = declaration(result);
    if (!product)
      return inferred(result, store.local(current->context.scope));
    auto context = current->context;
    TypeSyntax syntax;
    std::vector<std::string> explicitRegions;
    const auto &provided = node.children[0]->ownerGenericArguments.empty()
                               ? node.children[0]->genericArguments
                               : node.children[0]->ownerGenericArguments;
    for (const auto &argument : provided)
      if (!argument.region.empty())
        explicitRegions.push_back(argument.region);
    std::size_t regionIndex = 0;
    for (const auto &name : product->regions) {
      auto variable =
          regionIndex < explicitRegions.size()
              ? source(explicitRegions[regionIndex], context, node.span)
              : store.inference(context.scope);
      ++regionIndex;
      auto internal =
          "<" + name + ".inferred." + std::to_string(variable.index()) + ">";
      context.names[internal] = variable;
      syntax.regions.push_back(internal);
    }
    auto origin = result;
    while (types.product(origin).regionOrigin != Type::Unknown)
      origin = types.product(origin).regionOrigin;
    if (types.product(origin).genericOrigin != Type::Unknown)
      origin = types.product(origin).genericOrigin;
    const auto pattern = types.product(origin);
    const auto instance = types.product(result);
    std::vector<TypeBinding> typeArguments;
    for (std::size_t i = 0; i < pattern.genericParameters.size() &&
                            i < instance.genericArguments.size();
         ++i)
      typeArguments.push_back(
          {pattern.genericParameters[i], instance.genericArguments[i]});
    std::set<Type> inferred, fixed;
    std::size_t argumentIndex = 0;
    for (const auto &argument : provided) {
      if (!argument.region.empty())
        continue;
      if (argumentIndex >= typeArguments.size())
        break;
      auto &binding = typeArguments[argumentIndex++];
      if (argument.type) {
        binding.argument = decorate(binding.argument, *argument.type,
                                    current->context, argument.span);
        fixed.insert(binding.parameter);
      }
    }
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      auto target = i < facts(node).argumentOrder.size()
                        ? facts(node).argumentOrder[i]
                        : i;
      if (target < pattern.fields.size())
        inferArguments(pattern.fields[target].type, arguments[i], typeArguments,
                       inferred, fixed, node.span);
    }
    for (const auto &binding : typeArguments)
      context.arguments[binding.parameter] = binding.argument;
    auto formal = decorate(result, syntax, context, node.span);
    auto fields = types.product(formal).fields;
    std::vector<std::pair<RegionId, RegionId>> bindings;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      auto target = i < facts(node).argumentOrder.size()
                        ? facts(node).argumentOrder[i]
                        : i;
      if (target < fields.size())
        infer(arguments[i], fields[target].type, bindings);
    }
    formal = replace(formal, bindings);
    fields = types.product(formal).fields;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      auto target = i < facts(node).argumentOrder.size()
                        ? facts(node).argumentOrder[i]
                        : i;
      if (target < fields.size())
        require(arguments[i], fields[target].type, node.children[i + 1]->span);
    }
    return formal;
  }
  auto callee = static_cast<std::size_t>(facts(node).callee);
  if (callee >= signatures.size())
    return inferred(facts(node).type, store.local(current->context.scope));
  const auto &signature = signatures[callee];
  const auto &declaration = module.functions[callee];
  std::vector<std::pair<RegionId, RegionId>> substitution, bindings;
  std::vector<std::pair<RegionId, RegionId>> explicitRegions;
  std::size_t regionIndex = 0;
  if (!operatorIndex) {
    for (const auto &argument : node.children[0]->genericArguments) {
      if (argument.region.empty())
        continue;
      if (regionIndex >= declaration.regions.size()) {
        error(argument.span, "excess explicit region arguments");
        break;
      }
      const auto &name = declaration.regions[regionIndex++];
      if (auto found = signature.context.names.find(name);
          found != signature.context.names.end())
        explicitRegions.emplace_back(
            found->second,
            source(argument.region, current->context, argument.span));
    }
  }
  for (auto region : signature.quantified) {
    auto explicitArgument =
        std::find_if(explicitRegions.begin(), explicitRegions.end(),
                     [&](const auto &entry) { return entry.first == region; });
    substitution.emplace_back(region,
                              explicitArgument == explicitRegions.end()
                                  ? store.inference(current->context.scope)
                                  : explicitArgument->second);
  }
  std::vector<std::pair<std::string, RegionId>> receiverOwnerRegions;
  if (receiverCall) {
    // Extension-owner regions are implicit method arguments, not call-site
    // generic arguments.
    auto instantiateOwnerRegions =
        [&](const std::vector<GenericParameter> &parameters,
            const std::vector<std::string> &targetRegions) {
          // A covariant read-view reborrow cannot shorten the owner's nominal
          // region argument used by a method-level bound.
          auto actualReceiver = *methodReceiver;
          while (types.isView(actualReceiver))
            actualReceiver = types.view(actualReceiver).payload;
          auto formalReceiver = signature.parameters.empty()
                                    ? Type::Unknown
                                    : signature.parameters[0];
          while (types.isView(formalReceiver))
            formalReceiver = types.view(formalReceiver).payload;
          const ProductType *actualProduct = nullptr;
          const ProductType *formalProduct = nullptr;
          if (types.isProduct(actualReceiver) &&
              types.isProduct(formalReceiver)) {
            actualProduct = &types.product(actualReceiver);
            formalProduct = &types.product(formalReceiver);
          }
          const bool sameReceiverType =
              actualProduct && formalProduct &&
              ((formalProduct->regionOrigin != Type::Unknown &&
                formalProduct->regionOrigin == actualProduct->regionOrigin) ||
               (formalProduct->regionPattern != Type::Unknown &&
                formalProduct->regionPattern ==
                    actualProduct->regionPattern)) &&
              formalProduct->regionArguments.size() ==
                  actualProduct->regionArguments.size();
          for (const auto &parameter : parameters) {
            if (parameter.kind != GenericParameterKind::Region)
              continue;
            auto found = signature.context.names.find(parameter.name);
            if (found == signature.context.names.end())
              continue;
            auto argument = RegionId::Unspecified;
            auto targetRegion =
                std::find(targetRegions.begin(), targetRegions.end(),
                          parameter.name);
            if (actualProduct && targetRegion != targetRegions.end()) {
              auto index = static_cast<std::size_t>(
                  targetRegion - targetRegions.begin());
              if (index < actualProduct->regionArguments.size())
                argument = actualProduct->regionArguments[index];
            }
            if (argument == RegionId::Unspecified && sameReceiverType) {
              for (std::size_t i = 0;
                   i < formalProduct->regionArguments.size(); ++i)
                if (formalProduct->regionArguments[i] == found->second) {
                  argument = actualProduct->regionArguments[i];
                  break;
                }
            }
            if (argument != RegionId::Unspecified)
              receiverOwnerRegions.emplace_back(parameter.name, argument);
            if (argument == RegionId::Unspecified)
              argument = store.inference(current->context.scope);
            auto existing = std::find_if(
                substitution.begin(), substitution.end(),
                [&](const auto &entry) {
                  return entry.first == found->second;
                });
            if (existing == substitution.end())
              substitution.emplace_back(found->second, argument);
            else if (store.get(existing->second).kind == RegionKind::Inference)
              existing->second = argument;
          }
        };
    const auto &method = module.functions[callee];
    if (method.implementation >= 0 &&
        static_cast<std::size_t>(method.implementation) <
            module.implementations.size()) {
      const auto &implementation =
          module.implementations[method.implementation];
      instantiateOwnerRegions(implementation.genericParameters,
                             implementation.target.regions);
    } else if (!method.interfaceOwner.empty()) {
      auto owner = std::find_if(
          module.interfaces.begin(), module.interfaces.end(),
          [&](const auto &candidate) {
            return candidate.name == method.interfaceOwner;
          });
      if (owner != module.interfaces.end())
        instantiateOwnerRegions(owner->genericParameters, {});
    }
  }
  for (auto region : signature.backing)
    if (store.get(region).kind == RegionKind::Bound &&
        std::none_of(substitution.begin(), substitution.end(),
                     [&](const auto &entry) { return entry.first == region; }))
      substitution.emplace_back(region,
                                store.inference(current->context.scope));
  auto formals = signature.parameters;
  auto result = replace(signature.result, substitution);
  for (auto &formal : formals)
    formal = replace(formal, substitution);
  std::vector<TypeBinding> typeBindings;
  for (std::size_t i = 0; i < functions[callee].genericParameters.size() &&
                          i < facts(node).typeArguments.size();
       ++i)
    typeBindings.push_back(
        {functions[callee].genericParameters[i], facts(node).typeArguments[i]});
  std::set<Type> inferredParameters;
  std::set<Type> fixedParameters;
  std::size_t explicitIndex = 0;
  if (!operatorIndex && !node.children.empty())
    for (const auto &argument : node.children[0]->genericArguments) {
      if (!argument.region.empty())
        continue;
      if (explicitIndex >= typeBindings.size())
        break;
      auto &binding = typeBindings[explicitIndex++];
      if (argument.type) {
        binding.argument =
            decorate(binding.argument, *argument.type, current->context,
                     argument.span, RegionId::Unspecified);
        fixedParameters.insert(binding.parameter);
      }
    }
  // The receiver binds the callee's type parameters like any other argument,
  // so a view inside `T?` keeps its region in `take fn unwrap(): T`.
  if (receiverCall && methodReceiver && !formals.empty()) {
    auto actual = *methodReceiver;
    const auto mode = functions[callee].locals[0].mode;
    if (!facts(node).receiverPlan &&
        (mode == ParameterMode::Read || mode == ParameterMode::Mut) &&
        !types.isView(formals[0]))
      while (types.isView(actual))
        actual = types.view(actual).payload;
    inferArguments(formals[0], actual, typeBindings, inferredParameters,
                   fixedParameters, node.span);
  }
  for (std::size_t i = 0; i < arguments.size(); ++i) {
    auto parameter = parameterForArgument(i);
    if (parameter >= formals.size())
      continue;
    // A borrowed parameter receives the referent of an explicit view, so a
    // generic parameter binds to the payload rather than the view itself.
    auto actual = arguments[i];
    auto mode = functions[callee].locals[parameter].mode;
    if (!facts(*node.children[i + 1]).borrowConversion &&
        (mode == ParameterMode::Read || mode == ParameterMode::Mut) &&
        types.isView(actual) && !types.isView(formals[parameter]))
      actual = types.view(actual).payload;
    inferArguments(formals[parameter], actual, typeBindings, inferredParameters,
                   fixedParameters, node.span);
  }
  for (auto &formal : formals)
    formal = types.substitute(formal, typeBindings);
  result = types.substitute(result, typeBindings);
  {
    auto descriptor = types.callable(types.substitute(
        replace(signatureType(callee), substitution), typeBindings));
    auto normalized = types.callable(normalizeContract(
        types.callableType(std::move(descriptor)), {}, currentFunction,
        node.span, current->context.environment));
    for (std::size_t i = 0;
         i < formals.size() && i < normalized.parameters.size(); ++i)
      formals[i] = normalized.parameters[i].type;
    result = normalized.result;
  }
  auto declarationContext = signature.context;
  for (auto &[name, region] : declarationContext.names)
    region = replace(region, substitution);
  callableArguments(declaration.genericParameters, declaration.constraints,
                    typeBindings, declarationContext, current->context,
                    node.span, bindings);
  std::vector<RegionOutlives> argumentLifetimes;
  auto argument = [&](std::size_t parameter, Type actual, const Node &,
                      RegionId lifetime, bool converted) {
    if (parameter >= formals.size())
      return;
    bool borrowed =
        functions[callee].locals[parameter].mode == ParameterMode::Read ||
        functions[callee].locals[parameter].mode == ParameterMode::Mut;
    if (!converted && borrowed && types.isView(actual) &&
        !types.isView(formals[parameter])) {
      lifetime = types.view(actual).region;
      actual = types.view(actual).payload;
      if (receiverCall && parameter == 0)
        while (types.isView(actual)) {
          lifetime = store.intersection({lifetime, types.view(actual).region});
          actual = types.view(actual).payload;
        }
    }
    if (receiverCall && parameter == 0)
      for (unsigned hidden = 0; hidden < facts(node).hiddenReceiver; ++hidden)
        if (types.isOpaque(actual) && !types.product(actual).fields.empty())
          actual = types.product(actual).fields[0].type;
    infer(actual, formals[parameter], bindings);
    infer(lifetime, replace(signature.backing[parameter], substitution),
          bindings);
    if (borrowed)
      argumentLifetimes.push_back(
          {lifetime, replace(signature.backing[parameter], substitution)});
  };
  if (receiverCall && !formals.empty())
    argument(0, *methodReceiver,
             operatorIndex ? *node.children[0] : *node.children[0]->children[0],
             methodLocation, facts(node).receiverPlan.has_value());
  for (std::size_t i = 0; i < arguments.size(); ++i) {
    auto target = parameterForArgument(i);
    argument(target, arguments[i], *node.children[i + 1], argumentLocations[i],
             facts(*node.children[i + 1]).borrowConversion.has_value());
  }
  for (std::size_t pass = 0; pass <= signature.obligations.size(); ++pass) {
    bool changed = false;
    for (const auto &edge : signature.obligations) {
      auto shorter = replace(edge.shorter, substitution);
      auto longer = replace(replace(edge.longer, substitution), bindings);
      bool unbound = std::none_of(
          bindings.begin(), bindings.end(),
          [&](const auto &entry) { return entry.first == shorter; });
      if (store.get(shorter).kind == RegionKind::Inference &&
          store.get(longer).kind != RegionKind::Inference) {
        auto previous = replace(shorter, bindings);
        auto candidate =
            unbound ? longer : store.intersection({previous, longer});
        if (unbound || candidate != previous) {
          infer(longer, shorter, bindings);
          changed = true;
        }
      }
    }
    if (!changed)
      break;
  }
  for (const auto &[variable, value] : bindings) {
    auto environment = current->context.environment;
    auto answer = solver.instantiate(variable, value, environment);
    if (answer != RegionAnswer::Proven)
      error(node.span, "higher-ranked region would escape its binder",
            answer == RegionAnswer::Inconclusive);
  }
  for (const auto &edge : signature.obligations)
    require(replace(replace(edge.longer, substitution), bindings),
            replace(replace(edge.shorter, substitution), bindings), node.span);
  for (const auto &edge : argumentLifetimes)
    require(edge.longer, replace(edge.shorter, bindings), node.span);
  // `withinBounds` substitutes the declaration context through `bindings`.
  // Bridge owner regions using that context's resolved key, rather than only
  // the signature-context key used by `substitution`.
  for (const auto &[name, region] : receiverOwnerRegions) {
    auto found = declarationContext.names.find(name);
    if (found == declarationContext.names.end())
      continue;
    auto existing = std::find_if(
        bindings.begin(), bindings.end(), [&](const auto &entry) {
          return entry.first == found->second;
        });
    if (existing == bindings.end()) {
      if (found->second != region)
        bindings.emplace_back(found->second, region);
    } else {
      existing->second = region;
    }
  }
  withinBounds(declaration.genericParameters, declaration.constraints,
               typeBindings, declarationContext, bindings, node.span);
  if (receiverCall && !formals.empty()) {
    auto actual = *methodReceiver;
    while (!facts(node).receiverPlan && types.isView(actual) &&
           !types.isView(formals[0]))
      actual = types.view(actual).payload;
    for (unsigned hidden = 0; hidden < facts(node).hiddenReceiver; ++hidden)
      if (types.isOpaque(actual) && !types.product(actual).fields.empty())
        actual = types.product(actual).fields[0].type;
    auto expected = replace(formals[0], bindings);
    requireArgument(actual, expected,
                    functions[callee].locals[0].mode == ParameterMode::Mut,
                    node.span, signature.strict, formals[0]);
  }
  for (std::size_t i = 0; i < arguments.size(); ++i) {
    auto target = parameterForArgument(i);
    if (target >= formals.size())
      continue;
    auto actual = arguments[i];
    bool borrowed =
        functions[callee].locals[target].mode == ParameterMode::Read ||
        functions[callee].locals[target].mode == ParameterMode::Mut;
    if (!facts(*node.children[i + 1]).borrowConversion && borrowed &&
        types.isView(actual) && !types.isView(formals[target]))
      actual = types.view(actual).payload;
    requireArgument(actual, replace(formals[target], bindings),
                    functions[callee].locals[target].mode == ParameterMode::Mut,
                    node.children[i + 1]->span,
                    signature.strict || !fixedParameters.empty(),
                    formals[target]);
  }
  // A result region that no argument constrains can only denote storage that
  // outlives the call (or, for an unsafe callee, a lifetime its caller
  // asserts), so the caller may pick any region: `static` coerces to all.
  for (auto region : contained(result))
    if (std::any_of(
            substitution.begin(), substitution.end(),
            [&](const auto &entry) { return entry.second == region; }) &&
        std::none_of(bindings.begin(), bindings.end(),
                     [&](const auto &entry) { return entry.first == region; }))
      bindings.emplace_back(region, RegionId::Static);
  expressionErrors[&node] = replace(
      types.substitute(replace(signature.error, substitution), typeBindings),
      bindings);
  return replace(result, bindings);
}
void RegionPass::expectClosure(const Node &node, Type expected) {
  if (facts(node).callableCoercion != Type::Unknown)
    callableAdaptations[&node] = expected;
  if (node.kind == Kind::Closure)
    expectedClosures[&node] = expected;
  else if (node.kind == Kind::Group)
    expectClosure(*node.children[0], expected);
  else if (node.kind == Kind::Block && !node.children.empty())
    expectClosure(*node.children.back(), expected);
  else if (node.kind == Kind::If)
    for (std::size_t i = 1; i < node.children.size(); ++i)
      expectClosure(*node.children[i], expected);
  else if (node.kind == Kind::Match)
    for (std::size_t i = 1; i < node.children.size(); ++i)
      expectClosure(*node.children[i]->children.back(), expected);
  else if ((node.kind == Kind::Tuple || node.kind == Kind::Array) &&
           types.isProduct(expected)) {
    auto fields = types.product(expected).fields;
    for (std::size_t i = 0; i < node.children.size() && i < fields.size(); ++i)
      expectClosure(*node.children[i], fields[i].type);
  }
}
Type RegionPass::closure(const Node &node) {
  if (facts(node).closure < 0 ||
      static_cast<std::size_t>(facts(node).closure) >= closures.size())
    return facts(node).type;
  const auto &checked = *closures[facts(node).closure];
  std::optional<CallableType> expected;
  Type expectedType = Type::Unknown;
  if (auto found = expectedClosures.find(&node);
      found != expectedClosures.end() &&
      types.isFunctionPointer(found->second)) {
    expectedType = found->second;
    expected = types.callable(expectedType);
  }
  auto outerLocals = std::move(locals);
  auto outerStorage = std::move(storage);
  auto outerExpressions = std::move(expressions);
  auto *outer = current;
  auto *outerFacts = currentFacts;
  auto *outerReturns = inferredReturns;
  auto outerCaptureDepth = captureDepth;
  captureDepth = 0;
  RegionSignature nested;
  nested.span = node.span;
  nested.context = outer->context;
  nested.context.scope =
      store.binder(outer->context.scope.universe,
                   expected && !expected->regionParameters.empty());
  nested.context.environment.universe = nested.context.scope.universe;
  nested.strict = outer->strict || expected.has_value();
  std::vector<RegionBinding> substitution;
  if (expected) {
    for (std::size_t i = 0; i < expected->regionParameters.size(); ++i) {
      auto rigid = store.rigid(nested.context.scope, "<closure-universal>");
      substitution.push_back({expected->regionParameters[i], rigid});
      if (i < expected->regions.size())
        nested.context.names[expected->regions[i]] = rigid;
    }
    for (auto &parameter : expected->parameters)
      parameter.type = types.substituteRegions(parameter.type, substitution);
    for (auto &region : expected->parameterRegions)
      region = store.substitute(region, substitution);
    expected->result = types.substituteRegions(expected->result, substitution);
    expected->error = types.substituteRegions(expected->error, substitution);
  }
  current = &nested;
  currentFacts = &checked.function;
  locals.clear();
  storage.clear();
  expressions.clear();
  for (const auto &local : checked.function.locals) {
    auto lifetime = local.storage == StorageDuration::Static
                        ? RegionId::Static
                        : store.local(nested.context.scope);
    storage.push_back(lifetime);
    locals.push_back(inferred(local.type, lifetime));
  }
  std::vector<TypeField> captures;
  for (const auto &capture : checked.captures) {
    if (capture.source.root < 0 ||
        static_cast<std::size_t>(capture.source.root) >= outerLocals.size())
      continue;
    auto root = static_cast<std::size_t>(capture.source.root);
    auto captured =
        projectedType(types, outerLocals[root], capture.source.fields);
    auto type = captured.value_or(capture.type);
    auto lifetime = node.flag
                        ? store.bound(nested.context.scope, "<environment>")
                        : outerStorage[root];
    if (capture.proxy.root >= 0 &&
        static_cast<std::size_t>(capture.proxy.root) < locals.size()) {
      locals[capture.proxy.root] = outerLocals[root];
      storage[capture.proxy.root] = lifetime;
    }
    if (!node.flag)
      type = types.viewType(type,
                            capture.mode == ParameterMode::Mut
                                ? ParameterMode::Mut
                                : ParameterMode::Read,
                            lifetime);
    captures.push_back({"<capture>", type});
  }
  for (std::size_t i = 0; i < node.parameters.size(); ++i) {
    const auto &parameter = node.parameters[i];
    auto lifetime = expected && i < expected->parameterRegions.size()
                        ? expected->parameterRegions[i]
                        : store.bound(nested.context.scope, parameter.name);
    if (!parameter.annotation.sources.empty())
      lifetime = sources(parameter.annotation, nested.context, parameter.span,
                         lifetime);
    nested.backing.push_back(lifetime);
    nested.context.names[parameter.name] = lifetime;
    auto type = expected && parameter.annotation.empty() &&
                        i < expected->parameters.size()
                    ? expected->parameters[i].type
                    : decorate(checked.function.locals[i + 1].type,
                               parameter.annotation, nested.context,
                               parameter.span, lifetime);
    nested.parameters.push_back(type);
    locals[i + 1] = type;
    storage[i + 1] = lifetime;
    if (expected && i < expected->parameters.size()) {
      require(expected->parameters[i].type, type, parameter.span, true);
      if (i < expected->parameterRegions.size())
        require(expected->parameterRegions[i], lifetime, parameter.span);
    }
  }
  nested.result =
      expected && node.annotation.empty() ? expected->result
      : node.annotation.empty()
          ? Type::Unknown
          : decorate(checked.function.result, node.annotation, nested.context,
                     node.span,
                     nested.backing.size() == 1 ? nested.backing[0]
                                                : RegionId::Unspecified);
  nested.error = expected && node.error.empty()
                     ? expected->error
                     : decorate(checked.function.error, node.error,
                                nested.context, node.span);
  std::vector<Type> returns;
  inferredReturns = nested.result == Type::Unknown ? &returns : nullptr;
  expectClosure(*node.children[0], nested.result);
  auto body = expression(*node.children[0]);
  if (facts(*node.children[0]).flow.normal) {
    if (inferredReturns)
      returns.push_back(body);
    else
      require(body, nested.result, node.span, expected.has_value());
  }
  if (inferredReturns && !returns.empty()) {
    nested.result = returns[0];
    for (std::size_t i = 1; i < returns.size(); ++i)
      nested.result = merge(nested.result, returns[i], node.span);
  }
  if (expected)
    require(nested.result, expected->result, node.span, true);
  auto result = expectedType;
  if (!expected) {
    result = types.regionalProduct(checked.type, std::move(captures), {});
    auto descriptor = types.callable(checked.type);
    descriptor.result = nested.result;
    descriptor.abiResult = nested.result;
    descriptor.parameterRegions = nested.backing;
    descriptor.regionParameters.clear();
    for (std::size_t i = 0; i < nested.parameters.size(); ++i) {
      descriptor.parameters[i].type = nested.parameters[i];
      if (store.get(nested.backing[i]).binder == nested.context.scope.binder)
        descriptor.regionParameters.push_back(nested.backing[i]);
    }
    descriptor.regionUniverse = nested.context.scope.universe;
    closureDescriptors[result.index()] = std::move(descriptor);
  }
  CallableType proofContext;
  proofContext.regionUniverse = nested.context.scope.universe;
  proofContext.regionRequirements = nested.context.environment.assumptions;
  closures[facts(node).closure]->function.regionSignature =
      types.callableType(std::move(proofContext));
  current = outer;
  currentFacts = outerFacts;
  inferredReturns = outerReturns;
  captureDepth = outerCaptureDepth;
  locals = std::move(outerLocals);
  storage = std::move(outerStorage);
  expressions = std::move(outerExpressions);
  return result;
}
Type RegionPass::expression(const Node &node) {
  if (auto found = expressions.find(&node); found != expressions.end())
    return found->second;
  auto type = originalType(node);
  switch (node.kind) {
  case Kind::For:
    if (auto plan = iterations.find(&node); plan != iterations.end()) {
      type = expression(*plan->second.elaboration);
      break;
    }
    for (const auto &child : node.children)
      expression(*child);
    break;
  case Kind::Name:
    if (facts(node).slot >= 0 &&
        static_cast<std::size_t>(facts(node).slot) < locals.size())
      type = locals[facts(node).slot];
    else if (facts(node).callee >= 0 &&
             static_cast<std::size_t>(facts(node).callee) < signatures.size() &&
             types.isFunctionPointer(type)) {
      auto callee = static_cast<std::size_t>(facts(node).callee);
      type = signatureType(callee);
      std::vector<TypeBinding> bindings;
      for (std::size_t i = 0; i < functions[callee].genericParameters.size() &&
                              i < facts(node).typeArguments.size();
           ++i)
        bindings.push_back({functions[callee].genericParameters[i],
                            facts(node).typeArguments[i]});
      std::size_t argumentIndex = 0;
      std::vector<std::pair<RegionId, RegionId>> explicitRegions;
      std::size_t regionIndex = 0;
      for (const auto &argument : node.genericArguments) {
        if (!argument.region.empty()) {
          if (regionIndex < module.functions[callee].regions.size()) {
            const auto &name = module.functions[callee].regions[regionIndex++];
            if (auto found = signatures[callee].context.names.find(name);
                found != signatures[callee].context.names.end())
              explicitRegions.emplace_back(
                  found->second,
                  source(argument.region, current->context, argument.span));
          }
          continue;
        }
        if (argumentIndex < bindings.size() && argument.type)
          bindings[argumentIndex].argument =
              decorate(bindings[argumentIndex].argument, *argument.type,
                       current->context, argument.span);
        ++argumentIndex;
      }
      type = types.substitute(type, bindings);
      if (!explicitRegions.empty()) {
        type = replace(type, explicitRegions);
        auto descriptor = types.callable(type);
        std::erase_if(descriptor.regionParameters, [&](auto parameter) {
          return std::any_of(
              explicitRegions.begin(), explicitRegions.end(),
              [&](const auto &binding) { return binding.first == parameter; });
        });
        type = types.callableType(std::move(descriptor));
      }
    }
    break;
  case Kind::Group:
  case Kind::Unsafe:
    type = expression(*node.children[0]);
    break;
  case Kind::Text:
    type = inferred(type, RegionId::Static);
    break;
  case Kind::Unary:
    if (node.text == "read" || node.text == "mut") {
      auto operand = expression(*node.children[0]);
      auto mode =
          node.text == "read" ? ParameterMode::Read : ParameterMode::Mut;
      // Borrowing a view the checker already resolved to a single view is a
      // reborrow of its referent, not a view of the view.
      if (types.isView(operand) && types.isView(facts(node).type) &&
          !types.isView(types.view(facts(node).type).payload))
        type = types.viewType(types.view(operand).payload, mode,
                              types.view(operand).region);
      else
        type = types.viewType(operand, mode, backing(*node.children[0]));
    } else if (node.text == "*" && types.isView(expression(*node.children[0])))
      type = types.view(expression(*node.children[0])).payload;
    else if (node.text == "take")
      type = expression(*node.children[0]);
    else
      for (const auto &child : node.children)
        expression(*child);
    break;
  case Kind::Field:
  case Kind::Index: {
    auto base = expression(*node.children[0]);
    while (types.isView(base))
      base = types.view(base).payload;
    if (node.kind == Kind::Index && facts(node).indexView != Type::Unknown) {
      if (facts(node).callee >= 0) {
        auto indexed = call(node, true);
        if (types.isView(indexed))
          type = types.view(indexed).payload;
        else if (types.isView(facts(node).indexView))
          type = types.view(facts(node).indexView).payload;
      } else if (types.isView(facts(node).indexView)) {
        type = types.view(facts(node).indexView).payload;
      }
    } else if (types.isProduct(base) && facts(node).field >= 0 &&
               static_cast<std::size_t>(facts(node).field) <
                   types.product(base).fields.size())
      type = types.product(base).fields[facts(node).field].type;
    else if (types.isSlice(base) && node.children[1]->kind != Kind::Range)
      type = types.slice(base).element;
    for (std::size_t i = 1; i < node.children.size(); ++i)
      if (node.children[i]->kind == Kind::Range)
        for (const auto &bound : node.children[i]->children)
          expression(*bound);
      else
        expression(*node.children[i]);
    break;
  }
  case Kind::Call:
    type = call(node);
    if (facts(node).optional && types.isProduct(facts(node).type)) {
      auto fields = types.product(facts(node).type).fields;
      if (fields.size() > 1)
        fields[1].type = type;
      type = types.regionalProduct(facts(node).type, std::move(fields), {});
    }
    break;
  case Kind::None:
    if (types.isProduct(type)) {
      auto fields = types.product(type).fields;
      for (auto &field : fields)
        if (field.name != "<tag>")
          field.type = Type::Never;
      type = types.regionalProduct(type, std::move(fields), {});
    }
    break;
  case Kind::Variant: {
    auto payload = expression(*node.children[0]);
    if (types.isProduct(type)) {
      auto record = types.product(type);
      auto variant = static_cast<std::size_t>(facts(node).variant);
      auto fields = record.fields;
      for (auto &field : fields)
        if (field.name != "<tag>")
          field.type = Type::Never;
      if (variant < record.variants.size() &&
          !record.variants[variant].fields.empty())
        fields[record.variants[variant].fields[0]].type = payload;
      type = types.regionalProduct(type, std::move(fields), {});
    }
    break;
  }
  case Kind::Throw:
    if (!node.children.empty()) {
      auto error = expression(*node.children[0]);
      expressionErrors[&node] = error;
      if (!captureDepth && current->error != Type::Unknown)
        require(error, current->error, node.span);
    }
    break;
  case Kind::Try:
    type = expression(*node.children[0]);
    if (facts(node).outcomePropagation && types.isProduct(type) &&
        types.product(type).kind == AggregateKind::Outcome &&
        types.product(type).fields.size() > 2) {
      auto fields = types.product(type).fields;
      auto error = fields[2].type;
      type = fields[1].type;
      expressionErrors[&node] = error;
      if (!captureDepth && current->error != Type::Unknown)
        require(error, current->error, node.span);
    } else if (!captureDepth && current->error != Type::Unknown)
      if (auto found = expressionErrors.find(node.children[0].get());
          found != expressionErrors.end() && found->second != Type::Unknown)
        require(found->second, current->error, node.span);
    break;
  case Kind::Capture: {
    ++captureDepth;
    auto success = expression(*node.children[0]);
    --captureDepth;
    if (types.isProduct(type)) {
      auto fields = types.product(type).fields;
      if (fields.size() > 1)
        fields[1].type = success;
      if (fields.size() > 2)
        if (auto found = expressionErrors.find(node.children[0].get());
            found != expressionErrors.end())
          fields[2].type = found->second;
      type = types.regionalProduct(type, std::move(fields), {});
    }
    break;
  }
  case Kind::Binding: {
    if (node.children.empty()) {
      auto slot = facts(node).slot;
      if (slot >= 0 && !node.annotation.empty())
        locals[slot] = decorate(currentFacts->locals[slot].type,
                                node.annotation, current->context, node.span);
      break;
    }
    auto slot = facts(node).slot;
    std::optional<Type> declared;
    if (!node.annotation.empty()) {
      declared = decorate(slot >= 0 ? currentFacts->locals[slot].type
                                    : facts(*node.children[0]).type,
                          node.annotation, current->context, node.span);
      expectClosure(*node.children[0], *declared);
    }
    auto actual = expression(*node.children[0]);
    if (!node.patterns.empty()) {
      pattern(node.patterns[0], actual, backing(*node.children[0]));
      break;
    }
    auto expected = node.annotation.empty() ? actual : *declared;
    if (!node.annotation.empty()) {
      std::vector<std::pair<RegionId, RegionId>> bindings;
      infer(actual, expected, bindings);
      expected = replace(expected, bindings);
      require(actual, expected, node.span);
    }
    if (slot >= 0 && static_cast<std::size_t>(slot) < locals.size())
      locals[slot] = expected;
    break;
  }
  case Kind::Assign: {
    auto expected = expression(*node.children[0]);
    expectClosure(*node.children[1], expected);
    require(expression(*node.children[1]), expected, node.span);
  } break;
  case Kind::Return:
    if (!node.children.empty()) {
      expectClosure(*node.children[0], current->result);
      auto actual = expression(*node.children[0]);
      if (inferredReturns)
        inferredReturns->push_back(actual);
      else
        require(actual, current->result, node.span);
    }
    break;
  case Kind::Block:
    for (const auto &child : node.children) {
      auto value = expression(*child);
      if (!isStatement(child->kind) && !child->semicolon)
        type = value;
      else
        type = facts(node).type;
    }
    break;
  case Kind::If:
    if (!node.patterns.empty())
      pattern(node.patterns[0], expression(*node.children[0]),
              backing(*node.children[0]));
    else
      expression(*node.children[0]);
    if (node.children.size() >= 3)
      type = merge(expression(*node.children[1]), expression(*node.children[2]),
                   node.span);
    else if (node.children.size() >= 2)
      expression(*node.children[1]);
    break;
  case Kind::Match: {
    auto input = expression(*node.children[0]);
    auto region = backing(*node.children[0]);
    type = Type::Never;
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      const auto &arm = *node.children[i];
      if (!arm.patterns.empty())
        pattern(arm.patterns[0], input, region);
      if (arm.flag)
        expression(*arm.children[0]);
      type = merge(type, expression(*arm.children.back()), arm.span);
    }
    break;
  }
  case Kind::Tuple:
  case Kind::Array: {
    if (!types.isProduct(type))
      break;
    auto fields = types.product(type).fields;
    for (std::size_t i = 0; i < fields.size(); ++i) {
      auto index = node.flag && node.kind == Kind::Array ? 0 : i;
      if (index < node.children.size())
        fields[i].type = expression(*node.children[index]);
    }
    type = types.regionalProduct(type, std::move(fields), {});
    break;
  }
  case Kind::Closure:
    type = closure(node);
    break;
  default:
    for (const auto &child : node.children)
      expression(*child);
    if (types.containsViews(type))
      type = inferred(type, store.local(current->context.scope));
    break;
  }
  if (node.kind != Kind::Capture)
    for (const auto &child : node.children)
      if (auto found = expressionErrors.find(child.get());
          found != expressionErrors.end() && found->second != Type::Unknown) {
        if (auto own = expressionErrors.find(&node);
            own != expressionErrors.end() && own->second != Type::Unknown)
          own->second = merge(own->second, found->second, node.span);
        else
          expressionErrors[&node] = found->second;
      }
  if (facts(node).opaqueSource != Type::Unknown) {
    auto target = facts(node).rebuiltType;
    if (types.isOpaque(target)) {
      auto fields = types.product(target).fields;
      if (!fields.empty())
        fields[0].type = type;
      type = types.regionalProduct(target, std::move(fields), {});
    }
    if (facts(node).viewConversion) {
      auto location = backing(node);
      type = receiver(type, location, *facts(node).viewConversion, node.span);
      type = types.viewType(type, types.view(facts(node).conversionView).mode,
                            location);
    }
  }
  if (facts(node).unsizedSource != Type::Unknown)
    type = unsized(type, facts(node).rebuiltType);
  if (facts(node).reborrowSource != Type::Unknown && types.isView(type)) {
    auto source = types.view(type);
    type = types.viewType(source.payload, ParameterMode::Read, source.region);
  }
  if (facts(node).erasedSource != Type::Unknown) {
    type = erased(type, facts(node).rebuiltType, node.span);
  }
  if (facts(node).callableCoercion != Type::Unknown) {
    auto expected = facts(node).callableCoercion;
    if (auto found = callableAdaptations.find(&node);
        found != callableAdaptations.end())
      expected = found->second;
    if (types.isCallable(type) && types.isFunctionPointer(expected)) {
      auto descriptor = types.callable(type);
      if (auto found = closureDescriptors.find(type.index());
          found != closureDescriptors.end())
        descriptor = found->second;
      auto source = types.callableType(std::move(descriptor));
      require(source, expected, node.span, true);
      type = expected;
    }
  }
  for (auto injection : facts(node).injections) {
    auto fields = types.product(injection).fields;
    if (fields.size() > 1)
      fields[1].type = type;
    type = types.regionalProduct(injection, std::move(fields), {});
  }
  expressions[&node] = type;
  return type;
}
void RegionPass::resultSources(std::size_t index) {
  auto &facts = functions[index];
  const auto &syntax = module.functions[index];
  std::vector<std::size_t> eligible;
  for (std::size_t i = 0; i < syntax.parameters.size(); ++i)
    if (facts.locals[i].mode == ParameterMode::Read ||
        facts.locals[i].mode == ParameterMode::Mut ||
        types.containsViews(facts.locals[i].type))
      eligible.push_back(i);
  // An async call's future holds its borrowed inputs until it is dropped.
  if (syntax.asynchronous) {
    facts.resultSources = eligible;
    return;
  }
  if (!types.containsViews(facts.abiResult))
    return;
  auto add = [&](std::size_t parameter) {
    if (std::find(facts.resultSources.begin(), facts.resultSources.end(),
                  parameter) == facts.resultSources.end())
      facts.resultSources.push_back(parameter);
  };
  if (syntax.constructor) {
    facts.resultSources = eligible;
    return;
  }
  // Sources written on views nested in optional, tuple and outcome results
  // declare the same relationship as a top-level `from` clause.
  std::vector<std::string> declaredSources;
  std::set<std::size_t> carried, borrowed, named;
  auto collect = [&](auto &&self, const TypeSyntax &annotation) -> void {
    for (const auto &name : annotation.sources)
      if (std::find(declaredSources.begin(), declaredSources.end(), name) ==
          declaredSources.end())
        declaredSources.push_back(name);
    if (annotation.nested)
      self(self, *annotation.nested);
    for (const auto &element : annotation.elements)
      self(self, element);
  };
  collect(collect, syntax.annotation);
  collect(collect, syntax.error);
  if (!declaredSources.empty()) {
    for (const auto &name : declaredSources) {
      if (name == "static") {
        for (auto p : eligible) {
          auto candidates = contained(signatures[index].parameters[p]);
          candidates.push_back(signatures[index].backing[p]);
          if (std::find(candidates.begin(), candidates.end(),
                        RegionId::Static) != candidates.end()) {
            add(p);
            named.insert(p);
          }
        }
        continue;
      }
      auto found = std::find_if(
          syntax.parameters.begin(), syntax.parameters.end(),
          [&](const auto &parameter) { return parameter.name == name; });
      if (found != syntax.parameters.end()) {
        auto p = static_cast<std::size_t>(found - syntax.parameters.begin());
        if (std::find(eligible.begin(), eligible.end(), p) != eligible.end()) {
          add(p);
          named.insert(p);
        } else
          error(syntax.span,
                "borrowed result source is not borrowed input storage");
        continue;
      }
      bool patternBinding = false;
      for (const auto &[slot, parameter] : facts.parameterBindings)
        if (facts.locals[slot].name == name) {
          add(parameter);
          named.insert(parameter);
          patternBinding = true;
        }
      if (patternBinding)
        continue;
      auto region = signatures[index].context.names.find(name);
      if (region == signatures[index].context.names.end()) {
        error(syntax.span, "unknown borrowed result source '" + name + "'");
        continue;
      }
      for (auto p : eligible) {
        auto proves = [&](RegionId candidate) {
          return solver.outlives(candidate, region->second,
                                 signatures[index].context.environment) ==
                 RegionAnswer::Proven;
        };
        bool inside = false;
        for (auto candidate : contained(signatures[index].parameters[p]))
          inside |= proves(candidate);
        if (proves(signatures[index].backing[p]))
          borrowed.insert(p);
        if (inside || borrowed.contains(p)) {
          add(p);
          if (inside)
            carried.insert(p);
        }
      }
    }
    for (auto p : carried)
      if (!borrowed.contains(p) && !named.contains(p))
        facts.resultContents.push_back(p);
  } else if (signatures[index].strict || !syntax.annotation.regions.empty()) {
    auto required = contained(signatures[index].result);
    auto errorRegions = contained(signatures[index].error);
    required.insert(required.end(), errorRegions.begin(), errorRegions.end());
    for (auto region : required)
      for (auto p : eligible) {
        auto candidates = contained(signatures[index].parameters[p]);
        candidates.push_back(signatures[index].backing[p]);
        for (auto candidate : candidates)
          if (solver.outlives(candidate, region,
                              signatures[index].context.environment) ==
              RegionAnswer::Proven)
            add(p);
      }
    if (facts.resultSources.empty() &&
        std::any_of(required.begin(), required.end(),
                    [](auto region) { return region != RegionId::Static; }))
      diagnostics.error("ownership", syntax.span,
                        "borrowed result has no eligible input source");
  } else if (eligible.size() == 1)
    facts.resultSources = eligible;
  else if (eligible.size() > 1)
    diagnostics.error(
        "type", syntax.span,
        "ambiguous borrowed result requires an explicit from relationship");
  else
    diagnostics.error("ownership", syntax.span,
                      "borrowed result has no eligible input source");
}
std::vector<RegionId> RegionPass::contained(Type type) const {
  std::vector<RegionId> result;
  std::vector<Type> active;
  auto visit = [&](auto &&self, Type nested) -> void {
    if (std::find(active.begin(), active.end(), nested) != active.end())
      return;
    active.push_back(nested);
    if (types.isView(nested)) {
      result.push_back(types.view(nested).region);
      self(self, types.view(nested).payload);
    } else if (types.isSlice(nested))
      self(self, types.slice(nested).element);
    else if (types.isProduct(nested)) {
      const auto &record = types.product(nested);
      if (record.kind == AggregateKind::Array && !record.components.empty())
        self(self, record.components[0]);
      else
        for (const auto &field : record.fields)
          self(self, field.type);
    }
    active.pop_back();
  };
  visit(visit, type);
  return result;
}
void RegionPass::wellformed(Type type, Span span, bool indirect, bool tail,
                            unsigned depth) {
  if (type == Type::Unknown)
    return;
  if (std::find(wellformedActive.begin(), wellformedActive.end(), type) !=
      wellformedActive.end())
    return;
  wellformedActive.push_back(type);
  struct Pop {
    std::vector<Type> &active;
    ~Pop() { active.pop_back(); }
  } pop{wellformedActive};
  if (depth > limits::typeDepth) {
    error(span, "unsized well-formedness nesting limit exceeded", true);
    return;
  }
  if (!types.isSized(type) && !indirect && !tail)
    diagnostics.error(
        "type", span,
        types.isParameter(type)
            ? "by-value use of a possibly unsized type parameter requires a "
              "Sized bound; an interface's 'Self' is unsized unless declared "
              "'interface Name: Sized'"
            : "unsized value requires a view or a metadata-supporting owner");
  if (types.isView(type)) {
    wellformed(types.view(type).payload, span, true, false, depth + 1);
    return;
  }
  if (types.isSlice(type)) {
    if (!types.isSized(types.slice(type).element))
      diagnostics.error("type", span, "slice element requires Sized");
    return;
  }
  if (!types.isProduct(type))
    return;
  auto record = types.product(type);
  if (record.kind == AggregateKind::Array && !record.components.empty()) {
    wellformed(record.components[0], span, false, false, depth + 1);
    return;
  }
  if (!types.isSized(type) && !types.isSymbolic(type) &&
      types.pointerMetadata(type) != PointerMetadata::ElementCount &&
      types.pointerMetadata(type) != PointerMetadata::Witness)
    diagnostics.error(
        "feature", span,
        "unsized aggregate tails require metadata-bearing layout lowering");
  for (std::size_t i = 0; i < record.fields.size(); ++i) {
    auto allowedTail = (record.kind == AggregateKind::Product ||
                        record.kind == AggregateKind::Cell ||
                        record.kind == AggregateKind::RefCell) &&
                       i + 1 == record.fields.size();
    wellformed(record.fields[i].type, span, false, allowedTail, depth + 1);
  }
}
Type RegionPass::erased(Type source, Type target, Span span) {
  if (types.isView(source) && types.isView(target)) {
    const auto from = types.view(source), to = types.view(target);
    return types.viewType(erased(from.payload, to.payload, span), to.mode,
                          from.region);
  }
  if (types.isErased(target)) {
    if (types.isView(source))
      source = types.view(source).payload;
    return eraseContract(source, target, span, current->context.environment);
  }
  if (types.isProduct(source) && types.isProduct(target)) {
    const auto actual = types.product(source);
    auto fields = types.product(target).fields;
    if (fields.size() == actual.fields.size() && !fields.empty()) {
      for (std::size_t p = 0; p + 1 < fields.size(); ++p)
        fields[p].type = actual.fields[p].type;
      fields.back().type =
          erased(actual.fields.back().type, fields.back().type, span);
      return types.regionalProduct(target, std::move(fields),
                                   actual.regionArguments);
    }
  }
  return target;
}

Type RegionPass::unsized(Type source, Type target) {
  if (types.isView(source) && types.isView(target)) {
    const auto actual = types.view(source), wanted = types.view(target);
    if (wanted.mode == ParameterMode::Mut &&
        actual.mode != ParameterMode::Mut) {
      error(current->span,
            "unsizing cannot upgrade read access to mutable access");
      return source;
    }
    return types.viewType(unsized(actual.payload, wanted.payload), wanted.mode,
                          actual.region);
  }
  if (types.isSlice(target) && types.isProduct(source) &&
      types.product(source).kind == AggregateKind::Array) {
    const auto actual = types.product(source);
    auto element =
        actual.fields.empty() ? actual.components[0] : actual.fields[0].type;
    return types.sliceType(element);
  }
  if (types.isProduct(source) && types.isProduct(target)) {
    const auto actual = types.product(source);
    auto fields = types.product(target).fields;
    if (fields.size() == actual.fields.size() && !fields.empty()) {
      for (std::size_t i = 0; i + 1 < fields.size(); ++i)
        fields[i].type = actual.fields[i].type;
      fields.back().type =
          unsized(actual.fields.back().type, fields.back().type);
      return types.regionalProduct(target, std::move(fields),
                                   types.product(target).regionArguments);
    }
  }
  return source == target ? source : target;
}
Type RegionPass::signatureType(std::size_t index) {
  const auto &signature = signatures[index];
  CallableType descriptor;
  for (std::size_t i = 0; i < signature.parameters.size(); ++i)
    descriptor.parameters.push_back(
        {signature.parameters[i], functions[index].locals[i].mode,
         module.functions[index].parameters[i].name});
  descriptor.parameterRegions = signature.backing;
  descriptor.regionParameters = signature.quantified;
  descriptor.regions = module.functions[index].regions;
  for (auto region : signature.backing)
    if (store.get(region).kind == RegionKind::Bound &&
        std::find(descriptor.regionParameters.begin(),
                  descriptor.regionParameters.end(),
                  region) == descriptor.regionParameters.end())
      descriptor.regionParameters.push_back(region);
  descriptor.regionUniverse = signature.context.scope.universe;
  descriptor.result = signature.result;
  descriptor.error = signature.error;
  descriptor.abiResult = signature.result;
  descriptor.resultSources = functions[index].resultSources;
  descriptor.regionRequirements = signature.obligations;
  return types.callableType(std::move(descriptor));
}
void RegionPass::inferArguments(Type pattern, Type actual,
                                std::vector<TypeBinding> &bindings,
                                std::set<Type> &inferred,
                                const std::set<Type> &fixed, Span span) {
  if (actual == Type::Never)
    return;
  for (auto &binding : bindings)
    if (binding.parameter == pattern) {
      if (!fixed.contains(pattern))
        binding.argument = inferred.insert(pattern).second
                               ? actual
                               : merge(binding.argument, actual, span);
      return;
    }
  if (pattern == actual)
    return;
  auto pair = std::pair{pattern, actual};
  if (std::find(inferringArguments.begin(), inferringArguments.end(), pair) !=
      inferringArguments.end())
    return;
  inferringArguments.push_back(pair);
  struct Pop {
    std::vector<std::pair<Type, Type>> &active;
    ~Pop() { active.pop_back(); }
  } pop{inferringArguments};
  auto infer = [&](Type left, Type right) {
    inferArguments(left, right, bindings, inferred, fixed, span);
  };
  if (types.isView(pattern) && types.isView(actual))
    infer(types.view(pattern).payload, types.view(actual).payload);
  else if (types.isProduct(pattern) && types.isProduct(actual)) {
    const auto left = types.product(pattern), right = types.product(actual);
    auto arguments = left.genericArguments.empty() ? left.genericParameters
                                                   : left.genericArguments;
    if (!arguments.empty() &&
        arguments.size() == right.genericArguments.size()) {
      for (std::size_t i = 0; i < arguments.size(); ++i)
        infer(arguments[i], right.genericArguments[i]);
    } else if (left.kind == AggregateKind::Array && !left.components.empty() &&
               left.components.size() == right.components.size()) {
      for (std::size_t i = 0; i < left.components.size(); ++i)
        infer(left.components[i], right.components[i]);
    } else if (left.fields.size() == right.fields.size())
      for (std::size_t i = 0; i < left.fields.size(); ++i)
        infer(left.fields[i].type, right.fields[i].type);
  } else if (types.isFunctionPointer(pattern) &&
             types.isFunctionPointer(actual)) {
    const auto left = types.callable(pattern), right = types.callable(actual);
    for (std::size_t i = 0;
         i < left.parameters.size() && i < right.parameters.size(); ++i)
      infer(left.parameters[i].type, right.parameters[i].type);
    infer(left.result, right.result);
    infer(left.error, right.error);
  }
}
// A `Within<region r>` bound states that everything the generic argument
// borrows outlives `r`. The library interface has a blanket implementation, so
// this is the only place the obligation is enforced.
void RegionPass::withinBounds(
    const std::vector<GenericParameter> &parameters,
    const std::vector<GenericConstraint> &constraints,
    const std::vector<TypeBinding> &arguments, const RegionContext &declaration,
    const std::vector<std::pair<RegionId, RegionId>> &bindings, Span span) {
  auto enforce = [&](Type argument, const TypeSyntax &bound) {
    const auto separator = bound.name.rfind("::");
    const auto name = separator == std::string::npos
                          ? bound.name
                          : bound.name.substr(separator + 2);
    if (name != "Within" || bound.arguments.size() != 1 ||
        bound.arguments[0].region.empty())
      return;
    auto found = declaration.names.find(bound.arguments[0].region);
    if (found == declaration.names.end())
      return;
    auto limit = replace(found->second, bindings);
    // A higher-ranked `r` lives only for one call of the callee, so a region
    // from an enclosing universe already outlives it.
    auto enclosing = [&](auto &&self, RegionId region) -> bool {
      const auto &source = store.get(region);
      if (source.kind == RegionKind::Intersection)
        return std::all_of(source.sources.begin(), source.sources.end(),
                           [&](auto nested) { return self(self, nested); });
      const auto &target = store.get(limit);
      return target.kind == RegionKind::Rigid &&
             source.universe != target.universe &&
             store.ancestor(source.universe, target.universe);
    };
    for (auto region : contained(argument))
      if (!enclosing(enclosing, region))
        require(region, limit, span);
  };
  for (const auto &parameter : parameters) {
    if (parameter.kind != GenericParameterKind::Type)
      continue;
    auto binding = std::find_if(
        arguments.begin(), arguments.end(), [&](const auto &entry) {
          return types.isParameter(entry.parameter) &&
                 types.parameter(entry.parameter).name == parameter.name;
        });
    if (binding == arguments.end() || binding->argument == binding->parameter)
      continue;
    for (const auto &bound : parameter.bounds)
      enforce(binding->argument, bound);
    for (const auto &constraint : constraints)
      if (constraint.subject.name == parameter.name)
        for (const auto &bound : constraint.bounds)
          enforce(binding->argument, bound);
  }
}
void RegionPass::callableArguments(
    const std::vector<GenericParameter> &parameters,
    const std::vector<GenericConstraint> &constraints,
    const std::vector<TypeBinding> &arguments, RegionContext &declaration,
    RegionContext &caller, Span span,
    std::vector<std::pair<RegionId, RegionId>> &bindings) {
  for (const auto &parameter : parameters) {
    if (parameter.kind != GenericParameterKind::Type)
      continue;
    auto binding = std::find_if(
        arguments.begin(), arguments.end(), [&](const auto &entry) {
          return types.isParameter(entry.parameter) &&
                 types.parameter(entry.parameter).name == parameter.name;
        });
    if (binding == arguments.end())
      continue;
    std::vector<const TypeSyntax *> bounds;
    for (const auto &bound : parameter.bounds)
      bounds.push_back(&bound);
    for (const auto &constraint : constraints)
      if (constraint.subject.name == parameter.name)
        for (const auto &bound : constraint.bounds)
          bounds.push_back(&bound);
    for (const auto *bound : bounds) {
      if (bound->form != TypeForm::Callable)
        continue;
      auto constraint = types.parameter(binding->parameter).callableConstraint;
      if (constraint == Type::Unknown)
        continue;
      auto expected = types.substitute(
          decorate(constraint, *bound, declaration, span), arguments);
      if (binding->argument == binding->parameter)
        continue;
      auto actual = callableBound(binding->argument, caller, span);
      if (!types.isCallable(actual)) {
        error(span,
              "generic argument does not satisfy its callable region contract");
        continue;
      }
      if (current) {
        actual = normalizeContract(actual, {}, currentFunction, span,
                                   caller.environment);
        expected = normalizeContract(expected, {}, currentFunction, span,
                                     caller.environment);
      }
      infer(actual, expected, bindings);
      auto answer = relations.coerce(actual, replace(expected, bindings),
                                     caller.environment);
      if (answer != RegionAnswer::Proven)
        error(span,
              answer == RegionAnswer::Inconclusive
                  ? "quantified callable region solving is inconclusive"
                  : "generic callable argument violates its declared "
                    "relationship",
              answer == RegionAnswer::Inconclusive);
    }
  }
}
Type RegionPass::callableBound(Type type, RegionContext &context, Span span) {
  if (auto found = closureDescriptors.find(type.index());
      found != closureDescriptors.end())
    return types.callableType(found->second);
  if (!types.isParameter(type) || !types.isCallable(type))
    return type;
  const auto name = types.parameter(type).name;
  auto declared = [&](const std::vector<GenericParameter> &parameters,
                      const std::vector<GenericConstraint> &constraints)
      -> const TypeSyntax * {
    for (const auto &parameter : parameters)
      if (parameter.name == name)
        for (const auto &bound : parameter.bounds)
          if (bound.form == TypeForm::Callable)
            return &bound;
    for (const auto &constraint : constraints)
      if (constraint.subject.name == name)
        for (const auto &bound : constraint.bounds)
          if (bound.form == TypeForm::Callable)
            return &bound;
    return nullptr;
  };
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    if (std::find(functions[i].genericParameters.begin(),
                  functions[i].genericParameters.end(),
                  type) == functions[i].genericParameters.end())
      continue;
    const auto &function = module.functions[i];
    auto bound = declared(function.genericParameters, function.constraints);
    if (!bound && function.implementation >= 0) {
      const auto &owner = module.implementations[function.implementation];
      bound = declared(owner.genericParameters, owner.constraints);
    }
    if (!bound)
      for (const auto &[identity, owner] : products)
        if (owner->name == function.owner ||
            types.name(identity) == function.owner) {
          bound = declared(owner->genericParameters, owner->constraints);
          break;
        }
    if (!bound && !function.interfaceOwner.empty())
      for (const auto &owner : module.interfaces)
        if (owner.name == function.interfaceOwner) {
          bound = declared(owner.genericParameters, owner.constraints);
          break;
        }
    if (bound)
      return decorate(types.parameter(type).callableConstraint, *bound, context,
                      span);
  }
  error(span, "cannot establish the declared quantified callable bound", true);
  return type;
}
void RegionPass::run() {
  std::vector<RegionContext> productContexts;
  for (const auto &[identity, product] : products) {
    auto context = RegionContext{store.binder(), {}, {}, {}};
    declare(context, product->regions, product->span);
    assumptions(context, product->genericParameters, product->constraints,
                product->span);
    std::vector<RegionId> regions;
    for (const auto &name : product->regions)
      regions.push_back(context.names.at(name));
    auto arguments = types.product(identity).genericParameters;
    auto shell = types.regionalShell(identity, regions, arguments);
    types.setRegionPattern(shell, shell);
    nominalPatterns.emplace(identity, shell);
    nominalRegions.emplace(NominalKey{identity, regions, arguments},
                           NominalRegion{shell});
    productContexts.push_back(std::move(context));
  }
  for (std::size_t i = 0; i < products.size(); ++i) {
    const auto &[identity, product] = products[i];
    auto &context = productContexts[i];
    TypeSyntax syntax;
    syntax.regions = product->regions;
    decorate(identity, syntax, context, product->span);
    wellformed(identity, product->span, true);
  }
  auto decorateRule = [&](interfaces::Implementation &rule) {
    if (rule.declaration >= module.implementations.size())
      return;
    const auto &syntax = module.implementations[rule.declaration];
    RegionContext context{store.binder(), {}, {}, {}};
    if (!rule.regions.empty()) {
      const auto &region = store.get(rule.regions[0]);
      context.scope = {region.binder, region.universe};
    }
    context.environment.universe = context.scope.universe;
    context.environment.assumptions = rule.regionRequirements;
    std::size_t region = 0, type = 0;
    for (const auto &parameter : syntax.genericParameters)
      if (parameter.kind == GenericParameterKind::Region) {
        if (region < rule.regions.size())
          context.names[parameter.name] = rule.regions[region++];
      } else if (type < rule.parameters.size()) {
        auto identity = rule.parameters[type++];
        context.types[parameter.name] = identity;
        context.arguments[identity] = identity;
      }
    rule.target = decorate(rule.target, syntax.target, context, syntax.span);
    // Associated values naming a region-parameterized type carry their region
    // arguments, so projections substitute family regions into them.
    if (!types.isErased(rule.interfaceType))
      return;
    const auto &definition =
        interfaceData.definitions[types.erased(rule.interfaceType).declaration];
    for (auto &[ordinal, value] : rule.associated) {
      if (ordinal >= definition.associated.size() ||
          !types.isProduct(value.value))
        continue;
      const auto *provided = [&]() -> const Module::Associated * {
        for (const auto &candidate : syntax.associated)
          if (candidate.name == definition.associated[ordinal].name &&
              !candidate.constant && !candidate.value.empty())
            return &candidate;
        return nullptr;
      }();
      const auto *owner = declaration(value.value);
      if (!provided || !owner || owner->regions.empty())
        continue;
      auto family = context;
      std::size_t familyRegion = 0, familyType = 0;
      for (const auto &parameter : provided->genericParameters)
        if (parameter.kind == GenericParameterKind::Region) {
          if (familyRegion < value.regions.size())
            family.names[parameter.name] = value.regions[familyRegion++];
        } else if (familyType < value.parameters.size()) {
          auto identity = value.parameters[familyType++];
          family.types[parameter.name] = identity;
          family.arguments[identity] = identity;
        }
      family.environment.assumptions.insert(
          family.environment.assumptions.end(),
          value.regionRequirements.begin(), value.regionRequirements.end());
      if (familyRegion != 0) {
        const auto &region = store.get(value.regions[0]);
        family.scope = {region.binder, region.universe};
        family.environment.universe = region.universe;
      }
      value.value =
          decorate(value.value, provided->value, family, provided->span);
    }
  };
  for (auto &rule : interfaceData.implementations)
    decorateRule(rule);
  for (auto &[origin, rule] : interfaceData.unpinImplementations) {
    (void)origin;
    decorateRule(rule);
  }
  if (!diagnostics.empty())
    return;
  signatures.resize(module.functions.size());
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    const auto &syntax = module.functions[i];
    auto &signature = signatures[i];
    signature.span = syntax.span;
    signature.strict =
        !syntax.regions.empty() ||
        ((!syntax.interfaceOwner.empty() || syntax.implementation >= 0) &&
         !seeds[i].parameters.empty());
    auto &context = signature.context;
    context.scope = seeds[i].scope;
    context.environment = seeds[i].environment;
    context.names = seeds[i].names;
    signature.quantified = seeds[i].parameters;
    wellformed(functions[i].result, syntax.span);
    signature.obligations = context.environment.assumptions;
    for (std::size_t p = 0; p < syntax.parameters.size(); ++p) {
      wellformed(functions[i].locals[p].type, syntax.parameters[p].span,
                 functions[i].locals[p].mode == ParameterMode::Read ||
                     functions[i].locals[p].mode == ParameterMode::Mut);
      auto region = store.bound(context.scope, syntax.parameters[p].name);
      if (!syntax.parameters[p].annotation.sources.empty() &&
          !types.isView(functions[i].locals[p].type))
        region = sources(syntax.parameters[p].annotation, context,
                         syntax.parameters[p].span, region);
      context.names.emplace(syntax.parameters[p].name, region);
      signature.backing.push_back(region);
    }
    for (std::size_t p = 0; p < syntax.parameters.size(); ++p) {
      const auto *annotation = &syntax.parameters[p].annotation;
      auto type = functions[i].locals[p].type;
      if (syntax.parameters[p].name == "self" && syntax.implementation >= 0) {
        annotation = &module.implementations[syntax.implementation].target;
        // A pinned receiver's target annotation describes the pinned view's
        // payload, not the structural `Pin` wrapper.
        if (types.isProduct(type) &&
            types.product(type).kind == AggregateKind::Pin &&
            types.isView(types.product(type).fields[0].type)) {
          auto view = types.view(types.product(type).fields[0].type);
          auto region = view.region == RegionId::Unspecified
                            ? signature.backing[p]
                            : view.region;
          if (region == RegionId::Unspecified)
            region = store.inference(context.scope);
          auto payload = decorate(view.payload, *annotation, context,
                                  syntax.parameters[p].span, region);
          signature.parameters.push_back(
              types.structural(AggregateKind::Pin,
                               {types.viewType(payload, view.mode, region)}));
          continue;
        }
      }
      signature.parameters.push_back(decorate(type, *annotation, context,
                                              syntax.parameters[p].span,
                                              signature.backing[p]));
    }
    for (std::size_t p = 0; p < signature.parameters.size(); ++p)
      for (auto region : contained(signature.parameters[p]))
        context.environment.assumptions.push_back(
            {region, signature.backing[p]});
    for (const auto &[slot, parameter] : functions[i].parameterBindings)
      context.names.emplace(functions[i].locals[slot].name,
                            signature.backing[parameter]);
    RegionId fallback = RegionId::Unspecified;
    std::vector<RegionId> eligible;
    for (std::size_t p = 0; p < syntax.parameters.size(); ++p)
      if (functions[i].locals[p].mode == ParameterMode::Read ||
          functions[i].locals[p].mode == ParameterMode::Mut ||
          types.containsViews(signature.parameters[p]))
        eligible.push_back(types.isView(signature.parameters[p])
                               ? types.view(signature.parameters[p]).region
                               : signature.backing[p]);
    if (eligible.size() == 1)
      fallback = eligible[0];
    signature.result = decorate(functions[i].result, syntax.annotation, context,
                                syntax.span, fallback);
    signature.error = decorate(functions[i].error, syntax.error, context,
                               syntax.span, fallback);
  }
  if (!diagnostics.empty())
    return;
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    currentFunction = i;
    current = &signatures[i];
    currentFacts = &functions[i];
    expressions.clear();
    locals.clear();
    storage.clear();
    for (const auto &local : functions[i].locals) {
      storage.push_back(local.storage == StorageDuration::Static
                            ? RegionId::Static
                            : store.local(current->context.scope));
      locals.push_back(inferred(local.type, storage.back()));
    }
    for (std::size_t local = module.functions[i].parameters.size();
         local < functions[i].locals.size(); ++local)
      wellformed(functions[i].locals[local].type,
                 functions[i].locals[local].span);
    for (std::size_t p = 0; p < current->parameters.size(); ++p) {
      locals[p] = current->parameters[p];
      storage[p] = current->backing[p];
      if (module.functions[i].parameters[p].pattern)
        pattern(*module.functions[i].parameters[p].pattern, locals[p],
                storage[p]);
    }
    resultSources(i);
    functions[i].regionSignature = signatureType(i);
    for (const auto &parameter : module.functions[i].parameters)
      if (parameter.defaultValue.get())
        expression(*parameter.defaultValue);
    if (!module.functions[i].body.get())
      continue;
    expectClosure(*module.functions[i].body, current->result);
    auto result = expression(*module.functions[i].body);
    if (facts(*module.functions[i].body).flow.normal &&
        !module.functions[i].constructor)
      require(result, current->result, module.functions[i].body->span);
  }
  for (const auto &contract : contracts) {
    if (contract.implementation >= signatures.size() ||
        contract.declaration >= signatures.size()) {
      diagnostics.error("internal", contract.span,
                        "region contract references a missing declaration");
      continue;
    }
    current = &signatures[contract.implementation];
    auto actual = types.callable(signatureType(contract.implementation));
    auto expected = types.callable(signatureType(contract.declaration));
    auto fixedOwnerRegions = [&](std::size_t index, CallableType &descriptor) {
      const auto &syntax = module.functions[index];
      for (std::size_t parameter = 0;
           parameter < syntax.implicitGenericParameters &&
           parameter < syntax.genericParameters.size();
           ++parameter)
        if (syntax.genericParameters[parameter].kind ==
            GenericParameterKind::Region) {
          auto name = syntax.genericParameters[parameter].name;
          auto region = signatures[index].context.names.find(name);
          if (region != signatures[index].context.names.end())
            std::erase(descriptor.regionParameters, region->second);
        }
    };
    fixedOwnerRegions(contract.implementation, actual);
    fixedOwnerRegions(contract.declaration, expected);
    auto bindings = contract.bindings;
    if (!module.functions[contract.implementation].parameters.empty() &&
        module.functions[contract.implementation].parameters[0].name ==
            "self" &&
        !module.functions[contract.declaration].parameters.empty() &&
        module.functions[contract.declaration].parameters[0].name == "self" &&
        !functions[contract.declaration].genericParameters.empty()) {
      // `Self` is the receiver's region-decorated type; for a pinned
      // receiver, the payload of its pinned view.
      auto self = actual.parameters[0].type;
      if (types.isProduct(self) &&
          types.product(self).kind == AggregateKind::Pin)
        self = types.isView(types.product(self).fields[0].type)
                   ? types.view(types.product(self).fields[0].type).payload
                   : Type::Unknown;
      if (self != Type::Unknown)
        for (auto &binding : bindings)
          if (binding.parameter ==
              functions[contract.declaration].genericParameters[0])
            binding.argument = self;
    }
    auto providedType = types.callableType(std::move(actual));
    auto requiredType = types.callableType(std::move(expected));
    const auto &implementation = module.functions[contract.implementation];
    if (implementation.implementation >= 0) {
      const auto &syntax =
          module.implementations[implementation.implementation];
      std::vector<RegionId> arguments;
      for (const auto &argument : syntax.interface.arguments)
        if (!argument.region.empty())
          arguments.push_back(
              source(argument.region, current->context, contract.span));
      std::vector<std::pair<RegionId, RegionId>> regions;
      const auto &declaration = module.functions[contract.declaration];
      std::size_t argument = 0;
      for (std::size_t parameter = 0;
           parameter < declaration.implicitGenericParameters &&
           parameter < declaration.genericParameters.size();
           ++parameter)
        if (declaration.genericParameters[parameter].kind ==
                GenericParameterKind::Region &&
            argument < arguments.size()) {
          const auto &name = declaration.genericParameters[parameter].name;
          regions.emplace_back(
              signatures[contract.declaration].context.names.at(name),
              arguments[argument++]);
        }
      requiredType = replace(requiredType, regions);
    }
    require(normalizeContract(providedType, {}, contract.implementation,
                              contract.span, current->context.environment),
            normalizeContract(requiredType, bindings, contract.implementation,
                              contract.span, current->context.environment),
            contract.span, true);
  }
}
} // namespace
void Checker::resolveRegionProjections() {
  auto hasProjection = [&](auto &&self, const TypeSyntax &syntax) -> bool {
    if (syntax.form == TypeForm::Projection ||
        syntax.name.find("::") != std::string::npos)
      return true;
    if (syntax.nested && self(self, *syntax.nested))
      return true;
    for (const auto &element : syntax.elements)
      if (self(self, element))
        return true;
    for (const auto &argument : syntax.arguments)
      if (argument.type && self(self, *argument.type))
        return true;
    if (syntax.callable) {
      if (self(self, syntax.callable->result) ||
          self(self, syntax.callable->error))
        return true;
      for (const auto &parameter : syntax.callable->parameters)
        if (self(self, parameter.annotation))
          return true;
    }
    return false;
  };
  auto *saved = current;
  auto *environment = genericEnvironment;
  for (auto &function : module.functions) {
    current = &function;
    genericBindings(function);
    if (hasProjection(hasProjection, function.annotation) &&
        !checked.types->isOpaque(
            inference.value(functionVariables.at(&function)))) {
      auto result =
          annotation(function.annotation, function.span, function.owner);
      inference.set(functionVariables.at(&function), result);
      facts(function).diverges = result == Type::Never;
    }
    if (hasProjection(hasProjection, function.error))
      facts(function).error =
          annotation(function.error, function.span, function.owner);
  }
  current = saved;
  genericEnvironment = environment;
}
void Checker::checkRegions() {
  if (!annotationRegionScopes.empty()) {
    error("internal", {},
          "annotation region scope escaped declaration checking");
    return;
  }
  std::vector<std::pair<Type, const Module::Product *>> products;
  std::vector<RegionSeed> seeds;
  for (const auto &function : module.functions) {
    const auto &scope = functionRegions(function);
    seeds.push_back(
        {scope.scope, scope.environment, scope.names, scope.parameters});
  }
  for (const auto &product : module.products)
    products.emplace_back(
        typeNames.at(definitionName(product.span, product.name)), &product);
  RegionPass(
      module, checked.functions, checked.nodes, checked.patterns,
      checked.iterations, checked.closureBodies, *checked.types, diagnostics,
      *checked.interfaceData, std::move(products), regionContracts,
      semanticRegionAnnotations, std::move(seeds),
      [&](Type signature, std::span<const TypeBinding> bindings,
          std::size_t implementation, Span span,
          const RegionEnvironment &environment) {
        auto *saved = current;
        auto *savedEnvironment = genericEnvironment;
        current = &module.functions[implementation];
        genericBindings(*current);
        std::vector<TypeBinding> substitutions(bindings.begin(),
                                               bindings.end());
        if (current->implementation >= 0) {
          const auto index = static_cast<std::size_t>(current->implementation);
          const auto &syntax = module.implementations[index];
          auto rule =
              std::find_if(checked.interfaceData->implementations.begin(),
                           checked.interfaceData->implementations.end(),
                           [&](const auto &candidate) {
                             return candidate.declaration == index;
                           });
          if (rule == checked.interfaceData->implementations.end()) {
            error("internal", span, "missing implementation region context");
            current = saved;
            genericEnvironment = savedEnvironment;
            return Type::Unknown;
          }
          const auto &compiled = *rule;
          const auto &names = functionRegions(*current).names;
          std::vector<RegionBinding> ownerRegions;
          std::size_t ordinal = 0;
          for (const auto &parameter : syntax.genericParameters)
            if (parameter.kind == GenericParameterKind::Region &&
                ordinal < compiled.regions.size()) {
              if (auto found = names.find(parameter.name); found != names.end())
                ownerRegions.push_back(
                    {compiled.regions[ordinal], found->second});
              ++ordinal;
            }
          for (auto &binding : substitutions)
            binding.argument = checked.types->substituteRegions(
                binding.argument, ownerRegions);
        }
        auto descriptor = checked.types->callable(
            checked.types->substitute(signature, substitutions));
        auto regions = environment;
        regions.assumptions.insert(regions.assumptions.end(),
                                   descriptor.regionRequirements.begin(),
                                   descriptor.regionRequirements.end());
        interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                  diagnostics, interfaceAssumptions(),
                                  std::move(regions));
        for (auto &parameter : descriptor.parameters)
          parameter.type = solver.normalize(parameter.type, {}, span);
        descriptor.result = solver.normalize(descriptor.result, {}, span);
        descriptor.error = solver.normalize(descriptor.error, {}, span);
        descriptor.abiResult = solver.normalize(descriptor.abiResult, {}, span);
        current = saved;
        genericEnvironment = savedEnvironment;
        return checked.types->callableType(std::move(descriptor));
      },
      [&](Type actual, Type target, Span span,
          const RegionEnvironment &environment) {
        interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                  diagnostics, {}, environment);
        if (checked.types->isErased(actual))
          for (auto bound :
               interfaces::hierarchy(*checked.types, *checked.interfaceData,
                                     actual, actual, span, diagnostics))
            if (checked.types->eraseRegions(bound) ==
                checked.types->eraseRegions(target))
              return bound;
        if (auto bound = solver.implementedInterface(actual, target, span))
          return *bound;
        error("region", span,
              "erased receiver does not satisfy its declared region contract");
        return target;
      },
      [&](Type subject, std::size_t function, Span span,
          const RegionEnvironment &regions) {
        std::vector<interfaces::Obligation> assumptions;
        const auto &context = checked.functions.at(function);
        for (auto [type, bound] : context.interfaceBounds)
          assumptions.push_back({type, bound});
        for (auto type : context.unpinBounds)
          assumptions.push_back(
              {type, Type::Unknown, interfaces::Property::Unpin});
        interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                  diagnostics, std::move(assumptions), regions);
        solver.setEqualities(context.genericEqualities);
        return solver.prove(
            {subject, Type::Unknown, interfaces::Property::Unpin}, span, false);
      })
      .run();
}
} // namespace mettle
