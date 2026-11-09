#pragma once
#include <cstdint>
#include <optional>

#include "diagnostics/diagnostics.h"
#include "syntax/token.h"

namespace mettle {
std::optional<std::uint32_t> characterLiteral(std::string_view text, bool byte,
                                              Diagnostics &diagnostics,
                                              Span span);
// Decodes a text literal token (with quotes) to UTF-8 bytes.
std::optional<std::string> textLiteral(std::string_view text,
                                       Diagnostics &diagnostics, Span span);
std::vector<Token> tokenize(const Source &source, Diagnostics &diagnostics);
} // namespace mettle
