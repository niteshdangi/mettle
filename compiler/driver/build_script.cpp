#include "driver/build_script.h"
#include "driver/cache.h"
#include "driver/observe.h"
#include "packages/sha256.h"
#include "llvm/Support/Program.h"
#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

bool allOf(const std::string &name, bool (*accept)(char)) {
  return !name.empty() && std::all_of(name.begin(), name.end(), accept);
}

bool lower(char c) { return c >= 'a' && c <= 'z'; }
bool digit(char c) { return c >= '0' && c <= '9'; }
bool upper(char c) { return c >= 'A' && c <= 'Z'; }

bool identifier(const std::string &name) {
  return allOf(name, [](char c) { return lower(c) || digit(c) || c == '_'; }) &&
         lower(name[0]);
}

bool featureName(const std::string &name) {
  return allOf(name,
               [](char c) {
                 return lower(c) || digit(c) || c == '_' || c == '-';
               }) &&
         lower(name[0]);
}

bool libraryName(const std::string &name) {
  return allOf(name,
               [](char c) {
                 return lower(c) || upper(c) || digit(c) || c == '_' ||
                        c == '+' || c == '.' || c == '-';
               }) &&
         name[0] != '-';
}

bool variableName(const std::string &name) {
  return allOf(name,
               [](char c) {
                 return lower(c) || upper(c) || digit(c) || c == '_';
               }) &&
         !digit(name[0]);
}

// What a script declared on stdout.
struct Declared {
  // Module name and file relative to the out directory.
  std::vector<std::pair<std::string, std::string>> modules;
  std::vector<std::string> features, libraries, files, variables;
  bool reproducible = false;
};

// A reproducible script's recorded result: its declarations, the state of
// every declared input when it ran, and the content of everything it wrote.
struct Contract {
  Declared declared;
  Files inputs, variables, outputs;
};

std::optional<std::string> parseDeclarations(const std::string &text,
                                             Declared &declared) {
  std::istringstream lines(text);
  for (std::string line; std::getline(lines, line);) {
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    if (line.rfind("mettle:", 0) != 0)
      continue;
    auto body = line.substr(7);
    auto split = body.find('=');
    auto key = body.substr(0, split);
    auto value = split == std::string::npos ? "" : body.substr(split + 1);
    if (key == "reproducible" && split == std::string::npos)
      declared.reproducible = true;
    else if (key == "rerun-if-changed" && !value.empty())
      declared.files.push_back(value);
    else if (key == "rerun-if-env-changed" && variableName(value))
      declared.variables.push_back(value);
    else if (key == "feature" && featureName(value))
      declared.features.push_back(value);
    else if (key == "link-lib" && libraryName(value))
      declared.libraries.push_back(value);
    else if (key == "module") {
      auto equals = value.find('=');
      auto name = value.substr(0, equals);
      auto file = equals == std::string::npos ? "" : value.substr(equals + 1);
      auto normal = fs::path(file).lexically_normal();
      if (!identifier(name) || file.empty() || normal.is_absolute() ||
          *normal.begin() == "..")
        return "invalid declaration '" + line +
               "' (module=NAME=FILE needs a lowercase name and a file inside "
               "the out directory)";
      declared.modules.emplace_back(name, normal.generic_string());
    } else
      return "unknown or malformed declaration '" + line + "'";
  }
  return std::nullopt;
}

std::string serialize(const Contract &contract) {
  std::string text = "reproducible\n";
  for (const auto &[state, path] : contract.inputs)
    text += "input " + state + " " + path + "\n";
  for (const auto &[state, name] : contract.variables)
    text += "env " + state + " " + name + "\n";
  for (const auto &[hash, path] : contract.outputs)
    text += "out " + hash + " " + path + "\n";
  for (const auto &[name, file] : contract.declared.modules)
    text += "module " + name + " " + file + "\n";
  for (const auto &feature : contract.declared.features)
    text += "feature " + feature + "\n";
  for (const auto &library : contract.declared.libraries)
    text += "link-lib " + library + "\n";
  return text;
}

