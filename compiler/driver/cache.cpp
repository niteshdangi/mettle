#include "driver/cache.h"
#include "diagnostics/diagnostics.h"
#include "packages/sha256.h"
#include "syntax/lexer.h"
#include "support/limits.h"
#include "llvm/Support/FileSystem.h"
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string_view>
#include <utility>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

std::string fileStamp(const fs::path &path) {
  std::error_code error;
  auto size = fs::file_size(path, error);
  auto time = fs::last_write_time(path, error);
  return path.generic_string() + ":" + (error ? "?" : std::to_string(size)) +
         ":" +
         (error ? "?"
                : std::to_string(static_cast<long long>(
                      std::chrono::duration_cast<std::chrono::nanoseconds>(
                          time.time_since_epoch())
                          .count())));
}

std::string digest(const std::string &text) {
  packages::Sha256 hash;
  hash.update(text);
  return hash.finish();
}

std::string taggedKey(const std::string &tag,
                      const std::vector<std::string> &fields) {
  packages::Sha256 hash;
  auto add = [&](const std::string &field) {
    hash.update(field);
    hash.update(std::string_view("\0", 1));
  };
  add(tag);
  for (const auto &field : fields)
    add(field);
  return hash.finish();
}

std::string tokenCacheKey(const std::string &key) { return "lex-" + key; }

std::string tokenStreamDigest(const std::vector<Token> &tokens) {
  packages::Sha256 hash;
  for (const auto &token : tokens) {
    auto kind = std::to_string(static_cast<unsigned>(token.kind));
    auto size = std::to_string(token.text.size());
    hash.update(kind);
    hash.update(":");
    hash.update(size);
    hash.update(":");
    hash.update(token.text);
    hash.update(std::string_view("\0", 1));
  }
  return hash.finish();
}

std::string tokenRecordDigest(const std::vector<Token> &tokens) {
  packages::Sha256 hash;
  for (const auto &token : tokens) {
    auto begin = std::to_string(token.span.begin);
    auto end = std::to_string(token.span.end);
    hash.update(begin);
    hash.update(":");
    hash.update(end);
    hash.update(":");
    hash.update(std::to_string(static_cast<unsigned>(token.kind)));
    hash.update(":");
    hash.update(std::to_string(token.text.size()));
    hash.update(":");
    hash.update(token.text);
    hash.update(std::string_view("\0", 1));
  }
  return hash.finish();
}

std::string serializeTokens(const std::vector<Token> &tokens,
                            const std::string &tokenHash,
                            const std::string &recordHash) {
  std::string result =
      "mettle-lexed-tokens-1\n" + tokenHash + "\n" + recordHash + "\n";
  for (const auto &token : tokens) {
    result += std::to_string(static_cast<unsigned>(token.kind)) + " " +
              std::to_string(token.span.begin) + " " +
              std::to_string(token.span.end) + " " +
              std::to_string(token.text.size()) + "\n";
    result += token.text;
    result.push_back('\n');
  }
  return result;
}

bool readNumber(std::string_view line, std::size_t &position,
                std::size_t &value, char delimiter) {
  auto end = line.find(delimiter, position);
  if (end == std::string_view::npos)
    return false;
  auto parsed = std::from_chars(line.data() + position, line.data() + end,
                                value);
  if (parsed.ec != std::errc{} || parsed.ptr != line.data() + end)
    return false;
  position = end + 1;
  return true;
}

bool readFinalNumber(std::string_view line, std::size_t &position,
                     std::size_t &value) {
  auto parsed = std::from_chars(line.data() + position,
                                line.data() + line.size(), value);
  if (parsed.ec != std::errc{} || parsed.ptr != line.data() + line.size())
    return false;
  position = line.size();
  return true;
}

