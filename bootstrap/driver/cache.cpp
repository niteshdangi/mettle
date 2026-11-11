#include "driver/cache.h"
#include "diagnostics/diagnostics.h"
#include "packages/sha256.h"
#include "syntax/lexer.h"
#include "llvm/Support/FileSystem.h"
#include <cstdint>
#include <cstdlib>
#include <filesystem>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

std::string fileStamp(const fs::path &path) {
  std::uint64_t size = 0;
  auto hash = packages::hashFile(path, size);
  return path.generic_string() + ":" + hash.value_or("unreadable");
}

std::string digest(const std::string &text) {
  packages::Sha256 hash;
  hash.update(text);
  return hash.finish();
}

// Hash lexical content with parser-significant line breaks. A source that
// does not lex cleanly is hashed whole.
std::string tokenDigest(const Source &source) {
  Diagnostics scratch;
  auto tokens = tokenize(source, scratch);
  if (!scratch.empty())
    return digest("text:" + source.text);
  packages::Sha256 hash;
  // A run of line breaks counts once, and only between two tokens.
  bool started = false, newline = false;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::Space)
      continue;
    if (token.kind == TokenKind::Comment) {
      if (token.text.find_first_of("\r\n") != std::string::npos)
        newline = started;
      continue;
    }
    if (token.kind == TokenKind::Newline) {
      newline = started;
      continue;
    }
    if (token.kind == TokenKind::End)
      break;
    if (newline)
      hash.update("\n");
    started = true;
    newline = false;
    hash.update(std::to_string(static_cast<int>(token.kind)));
    hash.update(std::string_view(":", 1));
    hash.update(token.text);
    hash.update(std::string_view("\0", 1));
  }
  return "tokens:" + hash.finish();
}
} // namespace

std::optional<packages::Store> openStore(const Options &options) {
  if (options.noCache)
    return std::nullopt;
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
  else
    return std::nullopt;
  std::error_code error;
  root = fs::absolute(root, error);
  if (error)
    return std::nullopt;
  return packages::Store(
      root, {options.cacheLimitKib * 1024, options.cacheMaxAgeDays});
}

std::string compilerIdentity() {
  // One tool identity per compiler process, shared by nested host builds and
  // package keys. Hashing the executable again for each dependency is
  // redundant.
  static const std::string identity = [] {
    std::string text = std::string("mettle ") + METTLE_VERSION + " " +
                       METTLE_RUNTIME_TARGET +
                       " sanitized=" + std::to_string(METTLE_RUNTIME_SANITIZED);
    auto self = llvm::sys::fs::getMainExecutable(
        "mettle", reinterpret_cast<void *>(
                      reinterpret_cast<std::intptr_t>(&compilerIdentity)));
    text += "\n" + fileStamp(self) + "\n" + fileStamp(METTLE_RUNTIME_PATH);
    text += "\n" + fileStamp(METTLE_RUNTIME_ASAN_PATH);
    text += "\n" + fileStamp(METTLE_RUNTIME_TSAN_PATH);
    return text;
  }();
  return identity;
}

BuildInputs::BuildInputs(const std::string &libraryDirectory) {
  if (libraryDirectory.empty())
    return;
  std::error_code error;
  auto canonical = fs::weakly_canonical(libraryDirectory, error);
  libraryPrefix =
      (error ? fs::path(libraryDirectory) : canonical).generic_string() + "/";
}

void BuildInputs::record(const Source &source) {
  bool library =
      !libraryPrefix.empty() &&
      source.path.compare(0, libraryPrefix.size(), libraryPrefix) == 0;
  inputs[source.path] =
      library ? "text:" + digest(source.text) : tokenDigest(source);
  sourceDigests[source.path] = digest(source.text);
}

void BuildInputs::absent(const std::string &path) {
  inputs.emplace(path, "absent");
  absentPaths.insert(path);
}

void BuildInputs::generated(const std::string &name, const std::string &text) {
  inputs["generated:" + name] = "text:" + digest(text);
  packageInputsSafe = false;
}

