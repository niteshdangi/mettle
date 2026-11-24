#include "backend/llvm/object.h"

#include "types/layout.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Analysis/ValueTracking.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/GlobalDCE.h"
#include "llvm/Transforms/Instrumentation/AddressSanitizer.h"
#include "llvm/Transforms/Instrumentation/ThreadSanitizer.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"

#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace mettle::backend {

namespace {
void initializeTargets() {
  static std::once_flag initialized;
  std::call_once(initialized, [] {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
    LLVMInitializeAArch64TargetInfo();
    LLVMInitializeAArch64Target();
    LLVMInitializeAArch64TargetMC();
    LLVMInitializeAArch64AsmPrinter();
    LLVMInitializeAArch64AsmParser();
    LLVMInitializeWebAssemblyTargetInfo();
    LLVMInitializeWebAssemblyTarget();
    LLVMInitializeWebAssemblyTargetMC();
    LLVMInitializeWebAssemblyAsmPrinter();
    LLVMInitializeARMTargetInfo();
    LLVMInitializeARMTarget();
    LLVMInitializeARMTargetMC();
    LLVMInitializeARMAsmPrinter();
  });
}

llvm::Expected<std::unique_ptr<llvm::TargetMachine>>
createMachine(const llvm::Triple &triple, bool optimize) {
  initializeTargets();
  std::string diagnostic;
  const auto *target = llvm::TargetRegistry::lookupTarget(triple, diagnostic);
  if (target == nullptr)
    return llvm::createStringError(llvm::inconvertibleErrorCode(), diagnostic);
  llvm::TargetOptions options;
  // Lets the linker drop unreferenced library bodies.
  options.FunctionSections = options.DataSections = true;
  std::unique_ptr<llvm::TargetMachine> machine(target->createTargetMachine(
      triple, "generic", "", options, llvm::Reloc::PIC_, std::nullopt,
      optimize ? llvm::CodeGenOptLevel::Aggressive
               : llvm::CodeGenOptLevel::None));
  if (machine == nullptr)
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "target machine creation failed");
  return machine;
}
} // namespace

std::string defaultTargetTriple() {
  llvm::Triple triple(llvm::sys::getDefaultTargetTriple());
#ifdef METTLE_DARWIN_DEPLOYMENT_TARGET
  // The host triple embeds the kernel version, which makes the linker reject
  // objects as built for a newer OS than the runtime's deployment target.
  if (triple.isOSDarwin() && triple.isAArch64())
    return "arm64-apple-macosx" METTLE_DARWIN_DEPLOYMENT_TARGET;
#endif
  return triple.str();
}

llvm::Expected<llvm::DataLayout> targetDataLayout(llvm::StringRef triple) {
  auto machine =
      createMachine(llvm::Triple(llvm::Triple::normalize(triple)), false);
  if (!machine)
    return machine.takeError();
  return (*machine)->createDataLayout();
}

llvm::Error checkTargetLayout(const TypeStore &types, llvm::StringRef triple) {
  auto layout = targetDataLayout(triple);
  if (!layout)
    return layout.takeError();
  llvm::LLVMContext context;
  struct Expected {
    Type type;
    llvm::Type *storage;
  };
  auto *pointer = llvm::PointerType::get(context, 0);
  const Expected scalars[]{
      {Type::Bool, llvm::Type::getInt8Ty(context)},
      {Type::Char, llvm::Type::getInt32Ty(context)},
      {Type::I8, llvm::Type::getInt8Ty(context)},
      {Type::U8, llvm::Type::getInt8Ty(context)},
      {Type::I16, llvm::Type::getInt16Ty(context)},
      {Type::U16, llvm::Type::getInt16Ty(context)},
      {Type::I32, llvm::Type::getInt32Ty(context)},
      {Type::U32, llvm::Type::getInt32Ty(context)},
      {Type::I64, llvm::Type::getInt64Ty(context)},
      {Type::U64, llvm::Type::getInt64Ty(context)},
      {Type::I128, llvm::Type::getIntNTy(context, 128)},
      {Type::U128, llvm::Type::getIntNTy(context, 128)},
      {Type::Isize,
       llvm::Type::getIntNTy(context, layout->getPointerSizeInBits())},
      {Type::Usize,
       llvm::Type::getIntNTy(context, layout->getPointerSizeInBits())},
      {Type::F32, llvm::Type::getFloatTy(context)},
      {Type::F64, llvm::Type::getDoubleTy(context)},
  };
  auto mismatch = [&](llvm::StringRef what, std::uint64_t size,
                      std::uint64_t alignment,
                      llvm::Type *type) -> llvm::Error {
    if (size == layout->getTypeAllocSize(type).getFixedValue() &&
        alignment == layout->getABITypeAlign(type).value())
      return llvm::Error::success();
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "compiler-owned layout of " + what.str() +
            " disagrees with the target data layout " +
            layout->getStringRepresentation());
  };
  for (const auto &scalar : scalars) {
    auto owned = objectLayout(types, scalar.type);
    if (!owned)
      return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                     "scalar layout is unavailable");
    if (auto error = mismatch(typeName(scalar.type), owned->size,
                              owned->alignment, scalar.storage))
      return error;
  }
  if (layout->getPointerSizeInBits() != 64)
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "this source compiler machine model requires a 64-bit target");
  // Thin pointers and function pointers share the compiler-owned 8-byte layout.
  return mismatch("pointer", 8, 8, pointer);
}

