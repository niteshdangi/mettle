#pragma once

#include <cstddef>
#include <cstdint>

// Resource limits protect the compiler from exhausting its own stack, memory
// or time. Recursion depths are bounded by the stack the compiler runs on;
// count limits only trip on pathological input, far above any real program.
namespace mettle::limits {
inline constexpr std::size_t sourceBytes = std::size_t{1} << 30;
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
// Step budgets of fixpoint solvers and projection walks.
inline constexpr std::size_t activeLoans = std::size_t{1} << 22;
// Elements of expanded aggregate cleanup/initialization hierarchies.
inline constexpr std::size_t cleanupPlaces = std::size_t{1} << 24;
// Objects must stay addressable: sizes are bounded by the signed pointer range.
inline constexpr std::uint64_t objectBytes = std::uint64_t{1} << 62;
} // namespace mettle::limits
