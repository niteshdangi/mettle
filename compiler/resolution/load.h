#pragma once

#include "diagnostics/diagnostics.h"
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
std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics);
std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics);
} // namespace mettle::resolution
