#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/token.h"
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::expansion {
struct MacroSource {
  std::string identity, path;
  std::uint32_t bytes = 0;
};
struct MacroLocation {
  std::uint32_t source = UINT32_MAX;
  std::uint32_t begin = 0, end = 0;
};
struct MacroContext {
  std::vector<std::string> scope;
  MacroLocation definition;
  bool hygienic = false;
};
struct MacroToken {
  TokenKind kind = TokenKind::Word;
  std::string text;
  MacroLocation origin;
  bool space = false, authored = false, glued = false;
  std::optional<std::uint32_t> context;
};
enum class MacroNodeKind { Literal, Variable, Repetition, Capture };
struct MacroNode {
  MacroNodeKind kind = MacroNodeKind::Literal;
  MacroToken token;
  std::string name, fragment;
  std::vector<MacroNode> body;
  std::optional<MacroToken> separator;
  char repetition = '*';
};
struct MacroRule {
  std::vector<MacroNode> matcher, expansion;
};
struct MacroDefinition {
  std::string name;
  MacroLocation location;
  std::vector<std::string> scope, visibilityBoundary;
  bool publicItem = false;
  std::vector<MacroRule> rules;
};
struct MacroImport {
  std::vector<std::string> scope, path;
  std::string alias, name;
  bool publicItem = false;
  std::vector<std::string> restriction;
  MacroLocation location;
};
// All numeric references are relative to these tables, never compiler IDs.
struct MacroLibrary {
  std::vector<MacroSource> sources;
  std::vector<MacroContext> contexts;
  std::vector<MacroDefinition> definitions;
  std::vector<MacroImport> imports;
  std::vector<std::string> indexedModules;
  std::vector<std::vector<std::string>> declaredModules;
};
using MacroSourceIdentity = std::function<std::string(const Source &)>;
using MacroSourceRemap =
    std::function<std::optional<SourceId>(const MacroSource &)>;
bool validateMacros(const MacroLibrary &library, Diagnostics &diagnostics);
bool mergeMacros(MacroLibrary &target, const MacroLibrary &source,
                 Diagnostics &diagnostics, const MacroSourceRemap &remap,
                 const MacroSourceIdentity &identify);
std::optional<std::string> encodeMacros(const MacroLibrary &library,
                                        Diagnostics &diagnostics);
std::optional<MacroLibrary> decodeMacros(std::string_view bytes,
                                         Diagnostics &diagnostics);
} // namespace mettle::expansion
