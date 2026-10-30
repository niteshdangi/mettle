#pragma once

#include "syntax/ast.h"
#include <string>

namespace mettle {
// A canonical text of the syntax tree of `module`: declarations, types,
// patterns and expressions, without spans. Two sources with equal
// fingerprints parse to the same syntax; `::` paths and dotted chains of
// names are compared in their dotted-neutral form, with generic arguments
// attached to the path segment they apply to. Used by tools that rewrite
// source text (`migrate`, `format`) to prove the rewrite kept the syntax.
std::string fingerprint(const Module &module);
} // namespace mettle
