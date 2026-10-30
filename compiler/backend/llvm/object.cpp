#include "backend/llvm/object.h"

#include "types/layout.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
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

#include <memory>
#include <mutex>
#include <optional>
#include <string>

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
  const llvm::TargetOptions options;
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

llvm::Error emitObject(llvm::Module &module, llvm::StringRef triple,
                       llvm::StringRef output, bool optimize) {
  std::string diagnostic;
  const llvm::Triple targetTriple(llvm::Triple::normalize(triple));
  if (auto *identity = llvm::dyn_cast_or_null<llvm::MDString>(
          module.getModuleFlag("mettle.target.triple"));
      identity &&
      llvm::Triple::normalize(identity->getString()) != targetTriple.str())
    return llvm::createStringError(
        llvm::inconvertibleErrorCode(),
        "checked target facts disagree with the object target");
  auto created = createMachine(targetTriple, optimize);
  if (!created)
    return created.takeError();
  const std::unique_ptr<llvm::TargetMachine> machine = std::move(*created);
  module.setTargetTriple(targetTriple);
  const auto machineLayout = machine->createDataLayout();
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
  if (optimize) {
    llvm::LoopAnalysisManager loops;
    llvm::FunctionAnalysisManager functions;
    llvm::CGSCCAnalysisManager calls;
    llvm::ModuleAnalysisManager modules;
    llvm::PassBuilder builder(machine.get());
    builder.registerLoopAnalyses(loops);
    builder.registerFunctionAnalyses(functions);
    builder.registerCGSCCAnalyses(calls);
    builder.registerModuleAnalyses(modules);
    builder.crossRegisterProxies(loops, functions, calls, modules);
    auto pipeline =
        builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O2);
    pipeline.run(module, modules);
    if (llvm::verifyModule(module, &diagnostics))
      return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                     "invalid optimized backend module: " +
                                         diagnostic);
  }
  std::error_code error;
  llvm::raw_fd_ostream stream(output, error, llvm::sys::fs::OF_None);
  if (error) {
    return llvm::createStringError(error, "cannot create object file");
  }
  llvm::legacy::PassManager passes;
  if (machine->addPassesToEmitFile(passes, stream, nullptr,
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

} // namespace mettle::backend