// Zero-sized loads and stores carry no bits. Sanitizers would check them as
// variable-sized accesses of length zero, which ASan reports and then aborts.
void dropZeroSizedAccesses(llvm::Module &module) {
  const auto &layout = module.getDataLayout();
  std::vector<llvm::Instruction *> dead;
  for (auto &function : module)
    for (auto &block : function)
      for (auto &instruction : block) {
        if (auto *load = llvm::dyn_cast<llvm::LoadInst>(&instruction);
            load && !load->isVolatile() && load->getType()->isSized() &&
            layout.getTypeStoreSize(load->getType()).isZero()) {
          load->replaceAllUsesWith(
              llvm::Constant::getNullValue(load->getType()));
          dead.push_back(load);
        } else if (auto *store = llvm::dyn_cast<llvm::StoreInst>(&instruction);
                   store && !store->isVolatile() &&
                   store->getValueOperand()->getType()->isSized() &&
                   layout.getTypeStoreSize(store->getValueOperand()->getType())
                       .isZero())
          dead.push_back(store);
      }
  for (auto *instruction : dead)
    instruction->eraseFromParent();
}

llvm::Error instrumentModule(llvm::Module &module, bool sanitizeAddress,
                             bool sanitizeThread) {
  if (!sanitizeAddress && !sanitizeThread)
    return llvm::Error::success();
  dropZeroSizedAccesses(module);
  llvm::LoopAnalysisManager loops;
  llvm::FunctionAnalysisManager functions;
  llvm::CGSCCAnalysisManager calls;
  llvm::ModuleAnalysisManager modules;
  llvm::PassBuilder builder;
  builder.registerLoopAnalyses(loops);
  builder.registerFunctionAnalyses(functions);
  builder.registerCGSCCAnalyses(calls);
  builder.registerModuleAnalyses(modules);
  builder.crossRegisterProxies(loops, functions, calls, modules);
  llvm::ModulePassManager pipeline;
  if (sanitizeAddress)
    pipeline.addPass(
        llvm::AddressSanitizerPass(llvm::AddressSanitizerOptions{}));
  if (sanitizeThread) {
    pipeline.addPass(llvm::ModuleThreadSanitizerPass());
    pipeline.addPass(
        llvm::createModuleToFunctionPassAdaptor(llvm::ThreadSanitizerPass()));
  }
  pipeline.run(module, modules);
  std::string diagnostic;
  llvm::raw_string_ostream diagnostics(diagnostic);
  if (llvm::verifyModule(module, &diagnostics))
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "invalid instrumented backend module: " +
                                       diagnostic);
  return llvm::Error::success();
}

static void foldX86InductionOffsets(llvm::Module &module) {
  for (auto &function : module) {
    if (function.hasOptNone())
      continue;
    for (auto &block : function)
      for (auto &instruction : llvm::make_early_inc_range(block)) {
        auto *offset = llvm::dyn_cast<llvm::PossiblyDisjointInst>(&instruction);
        if (!offset || !offset->isDisjoint() || !offset->hasOneUse() ||
            !offset->getType()->isIntegerTy(32))
          continue;
        auto *index = llvm::dyn_cast<llvm::PHINode>(offset->getOperand(0));
        auto *one = llvm::dyn_cast<llvm::ConstantInt>(offset->getOperand(1));
        if (!index || !one || !one->isOne() ||
            !llvm::isa<llvm::SIToFPInst, llvm::UIToFPInst>(
                *offset->user_begin()))
          continue;
        auto *sum = llvm::BinaryOperator::CreateNUWAdd(index, one, "",
                                                       offset->getIterator());
        sum->takeName(offset);
        sum->setDebugLoc(offset->getDebugLoc());
        offset->replaceAllUsesWith(sum);
        offset->eraseFromParent();
      }
  }
}

