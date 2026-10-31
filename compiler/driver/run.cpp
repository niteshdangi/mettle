#include "driver/build_script.h"
#include "driver/cache.h"
#include "driver/document.h"
#include "driver/execute.h"
#include "driver/inspect.h"
#include "driver/options.h"
#include "driver/output.h"
#include "driver/procedural.h"
#include "expansion/macros.h"
#include "lint/lint.h"
#include "packages/plan.h"
#include "packages/sha256.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "semantics/checked.h"
#include "syntax/format.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "types/target.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Program.h"
#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <map>
#include <set>
#include <string_view>
#include <vector>

namespace mettle::driver {
namespace {
bool packageInput(const Options &options) {
  std::error_code error;
  return std::filesystem::is_directory(options.input, error) ||
         std::filesystem::path(options.input).filename() == "Mettle.toml";
}

std::filesystem::path packageSourceStore(const Options &options) {
  namespace fs = std::filesystem;
  fs::path root;
  const char *environment = std::getenv("METTLE_CACHE_DIR");
  if (!options.cacheDir.empty())
    root = options.cacheDir;
  else if (environment && *environment)
    root = environment;
  else if (const char *xdg = std::getenv("XDG_CACHE_HOME"); xdg && *xdg)
    root = fs::path(xdg) / "mettle";
  else if (const char *home = std::getenv("HOME"); home && *home)
    root = fs::path(home) / ".cache" / "mettle";
  return root / "sources" / "git";
}

bool runGit(const std::vector<std::string> &arguments,
            const std::optional<std::string> &stdoutPath,
            std::string &problem) {
  std::vector<llvm::StringRef> refs;
  refs.reserve(arguments.size());
  for (const auto &argument : arguments)
    refs.emplace_back(argument);
  std::optional<llvm::StringRef> redirects[3] = {
      std::nullopt,
      stdoutPath ? std::optional<llvm::StringRef>(*stdoutPath) : std::nullopt,
      std::nullopt};
  std::string message;
  bool notLaunched = false;
  int status = llvm::sys::ExecuteAndWait("git", refs, std::nullopt, redirects,
                                         0, 0, &message, &notLaunched);
  if (!notLaunched && status == 0)
    return true;
  problem = notLaunched ? "cannot start git: " + message
                        : "git exited with status " + std::to_string(status);
  return false;
}

std::optional<std::string> gitOutput(
    const std::vector<std::string> &arguments,
    const std::filesystem::path &store, std::string &problem,
    bool allowEmpty = false) {
  auto output = store / ("mettle-git-output-" +
                         std::to_string(std::hash<std::string>{}(
                             arguments.back())) +
                         ".txt");
  if (!runGit(arguments, output.generic_string(), problem))
    return std::nullopt;
  std::ifstream stream(output, std::ios::binary);
  std::string text((std::istreambuf_iterator<char>(stream)),
                   std::istreambuf_iterator<char>());
  std::error_code ignored;
  std::filesystem::remove(output, ignored);
  while (!text.empty() && (text.back() == '\n' || text.back() == '\r'))
    text.pop_back();
  if (text.empty() && !allowEmpty) {
    problem = "git returned an empty revision";
    return std::nullopt;
  }
  return text;
}

std::optional<packages::GitCheckout>
checkoutGit(const Options &options, const std::string &url,
            const std::string &selector, const std::string &lockedCommit,
            bool offline, std::string &problem) {
  namespace fs = std::filesystem;
  packages::Sha256 hash;
  hash.update(url);
  auto key = hash.finish();
  auto root = packageSourceStore(options);
  auto mirror = root / "mirrors" / key;
  std::error_code error;
  fs::create_directories(mirror.parent_path(), error);
  if (error) {
    problem = "cannot create package source store: " + error.message();
    return std::nullopt;
  }
  if (!fs::exists(mirror)) {
    if (offline) {
      problem = "offline mode has no cached repository";
      return std::nullopt;
    }
    if (!runGit({"git", "clone", "--mirror", "--", url,
                 mirror.generic_string()},
                std::nullopt, problem))
      return std::nullopt;
  } else if (!offline &&
             !runGit({"git", "--git-dir=" + mirror.generic_string(), "fetch",
                      "--tags", "origin"},
                     std::nullopt, problem))
    return std::nullopt;

  std::string expression;
  if (offline && !lockedCommit.empty())
    expression = lockedCommit + "^{commit}";
  else if (selector.rfind("rev=", 0) == 0)
    expression = selector.substr(4) + "^{commit}";
  else if (selector.rfind("tag=", 0) == 0)
    expression = "refs/tags/" + selector.substr(4) + "^{commit}";
  else if (selector.rfind("branch=", 0) == 0)
    expression = "refs/heads/" + selector.substr(7) + "^{commit}";
  else
    expression = "HEAD^{commit}";
  auto commit = gitOutput(
      {"git", "--git-dir=" + mirror.generic_string(), "rev-parse", "--verify",
       "--end-of-options", expression},
      root, problem);
  if (!commit)
    return std::nullopt;

  auto checkout = root / "checkouts" / key / *commit;
  if (!fs::exists(checkout)) {
    fs::create_directories(checkout.parent_path(), error);
    if (error) {
      problem = "cannot create git checkout directory: " + error.message();
      return std::nullopt;
    }
    if (!runGit({"git", "clone", "--shared", "--no-checkout", "--",
                 mirror.generic_string(), checkout.generic_string()},
                std::nullopt, problem) ||
        !runGit({"git", "-C", checkout.generic_string(), "checkout", "--detach",
                 *commit},
                std::nullopt, problem))
      return std::nullopt;
  }
  auto head = gitOutput(
      {"git", "-C", checkout.generic_string(), "rev-parse", "--verify",
       "HEAD^{commit}"},
      root, problem);
  if (!head || *head != *commit) {
    if (head)
      problem = "cached checkout does not match commit " + *commit;
    return std::nullopt;
  }
  auto status = gitOutput(
      {"git", "-C", checkout.generic_string(), "status", "--porcelain",
       "--untracked-files=all"},
      root, problem, true);
  if (!status || !status->empty()) {
    if (status && !status->empty())
      problem = "cached checkout contains modified or untracked files";
    return std::nullopt;
  }
  auto canonical = fs::canonical(checkout, error);
  if (error) {
    problem = "cannot identify git checkout: " + error.message();
    return std::nullopt;
  }
  return packages::GitCheckout{canonical.generic_string(), *commit};
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
      return std::none_of(
          external.begin(), external.end(), [&](const fs::path &directory) {
            return !directory.empty() && !inside(root, directory) &&
                   inside(path, directory);
          });
    }
    return true;
  };
  return configuration;
}

