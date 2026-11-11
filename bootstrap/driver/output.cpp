#include "driver/output.h"
#include "backend/llvm/lower.h"
#include "backend/llvm/object.h"
#include "driver/cache.h"
#include "packages/sha256.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/DiagnosticPrinter.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/ArchiveWriter.h"
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
// A private directory beside the output, so the object and the linked file
// get fixed names: random names would reach the executable (the linker's
// code-signature identifier and UUID) and break reproducible builds.
struct TemporaryDirectory {
  llvm::SmallString<256> path;
  ~TemporaryDirectory() {
    if (!path.empty()) {
      std::error_code ignored;
      std::filesystem::remove_all(path.str().str(), ignored);
    }
  }
  std::error_code create(const std::string &prefix) {
    return llvm::sys::fs::createUniqueDirectory(prefix, path);
  }
};

bool sameRuntimeTarget(llvm::StringRef requested, llvm::StringRef runtime) {
  const llvm::Triple a(llvm::Triple::normalize(requested)),
      b(llvm::Triple::normalize(runtime));
  return a.getArch() == b.getArch() && a.getVendor() == b.getVendor() &&
         a.getOS() == b.getOS() && a.getEnvironment() == b.getEnvironment() &&
         a.getOSVersion() == b.getOSVersion();
}

std::string runtimePath(const Options &options) {
  if (options.sanitizers.contains("address"))
    return METTLE_RUNTIME_ASAN_PATH;
  if (options.sanitizers.contains("thread"))
    return METTLE_RUNTIME_TSAN_PATH;
  return METTLE_RUNTIME_PATH;
}

// Reports why the runtime library and native link are unavailable, if so.
std::optional<std::string> linkUnavailable(const Options &options,
                                           std::string &compiler,
                                           bool needsLinker = true) {
  const auto runtime = runtimePath(options);
  if (!sameRuntimeTarget(options.target, METTLE_RUNTIME_TARGET))
    return std::string("runtime is built for ") + METTLE_RUNTIME_TARGET +
           "; use --emit object and link with a target runtime";
  if (!llvm::sys::fs::exists(runtime))
    return std::string("runtime library ") + runtime + " is missing";
  if (!needsLinker)
    return std::nullopt;
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

std::string artifactSuffix(const std::string &format,
                           const llvm::Triple &target) {
  return format == "static"   ? ".a"
         : format == "shared" ? (target.isOSDarwin() ? ".dylib" : ".so")
         : format == "object" ? ".o"
         : format == "llvm"   ? ".ll"
         : format == "ir"     ? ".ir"
                              : "";
}
} // namespace

std::optional<PackageObject>
nativePackageObject(const Options &options, const BuildInputs &inputs,
                    const ir::VerifiedProgram &program,
                    const std::string &identity,
                    const std::vector<std::string> &sources,
                    const std::string &checkedKey, std::string &error) {
  error.clear();
  const auto &ir = program.program();
  if (options.command != "build" || options.emit != "executable" ||
      options.emits.size() > 1 || options.library ||
      (options.profile != "debug" && options.profile != "release") ||
      options.debugInfo || !options.sanitizers.empty() ||
      !options.harness.empty() || options.freestanding ||
      options.packageContext || !ir.globalAssembly.empty() || sources.empty() ||
      checkedKey.empty() || !inputs.packageObjectsSafe() ||
      ir.functionPackages.size() != ir.functions.size() ||
      ir.staticPackages.size() != ir.statics.size())
    return std::nullopt;
  auto owned = [](const std::string &owner) {
    return owner.empty() || owner == "native:core" || owner == "native:alloc" ||
           owner == "native:std";
  };
  if (!std::all_of(ir.functionPackages.begin(), ir.functionPackages.end(),
                   owned) ||
      !std::all_of(ir.staticPackages.begin(), ir.staticPackages.end(), owned) ||
      (std::find(ir.functionPackages.begin(), ir.functionPackages.end(),
                 identity) == ir.functionPackages.end() &&
       std::find(ir.staticPackages.begin(), ir.staticPackages.end(),
                 identity) == ir.staticPackages.end()))
    return std::nullopt;
  llvm::LLVMContext context;
  auto module = mettle::backend::lower(
      program, context, options.checks.value_or(options.profile != "release"),
      options.target, false, nullptr, false, false, {true, identity, false});
  module->setModuleIdentifier(identity);
  module->setSourceFileName(sources.front());
  std::string verification;
  llvm::raw_string_ostream verificationStream(verification);
  if (llvm::verifyModule(*module, &verificationStream)) {
    error = "invalid " + identity + " object partition:\n" + verification;
    return std::nullopt;
  }
  // Unreferenced consumer declarations must not change the core partition key.
  for (auto it = module->begin(); it != module->end();) {
    auto &function = *it++;
    if (function.isDeclaration() && function.use_empty())
      function.eraseFromParent();
  }
  for (auto it = module->global_begin(); it != module->global_end();) {
    auto &global = *it++;
    if (global.isDeclaration() && global.use_empty())
      global.eraseFromParent();
  }
  auto byName = [](const auto &left, const auto &right) {
    return left.getName() < right.getName();
  };
  module->getFunctionList().sort(byName);
  std::string partition;
  llvm::raw_string_ostream stream(partition);
  module->print(stream, nullptr);
  packages::Sha256 hash;
  hash.update(partition);
  auto key = inputs.packageObjectKey(identity, sources,
                                     {{"checked:" + identity, checkedKey}}, {},
                                     options, hash.finish());
  if (!key)
    return std::nullopt;
  return PackageObject{identity, sources.front(), std::move(*key)};
}