static void versionIndexedStores(llvm::Function &function) {
  const auto &layout = function.getDataLayout();
  if (function.hasOptNone() || layout.getPointerSizeInBits() != 64 ||
      layout.getIndexSizeInBits(0) != 64 || layout.isNonIntegralAddressSpace(0))
    return;
  for (auto &block : llvm::make_early_inc_range(function)) {
    auto *latch = llvm::dyn_cast<llvm::BranchInst>(block.getTerminator());
    if (!latch || !latch->isConditional() || latch->getSuccessor(0) != &block ||
        latch->getSuccessor(1) == &block)
      continue;
    if (!block.hasNPredecessors(2))
      continue;
    auto *entry = *llvm::pred_begin(&block);
    if (entry == &block)
      entry = *std::next(llvm::pred_begin(&block));
    auto *exit = latch->getSuccessor(1);
    auto *test = llvm::dyn_cast<llvm::ICmpInst>(latch->getCondition());
    if (entry == &block ||
        !llvm::isa<llvm::BranchInst>(entry->getTerminator()) || !test ||
        test->getPredicate() != llvm::ICmpInst::ICMP_ULT)
      continue;
    auto *step = llvm::dyn_cast<llvm::BinaryOperator>(test->getOperand(0));
    auto *length = llvm::dyn_cast<llvm::LoadInst>(test->getOperand(1));
    if (!step || step->getOpcode() != llvm::Instruction::Add || !length ||
        length->getParent() != &block || !length->isSimple() ||
        !step->getType()->isIntegerTy(64))
      continue;
    auto *index = llvm::dyn_cast<llvm::PHINode>(step->getOperand(0));
    auto *one = llvm::dyn_cast<llvm::ConstantInt>(step->getOperand(1));
    if (!index || index->getParent() != &block || !one || !one->isOne() ||
        index->getIncomingValueForBlock(&block) != step)
      continue;
    auto *initial = llvm::dyn_cast<llvm::ConstantInt>(
        index->getIncomingValueForBlock(entry));
    if (!initial || !initial->isZero())
      continue;
    llvm::StoreInst *store = nullptr;
    bool supported = true;
    for (auto &instruction : block) {
      if (auto *candidate = llvm::dyn_cast<llvm::StoreInst>(&instruction)) {
        supported &= !store && candidate->isSimple();
        store = candidate;
      } else if (auto *load = llvm::dyn_cast<llvm::LoadInst>(&instruction)) {
        supported &= load->isSimple();
      } else if (&instruction != latch) {
        supported &= !instruction.mayReadOrWriteMemory() &&
                     !instruction.mayHaveSideEffects() &&
                     !llvm::isa<llvm::CallBase>(instruction);
      }
      for (const auto &operand : instruction.uses()) {
        const auto *use = llvm::dyn_cast<llvm::Instruction>(operand.getUser());
        if (use && use->getParent() == &block)
          continue;
        const auto *phi = llvm::dyn_cast_or_null<llvm::PHINode>(use);
        supported &= phi && phi->getParent() == exit &&
                     phi->getIncomingBlock(operand) == &block;
      }
    }
    if (!supported || !store || !store->comesBefore(length))
      continue;
    auto *element =
        llvm::dyn_cast<llvm::GetElementPtrInst>(store->getPointerOperand());
    if (!element || !element->isInBounds() || element->getNumIndices() != 1 ||
        element->getOperand(1) != index || element->getPointerAddressSpace())
      continue;
    if (!index->hasNUses(2) || !step->hasNUses(2) || !test->hasOneUse())
      continue;
    auto *data = llvm::dyn_cast<llvm::LoadInst>(element->getPointerOperand());
    if (!data || data->getParent() != &block || !data->isSimple() ||
        data->getPointerAddressSpace() || length->getPointerAddressSpace() ||
        !data->comesBefore(store))
      continue;
    const auto stride =
        layout.getTypeAllocSize(element->getSourceElementType());
    if (stride.isScalable() || stride.getFixedValue() == 0 ||
        stride != layout.getTypeStoreSize(store->getValueOperand()->getType()))
      continue;
    llvm::DominatorTree dom(function);
    auto *insertion = entry->getTerminator();
    auto canRead = [&](llvm::LoadInst *load) {
      return llvm::isa<llvm::AllocaInst>(
                 llvm::getUnderlyingObject(load->getPointerOperand())) &&
             dom.dominates(load->getPointerOperand(), insertion) &&
             llvm::isSafeToSpeculativelyExecute(load, insertion, nullptr, &dom);
    };
    if (!canRead(data) || !canRead(length))
      continue;
    auto *guard = llvm::SplitEdge(entry, &block, &dom);
    auto *terminator = guard->getTerminator();
    llvm::IRBuilder<> builder(terminator);
    auto read = [&](llvm::LoadInst *load) {
      auto *copy = builder.CreateAlignedLoad(
          load->getType(), load->getPointerOperand(), load->getAlign());
      return builder.CreateFreeze(copy);
    };
    auto *base = read(data);
    auto *count = read(length);
    auto *start = builder.CreatePtrToInt(base, builder.getInt64Ty());
    auto *bytes =
        builder.CreateMul(count, builder.getInt64(stride.getFixedValue()));
    auto *end = builder.CreateAdd(start, bytes);
    auto *limit = builder.CreateGEP(builder.getInt8Ty(), base, bytes);
    auto disjoint = [&](llvm::LoadInst *load) {
      auto *first = builder.CreatePtrToInt(load->getPointerOperand(),
                                           builder.getInt64Ty());
      auto *last = builder.CreateAdd(
          first, builder.getInt64(
                     layout.getTypeStoreSize(load->getType()).getFixedValue()));
      return builder.CreateAnd(
          builder.CreateICmpULT(first, last),
          builder.CreateOr(builder.CreateICmpULE(end, first),
                           builder.CreateICmpULE(last, start)));
    };
    auto *fits = builder.CreateAnd(
        builder.CreateICmpULE(
            count, builder.getInt64(INT64_MAX / stride.getFixedValue())),
        builder.CreateICmpULT(start, end));
    auto *safe = builder.CreateAnd(
        fits, builder.CreateAnd(disjoint(data), disjoint(length)));

    llvm::ValueToValueMapTy values;
    auto *fast = llvm::CloneBasicBlock(&block, values, ".disjoint", &function);
    values[&block] = fast;
    llvm::Value *fastData = values.lookup(data);
    llvm::Value *fastLength = values.lookup(length);
    values[data] = base;
    values[length] = count;
    for (auto &instruction : *fast)
      llvm::RemapInstruction(&instruction, values,
                             llvm::RF_IgnoreMissingLocals);
    auto *fastLatch = llvm::cast<llvm::BranchInst>(fast->getTerminator());
    llvm::IRBuilder<> atStart(&fast->front());
    auto *cursor = atStart.CreatePHI(base->getType(), 2);
    cursor->addIncoming(base, guard);
    llvm::IRBuilder<> atEnd(fastLatch);
    auto *next = atEnd.CreateGEP(element->getSourceElementType(), cursor, one);
    cursor->addIncoming(next, fast);
    fastLatch->setCondition(atEnd.CreateICmpNE(next, limit));
    auto *fastElement = llvm::cast<llvm::Instruction>(values.lookup(element));
    fastElement->replaceAllUsesWith(cursor);
    values[element] = cursor;
    fastElement->eraseFromParent();
    llvm::cast<llvm::Instruction>(values.lookup(test))->eraseFromParent();
    auto *fastIndex = llvm::cast<llvm::Instruction>(values.lookup(index));
    fastIndex->dropAllReferences();
    llvm::cast<llvm::Instruction>(values.lookup(step))->eraseFromParent();
    fastIndex->eraseFromParent();
    for (auto &phi : exit->phis()) {
      auto *original = phi.getIncomingValueForBlock(&block);
      llvm::Value *mapped = values.lookup(original);
      phi.addIncoming(mapped ? mapped : original, fast);
    }
    builder.CreateCondBr(safe, fast, &block);
    terminator->eraseFromParent();
    llvm::cast<llvm::Instruction>(fastData)->eraseFromParent();
    llvm::cast<llvm::Instruction>(fastLength)->eraseFromParent();
  }
}

