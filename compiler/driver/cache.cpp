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
  std::error_code error;
  auto size = fs::file_size(path, error);
  auto time = fs::last_write_time(path, error);
  return path.generic_string() + ":" + (error ? "?" : std::to_string(size)) +
         ":" + (error ? "?" : std::to_string(time.time_since_epoch().count()));
}

std::string digest(const std::string &text) {
  packages::Sha256 hash;
  hash.update(text);
  return hash.finish();
}

// Hash of the lexical content of a source: comments, spaces and runs of
// newlines do not take part. A source that does not lex cleanly is hashed
// whole.
std::string tokenDigest(const Source &source) {
  Diagnostics scratch;
  auto tokens = tokenize(source, scratch);
  if (!scratch.empty())
    return digest("text:" + source.text);
  packages::Sha256 hash;
  bool newline = false;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::Space || token.kind == TokenKind::Comment)
      continue;
    if (token.kind == TokenKind::Newline) {
      if (!newline)
        hash.update("\n");
      newline = true;
      continue;
    }
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
  std::string text = std::string("mettle ") + METTLE_VERSION + " " +
                     METTLE_RUNTIME_TARGET + " sanitized=" +
                     std::to_string(METTLE_RUNTIME_SANITIZED);
  auto self = llvm::sys::fs::getMainExecutable(
      "mettle", reinterpret_cast<void *>(
                    reinterpret_cast<std::intptr_t>(&compilerIdentity)));
  text += "\n" + fileStamp(self) + "\n" + fileStamp(METTLE_RUNTIME_PATH);
  return text;
}

BuildInputs::BuildInputs(const std::string &libraryDirectory) {
  if (libraryDirectory.empty())
    return;
  std::error_code error;
  auto canonical = fs::weakly_canonical(libraryDirectory, error);
  libraryPrefix = (error ? fs::path(libraryDirectory) : canonical)
                      .generic_string() +
                  "/";
}

void BuildInputs::record(const Source &source) {
  bool library = !libraryPrefix.empty() &&
                 source.path.compare(0, libraryPrefix.size(), libraryPrefix) ==
                     0;
  inputs[source.path] =
      library ? "text:" + digest(source.text) : tokenDigest(source);
}

void BuildInputs::absent(const std::string &path) {
  inputs.emplace(path, "absent");
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
  add(options.profile);
  add(options.checks.value_or(options.profile != "release") ? "checks"
                                                              : "wrap");
  add(options.target);
  add(options.cc);
  add(options.sysroot);
  add(options.freestanding ? "freestanding" : "hosted");
  for (const auto &library : options.extraLibraries)
    add("link:" + library);
  for (const auto &feature : rootFeatures)
    add("feature:" + feature);
  for (const auto &mount : mounts) {
    add("mount:" + mount.name + "=" + mount.source);
    for (const auto &feature : mount.features)
      add("mount-feature:" + mount.name + ":" + feature);
  }
  for (const auto &[path, state] : inputs)
    add(path + "=" + state);
  return hash.finish();
}
} // namespace mettle::driver
