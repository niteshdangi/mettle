#pragma once

#include "consteval/evaluate.h"
#include "semantics/check.h"
#include "semantics/inference.h"
#include "semantics/interfaces.h"
#include "semantics/region_solver.h"
#include <map>
#include <set>
#include <span>
#include <unordered_map>
#include <unordered_set>

namespace mettle {
class Checker {
public:
  Checker(Module module, Diagnostics &diagnostics,
          std::shared_ptr<const resolution::Resolution> symbols,
          bool requireEntry = true, TargetFacts target = {})
      : checked(std::move(module), std::move(symbols)), module(checked.tree),
        diagnostics(diagnostics), inference(diagnostics, *checked.types),
        requireEntry(requireEntry) {
    checked.targetDescription = std::move(target);
    checked.types->setPointerBits(pointerBits());
  }
  std::optional<CheckedModule> run();

private:
  friend class ConstantHost;
  TypeStore &typeStore() { return *checked.types; }
  // usize/isize width of the selected target; an unspecified target is 64.
  unsigned pointerBits() const {
    return checked.targetDescription.pointerBits
               ? checked.targetDescription.pointerBits
               : 64;
  }
  // The compiler-owned evaluator for required constants that go beyond
  // literal arithmetic: casts, control flow, const fn calls, aggregates.
  Type evaluatedConstant(const Node &node, Type expected);
  std::optional<StaticConstant> evaluatedStatic(const Node &node, Type type);
  bool needsEvaluator(const Node &node) const;
  bool constFunctionCall(const Node &node);
  std::optional<evaluation::Shape> constantShape(Type type);
  std::optional<evaluation::Value> constantValueOf(const StaticConstant &value);
  std::optional<StaticConstant> staticFromValue(const evaluation::Value &value,
                                                Type type, Span span);
  struct Binding {
    int variable;
    int slot;
    Function *owner = nullptr;
  };
  CheckedModule checked;
  Module &module;
  Diagnostics &diagnostics;
  TypeInference inference;
  bool requireEntry = true;
  unsigned unsafeDepth = 0;
  void requireUnsafe(Span span);
  void machineDeclarations();
  void staticNamesAndTypes();
  void inherentConstantNamesAndTypes();
  void staticDeclarations();
  void staticLocals();
  void staticInitializers();
  // Type of a text or byte-text literal; records its bytes. A malformed
  // literal is diagnosed and still typed so its uses do not cascade.
  Type textLiteralType(const Node &node);
  std::optional<StaticConstant> staticInitializer(const Node &node, Type type);
  std::optional<StaticConstant> staticValue(std::size_t index);
  std::optional<std::size_t> staticName(std::string_view name, Span span);
  std::unordered_map<std::string, std::size_t> staticNames;
  bool staticsDeclared = false;
  struct InherentConstant {
    const Module::Implementation *implementation = nullptr;
    const Module::Associated *declaration = nullptr;
    Type target = Type::Unknown;
    Type declaredType = Type::Unknown;
    Type value = Type::Unknown;
    unsigned char state = 0;
  };
  std::vector<InherentConstant> inherentConstants;
  std::unordered_map<std::string, std::size_t> inherentConstantNames;
  std::optional<Type> inherentConstantValue(std::size_t index, Type subject);
  std::vector<const Module::Product *> deferredLayouts;
  std::vector<unsigned char> staticStates;
  void targetDeclarations();
  std::set<std::string> guardedFeatures{};
  std::set<std::string> availableFeatures() const;
  void requireFeatures(const std::set<std::string> &features, Span span);
  int assemblyExpression(Node &node, bool reachable);
  void finishAssembly();
  int featureTest(Node &node);
  std::optional<int> targetCall(Node &node, bool reachable);
  ProductLayout productLayout(const Module::Product &product);
  std::optional<Type> machineAnnotation(const TypeSyntax &syntax, Span span,
                                        std::string_view owner);
  std::optional<int> machineValue(const Node &node);
  void checkBorrowAlignment();
  std::unordered_map<std::string, std::size_t> names;
  struct ConstructorCandidate {
    std::size_t function;
    interfaces::Implementation applicability;
  };
  std::map<Type, std::vector<ConstructorCandidate>> constructors;
  std::unordered_map<std::string, std::size_t> aliases;
  std::vector<unsigned char> aliasStates;
  mutable std::unordered_map<std::string, std::vector<const Module::Product *>>
      productIndex;
  std::unordered_map<std::string, Type> typeNames{
      {"i32", Type::I32},     {"bool", Type::Bool},   {"Unit", Type::Unit},
      {"Never", Type::Never}, {"char", Type::Char},   {"u8", Type::U8},
      {"i8", Type::I8},       {"i16", Type::I16},     {"i64", Type::I64},
      {"i128", Type::I128},   {"isize", Type::Isize}, {"u16", Type::U16},
      {"u32", Type::U32},     {"u64", Type::U64},     {"u128", Type::U128},
      {"usize", Type::Usize}, {"f32", Type::F32},     {"f64", Type::F64}};
  std::vector<std::unordered_map<std::string, Binding>> scopes;
  std::unordered_map<Function *, std::vector<int>> localVariables;
  std::unordered_map<const Function *, int> functionVariables;
  std::unordered_map<const Node *, int> nodeVariables;
  // Expression results whose evaluation already reported an error.
  std::vector<int> poisonedVariables;
  std::size_t reportedErrors = 0;
  std::unordered_set<const Node *> reusedNodes;
  // Built-in `lo..hi` ranges that are the source of a `for`: they keep the
  // structural counted-loop form; every other range value is a library range.
  std::unordered_set<const Node *> loopRanges;
  // `format` parameter bindings (by inference variable) and the nodes that may
  // hold a recipe or name one: arguments of `format` parameters, receivers.
  std::unordered_set<int> formatVariables;
  std::unordered_set<const Node *> permittedRecipes;
  bool formatMessage(Type type) const;
  void formatArguments(Node &call, const Function &callee, std::size_t offset);
  Function *current = nullptr;
  std::unordered_map<int, int> loopResults;
  std::vector<std::pair<int, Span>> integerOrBoolean;
  std::vector<std::pair<int, Span>> comparisons;
  struct NumericOperation {
    int variable;
    Span span;
    std::string operation;
  };
  std::vector<NumericOperation> numericOperations;
  struct FieldRequest {
    Node *node;
    int base, result;
    bool resolved = false;
    Type origin = Type::Unknown;
  };
  std::vector<FieldRequest> fieldRequests;
  std::unordered_map<const Function *, std::size_t> closureFunctions;
  std::unordered_map<const Node *, Type> closureContexts;
  std::unordered_map<const Node *, Type> expectedTypes;
  struct CaptureBinding {
    Binding source;
    int proxy;
    Span span;
  };
  std::unordered_map<const Function *, std::vector<CaptureBinding>>
      captureBindings;
  std::vector<std::pair<Function *, std::size_t>> closureScopes;

