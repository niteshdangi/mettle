#include "backend/llvm/lower.h"
#include "pipeline/compile.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/raw_ostream.h"
#include <algorithm>
#include <iostream>

namespace {
using namespace mettle;

constexpr auto scopes = R"(
type Guard { tag: i32; drop {} }
type Pair { tag: i32; first: Guard; second: Guard; drop {} }
enum Owned { Empty; One(Guard); Two(Guard, Guard) }
type Builder {
    tag: i32
    first: Guard
    second: Guard
    init(fail: bool) throws i32 {
        self.tag = 1199
        self.first = Guard(1121)
        if fail { throw 7 }
        self.second = Guard(1122)
    }
    drop {}
}
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self::Item?; } } }
type Walker {
    held: Guard
    n: i32
    max: i32
    drop {}
}
impl Walker implements core::iter::Iterator {
    type Item = Guard
    mut fn next(): Guard? {
        if self.n < self.max { self.n += 1; present(Guard(self.held.tag + self.n)) } else { none }
    }
}
fn walk(tag: i32, count: i32): Walker { Walker(Guard(tag), 0, count) }
fn test(value: read Guard, answer: bool): bool { answer }
fn statements(): Unit {
    let held = Guard(101)
    Guard(102)
    Guard(103);
}
fn conditional(): Unit {
    if test(Guard(201), true) { Guard(202); } else { Guard(203); }
}
fn conditions(): Unit {
    var count = 0
    while test(Guard(301 + count), count < 2) {
        Guard(310 + count)
        count += 1
    }
}
fn short_circuit(): Unit {
    let both = test(Guard(401), true) && test(Guard(402), true)
    Guard(403)
    let skipped_and = test(Guard(404), false) && test(Guard(405), true)
    Guard(406)
    let skipped_or = test(Guard(407), true) || test(Guard(408), false)
    Guard(409)
    let either = test(Guard(410), false) || test(Guard(411), true)
    Guard(412);
}
fn discarded_tail(): Unit {
    {
        let held = Guard(501)
        Guard(502)
    };
    Guard(503);
}
fn order(): Unit {
    let first = Guard(601)
    let pair = Pair(602, Guard(603), Guard(604))
    let last = Guard(605)
}
fn returns(): Guard {
    let held = Guard(701)
    return Guard(702)
}
fn returned(): Unit {
    let result = returns()
    Guard(703);
}
fn early(): Unit {
    let outer = Guard(711)
    { let inner = Guard(712); return }
}
fn jumps(): Unit {
    let outer = Guard(801)
    var count = 0
    while test(Guard(810 + count), count < 3) {
        let iteration = Guard(820 + count)
        count += 1
        if count == 1 { let branch = Guard(830); continue }
        if count == 2 { let branch = Guard(831); break }
    }
    Guard(840);
}
fn labeled_results(): Unit {
    let result = label outer: loop {
        let outer = Guard(1001)
        loop {
            let inner = Guard(1002)
            break label outer Guard(1003)
        }
    }
    Guard(1004);
}
fn labeled_continues(): Unit {
    var count = 0
    label outer: while count < 2 {
        let first = Guard(1010 + count)
        count += 1
        loop {
            let second = Guard(1020 + count)
            continue label outer
        }
    }
    Guard(1030);
}
fn variants(): Unit {
    let one = Owned::One(Guard(1101))
    let two = Owned::Two(Guard(1102), Guard(1103))
    let empty = Owned::Empty
    match take one {
        Owned::Empty => {},
        Owned::One(held) => {},
        Owned::Two(_, _) => {}
    }
}
fn constructors(): Unit {
    let _ = capture Builder(true)
    let _ = capture Builder(false)
}
fn array_rest(): Unit {
    let values = [Guard(1131), Guard(1132), Guard(1133)]
    match take values { [first, rest @ ..] => {} }
}
fn iterations(): Unit {
    for item in walk(1210, 2) { Guard(1201); }
    for item in walk(1220, 3) { break }
    var skipped = 0
    for item in walk(1230, 2) { skipped += 1; continue }
}
fn iterated_return(): Unit {
    for item in walk(1240, 2) { return }
}
fn main() {
    statements()
    conditional()
    conditions()
    short_circuit()
    discarded_tail()
    order()
    returned()
    early()
    jumps()
    labeled_results()
    labeled_continues()
    variants()
    constructors()
    array_rest()
    iterations()
    iterated_return()
    0
}
)";