bool outputOverwritesSource(const Options &options, const Source &source,
                            const Diagnostics &diagnostics) {
  namespace fs = std::filesystem;
  const llvm::Triple target(options.target);
  auto formats = options.emits;
  if (formats.empty())
    formats.push_back(options.emit);
  for (const auto &format : formats) {
    fs::path destination = options.output;
    if (formats.size() > 1)
      destination += artifactSuffix(format, target);
    auto aliases = [](const std::string &input, const fs::path &destination) {
      std::error_code error;
      if (fs::equivalent(input, destination, error))
        return true;
      error.clear();
      auto canonical = fs::weakly_canonical(input, error);
      if (error)
        return false;
      auto output = fs::weakly_canonical(destination, error);
      if (error)
        return false;
      if (canonical == output)
        return true;
      if (fs::is_directory(canonical, error)) {
        auto relative = output.lexically_relative(canonical);
        if (!relative.empty() && *relative.begin() != "..")
          return true;
      }
      auto relative = canonical.lexically_relative(output);
      return !relative.empty() && *relative.begin() != "..";
    };
    auto conflict = [&](const std::string &input) {
      return aliases(input, destination) ||
             (options.debugInfo && target.isOSDarwin() &&
              (format == "executable" || format == "shared") &&
              aliases(input, destination.string() + ".dSYM"));
    };
    if (conflict(source.path))
      return true;
    for (const auto &input : diagnostics.registeredSources())
      if (!input.path.empty() && conflict(input.path))
        return true;
  }
  return false;
}

