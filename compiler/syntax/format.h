#pragma once

#include "diagnostics/diagnostics.h"
#include "source/source.h"
#include <functional>
#include <optional>
#include <string>

namespace mettle {
// The canonical layout of `source`, or nullopt with a diagnostic when the
// source does not parse or the result cannot be proven equivalent.
//
// The formatter works on the token stream and changes only whitespace:
// indentation follows bracket nesting (4 spaces; a line continued inside
// brackets or after a trailing operator gets one more level), horizontal
// spacing is normalized around commas, colons, `::`, `.`, braces and
// assignment/comparison operators (other gaps keep one space or none as
// written), trailing whitespace is removed, blank lines are collapsed to at
// most one and the file ends in exactly one newline. Line breaks are never
// added or removed, so the newline-sensitive grammar sees the same
// statements. Comments, text literals (including multi-line raw text) and
// f-strings keep their bytes (line comments lose trailing whitespace).
//
// The result is checked before it is returned: it must lex and parse, have
// the same token sequence (kinds, texts and whether a line break separates
// neighbours), the same syntax-tree fingerprint, and be a fixed point.
// `expand`, when given, turns a source into the one the parser reads (the
// driver passes declarative-macro expansion); both fingerprints are taken
// from expanded sources so files that define macros can be checked too.
using SourceExpander =
    std::function<std::optional<Source>(const Source &, Diagnostics &)>;
std::optional<std::string> format(const Source &source,
                                  Diagnostics &diagnostics,
                                  const SourceExpander &expand = {});
} // namespace mettle
