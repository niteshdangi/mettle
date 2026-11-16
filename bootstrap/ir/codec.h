#pragma once

#include "ir/ir.h"
#include "metadata/references.h"
#include <memory>
#include <optional>
#include <span>

namespace mettle::ir {
class LazyFunctionBodies;

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
  std::shared_ptr<LazyFunctionBodies> lazyFunctions;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};

struct FunctionDecodeResult {
  std::optional<Function> function;
  std::string error;
  explicit operator bool() const { return function.has_value(); }
};

class LazyFunctionBodies {
public:
  FunctionDecodeResult load(std::size_t record, const Function &header,
                            const metadata::DecodeReferences &references) const;

private:
  struct State;
  explicit LazyFunctionBodies(std::shared_ptr<State> state)
      : state(std::move(state)) {}
  std::shared_ptr<State> state;
  friend DecodeResult
  decodeProgramLazy(std::span<const std::uint8_t>,
                    const metadata::DecodeReferences &references);
};

EncodeResult encodeProgram(const Program &program,
                           const metadata::EncodeReferences &references);
// Raw records require global-table assembly and pipeline validation before use.
DecodeResult decodeProgram(std::span<const std::uint8_t> bytes,
                           const metadata::DecodeReferences &references);
// Decodes and validates headers and record extents. Function bodies are
// validated when loaded; `bytes` must outlive the returned body loader.
DecodeResult decodeProgramLazy(std::span<const std::uint8_t> bytes,
                               const metadata::DecodeReferences &references);
} // namespace mettle::ir
