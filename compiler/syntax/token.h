#pragma once

#include "source/source.h"
#include <string>
#include <string_view>
#include <vector>

namespace mettle {
enum class TokenKind {
  Word,
  Integer,
  Symbol,
  Space,
  Comment,
  Newline,
  End,
  Character,
  Byte,
  Floating,
  QuotedWord,
  Text,
  PrefixedText
};
struct Token {
  TokenKind kind;
  Span span;
  std::string text;
};

bool isReservedWord(std::string_view word);
bool isUnsupportedExpressionWord(std::string_view word);
int binaryPrecedence(std::string_view operation);
bool isAssignmentOperator(std::string_view operation);
std::string_view compoundSymbol(std::string_view input);
} // namespace mettle
