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
  for (fs::recursive_directory_iterator it(directory), end; it != end; ++it)
    if (it->is_regular_file()) {
      std::uint64_t size = 0;
      auto hash = packages::hashFile(it->path(), size);
      if (!hash)
        throw fs::filesystem_error("cannot read observed file", it->path(),
                                   std::make_error_code(std::errc::io_error));
      found.emplace_back(
          it->path().lexically_relative(directory).generic_string(),
          std::move(*hash));
    }
  std::sort(found.begin(), found.end());
  return found;
}

std::string inputState(const fs::path &path) {
  std::error_code error;
  auto status = fs::status(path, error);
  if (status.type() == fs::file_type::not_found &&
      (!error || error == std::errc::no_such_file_or_directory ||
       error == std::errc::not_a_directory))
    return "absent";
  if (error)
    throw fs::filesystem_error("cannot inspect declared input", path, error);
  if (fs::is_directory(status)) {
    std::string listing;
    for (const auto &[name, hash] : filesBelow(path))
      listing += name + "=" + hash + "\n";
    return "dir:" + digest(listing);
  }
  if (fs::is_regular_file(status)) {
    std::uint64_t size = 0;
    auto hash = packages::hashFile(path, size);
    if (!hash)
      throw fs::filesystem_error("cannot read declared input", path,
                                 std::make_error_code(std::errc::io_error));
    return "file:" + *hash;
  }
  throw fs::filesystem_error(
      "declared input is not a regular file or directory", path,
      std::make_error_code(std::errc::operation_not_supported));
}

std::string variableState(const std::string &name) {
  const char *value = std::getenv(name.c_str());
  return value ? "set:" + digest(value) : "unset";
}
} // namespace mettle::driver
