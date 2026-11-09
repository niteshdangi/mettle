#pragma once

#include "diagnostics/diagnostics.h"
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace mettle::packages {
struct GitCheckout {
  std::string directory, commit;
};

struct Request {
  // A package directory or its package.mettle.
  std::string input;
  // Executable target to build; empty selects the package's only one.
  std::string target;
  std::vector<std::string> features;
  bool defaultFeatures = true;
  bool includeDev = false;
  // `--locked`: the lock may not change; `--offline`: nothing is fetched.
  bool locked = false, offline = false;
  // Extra local registry directories, searched before the manifest's.
  std::vector<std::string> registries;
  // The driver owns system-git execution and the package source store.
  std::function<std::optional<GitCheckout>(
      const std::string &url, const std::string &selector,
      const std::string &lockedCommit, bool offline, std::string &error)>
      gitCheckout;
};

// A dependency library mounted as the root module `name`.
struct Mount {
  std::string name, source;
  std::string identity;
  // Stable internal module root for this exact package source/version.
  std::string module;
  // The package name and version that supply it (for build records).
  std::string package, version;
  // Features the resolution enabled for this package, sorted.
  std::vector<std::string> features;
  // Direct dependencies visible to this package, as alias/module-root pairs.
  std::vector<std::pair<std::string, std::string>> dependencies;
};

// A package's `[build] script`, run on the host before consumers compile.
struct BuildScript {
  std::string package, version;
  std::string identity;
  // Absolute package directory and canonical script source.
  std::string directory, source;
  std::vector<std::string> features;
  std::vector<std::pair<std::string, std::string>> dependencies;
  bool root = false;
};

// A procedural macro declared by a package of the graph; its program runs on
// the host while sources expand.
struct Macro {
  std::string name, package, version;
  // Absolute package directory and canonical program source.
  std::string directory, source;
  std::vector<std::string> features;
  std::vector<std::pair<std::string, std::string>> dependencies;
};

struct Plan {
  std::string package, version;
  std::string rootIdentity;
  // Source file of the selected entry.
  std::string root;
  std::string kind;
  std::vector<std::string> emits;
  std::vector<Mount> mounts;
  std::vector<Mount> hostMounts;
  // Build scripts of the root and its dependencies, in resolution order.
  std::vector<BuildScript> scripts;
  // Procedural macros of the root and its dependencies, in resolution order.
  std::vector<Macro> macros;
  // Dependencies visible from the root package.
  std::vector<std::pair<std::string, std::string>> dependencies;
  std::vector<std::pair<std::string, std::string>> hostDependencies;
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

// Resolves the manifest, verifies or writes lock.mettle and returns the
// source graph of the selected target. Reports `package`, `lock`, `io` and
// `feature` diagnostics, each located in the manifest or lock when possible.
Outcome plan(const Request &request, Diagnostics &diagnostics);
} // namespace mettle::packages
