#pragma once

#include "semantics/checked.h"
#include "source/source.h"
#include <functional>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::lint {
enum class Level { Allow, Warn, Deny };

// Rule names are stable kebab-case identifiers.
inline constexpr std::string_view unusedBinding = "unused-binding";
inline constexpr std::string_view unusedMutability = "unused-mutability";
inline constexpr std::string_view unusedImport = "unused-import";
inline constexpr std::string_view unreachableCode = "unreachable-code";
inline constexpr std::string_view unusedOutcome = "unused-outcome";
const std::vector<std::string_view> &rules();
bool known(std::string_view rule);

struct Configuration {
  // Level of every rule without an entry in `levels` (`--deny warnings`).
  Level defaultLevel = Level::Warn;
  // Command-line levels by rule name; a source `@allow`, `@warn`, `@deny` or
  // `@forbid` attribute on a function overrides them inside it.
  std::map<std::string, Level> levels;
  // Only spans for which this returns true are linted; empty selects all.
  std::function<bool(Span)> include;
};

struct Finding {
  std::string rule;
  Span span;
  std::string message;
  Level level = Level::Warn;
};

// Semantic lints over checked facts. The syntax tree is only read; findings
// at `Level::Allow` are not returned. They are ordered by source position.
std::vector<Finding> run(const CheckedModule &module,
                         const Configuration &configuration);
} // namespace mettle::lint
