#pragma once

#include "source/source.h"
#include <ctime>
#include <filesystem>
#include <map>
#include <memory>
#include <set>

namespace mettle::driver {
struct LibraryCacheConfiguration {
  std::string compiler, identity, target, profile, cc, sysroot;
  bool checks = true, freestanding = false, debugInfo = false;
  std::set<std::string> features, targetFeatures, sanitizers;
  std::map<std::string, std::string> dependencies;
  bool operator==(const LibraryCacheConfiguration &) const = default;
};

struct LibraryInputs {
  std::string key;
  std::map<std::string, Source> sources;
  std::map<std::string, std::string> digests;
};

std::string
shippedLibrarySelector(const std::filesystem::path &directory,
                       const LibraryCacheConfiguration &configuration);

std::optional<LibraryInputs>
collectLibraryInputs(const std::filesystem::path &directory,
                     const LibraryCacheConfiguration &configuration,
                     std::string &error, std::string *snapshot = nullptr);

std::string
librarySnapshotSelector(const std::filesystem::path &directory,
                        const LibraryCacheConfiguration &configuration);

std::optional<LibraryInputs> restoreLibraryInputs(std::string_view record);
std::optional<std::string> entryStamp(const std::filesystem::path &path,
                                      std::time_t before);

class LibraryInputSnapshots {
public:
  LibraryInputSnapshots();
  ~LibraryInputSnapshots();
  std::shared_ptr<const LibraryInputs>
  collect(const std::filesystem::path &directory,
          const LibraryCacheConfiguration &configuration, std::string &error,
          std::string &fallback);

private:
  struct Entry;
  std::map<std::string, std::unique_ptr<Entry>> entries;
};
} // namespace mettle::driver
