#pragma once

#include "diagnostics/diagnostics.h"
#include "expansion/expand.h"
#include "expansion/procedural.h"
#include "source/source.h"
#include "syntax/ast.h"
#include <functional>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace mettle::resolution {
// Providers own I/O and return a canonical path as Source::path. In-memory
// callers supply a source catalog; this component never opens a file.
using SourceProvider =
    std::function<std::optional<Source>(const std::string &path)>;
// Native libraries (`core`, `alloc`, `std`) live at DIRECTORY/NAME/module.mt
// and are read through the same provider as program sources. A library root is
// mounted as a root module only when the loaded sources reference it and the
// program does not declare a root module of that name (user roots shadow the
// library). An empty directory disables library mounting.
struct Library {
  std::string directory;
  // `alloc` stays available (it only needs a provided allocator); `std` does
  // not.
  bool freestanding = false;
  // Dependency packages: each library source is mounted as the public root
  // module `name` before library references are scanned, and is treated as
  // user code (it may name the library roots and the prelude).
  struct Package {
    std::string name, source;
    // Features the package resolution enabled for this package.
    std::set<std::string> features;
  };
  std::vector<Package> packages;
  // Target facts and the root source's features that `@cfg` predicates test;
  // a dependency package tests its own features, the standard libraries none.
  expansion::Configuration configuration{};
  // Test/benchmark builds: the selected package's `@test` (or `@bench`)
  // functions are collected into `Module::tests`, the root `main` is dropped
  // and a synthesized harness entry is loaded beside it.
  enum class Harness { None, Test, Bench } harness = Harness::None;
  // Host-program macros that every loaded source may invoke; null for none.
  // The host must outlive the load.
  const expansion::Procedures *procedures = nullptr;
};
// An original source file in the selected package and its external-module
// path. The driver uses these inputs to discover and overlay doctests without
// changing files in the package.
struct SourceModule {
  Source source;
  std::vector<std::string> path;
};
std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics,
                           const Library &library = {},
                           std::vector<SourceModule> *sourceModules = nullptr);
std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics,
                           const Library &library = {});
} // namespace mettle::resolution