static int emitOne(const Options &options, const Source &source,
                   const ir::VerifiedProgram &program,
                   const Diagnostics &diagnostics,
                   const std::vector<PackageObject> &packageObjects,
                   packages::Store *store) {
  std::error_code fileError;
  auto inputPath = std::filesystem::weakly_canonical(source.path, fileError);
  if (!fileError && inputPath == std::filesystem::weakly_canonical(
                                     options.output, fileError)) {
    std::cerr << "mettle: error[io]: output would overwrite the source\n";
    return 1;
  }
  std::string linker;
  const bool nativeLink =
      options.emit == "executable" || options.emit == "shared";
  const bool archive = options.emit == "static";
  if (nativeLink || (archive && !options.freestanding))
    if (auto reason = linkUnavailable(options, linker, nativeLink)) {
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
    // The comp_dir is the root source's directory, never a temporary path.
    mettle::backend::DebugInfoRequest debugRequest{
        diagnostics.registeredSources(),
        std::filesystem::path(source.path).parent_path().string(),
        [&diagnostics](Span span) { return diagnostics.debugSpan(span); }};
    const bool splitPackages = !packageObjects.empty();
    auto module = mettle::backend::lower(
        program, context, checked, options.target, options.freestanding,
        options.debugInfo && options.emit != "ir" ? &debugRequest : nullptr,
        options.sanitizers.contains("address"),
        options.sanitizers.contains("thread"),
        {splitPackages, {}, !options.library});
    module->setSourceFileName(source.path);
    module->setTargetTriple(
        llvm::Triple(llvm::Triple::normalize(options.target)));
    if (llvm::verifyModule(*module, &llvm::errs())) {
      std::cerr << "mettle: error[internal]: invalid generated LLVM module\n";
      return 1;
    }
    if (options.emit == "llvm") {
      if (auto error = mettle::backend::instrumentModule(
              *module, options.sanitizers.contains("address"),
              options.sanitizers.contains("thread"))) {
        std::cerr << "mettle: error[backend]: "
                  << llvm::toString(std::move(error)) << '\n';
        return 1;
      }
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
      TemporaryDirectory work;
      std::string objectPath = output.path.str().str(), linked;
      std::filesystem::path directory;
      if (nativeLink || archive) {
        std::error_code absoluteError;
        const auto beside =
            std::filesystem::absolute(options.output, absoluteError).string();
        if (auto error = work.create(beside + ".mettle-link"))
          return ioFailure(
              "cannot create link directory beside " + options.output, error);
        directory = std::filesystem::path(work.path.str().str());
        objectPath = (directory / "main.o").string();
        linked = (directory / std::filesystem::path(options.output).filename())
                     .string();
      }
      std::vector<std::string> packagePaths;
      std::vector<packages::Store::Artifact> packageArtifacts;
      std::vector<const PackageObject *> packagesToStore;
      for (std::size_t i = 0; i < packageObjects.size(); ++i) {
        const auto &package = packageObjects[i];
        const bool native = package.identity.starts_with("native:");
        const auto cacheLabel =
            native ? "library object cache " : "package object cache ";
        const auto cacheIdentity =
            native ? package.identity.substr(7) : package.identity;
        auto packagePath =
            (directory / ("package-" + std::to_string(i) + ".o")).string();
        bool reused = false;
        if (store) {
          auto found = store->materialize(package.key, packagePath);
          if (found == packages::Store::Lookup::Hit) {
            reused = true;
            if (options.explain)
              std::cerr << "mettle: " << cacheLabel << "hit " << cacheIdentity
                        << " " << package.key.substr(4, 12) << '\n';
          } else if (options.explain) {
            std::cerr << "mettle: " << cacheLabel
                      << (found == packages::Store::Lookup::Corrupt
                              ? "entry corrupt, rebuilding "
                              : "miss ")
                      << cacheIdentity << " " << package.key.substr(4, 12)
                      << '\n';
          }
        } else if (options.explain) {
          std::cerr << "mettle: " << cacheLabel << "miss " << cacheIdentity
                    << " (disabled)\n";
        }
        if (!reused) {
          auto dependency = mettle::backend::lower(
              program, context, checked, options.target, options.freestanding,
              nullptr, false, false, {true, package.identity});
          dependency->setSourceFileName(package.source);
          dependency->setTargetTriple(
              llvm::Triple(llvm::Triple::normalize(options.target)));
          if (llvm::verifyModule(*dependency, &llvm::errs())) {
            std::cerr << "mettle: error[internal]: invalid generated package "
                         "LLVM module for "
                      << package.identity << '\n';
            return 1;
          }
          if (auto error =
                  mettle::backend::emitObject(*dependency, options.target,
                                              packagePath, native && release)) {
            std::cerr << "mettle: error[backend]: "
                      << llvm::toString(std::move(error)) << '\n';
            return 1;
          }
          if (backendDiagnostics.failed) {
            std::cerr << "mettle: error[assembly]: target assembly/code "
                         "generation rejected package '"
                      << package.identity << "':\n"
                      << backendDiagnostics.text;
            return 1;
          }
          if (store) {
            packageArtifacts.push_back({package.key, packagePath, false});
            packagesToStore.push_back(&package);
          }
        }
        packagePaths.push_back(std::move(packagePath));
      }
      if (auto error = mettle::backend::emitObject(
              *module, options.target, objectPath, release,
              options.sanitizers.contains("address"),
              options.sanitizers.contains("thread"))) {
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
      if (archive) {
        std::vector<llvm::NewArchiveMember> members;
        auto object = llvm::NewArchiveMember::getFile(objectPath, true);
        if (!object) {
          std::cerr << "mettle: error[io]: "
                    << llvm::toString(object.takeError()) << '\n';
          return 1;
        }
        object->MemberName = "main.o";
        members.push_back(std::move(*object));
        std::unique_ptr<llvm::MemoryBuffer> runtimeBuffer;
        std::unique_ptr<llvm::object::Archive> runtimeArchive;
        if (!options.freestanding) {
          auto buffer = llvm::MemoryBuffer::getFile(runtimePath(options));
          if (!buffer)
            return ioFailure("cannot read runtime archive", buffer.getError());
          runtimeBuffer = std::move(*buffer);
          auto runtime =
              llvm::object::Archive::create(runtimeBuffer->getMemBufferRef());
          if (!runtime) {
            std::cerr << "mettle: error[link]: "
                      << llvm::toString(runtime.takeError()) << '\n';
            return 1;
          }
          runtimeArchive = std::move(*runtime);
          llvm::Error error = llvm::Error::success();
          for (const auto &child : runtimeArchive->children(error)) {
            auto member = llvm::NewArchiveMember::getOldMember(child, true);
            if (!member) {
              llvm::consumeError(std::move(error));
              std::cerr << "mettle: error[link]: "
                        << llvm::toString(member.takeError()) << '\n';
              return 1;
            }
            members.push_back(std::move(*member));
          }
          if (error) {
            std::cerr << "mettle: error[link]: "
                      << llvm::toString(std::move(error)) << '\n';
            return 1;
          }
        }
        if (auto error = llvm::writeArchive(
                output.path, members, llvm::SymtabWritingMode::NormalSymtab,
                llvm::object::Archive::getDefaultKindForTriple(target), true,
                false)) {
          std::cerr << "mettle: error[link]: "
                    << llvm::toString(std::move(error)) << '\n';
          return 1;
        }
      } else if (nativeLink) {
        std::vector<std::string> arguments{linker,
                                           "--target=" + options.target};
        if (options.emit == "shared")
          arguments.push_back(target.isOSDarwin() ? "-dynamiclib" : "-shared");
        if (options.emit == "shared" && target.isOSDarwin())
          arguments.push_back(
              "-Wl,-install_name,@rpath/" +
              std::filesystem::path(options.output).filename().string());
        arguments.insert(arguments.end(), packagePaths.begin(),
                         packagePaths.end());
        arguments.push_back(objectPath);
        arguments.push_back(runtimePath(options));
        arguments.push_back("-o");
        arguments.push_back(linked);
        if (!options.sysroot.empty())
          arguments.push_back("--sysroot=" + options.sysroot);
        for (const auto &library : program.program().libraries)
          arguments.push_back("-l" + library);
        for (const auto &library : options.extraLibraries)
          arguments.push_back("-l" + library);
        if (llvm::Triple(options.target).isOSLinux()) {
          arguments.push_back("-fuse-ld=lld");
          arguments.push_back("-pthread");
        }
        if (options.sanitizers.contains("address")) {
          arguments.push_back("-fsanitize=address");
          arguments.push_back("-fno-sanitize-recover=all");
          arguments.push_back("-fno-omit-frame-pointer");
        } else if (options.sanitizers.contains("thread")) {
          arguments.push_back("-fsanitize=thread");
          arguments.push_back("-fno-sanitize-recover=all");
          arguments.push_back("-fno-omit-frame-pointer");
        }
#if METTLE_RUNTIME_SANITIZED
        else {
          arguments.push_back("-fsanitize=address,undefined");
          arguments.push_back("-fno-sanitize-recover=all");
        }
#endif
        std::vector<llvm::StringRef> refs(arguments.begin(), arguments.end());
        if (llvm::sys::ExecuteAndWait(linker, refs) != 0) {
          std::cerr << "mettle: error[link]: native link failed\n";
          return 1;
        }
        if (options.debugInfo && llvm::Triple(options.target).isOSDarwin()) {
          // ld64 only records a debug map to the temporary main.o, which is
          // deleted below; dsymutil folds the DWARF into OUTPUT.dSYM first.
          std::string tool;
          auto dir = std::filesystem::path(linker).parent_path().string();
          if (!dir.empty())
            if (auto found = llvm::sys::findProgramByName("dsymutil", {dir}))
              tool = *found;
          if (tool.empty())
            if (auto found = llvm::sys::findProgramByName("dsymutil"))
              tool = *found;
          if (tool.empty()) {
            std::cerr << "mettle: warning[debug]: dsymutil not found; the "
                         "executable has no debug symbols\n";
          } else {
            std::error_code absoluteError;
            const auto bundle =
                std::filesystem::absolute(options.output, absoluteError)
                    .string() +
                ".dSYM";
            std::filesystem::remove_all(bundle, absoluteError);
            std::vector<llvm::StringRef> symbolArguments{tool, linked, "-o",
                                                         bundle};
            if (llvm::sys::ExecuteAndWait(tool, symbolArguments) != 0)
              std::cerr << "mettle: warning[debug]: dsymutil failed\n";
          }
        }
        if (auto error = llvm::sys::fs::rename(linked, output.path))
          return ioFailure("cannot move linked output", error);
      }
      if (store && !packageArtifacts.empty()) {
        bool stored = store->putMany(packageArtifacts);
        if (options.explain)
          for (const auto *package : packagesToStore)
            std::cerr << "mettle: "
                      << (package->identity.starts_with("native:")
                              ? "library object cache "
                              : "package object cache ")
                      << (stored ? "stored " : "could not store ")
                      << (package->identity.starts_with("native:")
                              ? package->identity.substr(7)
                              : package->identity)
                      << " " << package->key.substr(4, 12) << '\n';
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

int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program, const Diagnostics &diagnostics,
         const std::vector<PackageObject> &packageObjects,
         packages::Store *store) {
  if (outputOverwritesSource(options, source, diagnostics)) {
    std::cerr << "mettle: error[io]: output would overwrite the source\n";
    return 1;
  }
  if (options.emits.size() <= 1)
    return emitOne(options, source, program, diagnostics, packageObjects,
                   store);
  namespace fs = std::filesystem;
  TemporaryDirectory work;
  if (auto error = work.create(options.output + ".mettle-outputs"))
    return ioFailure("cannot stage requested outputs", error);
  const fs::path directory(work.path.str().str());
  std::error_code directoryError;
  fs::create_directory(directory / "outputs", directoryError);
  if (!directoryError)
    fs::create_directory(directory / "backups", directoryError);
  if (directoryError)
    return ioFailure("cannot prepare output staging", directoryError);
  struct Artifact {
    fs::path destination, staged, backup;
    bool existed = false, directory = false;
  };
  std::vector<Artifact> artifacts;
  const llvm::Triple target(options.target);
  for (const auto &format : options.emits) {
    const auto suffix = artifactSuffix(format, target);
    Artifact artifact;
    artifact.destination = options.output + suffix;
    artifact.staged = directory / "outputs" / artifact.destination.filename();
    artifact.backup =
        directory / "backups" / ("backup-" + std::to_string(artifacts.size()));
    std::error_code error;
    if (fs::equivalent(source.path, artifact.destination, error)) {
      std::cerr << "mettle: error[io]: output would overwrite the source\n";
      return 1;
    }
    error.clear();
    artifact.existed = fs::exists(artifact.destination, error);
    if (error)
      return ioFailure("cannot inspect output", error);
    if (artifact.existed) {
      fs::copy_file(artifact.destination, artifact.backup, error);
      if (error)
        return ioFailure("cannot preserve existing output", error);
    }
    Options selected = options;
    selected.emit = format;
    selected.output = artifact.staged.string();
    if (int status = emitOne(selected, source, program, diagnostics, {}, store))
      return status;
    artifacts.push_back(std::move(artifact));
    const auto bundle = selected.output + ".dSYM";
    if (fs::exists(bundle, error)) {
      Artifact symbols;
      symbols.staged = bundle;
      symbols.destination = options.output + suffix + std::string(".dSYM");
      symbols.backup = directory / "backups" /
                       ("backup-" + std::to_string(artifacts.size()));
      symbols.existed = fs::exists(symbols.destination, error);
      if (error)
        return ioFailure("cannot inspect debug bundle", error);
      symbols.directory = true;
      artifacts.push_back(std::move(symbols));
    }
    if (error)
      return ioFailure("cannot inspect staged debug bundle", error);
  }
  for (std::size_t i = 0; i < artifacts.size(); ++i) {
    const auto &artifact = artifacts[i];
    std::error_code error;
    bool savedDirectory = false;
    if (artifact.directory && artifact.existed) {
      error = llvm::sys::fs::rename(artifact.destination.string(),
                                    artifact.backup.string());
      savedDirectory = !error;
    }
    if (!error)
      error = llvm::sys::fs::rename(artifact.staged.string(),
                                    artifact.destination.string());
    if (error) {
      for (std::size_t j = 0; j <= i; ++j) {
        std::error_code restore;
        const auto &previous = artifacts[j];
        if (j == i && previous.directory && !savedDirectory)
          continue;
        if (previous.directory && previous.existed) {
          fs::remove_all(previous.destination, restore);
          if (!restore)
            fs::rename(previous.backup, previous.destination, restore);
        } else if (previous.existed)
          fs::copy_file(previous.backup, previous.destination,
                        fs::copy_options::overwrite_existing, restore);
        else
          fs::remove(previous.destination, restore);
        if (restore)
          ioFailure("cannot restore " + previous.destination.string(), restore);
      }
      return ioFailure("cannot publish " + artifact.destination.string(),
                       error);
    }
  }
  return 0;
}
} // namespace mettle::driver