std::optional<std::vector<Token>>
deserializeTokens(const std::string &record, const Source &source,
                  const std::string &expectedTokenHash,
                  const std::string &expectedRecordHash) {
  static constexpr std::string_view header = "mettle-lexed-tokens-1\n";
  if (record.compare(0, header.size(), header) != 0)
    return std::nullopt;
  auto tokenHashEnd = record.find('\n', header.size());
  auto recordHashEnd =
      tokenHashEnd == std::string::npos
          ? std::string::npos
          : record.find('\n', tokenHashEnd + 1);
  if (tokenHashEnd == std::string::npos ||
      recordHashEnd == std::string::npos ||
      record.substr(header.size(), tokenHashEnd - header.size()) !=
          expectedTokenHash ||
      record.substr(tokenHashEnd + 1,
                    recordHashEnd - tokenHashEnd - 1) != expectedRecordHash)
    return std::nullopt;

  std::vector<Token> tokens;
  auto position = recordHashEnd + 1;
  while (position < record.size()) {
    auto lineEnd = record.find('\n', position);
    if (lineEnd == std::string::npos)
      return std::nullopt;
    std::string_view line(record.data() + position, lineEnd - position);
    std::size_t field = 0, kind = 0, begin = 0, end = 0, size = 0;
    if (!readNumber(line, field, kind, ' ') ||
        !readNumber(line, field, begin, ' ') ||
        !readNumber(line, field, end, ' ') ||
        !readFinalNumber(line, field, size) || field != line.size() ||
        kind > static_cast<std::size_t>(TokenKind::FormatClose) ||
        begin > end || end > source.text.size() ||
        size > record.size() - lineEnd - 1 ||
        tokens.size() >= limits::tokens)
      return std::nullopt;
    position = lineEnd + 1;
    Token token{static_cast<TokenKind>(kind), {begin, end, source.id},
                record.substr(position, size)};
    position += size;
    if (position >= record.size() || record[position++] != '\n')
      return std::nullopt;
    tokens.push_back(std::move(token));
  }
  if (tokens.empty() || tokens.back().kind != TokenKind::End ||
      tokenStreamDigest(tokens) != expectedTokenHash ||
      tokenRecordDigest(tokens) != expectedRecordHash)
    return std::nullopt;
  return tokens;
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
  // A run of line breaks counts once, and only between two tokens.
  bool started = false, newline = false;
  for (const auto &token : tokens) {
    if (token.kind == TokenKind::Space || token.kind == TokenKind::Comment)
      continue;
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
  std::string text = std::string("mettle ") + METTLE_VERSION + " " +
                     METTLE_RUNTIME_TARGET +
                     " sanitized=" + std::to_string(METTLE_RUNTIME_SANITIZED);
  auto self = llvm::sys::fs::getMainExecutable(
      "mettle", reinterpret_cast<void *>(
                    reinterpret_cast<std::intptr_t>(&compilerIdentity)));
  text += "\n" + fileStamp(self) + "\n" + fileStamp(METTLE_RUNTIME_PATH);
  return text;
}

std::vector<Token> cachedTokens(packages::Store &store, const Source &source,
                                Diagnostics &diagnostics, bool explain) {
  auto compiler = compilerIdentity();
  auto rawHash = digest(source.text);
  auto index = tokenCacheKey(
      taggedKey("mettle-lexed-module-index-1", {compiler, source.path}));
  if (auto entry = store.text(index)) {
    static constexpr std::string_view header = "mettle-lexed-index-1\n";
    if (entry->compare(0, header.size(), header) == 0) {
      auto rawEnd = entry->find('\n', header.size());
      auto tokenEnd = rawEnd == std::string::npos
                          ? std::string::npos
                          : entry->find('\n', rawEnd + 1);
      auto recordEnd = tokenEnd == std::string::npos
                           ? std::string::npos
                           : entry->find('\n', tokenEnd + 1);
      if (rawEnd != std::string::npos && tokenEnd != std::string::npos &&
          recordEnd != std::string::npos &&
          entry->substr(header.size(), rawEnd - header.size()) == rawHash) {
        auto tokenHash = entry->substr(rawEnd + 1, tokenEnd - rawEnd - 1);
        auto recordHash =
            entry->substr(tokenEnd + 1, recordEnd - tokenEnd - 1);
        auto artifact = tokenCacheKey(taggedKey(
            "mettle-lexed-module-1",
            {compiler, rawHash, tokenHash, recordHash}));
        if (auto record = store.text(artifact))
          if (auto tokens = deserializeTokens(*record, source, tokenHash,
                                              recordHash)) {
            if (explain)
              std::cerr << "mettle: module cache hit " << source.path << '\n';
            return std::move(*tokens);
          }
      }
    }
  }

  auto tokens = tokenize(source, diagnostics);
  if (diagnostics.empty()) {
    auto tokenHash = tokenStreamDigest(tokens);
    auto recordHash = tokenRecordDigest(tokens);
    auto artifact = tokenCacheKey(taggedKey(
        "mettle-lexed-module-1", {compiler, rawHash, tokenHash, recordHash}));
    auto budget = store.limits().bytes;
    if (source.text.size() <= budget &&
        tokens.size() <= (budget - source.text.size()) / 100) {
      auto record = serializeTokens(tokens, tokenHash, recordHash);
      auto indexRecord = "mettle-lexed-index-1\n" + rawHash + "\n" +
                         tokenHash + "\n" + recordHash + "\n";
      if (record.size() <= budget &&
          indexRecord.size() <= budget - record.size()) {
        store.putText(artifact, record);
        store.prune(artifact);
        store.putText(index, indexRecord);
        store.prune(artifact);
      }
    }
  }
  if (explain)
    std::cerr << "mettle: module cache "
              << (diagnostics.empty() ? "miss " : "unavailable ")
              << source.path << '\n';
  return tokens;
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
}

void BuildInputs::absent(const std::string &path) {
  inputs.emplace(path, "absent");
}

void BuildInputs::generated(const std::string &name, const std::string &text) {
  inputs["generated:" + name] = "text:" + digest(text);
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
} // namespace mettle::driver
