#include "backend/llvm/lower.h"
#include "backend/llvm/cleanup.h"

#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include <map>

namespace mettle::backend {
namespace {
class Lowerer {
public:
  Lowerer(const ir::Program &program, llvm::LLVMContext &context)
      : program(program), context(context),
        module(std::make_unique<llvm::Module>("mettle", context)),
        builder(context),
        lowering{program, context, *module, builder, functions, {}} {}
  std::unique_ptr<llvm::Module> run() {
    for (const auto &f : program.functions) {
      std::vector<llvm::Type *> parameters;
      for (std::size_t i = 0; i < f.parameters; ++i)
        parameters.push_back(f.locals[i].mode == ParameterMode::Read ||
                                     f.locals[i].mode == ParameterMode::Mut
                                 ? builder.getPtrTy()
                                 : type(f.locals[i].type));
      auto *signature =
          llvm::FunctionType::get(resultType(f.result), parameters, false);
      auto *function =
          f.externalName.empty()
              ? llvm::Function::Create(signature,
                                       llvm::GlobalValue::InternalLinkage,
                                       "mettle." + f.name, *module)
              : llvm::cast<llvm::Function>(
                    module->getOrInsertFunction(f.externalName, signature)
                        .getCallee());
      function->setUWTableKind(llvm::UWTableKind::Default);
      if (f.result == Type::Never)
        function->addFnAttr(llvm::Attribute::NoReturn);
      functions.push_back(function);
    }
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (program.functions[i].externalName.empty())
        function(program.functions[i], functions[i]);
    auto *entry = llvm::Function::Create(
        llvm::FunctionType::get(builder.getInt32Ty(), false),
        llvm::GlobalValue::ExternalLinkage, "main", *module);
    entry->setUWTableKind(llvm::UWTableKind::Default);
    builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", entry));
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (program.functions[i].name == "main") {
        auto *callback = lowering.callback("mettle.main");
        auto saved = builder.saveIP();
        builder.SetInsertPoint(
            llvm::BasicBlock::Create(context, "entry", callback));
        auto *result = builder.CreateCall(functions[i]);
        builder.CreateStore(result, callback->getArg(0));
        builder.CreateRetVoid();
        builder.restoreIP(saved);
        auto *resultSlot = builder.CreateAlloca(builder.getInt32Ty());
        builder.CreateStore(builder.getInt32(0), resultSlot);
        builder.CreateCall(
            lowering.runtime("mettle_rt_main", builder.getInt32Ty(),
                             {builder.getPtrTy(), builder.getPtrTy()}),
            {resultSlot, callback});
        builder.CreateRet(builder.CreateLoad(builder.getInt32Ty(), resultSlot));
        break;
      }
    return std::move(module);
  }
  bool checked = true;

private:
  const ir::Program &program;
  llvm::LLVMContext &context;
  std::unique_ptr<llvm::Module> module;
  llvm::IRBuilder<> builder;
  std::vector<llvm::Function *> functions;
  LoweringContext lowering;