constexpr auto arguments = R"(
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self::Item?; } } }
type Guard { tag: i32; drop {} }
type Walker {
    held: Guard
    n: i32
    drop {}
}
impl Walker implements core::iter::Iterator {
    type Item = Guard
    mut fn next(): Guard? {
        if self.n < 2 { self.n += 1; present(Guard(907)) } else { none }
    }
}
type Panicker {
    tag: i32
    drop { let zero = 0; let trapped = 1 / zero }
}
fn explode(): Guard {
    loop {
        let held = Panicker(902)
        break Guard(903)
    }
}
fn consume(first: take Guard, second: take Guard): Unit {
    Guard(904);
}
fn arguments(): Unit {
    let held = Guard(901)
    for item in Walker(Guard(906), 0) {
        consume(Guard(905), explode())
    }
}
fn main() { arguments(); 0 }
)";

ir::Function external(std::string name, Type result, std::size_t parameters) {
  ir::Function function{};
  function.name = name;
  function.externalName = std::move(name);
  function.result = result;
  function.parameters = parameters;
  for (std::size_t i = 0; i < parameters; ++i)
    function.locals.push_back({"value", Type::I32, false, {}});
  return function;
}

void observe(ir::Function &function, int recorder) {
  ir::Value tag{function.values++, Type::I32};
  ir::Value recorded{function.values++, Type::Unit};
  function.blocks[0].instructions.insert(
      function.blocks[0].instructions.begin(),
      {{ir::Op::Load, tag, {}, {}, "", {0, {Projection::field(0)}}, -1, 0, {}},
       {ir::Op::Call, recorded, {tag}, {}, "", {}, recorder, 0, {}}});
}

bool instrument(ir::Program &program, bool unwind) {
  int recorder = static_cast<int>(program.functions.size());
  program.functions.push_back(
      external("mettle_test_cleanup_source_record", Type::Unit, 1));
  int checker = static_cast<int>(program.functions.size());
  program.functions.push_back(
      external("mettle_test_cleanup_source_result", Type::I32, 2));
  for (auto &function : program.functions)
    if (function.name == "Guard.drop" || function.name == "Pair.drop" ||
        function.name == "Builder.drop" || function.name == "Panicker.drop")
      observe(function, recorder);
  auto main = std::find_if(
      program.functions.begin(), program.functions.end(),
      [](const auto &function) { return function.name == "main"; });
  if (main == program.functions.end())
    return false;
  ir::Value caught;
  if (unwind) {
    for (auto &block : main->blocks)
      for (auto &instruction : block.instructions)
        if (instruction.op == ir::Op::Call &&
            program.functions[instruction.callee].name == "arguments") {
          caught = instruction.result;
          caught.type = Type::I32;
          instruction.op = ir::Op::CatchCall;
          instruction.result = caught;
        }
    if (caught.id < 0)
      return false;
    for (const auto &block : main->blocks) {
      for (const auto &instruction : block.instructions)
        for (auto operand : instruction.operands)
          if (operand.id == caught.id)
            return false;
      if (block.exit.value.id == caught.id)
        return false;
    }
  }
  for (auto &block : main->blocks)
    if (block.exit.kind == ir::Exit::Return) {
      ir::Value mode{main->values++, Type::I32};
      ir::Value checked{main->values++, Type::I32};
      block.instructions.push_back(
          {ir::Op::Constant, mode, {}, {}, "", {}, -1, unwind ? 1 : 0, {}});
      block.instructions.push_back({ir::Op::Call,
                                    checked,
                                    {unwind ? caught : block.exit.value, mode},
                                    {},
                                    "",
                                    {},
                                    checker,
                                    0,
                                    {}});
      block.exit.value = checked;
    }
  return true;
}
} // namespace

int main(int argc, char **) {
  using namespace mettle;
  bool unwind = argc > 1;
  Source source{unwind ? "cleanup-source-argument-unwind.mt"
                       : "cleanup-source-scopes.mt",
                unwind ? arguments : scopes};
  Diagnostics diagnostics;
  auto compiled = pipeline::compile(source, diagnostics);
  if (!compiled) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  // Only test observers and an IR catch boundary are injected. Source scopes,
  // moves, temporary materialization, and cleanup operations remain unchanged.
  auto program = compiled->program();
  if (!instrument(program, unwind)) {
    std::cerr << "source trace instrumentation could not identify its entry\n";
    return 1;
  }
  auto verified = pipeline::admit(std::move(program), diagnostics);
  if (!verified) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  llvm::LLVMContext context;
  auto module = backend::lower(*verified, context, true);
  if (llvm::verifyModule(*module, &llvm::errs()))
    return 1;
  llvm::outs() << "; Instrumented source-IR trace; not source extern syntax.\n";
  module->print(llvm::outs(), nullptr);
}
