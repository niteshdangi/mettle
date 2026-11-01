#pragma once

#include "resolution/load.h"
#include "types/target.h"
#include "types/type.h"
#include <iosfwd>
#include <string>

namespace mettle::lsp {
// What the server needs from its host: the library layout and target facts the
// front end analyzes with, and a reader for source files that are not open in
// the editor (the host owns file I/O).
struct Configuration {
  resolution::Library library;
  resolution::SourceProvider provider;
  TargetFacts target;
  std::string version;
  NumericEvaluator numericEvaluator = nullptr;
};

// Serves the Language Server Protocol (JSON-RPC with Content-Length framing)
// until `exit` or end of input. Returns 0 when `exit` followed `shutdown`,
// otherwise 1.
int serve(std::istream &in, std::ostream &out,
          const Configuration &configuration);
} // namespace mettle::lsp
