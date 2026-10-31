#pragma once

#include "cleanup/plan.h"
#include "types/layout.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include <functional>
#include <unordered_map>

namespace mettle::backend {
class CleanupFrame;
struct LoweringContext {
  const ir::Program &program;
  llvm::LLVMContext &context;
  llvm::Module &module;
  llvm::IRBuilder<> &builder;
  std::vector<llvm::Function *> &functions;
  std::unordered_map<std::uint32_t, llvm::StructType *> products;
  std::unordered_map<std::uint32_t, ObjectLayout> layouts{};
  std::unordered_map<std::uint32_t, bool> indirects{};
  bool freestanding = false;
  std::vector<llvm::GlobalVariable *> statics{};
  // The persistent frame of a coroutine state's body.
  std::function<CleanupFrame &(Type)> coroutine{};

  const ObjectLayout &layout(Type type);
  std::uint64_t alignment(Type type);
  // Aggregates above this size are passed as pointers to immutable snapshots
  // in stack temporaries instead of first-class LLVM values.
  static constexpr std::uint64_t indirectThreshold = 1024;
  bool indirect(Type type);
  llvm::Type *layoutType(Type type);
  llvm::Type *type(Type type);
  llvm::Type *storageType(Type type);
  llvm::Value *zero(Type type);
  Type fieldType(Type owner, unsigned field);
  std::uint64_t fieldOffset(Type owner, unsigned field);
  llvm::Value *load(Type type, llvm::Value *address, llvm::Align alignment);
  void store(Type type, llvm::Value *value, llvm::Value *address,
             llvm::Align alignment);
  llvm::Type *viewType(Type payload);
  llvm::AllocaInst *temporary(llvm::Type *type);
  llvm::AllocaInst *temporary(Type type);
  llvm::Value *fieldPointer(llvm::Value *address, Type owner, unsigned field);
  llvm::Value *fieldAddress(llvm::Value *address, Type &owner, unsigned field);
  llvm::Value *projectField(llvm::Value *handle, Type owner, unsigned field);
  llvm::Value *construct(Type type, llvm::ArrayRef<llvm::Value *> fields,
                         unsigned selected = 0);
  llvm::Value *variant(Type type, unsigned ordinal,
                       llvm::ArrayRef<llvm::Value *> fields);
  llvm::Value *enumTag(Type type, llvm::Value *address, bool ordinal = true);
  llvm::Value *extract(llvm::Value *value, Type owner, unsigned field);
  llvm::Type *resultType(Type type);
  llvm::FunctionCallee runtime(llvm::StringRef name, llvm::Type *result,
                               llvm::ArrayRef<llvm::Type *> parameters);
  llvm::Function *callback(const llvm::Twine &name, bool cleanup = false);
};

// All addresses used by unwind callbacks refer to the wrapper's frame, never
// the body callback's stack. Flags describe ownership, not byte initialization.
class CleanupFrame {
public:
  CleanupFrame(LoweringContext &lowering, const ir::Function &source,
               llvm::Function *wrapper);
  // A coroutine body's frame is the state of its future. Its layout is known
  // on construction; callbacks are emitted once every function is declared.
  CleanupFrame(LoweringContext &lowering, const ir::Function &source,
               std::string name);
  llvm::Function *body() const { return bodyFunction; }
  llvm::Function *unwind() const { return cleanupFunction; }
  llvm::StructType *structure() const { return frameType; }
  std::uint64_t size() const {
    return (frameSize + frameAlignment - 1) & ~(frameAlignment - 1);
  }
  std::uint64_t align() const { return frameAlignment; }
  void finishCallbacks();
  // Coroutine protocol. The state field holds 0 before the first resumption,
  // the suspension point while suspended, `running` while the body executes
  // or after it panicked, and `complete` after it returned.
  static constexpr int running = -2, complete = -1;
  void startCoroutine(llvm::Value *state, llvm::Value *environment);
  // Runs the body once; the result is `optional` of the body's result.
  llvm::Value *resumeCoroutine(llvm::Value *state, llvm::Value *context,
                               Type optional);
  llvm::Value *stateAddress() { return field(stateField); }
  llvm::Value *contextAddress() { return field(contextField); }
  bool spilled(int value) const { return spills.contains(value); }
  llvm::Value *spillAddress(int value) { return field(spills.at(value)); }
  llvm::Value *createWrapper();
  llvm::Value *address(const Place &place);
  llvm::Align alignment(const Place &place);
  void declare(const Place &place);
  void move(const Place &place);
  void store(const ir::Instruction &instruction, llvm::Value *value);
  void dropPlace(const Place &place);
  void remember(ir::Value value, llvm::Value *result);
  void consume(ir::Value value);
  void scopeExit(int scope);
  void returnValue(ir::Value value, llvm::Value *result);
  void finishWrapper(llvm::Value *frame);
  llvm::Value *variadicContext();
  // Storage of a source local in the body callback; a borrowed local's
  // storage holds the pointer to its value.
  llvm::Value *localStorage(std::size_t local) {
    return field(localFields.at(local));
  }

private:
  CleanupFrame(LoweringContext &lowering, const ir::Function &source,
               llvm::Function *wrapper, std::string name);
  struct Root {
    Type type;
    unsigned field;
    unsigned node;
    int local = -1;
    bool indirect = false;
    Place place;
  };
  struct Node {
    Type type;
    int destructor;
    unsigned root;
    unsigned flag;
    int parent;
    std::vector<unsigned> path;
    std::vector<unsigned> children;
    int relocation = -1;
    int relocatedFlag = -1;
    NativeCleanup nativeAction = NativeCleanup::None;
  };
  struct Replacement {
    unsigned destination;
    unsigned pointer;
    unsigned pending;
    llvm::Function *destroy;
    llvm::Function *install;
  };
  LoweringContext &lowering;
  const ir::Function &source;
  llvm::Function *wrapper;
  llvm::Function *bodyFunction;
  llvm::Function *cleanupFunction;
  llvm::StructType *frameType;
  llvm::Value *frame = nullptr;
  unsigned resultField;
  std::string name;
  bool callbacksEmitted = false;
  unsigned stateField = 0, contextField = 0;
  std::unordered_map<int, unsigned> spills;
  cleanup::Plan plan;
  std::vector<llvm::Type *> fields;
  std::uint64_t frameSize = 0, frameAlignment = 1;
  std::vector<Root> roots;
  std::vector<Node> nodes;
  std::vector<unsigned> locals;
  std::vector<unsigned> localFields;
  std::vector<unsigned> planNodes;
  std::unordered_map<int, unsigned> values;
  std::vector<Replacement> replacements;
  std::unordered_map<const ir::Instruction *, unsigned> replacementIndices;
  std::unordered_map<unsigned, llvm::Function *> drops;

  unsigned addField(llvm::Type *type, std::uint64_t alignment = 0);
  void clearFlags();
  void bindStatics();
  unsigned addRoot(const cleanup::Plan &plan, int place, int local = -1);
  unsigned addNode(const cleanup::Plan &plan, int place, unsigned root,
                   int parent, std::vector<unsigned> path);
  unsigned placeNode(const Place &place) const;
  llvm::Value *field(unsigned index);
  llvm::Value *nodeAddress(unsigned node);
  void set(unsigned node, bool initialized);
  void initialize(unsigned node, llvm::Value *initialized);
  void updateParents(unsigned node);
  void drop(unsigned node);
  llvm::Function *dropCallback(unsigned node);
  void emitCallbacks();
  void emitReplacement(Replacement &replacement);
  void callDrop(unsigned node, llvm::Value *unwinding);
  std::vector<unsigned> cleanupOrder() const;
};
} // namespace mettle::backend
