#pragma once

#include "diagnostics/diagnostics.h"
#include "expansion/expand.h"
#include "expansion/procedural.h"
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace mettle::expansion {
struct MacroModuleSource {
  Source source;
  // Canonical module path named by the invocation.
  std::vector<std::string> path;
  // File-module scope of `source`; trailing path components may be inline
  // modules within that source.
  std::vector<std::string> sourcePath;
};
using MacroModuleProvider = std::function<std::optional<MacroModuleSource>(
    const std::vector<std::string> &path,
    const std::vector<std::string> &from)>;

// Expands the declarative macros of one source before it is parsed.
//
//   macro name {
//       (matcher) => { expansion };
//   }
//
// Definitions are lexically inline-module-scoped within this source and order
// independent. An invocation `name!(...)` (also `[...]` and `{...}`) selects
// the first rule whose matcher recognizes the argument tokens; short and full
// fragment-kind spellings are accepted. Explicit imports bind macros in their
// separate namespace, and public imports reexport them. A qualified invocation
// can resolve a macro from an external module through the loader-supplied
// provider, subject to its visibility boundary.
// Structured fragments must parse with the native parser. Template-local
// bindings, including match-arm pattern bindings, are renamed per expansion;
// `$capture(name)` deliberately names an invocation-context identifier.
// Expression-position expansions are grouped as a whole. Free names are
// qualified to the definition's module across inline-module boundaries. A
// recursion limit and every matching, definition or repetition fault is a
// structured `macro` diagnostic at the use site.
//
// `procedural` (may be null) names host-program macros that are invoked the
// same way (`name!(...)`): the argument tokens go to the program (see
// expansion/procedural.h), its text output is re-lexed and spliced in with
// every token attributed to the invocation, and the result is expanded again.
// A program failure, a protocol fault or output that does not lex is a
// `macro` diagnostic at the invocation. A lexically visible declarative macro
// of the same name takes precedence.
//
// `declarations`, when supplied, receives the syntax-only declarations removed
// from this source so name resolution can build their macro namespace.
// Returns nullopt when the source has no local, imported or qualified macro
// invocation, no procedural macro, or does not lex (the parser then reports
// it); otherwise the generated source, which keeps the original path. Its
// registered provenance maps every generated token back to the template or
// argument token it came from, with the invocation as the origin, and unchanged
// text exactly, so diagnostics keep their positions.
std::optional<Source>
expandMacros(const Source &source, Diagnostics &diagnostics,
             const SourceAllocator &allocate,
             const Procedures *procedural = nullptr,
             std::vector<std::string> modulePath = {},
             const MacroModuleProvider &modules = {},
             std::vector<Module::MacroDeclaration> *declarations = nullptr);
} // namespace mettle::expansion
