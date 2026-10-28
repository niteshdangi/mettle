#include "backend/llvm/object.h"

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
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <mutex>
#include <optional>
#include <string>

namespace mettle::backend {

llvm::Error emitObject(llvm::Module &module, llvm::StringRef triple,
                       llvm::StringRef output, bool optimize) {
  static std::once_flag initialized;
  std::call_once(initialized, [] {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeAArch64TargetInfo();
    LLVMInitializeAArch64Target();
    LLVMInitializeAArch64TargetMC();
    LLVMInitializeAArch64AsmPrinter();
    LLVMInitializeWebAssemblyTargetInfo();
    LLVMInitializeWebAssemblyTarget();
    LLVMInitializeWebAssemblyTargetMC();
    LLVMInitializeWebAssemblyAsmPrinter();
    LLVMInitializeARMTargetInfo();
    LLVMInitializeARMTarget();
    LLVMInitializeARMTargetMC();
    LLVMInitializeARMAsmPrinter();
  });

  std::string diagnostic;
  const llvm::Triple targetTriple(llvm::Triple::normalize(triple));
  const auto *target =
      llvm::TargetRegistry::lookupTarget(targetTriple, diagnostic);
  if (target == nullptr) {
    return llvm::createStringError(llvm::inconvertibleErrorCode(), diagnostic);
  }
  const llvm::TargetOptions options;
  const std::unique_ptr<llvm::TargetMachine> machine(
      target->createTargetMachine(targetTriple, "generic", "", options,
                                  llvm::Reloc::PIC_, std::nullopt,
                                  optimize ? llvm::CodeGenOptLevel::Aggressive
                                           : llvm::CodeGenOptLevel::None));
  if (machine == nullptr) {
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "target machine creation failed");
  }
  module.setTargetTriple(targetTriple);
  module.setDataLayout(machine->createDataLayout());

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
