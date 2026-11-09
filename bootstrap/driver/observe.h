#pragma once

#include <filesystem>
#include <string>
#include <utility>
#include <vector>

namespace mettle::driver {
// Observations that host programs (build scripts, procedural macros) declare
// as the inputs of a reproducible result.
using Files = std::vector<std::pair<std::string, std::string>>;

std::string digest(const std::string &text);

// Relative path of every regular file below `directory`, with its content
// hash, sorted.
Files filesBelow(const std::filesystem::path &directory);

// The state of a declared input: `file:HASH`, `dir:HASH` (over every file
// below it) or `absent`.
std::string inputState(const std::filesystem::path &path);

// `set:HASH` of the value of an environment variable, or `unset`.
std::string variableState(const std::string &name);
} // namespace mettle::driver