std::optional<Contract> parseContract(const std::string &text) {
  Contract contract;
  std::istringstream lines(text);
  std::string line;
  if (!std::getline(lines, line) || line != "reproducible")
    return std::nullopt;
  contract.declared.reproducible = true;
  while (std::getline(lines, line)) {
    auto first = line.find(' ');
    if (first == std::string::npos)
      return std::nullopt;
    auto kind = line.substr(0, first);
    auto rest = line.substr(first + 1);
    auto second = rest.find(' ');
    if (kind == "feature")
      contract.declared.features.push_back(rest);
    else if (kind == "link-lib")
      contract.declared.libraries.push_back(rest);
    else if (second == std::string::npos)
      return std::nullopt;
    else {
      auto head = rest.substr(0, second), tail = rest.substr(second + 1);
      if (kind == "input")
        contract.inputs.emplace_back(head, tail);
      else if (kind == "env")
        contract.variables.emplace_back(head, tail);
      else if (kind == "out")
        contract.outputs.emplace_back(head, tail);
      else if (kind == "module")
        contract.declared.modules.emplace_back(head, tail);
      else
        return std::nullopt;
    }
  }
  return contract;
}

// Why a recorded result no longer holds, or nothing when it does.
std::optional<std::string> stale(const Contract &contract,
                                 const fs::path &directory,
                                 const fs::path &outDirectory) {
  for (const auto &[state, path] : contract.inputs)
    if (inputState(directory / path) != state)
      return "input '" + path + "' changed";
  for (const auto &[state, name] : contract.variables)
    if (variableState(name) != state)
      return "environment variable " + name + " changed";
  Files expected;
  for (const auto &[hash, path] : contract.outputs)
    expected.emplace_back(path, hash);
  std::sort(expected.begin(), expected.end());
  if (filesBelow(outDirectory) != expected)
    return "generated files are missing or were modified";
  return std::nullopt;
}

class Runner {
public:
  Runner(const Options &options, const packages::Plan &plan,
         packages::Store *store, ScriptResults &results)
      : options(options), plan(plan), store(store), results(results) {
    for (const auto &mount : plan.mounts)
      taken.insert(mount.name);
  }

  bool run() {
    for (const auto &script : plan.scripts)
      if (!one(script))
        return false;
    return true;
  }

private:
  const Options &options;
  const packages::Plan &plan;
  packages::Store *store;
  ScriptResults &results;
  std::set<std::string> taken;

  bool fail(const packages::BuildScript &script, const std::string &message) {
    std::cerr << "mettle: error[build]: build script of '" << script.package
              << "' " << script.version << ": " << message << '\n';
    return false;
  }

  void explain(const packages::BuildScript &script,
               const std::string &message) {
    if (options.explain)
      std::cerr << "mettle: build script of '" << script.package
                << "': " << message << '\n';
  }

  std::set<std::string> featuresOf(const packages::BuildScript &script) const {
    if (script.root)
      return {plan.features.begin(), plan.features.end()};
    for (const auto &mount : plan.mounts)
      if (mount.package == script.package)
        return {mount.features.begin(), mount.features.end()};
    return {};
  }

  bool apply(const packages::BuildScript &script, const Declared &declared,
             const fs::path &outDirectory,
             const std::set<std::string> &features) {
    for (const auto &[name, file] : declared.modules) {
      std::error_code error;
      auto source = fs::canonical(outDirectory / file, error);
      if (error || !fs::is_regular_file(source))
        return fail(script, "module '" + name +
                                "' names a file the script "
                                "did not generate: " +
                                file);
      if (!taken.insert(name).second)
        return fail(script,
                    "module '" + name + "' collides with another root module");
      results.modules.push_back({name, source.generic_string(), features});
    }
    results.features[script.package].insert(declared.features.begin(),
                                            declared.features.end());
    for (const auto &library : declared.libraries)
      if (std::find(results.libraries.begin(), results.libraries.end(),
                    library) == results.libraries.end())
        results.libraries.push_back(library);
    return true;
  }

