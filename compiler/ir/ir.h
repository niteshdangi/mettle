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
  FeatureTest
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
  std::vector<Type> typeArguments{};
  Type constantParameter = Type::Unknown;
  Type interfaceType = Type::Unknown;
  Type interfaceSelf = Type::Unknown;
  int interfaceMethod = -1;
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
};
enum class Exit { None, Jump, Branch, Return, Unreachable };
struct Terminator {
  Exit kind = Exit::None;
  Value value{};
  int first = -1;
  int second = -1;
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
  std::string externalName{};
  bool twoPhaseReceiver = false;
  int constructorSelfSlot = -1;
  bool indirectContract = false;
  std::vector<Type> genericParameters{};
  bool declarationOnly = false;
  std::vector<std::size_t> genericResultSources{};
  std::vector<std::pair<Type, Type>> interfaceBounds{};
  std::vector<Type> unpinBounds{};
  Type regionSignature = Type::Unknown;
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
  std::vector<std::string> libraries{};
  TargetFacts target{};
  std::vector<Assembly> globalAssembly{};
};

void print(const Program &program, std::ostream &out);
} // namespace mettle::ir
