#include "backend/llvm/cleanup.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/raw_ostream.h"
#include <functional>

namespace {
using namespace mettle;
using namespace mettle::backend;

ir::Instruction value(int id, Type type) {
  ir::Instruction instruction{};
  instruction.op = ir::Op::Construct;
  instruction.result = {id, type};
  return instruction;
}

ir::Instruction store(int id, Type type, Place place) {
  ir::Instruction instruction{};
  instruction.op = ir::Op::Store;
  instruction.result = {id + 100, Type::Unit};
  instruction.operands = {{id, type}};
  instruction.place = std::move(place);
  return instruction;
}

llvm::Constant *leaf(LoweringContext &lowering, Type type, int tag) {
  return llvm::ConstantStruct::get(
      llvm::cast<llvm::StructType>(lowering.type(type)),
      {lowering.builder.getInt32(tag)});
}

llvm::Constant *parent(LoweringContext &lowering, Type type, Type leafType,
                       int first, int second) {
  return llvm::ConstantStruct::get(
      llvm::cast<llvm::StructType>(lowering.type(type)),
      {leaf(lowering, leafType, first), leaf(lowering, leafType, second)});
}

llvm::Function *
build(LoweringContext &lowering, ir::Function source,
      const std::function<void(CleanupFrame &, const ir::Function &)> &emit) {
  auto saved = lowering.builder.saveIP();
  std::vector<llvm::Type *> parameters;
  if (source.parameters)
    parameters.push_back(lowering.builder.getPtrTy());
  auto *wrapper = llvm::Function::Create(
      llvm::FunctionType::get(lowering.builder.getVoidTy(), parameters, false),
      llvm::GlobalValue::InternalLinkage, source.name, lowering.module);
  wrapper->setUWTableKind(llvm::UWTableKind::Default);
  CleanupFrame frame(lowering, source, wrapper);
  frame.createWrapper();
  lowering.builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", frame.body()));
  emit(frame, source);
  if (!lowering.builder.GetInsertBlock()->getTerminator())
    frame.returnValue({}, nullptr);
  llvm::Function *action = wrapper;
  if (!source.parameters) {
    action = lowering.callback(source.name + ".action");
    lowering.builder.SetInsertPoint(
        llvm::BasicBlock::Create(lowering.context, "entry", action));
    lowering.builder.CreateCall(wrapper);
    lowering.builder.CreateRetVoid();
  }
  lowering.builder.restoreIP(saved);
  return action;
}
} // namespace

