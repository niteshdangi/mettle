#pragma once

#include "diagnostics/diagnostics.h"
#include "packages/data.h"
#include "packages/semver.h"
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace mettle::packages {
struct DependencySpec {
  // The dependency's package name; it also names the mounted module root
  // (with '-' spelled '_').
  std::string name;
  std::optional<std::string> path;
  std::optional<std::string> git;
  std::optional<std::string> rev, tag, branch;
  std::optional<Requirement> requirement;
  std::vector<std::string> features;
  bool defaultFeatures = true;
  bool optional = false;
  // The dependency key in the declaring manifest.
  Span span;
};

struct Target {
  std::string name, kind, source;
  Span span;
};

// A procedural macro: a Mettle host program, relative to the package
// directory, that `name!(...)` invocations run. `api` is the extension API
// major version it requires.
struct MacroDecl {
  std::string name, source;
  std::int64_t api = 0;
  Span span;
};

struct Feature {
  std::string name;
  // `feature`, `dep:name` or `name/feature` entries.
  std::vector<std::string> items;
  Span span;
};

struct Manifest {
  std::string name;
  Version version;
  std::vector<Target> targets;
  // Only `dependencies` take part in builds; `dev-dependencies` are parsed and
  // validated but belong to a separate (test) context.
  std::vector<DependencySpec> dependencies, buildDependencies, devDependencies;
  std::vector<Feature> features;
  // Local registry directory declared by the root package, if any.
  std::optional<std::string> registry;
  // `[build] script`: a Mettle program, relative to the package directory,
  // that runs on the host before this package's consumers compile.
  std::optional<std::string> buildScript;
  Span buildScriptSpan;
  // Host macro declarations in source order.
  std::vector<MacroDecl> macros;
  // Absolute, normalized package directory.
  std::string directory;
  SourceId source = 0;
  Span nameSpan;

  const DependencySpec *dependency(const std::string &name) const;
  const Feature *feature(const std::string &name) const;
  // The library target, or the executable named `name` (empty: the only one).
  const Target *library() const;
};

bool validPackageName(const std::string &name);
// The module root a dependency package is mounted as.
std::string moduleName(const std::string &package);

// Validates a parsed package.mettle; every fault is a `package` diagnostic.
std::optional<Manifest> parseManifest(const data::Value &root,
                                      const Source &source,
                                      const std::string &directory,
                                      Diagnostics &diagnostics);
} // namespace mettle::packages
