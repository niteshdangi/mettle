#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"
#include <functional>
#include <set>
#include <string>

namespace mettle::expansion {
// Facts that `@cfg` predicates test. The driver derives the target facts from
// the selected target and supplies the enabled package features; an empty
// value matches no predicate on that key.
struct Configuration {
  std::string os, arch, family, endian;
  unsigned pointerWidth = 0;
  std::set<std::string> targetFeatures, features;
  // Test builds: collect `@test`/`@bench` functions of the root source into
  // `Module::tests` and drop that source's own entry function (the harness
  // supplies the entry).
  bool collectTests = false, dropEntry = false;
};
// Allocates the identity of a generated source (the text of a derive).
using SourceAllocator = std::function<SourceId()>;
// Expands the attributes of one parsed source before its member functions are
// flattened: validates attribute names and attachment, removes items, members
// and variants whose `@cfg` predicate is false (every predicate is validated,
// including those in inactive code), and generates the implementations that
// `@derive` requests. Generated code is parsed as an ordinary source and
// registered with the diagnostics for provenance. Consumed attributes
// (`cfg`, `derive`) are removed from the tree.
void expand(Module &module, Diagnostics &diagnostics,
            const Configuration &configuration,
            const SourceAllocator &allocate);
} // namespace mettle::expansion