  bool one(const packages::BuildScript &script) {
    fs::path directory = script.directory;
    fs::path work = directory / "target" / "mettle";
    fs::path outDirectory = work / "out";
    fs::path binary = work / "build-script";
    std::error_code error;
    fs::create_directories(work, error);
    if (error)
      return fail(script, "cannot create " + work.generic_string() + ": " +
                              error.message());
    // Scripts are compiled for the host whatever the build target is.
    Options host;
    host.command = "build";
    host.input = script.source;
    host.output = binary.generic_string();
    host.cc = options.cc;
    host.sysroot = options.sysroot;
    host.libraryDirectory = options.libraryDirectory;
    host.cacheDir = options.cacheDir;
    host.cacheLimitKib = options.cacheLimitKib;
    host.cacheMaxAgeDays = options.cacheMaxAgeDays;
    host.noCache = options.noCache;
    host.explain = options.explain;
    if (driver::run(host) != 0)
      return fail(script, "compiling the script failed");

    auto features = featuresOf(script);
    std::string joined;
    for (const auto &feature : features)
      joined += (joined.empty() ? "" : ",") + feature;
    std::uint64_t size = 0;
    auto binaryHash = packages::hashFile(binary, size);
    if (!binaryHash)
      return fail(script, "cannot read the compiled script");
    packages::Sha256 identity;
    for (const auto &field :
         {std::string("mettle-script-key-1"), compilerIdentity(),
          script.package, script.version, script.directory, *binaryHash,
          options.target, options.profile, joined}) {
      identity.update(field);
      identity.update(std::string_view("\0", 1));
    }
    auto key = identity.finish();

    if (!store)
      explain(script, "rerun (caching is off)");
    else if (auto text = store->text(key)) {
      auto contract = parseContract(*text);
      auto reason = contract ? stale(*contract, directory, outDirectory)
                             : std::optional<std::string>("unreadable record");
      if (!reason) {
        explain(script, "reused (declared reproducible; inputs unchanged)");
        return apply(script, contract->declared, outDirectory, features);
      }
      explain(script, "rerun (" + *reason + ")");
    } else
      explain(script, "rerun (no reproducible record)");

    fs::remove_all(outDirectory, error);
    fs::create_directories(outDirectory, error);
    if (error)
      return fail(script, "cannot create " + outDirectory.generic_string());
    auto log = (work / "build-script.stdout").generic_string();
    for (const auto &[name, value] :
         std::vector<std::pair<const char *, std::string>>{
             {"METTLE_OUT_DIR", outDirectory.generic_string()},
             {"METTLE_PACKAGE_DIR", script.directory},
             {"METTLE_PACKAGE_NAME", script.package},
             {"METTLE_PACKAGE_VERSION", script.version},
             {"METTLE_TARGET", options.target},
             {"METTLE_PROFILE", options.profile},
             {"METTLE_FEATURES", joined}})
      setenv(name, value.c_str(), 1);
    auto previous = fs::current_path(error);
    fs::current_path(directory, error);
    if (error)
      return fail(script, "cannot enter " + script.directory);
    auto program = binary.generic_string();
    std::vector<llvm::StringRef> arguments{program};
    std::optional<llvm::StringRef> redirects[3] = {
        std::nullopt, llvm::StringRef(log), std::nullopt};
    std::string message;
    bool notLaunched = false;
    int status =
        llvm::sys::ExecuteAndWait(program, arguments, std::nullopt, redirects,
                                  0, 0, &message, &notLaunched);
    std::error_code restored;
    fs::current_path(previous, restored);
    if (notLaunched || status != 0)
      return fail(script, notLaunched
                              ? "cannot run the script: " + message
                              : "exited with status " + std::to_string(status));
    std::ifstream stream(log, std::ios::binary);
    std::ostringstream output;
    output << stream.rdbuf();
    Declared declared;
    if (auto problem = parseDeclarations(output.str(), declared))
      return fail(script, *problem);
    if (!apply(script, declared, outDirectory, features))
      return false;
    if (declared.reproducible && store) {
      Contract contract;
      contract.declared = declared;
      for (const auto &path : declared.files)
        contract.inputs.emplace_back(inputState(directory / path), path);
      for (const auto &name : declared.variables)
        contract.variables.emplace_back(variableState(name), name);
      for (const auto &[path, hash] : filesBelow(outDirectory))
        contract.outputs.emplace_back(hash, path);
      store->putText(key, serialize(contract));
    }
    return true;
  }
};
} // namespace

bool runBuildScripts(const Options &options, const packages::Plan &plan,
                     packages::Store *store, ScriptResults &results) {
  return Runner(options, plan, store, results).run();
}
} // namespace mettle::driver
