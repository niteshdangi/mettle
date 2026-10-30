#pragma once

#include "diagnostics/diagnostics.h"
#include "expansion/expand.h"
#include <optional>

namespace mettle::expansion {
// Expands the declarative macros of one source before it is parsed.
//
//   macro name {
//       (matcher) => { expansion };
//   }
//
// Definitions are file-local and order independent. An invocation `name!(...)`
// (also `[...]` and `{...}`) selects the first rule whose matcher recognizes
// the argument tokens; `expr`, `stmt`, `pat`, `ty`, `path` and `item`
// fragments must parse with the native parser. Identifiers that an expansion
// binds itself (`let`, `var`, `for`, closure parameters) are renamed per
// expansion, so they never capture or shadow user names; `$capture(name)`
// deliberately names an invocation-context identifier. A recursion limit and
// every matching, definition or repetition fault is a structured `macro`
// diagnostic at the use site.
//
// Returns nullopt when the source defines no macro or does not lex (the
// parser then reports it); otherwise the generated source, which keeps the
// original path. Its registered provenance maps every generated token back to
// the template or argument token it came from, with the invocation as the
// origin, and unchanged text exactly, so diagnostics keep their positions.
std::optional<Source> expandMacros(const Source &source,
                                   Diagnostics &diagnostics,
                                   const SourceAllocator &allocate);
} // namespace mettle::expansion
