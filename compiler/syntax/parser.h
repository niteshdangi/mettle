#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"

namespace mettle {
Module parse(const Source &source, Diagnostics &diagnostics);
} // namespace mettle
