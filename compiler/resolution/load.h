#pragma once

#include "diagnostics/diagnostics.h"
#include "expansion/expand.h"
#include "syntax/ast.h"
#include <functional>
#include <optional>
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
  // Target and feature facts that `@cfg` predicates test.
  expansion::Configuration configuration{};
};
std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics,
                           const Library &library = {});
std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics,
                           const Library &library = {});
} // namespace mettle::resolution
