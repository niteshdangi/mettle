#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"

namespace mettle {
// Parses the item syntax of one source. Products and implementations still own
// their member functions, so attribute expansion can add or remove items
// before `completeDeclarations` flattens them into module-level function lists.
Module parseDeclarations(const Source &source, Diagnostics &diagnostics);
void completeDeclarations(Module &module);
Module parse(const Source &source, Diagnostics &diagnostics);

// Reuses tokenization while native parsing determines each fragment boundary.
class FragmentParser {
public:
  explicit FragmentParser(std::string text);
  ~FragmentParser();
  std::optional<std::size_t> end(std::string_view kind, std::size_t begin);

private:
  struct Impl;
  std::unique_ptr<Impl> impl;
};
} // namespace mettle
