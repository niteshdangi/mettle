#pragma once

#include "diagnostics/diagnostics.h"
#include <optional>
#include <string>
#include <vector>

namespace mettle::packages {
struct Request {
  // A package directory or its Mettle.toml.
  std::string input;
  // Executable target to build; empty selects the package's only one.
  std::string target;
  std::vector<std::string> features;
  bool defaultFeatures = true;
  // `--locked`: the lock may not change; `--offline`: nothing is fetched.
  bool locked = false, offline = false;
  // Extra local registry directories, searched before the manifest's.
  std::vector<std::string> registries;
};

// A dependency library mounted as the root module `name`.
struct Mount {
  std::string name, source;
  // The package name and version that supply it (for build records).
  std::string package, version;
  // Features the resolution enabled for this package, sorted.
  std::vector<std::string> features;
};

// A package's `[build] script`, run on the host before consumers compile.
struct BuildScript {
  std::string package, version;
  // Absolute package directory and canonical script source.
  std::string directory, source;
  bool root = false;
};

struct Plan {
  std::string package, version;
  // Source file of the selected executable target.
  std::string root;
  std::vector<Mount> mounts;
  // Build scripts of the root and its dependencies, in resolution order.
  std::vector<BuildScript> scripts;
  // Features the resolution enabled for the root package, sorted.
  std::vector<std::string> features;
  // Content identity of everything that selects this build's inputs: the
  // lock, selected features and target.
  std::string fingerprint;
};

struct Outcome {
  std::optional<Plan> plan;
  // Registered source for diagnostics that carry no span.
  Source fallback;
};

// Resolves the manifest, verifies or writes Mettle.lock and returns the
// source graph of the selected target. Reports `package`, `lock`, `io` and
// `feature` diagnostics, each located in the manifest or lock when possible.
Outcome plan(const Request &request, Diagnostics &diagnostics);
} // namespace mettle::packages