// Prints the findings with the front end's provenance rules; true when none is
// denied.
std::string jsonString(std::string_view value) {
  static constexpr char hex[] = "0123456789abcdef";
  std::string out = "\"";
  for (unsigned char c : value) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += static_cast<char>(c);
    } else if (c < 0x20) {
      out += "\\u00";
      out += hex[c >> 4];
      out += hex[c & 15];
    } else {
      out += static_cast<char>(c);
    }
  }
  return out + '"';
}

bool reportFindings(const std::vector<lint::Finding> &findings,
                    Diagnostics &diagnostics, const Source &source, bool json) {
  std::size_t warnings = 0, denied = 0;
  for (const auto &finding : findings) {
    if (json) {
      const Source *owner = &source;
      for (const auto &candidate : diagnostics.registeredSources())
        if (candidate.id == finding.span.source) {
          owner = &candidate;
          break;
        }
      std::cout << "{\"code\":" << jsonString(finding.rule) << ",\"level\":"
                << jsonString(finding.level == lint::Level::Deny ? "deny"
                                                                 : "warn")
                << ",\"span\":{\"file\":" << jsonString(owner->path)
                << ",\"begin\":" << finding.span.begin
                << ",\"end\":" << finding.span.end
                << "},\"message\":" << jsonString(finding.message) << "}\n";
      denied += finding.level == lint::Level::Deny;
      continue;
    }
    if (finding.level == lint::Level::Deny) {
      diagnostics.error(finding.rule, finding.span, finding.message);
      ++denied;
    } else {
      diagnostics.warning(finding.rule, finding.span, finding.message);
      ++warnings;
    }
  }
  if (json)
    return denied == 0;
  diagnostics.print(source, std::cerr);
  if (warnings || denied)
    std::cerr << "mettle: lint: " << warnings << " warning(s), " << denied
              << " denied finding(s)\n";
  return denied == 0;
}
} // namespace

int run(const Options &requested) {
  if (!requested.sanitizerError.empty()) {
    std::cerr << "mettle: error[option]: " << requested.sanitizerError << '\n';
    return 2;
  }
  if (!requested.sanitizers.empty() && requested.command != "build" &&
      requested.command != "run" && requested.command != "test") {
    std::cerr << "mettle: error[option]: --sanitize is supported only by "
                 "build, run and test\n";
    return 2;
  }
  if (requested.sanitizers.contains("undefined")) {
    std::cerr << "mettle: error[feature]: --sanitize undefined is not "
                 "implemented for emitted Mettle IR; Mettle already checks "
                 "integer overflow\n";
    return 1;
  }
  if (requested.sanitizers.contains("address") &&
      requested.sanitizers.contains("thread")) {
    std::cerr << "mettle: error[feature]: --sanitize address and thread "
                 "cannot be combined\n";
    return 1;
  }
  if (!requested.sanitizers.empty() && requested.command == "build" &&
      requested.emit == "ir") {
    std::cerr << "mettle: error[feature]: --sanitize requires LLVM "
                 "instrumentation and cannot be used with --emit ir\n";
    return 1;
  }
  if (requested.command == "clean")
    return clean(requested);
  if (requested.command == "fmt")
    return formatFiles(requested);
  if (requested.command == "doc")
    return document(requested);
  if (requested.command == "run" || requested.command == "test" ||
      requested.command == "bench")
    return execute(requested);
  return build(requested, nullptr);
}

