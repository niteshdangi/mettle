#pragma once

#include "expansion/expand.h"
#include <string>
#include <vector>

namespace mettle::expansion {
// One derive named by an `@derive(...)` attribute.
struct DeriveRequest {
  std::string name;
  Span span;
};

// Attribute names with a defined meaning. Names outside this set are unknown.
bool knownAttribute(const std::string &name);

// Evaluates the predicate of an `@cfg(...)` attribute. A malformed or unknown
// predicate is diagnosed and counts as false.
bool evaluateCfg(const Attribute &attribute,
                 const Configuration &configuration, Diagnostics &diagnostics);

// Parses `@derive(A, B, ...)` into requests, diagnosing malformed lists and
// duplicate names.
std::vector<DeriveRequest> deriveRequests(const Attribute &attribute,
                                          std::set<std::string> &requested,
                                          Diagnostics &diagnostics);

// Generates the implementations requested for one type declaration and adds
// them to the module; `Copy` marks the declaration itself.
void generateDerives(Module &module, std::size_t product,
                     const std::vector<DeriveRequest> &requests,
                     Diagnostics &diagnostics, const SourceAllocator &allocate);
} // namespace mettle::expansion
