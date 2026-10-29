#pragma once
#include <cstdint>
#include <optional>

#include "diagnostics/diagnostics.h"
#include "syntax/token.h"

namespace mettle {
std::optional<std::uint32_t> characterLiteral(std::string_view text, bool byte,
                                              Diagnostics &diagnostics,
                                              Span span);
std::vector<Token> tokenize(const Source &source, Diagnostics &diagnostics);
} // namespace mettle
