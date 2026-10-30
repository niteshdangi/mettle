#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::packages {
struct Version {
  std::uint64_t major = 0, minor = 0, patch = 0;
  std::vector<std::string> pre;
  // Build metadata never takes part in ordering or equality.
  std::string build;
};

// Strict SemVer 2.0.0 `MAJOR.MINOR.PATCH[-PRE][+BUILD]`.
std::optional<Version> parseVersion(std::string_view text);
std::string toString(const Version &version);
// Negative, zero or positive; SemVer precedence.
int compare(const Version &left, const Version &right);

// One bound of an interval: `>=`, `>`, `<=`, `<` or `=`.
struct Comparator {
  enum class Op { Exact, Greater, GreaterEqual, Less, LessEqual };
  Op op = Op::Exact;
  Version version;
  // A comparator whose version text carried a prerelease tag.
  bool prerelease = false;
};

// Exact, caret, tilde and comparator intersections; `alternatives` is the
// union of the comma-separated intersections of each requirement string.
struct Requirement {
  std::vector<std::vector<Comparator>> alternatives;
  std::string text;

  // A prerelease candidate matches only through a comparator that names a
  // prerelease of the same major.minor.patch.
  bool matches(const Version &version) const;
};

// Parses one requirement string, or reports why it is invalid in `error`.
std::optional<Requirement> parseRequirement(std::string_view text,
                                            std::string &error);
// Union of several requirement strings.
Requirement unite(std::vector<Requirement> parts);
} // namespace mettle::packages
