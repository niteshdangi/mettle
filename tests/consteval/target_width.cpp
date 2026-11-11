// Required constants are a function of the selected target's pointer width,
// never of the host's. The driver admits only 64-bit targets today, so the
// 32-bit contract is exercised through the checker's target description.
#include "consteval/evaluate.h"
#include "semantics/check.h"
#include "syntax/parser.h"
#include "types/machine.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
bool accepted(const std::string &text, unsigned pointerBits,
              std::string *message = nullptr,
              std::uint64_t *firstStatic = nullptr) {
  mettle::Diagnostics diagnostics;
  auto parsed = mettle::parse({"constants.mt", text}, diagnostics);
  mettle::TargetFacts target;
  target.pointerBits = pointerBits;
  auto checked = mettle::check(std::move(parsed), diagnostics, false, target);
  if (message && !diagnostics.items.empty())
    *message = diagnostics.items[0].message;
  if (firstStatic && checked && diagnostics.empty()) {
    const auto &statics = checked->statics();
    if (statics.empty() || !statics.front().initializer)
      return false;
    const auto &value = *statics.front().initializer;
    if (value.kind != mettle::StaticConstant::Kind::Scalar ||
        value.scalar.negative || value.scalar.magnitude[1] != 0)
      return false;
    *firstStatic = value.scalar.magnitude[0];
  }
  return checked.has_value() && diagnostics.empty();
}

int failures = 0;
void expect(bool condition, const char *what) {
  if (!condition) {
    std::cerr << "FAILED: " << what << '\n';
    ++failures;
  }
}

mettle::NodeOwner expression(const std::string &text) {
  mettle::Diagnostics diagnostics;
  auto module = mettle::parse(
      {"imported-constant.mt", "fn body() { " + text + " }\n"}, diagnostics);
  if (!diagnostics.empty() || module.functions.empty())
    throw std::runtime_error("invalid constant test expression");
  return std::move(module.functions.front().body);
}

class ImportedHost : public mettle::evaluation::Host {
public:
  mettle::evaluation::CheckedFunction function;
  std::string phase, message;

  void report(const std::string &reportedPhase, mettle::Span,
              const std::string &reportedMessage) override {
    phase = reportedPhase;
    message = reportedMessage;
  }
  mettle::evaluation::Lookup lookup(const mettle::Node &name,
                                    std::size_t &) override {
    mettle::evaluation::Lookup result;
    if (name.text == "imported") {
      result.kind = mettle::evaluation::Lookup::Kind::Function;
      result.checkedFunction = &function;
    }
    return result;
  }
};

void importedConstants() {
  using namespace mettle;
  auto body = expression("value as usize");
  auto defaultValue = expression("4294967297u64");
  ImportedHost host;
  evaluation::CheckedFunction::Parameter parameter;
  parameter.name = "value";
  parameter.shape.type = Type::U64;
  parameter.defaultValue = defaultValue.get();
  host.function.parameters.push_back(std::move(parameter));
  host.function.result.type = Type::Usize;
  host.function.body = body.get();
  auto call = expression("imported()");
  evaluation::Options options;
  options.pointerBits = 32;
  auto result = evaluation::evaluate(host, options, *call, {});
  expect(result.value && result.value->number.magnitude[0] == 1,
         "imported const defaults and target-width casts need no declaration");
  options.pointerBits = 64;
  result = evaluation::evaluate(host, options, *call, {});
  expect(result.value && result.value->number.magnitude[0] == 4294967297ULL,
         "imported const calls preserve the selected 64-bit target");

  host.function.unsafeFunction = true;
  result = evaluation::evaluate(host, options, *call, {});
  expect(!result.value && host.phase == "unsafe",
         "imported const calls preserve unsafe requirements");
  auto allowed = expression("unsafe { imported() }");
  result = evaluation::evaluate(host, options, *allowed, {});
  expect(result.value && result.value->number.magnitude[0] == 4294967297ULL,
         "an unsafe block permits an imported unsafe const call");
  host.function.unsafeFunction = false;

  auto overflow = expression("4294967295usize + 1usize");
  host.function.body = overflow.get();
  options.pointerBits = 32;
  result = evaluation::evaluate(host, options, *call, {});
  expect(!result.value && host.phase == "constant" &&
             host.message.find("overflow") != std::string::npos,
         "imported const arithmetic uses the ordinary checked overflow policy");

  auto recursive = expression("imported()");
  host.function.body = recursive.get();
  options.callDepth = 2;
  result = evaluation::evaluate(host, options, *call, {});
  expect(!result.value && host.phase == "limit" &&
             host.message.find("call depth") != std::string::npos,
         "source and imported const calls share the depth budget");
}

