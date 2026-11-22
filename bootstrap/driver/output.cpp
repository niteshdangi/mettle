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
#include "llvm/Transforms/Utils/Cloning.h"
#include <algorithm>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <unordered_map>

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

struct BackendOutput {
  std::string diagnostics;
  bool failed = false;
  llvm::LLVMContext context;
  std::unique_ptr<llvm::Module> module;
  Temporary object;
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

llvm::Error emitUnitArchive(llvm::Module &module, const Options &options,
                            llvm::StringRef output,
                            const std::filesystem::path &directory,
                            const std::string &identity, packages::Store *store,
                            std::vector<packages::Store::Artifact> &artifacts) {
  packages::Sha256 namespaceHash;
  for (const auto &field : {std::string("mettle-object-units-2"), identity,
                            module.getSourceFileName()}) {
    namespaceHash.update(field);
    namespaceHash.update(std::string_view("\0", 1));
  }
  const auto symbolNamespace = namespaceHash.finish();
  packages::Sha256 bucketHash;
  for (const auto &field :
       {symbolNamespace, compilerIdentity(), options.target, options.profile,
        std::to_string(
            options.checks.value_or(options.profile != "release"))}) {
    bucketHash.update(field);
    bucketHash.update(std::string_view("\0", 1));
  }
  const auto bucketKey = "unit-" + bucketHash.finish();
  const auto previousPath = directory / (bucketKey + ".a");
  std::unique_ptr<llvm::MemoryBuffer> previousBuffer;
  std::unique_ptr<llvm::object::Archive> previousArchive;
  std::unordered_map<std::string, llvm::NewArchiveMember> previous;
  if (store && store->materialize(bucketKey, previousPath) ==
                   packages::Store::Lookup::Hit) {
    auto buffer = llvm::MemoryBuffer::getFile(previousPath.string());
    if (!buffer)
      return llvm::createStringError(buffer.getError(),
                                     "cannot read object unit cache");
    previousBuffer = std::move(*buffer);
    auto archive =
        llvm::object::Archive::create(previousBuffer->getMemBufferRef());
    if (!archive)
      llvm::consumeError(archive.takeError());
    else {
      previousArchive = std::move(*archive);
      llvm::Error error = llvm::Error::success();
      for (const auto &child : previousArchive->children(error)) {
        auto member = llvm::NewArchiveMember::getOldMember(child, true);
        if (!member) {
          llvm::consumeError(member.takeError());
          previous.clear();
          break;
        }
        previous.emplace(member->MemberName.str(), std::move(*member));
      }
      if (error) {
        llvm::consumeError(std::move(error));
        previous.clear();
      }
    }
  }
  std::vector<llvm::NewArchiveMember> members;
  std::deque<std::string> memberNames;
  std::size_t reused = 0, generated = 0;
  if (auto error = mettle::backend::emitObjectUnits(
          module, options.target, symbolNamespace, options.profile == "release",
          [&](llvm::Module &unit,
              mettle::backend::ObjectUnitEmitter emit) -> llvm::Error {
            std::string text;
            llvm::raw_string_ostream stream(text);
            unit.print(stream, nullptr);
            packages::Sha256 hash;
            hash.update(bucketKey);
            hash.update(text);
            const auto name =
                (&unit == &module ? "retained-" : "") + hash.finish() + ".o";
            if (auto found = previous.find(name); found != previous.end()) {
              members.push_back(std::move(found->second));
              ++reused;
            } else {
              const auto path = (directory / name).string();
              if (auto error = emit(path))
                return error;
              auto member = llvm::NewArchiveMember::getFile(path, true);
              if (!member)
                return member.takeError();
              memberNames.push_back(name);
              member->MemberName = memberNames.back();
              members.push_back(std::move(*member));
              ++generated;
            }
            return llvm::Error::success();
          }))
    return error;
  if (auto error = llvm::writeArchive(
          output, members, llvm::SymtabWritingMode::NormalSymtab,
          llvm::object::Archive::getDefaultKindForTriple(
              llvm::Triple(options.target)),
          true, false))
    return error;
  if (store)
    artifacts.push_back({bucketKey, output.str(), false});
  if (options.explain)
    std::cerr << "mettle: machine unit cache " << identity << " reused "
              << reused << " generated " << generated << '\n';
  return llvm::Error::success();
}

llvm::Expected<bool> retainedArchive(llvm::StringRef path) {
  auto buffer = llvm::MemoryBuffer::getFile(path);
  if (!buffer)
    return llvm::createStringError(buffer.getError(),
                                   "cannot read native unit archive");
  auto archive = llvm::object::Archive::create((*buffer)->getMemBufferRef());
  if (!archive)
    return archive.takeError();
  llvm::Error error = llvm::Error::success();
  bool retained = false;
  for (const auto &child : (*archive)->children(error)) {
    auto name = child.getName();
    if (!name) {
      llvm::consumeError(std::move(error));
      return name.takeError();
    }
    retained = name->starts_with("retained-");
    break;
  }
  if (error)
    return std::move(error);
  return retained;
}
} // namespace