static llvm::Error prepareObject(llvm::Module &module,
                                 const llvm::Triple &targetTriple,
                                 llvm::TargetMachine &machine, bool optimize,
                                 bool sanitizeAddress, bool sanitizeThread) {
  std::string diagnostic;
  if (auto *identity = llvm::dyn_cast_or_null<llvm::MDString>(
          module.getModuleFlag("mettle.target.triple"));
      identity &&
      llvm::Triple::normalize(identity->getString()) != targetTriple.str())
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "checked target facts disagree with the object target");
  module.setTargetTriple(targetTriple);
  const auto machineLayout = machine.createDataLayout();
  if (!module.getDataLayoutStr().empty() &&
      module.getDataLayout() != machineLayout)
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "module data layout disagrees with the target machine");
  module.setDataLayout(machineLayout);
  if (module.getModuleFlag("mettle.pointer.width") &&
      module.getDataLayout().getPointerSizeInBits() != 64)
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "this source compiler machine model requires a 64-bit target");

  llvm::raw_string_ostream diagnostics(diagnostic);
  if (llvm::verifyModule(module, &diagnostics)) {
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "invalid backend module: " + diagnostic);
  }
  if (sanitizeAddress || sanitizeThread)
    dropZeroSizedAccesses(module);
  {
    llvm::LoopAnalysisManager loops;
    llvm::FunctionAnalysisManager functions;
    llvm::CGSCCAnalysisManager calls;
    llvm::ModuleAnalysisManager modules;
    llvm::PipelineTuningOptions tuning;
    tuning.SLPVectorization = true;
    llvm::PassBuilder builder(&machine, tuning);
    builder.registerLoopAnalyses(loops);
    builder.registerFunctionAnalyses(functions);
    builder.registerCGSCCAnalyses(calls);
    builder.registerModuleAnalyses(modules);
    builder.crossRegisterProxies(loops, functions, calls, modules);
    auto addSanitizers = [=](llvm::ModulePassManager &pipeline) {
      if (sanitizeAddress)
        pipeline.addPass(
            llvm::AddressSanitizerPass(llvm::AddressSanitizerOptions{}));
      if (sanitizeThread) {
        pipeline.addPass(llvm::ModuleThreadSanitizerPass());
        pipeline.addPass(llvm::createModuleToFunctionPassAdaptor(
            llvm::ThreadSanitizerPass()));
      }
    };
    llvm::ModulePassManager pipeline;
    if (optimize) {
      builder.registerOptimizerLastEPCallback(
          [addSanitizers](llvm::ModulePassManager &passes,
                          llvm::OptimizationLevel,
                          llvm::ThinOrFullLTOPhase) { addSanitizers(passes); });
      pipeline =
          builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2);
      pipeline.run(module, modules);
      if (targetTriple.getArch() == llvm::Triple::x86_64 && !sanitizeAddress &&
          !sanitizeThread)
        for (auto &function : module)
          if (!function.isDeclaration())
            versionIndexedStores(function);
      if (targetTriple.getArch() == llvm::Triple::x86_64)
        foldX86InductionOffsets(module);
    } else {
      pipeline.addPass(llvm::GlobalDCEPass());
      pipeline.run(module, modules);
      if (auto error =
              instrumentModule(module, sanitizeAddress, sanitizeThread))
        return error;
    }
    if (llvm::verifyModule(module, &diagnostics))
      return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                     "invalid optimized backend module: " +
                                         diagnostic);
  }
  return llvm::Error::success();
}