int build(const Options &requested,
          std::vector<Module::TestFunction> *discovered,
          std::vector<resolution::SourceModule> *sourceModules,
          const std::map<std::string, std::string> *sourceOverrides) {
  Options options = requested;
  std::optional<packages::Store> store;
  std::string input = options.input;
  std::vector<resolution::Library::Package> dependencies;
  std::vector<std::pair<std::string, std::string>> packageDependencies;
  std::vector<packages::Macro> macros;
  std::vector<packages::Mount> hostPackages;
  std::set<std::string> rootFeatures =
      options.packageContext
          ? options.injectedFeatures
          : std::set<std::string>(options.features.begin(),
                                  options.features.end());
  if (options.packageContext) {
    dependencies = options.injectedPackages;
    packageDependencies = options.packageDependencies;
  }
  if (packageInput(options)) {
    if (options.command != "build" && options.command != "check" &&
        options.command != "lint") {
      std::cerr << "mettle: error[package]: only 'check', 'lint' and 'build' "
                   "accept a package\n";
      return 2;
    }
    Diagnostics planning;
    packages::Request packageRequest;
    packageRequest.input = options.input;
    packageRequest.target = options.bin;
    packageRequest.features = options.features;
    packageRequest.defaultFeatures = options.defaultFeatures;
    packageRequest.locked = options.locked;
    packageRequest.offline = options.offline;
    packageRequest.registries = options.registries;
    packageRequest.gitCheckout =
        [&options](const std::string &url, const std::string &selector,
                   const std::string &lockedCommit, bool offline,
                   std::string &problem) {
          return checkoutGit(options, url, selector, lockedCommit, offline,
                             problem);
        };
    auto outcome = packages::plan(packageRequest, planning);
    if (!outcome.plan) {
      planning.print(outcome.fallback, std::cerr);
      return 1;
    }
    input = outcome.plan->root;
    macros = outcome.plan->macros;
    packageDependencies = outcome.plan->dependencies;
    hostPackages = outcome.plan->hostMounts;
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
      for (const auto &extra : generated.features[mount.identity])
        features.insert(extra);
      resolution::Library::Package dependency;
      dependency.name = mount.name;
      dependency.source = mount.source;
      dependency.module = mount.module;
      dependency.dependencies = mount.dependencies;
      dependency.features = std::move(features);
      dependencies.push_back(std::move(dependency));
    }
    for (auto &module : generated.modules)
      dependencies.push_back(std::move(module));
    rootFeatures = {outcome.plan->features.begin(),
                    outcome.plan->features.end()};
    for (const auto &extra : generated.features[outcome.plan->rootIdentity])
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
  auto sourceText = (*buffer)->getBuffer().str();
  if (!pathError && sourceOverrides)
    if (auto replacement = sourceOverrides->find(rootPath.generic_string());
        replacement != sourceOverrides->end())
      sourceText = replacement->second;
  Source source{pathError ? input : rootPath.generic_string(),
                std::move(sourceText)};
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
  BuildInputs inputs(options.libraryDirectory);
  inputs.record(source);
  std::optional<ProcedureHost> procedural;
  if (!macros.empty()) {
    if (!store)
      store = openStore(options);
    procedural.emplace(options, std::move(macros), std::move(hostPackages),
                       store ? &*store : nullptr, inputs);
    if (!procedural->prepare())
      return 1;
  }
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
    auto text = (*child)->getBuffer().str();
    if (sourceOverrides)
      if (auto replacement = sourceOverrides->find(canonical.generic_string());
          replacement != sourceOverrides->end())
        text = replacement->second;
    Source loaded{canonical.generic_string(), std::move(text)};
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
  resolution::Library library;
  library.directory = options.libraryDirectory;
  library.freestanding = options.freestanding;
  library.packages = std::move(dependencies);
  options.packageDependencies = packageDependencies;
  library.packageDependencies = std::move(packageDependencies);
  library.configuration = configuration;
  if (options.harness == "test")
    library.harness = resolution::Library::Harness::Test;
  else if (options.harness == "bench")
    library.harness = resolution::Library::Harness::Bench;
  if (procedural)
    library.procedures = &procedural->procedures();
  auto tree =
      resolution::load(source, provider, diagnostics, library, sourceModules);
  if (tree && discovered) {
    *discovered = tree->tests;
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
    auto configuration =
        lintConfiguration(options, diagnostics, source.path, mounts);
    observer = [&findings, configuration](const CheckedModule &checked) {
      findings = lint::run(checked, configuration);
    };
  }
  auto program = tree
                     ? pipeline::compile(std::move(*tree), diagnostics,
                                         !options.freestanding, facts, observer)
                     : std::nullopt;
  if (!program) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  if (options.command == "lint")
    return reportFindings(findings, diagnostics, source,
                          options.format == "json")
               ? 0
               : 1;
  if (options.command == "check")
    return 0;
  int status = emit(options, source, *program, diagnostics);
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