std::string
BuildInputs::key(const Options &options,
                 const std::vector<resolution::Library::Package> &mounts,
                 const std::set<std::string> &rootFeatures) const {
  packages::Sha256 hash;
  auto add = [&](const std::string &field) {
    hash.update(field);
    hash.update(std::string_view("\0", 1));
  };
  add("mettle-build-key-1");
  add(compilerIdentity());
  add(options.emit);
  add(options.library ? "library" : "executable");
  add(options.profile);
  add(options.checks.value_or(options.profile != "release") ? "checks"
                                                            : "wrap");
  add(options.target);
  add(options.cc);
  add(options.sysroot);
  add(options.freestanding ? "freestanding" : "hosted");
  add(options.packageContext ? "package-context" : "ordinary-context");
  add("harness:" + options.harness);
  for (const auto &sanitizer : options.sanitizers)
    add("sanitize:" + sanitizer);
  // The linker embeds the output's file name (code-signature identifier).
  add("name:" + fs::path(options.output).filename().string());
  for (const auto &library : options.extraLibraries)
    add("link:" + library);
  for (const auto &feature : rootFeatures)
    add("feature:" + feature);
  for (const auto &mount : mounts) {
    add("mount:" + mount.name + "=" + mount.source);
    add("mount-module:" + mount.module);
    for (const auto &feature : mount.features)
      add("mount-feature:" + mount.name + ":" + feature);
    for (const auto &[name, module] : mount.dependencies)
      add("mount-dependency:" + mount.module + ":" + name + "=" + module);
  }
  for (const auto &[name, module] : options.packageDependencies)
    add("package-dependency:" + name + "=" + module);
  for (const auto &[path, state] : inputs)
    add(path + "=" + state);
  return hash.finish();
}

std::optional<std::string> BuildInputs::packageObjectKey(
    const std::string &identity, const std::vector<std::string> &sources,
    const std::vector<std::pair<std::string, std::string>> &dependencies,
    const std::set<std::string> &features, const Options &options,
    const std::string &nativePartition) const {
  if (!packageInputsSafe || identity.empty() || sources.empty())
    return std::nullopt;
  packages::Sha256 hash;
  auto add = [&](const std::string &field) {
    hash.update(field);
    hash.update(std::string_view("\0", 1));
  };
  add("mettle-package-object-key-2");
  add(identity);
  add(compilerIdentity());
  add(options.target);
  add(options.profile);
  add(options.checks.value_or(options.profile != "release") ? "checks"
                                                            : "wrap");
  add(options.freestanding ? "freestanding" : "hosted");
  add(options.cc);
  add(options.sysroot);
  add(options.packageContext ? "package-context" : "ordinary-context");
  add(options.harness);
  add(options.debugInfo ? "debug-info" : "no-debug-info");
  for (const auto &library : options.extraLibraries)
    add("link:" + library);
  for (const auto &sanitizer : options.sanitizers)
    add("sanitize:" + sanitizer);
  for (const auto &feature : features)
    add("feature:" + feature);
  std::set<std::string> uniqueSources(sources.begin(), sources.end());
  for (const auto &path : uniqueSources) {
    auto digest = sourceDigests.find(path);
    if (digest == sourceDigests.end())
      return std::nullopt;
    add("source:" + path + "=" + digest->second);
  }
  for (const auto &[path, digest] : sourceDigests)
    if (!libraryPrefix.empty() &&
        path.compare(0, libraryPrefix.size(), libraryPrefix) == 0)
      add("library:" + path + "=" + digest);
  // A probed-absent file appearing could change any package's resolution, so
  // every probe participates in every package key.
  for (const auto &path : absentPaths)
    add("absent:" + path);
  for (const auto &[alias, dependency] : dependencies)
    add("dependency:" + alias + "=" + dependency);
  add("native-partition:" + nativePartition);
  return "pkg-" + hash.finish();
}
} // namespace mettle::driver
