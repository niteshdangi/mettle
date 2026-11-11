#include "driver/library_cache.h"
#include "packages/sha256.h"
#include "support/limits.h"
#include <algorithm>
#include <fstream>

namespace mettle::driver {
std::optional<LibraryInputs>
collectLibraryInputs(const std::filesystem::path &directory,
                     const LibraryCacheConfiguration &configuration,
                     std::string &problem) {
  namespace fs = std::filesystem;
  problem.clear();
  auto fail = [&](const std::string &message) -> std::optional<LibraryInputs> {
    problem = "cannot snapshot checked library: " + message;
    return std::nullopt;
  };
  if (configuration.compiler.empty() || configuration.identity.empty())
    return fail("compiler and package identities are required");
  std::error_code error;
  auto root = fs::canonical(directory, error);
  if (error || !fs::is_directory(root, error))
    return fail(directory.string() + " is not a readable directory");
  std::vector<fs::path> paths;
  for (fs::recursive_directory_iterator item(root, error), end;
       !error && item != end; item.increment(error)) {
    paths.push_back(item->path());
    if (paths.size() > limits::tokens)
      return fail("source inventory exceeds the compiler count limit");
  }
  if (error)
    return fail("directory traversal failed: " + error.message());
  std::sort(paths.begin(), paths.end());
  packages::Sha256 hash;
  auto field = [&](std::string_view value) {
    char length[8];
    auto size = static_cast<std::uint64_t>(value.size());
    for (unsigned i = 0; i < 8; ++i)
      length[i] = static_cast<char>(size >> (i * 8));
    hash.update({length, sizeof(length)});
    hash.update(value);
  };
  auto strings = [&](const std::set<std::string> &values) {
    field(std::to_string(values.size()));
    for (const auto &value : values)
      field(value);
  };
  field("mettle-checked-library-inputs-1");
  field(configuration.compiler);
  field(configuration.identity);
  field(root.generic_string());
  field(configuration.target);
  field(configuration.profile);
  field(configuration.cc);
  field(configuration.sysroot);
  field(configuration.checks ? "checks" : "wrap");
  field(configuration.freestanding ? "freestanding" : "hosted");
  field(configuration.debugInfo ? "debug-info" : "no-debug-info");
  strings(configuration.features);
  strings(configuration.targetFeatures);
  strings(configuration.sanitizers);
  field(std::to_string(configuration.dependencies.size()));
  for (const auto &[identity, key] : configuration.dependencies) {
    field(identity);
    field(key);
  }
  LibraryInputs inputs;
  for (const auto &path : paths) {
    auto status = fs::symlink_status(path, error);
    if (error)
      return fail("cannot inspect " + path.string() + ": " + error.message());
    if (!fs::is_directory(status) && !fs::is_symlink(status) &&
        path.extension() != ".mt")
      continue;
    auto canonical = fs::canonical(path, error);
    if (error)
      return fail("cannot identify " + path.string() + ": " + error.message());
    auto relative = canonical.lexically_relative(root);
    if (relative.empty() || *relative.begin() == "..")
      return fail("source link escapes the declared library root: " +
                  path.string());
    field(path.lexically_relative(root).generic_string());
    field(canonical.generic_string());
    if (fs::is_directory(canonical, error)) {
      field("directory");
      continue;
    }
    if (error || !fs::is_regular_file(canonical, error))
      return fail("unsupported source entry: " + path.string());
    if (path.extension() != ".mt") {
      field("non-source-link");
      continue;
    }
    auto size = fs::file_size(canonical, error);
    if (error || size > limits::sourceBytes)
      return fail("source size is unavailable or exceeds the compiler limit: " +
                  path.string());
    std::ifstream stream(canonical, std::ios::binary);
    std::string text(static_cast<std::size_t>(size), '\0');
    stream.read(text.data(), static_cast<std::streamsize>(text.size()));
    if (!stream || stream.peek() != std::char_traits<char>::eof())
      return fail("source changed or could not be read: " + path.string());
    field("source");
    field(text);
    auto name = canonical.generic_string();
    auto found = inputs.sources.find(name);
    if (found != inputs.sources.end() && found->second.text != text)
      return fail("source changed during snapshot: " + path.string());
    inputs.sources.insert_or_assign(name,
                                    Source{name, std::move(text), SourceId{0}});
  }
  if (inputs.sources.empty())
    return fail("no library sources");
  inputs.key = hash.finish();
  return inputs;
}
} // namespace mettle::driver
