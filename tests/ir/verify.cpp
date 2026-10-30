#include "ir/verify.h"
#include "analysis/initialization.h"
#include "analysis/liveness.h"
#include "lowering/scalar.h"
#include "pipeline/compile.h"
#include "semantics/check.h"
#include "syntax/parser.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>

namespace {
using mettle::Type;
using namespace mettle::ir;

Program simple() {
  Instruction constant{
      Op::Constant, {0, Type::I32}, {}, {}, "", {-1, {}}, -1, 0, {}};
  Block block{{constant}, {Exit::Return, {0, Type::I32}}};
  return {{{"main", Type::I32, 0, {}, {block}, 1}}};
}
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
void rejected(const Program &program, const char *expected) {
  mettle::Diagnostics diagnostics;
  require(!verify(program, diagnostics), "malformed IR passed verification");
  require(!diagnostics.empty(), "IR rejection had no diagnostic");
  require(diagnostics.items[0].phase == "internal",
          "IR defect was blamed on source");
  bool found = false;
  for (const auto &item : diagnostics.items)
    found |= item.message.find(expected) != std::string::npos;
  require(found, expected);
}
Program diamond(bool phi) {
  auto program = simple();
  auto &f = program.functions[0];
  f.blocks = {
      {{{Op::Constant, {0, Type::Bool}, {}, {}, "", {-1, {}}, -1, 1, {}}},
       {Exit::Branch, {0, Type::Bool}, 1, 2}},
      {{{Op::Constant, {1, Type::I32}, {}, {}, "", {-1, {}}, -1, 10, {}}},
       {Exit::Jump, {}, 3}},
      {{{Op::Constant, {2, Type::I32}, {}, {}, "", {-1, {}}, -1, 20, {}}},
       {Exit::Jump, {}, 3}},
      {{}, {Exit::Return, {1, Type::I32}}}};
  f.values = 3;
  if (phi) {
    f.blocks[3].instructions.push_back({Op::Phi,
                                        {3, Type::I32},
                                        {{1, Type::I32}, {2, Type::I32}},
                                        {1, 2},
                                        "",
                                        {-1, {}},
                                        -1,
                                        0,
                                        {}});
    f.blocks[3].exit.value = {3, Type::I32};
    f.values = 4;
  }
  return program;
}
void verifierCases() {
  mettle::Diagnostics diagnostics;
  require(verify(simple(), diagnostics), "valid simple CFG rejected");
  auto program = simple();
  program.functions[0].blocks[0].exit = {};
  rejected(program, "terminator");
  program = simple();
  program.functions[0].blocks[0].exit = {Exit::Jump, {}, 99};
  rejected(program, "successor");
  program = simple();
  program.functions[0].blocks[0].exit.value = {99, Type::I32};
  rejected(program, "operand");
  program = simple();
  program.functions[0].blocks[0].exit.value.type = Type::Bool;
  rejected(program, "type");
  rejected(diamond(false), "dominate");
  require(verify(diamond(true), diagnostics), "valid phi CFG rejected");
  program = diamond(true);
  program.functions[0].blocks[3].instructions[0].predecessors = {1, 1};
  rejected(program, "instruction");
  program = simple();
  program.functions[0].blocks[0].instructions[0] = {
      Op::Call, {0, Type::I32}, {}, {}, "", {-1, {}}, 5, 0, {}};
  rejected(program, "callee");
  program = simple();
  program.functions[0].locals.push_back({"x", Type::I32, false, {}});
  program.functions[0].blocks[0].instructions[0] = {
      Op::Load, {0, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}};
  require(verify(program, diagnostics),
          "typed uninitialized load was not structurally valid");
  mettle::analysis::initialization(program, diagnostics);
  require(!diagnostics.empty() && diagnostics.items.back().phase == "type",
          "independent initialization analysis missed uninitialized load");
  program.functions[0].blocks[0].instructions[0].place.fields = {
      mettle::Projection::field(0)};
  rejected(program, "projected place");
  program = simple();
  program.functions[0].locals.push_back({"x", Type::I32, true, {}});
  program.functions[0].blocks[0].instructions[0] = {
      Op::BorrowRead,
      {0, Type::I32, Access::Read},
      {},
      {},
      "",
      {0, {}},
      -1,
      0,
      {}};
  program.functions[0].blocks[0].exit.value = {0, Type::I32, Access::Read};
  rejected(program, "return type");
  program = simple();
  program.functions[0].locals.push_back({"x", Type::I32, true, {}});
  program.functions[0].blocks[0].instructions = {
      {Op::BorrowMut,
       {0, Type::I32, Access::Mut},
       {},
       {},
       "",
       {0, {}},
       -1,
       0,
       {}},
      {Op::Call,
       {1, Type::Unit},
       {{0, Type::I32, Access::Mut}, {0, Type::I32, Access::Mut}},
       {},
       "",
       {-1, {}},
       1,
       0,
       {}},
      {Op::Constant, {2, Type::I32}, {}, {}, "", {-1, {}}, -1, 0, {}}};
  program.functions[0].values = 3;
  program.functions[0].blocks[0].exit.value = {2, Type::I32};
  program.functions.push_back(
      {"both",
       Type::Unit,
       2,
       {{"a", Type::I32, false, {}, mettle::ParameterMode::Mut},
        {"b", Type::I32, false, {}, mettle::ParameterMode::Mut}},
       {{{{Op::Constant, {0, Type::Unit}, {}, {}, "", {-1, {}}, -1, 0, {}}},
         {Exit::Return, {0, Type::Unit}}}},
       1});
  rejected(program, "multiple parameters");
}
void valueLivenessCases() {
  mettle::Diagnostics diagnostics;
  auto branch = diamond(true);
  require(verify(branch, diagnostics), "liveness diamond is invalid");
  auto live = mettle::analysis::valueLiveness(branch.functions[0]);
  require(live.out[1] == std::set<int>{1},
          "first phi edge did not retain its operand");
  require(live.out[2] == std::set<int>{2},
          "second phi edge did not retain its operand");
  require(live.in[3].empty(), "phi operands leaked into successor liveness");

  auto loop = simple();
  auto &function = loop.functions[0];
  function.blocks = {
      {{{Op::Constant, {0, Type::I32}, {}, {}, "", {-1, {}}, -1, 0, {}}},
       {Exit::Jump, {}, 1}},
      {{{Op::Phi,
         {1, Type::I32},
         {{0, Type::I32}, {3, Type::I32}},
         {0, 2},
         "",
         {-1, {}},
         -1,
         0,
         {}},
        {Op::Constant, {2, Type::Bool}, {}, {}, "", {-1, {}}, -1, 1, {}}},
       {Exit::Branch, {2, Type::Bool}, 2, 3}},
      {{{Op::Constant, {3, Type::I32}, {}, {}, "", {-1, {}}, -1, 1, {}}},
       {Exit::Jump, {}, 1}},
      {{}, {Exit::Return, {1, Type::I32}}}};
  function.values = 4;
  require(verify(loop, diagnostics), "liveness loop is invalid");
  live = mettle::analysis::valueLiveness(function);
  require(live.out[0] == std::set<int>{0}, "entry phi operand was not live");
  require(live.out[2] == std::set<int>{3}, "back-edge phi operand was not live");
  require(live.out[1] == std::set<int>{1}, "loop result was not live");
}
void phaseOwnership() {
  mettle::Source source{"memory.mt", "fn main() { -(2147483648) }\n"};
  mettle::Diagnostics diagnostics;
  auto parsed = mettle::parse(source, diagnostics);
  auto *expression = parsed.functions[0].body->children[0].get();
  auto checked = mettle::check(std::move(parsed), diagnostics);
  require(checked.has_value(), "valid syntax failed checking");
  auto moved = std::move(*checked);
  require(moved.facts(*expression).foldedNegativeLiteral,
          "checked facts did not survive owner move");
  require(expression->children[0]->children[0]->text == "2147483648",
          "semantic checking mutated the original literal spelling");
  auto program = mettle::lowering::lower(moved, diagnostics);
  require(verify(program, diagnostics),
          "lowering checked syntax failed verification");
  auto compiled = mettle::pipeline::compile(source, diagnostics);
  require(compiled.has_value(), "in-memory compiler pipeline failed");
  mettle::Diagnostics divergence;
  auto nonreturning = mettle::pipeline::compile(
      {"divergence.mt", "fn stop(): Never { loop {} }\n"
                        "fn inferred() { true && stop() }\n"
                        "fn annotated(): i32 { let _ = true && stop(); 42 }\n"
                        "fn main() { 0 }\n"},
      divergence);
  require(nonreturning.has_value(),
          "unreachable short-circuit merge became an invalid return");
  mettle::Diagnostics invalid;
  require(!mettle::pipeline::compile({"broken.mt", "fn main() { missing }\n"},
                                     invalid),
          "pipeline published invalid source");
  require(invalid.items[0].phase == "name", "pipeline changed rejection phase");
  for (std::string bytes :
       {std::string("\xc0\x80", 2), std::string("\xed\xa0\x80", 3),
        std::string("\xf4\x90\x80\x80", 4), std::string("\xe2\x82", 2)}) {
    mettle::Diagnostics encoding;
    require(!mettle::pipeline::compile({"encoding.mt", bytes}, encoding),
            "in-memory pipeline accepted malformed UTF-8");
    require(encoding.items[0].phase == "lex",
            "encoding rejected outside the source boundary");
  }
  mettle::Diagnostics products;
  auto constructed = mettle::pipeline::compile(
      {"product.mt", "copy type Point { x: i32 }\nfn main() { Point(42).x }\n"},
      products);
  require(constructed.has_value(), "product compilation failed");
  auto malformed = constructed->program();
  for (auto &block : malformed.functions[0].blocks)
    for (auto &instruction : block.instructions)
      if (!instruction.place.fields.empty())
        instruction.place.fields.back() = mettle::Projection::field(999);
  rejected(malformed, "projected place");
  malformed = constructed->program();
  for (auto &block : malformed.functions[0].blocks)
    for (auto &instruction : block.instructions)
      if (instruction.op == Op::Construct)
        instruction.operands.clear();
  rejected(malformed, "operand count");
  mettle::Diagnostics aliases;
  auto aliasSyntax = mettle::parse(
      {"alias.mt", "alias Coordinate = Point\n"
                   "copy type Point { value: i32; "
                   "static fn make(value: i32): Self { Self(value) } }\n"
                   "fn main() { Coordinate::make(42).value }\n"},
      aliases);
  auto aliasChecked = mettle::check(std::move(aliasSyntax), aliases);
  require(aliasChecked.has_value(), "declaration aliases failed checking");
  require(aliasChecked->syntax().aliases[0].target.name == "Point",
          "alias checking changed target syntax");
  const auto &aliasMain = aliasChecked->syntax().functions[0];
  const auto &aliasCall = *aliasMain.body->children[0]->children[0];
  require(aliasCall.children[0]->text == "Coordinate::make",
          "associated lookup rewrote qualified source spelling");
  auto aliasProgram = mettle::lowering::lower(*aliasChecked, aliases);
  aliasChecked.reset();
  require(verify(aliasProgram, aliases),
          "alias/type identities depended on checked syntax lifetime");
}
void ownedValueCases() {
  mettle::Diagnostics diagnostics;
  auto compiled = mettle::pipeline::compile(
      {"owners.mt",
       "type Guard<region r> { counter: mut i32 from r; "
       "drop { *self.counter += 1 } }\n"
       "fn route(value: take Guard, flag: bool): Guard from value { "
       "if flag { value } else { value } }\n"
       "fn consume(value: take Guard) {}\n"
       "fn main() { var counter = 0; "
       "{ let owned = route(Guard(mut counter), true) }; "
       "if counter == 1 { 0 } else { 1 } }\n"},
      diagnostics);
  require(compiled.has_value(), "valid branch ownership rejected");
  auto rejectedOwner = [](Program program, const char *expected) {
    mettle::Diagnostics errors;
    require(!mettle::pipeline::admit(std::move(program), errors),
            "malformed SSA ownership was admitted");
    bool found = false;
    for (const auto &error : errors.items)
      found |= error.phase == "internal" &&
               error.message.find(expected) != std::string::npos;
    require(found, expected);
  };
  auto function = [](Program &program, const char *name) -> Function & {
    auto found = std::find_if(
        program.functions.begin(), program.functions.end(),
        [&](const auto &candidate) { return candidate.name == name; });
    require(found != program.functions.end(), "missing ownership fixture");
    return *found;
  };
  auto duplicated = compiled->program();
  auto &main = function(duplicated, "main");
  auto owned =
      std::find_if(main.locals.begin(), main.locals.end(),
                   [](const auto &local) { return local.name == "owned"; });
  require(owned != main.locals.end(), "missing owned storage");
  int original = static_cast<int>(owned - main.locals.begin());
  int duplicate = static_cast<int>(main.locals.size());
  auto local = *owned;
  local.name = "duplicate";
  ++local.order;
  main.locals.push_back(local);
  bool inserted = false;
  for (auto &block : main.blocks) {
    for (std::size_t i = 0; i < block.instructions.size(); ++i)
      if (block.instructions[i].op == Op::Store &&
          block.instructions[i].place.root == original) {
        auto store = block.instructions[i];
        store.result.id = main.values++;
        store.place.root = duplicate;
        block.instructions.insert(block.instructions.begin() + i + 1, store);
        inserted = true;
        break;
      }
    if (inserted)
      break;
  }
  require(inserted, "missing ownership transfer");
  auto discarded = duplicated;
  for (auto &block : function(discarded, "main").blocks)
    for (auto &instruction : block.instructions)
      if (instruction.op == Op::Store && instruction.place.root == duplicate)
        instruction = {Op::Declare, instruction.result, {}, {},
                       "",          {original, {}},     -1, 0,
                       {}};
  rejectedOwner(std::move(duplicated), "already have been consumed");
  rejectedOwner(std::move(discarded), "discards live owned storage");
  auto missingCleanup = compiled->program();
  auto &missingMain = function(missingCleanup, "main");
  int scope = missingMain.locals[original].scope;
  for (auto &block : missingMain.blocks)
    for (auto &instruction : block.instructions)
      if (instruction.op == Op::ScopeExit && instruction.number == scope)
        instruction = {
            Op::Constant, instruction.result, {}, {}, "", {-1, {}}, -1, 0, {}};
  rejectedOwner(std::move(missingCleanup), "without scope cleanup");

  auto branch = compiled->program();
  auto &route = function(branch, "route");
  auto type = route.result;
  route.locals.resize(2);
  route.scopes = {{-1}};
  route.values = 3;
  route.blocks = {
      {{{Op::Move, {0, type}, {}, {}, "", {0, {}}, -1, 0, {}},
        {Op::Load, {1, Type::Bool}, {}, {}, "", {1, {}}, -1, 0, {}}},
       {Exit::Branch, {1, Type::Bool}, 1, 2}},
      {{}, {Exit::Jump, {}, 3}},
      {{}, {Exit::Jump, {}, 3}},
      {{{Op::Phi,
         {2, type},
         {{0, type}, {0, type}},
         {1, 2},
         "",
         {-1, {}},
         -1,
         0,
         {}}},
       {Exit::Return, {2, type}}}};
  mettle::Diagnostics valid;
  require(mettle::pipeline::admit(branch, valid).has_value(),
          "mutually exclusive phi transfers rejected");
  auto consume = std::find_if(
      branch.functions.begin(), branch.functions.end(),
      [](const auto &candidate) { return candidate.name == "consume"; });
  route.blocks[1].instructions.push_back(
      {Op::Call,
       {3, Type::Unit},
       {{0, type}},
       {},
       "",
       {-1, {}},
       static_cast<int>(consume - branch.functions.begin()),
       0,
       {}});
  route.values = 4;
  rejectedOwner(std::move(branch), "already have been consumed");
}
void variantRefinementCases() {
  mettle::Diagnostics diagnostics;
  auto compiled = mettle::pipeline::compile(
      {"variants.mt",
       "copy enum Value { Empty; Held(i32) }\n"
       "fn unpack(value: Value) { match value { Value::Empty => 0, "
       "Value::Held(payload) => payload } }\n"
       "fn main() { unpack(Value::Held(42)) }\n"},
      diagnostics);
  require(compiled.has_value(), "valid tagged pattern CFG rejected");
  auto malformed = compiled->program();
  for (auto &function : malformed.functions)
    if (function.name == "unpack")
      for (auto &block : function.blocks)
        for (auto &instruction : block.instructions)
          if (instruction.op == Op::VariantTest)
            instruction = {Op::Constant,
                           instruction.result,
                           {},
                           {},
                           "",
                           {-1, {}},
                           -1,
                           1,
                           {}};
  mettle::Diagnostics rejectedTag;
  require(!mettle::pipeline::admit(std::move(malformed), rejectedTag),
          "unrefined variant payload was admitted");
  require(std::any_of(rejectedTag.items.begin(), rejectedTag.items.end(),
                      [](const auto &item) {
                        return item.phase == "internal" &&
                               item.message.find("tag refinement") !=
                                   std::string::npos;
                      }),
          "missing variant-refinement diagnostic");
  malformed = compiled->program();
  for (auto &function : malformed.functions)
    for (auto &block : function.blocks)
      for (auto &instruction : block.instructions)
        if (instruction.op == Op::VariantConstruct)
          instruction.number = 999;
  rejected(malformed, "variant constructor");
}
void conditionalUnpinProofCases() {
  mettle::Diagnostics diagnostics;
  auto compiled = mettle::pipeline::compile(
      {"unpin.mt",
       "interface Ready {}\n"
       "impl i32 implements Ready {}\n"
       "type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }\n"
       "unsafe impl<T: Ready> Wrapper<T> implements Unpin {}\n"
       "fn main() { var handle = core::pin::pin("
       "Wrapper(42,core::marker::PhantomPinned)); "
       "let value = handle.get_mut(); 0 }\n"},
      diagnostics);
  require(compiled.has_value(), "validated conditional Unpin rejected");
  auto program = compiled->program();
  bool proof = false;
  for (const auto &function : program.functions)
    for (const auto &block : function.blocks)
      for (const auto &instruction : block.instructions)
        for (auto [subject, runtime] : instruction.unpinProofs) {
          (void)subject;
          proof = true;
          require(!program.types->isUnpin(runtime),
                  "conditional proof became an unconditional type flag");
        }
  require(proof, "conditional pin access lost its proof request");
  mettle::Diagnostics unproven;
  require(!mettle::pipeline::admit(std::move(program), unproven),
          "conditional Unpin was admitted without its semantic proof context");
}
} // namespace
int main() {
  try {
    verifierCases();
    valueLivenessCases();
    phaseOwnership();
    ownedValueCases();
    variantRefinementCases();
    conditionalUnpinProofCases();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  std::cout
      << "IR verification, independent analysis and phase ownership passed\n";
}
