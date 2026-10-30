#include "syntax/token.h"
#include <algorithm>
#include <initializer_list>

namespace mettle {
namespace {
bool contains(std::initializer_list<std::string_view> values,
              std::string_view value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}
} // namespace
bool isReservedWord(std::string_view word) {
  return contains(
      {"fn",     "type",      "copy",    "let",     "var",        "read",
       "mut",    "take",      "if",      "else",    "while",      "loop",
       "break",  "continue",  "return",  "true",    "false",      "pub",
       "enum",   "interface", "throws",  "throw",   "try",        "capture",
       "match",  "none",      "present", "success", "failure",    "async",
       "await",  "for",       "in",      "module",  "import",     "unsafe",
       "extern", "static",    "const",   "init",    "drop",       "heap",
       "shared", "weak",      "local",   "pinned",  "as",         "alias",
       "label",  "union",     "where",   "region",  "implements", "receiver",
       "macro",  "_"},
      word);
}
bool isUnsupportedExpressionWord(std::string_view word) {
  return contains({"read",      "mut",     "take",    "heap",   "shared",
                   "local",     "weak",    "pinned",  "match",  "none",
                   "present",   "success", "failure", "try",    "capture",
                   "throw",     "async",   "await",   "for",    "fn",
                   "unsafe",    "type",    "copy",    "pub",    "enum",
                   "interface", "module",  "import",  "extern", "const",
                   "static",    "union",   "alias",   "macro",  "label"},
                  word);
}
int binaryPrecedence(std::string_view op) {
  if (op == ".." || op == "..=")
    return 1;
  if (op == "??")
    return 2;
  if (op == "||")
    return 3;
  if (op == "&&")
    return 4;
  if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" ||
      op == ">=")
    return 5;
  if (op == "|")
    return 6;
  if (op == "^")
    return 7;
  if (op == "&")
    return 8;
  if (op == "<<" || op == ">>")
    return 9;
  if (op == "+" || op == "-")
    return 10;
  if (op == "*" || op == "/" || op == "%")
    return 11;
  return 0;
}
bool isAssignmentOperator(std::string_view op) {
  return contains(
      {"=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="}, op);
}
std::string_view compoundSymbol(std::string_view input) {
  for (std::string_view symbol :
       {"...", "..=", "..", ">>=", "<<=", "==", "!=", "<=", ">=",
        "&&",  "||",  "+=", "-=",  "*=",  "/=", "%=", "&=", "|=",
        "^=",  "<<",  ">>", "->",  "=>",  "?.", "??"})
    if (input.starts_with(symbol))
      return symbol;
  return {};
}
} // namespace mettle
