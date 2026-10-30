#pragma once

#include "syntax/ast.h"
#include <string>

namespace mettle {
// A canonical text of the syntax tree of `module`: declarations, types,
// patterns and expressions, without spans. Two sources with equal
// fingerprints parse to the same syntax. Used by tools that rewrite source
// text (`format`) to prove the rewrite kept the syntax.
std::string fingerprint(const Module &module);
} // namespace mettle