int main(int argc, char **) {
  using namespace mettle;
  using namespace mettle::backend;
  auto types = std::make_shared<TypeStore>();
  auto leafType = types->declareProduct("Leaf", false);
  auto parentType = types->declareProduct("Parent", false);
  types->defineProduct(leafType, {{"tag", Type::I32}});
  types->defineProduct(parentType, {{"first", leafType}, {"second", leafType}});
  types->setDestructor(leafType, 0);
  types->setDestructor(parentType, 1);
  auto view = types->viewType(parentType, ParameterMode::Mut);
  ir::Program program;
  program.types = types;
  llvm::LLVMContext context;
  llvm::Module module("cleanup-frame-native", context);
  llvm::IRBuilder<> builder(context);
  std::vector<llvm::Function *> functions;
  LoweringContext lowering{program, context, module, builder, functions, {}};
  for (auto name : {"mettle_test_leaf_drop", "mettle_test_parent_drop"})
    functions.push_back(llvm::cast<llvm::Function>(
        lowering.runtime(name, builder.getVoidTy(), {builder.getPtrTy()})
            .getCallee()));
  auto *main = llvm::Function::Create(
      llvm::FunctionType::get(builder.getInt32Ty(), false),
      llvm::GlobalValue::ExternalLinkage, "main", module);
  main->setUWTableKind(llvm::UWTableKind::Default);
  builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", main));
  llvm::Value *failed = builder.getFalse();
  auto run = [&](llvm::Function *action, int expected,
                 llvm::Value *argument = nullptr) {
    auto *code = builder.CreateCall(
        lowering.runtime("mettle_rt_catch", builder.getInt32Ty(),
                         {builder.getPtrTy(), builder.getPtrTy()}),
        {argument ? argument
                  : llvm::ConstantPointerNull::get(builder.getPtrTy()),
         action});
    failed = builder.CreateOr(
        failed, builder.CreateICmpNE(code, builder.getInt32(expected)));
  };
  auto source = [&](std::string name) {
    ir::Function result{};
    result.name = std::move(name);
    result.result = Type::Unit;
    result.locals = {
        {"owner", parentType, true, {}, ParameterMode::Value, 0, 0}};
    result.blocks.resize(1);
    result.blocks[0].instructions = {value(0, parentType),
                                     store(0, parentType, {0, {}})};
    return result;
  };
  auto initialize = [&](CleanupFrame &frame, const ir::Function &source,
                        int first, int second) {
    auto *constant = parent(lowering, parentType, leafType, first, second);
    frame.remember({0, parentType}, constant);
    frame.store(source.blocks[0].instructions[1], constant);
  };
  auto panic = [&] {
    builder.CreateCall(lowering.runtime("mettle_rt_panic", builder.getVoidTy(),
                                        {builder.getInt32Ty()}),
                       {builder.getInt32(7)});
    builder.CreateUnreachable();
  };
  if (argc > 1) {
    auto doublePanic =
        build(lowering, source("double_panic"),
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 20, 99);
                frame.scopeExit(0);
              });
    run(doublePanic, 9);
  } else {
    auto normal = source("normal");
    normal.locals.push_back(
        {"last", leafType, false, {}, ParameterMode::Value, 0, 1});
    normal.blocks[0].instructions.push_back(value(1, leafType));
    normal.blocks[0].instructions.push_back(store(1, leafType, {1, {}}));
    run(build(lowering, normal,
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 10, 11);
                auto *last = leaf(lowering, leafType, 7);
                frame.remember({1, leafType}, last);
                frame.store(source.blocks[0].instructions[3], last);
                frame.scopeExit(0);
              }),
        0);
    auto partial = source("partial");
    partial.blocks[0].instructions = {
        value(0, leafType), store(0, leafType, {0, {Projection::field(0)}})};
    run(build(lowering, partial,
              [&](CleanupFrame &frame, const ir::Function &source) {
                auto *first = leaf(lowering, leafType, 12);
                frame.remember({0, leafType}, first);
                frame.store(source.blocks[0].instructions[1], first);
                frame.scopeExit(0);
              }),
        0);
    auto moved = source("moved");
    moved.locals.push_back(
        {"destination", parentType, false, {}, ParameterMode::Value, 0, 1});
    moved.blocks[0].instructions.push_back(value(1, parentType));
    moved.blocks[0].instructions.push_back(store(1, parentType, {1, {}}));
    run(build(lowering, moved,
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 13, 14);
                auto *owner = builder.CreateLoad(lowering.type(parentType),
                                                 frame.address({0, {}}));
                frame.move({0, {}});
                frame.remember({1, parentType}, owner);
                frame.store(source.blocks[0].instructions[3], owner);
                frame.scopeExit(0);
              }),
        0);
    run(build(lowering, source("unwind"),
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 15, 16);
                panic();
              }),
        7);
    run(build(lowering, source("destructor_panic"),
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 20, 21);
                frame.scopeExit(0);
              }),
        9);
    auto replacement = source("replacement");
    replacement.blocks[0].instructions.push_back(value(1, parentType));
    replacement.blocks[0].instructions.push_back(store(1, parentType, {0, {}}));
    run(build(lowering, replacement,
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 20, 21);
                auto *pending = parent(lowering, parentType, leafType, 30, 31);
                frame.remember({1, parentType}, pending);
                frame.store(source.blocks[0].instructions[3], pending);
                frame.scopeExit(0);
              }),
        9);
    auto pending = replacement;
    pending.name = "pending_failure";
    run(build(lowering, pending,
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 17, 18);
                frame.remember({1, parentType},
                               parent(lowering, parentType, leafType, 40, 41));
                panic();
              }),
        7);
    auto protectedReturn = source("protected_return");
    protectedReturn.locals[0].scope = -2;
    run(build(lowering, protectedReturn,
              [&](CleanupFrame &frame, const ir::Function &source) {
                initialize(frame, source, 19, 22);
                frame.scopeExit(0);
                panic();
              }),
        7);
    for (bool storedView : {false, true}) {
      auto borrowed = source(storedView ? "view" : "borrowed");
      borrowed.parameters = 1;
      borrowed.locals[0].type = storedView ? view : parentType;
      borrowed.locals[0].mode =
          storedView ? ParameterMode::Value : ParameterMode::Mut;
      Place destination{0, {}};
      if (storedView)
        destination.fields.push_back(Projection::dereference());
      borrowed.blocks[0].instructions[1] = store(0, parentType, destination);
      auto *referent = builder.CreateAlloca(lowering.type(parentType));
      builder.CreateStore(parent(lowering, parentType, leafType, 20, 21),
                          referent);
      auto *action =
          build(lowering, borrowed,
                [&](CleanupFrame &frame, const ir::Function &source) {
                  initialize(frame, source, 30, 31);
                  frame.scopeExit(0);
                });
      run(action, 9, referent);
      auto *installed = builder.CreateLoad(lowering.type(parentType), referent);
      auto *first = builder.CreateExtractValue(installed, {0, 0});
      auto *second = builder.CreateExtractValue(installed, {1, 0});
      failed = builder.CreateOr(
          failed,
          builder.CreateOr(builder.CreateICmpNE(first, builder.getInt32(30)),
                           builder.CreateICmpNE(second, builder.getInt32(31))));
    }
  }
  auto *trace = builder.CreateCall(
      lowering.runtime("mettle_test_cleanup_result", builder.getInt32Ty(), {}));
  builder.CreateRet(builder.CreateSelect(failed, builder.getInt32(41), trace));
  if (llvm::verifyModule(module, &llvm::errs()))
    return 1;
  module.print(llvm::outs(), nullptr);
}
