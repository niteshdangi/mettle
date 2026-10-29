#pragma once

#include "places/place.h"
#include "resolution/resolve.h"
#include "semantics/interfaces.h"
#include "syntax/ast.h"
#include "types/assembly.h"
#include "types/type.h"
#include <cstdint>
#include <set>
#include <unordered_map>
#include <utility>

namespace mettle {
struct Flow {
  bool normal = true;
  bool returns = false;
  std::set<int> breaks;
  std::set<int> continues;
};
struct ReceiverStep {
  enum class Kind { Native, Projection, Unsize, Erase };
  Kind kind = Kind::Native;
  Type source = Type::Unknown, target = Type::Unknown;
  Type resultView = Type::Unknown;
  Type count = Type::Unknown;
  ParameterMode mode = ParameterMode::Read;
  int callee = -1;
  std::vector<Type> typeArguments{};
  Type interfaceSelf = Type::Unknown, interfaceType = Type::Unknown;
  int interfaceMethod = -1;
};
struct ReceiverPlan {
  Type source = Type::Unknown, target = Type::Unknown;
  std::vector<ReceiverStep> steps{};
};
struct NodeFacts {
  Type type = Type::Unknown;
  int slot = -1;
  int callee = -1;
  int field = -1;
  int control = -1;
  int variant = -1;
  Type effect = Type::Unknown;
  Type readView = Type::Unknown, mutView = Type::Unknown;
  ParameterMode iterationMode = ParameterMode::Read;
  std::vector<Type> injections{};
  Type rebuiltType = Type::Unknown;
  bool constructor = false;
  bool method = false;
  bool receiverReservation = false;
  bool optional = false;
  Type interfaceType = Type::Unknown;
  Type interfaceSelf = Type::Unknown;
  int interfaceMethod = -1;
  unsigned hiddenReceiver = 0;
  int witness = -1;
  Type erasedSource = Type::Unknown;
  Type opaqueSource = Type::Unknown;
  Type unsizedSource = Type::Unknown;
  Type unsizedCount = Type::Unknown;
  Type reborrowSource = Type::Unknown;
  unsigned dereferences = 0;
  std::optional<Place> place;
  std::int32_t number = 0;
  bool foldedNegativeLiteral = false;
  std::optional<NumericLiteral> numeric{};
  std::string machineOperation{};
  Type machineType = Type::Unknown;
  std::vector<Type> unpinRequirements{};
  std::vector<ParameterMode> machineBorrowModes{};
  std::vector<std::size_t> argumentOrder;
  std::vector<std::size_t> defaultArguments;
  bool indirect = false;
  bool operatorCall = false;
  bool exclusivePlace = false;
  bool unsafeContext = false, writeOnly = false;
  Type indexView = Type::Unknown;
  int closure = -1;
  Type callableCoercion = Type::Unknown;
  Type callableSource = Type::Unknown;
  Flow flow;
  std::vector<Type> typeArguments{};
  std::vector<Type> implementationArguments{};
  Type constantParameter = Type::Unknown;
  Type constantCount = Type::Unknown;
  Type elementView = Type::Unknown;
  std::vector<Type> callParameterTypes{};
  Type callResult = Type::Unknown;
  std::vector<Type> callDefaultAbiResults{}, callDefaultValueTypes{};
  std::optional<ReceiverPlan> receiverPlan{}, borrowConversion{},
      viewConversion{};
  Type conversionView = Type::Unknown;
  std::optional<Assembly> assembly{};
  std::set<std::string> targetFeatures{};
};
struct Local {
  std::string name;
  Type type;
  bool mutableBinding;
  Span span;
  ParameterMode mode = ParameterMode::Value;
  bool patternView = false;
  StorageDuration storage = StorageDuration::Automatic;
  int staticIndex = -1;
};
struct FunctionFacts {
  Type result = Type::Unknown;
  bool diverges = false;
  std::vector<Local> locals;
  std::vector<std::size_t> resultSources;
  Type error = Type::Unknown;
  Type abiResult = Type::Unknown;
  std::vector<Type> defaultAbiResults;
  std::vector<Type> defaultValueTypes;
  std::vector<bool> defaultBorrowed;
  std::vector<bool> defaultBorrowOperand;
  std::unordered_map<int, std::size_t> parameterBindings;
  std::unordered_map<int, std::pair<Type, Type>> parameterViewTypes;
  int constructorSelfSlot = -1;
  std::string canonicalName{};
  Type opaqueResult = Type::Unknown;
  Type regionSignature = Type::Unknown;
  std::vector<Type> genericParameters{};
  std::vector<std::size_t> genericResultSources{};
  std::vector<std::pair<Type, Type>> interfaceBounds{};
  std::vector<Type> unpinBounds{};
  std::vector<TypeBinding> genericEqualities{};
  std::string externalName{};
  FloatingPolicy floatingPolicy{};
  std::string library{};
  int variadicCursor = -1;
  std::set<std::string> targetFeatures{};
  bool naked = false;
};
struct StaticFacts {
  std::string name, externalName, library;
  Type type = Type::Unknown;
  std::optional<StaticConstant> initializer{};
  std::size_t identity = 0;
};
struct RegionContract {
  std::size_t implementation, declaration;
  Span span;
  std::vector<TypeBinding> bindings{};
};
struct PatternFacts {
  Type type = Type::Unknown;
  int slot = -1;
  int variant = -1;
  std::vector<std::uint32_t> fields;
  int guardSlot = -1;
  std::optional<Projection> slice{};
  std::int32_t number = 0;
  std::optional<NumericLiteral> numeric{};
};
struct ClosureCapture {
  Place source;
  Place proxy;
  Type type = Type::Unknown;
  Type storedType = Type::Unknown;
  ParameterMode mode = ParameterMode::Read;
  Span span;
};
struct ClosureFacts {
  Function declaration;
  const Node *syntax = nullptr;
  const Function *parent = nullptr;
  FunctionFacts function;
  std::vector<ClosureCapture> captures;
  Type type = Type::Unknown;
  bool deferred = false;
};

class Checker;
class CheckedModule {
public:
  CheckedModule(CheckedModule &&) = default;
  CheckedModule &operator=(CheckedModule &&) = default;
  const Module &syntax() const { return tree; }
  const TargetFacts &target() const { return targetDescription; }
  const std::vector<Assembly> &globalAssembly() const { return assemblyItems; }
  const NodeFacts &facts(const Node &node) const { return nodes.at(&node); }
  const PatternFacts &facts(const Pattern &pattern) const {
    return patterns.at(&pattern);
  }
  const FunctionFacts &function(std::size_t index) const {
    return functions.at(index);
  }
  const std::vector<StaticFacts> &statics() const { return staticStorage; }
  std::shared_ptr<const TypeStore> typeStore() const { return types; }
  const resolution::Resolution &namespaces() const { return *symbols; }
  const interfaces::Database &interfaceDatabase() const {
    return *interfaceData;
  }
  const std::vector<std::unique_ptr<ClosureFacts>> &closures() const {
    return closureBodies;
  }

private:
  friend class Checker;
  explicit CheckedModule(Module module,
                         std::shared_ptr<const resolution::Resolution> symbols)
      : tree(std::move(module)), symbols(std::move(symbols)) {}
  Module tree;
  TargetFacts targetDescription{};
  std::vector<Assembly> assemblyItems{};
  std::unordered_map<const Node *, NodeFacts> nodes;
  std::unordered_map<const Pattern *, PatternFacts> patterns;
  std::vector<FunctionFacts> functions;
  std::vector<StaticFacts> staticStorage;
  std::vector<std::unique_ptr<ClosureFacts>> closureBodies;
  std::shared_ptr<TypeStore> types = std::make_shared<TypeStore>();
  std::shared_ptr<const resolution::Resolution> symbols;
  std::shared_ptr<interfaces::Database> interfaceData =
      std::make_shared<interfaces::Database>();
};
} // namespace mettle
