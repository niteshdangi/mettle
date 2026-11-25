#pragma once

#include "places/place.h"
#include "source/source.h"
#include "types/assembly.h"
#include "types/type.h"
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <ostream>
#include <string>
#include <utility>
#include <vector>

namespace mettle::ir {
enum class Access { Owned, Read, Mut };
enum class InlineHint { Default, Hint, Always, Never };
struct Value {
  int id = -1;
  Type type = Type::Never;
  Access access = Access::Owned;
  bool operator==(const Value &) const = default;
};
struct Local {
  std::string name;
  Type type;
  bool mutableBinding;
  Span span;
  ParameterMode mode = ParameterMode::Value;
  int scope = 0;
  std::uint32_t order = 0;
  StorageDuration storage = StorageDuration::Automatic;
  int staticIndex = -1;
  bool operator==(const Local &) const = default;
};
enum class Op {
  Constant,
  Declare,
  Load,
  Store,
  Unary,
  Binary,
  Call,
  Phi,
  Construct,
  Project,
  Move,
  BorrowRead,
  BorrowMut,
  ReserveMut,
  Activate,
  ViewRead,
  ViewMut,
  ScopeExit,
  CatchCall,
  VariantConstruct,
  VariantTest,
  Panic,
  FunctionAddress,
  IndirectCall,
  ArrayBorrowRead,
  ArrayBorrowMut,
  ArrayRepeat,
  ArrayTake,
  CallableCoerce,
  EraseView,
  OwnerUnsize,
  ErasedUpcast,
  WitnessMethod,
  OpaqueRepack,
  UnsizeView,
  SliceLength,
  SliceBorrowRead,
  SliceBorrowMut,
  Cast,
  Machine,
  StorageWrite,
  DropPlace,
  Assembly,
  FeatureTest,
  TextLiteral,
  RawAddress
};
struct Instruction {
  Op op;
  Value result;
  std::vector<Value> operands;
  std::vector<int> predecessors;
  std::string text;
  Place place;
  int callee = -1;
  std::int32_t number = 0;
  Span span;
  Value target{};
  Type indirectType = Type::Unknown;
  std::vector<std::size_t> callLocalParameters{};
  std::vector<Type> typeArguments{};
  Type constantParameter = Type::Unknown;
  Type interfaceType = Type::Unknown;
  Type interfaceSelf = Type::Unknown;
  int interfaceMethod = -1;
  int dropFunction = -1;
  bool erasedDispatch = false;
  Type opaqueType = Type::Unknown;
  struct WitnessEntry {
    Type owner;
    std::size_t method;
    bool operator==(const WitnessEntry &) const = default;
  };
  std::vector<WitnessEntry> witnessEntries{};
  std::optional<NumericLiteral> numeric{};
  bool unsafeAllowed = false;
  // Semantic subjects retain their regions; second members name runtime types.
  std::vector<std::pair<Type, Type>> unpinProofs{};
  std::optional<Assembly> assembly{};
  // Source lexical scope active when this instruction was lowered.
  int scope = 0;
  bool operator==(const Instruction &) const = default;
};
// `Suspend` ends a coroutine poll; the next poll resumes at `first`. Analyses
// treat it as a jump because the frame, its places and its loans persist.
enum class Exit { None, Jump, Branch, Return, Unreachable, Suspend };
constexpr bool continues(Exit kind) {
  return kind == Exit::Jump || kind == Exit::Suspend;
}
struct Terminator {
  Exit kind = Exit::None;
  Value value{};
  int first = -1;
  int second = -1;
  Span span{};
  bool unpredictable = false;
  bool operator==(const Terminator &) const = default;
};
struct Block {
  std::vector<Instruction> instructions;
  Terminator exit;
  bool operator==(const Block &) const = default;
};
struct Function {
  std::string name;
  Type result;
  std::size_t parameters;
  std::vector<Local> locals;
  std::vector<Block> blocks;
  int values = 0;
  struct Scope {
    int parent = -1;
    bool operator==(const Scope &) const = default;
  };
  std::vector<Scope> scopes{{-1}};
  std::vector<std::size_t> resultSources{};
  std::vector<std::size_t> resultContents{};
  // (source, target) parameters from `Within` bounds; see FunctionFacts.
  std::vector<std::pair<std::size_t, std::size_t>> withinFlows{};
  std::string externalName{};
  bool twoPhaseReceiver = false;
  int constructorSelfSlot = -1;
  bool indirectContract = false;
  // Access parameters whose views a called value cannot retain.
  std::vector<std::size_t> callLocalParameters{};
  std::vector<Type> genericParameters{};
  bool declarationOnly = false;
  std::vector<std::size_t> genericResultSources{};
  std::vector<std::pair<Type, Type>> interfaceBounds{};
  std::vector<Type> unpinBounds{};
  std::vector<Type> sizedBounds{};
  Type regionSignature = Type::Unknown;
  // Declared interface signature result when the body's concrete result
  // differs (an async default with an inferred future); calls not yet
  // resolved to an implementation are checked against it.
  Type interfaceResult = Type::Unknown;
  std::vector<TypeBinding> genericEqualities{};
  bool unsafeFunction = false;
  std::string abi{};
  bool foreignDeclaration = false;
  bool exportedDefinition = false;
  bool variadic = false;
  FloatingPolicy floatingPolicy{};
  int variadicCursor = -1;
  std::set<std::string> targetFeatures{};
  std::optional<Assembly> nakedAssembly{};
  struct ArrayLoop {
    int header, body, step, done;
    std::vector<int> blocks;
    Place source;
    Value index;
    int element;
    ParameterMode mode;
    bool operator==(const ArrayLoop &) const = default;
  };
  std::vector<ArrayLoop> arrayLoops{};
  // A coroutine body runs inside a `CoroutineState` frame and may suspend.
  bool coroutine = false;
  // Declaration span of the source function; empty for synthesized ones.
  Span span{};
  // Optimization policy only; never changes source-level execution.
  InlineHint inlineHint = InlineHint::Default;
  bool trackCaller = false;
  Function externalDeclaration(std::string symbol) const {
    Function declaration;
    declaration.name = name;
    declaration.result = result;
    declaration.parameters = parameters;
    declaration.locals = locals;
    declaration.locals.resize(parameters);
    declaration.scopes = scopes;
    declaration.resultSources = resultSources;
    declaration.resultContents = resultContents;
    declaration.withinFlows = withinFlows;
    declaration.externalName = std::move(symbol);
    declaration.twoPhaseReceiver = twoPhaseReceiver;
    declaration.indirectContract = indirectContract;
    declaration.callLocalParameters = callLocalParameters;
    declaration.genericParameters = genericParameters;
    declaration.genericResultSources = genericResultSources;
    declaration.interfaceBounds = interfaceBounds;
    declaration.unpinBounds = unpinBounds;
    declaration.sizedBounds = sizedBounds;
    declaration.regionSignature = regionSignature;
    declaration.interfaceResult = interfaceResult;
    declaration.genericEqualities = genericEqualities;
    declaration.unsafeFunction = unsafeFunction;
    declaration.abi = abi;
    declaration.foreignDeclaration = foreignDeclaration;
    declaration.variadic = variadic;
    declaration.floatingPolicy = floatingPolicy;
    declaration.variadicCursor = variadicCursor;
    declaration.targetFeatures = targetFeatures;
    declaration.coroutine = coroutine;
    declaration.span = span;
    declaration.inlineHint = inlineHint;
    declaration.trackCaller = trackCaller;
    return declaration;
  }
  bool operator==(const Function &) const = default;
};
void remapTypes(Function &function, const std::function<Type(Type)> &remap);
struct FunctionIndex {
  std::string name;
  Type result = Type::Unknown;
  std::size_t parameters = 0;
  bool generic = false, declarationOnly = false, exportedDefinition = false,
       indirectContract = false, naked = false, hasAbi = false,
       hasExternalName = false, hasVariadicCursor = false;
  std::set<std::string> targetFeatures;
  bool valid = false;
};
FunctionIndex indexFunction(const Function &function);
class StaticInitializer {
public:
  using Loader = std::function<std::shared_ptr<const StaticConstant>()>;
  StaticInitializer() = default;
  StaticInitializer(std::nullptr_t) {}
  template <class T>
  StaticInitializer(std::shared_ptr<T> value) : value(std::move(value)) {}
  static StaticInitializer deferred(Loader load) {
    StaticInitializer result;
    result.pending = std::make_shared<Pending>();
    result.pending->load = std::move(load);
    return result;
  }
  explicit operator bool() const { return value || pending; }
  bool operator==(std::nullptr_t) const { return !*this; }
  const StaticConstant *get() const {
    if (!pending)
      return value.get();
    std::call_once(pending->once, [this] {
      pending->value = pending->load();
      pending->load = nullptr;
    });
    return pending->value.get();
  }
  const StaticConstant &operator*() const { return *get(); }
  const StaticConstant *operator->() const { return get(); }

private:
  struct Pending {
    std::once_flag once;
    Loader load;
    std::shared_ptr<const StaticConstant> value;
  };
  std::shared_ptr<const StaticConstant> value;
  std::shared_ptr<Pending> pending;
};
struct Program {
  struct Static {
    std::string name, externalName, library;
    Type type;
    bool mutableBinding = false, foreignDeclaration = false;
    Span span{};
    StaticInitializer initializer{};
    bool trustedInitializer = false;
  };
  TypeRecords<Function, true> functions;
  std::shared_ptr<const std::vector<FunctionIndex>> functionIndex{};
  std::vector<std::uint32_t> functionIndexRecords{};
  const FunctionIndex *deferredFunctionIndex(std::size_t index) const {
    if (!functionIndex || index >= functions.size() ||
        functions.isMaterialized(index))
      return nullptr;
    std::size_t record = index;
    if (!functionIndexRecords.empty()) {
      if (index >= functionIndexRecords.size() ||
          functionIndexRecords[index] == UINT32_MAX)
        return nullptr;
      record = functionIndexRecords[index];
    }
    return record < functionIndex->size() && (*functionIndex)[record].valid
               ? &(*functionIndex)[record]
               : nullptr;
  }
  // Optional package-instance ownership, aligned with `functions` and
  // `statics`; an empty entry means root-owned or owner-ambiguous.
  std::vector<std::string> functionPackages{};
  // Archive record ordinals for imported functions whose CFGs are deferred.
  std::vector<std::optional<std::size_t>> lazyFunctionRecords{};
  std::vector<std::optional<std::size_t>> declarationSources{};
  std::shared_ptr<const TypeStore> types = std::make_shared<const TypeStore>();
  std::vector<int> closureFunctions{};
  // Interface dispatch for an opaque or erased self type, selected when a
  // generic call is instantiated with it.
  struct OpaqueAdapter {
    Type self, interfaceType;
    int method, function;
    std::vector<Type> methodArguments;
  };
  std::vector<OpaqueAdapter> opaqueAdapters{};
  bool requireEntry = true;
  // Functions imported unchanged from a checked library; an executable
  // instantiates the ones its entry reaches. Not part of the encoding.
  std::vector<bool> libraryBodies{};
  // Verified bodies supplied only for cross-object optimization.
  std::vector<bool> availableExternally{};
  // Concrete generic instances may be emitted in more than one object.
  std::vector<bool> genericInstances{};
  std::vector<Static> statics{};
  std::vector<std::string> staticPackages{};
  std::vector<std::string> libraries{};
  TargetFacts target{};
  std::vector<Assembly> globalAssembly{};
  // Coroutine state types of the instance program and their body functions.
  std::vector<std::pair<Type, int>> coroutines{};
  // Specialized `core.slice.drop_values<T>` functions used for dynamic drops.
  std::vector<std::pair<Type, int>> dynamicDropFunctions{};
};

void print(const Program &program, std::ostream &out);
} // namespace mettle::ir