void integerMethods() {
  using namespace mettle;
  const std::array fullProduct{integerMaximum(Type::U128),
                               integerMaximum(Type::U128)};
  auto result = evaluateIntegerMethod("overflowing_mul", Type::U128,
                                      fullProduct, 64, true);
  expect(result && result->value == integerLiteral(1) && result->failed,
         "full-width multiplication retains wrapped bits and overflow");
  result =
      evaluateIntegerMethod("checked_mul", Type::U128, fullProduct, 64, true);
  expect(result && result->failed,
         "checked full-width multiplication reports absence");
  bool overflow = false;
  try {
    (void)evaluateIntegerConstant("*", Type::U128, fullProduct[0],
                                  fullProduct[1]);
  } catch (const std::invalid_argument &) {
    overflow = true;
  }
  expect(overflow, "ordinary full-width multiplication still rejects overflow");

  const std::array hugePower{integerLiteral(2), integerMaximum(Type::U32)};
  result =
      evaluateIntegerMethod("overflowing_pow", Type::U128, hugePower, 64, true);
  expect(result && result->value == integerLiteral(0) && result->failed,
         "wrapped-zero powers retain overflow at maximum exponent");
  const std::array exactPower{integerLiteral(-2), integerLiteral(127)};
  result = evaluateIntegerMethod("overflowing_pow", Type::I128, exactPower, 64,
                                 true);
  expect(result && result->value == integerMinimum(Type::I128) &&
             !result->failed,
         "negative powers can exactly produce the signed minimum");

  const std::array maximum{integerMaximum(Type::U128)};
  result = evaluateIntegerMethod("isqrt", Type::U128, maximum, 64, true);
  NumericLiteral root;
  root.magnitude[0] = ~std::uint64_t{0};
  expect(result && result->value == root,
         "u128 square root rounds down at the full-width boundary");
  const std::array logarithm{maximum[0], integerLiteral(2)};
  result = evaluateIntegerMethod("ilog", Type::U128, logarithm, 64, true);
  expect(result && result->type == Type::U32 &&
             result->value == integerLiteral(127),
         "u128 integer logarithms return their exact u32 result");

  const std::array endian{integerLiteral(0x0102)};
  result = evaluateIntegerMethod("from_be", Type::U16, endian, 64, true);
  expect(result && result->value == integerLiteral(0x0201),
         "big-endian conversion swaps on little-endian targets");
  result = evaluateIntegerMethod("from_be", Type::U16, endian, 64, false);
  expect(result && result->value == integerLiteral(0x0102),
         "big-endian conversion is unchanged on big-endian targets");
}
} // namespace

int main() {
  integerMethods();
  const std::string literal = "const N: usize = 4294967296;\n";
  expect(accepted(literal, 64), "2^32 fits usize on a 64-bit target");
  expect(!accepted(literal, 32), "2^32 exceeds usize on a 32-bit target");

  const std::string arithmetic = "const N: usize = 4294967295usize + 1;\n";
  std::string message;
  expect(accepted(arithmetic, 64), "usize sum is exact on a 64-bit target");
  expect(!accepted(arithmetic, 32, &message) &&
             message.find("overflow") != std::string::npos,
         "usize sum overflows on a 32-bit target");

  const std::string length = "const fn big(): usize { 4294967295usize + 1 }\n"
                             ""
                             "static S: usize = big();\n";
  expect(accepted(length, 64), "const fn usize result on 64 bits");
  expect(!accepted(length, 32), "const fn usize overflow on 32 bits");

  const std::string cast = "const fn narrow(x: u64): usize { x as usize }\n"
                           "static S: usize = narrow(4294967297);\n"
                           "static K: bool = narrow(4294967297) == 1;\n";
  std::uint64_t value = 0;
  expect(accepted(cast, 64, nullptr, &value) && value == 4294967297ULL,
         "u64 to usize keeps all bits on 64 bits");
  expect(accepted(cast, 32, nullptr, &value) && value == 1,
         "u64 to usize truncates on 32 bits");
  importedConstants();
  return failures == 0 ? 0 : 1;
}
