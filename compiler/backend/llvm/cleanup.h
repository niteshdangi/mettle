#pragma once

#include "cleanup/plan.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include <unordered_map>

namespace mettle::backend {
struct LoweringContext {
  const ir::Program &program;
  llvm::LLVMContext &context;
  llvm::Module &module;
  llvm::IRBuilder<> &builder;
  std::vector<llvm::Function *> &functions;
  std::unordered_map<std::uint32_t, llvm::StructType *> products;

  llvm::Type *type(Type type);
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
  llvm::Function *body() const { return bodyFunction; }
  llvm::Value *createWrapper();
  llvm::Value *address(const Place &place);
  void declare(const Place &place);
  void move(const Place &place);
  void store(const ir::Instruction &instruction, llvm::Value *value);
  void remember(ir::Value value, llvm::Value *result);
  void consume(ir::Value value);
  void scopeExit(int scope);
  void returnValue(ir::Value value, llvm::Value *result);
  void finishWrapper(llvm::Value *frame);

private:
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
  cleanup::Plan plan;
  std::vector<llvm::Type *> fields;
  std::vector<Root> roots;
  std::vector<Node> nodes;
  std::vector<unsigned> locals;
  std::vector<unsigned> localFields;
  std::vector<unsigned> planNodes;
  std::unordered_map<int, unsigned> values;
  std::vector<Replacement> replacements;
  std::unordered_map<const ir::Instruction *, unsigned> replacementIndices;
  std::unordered_map<unsigned, llvm::Function *> drops;

  unsigned addField(llvm::Type *type);
  unsigned addRoot(const cleanup::Plan &plan, int place, int local = -1);
  unsigned addNode(const cleanup::Plan &plan, int place, unsigned root,
                   int parent, std::vector<unsigned> path);
  unsigned placeNode(const Place &place) const;
  llvm::Value *field(unsigned index);
  llvm::Value *nodeAddress(unsigned node);
  void set(unsigned node, bool initialized);
  void updateParents(unsigned node);
  void drop(unsigned node);
  llvm::Function *dropCallback(unsigned node);
  void emitCallbacks();
  void emitReplacement(Replacement &replacement);
  void callDrop(unsigned node, llvm::Value *unwinding);
  std::vector<unsigned> cleanupOrder() const;
};
} // namespace mettle::backend
