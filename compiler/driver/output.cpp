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
#include <optional>
#include <sstream>

namespace mettle::driver {
namespace {
struct Temporary {
  llvm::SmallString<256> path;
  ~Temporary() {
    if (!path.empty())
      llvm::sys::fs::remove(path);
  }
  std::error_code create(const std::string &model) {
    return llvm::sys::fs::createUniqueFile(model, path);
  }
};

bool sameRuntimeTarget(llvm::StringRef requested, llvm::StringRef runtime) {
  const llvm::Triple a(llvm::Triple::normalize(requested)),
      b(llvm::Triple::normalize(runtime));
  return a.getArch() == b.getArch() && a.getVendor() == b.getVendor() &&
         a.getOS() == b.getOS() && a.getEnvironment() == b.getEnvironment() &&
         a.getOSVersion() == b.getOSVersion();
}

// Reports why the runtime library and native link are unavailable, if so.
std::optional<std::string> linkUnavailable(const Options &options,
                                           std::string &compiler) {
  if (!sameRuntimeTarget(options.target, METTLE_RUNTIME_TARGET))
    return std::string("runtime is built for ") + METTLE_RUNTIME_TARGET +
           "; use --emit object and link with a target runtime";
  if (!llvm::sys::fs::exists(METTLE_RUNTIME_PATH))
    return std::string("runtime library ") + METTLE_RUNTIME_PATH +
           " is missing";
  auto found = llvm::sys::findProgramByName(options.cc);
  if (!found)
    return "cannot find selected C++ linker";
  compiler = *found;
  return std::nullopt;
}

int ioFailure(const std::string &action, const std::error_code &error) {
  std::cerr << "mettle: error[io]: " << action << ": " << error.message()
            << '\n';
  return 1;
}
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
  std::string linker;
  if (options.emit == "executable")
    if (auto reason = linkUnavailable(options, linker)) {
      std::cerr << "mettle: error[link]: " << *reason << '\n';
      return 1;
    }
  Temporary output;
  if (auto error = output.create(options.output + ".mettle-%%%%%%")) {
    std::cerr << "mettle: error[io]: cannot create output beside "
              << options.output << ": " << error.message() << '\n';
    return 1;
  }
  bool release = options.profile == "release";
  bool checked = options.checks.value_or(!release);
  if (options.emit == "ir") {
    std::ostringstream stream;
    mettle::ir::print(program.program(), stream);
    llvm::raw_fd_ostream out(output.path, fileError);
    if (fileError)
      return ioFailure("cannot open " + options.output, fileError);
    out << stream.str();
    out.close();
    if (out.has_error()) {
      auto writeError = out.error();
      out.clear_error();
      return ioFailure("cannot write " + options.output, writeError);
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
    if (auto error = mettle::backend::checkTargetLayout(
            *program.program().types, options.target)) {
      std::cerr << "mettle: error[internal]: "
                << llvm::toString(std::move(error)) << '\n';
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
        return ioFailure("cannot open " + options.output, fileError);
      module->print(out, nullptr);
      out.close();
      if (out.has_error()) {
        auto writeError = out.error();
        out.clear_error();
        return ioFailure("cannot write " + options.output, writeError);
      }
    } else {
      Temporary object;
      std::string objectPath = output.path.str().str();
      if (options.emit == "executable") {
        if (auto error = object.create(options.output + ".object-%%%%%%"))
          return ioFailure("cannot create object beside " + options.output,
                           error);
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
        std::vector<std::string> arguments{
            linker,     "--target=" + options.target,
            objectPath, METTLE_RUNTIME_PATH,
            "-o",       output.path.str().str()};
        if (!options.sysroot.empty())
          arguments.push_back("--sysroot=" + options.sysroot);
        for (const auto &library : program.program().libraries)
          arguments.push_back("-l" + library);
        if (llvm::Triple(options.target).isOSLinux()) {
          arguments.push_back("-fuse-ld=lld");
          arguments.push_back("-pthread");
        }
#if METTLE_RUNTIME_SANITIZED
        arguments.push_back("-fsanitize=address,undefined");
        arguments.push_back("-fno-sanitize-recover=all");
#endif
        std::vector<llvm::StringRef> refs(arguments.begin(), arguments.end());
        if (llvm::sys::ExecuteAndWait(linker, refs) != 0) {
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
