#pragma once

#include "lsp/symbols.h"
#include "lsp/text.h"
#include <optional>
#include <string>
#include <tuple>
#include <vector>

namespace mettle::lsp {
// One analyzed document of the workspace.
struct File {
  std::string uri;
  const LineIndex *lines = nullptr;
  const SymbolIndex *index = nullptr;
};
using Files = std::vector<File>;

// A byte range of a workspace file.
struct Site {
  std::size_t file = 0, begin = 0, end = 0;
  bool operator<(const Site &other) const {
    return std::tie(file, begin, end) <
           std::tie(other.file, other.begin, other.end);
  }
  bool operator==(const Site &other) const {
    return file == other.file && begin == other.begin && end == other.end;
  }
};

// The declarations the identifier at `offset` of `files[file]` can refer to:
// the visible local or parameter, else the items of that name (those of the
// same file when it has any). Empty when there is no identifier or no match.
struct Target {
  std::size_t file;
  int declaration;
};
std::vector<Target> targetsAt(const Files &files, std::size_t file,
                              std::size_t offset);
const Declaration &declarationOf(const Files &files, Target target);

struct Hover {
  std::string markdown;
  Site range;
};
std::optional<Hover> hoverAt(const Files &files, std::size_t file,
                             std::size_t offset);
std::vector<Site> definitionsAt(const Files &files, std::size_t file,
                                std::size_t offset);

// Renaming the symbol at `offset`. `error` is set when it cannot be renamed
// safely; otherwise `name` is the identifier and, when `replacement` is not
// empty, `edits` replace every occurrence of the symbol.
struct RenamePlan {
  std::string error;
  Site name;
  std::string current;
  std::vector<Site> edits;
};
RenamePlan planRename(const Files &files, std::size_t file, std::size_t offset,
                      const std::string &replacement);
} // namespace mettle::lsp
