#pragma once

#include "diagnostics/diagnostics.h"
#include "source/source.h"
#include <optional>
#include <string>
#include <vector>

namespace mettle {
// A pre-cutover spelling left unchanged because the target spelling would
// not parse to the same syntax tree there (or needs a form not yet supported).
struct MigrationSkip {
  std::size_t offset = 0;
  std::string reason;
};
struct Migration {
  std::string text;
  std::size_t rewrites = 0;
  std::vector<MigrationSkip> skipped;
};
// Rewrites the pre-cutover spellings of language-grammar section 13 to the
// target spellings using the token stream and parsed declarations of
// `source`: `::` paths and turbofish, `impl`, and `<T implements I>::Item`.
// The source must parse; the result is parsed again and its syntax tree is
// compared with the original (paths compared in their dotted-neutral form),
// so a rewrite that would change the meaning is reported as an error instead
// of produced. Sites that cannot be rewritten safely stay as they are and are
// listed in `skipped`; running the migration again converges on nested forms.
std::optional<Migration> migrate(const Source &source,
                                 Diagnostics &diagnostics);
} // namespace mettle
