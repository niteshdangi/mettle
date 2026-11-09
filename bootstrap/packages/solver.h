#pragma once

#include "diagnostics/diagnostics.h"
#include "packages/manifest.h"
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace mettle::packages {
enum class SourceKind { Root, Path, Registry, Git };

struct Candidate {
  std::shared_ptr<const Manifest> manifest;
  SourceKind kind = SourceKind::Path;
  // Package directory; for a registry package its place in the registry.
  std::string location;
  // Identity of the registry that supplied the package (registry kind only).
  std::string registry;
  // Git source identity (git kind only).
  std::string git, commit;
  // Stable lock/workspace-relative identity, not an absolute cache path.
  std::string sourceIdentity;
  bool yanked = false, host = false;
};
std::string identity(const Candidate &candidate);

// Where candidates come from; the solver performs no I/O itself.
struct Universe {
  // The package a path dependency declared by `from` refers to; reports its
  // own diagnostics and returns nothing when the package cannot be loaded.
  std::function<std::optional<Candidate>(const Manifest &from,
                                         const DependencySpec &spec)>
      path;
  std::function<std::optional<Candidate>(const Manifest &from,
                                         const DependencySpec &spec)>
      git;
  std::function<std::vector<Candidate>(const std::string &name)> registry;
  // Why no registry candidate of `name` exists (offline, no registry, ...).
  std::function<std::string(const std::string &name)> absence;
};

struct Problem {
  Candidate root;
  std::vector<std::string> features;
  bool defaultFeatures = true;
  // Versions pinned by an existing lock; preferred while they still satisfy.
  std::map<std::string, std::vector<Version>> preferred;
};

struct ResolvedPackage {
  Candidate candidate;
  std::string identity;
  // Selected features and active dependencies, sorted.
  std::vector<std::string> features;
  // Dependency manifest key and exact package instance identity.
  std::vector<std::pair<std::string, std::string>> dependencies;
  const std::string &name() const { return candidate.manifest->name; }
};

struct Resolution {
  // The root first, then every other package sorted by identity.
  std::vector<ResolvedPackage> packages;
};

// Chronological backtracking over registry versions: the highest compatible
// non-yanked candidate wins unless a lock prefers another. Unifies features
// per package; conflicts and dependency cycles are diagnostics.
std::optional<Resolution> resolve(const Problem &request,
                                  const Universe &universe,
                                  Diagnostics &diagnostics);
} // namespace mettle::packages
