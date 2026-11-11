#pragma once

#include "ir/ir.h"
#include "metadata/references.h"
#include <span>

namespace mettle::ir {
struct EncodeResult {
  std::vector<std::uint8_t> bytes;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};
struct DecodeResult {
  Program program;
  // Records retain archive order; destination indices select consumer tables.
  std::vector<std::string> functionIdentities, staticIdentities;
  std::vector<std::uint32_t> functionDestinations, staticDestinations;
  // Sparse assignments from consumer closure slots to consumer functions.
  std::vector<std::pair<std::uint32_t, int>> closureFunctions;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};

EncodeResult encodeProgram(const Program &program,
                           const metadata::EncodeReferences &references);
// Raw records require global-table assembly and pipeline validation before use.
DecodeResult decodeProgram(std::span<const std::uint8_t> bytes,
                           const metadata::DecodeReferences &references);
} // namespace mettle::ir