static llvm::Error writeObject(llvm::Module &module,
                               llvm::TargetMachine &machine,
                               llvm::StringRef output) {
  std::error_code error;
  llvm::raw_fd_ostream stream(output, error, llvm::sys::fs::OF_None);
  if (error) {
    return llvm::createStringError(error, "cannot create object file");
  }
  llvm::legacy::PassManager passes;
  if (machine.addPassesToEmitFile(passes, stream, nullptr,
                                  llvm::CodeGenFileType::ObjectFile)) {
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "object emission is unavailable for target");
  }
  passes.run(module);
  stream.flush();
  if (stream.has_error()) {
    error = stream.error();
    stream.clear_error();
    return llvm::createStringError(error, "cannot write object file");
  }
  return llvm::Error::success();
}

llvm::Error emitObject(llvm::Module &module, llvm::StringRef triple,
                       llvm::StringRef output, bool optimize,
                       bool sanitizeAddress, bool sanitizeThread) {
  const llvm::Triple targetTriple(llvm::Triple::normalize(triple));
  auto machine = createMachine(targetTriple, optimize);
  if (!machine)
    return machine.takeError();
  if (auto error = prepareObject(module, targetTriple, **machine, optimize,
                                 sanitizeAddress, sanitizeThread))
    return error;
  return writeObject(module, **machine, output);
}

llvm::Error emitObjectUnits(llvm::Module &module, llvm::StringRef triple,
                            llvm::StringRef symbolNamespace, bool optimize,
                            ObjectUnitConsumer consume) {
  const llvm::Triple targetTriple(llvm::Triple::normalize(triple));
  auto machine = createMachine(targetTriple, optimize);
  if (!machine)
    return machine.takeError();
  if (auto error = prepareObject(module, targetTriple, **machine, optimize,
                                 false, false))
    return error;
  return partitionObjectModule(
      module, symbolNamespace, [&](llvm::Module &unit) {
        return consume(unit, [&](llvm::StringRef output) {
          return writeObject(unit, **machine, output);
        });
      });
}

} // namespace mettle::backend