std::vector<PackageObject> libraryObjects(
    const Options &options, const BuildInputs &inputs,
    const ir::Program &program,
    const std::map<std::string, std::vector<std::string>> &packageSources,
    const std::map<std::string, std::string> &packageKeys,
    const std::function<const ir::VerifiedProgram *()> &library) {
  if (options.command != "build" || options.emit != "executable" ||
      options.emits.size() > 1 || options.library ||
      (options.profile != "debug" && options.profile != "release") ||
      options.debugInfo || !options.sanitizers.empty() ||
      !options.harness.empty() || options.freestanding ||
      options.packageContext || !program.globalAssembly.empty() ||
      !inputs.packageObjectsSafe() ||
      program.functionPackages.size() != program.functions.size() ||
      program.staticPackages.size() != program.statics.size() ||
      program.libraryBodies.size() < program.functions.size())
    return {};
  auto owned = [&](const std::string &owner) {
    return owner.empty() || packageSources.contains(owner);
  };
  if (!std::all_of(program.functionPackages.begin(),
                   program.functionPackages.end(), owned) ||
      !std::all_of(program.staticPackages.begin(), program.staticPackages.end(),
                   owned))
    return {};
  for (std::size_t i = 0; i < program.functionPackages.size(); ++i)
    if (!program.functionPackages[i].empty()) {
      const auto &function = program.functions[i];
      if (!program.libraryBodies[i] || function.variadicCursor >= 0 ||
          (!function.abi.empty() && function.externalName.empty()))
        return {};
    }
  std::vector<PackageObject> objects;
  // Objects reference each other's bodies, so all link together.
  for (const auto &[identity, sources] : packageSources) {
    auto key = packageKeys.find(identity);
    if (!identity.starts_with("native:") || sources.empty() ||
        key == packageKeys.end() || key->second.empty())
      return {};
    packages::Sha256 hash;
    for (const auto &field : {std::string("mettle-library-object-3"),
                              compilerIdentity(), identity, key->second}) {
      hash.update(field);
      hash.update(std::string_view("\0", 1));
    }
    // Panic locations embed the library's source paths.
    for (const auto &path : sources) {
      hash.update(path);
      hash.update(std::string_view("\0", 1));
    }
    objects.push_back(
        {identity, sources.front(), "pkg-" + hash.finish(), library});
  }
  return objects;
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
                   packages::Store *store,
                   BackendOutput *sharedBackend = nullptr) {
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
    std::optional<BackendOutput> localBackend;
    if (!sharedBackend)
      localBackend.emplace();
    auto &backend = sharedBackend ? *sharedBackend : *localBackend;
    auto &context = backend.context;
    context.setDiagnosticHandlerCallBack(
        [](const llvm::DiagnosticInfo *diagnostic, void *opaque) {
          auto &state = *static_cast<BackendOutput *>(opaque);
          llvm::raw_string_ostream text(state.diagnostics);
          llvm::DiagnosticPrinterRawOStream printer(text);
          diagnostic->print(printer);
          text << '\n';
          state.failed |= diagnostic->getSeverity() == llvm::DS_Error;
        },
        &backend);
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
        {},
        std::filesystem::path(source.path).parent_path().string(),
        [&diagnostics](Span span) { return diagnostics.debugSpan(span); }};
    debugRequest.sources.reserve(diagnostics.registeredSources().size());
    for (const auto &input : diagnostics.registeredSources())
      debugRequest.sources.push_back(&input);
    const bool splitPackages = !packageObjects.empty();
    const bool privateRoot =
        release && splitPackages &&
        std::all_of(packageObjects.begin(), packageObjects.end(),
                    [](const auto &package) {
                      return package.identity.starts_with("native:");
                    });
    if (!backend.module) {
      if (options.explain)
        std::cerr << "mettle: backend lowering " << options.target << '\n';
      backend.module = mettle::backend::lower(
          program, context, checked, options.target, options.freestanding,
          options.debugInfo && options.emit != "ir" ? &debugRequest : nullptr,
          options.sanitizers.contains("address"),
          options.sanitizers.contains("thread"),
          {splitPackages, {}, !options.library, false, privateRoot},
          &debugRequest);
    }
    auto &module = backend.module;
    module->setSourceFileName(source.path);
    module->setTargetTriple(
        llvm::Triple(llvm::Triple::normalize(options.target)));
    if (llvm::verifyModule(*module, &llvm::errs())) {
      std::cerr << "mettle: error[internal]: invalid generated LLVM module\n";
      return 1;
    }
    if (options.emit == "llvm") {
      auto instrumented =
          !options.sanitizers.empty() ? llvm::CloneModule(*module) : nullptr;
      auto &printed = instrumented ? *instrumented : *module;
      if (auto error = mettle::backend::instrumentModule(
              printed, options.sanitizers.contains("address"),
              options.sanitizers.contains("thread"))) {
        std::cerr << "mettle: error[backend]: "
                  << llvm::toString(std::move(error)) << '\n';
        return 1;
      }
      llvm::raw_fd_ostream out(output.path, fileError);
      if (fileError)
        return ioFailure("cannot open " + options.output, fileError);
      printed.print(out, nullptr);
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
      const bool rootUnits = options.emit == "executable" &&
                             options.emits.size() <= 1 && !options.debugInfo &&
                             options.sanitizers.empty() &&
                             program.program().globalAssembly.empty();
      if (rootUnits)
        objectPath = (directory / "main.a").string();
      for (std::size_t i = 0; i < packageObjects.size(); ++i) {
        const auto &package = packageObjects[i];
        const bool native = package.identity.starts_with("native:");
        const auto cacheLabel =
            native ? "library object cache " : "package object cache ";
        const auto cacheIdentity =
            native ? package.identity.substr(7) : package.identity;
        auto packagePath = (directory / ("package-" + std::to_string(i) +
                                         (native ? ".a" : ".o")))
                               .string();
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
          const auto *source = &program;
          if (package.library && !(source = package.library())) {
            std::cerr << "mettle: error[internal]: cannot specialize library "
                         "package "
                      << cacheIdentity << '\n';
            return 1;
          }
          auto dependency = mettle::backend::lower(
              *source, context, checked, options.target, options.freestanding,
              nullptr, false, false,
              {true, package.identity, false, bool(package.library)},
              &debugRequest);
          dependency->setSourceFileName(package.source);
          dependency->setTargetTriple(
              llvm::Triple(llvm::Triple::normalize(options.target)));
          if (llvm::verifyModule(*dependency, &llvm::errs())) {
            std::cerr << "mettle: error[internal]: invalid generated package "
                         "LLVM module for "
                      << package.identity << '\n';
            return 1;
          }
          auto emitDependency = [&]() {
            if (native)
              return emitUnitArchive(*dependency, options, packagePath,
                                     directory, package.identity, store,
                                     packageArtifacts);
            return mettle::backend::emitObject(*dependency, options.target,
                                               packagePath, false);
          };
          if (auto error = emitDependency()) {
            std::cerr << "mettle: error[backend]: "
                      << llvm::toString(std::move(error)) << '\n';
            return 1;
          }
          if (backend.failed) {
            std::cerr << "mettle: error[assembly]: target assembly/code "
                         "generation rejected package '"
                      << package.identity << "':\n"
                      << backend.diagnostics;
            return 1;
          }
          if (store) {
            packageArtifacts.push_back({package.key, packagePath, false});
            packagesToStore.push_back(&package);
          }
        }
        packagePaths.push_back(std::move(packagePath));
      }
      const bool reusedObject = !backend.object.path.empty();
      if (!reusedObject) {
        if (sharedBackend)
          if (auto error = backend.object.create(options.output +
                                                 ".mettle-object-%%%%%%"))
            return ioFailure("cannot stage reusable object", error);
        if (options.explain)
          std::cerr << "mettle: backend object " << options.target << '\n';
        auto generated = sharedBackend ? llvm::CloneModule(*module) : nullptr;
        auto emitRoot = [&]() {
          auto &lowered = generated ? *generated : *module;
          if (rootUnits)
            return emitUnitArchive(lowered, options, objectPath, directory,
                                   "root", store, packageArtifacts);
          return mettle::backend::emitObject(
              lowered, options.target,
              sharedBackend ? backend.object.path.str()
                            : llvm::StringRef(objectPath),
              release, options.sanitizers.contains("address"),
              options.sanitizers.contains("thread"));
        };
        if (auto error = emitRoot()) {
          std::cerr << "mettle: error[backend]: "
                    << llvm::toString(std::move(error)) << '\n';
          return 1;
        }
      }
      if (backend.failed) {
        std::cerr << "mettle: error[assembly]: target assembly/code generation "
                     "rejected the program:\n"
                  << backend.diagnostics;
        return 1;
      }
      if (sharedBackend && !rootUnits) {
        std::error_code error;
        std::filesystem::copy_file(
            backend.object.path.str().str(), objectPath,
            std::filesystem::copy_options::overwrite_existing, error);
        if (error)
          return ioFailure("cannot stage object output", error);
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
        if (target.isOSBinFormatELF() && (rootUnits || !packagePaths.empty()))
          arguments.push_back("-Wl,--start-group");
        auto addInput = [&](const std::string &path, bool archiveInput) {
          bool whole = false;
          if (archiveInput) {
            auto retained = retainedArchive(path);
            if (!retained) {
              std::cerr << "mettle: error[link]: "
                        << llvm::toString(retained.takeError()) << '\n';
              return false;
            }
            whole = *retained;
          }
          if (whole && target.isOSDarwin())
            arguments.insert(arguments.end(),
                             {"-Xlinker", "-force_load", "-Xlinker", path});
          else {
            if (whole && target.isOSBinFormatELF())
              arguments.push_back("-Wl,--whole-archive");
            arguments.push_back(path);
            if (whole && target.isOSBinFormatELF())
              arguments.push_back("-Wl,--no-whole-archive");
          }
          return true;
        };
        if (!addInput(objectPath, rootUnits))
          return 1;
        for (std::size_t index = 0; index < packagePaths.size(); ++index)
          if (!addInput(packagePaths[index],
                        packageObjects[index].identity.starts_with("native:")))
            return 1;
        arguments.push_back(runtimePath(options));
        if (target.isOSBinFormatELF() && (rootUnits || !packagePaths.empty()))
          arguments.push_back("-Wl,--end-group");
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
        if (options.emit == "executable") {
          if (target.isOSBinFormatELF())
            arguments.push_back("-Wl,--gc-sections");
          else if (target.isOSDarwin())
            arguments.push_back("-Wl,-dead_strip");
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
        // The linker's diagnostics go through the driver's own stream so a
        // caller that captures diagnostics (doctests) sees them.
        const auto linkLog = linked + ".link.log";
        const std::optional<llvm::StringRef> redirects[] = {
            std::nullopt, std::nullopt, llvm::StringRef(linkLog)};
        const int linkStatus =
            llvm::sys::ExecuteAndWait(linker, refs, std::nullopt, redirects);
        if (std::ifstream log(linkLog); log)
          if (std::ostringstream text; text << log.rdbuf())
            std::cerr << text.str();
        std::error_code ignored;
        std::filesystem::remove(linkLog, ignored);
        if (linkStatus != 0) {
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
            const auto bundle = options.output + ".dSYM";
            std::vector<llvm::StringRef> symbolArguments{tool, linked, "-o",
                                                         bundle};
            if (llvm::sys::ExecuteAndWait(tool, symbolArguments) != 0) {
              std::cerr << "mettle: error[debug]: dsymutil failed\n";
              return 1;
            }
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
  const llvm::Triple target(options.target);
  const bool debugBundle =
      options.debugInfo && target.isOSDarwin() &&
      (options.emit == "executable" || options.emit == "shared");
  if (options.emits.size() <= 1 && !debugBundle)
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
  BackendOutput backend;
  auto formats = options.emits;
  if (formats.empty())
    formats.push_back(options.emit);
  for (const auto &format : formats) {
    const auto suffix =
        formats.size() > 1 ? artifactSuffix(format, target) : "";
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
    if (int status = emitOne(selected, source, program, diagnostics, {}, store,
                             &backend))
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
