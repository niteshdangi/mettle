#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>

// Resource limits protect the compiler from exhausting its own stack, memory
// or time. Recursion depths are bounded by the stack the compiler runs on;
// count limits only trip on pathological input, far above any real program.
namespace mettle::limits {
// Self-hosted source spans use per-file 32-bit byte offsets.
inline constexpr std::size_t sourceBytes =
    std::numeric_limits<std::uint32_t>::max();
inline constexpr std::size_t tokens = std::size_t{1} << 26;
inline constexpr std::size_t functions = std::size_t{1} << 22;
inline constexpr std::size_t products = std::size_t{1} << 22;
inline constexpr std::size_t interfaces = std::size_t{1} << 22;
inline constexpr std::size_t witnessSlots = std::size_t{1} << 26;
inline constexpr std::size_t locals = std::size_t{1} << 24;
inline constexpr std::size_t cfgBlocks = std::size_t{1} << 26;
// Printed diagnostics only; every further error is counted and summarized.
inline constexpr std::size_t diagnostics = 100;
inline constexpr unsigned parserNesting = 128;
inline constexpr unsigned syntaxDepth = 256;
inline constexpr unsigned typeDepth = 128;
// Spelled size of one specialization argument: polymorphic recursion that
// doubles a type each level is reported long before it exhausts memory.
inline constexpr std::size_t typeNameBytes = std::size_t{1} << 20;
// Step budgets of fixpoint solvers and projection walks.
inline constexpr std::size_t activeLoans = std::size_t{1} << 22;
// Elements of expanded aggregate cleanup/initialization hierarchies.
inline constexpr std::size_t cleanupPlaces = std::size_t{1} << 24;
// Compile-time evaluation: evaluation steps per required constant and the
// nesting of const function calls. Exhaustion is a diagnostic, never a cap.
inline constexpr std::size_t constEvalSteps = std::size_t{1} << 24;
inline constexpr unsigned constEvalDepth = 256;
// Objects must stay addressable: sizes are bounded by the signed pointer range.
inline constexpr std::uint64_t objectBytes = std::uint64_t{1} << 62;
} // namespace mettle::limits
