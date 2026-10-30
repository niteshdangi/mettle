// Required constants are a function of the selected target's pointer width,
// never of the host's. The driver admits only 64-bit targets today, so the
// 32-bit contract is exercised through the checker's target description.
#include "semantics/check.h"
#include "syntax/parser.h"
#include <iostream>
#include <string>

namespace {
bool accepted(const std::string &text, unsigned pointerBits,
              std::string *message = nullptr) {
  mettle::Diagnostics diagnostics;
  auto parsed = mettle::parse({"constants.mt", text}, diagnostics);
  mettle::TargetFacts target;
  target.pointerBits = pointerBits;
  auto checked = mettle::check(std::move(parsed), diagnostics, false, target);
  if (message && !diagnostics.items.empty())
    *message = diagnostics.items[0].message;
  return checked.has_value() && diagnostics.empty();
}

int failures = 0;
void expect(bool condition, const char *what) {
  if (!condition) {
    std::cerr << "FAILED: " << what << '\n';
    ++failures;
  }
}
} // namespace

int main() {
  const std::string literal = "const N: usize = 4294967296;\n";
  expect(accepted(literal, 64), "2^32 fits usize on a 64-bit target");
  expect(!accepted(literal, 32), "2^32 exceeds usize on a 32-bit target");

  const std::string arithmetic =
      "const N: usize = 4294967295usize + 1;\n";
  std::string message;
  expect(accepted(arithmetic, 64), "usize sum is exact on a 64-bit target");
  expect(!accepted(arithmetic, 32, &message) &&
             message.find("overflow") != std::string::npos,
         "usize sum overflows on a 32-bit target");

  const std::string length =
      "const fn big(): usize { 4294967295usize + 1 }\n"
      ""
      "static S: usize = big();\n";
  expect(accepted(length, 64), "const fn usize result on 64 bits");
  expect(!accepted(length, 32), "const fn usize overflow on 32 bits");

  const std::string cast =
      "const fn narrow(x: u64): usize { x as usize }\n"
      "static S: usize = narrow(4294967297);\n"
      "static K: bool = narrow(4294967297) == 1;\n";
  expect(accepted(cast, 64), "u64 to usize keeps all bits on 64 bits");
  expect(accepted(cast, 32), "u64 to usize truncates on 32 bits");
  return failures == 0 ? 0 : 1;
}
