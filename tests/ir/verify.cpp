#include "ir/verify.h"
#include "analysis/initialization.h"
#include "analysis/loans.h"
#include "analysis/origins.h"
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
void floatingCarrierCases() {
  auto program = simple();
  Instruction instruction;
  instruction.op = Op::Constant;
  instruction.result = {1, Type::F32};
  instruction.numeric = mettle::NumericLiteral{};
  instruction.numeric->floatingBits = 0x80000000u;
  program.functions[0].blocks[0].instructions.push_back(instruction);
  program.functions[0].values = 2;
  mettle::Diagnostics diagnostics;
  require(verify(program, diagnostics), "raw binary32 signed zero rejected");
  auto &constant = program.functions[0].blocks[0].instructions.back();
  constant.numeric->floatingBits = 0x100000000ull;
  rejected(program, "instruction");
  constant.numeric->floatingBits = 0xff812345u;
  constant.result.type = Type::F64;
  constant.numeric->floatingBits = 0xfff0123456789abcull;
  require(verify(program, diagnostics), "raw binary64 signaling NaN rejected");
  constant.numeric->floating = "nan";
  rejected(program, "instruction");
  constant.numeric->floating.clear();
  constant.numeric->magnitude[0] = 1;
  rejected(program, "instruction");
  constant.numeric->magnitude[0] = 0;
  constant.numeric->negative = true;
  rejected(program, "instruction");
  constant.numeric->negative = false;
  constant.result.type = Type::U64;
  rejected(program, "instruction");

  program = simple();
  mettle::StaticConstant initializer;
  initializer.type = Type::Bool;
  initializer.scalar.floatingBits = 0;
  program.statics.push_back(
      {"bad", "", "", Type::Bool, false, false, {}, initializer});
  rejected(program, "static initializer");
  program.statics[0].type = Type::Char;
  program.statics[0].initializer->type = Type::Char;
  rejected(program, "static initializer");
}
void staticConsumptionCases() {
  auto types = std::make_shared<mettle::TypeStore>();
  auto array = types->arrayType(Type::I32, types->constant(Type::Usize, 2));
  for (auto storage :
       {mettle::StorageDuration::Automatic, mettle::StorageDuration::Static})
    for (auto op : {Op::Move, Op::DropPlace, Op::ArrayTake}) {
      auto result = op == Op::Move        ? array
                    : op == Op::ArrayTake ? Type::I32
                                          : Type::Unit;
      Instruction consume{op, {1, result}, {}, {}, "", {0, {}}, -1, 0, {}};
      consume.unsafeAllowed = true;
      if (op == Op::ArrayTake)
        consume.operands = {{0, Type::Usize}};
      Local local{"items", array, true, {}};
      local.storage = storage;
      Program program;
      program.types = types;
      program.requireEntry = false;
      program.functions = {
          {"consume",
           result,
           storage == mettle::StorageDuration::Static ? 0u : 1u,
           {local},
           {{{{Op::Constant, {0, Type::Usize}, {}, {}, "", {-1, {}}, -1, 0, {}},
              consume},
             {Exit::Return, {1, result}}}},
           2}};
      mettle::Diagnostics diagnostics;
      mettle::analysis::initialization(program, diagnostics);
      if (storage == mettle::StorageDuration::Automatic)
        require(diagnostics.empty(), "local consumption was rejected");
      else
        require(std::any_of(diagnostics.items.begin(), diagnostics.items.end(),
                            [](const auto &item) {
                              return item.phase == "ownership" &&
                                     item.message.find("static storage") !=
                                         std::string::npos;
                            }),
                "static consumption bypassed initialization analysis");
    }
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
      mettle::Source{"divergence.mt",
                     "fn stop(): Never { loop {} }\n"
                     "fn inferred() { true && stop() }\n"
                     "fn annotated(): i32 { let _ = true && stop(); 42 }\n"
                     "fn main() { 0 }\n"},
      divergence);
  require(nonreturning.has_value(),
          "unreachable short-circuit merge became an invalid return");
  mettle::Diagnostics invalid;
  require(!mettle::pipeline::compile(
              mettle::Source{"broken.mt", "fn main() { missing }\n"}, invalid),
          "pipeline published invalid source");
  require(invalid.items[0].phase == "name", "pipeline changed rejection phase");
  for (std::string bytes :
       {std::string("\xc0\x80", 2), std::string("\xed\xa0\x80", 3),
        std::string("\xf4\x90\x80\x80", 4), std::string("\xe2\x82", 2)}) {
    mettle::Diagnostics encoding;
    require(!mettle::pipeline::compile(mettle::Source{"encoding.mt", bytes},
                                       encoding),
            "in-memory pipeline accepted malformed UTF-8");
    require(encoding.items[0].phase == "lex",
            "encoding rejected outside the source boundary");
  }
  mettle::Diagnostics products;
  auto constructed = mettle::pipeline::compile(
      mettle::Source{"product.mt",
                     "copy type Point { x: i32 }\nfn main() { Point(42).x }\n"},
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
                   "fn main() { Coordinate.make(42).value }\n"},
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
      mettle::Source{
          "owners.mt",
          "type Guard<region r> { counter: mut i32 from r; "
          "drop { *self.counter += 1 } }\n"
          "fn route(take value: Guard, flag: bool): Guard from value { "
          "if flag { value } else { value } }\n"
          "fn consume(take value: Guard) {}\n"
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
      mettle::Source{
          "variants.mt",
          "copy enum Value { Empty; Held(i32) }\n"
          "fn unpack(value: Value) { match value { Value.Empty => 0, "
          "Value.Held(payload) => payload } }\n"
          "fn main() { unpack(Value.Held(42)) }\n"},
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
      mettle::Source{
          "unpin.mt",
          "interface Ready {}\n"
          "extend i32 implements Ready {}\n"
          "type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }\n"
          "unsafe extend<T: Ready> Wrapper<T> implements Unpin {}\n"
          "fn main() { var handle = core.pin.pin("
          "Wrapper(42,core.marker.PhantomPinned)); "
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
void indirectContractCases() {
  mettle::Diagnostics diagnostics;
  auto compiled = mettle::pipeline::compile(
      mettle::Source{"indirect.mt",
                     "fn answer(): i32 { 42 }\n"
                     "fn invoke(callback: fn(): i32): i32 { callback() }\n"
                     "fn main(): i32 { invoke(answer) }\n"},
      diagnostics);
  require(compiled.has_value(), "valid indirect call failed compilation");
  auto original = compiled->program();
  auto call = [](Program &program) -> Instruction & {
    for (auto &function : program.functions)
      for (auto &block : function.blocks)
        for (auto &instruction : block.instructions)
          if (instruction.op == Op::IndirectCall)
            return instruction;
    throw std::runtime_error("missing indirect-call fixture");
  };
  require(call(original).callee >= 0, "missing indirect-call contract");
  require(mettle::pipeline::admit(original, diagnostics).has_value(),
          "valid indirect-call contract was not admitted");
  for (int mutation = 0; mutation < 8; ++mutation) {
    auto malformed = original;
    auto &instruction = call(malformed);
    auto &contract = malformed.functions[instruction.callee];
    switch (mutation) {
    case 0:
      instruction.callee = -1;
      break;
    case 1:
      instruction.callee = static_cast<int>(malformed.functions.size());
      break;
    case 2:
      contract.indirectContract = false;
      break;
    case 3:
      contract.abi = "C";
      break;
    case 4:
      contract.variadic = !contract.variadic;
      break;
    case 5:
      contract.unsafeFunction = !contract.unsafeFunction;
      break;
    case 6:
      contract.targetFeatures.insert("avx");
      break;
    case 7:
      instruction.callLocalParameters.push_back(0);
      break;
    }
    mettle::Diagnostics structural;
    require(!verify(malformed, structural),
            "malformed indirect-call contract passed structural verification");
    require(
        std::any_of(structural.items.begin(), structural.items.end(),
                    [](const auto &item) { return item.phase == "internal"; }),
        "indirect-call contract defect was blamed on source");
    mettle::Diagnostics admission;
    require(!mettle::pipeline::admit(std::move(malformed), admission),
            "malformed indirect-call contract reached admission");
  }
}
void rawDropTypeCases() {
  auto types = std::make_shared<mettle::TypeStore>();
  auto resource = types->declareProduct("RawOnly", false);
  types->defineProduct(resource, {{"tag", Type::I32}});
  auto pointer = types->pointerType(resource, mettle::ParameterMode::Mut);
  Instruction drop{Op::DropPlace,
                   {0, Type::Unit},
                   {},
                   {},
                   "",
                   {0, {mettle::Projection::dereference()}},
                   -1,
                   0,
                   {}};
  drop.unsafeAllowed = true;
  Program program;
  program.types = types;
  program.requireEntry = false;
  program.functions = {{"dispose",
                        Type::Unit,
                        1,
                        {{"pointer", pointer, false, {}}},
                        {{{drop}, {Exit::Return, {0, Type::Unit}}}},
                        1}};
  mettle::Diagnostics valid;
  require(verify(program, valid), "valid raw-pointer drop was rejected");
  types->setDestructor(resource, 99);
  rejected(program, "destructor");
  mettle::Diagnostics admission;
  require(!mettle::pipeline::admit(std::move(program), admission),
          "raw drop with an invalid destructor was admitted");
}
void packageOwnershipPropagation() {
  mettle::TypeStore types;
  auto parameter = types.declareParameter("T", false);
  auto root = types.declareProduct("Owned", false);
  types.setGenericParameters(root, {parameter});
  types.defineProduct(root, {{"value", parameter}});
  auto cached = types.instantiateProduct(root, {Type::I32});
  auto regional =
      types.regionalShell(cached, {mettle::RegionId::Static}, {Type::I32});
  types.defineProduct(regional, {{"value", Type::I32}});
  auto pattern =
      types.regionalShell(root, {mettle::RegionId::Static}, {parameter});
  types.defineProduct(pattern, {{"value", parameter}});
  types.setRegionPattern(pattern, pattern);
  auto genericPattern = types.instantiateProduct(pattern, {Type::I32});
  std::vector<mettle::TypeBinding> bindings{{parameter, Type::I32}};
  auto substituted = types.substitute(pattern, bindings);
  std::vector<Type> family{root,    cached,         regional,
                           pattern, genericPattern, substituted};
  auto unrelated = types.declareProduct("Owned", false);
  types.defineProduct(unrelated, {{"value", Type::I32}});
  types.setProductPackage(unrelated, 9);
  auto tuple = types.structural(mettle::AggregateKind::Tuple, {Type::I32});
  auto requirePackages = [&](std::uint32_t expected) {
    for (auto member : family)
      require(types.product(member).package == expected,
              "nominal derivative lost its declared package owner");
    require(types.product(unrelated).package == 9 &&
                types.product(tuple).package == mettle::unknownPackage,
            "package propagation inferred ownership from spelling or shape");
  };
  types.setProductPackage(root, 7);
  requirePackages(7);
  require(types.instantiateProduct(root, {Type::I32}) == cached,
          "package assignment changed generic instance identity");
  auto future = types.instantiateProduct(root, {Type::I64});
  family.push_back(future);
  family.push_back(types.regionalProduct(future, {{"value", Type::I64}},
                                         {mettle::RegionId::Static}, true));
  requirePackages(7);
  types.refreshProductInstances();
  requirePackages(7);
  types.setProductPackage(root, 0);
  requirePackages(0);
}
void regionalProductRefresh() {
  mettle::TypeStore types;
  auto parameter = types.declareParameter("T", false);
  auto family = types.erasedType({"Family", 0});
  auto root = types.declareProduct("Carrier", false);
  types.setGenericParameters(root, {parameter});
  types.defineProduct(
      root,
      {{"borrowed", types.viewType(parameter, mettle::ParameterMode::Read)},
       {"owned", types.projection(parameter, family, 0)}});
  auto instance = types.instantiateProduct(root, {Type::I32});
  auto fields = types.product(instance).fields;
  auto view = types.viewType(Type::I32, mettle::ParameterMode::Read,
                             mettle::RegionId::Static);
  fields[0].type = view;
  auto decorated =
      types.regionalProduct(instance, fields, {mettle::RegionId::Static});
  fields[1].type = Type::I64;
  auto normalized =
      types.regionalProduct(instance, fields, {mettle::RegionId::Static}, true);
  types.setDestructor(root, 0);
  types.refreshProductInstances();
  require(types.product(decorated).fields[0].type == view &&
              types.product(normalized).fields[0].type == view,
          "generic refresh erased derived field regions");
  require(types.product(normalized).fields[1].type == Type::I64,
          "generic refresh discarded normalized associated fields");
  require(types.product(decorated).hasDestructor &&
              types.product(normalized).hasDestructor &&
              types.product(normalized).destructor == 0,
          "preserving derived fields lost refreshed cleanup metadata");
}
void loopSiblingViewCases() {
  auto inspect = [](const std::string &body, int linked, int unlinked) {
    mettle::Diagnostics diagnostics;
    auto syntax = mettle::parse(
        {"siblings.mt",
         "fn split(mut value: [i32; 2]): "
         "(read i32 from value, mut i32 from value) { "
         "(read value[0usize], mut value[1usize]) }\n"
         "fn probe(mut value: [i32; 2]) { " +
             body +
             " }\nfn main() { var values = [1, 2]; probe(mut values); 0 }\n"},
        diagnostics);
    auto checked = mettle::check(std::move(syntax), diagnostics);
    require(checked.has_value(), "sibling-view fixture failed type checking");
    auto program = mettle::lowering::lower(*checked, diagnostics);
    require(verify(program, diagnostics),
            "sibling-view fixture has invalid IR");
    mettle::analysis::EffectSummaries summaries(program.functions.size());
    bool inspected = false;
    for (const auto &function : program.functions) {
      if (function.name != "probe")
        continue;
      inspected = true;
      auto info = mettle::analysis::origins(function, program, summaries);
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions) {
          if (instruction.op != Op::Call ||
              program.functions[instruction.callee].name != "split")
            continue;
          bool siblings = false;
          for (const auto &[path, sources] :
               info.values[instruction.result.id]) {
            (void)path;
            for (auto source : sources)
              siblings |= !info.loans.at(source).disjointOutputs.empty();
          }
          --(siblings ? linked : unlinked);
        }
    }
    require(inspected && linked == 0 && unlinked == 0,
            "loop sibling disjointness crossed an invocation boundary");
  };
  inspect("var index = 0; while index < 2 { "
          "let pair = split(mut value); let _ = *pair.0; index += 1 }",
          1, 0);
  inspect("var pair = split(mut value); var index = 0; "
          "while index < 2 { pair = split(mut value); index += 1 }; "
          "let _ = *pair.0",
          1, 1);
}
void contentsOnlyResultPathCases() {
  auto types = std::make_shared<mettle::TypeStore>();
  mettle::ErasedType payload;
  payload.name = "Payload";
  auto unknown = types->erasedType(payload);
  auto owned = types->erasedBound(unknown, mettle::RegionId::Static);
  auto region = types->regions().bound(types->regions().binder(), "r");
  auto borrowed = types->erasedBound(unknown, region);
  auto view = types->viewType(Type::I32, mettle::ParameterMode::Read);
  auto tag = types->declareParameter("Tag", false);
  auto carrier = types->declareProduct("Hidden", false);
  types->setGenericParameters(
      carrier, {types->declareParameter("T", false, false),
                types->declareParameter("U", false, false), tag});
  types->defineProduct(carrier, {});
  auto count = types->constant(Type::Usize, 65);
  auto inspect = [&](Type first, Type second, bool contentsOnly) {
    auto hidden = types->instantiateProduct(carrier, {first, second, tag});
    auto declared = types->arrayType(hidden, count);
    auto runtime = types->eraseRegions(declared);
    mettle::CallableType signature;
    signature.parameters = {{Type::I32, mettle::ParameterMode::Mut, "self"}};
    signature.result = view;
    signature.error = declared;
    signature.abiResult = view;
    signature.resultSources = {0};
    Function function{
        "abstract",
        types->structural(mettle::AggregateKind::Outcome, {view, runtime}),
        1,
        {{"self", Type::I32, true, {}, mettle::ParameterMode::Mut}},
        {}};
    function.declarationOnly = true;
    function.genericParameters = {tag};
    function.regionSignature = types->callableType(std::move(signature));
    function.resultSources = {0};
    Program program;
    program.types = types;
    program.functions.push_back(std::move(function));
    mettle::analysis::EffectSummaries summaries(1);
    auto info =
        mettle::analysis::origins(program.functions[0], program, summaries);
    require(!info.effects.returns.at({mettle::Projection::field(1)}).empty(),
            "contents-only selection removed the borrowed success source");
    mettle::analysis::ViewPath path{
        mettle::Projection::field(2),
        mettle::Projection::opaque(types->product(runtime).components[0])};
    auto error = info.effects.returns.find(path);
    require((error == info.effects.returns.end() || error->second.empty()) ==
                contentsOnly,
            "opaque result classification did not require all-static leaves");
    if (!contentsOnly)
      return;
    std::vector<mettle::TypeBinding> bindings{{tag, Type::I32}};
    auto instantiated =
        types->substitute(program.functions[0].result, bindings);
    Instruction borrow{Op::BorrowMut,
                       {0, Type::I32, Access::Mut},
                       {},
                       {},
                       "",
                       {0, {}},
                       -1,
                       0,
                       {}};
    Instruction call{Op::Call,
                     {1, instantiated},
                     {{0, Type::I32, Access::Mut}},
                     {},
                     "",
                     {-1, {}},
                     0,
                     0,
                     {}};
    call.typeArguments = {Type::I32};
    Function caller{"caller",
                    instantiated,
                    1,
                    program.functions[0].locals,
                    {{{borrow, call}, {Exit::Return, {1, instantiated}}}},
                    2};
    caller.resultSources = {0};
    caller.regionSignature =
        types->substitute(program.functions[0].regionSignature, bindings);
    program.functions.push_back(std::move(caller));
    mettle::analysis::EffectSummaries calls(2);
    calls.slot(0) = info.effects;
    auto transferred =
        mettle::analysis::origins(program.functions[1], program, calls);
    for (auto &projection : path)
      projection.type = types->substitute(projection.type, bindings);
    const auto &origins = transferred.values[1].at(path);
    require(!origins.empty(), "instantiated erased result lost its loan slot");
    for (auto id : origins)
      require(transferred.loans.at(id).parents.empty() &&
                  transferred.loans.at(id).targets.empty(),
              "instantiated opaque result inherited receiver storage");
    for (auto id : transferred.values[1].at({mettle::Projection::field(1)}))
      require(!transferred.loans.at(id).parents.empty(),
              "instantiated success lost its receiver ancestry");
  };
  inspect(owned, owned, true);
  for (auto other : {unknown, borrowed, view}) {
    inspect(owned, other, false);
    inspect(other, owned, false);
  }
}
void preparedAnalysisReuse() {
  auto program = simple();
  program.functions[0].name = "value";
  auto caller = program.functions[0];
  caller.name = "main";
  caller.blocks[0].instructions[0] = {
      Op::Call, {0, Type::I32}, {}, {}, "", {-1, {}}, 0, 0, {}};
  program.functions.push_back(std::move(caller));
  auto unrelated = program.functions[0];
  unrelated.name = "unrelated";
  program.functions.push_back(std::move(unrelated));
  mettle::Diagnostics diagnostics;
  auto checked = mettle::analysis::loans(program, diagnostics);
  require(diagnostics.empty(), "valid preparation failed loan analysis");
  auto reused =
      mettle::analysis::loans(program, diagnostics, &program, &checked);
  require(diagnostics.empty() && reused.reusedFunctions == 3,
          "unchanged preparation did not reuse loan results");
  auto changed = program;
  changed.functions[0].blocks[0].instructions[0].number = 42;
  auto invalidated =
      mettle::analysis::loans(changed, diagnostics, &program, &checked);
  require(diagnostics.empty() && invalidated.reusedFunctions == 1,
          "changed callee did not invalidate its unchanged caller");
  changed.functions[0].locals.push_back({"x", Type::I32, false, {}});
  changed.functions[0].blocks[0].instructions[0] = {
      Op::Load, {0, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}};
  mettle::analysis::initialization(changed, diagnostics, &program);
  require(!diagnostics.empty() && diagnostics.items.back().phase == "type",
          "changed prepared body bypassed initialization analysis");
}

void preparedDeclarations() {
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse({"prepared.mt",
                             "fn identity<T: Copy>(value: T): T { value }\n"
                             "fn main(): i32 { identity(42) - 42 }\n"},
                            diagnostics);
  unsigned observations = 0;
  auto prepared = mettle::pipeline::prepare(
      std::move(tree), diagnostics, true, {},
      [&](const mettle::CheckedModule &) { ++observations; });
  require(prepared.has_value() && diagnostics.empty(),
          "valid symbolic declarations were not prepared");
  require(observations == 1,
          "preparation did not observe checking exactly once");
  require(std::any_of(prepared->program().functions.begin(),
                      prepared->program().functions.end(),
                      [](const auto &function) {
                        return !function.genericParameters.empty() &&
                               !function.blocks.empty();
                      }),
          "preparation discarded symbolic generic bodies");
  auto executable =
      mettle::pipeline::compile(std::move(*prepared), diagnostics);
  require(executable.has_value() && diagnostics.empty(),
          "prepared declarations did not survive frontend destruction");
  require(std::none_of(executable->program().functions.begin(),
                       executable->program().functions.end(),
                       [](const auto &function) {
                         return !function.genericParameters.empty();
                       }),
          "prepared compilation skipped concrete specialization");
  require(observations == 1, "prepared compilation repeated frontend checking");

  mettle::Diagnostics invalid;
  auto broken =
      mettle::parse({"unprepared.mt", "fn main(): i32 { true }\n"}, invalid);
  require(!mettle::pipeline::prepare(std::move(broken), invalid),
          "preparation published an unchecked declaration");
  require(!invalid.empty() && invalid.items.front().phase == "type",
          "preparation changed the source rejection phase");
}

void importedPreparation() {
  for (int failure = 0; failure != 4; ++failure) {
    mettle::Diagnostics diagnostics;
    auto tree =
        mettle::parse({"consumer.mt", "fn main(): i32 { 0 }\n"}, diagnostics);
    unsigned imports = 0, checks = 0;
    mettle::pipeline::LibraryImporter import =
        [&](const mettle::Module &, const mettle::resolution::Resolution &,
            mettle::Diagnostics &)
        -> std::optional<mettle::pipeline::ImportedProgram> {
      ++imports;
      if (failure == 1)
        return std::nullopt;
      mettle::pipeline::ImportedProgram imported;
      imported.metadata.emplace();
      imported.metadata->libraries = {"first", "second", "first"};
      if (failure == 2)
        imported.metadata->target.pointerBits = 32;
      if (failure == 3)
        imported.metadata->functions.push_back(
            {"unplaced", mettle::Type::I32, 0, {}, {}});
      return imported;
    };
    auto prepared = mettle::pipeline::prepare(
        std::move(tree), diagnostics, true, {},
        [&](const mettle::CheckedModule &) { ++checks; }, {}, nullptr, {},
        nullptr, nullptr, import);
    require(imports == 1, "library import repeated namespace resolution");
    if (!failure) {
      require(prepared.has_value() && diagnostics.empty() && checks == 1,
              "post-resolution import did not preserve ordinary checking");
      require(prepared->program().libraries ==
                  std::vector<std::string>{"first", "second", "first"},
              "import changed native library ordering or repetitions");
      require(mettle::pipeline::compile(std::move(*prepared), diagnostics)
                  .has_value(),
              "post-resolution import bypassed concrete admission");
    } else {
      require(!prepared && !diagnostics.empty() &&
                  diagnostics.items.front().phase == "metadata",
              "invalid library metadata did not reject before publication");
    }
  }
}
} // namespace
int main() {
  try {
    verifierCases();
    floatingCarrierCases();
    staticConsumptionCases();
    phaseOwnership();
    ownedValueCases();
    variantRefinementCases();
    conditionalUnpinProofCases();
    indirectContractCases();
    rawDropTypeCases();
    packageOwnershipPropagation();
    regionalProductRefresh();
    loopSiblingViewCases();
    contentsOnlyResultPathCases();
    preparedAnalysisReuse();
    preparedDeclarations();
    importedPreparation();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  std::cout
      << "IR verification, independent analysis and phase ownership passed\n";
}