  NodeFacts &facts(const Node &node) { return checked.nodes[&node]; }
  FunctionFacts &facts(const Function &function) {
    if (auto found = closureFunctions.find(&function);
        found != closureFunctions.end())
      return checked.closureBodies.at(found->second)->function;
    return checked.functions.at(
        static_cast<std::size_t>(&function - module.functions.data()));
  }
  void error(std::string phase, Span span, std::string message);
  void coerce(Node &expression, int actual, int expected, Span span);
  int join(Node &left, int a, Node &right, int b, Span span);
  Type annotation(const TypeSyntax &syntax, Span span,
                  std::string_view owner = {});
  Type semanticAnnotation(const TypeSyntax &syntax, Span span,
                          std::string_view owner = {});
  unsigned semanticAnnotationDepth = 0;
  void checkRegions();
  void resolveRegionProjections();
  std::vector<RegionContract> regionContracts;
  struct AnnotationRegions {
    RegionScope scope;
    RegionEnvironment environment;
    std::unordered_map<std::string, RegionId> names;
    std::vector<RegionId> parameters;
    bool boundElision = false;
    RegionId fallback = RegionId::Unspecified;
  };
  std::vector<AnnotationRegions> annotationRegionScopes;
  std::unordered_map<const Function *, AnnotationRegions> functionRegionScopes;
  std::unordered_map<const TypeSyntax *, Type> semanticRegionAnnotations;
  RegionEnvironment emptyRegionEnvironment;
  std::vector<RegionId>
  pushRegionParameters(const std::vector<GenericParameter> &parameters,
                       Span span);
  void popRegionParameters();
  const RegionEnvironment &regionEnvironment() const;
  RegionId annotationRegion(const TypeSyntax &syntax, Span span);
  RegionId regionReference(std::string_view name, Span span);
  AnnotationRegions &functionRegions(const Function &function);
  void
  assumeRegionConstraints(const std::vector<GenericConstraint> &constraints,
                          Span span);
  Type callableAnnotation(const TypeSyntax &syntax, Span span,
                          std::string_view owner);
  Type callableRegionAnnotation(const TypeSyntax &syntax, Span span,
                                std::string_view owner);
  CallableType functionSignature(std::size_t index);
  int functionValue(Node &node, std::size_t index);
  int indirectCall(Node &node, bool reachable, int calleeVariable = -1);
  int closure(Node &node, bool reachable);
  void inferCaptures(ClosureFacts &closure);
  void contextualize(Node &node, Type expected);
  void resolveClosure(ClosureFacts &closure, bool final = false);
  void completeClosure(ClosureFacts &closure, bool final = false);
  void finishClosures();
  bool compatibleCallable(Type source, Type target) const;
  bool callableObligation(Type actual, Type contract, Span span);
  std::optional<Type> genericAnnotation(const TypeSyntax &syntax, Span span,
                                        std::string_view owner = {});
  const std::vector<Type> &genericBindings(Function &function);
  std::optional<int>
  genericCall(Node &node, bool reachable, std::size_t callee,
              std::size_t receiverOffset,
              std::span<const TypeBinding> ownerBindings = {},
              bool aliasConstructor = false);
  std::optional<int> genericConstruction(Node &node, bool reachable,
                                         std::string_view name);
  std::optional<CallableType> genericFunctionValue(Node &node,
                                                   std::size_t callee);
  struct GenericEnvironment;
  Type genericArgument(const GenericArgument &argument, Type parameter);
  void explicitGenericBindings(const Function &function, const Node &callee,
                               const GenericEnvironment &environment,
                               std::vector<TypeBinding> &bindings, Span span);
  Type constantType(const Node &node, Type expected = Type::Unknown);
  Type constantContext(const Node &node);
  struct GenericEnvironment {
    std::unordered_map<std::string, Type> names;
    std::map<Type, std::vector<TypeSyntax>> bounds;
    std::vector<Type> parameters;
    std::map<Type, Type> defaults;
    std::vector<TypeBinding> equalities;
    Span declarationSpan{};
    std::set<const GenericConstraint *> boundConstraints;
  };
  int genericCustomConstruction(Node &node, bool reachable, Type origin,
                                Type pattern, GenericEnvironment &environment,
                                bool alias);
  void seedInterfaceBindings(const Node &node,
                             const GenericEnvironment &environment,
                             std::vector<TypeBinding> &bindings);
  GenericEnvironment *genericEnvironment = nullptr;
  // Bounds on arguments that mention no type parameter (including defaults)
  // are proved once every implementation is registered.
  struct DeferredObligation {
    const GenericEnvironment *environment;
    GenericEnvironment *context;
    std::vector<TypeBinding> bindings;
    std::vector<Type> parameters;
    Span span;
  };
  // While set, genericObligations proves (`deferredOnly`) or skips only the
  // listed parameters.
  const std::vector<Type> *obligationParameters = nullptr;
  bool obligationsOnly = false;
  std::vector<DeferredObligation> deferredObligations;
  bool implementationsRegistered = false;
  void proveDeferredObligations();
  std::unordered_map<const Function *, GenericEnvironment> functionGenerics;
  std::unordered_map<const Module::Product *, GenericEnvironment>
      productGenerics;
  std::unordered_map<const Module::Alias *, GenericEnvironment> aliasGenerics;
  GenericEnvironment
  makeGenericEnvironment(const std::vector<GenericParameter> &parameters,
                         const std::vector<GenericConstraint> &constraints,
                         const GenericEnvironment *parent = nullptr);
  std::vector<Type>
  genericArguments(const std::vector<GenericParameter> &parameters,
                   const std::vector<GenericArgument> &arguments,
                   GenericEnvironment &environment, Span span);
  bool genericObligations(const GenericEnvironment &environment,
                          std::span<const TypeBinding> bindings, Span span,
                          std::span<const RegionBinding> regions = {});
  bool interfaceObligation(Type actual, const TypeSyntax &bound, Span span);
  bool interfaceObligation(Type actual, Type interfaceType, Span span);
  Type normalizeGenericType(Type type, std::span<const TypeBinding> bindings,
                            Span span);
  Type normalizeCallType(Type type, std::span<const TypeBinding> bindings,
                         const Function &callee, Span span);
  static bool inferredArgument(const GenericArgument &argument);
  bool agreesWherePartial(Type bound, Type partial);
  void inferFromExpected(Type pattern, Type expected,
                         std::vector<TypeBinding> &bindings);
  bool inferGeneric(Type pattern, Type actual,
                    std::vector<TypeBinding> &bindings, Span span);
  void prepareGenerics();
  std::unordered_map<std::string, std::size_t> interfaceNames;
  // Per method name: interface declarations whose hierarchy declares it.
  std::unordered_map<std::string, std::vector<bool>> methodInterfaces;
  const std::vector<bool> &interfacesDeclaring(const std::string &name);
  std::unordered_map<const Module::Interface *, GenericEnvironment>
      interfaceGenerics;
  std::unordered_map<const Module::Implementation *, GenericEnvironment>
      implementationGenerics;
  std::unordered_map<const TypeSyntax *, Type> implicitInterfaceParameters;
  std::map<Type, Span> erasedUses;
  unsigned interfaceDepth = 0;
  // Bounds whose assumptions are being elaborated; a bound that mentions a
  // projection of its own environment is proven coinductively, not re-expanded.
  std::set<const TypeSyntax *> elaboratingBounds;
  bool interfacesReady = false;
  struct ProjectionRequirement {
    Type subject, interfaceType;
    Span span;
    std::vector<interfaces::Obligation> assumptions;
    RegionEnvironment regions;
  };
  std::vector<ProjectionRequirement> projectionRequirements;
  std::unordered_map<const TypeSyntax *, Type> opaqueDeclarations;
  void interfaceHeaders();
  void interfaceSignatures();
  void interfaceImplementations();
  void checkInterfaceContracts();
  std::optional<Type> interfaceAnnotation(const TypeSyntax &syntax, Span span,
                                          std::string_view owner = {});
  Type interfaceBound(const TypeSyntax &bound, Span span,
                      std::string_view owner = {},
                      Type subject = Type::Unknown);
  bool interfaceProperty(const TypeSyntax &bound, std::string_view property,
                         Span span);
  bool intrinsicProperty(const TypeSyntax &bound, std::string_view property,
                         Span span) const;
  void concurrencyDeclaration(const Module::Implementation &syntax,
                              interfaces::Property property,
                              interfaces::Implementation &implementation);
  std::optional<interfaces::Property> propertyBound(const TypeSyntax &bound,
                                                    Span span) const;
  std::vector<interfaces::Obligation> interfaceAssumptions();
  bool unpinObligation(Type type, Span span);
  bool shareable(Type type, Span span);
  std::optional<std::size_t> interfaceMethod(Type self, std::string_view method,
                                             Node &call);
  Type interfaceProjection(Type subject, Type interfaceType,
                           std::string_view member,
                           std::span<const GenericArgument> arguments,
                           Span span);
  std::optional<Type> associatedConstant(const Node &node);
  void finalizeInterfaces();
  void finalizeErasure();
  bool eraseCoercion(Node &expression, Type source, Type target, Span span);
  bool unsizeCoercion(Node &expression, Type source, Type target, Span span);
  std::optional<int> operatorCall(Node &node, int left, int right = -1,
                                  bool mutableIndex = false);
  void requireMutablePlace(Node &node);
  std::optional<std::size_t> receiverMethod(Type source, Node &call);
  std::optional<std::size_t> receiverCandidate(Type self, ParameterMode mode,
                                               std::string_view name,
                                               Node &call);
  std::optional<ReceiverStep> dereferenceStep(Type source, bool exclusive,
                                              Span span);
  bool mutableReceiverPlan(ReceiverPlan &plan, Span span, bool report = true);
  std::optional<ReceiverPlan> receiverConversion(Type source, Type target,
                                                 ParameterMode mode, Span span,
                                                 bool report = true);
  bool borrowCoercion(Node &node, int actual, Type target, ParameterMode mode);
  void
  validateGenericEnvironment(const std::vector<GenericParameter> &parameters,
                             const std::vector<GenericConstraint> &constraints,
                             GenericEnvironment &environment);
  // Binds parameters that bounds and equalities determine from those already
  // bound (`A: Future<Output = X>` fixes `X` once `A` is known).
  void propagateGenericBindings(const GenericEnvironment &environment,
                                std::vector<TypeBinding> &bindings, Span span);
  void completeGenericBindings(const GenericEnvironment &environment,
                               std::vector<TypeBinding> &bindings, Span span);
  unsigned genericDepth = 0;
  std::map<std::pair<std::size_t, std::vector<Type>>, Type>
      genericAliasInstances;
  std::set<std::pair<std::size_t, std::vector<Type>>> activeGenericAliases;
  struct GenericCallRequest {
    Node *node;
    Function *function;
    int result;
    std::vector<TypeBinding> bindings;
    GenericEnvironment *environment;
    Function *caller;
    // Declaration result last resolved; an unchanged one needs no rework.
    Type resolvedDeclaration = Type::Unknown;
  };
  std::vector<GenericCallRequest> genericCallRequests;
  void resolveGenericCalls();
  // A generic call at the tail of an `if`/`match` branch (or an argument of
  // such a call) may leave parameters that only the other branches fix, as in
  // `if c { left(a) } else { right(b) }`; the join completes it.
  struct DeferredCall {
    Function *function;
    std::vector<TypeBinding> bindings;
    std::vector<Type> signature;
    Type resultPattern, errorPattern;
    int variable;
    std::size_t request;
    GenericEnvironment *environment, *caller;
    Function *owner;
    std::vector<RegionBinding> explicitRegions;
  };
  std::unordered_set<const Node *> deferrableCalls;
  std::unordered_map<const Node *, DeferredCall> deferredCalls;
  void markDeferrable(Node &tail);
  bool partialType(Type type);
  Type mergePartial(Type a, Type b);
  void refineDeferred(Node &tail, Type expected);
  void finishDeferred(Node &call, DeferredCall deferred, Type expected);
  // Completes the deferred calls at the given branch tails from their join.
  void joinDeferred(std::span<Node *const> tails, std::span<const int> types);
  void declarations();
  Type resolveAlias(std::size_t index, unsigned depth = 0);
  unsigned aliasDepth = 0;
  unsigned effectContext = 0;
  std::unordered_map<const Pattern *, int> patternVariables;
  bool patternGuard = false;
  std::vector<std::pair<Node *, int>> matches;
  std::vector<std::pair<Pattern *, int>> irrefutable;
  int bindingPattern(Node &node, bool reachable);
  int conditionalPattern(Node &node, bool reachable);
  std::string definitionName(Span span, std::string_view spelling) const;
  // Product declarations with this canonical name, in declaration order.
  const std::vector<const Module::Product *> &
  productsNamed(const std::string &name) const;
  std::string typeName(std::string_view spelling, Span span,
                       std::string_view owner = {}) const;
  std::string callableName(std::string_view spelling, std::string_view owner,
                           Span span) const;
  bool visibleField(Type type, std::size_t field, Span use);
  Binding lookup(const std::string &name, Span span);
  int local(std::string name, int variable, bool mutableBinding, Span span);
  Flow flow(Node &node, std::string_view owner = {});
  void controlFlow(Function &function);
  bool pathContainer(std::string_view spelling, const Function *function,
                     Span span) const;
  void qualifyDottedPath(Node &node, const std::set<std::string> &lexical,
                         const Function *function);
  void qualifyDottedPaths(Node &node);
  int loop(Node &node, bool reachable);
  bool implementsProtocol(Type type, std::string_view interface, Span span);
  bool desugarIteration(Node &node, Type source);
  std::optional<int> genericUnitVariant(Node &node);
  int transfer(Node &node, bool reachable);
  Type literal(const Node &node, bool negative = false);
  void function(Function &function);
  void parameterDefaults(Function &function);
  void constructor(Function &function);
  bool constructorShapeMatches(const Function &function, const Node &call);
  bool constructorShapesOverlap(const Function &a, const Function &b);
  void registerConstructors();
  std::optional<std::vector<TypeBinding>>
  constructorApplicability(const ConstructorCandidate &candidate, Type type,
                           Span span, interfaces::Solver &solver,
                           std::span<const TypeBinding> seed = {});
  void completeArguments(Node &node, Function &function,
                         const std::vector<bool> &used,
                         bool reportMissing = true);
  int node(Node &node, bool reachable);
  int checkNode(Node &node, bool reachable);
  int call(Node &node, bool reachable);
  std::optional<int> machineCall(Node &node, bool reachable, int receiver = -1);
  void products();
  void fields(bool final = true);
  int sumExpression(Node &node, bool reachable);
  int aggregate(Node &node, bool reachable);
  std::optional<std::int32_t> constantInteger(const Node &node);
  std::optional<int> variantCall(Node &node, std::string_view name,
                                 bool reachable);
  int match(Node &node, bool reachable);
  void pattern(Pattern &pattern, int variable, ParameterMode mode);
  void resolvePatterns();
  void exhaustiveness();
  PatternFacts &facts(const Pattern &pattern) {
    return checked.patterns[&pattern];
  }
};
} // namespace mettle
