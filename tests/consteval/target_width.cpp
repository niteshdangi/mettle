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
              std::uint64_t *firstStatic = nullptr, bool littleEndian = true) {
  mettle::Diagnostics diagnostics;
  auto parsed = mettle::parse({"constants.mt", text}, diagnostics);
  mettle::TargetFacts target;
  target.pointerBits = pointerBits;
  target.littleEndian = littleEndian;
  auto checked = mettle::check(std::move(parsed), diagnostics, false, target);
  if (message && !diagnostics.items.empty())
    *message = diagnostics.items[0].message;
  if (firstStatic && checked && diagnostics.empty()) {
    const auto &statics = checked->statics();
    if (statics.empty() || !statics.front().initializer)
      return false;
    const auto &value = *statics.front().initializer;
    if ((value.kind != mettle::StaticConstant::Kind::Scalar &&
         value.kind != mettle::StaticConstant::Kind::Pointer) ||
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
  std::uint64_t indexed = 0;
  expect(accepted("enum Event<T> { Ready(T); Pending }\n"
                  "extend<T> Event<T> { const fn is_ready(): bool { "
                  "match self { Event.Ready(value) => true, "
                  "Event.Pending => false } } }\n"
                  "const VALUE: bool = Event<i32>.Ready(3).is_ready() && "
                  "!Event<i32>.Pending.is_ready();\n",
                  64, nullptr, &indexed) &&
             indexed == 1,
         "generic enum constants retain owner arguments through method calls");
  expect(accepted("type Payload { value: i32 }\n"
                  "enum Event<T> { Ready(T); Pending }\n"
                  "const fn inspect(read event: Event<Payload>): i32 { "
                  "match event { Event.Ready(payload) => payload.value, "
                  "Event.Pending => 0 } }\n"
                  "const fn run(): i32 { "
                  "let event = Event<Payload>.Ready(Payload(42)); "
                  "inspect(read event) }\n"
                  "const VALUE: i32 = run();\n",
                  64, nullptr, &indexed) &&
             indexed == 42,
         "constant read matches retain borrowed non-Copy variant payloads");
  expect(accepted("copy type Callbacks { callback: unsafe fn(i32): i32 }\n"
                  "unsafe fn raw(value: i32): i32 { value }\n"
                  "const fn table(): Callbacks { Callbacks(raw) }\n"
                  "static TABLE: Callbacks = table();\n",
                  64),
         "constant aggregate calls retain unsafe callback relocations");
  std::string callbackError;
  expect(!accepted("copy type Callbacks { callback: fn(i32): i32 }\n"
                   "unsafe fn raw(value: i32): i32 { value }\n"
                   "const fn table(): Callbacks { Callbacks(raw) }\n"
                   "static TABLE: Callbacks = table();\n",
                   64, &callbackError) &&
             callbackError.find("unsafe fn") != std::string::npos,
         "constant callback aggregates cannot erase unsafe-call requirements");
  expect(accepted("enum Tag { First, Last }\n"
                  "const N: u8 = Tag.Last as u8;\n",
                  64, nullptr, &indexed) &&
             indexed == 1,
         "fieldless enum constant casts preserve variant ordinal");
  expect(accepted("enum Tag { First = 7, Last = 42 }\n"
                  "const N: u8 = Tag.Last as u8;\n",
                  64, nullptr, &indexed) &&
             indexed == 42,
         "fieldless enum constant casts preserve explicit discriminants");
  expect(accepted("const fn at(i: i32): i32 { "
                  "let values = [11, 23]; values[i] }\n"
                  "const N: i32 = at(1);\n",
                  64, nullptr, &indexed) &&
             indexed == 23,
         "checked i32 indexing executes in required constants");
  expect(accepted("const fn at(): i32 { [11, 23][1i32] }\n"
                  "const N: i32 = at();\n",
                  64, nullptr, &indexed) &&
             indexed == 23,
         "checked i32 indexing executes on constant array temporaries");
  std::string indexError;
  expect(!accepted("const fn at(i: i32): i32 { "
                   "let values = [11, 23]; values[i] }\n"
                   "const N: i32 = at(-1);\n",
                   64, &indexError) &&
             indexError.find("out of bounds") != std::string::npos,
         "negative checked i32 constant index remains out of bounds");
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
  const std::string memory =
      "const fn bytes(): u32 { var data = [1u8, 2u8, 3u8, 4u8, 5u8]; "
      "let p = core.ptr.from_mut(mut data).cast<u8>(); "
      "unsafe { core.ptr.read_unaligned(p.add(1usize).cast<u32>()) } }\n"
      "const VALUE: u32 = bytes();\n";
  for (auto width : {32u, 64u}) {
    const std::string pointerBits =
        "const fn from_bits(value: isize): ptr<read u8> { "
        "unsafe { core.mem.transmute<ptr<read u8>>(value) } }\n"
        "const VALUE: ptr<read u8> = from_bits(";
    for (auto input : {-42, -1, 0, 42}) {
      auto expected = static_cast<std::uint64_t>(input);
      if (width == 32)
        expected = static_cast<std::uint32_t>(input);
      expect(accepted(pointerBits + std::to_string(input) + "isize);\n", width,
                      nullptr, &value) &&
                 value == expected,
             "integer-to-pointer constant transmute retains target-width bits");
    }
    auto minimum = width == 32 ? "-2147483648" : "-9223372036854775808";
    expect(
        accepted(pointerBits + minimum + "isize);\n", width, nullptr, &value) &&
            value == (std::uint64_t{1} << (width - 1)),
        "signed-minimum pointer transmute retains the target sign bit");
    expect(accepted(memory, width, nullptr, &value) && value == 0x05040302,
           "unaligned constant loads use little-endian target bytes");
    expect(accepted(memory, width, nullptr, &value, false) &&
               value == 0x02030405,
           "unaligned constant loads use big-endian target bytes");
  }
  return failures == 0 ? 0 : 1;
}
