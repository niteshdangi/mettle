#pragma once

#include "places/place.h"
#include "source/source.h"
#include "types/assembly.h"
#include "types/type.h"
#include <cstdint>
#include <memory>
#include <ostream>
#include <vector>

namespace mettle::ir {
enum class Access { Owned, Read, Mut };
enum class InlineHint { Default, Hint, Always, Never };
struct Value {
  int id = -1;
  Type type = Type::Never;
  Access access = Access::Owned;
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
  TextLiteral
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
  };
  std::vector<WitnessEntry> witnessEntries{};
  std::optional<NumericLiteral> numeric{};
  bool unsafeAllowed = false;
  // Semantic subjects retain their regions; second members name runtime types.
  std::vector<std::pair<Type, Type>> unpinProofs{};
  std::optional<Assembly> assembly{};
  // Source lexical scope active when this instruction was lowered.
  int scope = 0;
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
};
struct Block {
  std::vector<Instruction> instructions;
  Terminator exit;
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
  };
  std::vector<ArrayLoop> arrayLoops{};
  // A coroutine body runs inside a `CoroutineState` frame and may suspend.
  bool coroutine = false;
  // Declaration span of the source function; empty for synthesized ones.
  Span span{};
  // Optimization policy only; never changes source-level execution.
  InlineHint inlineHint = InlineHint::Default;
};
struct Program {
  struct Static {
    std::string name, externalName, library;
    Type type;
    bool mutableBinding = false, foreignDeclaration = false;
    Span span{};
    std::optional<StaticConstant> initializer{};
  };
  std::vector<Function> functions;
  // Optional package-instance ownership, aligned with `functions` and
  // `statics`; an empty entry means root-owned or owner-ambiguous.
  std::vector<std::string> functionPackages{};
  std::shared_ptr<const TypeStore> types = std::make_shared<const TypeStore>();
  std::vector<int> closureFunctions{};
  struct OpaqueAdapter {
    Type self, interfaceType;
    int method, function;
    std::vector<Type> methodArguments;
  };
  std::vector<OpaqueAdapter> opaqueAdapters{};
  bool requireEntry = true;
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
