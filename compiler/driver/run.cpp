#include "driver/build_script.h"
#include "driver/cache.h"
#include "driver/execute.h"
#include "driver/inspect.h"
#include "driver/options.h"
#include "driver/output.h"
#include "expansion/macros.h"
#include "lint/lint.h"
#include "packages/plan.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "semantics/checked.h"
#include "syntax/format.h"
#include "syntax/lexer.h"
#include "syntax/migrate.h"
#include "syntax/parser.h"
#include "types/target.h"
#include "llvm/Support/MemoryBuffer.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>
#include <vector>

namespace mettle::driver {
namespace {
bool packageInput(const Options &options) {
  std::error_code error;
  return std::filesystem::is_directory(options.input, error) ||
         std::filesystem::path(options.input).filename() == "Mettle.toml";
}

// `mettle clean`: empties the build cache and, given a package, that
// package's generated build-script outputs.
int clean(const Options &options) {
  namespace fs = std::filesystem;
  Options selected = options;
  selected.noCache = false;
  auto store = openStore(selected);
  if (!store) {
    std::cerr << "mettle: error[io]: no cache directory (use --cache-dir or "
                 "METTLE_CACHE_DIR)\n";
    return 1;
  }
  std::string problem;
  auto removed = store->clear(options.dryRun, problem);
  if (!removed) {
    std::cerr << "mettle: error[io]: " << problem << '\n';
    return 1;
  }
  std::cout << "mettle: cache " << store->root().generic_string() << ": "
            << (options.dryRun ? "would remove " : "removed ")
            << removed->entries << " entries, " << removed->blobs << " blobs, "
            << removed->bytes << " bytes\n";
  if (!options.input.empty()) {
    fs::path input(options.input);
    std::error_code error;
    auto directory =
        fs::is_directory(input, error) ? input : input.parent_path();
    auto generated = directory / "target" / "mettle";
    if (fs::exists(generated, error)) {
      std::cout << "mettle: " << (options.dryRun ? "would remove " : "removed ")
                << generated.generic_string() << '\n';
      if (!options.dryRun)
        fs::remove_all(generated, error);
    }
  }
  return 0;
}

std::string lineAt(const std::string &text, std::size_t line) {
  std::size_t begin = 0;
  for (std::size_t index = 1; index < line && begin != std::string::npos;
       ++index) {
    begin = text.find('\n', begin);
    if (begin != std::string::npos)
      ++begin;
  }
  if (begin == std::string::npos || begin >= text.size())
    return "<end of file>";
  auto end = text.find('\n', begin);
  return text.substr(begin, end == std::string::npos ? end : end - begin);
}

// `mettle fmt FILE... [--check]`: rewrites each file in its canonical layout
// (atomically, only when it changes) or, with --check, lists the files that
// would change. A file that cannot be formatted safely is reported and left
// untouched. Exit status: 0 clean, 1 drift or an error.
int formatFiles(const Options &options) {
  namespace fs = std::filesystem;
  std::vector<std::string> inputs{options.input};
  inputs.insert(inputs.end(), options.moreInputs.begin(),
                options.moreInputs.end());
  int status = 0;
  for (const auto &input : inputs) {
    std::ifstream in(input, std::ios::binary);
    std::string text((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    if (!in && !in.eof()) {
      std::cerr << "mettle: error[io]: cannot read " << input << '\n';
      status = 1;
      continue;
    }
    Source source{input, text};
    Diagnostics diagnostics;
    auto formatted =
        format(source, diagnostics, [](const Source &input, Diagnostics &sink) {
          SourceId next = input.id + 1;
          return expansion::expandMacros(input, sink, [&] { return next++; });
        });
    if (!formatted) {
      diagnostics.print(source, std::cerr);
      status = 1;
      continue;
    }
    if (*formatted == text)
      continue;
    if (options.check) {
      status = 1;
      auto limit = std::min(text.size(), formatted->size());
      std::size_t at = 0;
      while (at < limit && text[at] == (*formatted)[at])
        ++at;
      // The identical prefix has the same number of lines in both texts.
      auto line =
          1 + static_cast<std::size_t>(std::count(
                  text.begin(), text.begin() + static_cast<std::ptrdiff_t>(at),
                  '\n'));
      std::cout << input << ": would be reformatted (first difference at line "
                << line << ")\n- " << lineAt(text, line) << "\n+ "
                << lineAt(*formatted, line) << '\n';
      continue;
    }
    auto temporary = fs::path(input + ".mettle-fmt.tmp");
    {
      std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
      out << *formatted;
      out.flush();
      if (!out) {
        std::cerr << "mettle: error[io]: cannot write " << input << '\n';
        status = 1;
        std::error_code ignored;
        fs::remove(temporary, ignored);
        continue;
      }
    }
    std::error_code error;
    fs::permissions(temporary, fs::status(input, error).permissions(), error);
    error.clear();
    fs::rename(temporary, input, error);
    if (error) {
      std::cerr << "mettle: error[io]: cannot replace " << input << ": "
                << error.message() << '\n';
      status = 1;
      fs::remove(temporary, error);
      continue;
    }
    std::cout << "mettle: formatted " << input << '\n';
  }
  return status;
}

// Lint levels from the command line; `include` keeps findings out of the
// standard library, dependency packages and generated code.
lint::Configuration
lintConfiguration(const Options &options, const Diagnostics &diagnostics,
                  const std::string &rootPath,
                  const std::vector<resolution::Library::Package> &mounts) {
  namespace fs = std::filesystem;
  lint::Configuration configuration;
  for (const auto &[name, rule] : options.lintLevels) {
    auto level = name == "allow"  ? lint::Level::Allow
                 : name == "warn" ? lint::Level::Warn
                                  : lint::Level::Deny;
    if (rule == "warnings") {
      configuration.defaultLevel = level;
      continue;
    }
    configuration.levels[rule] = level;
  }
  auto canonical = [](const std::string &path) {
    std::error_code error;
    return fs::weakly_canonical(path, error);
  };
  auto inside = [](const fs::path &path, const fs::path &directory) {
    auto relative = path.lexically_relative(directory);
    return !relative.empty() && *relative.begin() != "..";
  };
  auto root = canonical(rootPath);
  std::vector<fs::path> external{canonical(options.libraryDirectory)};
  for (const auto &mount : mounts)
    external.push_back(canonical(mount.source).parent_path());
  configuration.include = [&diagnostics, root, external, inside,
                           canonical](Span span) {
    if (span.source == 0)
      return true;
    if (diagnostics.isGenerated(span.source))
      return false;
    for (const auto &source : diagnostics.registeredSources()) {
      if (source.id != span.source)
        continue;
      auto path = canonical(source.path);
      return std::none_of(external.begin(), external.end(),
                          [&](const fs::path &directory) {
                            return !directory.empty() &&
                                   !inside(root, directory) &&
                                   inside(path, directory);
                          });
    }
    return true;
  };
  return configuration;
}

// Prints the findings with the front end's provenance rules; true when none is
// denied.
bool reportFindings(const std::vector<lint::Finding> &findings,
                    Diagnostics &diagnostics, const Source &source) {
  std::size_t warnings = 0, denied = 0;
  for (const auto &finding : findings) {
    if (finding.level == lint::Level::Deny) {
      diagnostics.error(finding.rule, finding.span, finding.message);
      ++denied;
    } else {
      diagnostics.warning(finding.rule, finding.span, finding.message);
      ++warnings;
    }
  }
  diagnostics.print(source, std::cerr);
  if (warnings || denied)
    std::cerr << "mettle: lint: " << warnings << " warning(s), " << denied
              << " denied finding(s)\n";
  return denied == 0;
}
} // namespace

int run(const Options &requested) {
  if (requested.command == "clean")
    return clean(requested);
  if (requested.command == "fmt")
    return formatFiles(requested);
  if (requested.command == "run" || requested.command == "test" ||
      requested.command == "bench")
    return execute(requested);
  return build(requested, nullptr);
}

int build(const Options &requested,
          std::vector<Module::TestFunction> *discovered) {
  Options options = requested;
  std::optional<packages::Store> store;
  std::string input = options.input;
  std::vector<resolution::Library::Package> dependencies;
  std::set<std::string> rootFeatures(options.features.begin(),
                                     options.features.end());
  if (packageInput(options)) {
    if (options.command != "build" && options.command != "check" &&
        options.command != "lint") {
      std::cerr << "mettle: error[package]: only 'check', 'lint' and 'build' "
                   "accept a package\n";
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
    ScriptResults generated;
    if (!outcome.plan->scripts.empty()) {
      store = openStore(options);
      if (!runBuildScripts(options, *outcome.plan, store ? &*store : nullptr,
                           generated))
        return 1;
    }
    for (const auto &mount : outcome.plan->mounts) {
      std::set<std::string> features(mount.features.begin(),
                                     mount.features.end());
      for (const auto &extra : generated.features[mount.package])
        features.insert(extra);
      dependencies.push_back({mount.name, mount.source, std::move(features)});
    }
    for (auto &module : generated.modules)
      dependencies.push_back(std::move(module));
    rootFeatures = {outcome.plan->features.begin(),
                    outcome.plan->features.end()};
    for (const auto &extra : generated.features[outcome.plan->package])
      rootFeatures.insert(extra);
    options.extraLibraries = std::move(generated.libraries);
  } else if (options.packageOptions) {
    std::cerr << "mettle: error[package]: --bin, --no-default-features, "
                 "--registry, --locked, --offline and --frozen need a package "
                 "directory or Mettle.toml\n";
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
  if (options.command == "migrate") {
    auto migration = migrate(source, diagnostics);
    if (!migration) {
      diagnostics.print(source, std::cerr);
      return 1;
    }
    for (const auto &skipped : migration->skipped) {
      auto line = 1 + std::count(source.text.begin(),
                                 source.text.begin() +
                                     static_cast<std::ptrdiff_t>(std::min(
                                         skipped.offset, source.text.size())),
                                 '\n');
      std::cerr << source.path << ':' << line
                << ": warning[migrate]: left unchanged: " << skipped.reason
                << '\n';
    }
    if (options.output.empty())
      std::cout << migration->text;
    else {
      std::ofstream out(options.output, std::ios::binary);
      out << migration->text;
      if (!out) {
        std::cerr << "mettle: error[io]: cannot write " << options.output
                  << '\n';
        return 1;
      }
    }
    return 0;
  }
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
  BuildInputs inputs(options.libraryDirectory);
  inputs.record(source);
  resolution::SourceProvider provider =
      [&](const std::string &path) -> std::optional<Source> {
    std::error_code error;
    bool exists = std::filesystem::exists(path, error);
    if (!exists && !error) {
      inputs.absent(path);
      return std::nullopt;
    }
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
    Source loaded{canonical.generic_string(), (*child)->getBuffer().str()};
    inputs.record(loaded);
    return loaded;
  };
  auto facts = targetFacts(options.target);
  expansion::Configuration configuration;
  configuration.os = facts.system == TargetSystem::Linux    ? "linux"
                     : facts.system == TargetSystem::Darwin ? "macos"
                                                            : "";
  configuration.arch = facts.arch == TargetArch::X86_64    ? "x86_64"
                       : facts.arch == TargetArch::Aarch64 ? "aarch64"
                                                           : "";
  configuration.family = configuration.os.empty() ? "" : "unix";
  configuration.endian = facts.littleEndian ? "little" : "big";
  configuration.pointerWidth = facts.pointerBits;
  configuration.targetFeatures = facts.baseline;
  configuration.features = std::move(rootFeatures);
  auto mounts = dependencies;
  resolution::Library library{options.libraryDirectory, options.freestanding,
                              std::move(dependencies), configuration};
  if (options.harness == "test")
    library.harness = resolution::Library::Harness::Test;
  else if (options.harness == "bench")
    library.harness = resolution::Library::Harness::Bench;
  auto tree = resolution::load(source, provider, diagnostics, library);
  if (tree && discovered) {
    for (const auto &entry : tree->tests)
      if (entry.path.size() > 1)
        diagnostics.error(
            "feature", entry.span,
            "tests and benchmarks inside modules are not supported yet; "
            "declare them in the root module of the source");
    *discovered = tree->tests;
    if (!diagnostics.empty())
      tree.reset();
  }
  // Executables and objects are reused when every input of the build,
  // as gathered while loading, matches a stored result.
  std::optional<std::string> cacheKey;
  // `-g` builds are never cached: paths and the Darwin dSYM are outputs that
  // the cache does not store.
  if (tree && options.command == "build" && !options.debugInfo &&
      (options.emit == "executable" || options.emit == "object")) {
    if (!store)
      store = openStore(options);
    std::error_code error;
    auto sourcePath = std::filesystem::weakly_canonical(source.path, error);
    if (store && (error || sourcePath != std::filesystem::weakly_canonical(
                                             options.output, error))) {
      cacheKey = inputs.key(options, mounts, configuration.features);
      auto found = store->materialize(*cacheKey, options.output);
      if (found == packages::Store::Lookup::Hit) {
        if (options.explain)
          std::cerr << "mettle: cache hit " << cacheKey->substr(0, 12)
                    << ": compile and link skipped\n";
        return 0;
      }
      if (options.explain)
        std::cerr << "mettle: cache "
                  << (found == packages::Store::Lookup::Corrupt
                          ? "entry corrupt, rebuilding "
                          : "miss ")
                  << cacheKey->substr(0, 12) << '\n';
    }
  }
  std::vector<lint::Finding> findings;
  pipeline::CheckedObserver observer;
  if (options.command == "lint") {
    auto configuration = lintConfiguration(options, diagnostics, source.path,
                                           mounts);
    observer = [&findings, configuration](const CheckedModule &checked) {
      findings = lint::run(checked, configuration);
    };
  }
  auto program = tree ? pipeline::compile(std::move(*tree), diagnostics,
                                          !options.freestanding, facts,
                                          observer)
                      : std::nullopt;
  if (!program) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  if (options.command == "lint")
    return reportFindings(findings, diagnostics, source) ? 0 : 1;
  if (options.command == "check")
    return 0;
  int status = emit(options, source, *program, diagnostics.registeredSources());
  if (status == 0 && cacheKey && store) {
    bool stored =
        store->put(*cacheKey, options.output, options.emit == "executable");
    if (options.explain)
      std::cerr << "mettle: cache " << (stored ? "stored " : "could not store ")
                << cacheKey->substr(0, 12) << '\n';
    for (const auto &note : store->prune(*cacheKey))
      if (options.explain)
        std::cerr << "mettle: cache " << note << '\n';
  }
  return status;
}
} // namespace mettle::driver
