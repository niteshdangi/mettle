#pragma once

#include "source/source.h"
#include <filesystem>
#include <map>
#include <set>

namespace mettle::driver {
struct LibraryCacheConfiguration {
  std::string compiler, identity, target, profile, cc, sysroot;
  bool checks = true, freestanding = false, debugInfo = false;
  std::set<std::string> features, targetFeatures, sanitizers;
  std::map<std::string, std::string> dependencies;
};

struct LibraryInputs {
  std::string key;
  std::map<std::string, Source> sources;
};

std::optional<LibraryInputs>
collectLibraryInputs(const std::filesystem::path &directory,
                     const LibraryCacheConfiguration &configuration,
                     std::string &error);
} // namespace mettle::driver
