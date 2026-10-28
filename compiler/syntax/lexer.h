#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/token.h"

namespace mettle {
std::vector<Token> tokenize(const Source &source, Diagnostics &diagnostics);
} // namespace mettle
