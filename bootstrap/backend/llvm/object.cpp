#include "backend/llvm/object.h"

#include "types/layout.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ValueTracking.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InlineAsm.h"
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
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/GlobalDCE.h"
#include "llvm/Transforms/IPO/StripDeadPrototypes.h"
#include "llvm/Transforms/Instrumentation/AddressSanitizer.h"
#include "llvm/Transforms/Instrumentation/ThreadSanitizer.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"

#include <future>
#include <memory>
#include <mutex>
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

static llvm::Error verifyObject(llvm::Module &module,
                                const llvm::Triple &targetTriple,
                                llvm::TargetMachine &machine) {
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
  return llvm::Error::success();
}

static llvm::Error optimizeObject(llvm::Module &module,
                                  const llvm::Triple &targetTriple,
                                  llvm::TargetMachine &machine, bool optimize,
                                  bool sanitizeAddress, bool sanitizeThread) {
  std::string diagnostic;
  llvm::raw_string_ostream diagnostics(diagnostic);
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

static std::unique_ptr<llvm::Module>
splitEntryOptimization(llvm::Module &module, llvm::StringRef symbolNamespace,
                       bool primary) {
  if ((primary && !module.getFunction("main")) ||
      !module.getModuleInlineAsm().empty() || !module.alias_empty() ||
      !module.ifunc_empty() || module.getNamedMetadata("llvm.dbg.cu") ||
      llvm::any_of(module.globals(), [](const llvm::GlobalVariable &value) {
        return !value.isDeclaration() || value.hasExternalWeakLinkage() ||
               value.getName().starts_with("llvm.");
      }))
    return nullptr;
  using Functions = llvm::SmallPtrSet<llvm::Function *, 32>;
  llvm::DenseMap<llvm::Function *, llvm::SmallVector<llvm::Function *, 8>>
      edges;
  llvm::SmallVector<llvm::Function *, 8> entries;
  Functions barriers;
  llvm::SmallPtrSet<llvm::MDNode *, 8> entryFamilies;
  if (!primary)
    for (auto &function : module)
      if (!function.isDeclaration() && !function.hasLocalLinkage() &&
          !function.hasAvailableExternallyLinkage())
        if (auto *family = function.getMetadata("mettle.codegen.family"))
          entryFamilies.insert(family);
  for (auto &function : module) {
    if (function.hasExternalWeakLinkage() || function.hasPrefixData() ||
        function.hasPrologueData() ||
        function.getMetadata(llvm::LLVMContext::MD_associated))
      return nullptr;
    if (function.isDeclaration())
      continue;
    auto *family = function.getMetadata("mettle.codegen.family");
    auto *familyName =
        family && family->getNumOperands() == 1
            ? llvm::dyn_cast<llvm::MDString>(family->getOperand(0))
            : nullptr;
    if (familyName && (primary ? familyName->getString() == "main"
                               : entryFamilies.contains(family)))
      entries.push_back(&function);
    else if (function.hasLocalLinkage() &&
             function.hasFnAttribute(llvm::Attribute::NoInline))
      barriers.insert(&function);
    auto &references = edges[&function];
    llvm::SmallPtrSet<llvm::Value *, 32> seen;
    llvm::SmallVector<llvm::Value *, 16> pending;
    for (auto &block : function) {
      if (block.hasAddressTaken())
        return nullptr;
      for (auto &instruction : block)
        for (auto &use : instruction.operands())
          pending.push_back(use.get());
    }
    while (!pending.empty()) {
      auto *value = pending.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      if (auto *callee = llvm::dyn_cast<llvm::Function>(value)) {
        if (!callee->isDeclaration())
          references.push_back(callee);
      } else if (auto *assembly = llvm::dyn_cast<llvm::InlineAsm>(value)) {
        auto text = llvm::StringRef(assembly->getAsmString());
        if (assembly->hasSideEffects() || text.contains('.') ||
            llvm::any_of(module, [&](const llvm::Function &candidate) {
              return candidate.hasName() && text.contains(candidate.getName());
            }))
          return nullptr;
      } else if (auto *constant = llvm::dyn_cast<llvm::Constant>(value)) {
        for (auto &use : constant->operands())
          pending.push_back(use.get());
      }
    }
  }
  if (entries.empty())
    return nullptr;
  bool hasLoop = false;
  for (auto *entry : entries) {
    llvm::DominatorTree dominance(*entry);
    llvm::LoopInfo loops(dominance);
    hasLoop |= !loops.empty();
    for (auto &block : *entry)
      if (!loops.getLoopFor(&block))
        for (auto &instruction : block)
          if (auto *call = llvm::dyn_cast<llvm::CallBase>(&instruction))
            if (auto *callee = call->getCalledFunction();
                callee && callee->hasLocalLinkage() && callee->size() > 1 &&
                !llvm::is_contained(entries, callee) &&
                !callee->hasFnAttribute(llvm::Attribute::AlwaysInline))
              barriers.insert(callee);
  }
  if ((primary && !hasLoop) || barriers.empty())
    return nullptr;
  llvm::SmallVector<llvm::Function *, 32> pending;
  for (auto &[function, references] : edges)
    if (!function->hasLocalLinkage() &&
        !function->hasAvailableExternallyLinkage() &&
        !(function->hasLinkOnceODRLinkage() && function->hasHiddenVisibility()))
      pending.push_back(function);
  Functions hot;
  while (!pending.empty()) {
    auto *function = pending.pop_back_val();
    if (!barriers.contains(function) && hot.insert(function).second)
      pending.append(edges[function].begin(), edges[function].end());
  }
  pending.append(barriers.begin(), barriers.end());
  Functions cold;
  while (!pending.empty()) {
    auto *function = pending.pop_back_val();
    if (!hot.contains(function) && cold.insert(function).second)
      pending.append(edges[function].begin(), edges[function].end());
  }
  if (cold.empty() || hot.empty())
    return nullptr;
  llvm::DenseMap<const llvm::Comdat *, bool> comdats;
  Functions exports;
  for (auto &[function, references] : edges)
    if (auto *comdat = function->getComdat()) {
      bool isolated = cold.contains(function);
      auto [found, inserted] = comdats.try_emplace(comdat, isolated);
      if ((!inserted && found->second != isolated) ||
          comdat->getSelectionKind() != llvm::Comdat::Any)
        return nullptr;
    }
  for (auto &[function, references] : edges)
    for (auto *reference : references)
      if (cold.contains(function) != cold.contains(reference)) {
        if ((reference->hasLinkOnceLinkage() &&
             !reference->hasLinkOnceODRLinkage()) ||
            (!cold.contains(function) &&
             reference->hasFnAttribute(llvm::Attribute::AlwaysInline)))
          return nullptr;
        exports.insert(reference);
      }
  for (auto &reference : module)
    if (exports.contains(&reference)) {
      if (reference.hasLocalLinkage()) {
        reference.setName("mettle.split." + symbolNamespace + "." +
                          reference.getName());
        reference.setLinkage(llvm::GlobalValue::ExternalLinkage);
        reference.setVisibility(llvm::GlobalValue::HiddenVisibility);
        reference.setDSOLocal(true);
      } else if (reference.hasLinkOnceODRLinkage()) {
        reference.setLinkage(llvm::GlobalValue::WeakODRLinkage);
      }
    }
  llvm::ValueToValueMapTy mapping;
  auto isolated =
      llvm::CloneModule(module, mapping, [&](const llvm::GlobalValue *value) {
        auto *function = llvm::dyn_cast<llvm::Function>(value);
        return function &&
               cold.contains(const_cast<llvm::Function *>(function));
      });
  for (auto *function : cold) {
    function->deleteBody();
    function->setComdat(nullptr);
  }
  return isolated;
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
  if (auto error = verifyObject(module, targetTriple, **machine))
    return error;
  if (auto error = optimizeObject(module, targetTriple, **machine, optimize,
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
  if (auto error = verifyObject(module, targetTriple, **machine))
    return error;
  std::vector<std::unique_ptr<llvm::Module>> isolated;
  const auto threads = llvm::hardware_concurrency().compute_thread_count();
  bool unoptimized = false;
  struct Job {
    llvm::SmallVector<char, 0> bitcode;
    std::string output;
    bool optimize = false;
  };
  auto run = [&](const Job &job,
                 std::unique_ptr<llvm::TargetMachine> &worker) -> std::string {
    llvm::LLVMContext context;
    auto unit = llvm::parseBitcodeFile(
        llvm::MemoryBufferRef(
            llvm::StringRef(job.bitcode.data(), job.bitcode.size()), ""),
        context);
    if (!unit)
      return llvm::toString(unit.takeError());
    if (!worker) {
      auto target = createMachine(targetTriple, optimize);
      if (!target)
        return llvm::toString(target.takeError());
      worker = std::move(*target);
    }
    if (job.optimize) {
      if (auto error = verifyObject(**unit, targetTriple, *worker))
        return llvm::toString(std::move(error));
      if (auto error =
              optimizeObject(**unit, targetTriple, *worker, true, false, false))
        return llvm::toString(std::move(error));
    }
    if (auto error = writeObject(**unit, *worker, job.output))
      return llvm::toString(std::move(error));
    return {};
  };
  std::vector<Job> serial;
  std::vector<std::shared_future<std::string>> parallel;
  std::unique_ptr<llvm::DefaultThreadPool> pool;
  std::unique_ptr<llvm::Module> localOwner;
  llvm::Module *local = nullptr;
  Job localJob;
  auto collect = [&](llvm::Module &unit,
                     std::unique_ptr<llvm::Module> owner) -> llvm::Error {
    Job job;
    job.optimize = unoptimized;
    if (unoptimized)
      if (auto error = verifyObject(unit, targetTriple, **machine))
        return error;
    llvm::raw_svector_ostream stream(job.bitcode);
    llvm::WriteBitcodeToFile(unit, stream);
    auto output =
        consume(llvm::StringRef(job.bitcode.data(), job.bitcode.size()),
                unoptimized        ? ObjectUnitKind::Unoptimized
                : &unit == &module ? ObjectUnitKind::Retained
                                   : ObjectUnitKind::Optimized);
    if (!output)
      return output.takeError();
    if (output->empty())
      return llvm::Error::success();
    job.output = std::move(*output);
    if ((!llvm::llvm_is_multithreaded() || threads <= 1) &&
        &unit.getContext() == &module.getContext() &&
        (!local || unit.getInstructionCount() > local->getInstructionCount())) {
      local = &unit;
      localOwner = std::move(owner);
      std::swap(job, localJob);
      if (job.output.empty())
        return llvm::Error::success();
    }
    if (llvm::llvm_is_multithreaded() && threads > 1) {
      if (!pool)
        pool = std::make_unique<llvm::DefaultThreadPool>(
            llvm::hardware_concurrency(threads));
      parallel.push_back(pool->async([&run, job = std::move(job)] {
        thread_local std::unique_ptr<llvm::TargetMachine> worker;
        return run(job, worker);
      }));
    } else {
      serial.push_back(std::move(job));
    }
    return llvm::Error::success();
  };
  auto *current = &module;
  std::string currentNamespace = symbolNamespace.str();
  if (optimize && targetTriple.isOSLinux()) {
    while (isolated.size() + 1 < 16) {
      auto part =
          splitEntryOptimization(*current, currentNamespace, isolated.empty());
      if (!part)
        break;
      const bool splitCold =
          part->getInstructionCount() > current->getInstructionCount();
      llvm::ModuleAnalysisManager analyses;
      llvm::StripDeadPrototypesPass{}.run(*current, analyses);
      llvm::StripDeadPrototypesPass{}.run(*part, analyses);
      unoptimized = true;
      if (auto error = collect(*current, nullptr))
        return error;
      current = part.get();
      currentNamespace += ".split";
      isolated.push_back(std::move(part));
      if (!splitCold)
        break;
    }
  }
  if (unoptimized) {
    if (auto error = collect(*current, nullptr))
      return error;
  } else {
    if (auto error = optimizeObject(module, targetTriple, **machine, optimize,
                                    false, false))
      return error;
    if (auto error = partitionObjectModule(module, symbolNamespace, collect))
      return error;
  }
  if (local) {
    if (localJob.optimize)
      if (auto error = optimizeObject(*local, targetTriple, **machine, true,
                                      false, false))
        return error;
    if (auto error = writeObject(*local, **machine, localJob.output))
      return error;
  }
  std::unique_ptr<llvm::TargetMachine> serialMachine;
  for (const auto &job : serial)
    if (auto error = run(job, serialMachine); !error.empty())
      return llvm::createStringError(llvm::inconvertibleErrorCode(), error);
  for (auto &result : parallel)
    if (const auto &error = result.get(); !error.empty())
      return llvm::createStringError(llvm::inconvertibleErrorCode(), error);
  return llvm::Error::success();
}

} // namespace mettle::backend
