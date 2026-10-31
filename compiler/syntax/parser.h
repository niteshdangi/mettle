#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"
#include <vector>

namespace mettle {
// Parses the item syntax of one source. Products and implementations still own
// their member functions, so attribute expansion can add or remove items
// before `completeDeclarations` flattens them into module-level function lists.
Module parseDeclarations(const Source &source, Diagnostics &diagnostics);
Module parseDeclarations(const Source &source, std::vector<Token> tokens,
                         Diagnostics &diagnostics);
void completeDeclarations(Module &module);
Module parse(const Source &source, Diagnostics &diagnostics);
Module parse(const Source &source, std::vector<Token> tokens,
             Diagnostics &diagnostics);
} // namespace mettle
