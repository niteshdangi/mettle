#pragma once

#include <cstddef>

namespace mettle::limits {
inline constexpr std::size_t sourceBytes = 8 * 1024 * 1024;
inline constexpr std::size_t tokens = 500000;
inline constexpr std::size_t functions = 1024;
inline constexpr std::size_t products = 1024;
inline constexpr std::size_t interfaces = 1024;
inline constexpr std::size_t witnessSlots = 65536;
inline constexpr std::size_t locals = 1024;
inline constexpr std::size_t cfgBlocks = 4096;
inline constexpr std::size_t diagnostics = 32;
inline constexpr unsigned parserNesting = 128;
inline constexpr unsigned syntaxDepth = 256;
inline constexpr unsigned typeDepth = 128;
inline constexpr std::size_t activeLoans = 4096;
inline constexpr std::size_t cleanupPlaces = 65536;
} // namespace mettle::limits
