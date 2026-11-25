#include "driver/cache.h"
#include "diagnostics/diagnostics.h"
#include "driver/library_cache.h"
#include "packages/sha256.h"
#include "syntax/lexer.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Object/BuildID.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBuffer.h"
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <mutex>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;
std::optional<std::string> runtimeIdentity;
std::mutex identityMutex;

std::string fileStamp(const fs::path &path, packages::Store *store) {
  auto started = std::time(nullptr);
  auto stamp = store ? entryStamp(path, started) : std::nullopt;
  std::string key;
  if (stamp) {
    packages::Sha256 selector;
    selector.update("mettle-runtime-digest-1\n");
    selector.update(path.generic_string());
    selector.update("\n");
    selector.update(*stamp);
    key = "runtime-" + selector.finish();
    auto entry = store->data(key, 64);
    if (entry.status == packages::Store::Lookup::Hit &&
        entry.bytes.size() == 64)
      return path.generic_string() + ":" + entry.bytes;
  }
  std::uint64_t size = 0;
  auto hash = packages::hashFile(path, size);
  if (hash && stamp && entryStamp(path, started) == stamp)
    store->putData(key, *hash);
  return path.generic_string() + ":" + hash.value_or("unreadable");
}

std::string compilerStamp(const fs::path &path) {
  auto object = llvm::object::ObjectFile::createObjectFile(path.string());
  if (object) {
    auto identity = llvm::object::getBuildID(object->getBinary());
    if (!identity.empty())
      return "build-id:" + llvm::toHex(identity, true);
  } else {
    llvm::consumeError(object.takeError());
  }
  std::uint64_t size = 0;
  auto hash = packages::hashFile(path, size);
  return "sha256:" + hash.value_or("unreadable:" + path.generic_string());
}

std::string digest(std::string_view text) {
  packages::Sha256 hash;
  hash.update(text);
  return hash.finish();
}

// Hash lexical content with parser-significant line breaks. A source that
// does not lex cleanly is hashed whole.
std::string tokenDigest(const Source &source) {
  Diagnostics scratch;
  auto tokens = tokenize(source, scratch);
  if (!scratch.empty()) {
    packages::Sha256 hash;
    hash.update("text:");
    hash.update(source.text);
    return hash.finish();
  }
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
std::string identity(packages::Store *store);
} // namespace

std::optional<packages::Store> openStore(const Options &options,
                                         bool primeIdentity) {
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
  packages::Store store(
      root, {options.cacheLimitKib * 1024, options.cacheMaxAgeDays});
  // The toolchain's prebuilt library, when it ships one beside the compiler
  // (`METTLE_SHIPPED_STORE` overrides `<compiler dir>/../lib/mettle/store`).
  std::error_code ignored;
  fs::path shipped;
  if (const char *named = std::getenv("METTLE_SHIPPED_STORE"); named && *named)
    shipped = named;
  else
    shipped = fs::path(llvm::sys::fs::getMainExecutable(
                           "mettle",
                           reinterpret_cast<void *>(
                               reinterpret_cast<std::intptr_t>(&openStore))))
                  .parent_path() /
              ".." / "lib" / "mettle" / "store";
  shipped = fs::weakly_canonical(shipped, ignored);
  if (fs::is_directory(shipped, ignored) && shipped != root)
    store.useShipped(shipped);
  if (primeIdentity)
    identity(&store);
  return store;
}

namespace {
std::string identity(packages::Store *store) {
  static const std::string image = [] {
    std::string text = std::string("mettle ") + METTLE_VERSION + " " +
                       METTLE_RUNTIME_TARGET +
                       " sanitized=" + std::to_string(METTLE_RUNTIME_SANITIZED);
    auto self = llvm::sys::fs::getMainExecutable(
        "mettle",
        reinterpret_cast<void *>(reinterpret_cast<std::intptr_t>(&openStore)));
    text += "\n" + compilerStamp(self);
    return text;
  }();
  std::lock_guard lock(identityMutex);
  if (!runtimeIdentity)
    runtimeIdentity = image + "\n" + fileStamp(METTLE_RUNTIME_PATH, store) +
                      "\n" + fileStamp(METTLE_RUNTIME_ASAN_PATH, store) + "\n" +
                      fileStamp(METTLE_RUNTIME_TSAN_PATH, store);
  return *runtimeIdentity;
}
} // namespace

std::string compilerIdentity() { return identity(nullptr); }

void resetRuntimeIdentity() {
  std::lock_guard lock(identityMutex);
  runtimeIdentity.reset();
}

BuildInputs::BuildInputs(const std::string &libraryDirectory) {
  if (libraryDirectory.empty())
    return;
  std::error_code error;
  auto canonical = fs::weakly_canonical(libraryDirectory, error);
  libraryPrefix =
      (error ? fs::path(libraryDirectory) : canonical).generic_string() + "/";
}

void BuildInputs::record(const Source &source, const std::string &requested) {
  requests[source.path].insert(requested);
  recordDigest(source, digest(source.text));
}

