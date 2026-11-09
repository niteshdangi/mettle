#include "driver/observe.h"
#include "packages/sha256.h"
#include "packages/store.h"
#include <algorithm>
#include <cstdint>
#include <cstdlib>

namespace mettle::driver {
namespace fs = std::filesystem;

std::string digest(const std::string &text) {
  packages::Sha256 hash;
  hash.update(text);
  return hash.finish();
}

Files filesBelow(const fs::path &directory) {
  Files found;
  std::error_code error;
  for (fs::recursive_directory_iterator it(directory, error), end;
       !error && it != end; it.increment(error))
    if (it->is_regular_file(error)) {
      std::uint64_t size = 0;
      found.emplace_back(
          it->path().lexically_relative(directory).generic_string(),
          packages::hashFile(it->path(), size).value_or("unreadable"));
    }
  std::sort(found.begin(), found.end());
  return found;
}

std::string inputState(const fs::path &path) {
  std::error_code error;
  if (fs::is_directory(path, error)) {
    std::string listing;
    for (const auto &[name, hash] : filesBelow(path))
      listing += name + "=" + hash + "\n";
    return "dir:" + digest(listing);
  }
  if (fs::is_regular_file(path, error)) {
    std::uint64_t size = 0;
    return "file:" + packages::hashFile(path, size).value_or("unreadable");
  }
  return "absent";
}

std::string variableState(const std::string &name) {
  const char *value = std::getenv(name.c_str());
  return value ? "set:" + digest(value) : "unset";
}
} // namespace mettle::driver
