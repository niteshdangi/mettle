#include "driver/output.h"
#include "backend/llvm/lower.h"
#include "backend/llvm/object.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/DiagnosticPrinter.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Triple.h"
#include <algorithm>
#include <filesystem>
#include <iostream>
#include <sstream>

namespace mettle::driver {
namespace {
struct Temporary {
  llvm::SmallString<256> path;
  ~Temporary() {
    if (!path.empty())
      llvm::sys::fs::remove(path);
  }
  bool create(const std::string &model) {
    return !llvm::sys::fs::createUniqueFile(model, path);
  }
};

} // namespace
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program) {
  std::error_code fileError;
  auto inputPath = std::filesystem::weakly_canonical(options.input, fileError);
  if (!fileError && inputPath == std::filesystem::weakly_canonical(
                                     options.output, fileError)) {
    std::cerr << "mettle: error[io]: output would overwrite the source\n";
    return 1;
  }
  Temporary output;
  if (!output.create(options.output + ".mettle-%%%%%%")) {
    std::cerr << "mettle: error[io]: cannot create output beside "
              << options.output << '\n';
    return 1;
  }
  bool release = options.profile == "release";
  bool checked = options.checks.value_or(!release);
  if (options.emit == "ir") {
    std::ostringstream stream;
    mettle::ir::print(program.program(), stream);
    llvm::raw_fd_ostream out(output.path, fileError);
    if (fileError)
      return 1;
    out << stream.str();
    out.close();
    if (out.has_error()) {
      out.clear_error();
      return 1;
    }
  } else {
    struct BackendDiagnostics {
      std::string text;
      bool failed = false;
    } backendDiagnostics;
    llvm::LLVMContext context;
    context.setDiagnosticHandlerCallBack(
        [](const llvm::DiagnosticInfo *diagnostic, void *opaque) {
          auto &state = *static_cast<BackendDiagnostics *>(opaque);
          llvm::raw_string_ostream text(state.text);
          llvm::DiagnosticPrinterRawOStream printer(text);
          diagnostic->print(printer);
          text << '\n';
          state.failed |= diagnostic->getSeverity() == llvm::DS_Error;
        },
        &backendDiagnostics);
    auto target = llvm::Triple(llvm::Triple::normalize(options.target));
    auto facts = targetFacts(options.target);
    if (program.program().target.arch != facts.arch ||
        program.program().target.system != facts.system ||
        program.program().target.pointerBits != facts.pointerBits ||
        program.program().target.baseline != facts.baseline) {
      std::cerr
          << "mettle: error[internal]: checked target facts disagree with "
             "the selected backend target\n";
      return 1;
    }
    bool foreign = false, foreignUnwind = false;
    for (const auto &function : program.program().functions) {
      foreign |= !function.abi.empty();
      foreignUnwind |= function.abi == "C-unwind";
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions)
          if (program.program().types->isFunctionPointer(
                  instruction.indirectType)) {
            const auto &abi =
                program.program().types->callable(instruction.indirectType).abi;
            foreign |= !abi.empty();
            foreignUnwind |= abi == "C-unwind";
          }
    }
    if (foreign &&
        !((target.getArch() == llvm::Triple::x86_64 && target.isOSLinux()) ||
          (target.getArch() == llvm::Triple::aarch64 && target.isOSDarwin()))) {
      std::cerr << "mettle: error[feature]: this C ABI implementation supports "
                   "Linux x86-64 and Darwin ARM64\n";
      return 1;
    }
    if (options.freestanding && foreignUnwind) {
      std::cerr << "mettle: error[feature]: freestanding abort mode cannot "
                   "require a foreign unwind runtime\n";
      return 1;
    }
    auto module = mettle::backend::lower(program, context, checked,
                                         options.target, options.freestanding);
    module->setSourceFileName(source.path);
    module->setTargetTriple(
        llvm::Triple(llvm::Triple::normalize(options.target)));
    if (llvm::verifyModule(*module, &llvm::errs())) {
      std::cerr << "mettle: error[internal]: invalid generated LLVM module\n";
      return 1;
    }
    if (options.emit == "llvm") {
      llvm::raw_fd_ostream out(output.path, fileError);
      if (fileError)
        return 1;
      module->print(out, nullptr);
      out.close();
      if (out.has_error()) {
        out.clear_error();
        return 1;
      }
    } else {
      Temporary object;
      std::string objectPath = output.path.str().str();
      if (options.emit == "executable") {
        if (!object.create(options.output + ".object-%%%%%%"))
          return 1;
        objectPath = object.path.str().str();
      }
      if (auto error = mettle::backend::emitObject(*module, options.target,
                                                   objectPath, release)) {
        std::cerr << "mettle: error[backend]: "
                  << llvm::toString(std::move(error)) << '\n';
        return 1;
      }
      if (backendDiagnostics.failed) {
        std::cerr << "mettle: error[assembly]: target assembly/code generation "
                     "rejected the program:\n"
                  << backendDiagnostics.text;
        return 1;
      }
      if (options.emit == "executable") {
        if (llvm::Triple::normalize(options.target) !=
            llvm::Triple::normalize(METTLE_RUNTIME_TARGET)) {
          std::cerr << "mettle: error[link]: runtime is built for "
                    << METTLE_RUNTIME_TARGET
                    << "; use --emit object and link with a target runtime\n";
          return 1;
        }
        auto compiler = llvm::sys::findProgramByName(options.cc);
        if (!compiler) {
          std::cerr << "mettle: error[link]: cannot find selected C++ linker\n";
          return 1;
        }
        std::vector<std::string> arguments{
            *compiler,  "--target=" + options.target,
            objectPath, METTLE_RUNTIME_PATH,
            "-o",       output.path.str().str()};
        if (!options.sysroot.empty())
          arguments.push_back("--sysroot=" + options.sysroot);
        for (const auto &library : program.program().libraries)
          arguments.push_back("-l" + library);
        if (llvm::Triple(options.target).isOSLinux())
          arguments.push_back("-fuse-ld=lld");
#if METTLE_RUNTIME_SANITIZED
        arguments.push_back("-fsanitize=address,undefined");
        arguments.push_back("-fno-sanitize-recover=all");
#endif
        std::vector<llvm::StringRef> refs(arguments.begin(), arguments.end());
        if (llvm::sys::ExecuteAndWait(*compiler, refs) != 0) {
          std::cerr << "mettle: error[link]: native link failed\n";
          return 1;
        }
      }
    }
  }
  if (auto error = llvm::sys::fs::rename(output.path, options.output)) {
    std::cerr << "mettle: error[io]: cannot publish output: " << error.message()
              << '\n';
    return 1;
  }
  output.path.clear();
  return 0;
}
} // namespace mettle::driver