void BuildInputs::record(const LibraryInputs &snapshot) {
  for (const auto &[path, contentDigest] : snapshot.digests) {
    inputs[path] = "text:" + contentDigest;
    sourceDigests[path] = contentDigest;
  }
  traceable = false;
}

void BuildInputs::include(const Source &source) {
  auto content = digest(source.text);
  inputs[source.path] = "text:" + content;
  sourceDigests[source.path] = std::move(content);
  exactPaths.insert(source.path);
}

void BuildInputs::recordShippedLibrary(const std::string &name,
                                       const std::string &key) {
  inputs["shipped-library:" + name] = key;
  shippedNames.insert(name);
}

void BuildInputs::recordDigest(const Source &source,
                               std::string contentDigest) {
  bool library =
      !libraryPrefix.empty() &&
      source.path.compare(0, libraryPrefix.size(), libraryPrefix) == 0;
  if (exactPaths.count(source.path))
    inputs[source.path] = "text:" + contentDigest;
  else
    inputs[source.path] =
        library ? "text:" + contentDigest : tokenDigest(source);
  sourceDigests[source.path] = std::move(contentDigest);
}

void BuildInputs::absent(const std::string &path) {
  inputs.emplace(path, "absent");
  absentPaths.insert(path);
}

std::optional<std::string> BuildInputs::environment(const std::string &name) {
  const char *value = std::getenv(name.c_str());
  inputs["generated:environment:" + name] =
      "text:" + digest(value ? "present:" + std::string(value) : "absent");
  packageInputsSafe = false;
  environmentNames.insert(name);
  if (!value)
    return std::nullopt;
  return std::string(value);
}

void BuildInputs::generated(const std::string &name, const std::string &text) {
  inputs["generated:" + name] = "text:" + digest(text);
  packageInputsSafe = false;
  traceable = false;
}

std::vector<std::string> BuildInputs::paths() const {
  std::vector<std::string> result;
  for (const auto &[path, requested] : requests)
    result.push_back(path);
  return result;
}

std::optional<std::string>
BuildInputs::trace(const std::string &checked) const {
  if (!traceable)
    return std::nullopt;
  std::string text;
  auto add = [&](std::string_view field) {
    text += field;
    text.push_back('\0');
  };
  add("mettle-build-trace-2");
  add(checked);
  for (const auto &[path, requested] : requests)
    for (const auto &from : requested) {
      add(exactPaths.count(path) ? "exact" : "source");
      add(from);
      add(path);
    }
  for (const auto &path : absentPaths) {
    add("absent");
    add(path);
  }
  for (const auto &name : environmentNames) {
    add("environment");
    add(name);
  }
  for (const auto &name : shippedNames) {
    add("shipped");
    add(name);
  }
  return text;
}

std::optional<BuildReplay> BuildInputs::replay(
    std::string_view trace,
    const std::function<std::optional<std::string>(const std::string &)>
        &shipped) const {
  auto next = [&]() -> std::optional<std::string> {
    auto end = trace.find('\0');
    if (end == std::string_view::npos)
      return std::nullopt;
    std::string field(trace.substr(0, end));
    trace.remove_prefix(end + 1);
    return field;
  };
  auto version = next();
  auto checked = next();
  if (!version || *version != "mettle-build-trace-2" || !checked)
    return std::nullopt;
  BuildReplay result{BuildInputs(), {}};
  result.inputs.libraryPrefix = libraryPrefix;
  if (!checked->empty()) {
    auto current = shipped(*checked);
    if (!current)
      return std::nullopt;
    result.checked = std::move(*current);
  }
  while (!trace.empty()) {
    auto kind = next();
    auto field = next();
    if (!kind || !field)
      return std::nullopt;
    std::error_code error;
    if (*kind == "source" || *kind == "exact") {
      auto path = next();
      if (!path)
        return std::nullopt;
      if (!field->empty()) {
        auto canonical = fs::canonical(*field, error);
        if (error || canonical.generic_string() != *path)
          return std::nullopt;
      }
      auto buffer = llvm::MemoryBuffer::getFile(*path);
      if (!buffer)
        return std::nullopt;
      Source source{*path, (*buffer)->getBuffer().str()};
      result.inputs.record(source, *field);
      if (*kind == "exact")
        result.inputs.include(source);
    } else if (*kind == "absent") {
      if (fs::exists(*field, error) || error)
        return std::nullopt;
      result.inputs.absent(*field);
    } else if (*kind == "environment") {
      result.inputs.environment(*field);
    } else if (*kind == "shipped") {
      auto current = shipped(*field);
      if (!current)
        return std::nullopt;
      result.inputs.recordShippedLibrary(*field, *current);
    } else {
      return std::nullopt;
    }
  }
  return result;
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
  add("package-name:" + options.packageName);
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
    const std::set<std::string> &features, const Options &options) const {
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
  return "pkg-" + hash.finish();
}
} // namespace mettle::driver