  llvm::Type *type(Type t) { return lowering.type(t); }
  llvm::Type *resultType(Type t) { return lowering.resultType(t); }
  llvm::Value *unit() { return llvm::Constant::getNullValue(type(Type::Unit)); }
  void panicIf(llvm::Value *condition) {
    auto *function = builder.GetInsertBlock()->getParent();
    auto *panic = llvm::BasicBlock::Create(context, "panic", function);
    auto *next = llvm::BasicBlock::Create(context, "checked", function);
    builder.CreateCondBr(condition, panic, next);
    builder.SetInsertPoint(panic);
    auto panicFunction = lowering.runtime(
        "mettle_rt_panic", builder.getVoidTy(), {builder.getInt32Ty()});
    llvm::cast<llvm::Function>(panicFunction.getCallee())
        ->addFnAttr(llvm::Attribute::NoReturn);
    builder.CreateCall(panicFunction, {builder.getInt32(1)});
    builder.CreateUnreachable();
    builder.SetInsertPoint(next);
  }
  llvm::Value *binary(const std::string &op, llvm::Value *a, llvm::Value *b,
                      Type operand) {
    if (op == "+" || op == "-" || op == "*") {
      if (checked) {
        auto intrinsic = op == "+"   ? llvm::Intrinsic::sadd_with_overflow
                         : op == "-" ? llvm::Intrinsic::ssub_with_overflow
                                     : llvm::Intrinsic::smul_with_overflow;
        auto *fn = llvm::Intrinsic::getOrInsertDeclaration(
            module.get(), intrinsic, {a->getType()});
        auto *result = builder.CreateCall(fn, {a, b});
        auto *value = builder.CreateExtractValue(result, 0);
        panicIf(builder.CreateExtractValue(result, 1));
        return value;
      }
      if (op == "+")
        return builder.CreateAdd(a, b);
      if (op == "-")
        return builder.CreateSub(a, b);
      return builder.CreateMul(a, b);
    }
    if (op == "/" || op == "%") {
      auto *zero = builder.CreateICmpEQ(b, builder.getInt32(0));
      auto *overflow = builder.CreateAnd(
          builder.CreateICmpEQ(a, builder.getInt32(0x80000000)),
          builder.CreateICmpEQ(b, builder.getInt32(-1)));
      panicIf(builder.CreateOr(zero, overflow));
      return op == "/" ? builder.CreateSDiv(a, b) : builder.CreateSRem(a, b);
    }
    if (op == "<<" || op == ">>") {
      if (checked)
        panicIf(builder.CreateICmpUGE(b, builder.getInt32(32)));
      b = builder.CreateAnd(b, builder.getInt32(31));
      return op == "<<" ? builder.CreateShl(a, b) : builder.CreateAShr(a, b);
    }
    if (op == "&")
      return builder.CreateAnd(a, b);
    if (op == "|")
      return builder.CreateOr(a, b);
    if (op == "^")
      return builder.CreateXor(a, b);
    if (operand == Type::Unit)
      return builder.getInt1(op == "==" || op == "<=" || op == ">=");
    if (op == "==")
      return builder.CreateICmpEQ(a, b);
    if (op == "!=")
      return builder.CreateICmpNE(a, b);
    bool sign = operand == Type::I32;
    if (op == "<")
      return sign ? builder.CreateICmpSLT(a, b) : builder.CreateICmpULT(a, b);
    if (op == "<=")
      return sign ? builder.CreateICmpSLE(a, b) : builder.CreateICmpULE(a, b);
    if (op == ">")
      return sign ? builder.CreateICmpSGT(a, b) : builder.CreateICmpUGT(a, b);
    if (op == ">=")
      return sign ? builder.CreateICmpSGE(a, b) : builder.CreateICmpUGE(a, b);
    llvm_unreachable("unknown checked binary operation");
  }
  void function(const ir::Function &source, llvm::Function *target) {
    CleanupFrame frame(lowering, source, target);
    frame.createWrapper();
    target = frame.body();
    std::vector<llvm::BasicBlock *> blocks, ends;
    for (std::size_t i = 0; i < source.blocks.size(); ++i)
      blocks.push_back(
          llvm::BasicBlock::Create(context, "b" + std::to_string(i), target));
    ends.resize(blocks.size());
    builder.SetInsertPoint(blocks[0]);
    auto address = [&](const Place &place) -> llvm::Value * {
      return frame.address(place);
    };
    std::vector<llvm::Value *> values(source.values, nullptr);
    struct Pending {
      llvm::PHINode *phi;
      const ir::Instruction *instruction;
      int block;
    };
    std::vector<Pending> pending;
    for (std::size_t b = 0; b < blocks.size(); ++b) {
      builder.SetInsertPoint(blocks[b]);
      for (const auto &n : source.blocks[b].instructions)
        if (n.op == ir::Op::Phi) {
          auto *phi = builder.CreatePHI(type(n.result.type), n.operands.size());
          pending.push_back({phi, &n, static_cast<int>(b)});
          values[n.result.id] = phi;
        }
      for (const auto &n : source.blocks[b].instructions) {
        llvm::Value *result = unit();
        auto get = [&](std::size_t i) { return values[n.operands[i].id]; };
        switch (n.op) {
        case ir::Op::Constant:
          if (n.result.type == Type::I32)
            result = builder.getInt32(n.number);
          if (n.result.type == Type::Bool)
            result = builder.getInt1(n.number != 0);
          break;
        case ir::Op::Declare:
          frame.declare(n.place);
          break;
        case ir::Op::Load:
          result = builder.CreateLoad(type(n.result.type), address(n.place));
          break;
        case ir::Op::Move:
          result = builder.CreateLoad(type(n.result.type), address(n.place));
          frame.move(n.place);
          break;
        case ir::Op::BorrowRead:
        case ir::Op::BorrowMut:
        case ir::Op::ReserveMut:
        case ir::Op::ViewRead:
        case ir::Op::ViewMut:
          result = address(n.place);
          break;
        case ir::Op::Activate:
          break;
        case ir::Op::Store:
          frame.store(n, get(0));
          break;
        case ir::Op::ScopeExit:
          frame.scopeExit(n.number);
          break;
        case ir::Op::Unary:
          result = n.text == "!"
                       ? builder.CreateNot(get(0))
                       : binary("-", builder.getInt32(0), get(0), Type::I32);
          break;
        case ir::Op::Binary:
          result = binary(n.text, get(0), get(1), n.operands[0].type);
          break;
        case ir::Op::Call:
        case ir::Op::CatchCall: {
          std::vector<llvm::Value *> arguments;
          for (auto value : n.operands) {
            arguments.push_back(values[value.id]);
            frame.consume(value);
          }
          if (n.op == ir::Op::CatchCall) {
            std::vector<llvm::Type *> members;
            for (auto *argument : arguments)
              members.push_back(argument->getType());
            auto *contextType = llvm::StructType::get(context, members);
            auto *callback = lowering.callback("mettle.catch");
            auto saved = builder.saveIP();
            builder.SetInsertPoint(
                llvm::BasicBlock::Create(context, "entry", callback));
            std::vector<llvm::Value *> loaded;
            for (unsigned i = 0; i < members.size(); ++i)
              loaded.push_back(builder.CreateLoad(
                  members[i], builder.CreateStructGEP(contextType,
                                                      callback->getArg(0), i)));
            builder.CreateCall(functions[n.callee], loaded);
            builder.CreateRetVoid();
            builder.restoreIP(saved);
            // Catch returns before this callback stack is unwound, so this
            // context need not escape into the function's outer cleanup frame.
            llvm::IRBuilder<> entryBuilder(&target->getEntryBlock(),
                                           target->getEntryBlock().begin());
            auto *callContext = entryBuilder.CreateAlloca(contextType);
            for (unsigned i = 0; i < arguments.size(); ++i)
              builder.CreateStore(
                  arguments[i],
                  builder.CreateStructGEP(contextType, callContext, i));
            result = builder.CreateCall(
                lowering.runtime("mettle_rt_catch", builder.getInt32Ty(),
                                 {builder.getPtrTy(), builder.getPtrTy()}),
                {callContext, callback});
          } else {
            auto *call = builder.CreateCall(functions[n.callee], arguments);
            if (n.result.type != Type::Unit && n.result.type != Type::Never)
              result = call;
          }
          break;
        }
        case ir::Op::Phi: {
          result = values[n.result.id];
          break;
        }
        case ir::Op::Construct:
          result = llvm::Constant::getNullValue(type(n.result.type));
          for (std::size_t i = 0; i < n.operands.size(); ++i) {
            result = builder.CreateInsertValue(result, get(i),
                                               static_cast<unsigned>(i));
            frame.consume(n.operands[i]);
          }
          break;
        case ir::Op::Project:
          result = builder.CreateExtractValue(get(0),
                                              static_cast<unsigned>(n.number));
          break;
        }
        frame.remember(n.result, result);
        values[n.result.id] = result;
      }
      const auto &exit = source.blocks[b].exit;
      switch (exit.kind) {
      case ir::Exit::Jump:
        builder.CreateBr(blocks[exit.first]);
        break;
      case ir::Exit::Branch:
        builder.CreateCondBr(values[exit.value.id], blocks[exit.first],
                             blocks[exit.second]);
        break;
      case ir::Exit::Return:
        frame.returnValue(exit.value, source.result == Type::Unit ||
                                              source.result == Type::Never
                                          ? nullptr
                                          : values[exit.value.id]);
        break;
      case ir::Exit::Unreachable:
        builder.CreateUnreachable();
        break;
      case ir::Exit::None:
        llvm_unreachable("unterminated compiler CFG");
      }
      ends[b] = builder.GetInsertBlock();
    }
    std::map<std::pair<int, int>, llvm::BasicBlock *> transfers;
    for (std::size_t b = 0; b < source.blocks.size(); ++b)
      for (const auto &n : source.blocks[b].instructions)
        if (n.op == ir::Op::Phi && program.types->needsDrop(n.result.type))
          for (std::size_t i = 0; i < n.predecessors.size(); ++i) {
            int predecessor = n.predecessors[i];
            auto key = std::pair(predecessor, static_cast<int>(b));
            auto [entry, inserted] = transfers.try_emplace(key, nullptr);
            if (inserted) {
              auto *edge =
                  llvm::BasicBlock::Create(context, "transfer", target);
              entry->second = edge;
              auto *terminator = ends[predecessor]->getTerminator();
              for (unsigned s = 0; s < terminator->getNumSuccessors(); ++s)
                if (terminator->getSuccessor(s) == blocks[b])
                  terminator->setSuccessor(s, edge);
              builder.SetInsertPoint(edge);
              builder.CreateBr(blocks[b]);
            }
            builder.SetInsertPoint(entry->second->getTerminator());
            frame.consume(n.operands[i]);
          }
    for (auto &p : pending)
      for (std::size_t i = 0; i < p.instruction->operands.size(); ++i) {
        int predecessor = p.instruction->predecessors[i];
        auto transfer = transfers.find({predecessor, p.block});
        p.phi->addIncoming(values[p.instruction->operands[i].id],
                           transfer == transfers.end() ? ends[predecessor]
                                                       : transfer->second);
      }
  }
};
} // namespace

std::unique_ptr<llvm::Module> lower(const ir::VerifiedProgram &program,
                                    llvm::LLVMContext &context, bool checked) {
  Lowerer lowerer(program.program(), context);
  lowerer.checked = checked;
  return lowerer.run();
}
} // namespace mettle::backend
