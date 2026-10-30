#include "driver/inspect.h"
#include "driver/options.h"
#include "driver/output.h"
#include "packages/plan.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "types/target.h"
#include "llvm/Support/MemoryBuffer.h"
#include <filesystem>
#include <iostream>
#include <vector>

namespace mettle::driver {
namespace {
bool packageInput(const Options &options) {
  std::error_code error;
  return std::filesystem::is_directory(options.input, error) ||
         std::filesystem::path(options.input).filename() == "Mettle.toml";
}
} // namespace

int run(const Options &options) {
  std::string input = options.input;
  std::vector<resolution::Library::Package> dependencies;
  if (packageInput(options)) {
    if (options.command != "build" && options.command != "check") {
      std::cerr << "mettle: error[package]: only 'check' and 'build' accept a "
                   "package\n";
      return 2;
    }
    Diagnostics planning;
    auto outcome = packages::plan({options.input, options.bin, options.features,
                                   options.defaultFeatures, options.locked,
                                   options.offline, options.registries},
                                  planning);
    if (!outcome.plan) {
      planning.print(outcome.fallback, std::cerr);
      return 1;
    }
    input = outcome.plan->root;
    for (const auto &mount : outcome.plan->mounts)
      dependencies.push_back({mount.name, mount.source});
  } else if (options.packageOptions) {
    std::cerr << "mettle: error[package]: --bin, --features, "
                 "--no-default-features, --registry, --locked, --offline and "
                 "--frozen need a package directory or Mettle.toml\n";
    return 2;
  }
  auto buffer = llvm::MemoryBuffer::getFile(input);
  if (!buffer) {
    std::cerr << "mettle: error[io]: cannot read " << input << ": "
              << buffer.getError().message() << '\n';
    return 1;
  }
  std::error_code pathError;
  auto rootPath = std::filesystem::canonical(input, pathError);
  Source source{pathError ? input : rootPath.generic_string(),
                (*buffer)->getBuffer().str()};
  Diagnostics diagnostics;
  if (options.command == "tokens" || options.command == "syntax") {
    Module tree;
    if (options.command == "tokens")
      tree.tokens = tokenize(source, diagnostics);
    else
      tree = parse(source, diagnostics);
    inspect(tree);
    diagnostics.print(source, std::cerr);
    return diagnostics.empty() ? 0 : 1;
  }
  if (!targetFacts(options.target).initialProfile()) {
    diagnostics.error(
        "feature", {},
        "source compilation supports Darwin ARM64 and Linux x86-64 targets");
    diagnostics.print(source, std::cerr);
    return 1;
  }
  resolution::SourceProvider provider =
      [&](const std::string &path) -> std::optional<Source> {
    std::error_code error;
    bool exists = std::filesystem::exists(path, error);
    if (!exists && !error)
      return std::nullopt;
    auto child = llvm::MemoryBuffer::getFile(path);
    if (!child) {
      diagnostics.error(
          "io", {}, "cannot read " + path + ": " + child.getError().message());
      return std::nullopt;
    }
    auto canonical = std::filesystem::canonical(path, error);
    if (error) {
      diagnostics.error("io", {},
                        "cannot identify " + path + ": " + error.message());
      return std::nullopt;
    }
    return Source{canonical.generic_string(), (*child)->getBuffer().str()};
  };
  auto tree = resolution::load(source, provider, diagnostics,
                               {options.libraryDirectory, options.freestanding,
                                std::move(dependencies)});
  auto program = tree ? pipeline::compile(std::move(*tree), diagnostics,
                                          !options.freestanding,
                                          targetFacts(options.target))
                      : std::nullopt;
  if (!program) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  return options.command == "check" ? 0 : emit(options, source, *program);
}
} // namespace mettle::driver
