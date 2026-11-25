#include "ir/verify.h"
#include "analysis/initialization.h"
#include "analysis/loans.h"
#include "analysis/origins.h"
#include "analysis/value_ownership.h"
#include "consteval/evaluate.h"
#include "instances/specialize.h"
#include "ir/dominance.h"
#include "lowering/scalar.h"
#include "pipeline/compile.h"
#include "semantics/check.h"
#include "semantics/inference.h"
#include "syntax/parser.h"
#include "types/machine.h"
#include <algorithm>
#include <array>
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
void dominanceCases() {
  Function function{"dominance", Type::Unit, 0, {}, {}, 0};
  function.blocks.resize(7);
  function.blocks[0].exit = {Exit::Branch, {}, 1, 2};
  function.blocks[1].exit = {Exit::Jump, {}, 3};
  function.blocks[2].exit = {Exit::Jump, {}, 3};
  function.blocks[3].exit = {Exit::Branch, {}, 4, 5};
  function.blocks[4].exit = {Exit::Jump, {}, 3};
  function.blocks[5].exit = {Exit::Return};
  function.blocks[6].exit = {Exit::Jump, {}, 5};
  Dominance dominance(function);
  for (int block = 0; block < 6; ++block) {
    require(dominance.dominates(0, block), "entry lost dominance");
    require(dominance.dominates(block, block), "block lost self dominance");
  }
  require(dominance.dominates(3, 4) && dominance.dominates(3, 5),
          "loop header lost dominance");
  require(!dominance.dominates(1, 3) && !dominance.dominates(2, 1) &&
              !dominance.dominates(4, 3) && !dominance.dominates(5, 4),
          "dominator intervals crossed siblings or a backedge");
  require(!dominance.reachable(6) && !dominance.dominates(6, 5) &&
              dominance.dominates(5, 6),
          "unreachable predecessor changed dominance");
}
void inferenceWakeupCases() {
  mettle::TypeStore types;
  mettle::Diagnostics diagnostics;
  mettle::TypeInference inference(diagnostics, types);
  auto leaf = inference.fresh(), alias = inference.fresh();
  auto array = inference.composite(mettle::AggregateKind::Array, {leaf}, 1);
  int blocked = -1;
  require(inference.value(array, &blocked) == Type::Unknown && blocked == leaf,
          "aggregate inference did not identify its unresolved child");
  mettle::TypeInference::Changes changes(inference);
  inference.equal(leaf, alias, {});
  require(changes.next() == leaf &&
              inference.value(array, &blocked) == Type::Unknown &&
              blocked == alias,
          "inference aliasing did not wake and redirect its dependent");
  auto children =
      inference.components(alias, mettle::AggregateKind::Optional, {});
  require(changes.next() == alias &&
              inference.value(array, &blocked) == Type::Unknown &&
              blocked == children.front(),
          "aggregate shape discovery lost its child dependency");
  inference.equal(inference.numeric(false), children.front(), {});
  bool woke = false;
  while (auto variable = changes.next())
    woke |= *variable == children.front();
  auto resolved = inference.value(array);
  require(woke && diagnostics.empty() && types.isProduct(resolved) &&
              types.product(types.product(resolved).components.front())
                      .components.front() == Type::I32,
          "defaulted numeric inference did not resolve its aggregate owners");
  std::vector<int> dependencies;
  require(inference.value(array, nullptr, &dependencies) == resolved &&
              std::find(dependencies.begin(), dependencies.end(), array) !=
                  dependencies.end() &&
              std::find(dependencies.begin(), dependencies.end(),
                        inference.representative(children.front())) !=
                  dependencies.end(),
          "resolved aggregate inference lost its mutable child dependencies");
  inference.set(children.front(), Type::I64);
  dependencies.clear();
  auto refined = inference.value(array, nullptr, &dependencies);
  require(refined != resolved &&
              types.product(types.product(refined).components.front())
                      .components.front() == Type::I64,
          "known inferred child refinement did not update its aggregate");
}
void constantValueSnapshotCases() {
  using mettle::evaluation::Value;
  Value scalar;
  scalar.kind = Value::Kind::Integer;
  scalar.type = Type::I32;
  scalar.number = mettle::integerLiteral(7);
  Value array;
  array.kind = Value::Kind::Array;
  array.elements.assign(3, scalar);
  Value outer;
  outer.kind = Value::Kind::Tuple;
  outer.elements = {array, array};
  auto copy = outer;
  copy.elements[0].elements[1].number = mettle::integerLiteral(11);
  require(outer.elements[0].elements[1].number == mettle::integerLiteral(7) &&
              copy.elements[0].elements[1].number ==
                  mettle::integerLiteral(11) &&
              copy.elements[1].elements[1].number == mettle::integerLiteral(7),
          "constant aggregate mutation changed another value snapshot");
  mettle::TypeStore types;
  for (auto operation :
       {"numeric.wrapping_missing", "numeric.strict_checked_add",
        "missing.checked_add", "numeric.checked_add.extra"})
    require(!mettle::machineSignature(types, operation,
                                      std::array{Type::I32, Type::I32}),
            "unknown primitive operation acquired a valid signature");
  auto optional = mettle::machineSignature(types, "numeric.checked_add",
                                           std::array{Type::I32, Type::I32});
  require(optional && optional->value == Type::I32 &&
              optional->shape == mettle::MachineSignature::Shape::Optional,
          "checked primitive lost its optional result contract");
}
void emptySpecializationCases() {
  Program program;
  Function function{"main", Type::I32, 0, {}, {}, 7};
  function.blocks.resize(5);
  function.blocks[0] = {
      {{Op::Constant, {0, Type::Bool}, {}, {}, "", {-1, {}}, -1, 1, {}}},
      {Exit::Branch, {0, Type::Bool}, 3, 4}};
  function.blocks[1] = {{{Op::Phi,
                          {6, Type::I32},
                          {{3, Type::I32}, {5, Type::I32}},
                          {2, 4},
                          "",
                          {-1, {}},
                          -1,
                          0,
                          {}}},
                        {Exit::Return, {6, Type::I32}}};
  function.blocks[2] = {{{Op::Phi,
                          {3, Type::I32},
                          {{2, Type::I32}},
                          {3},
                          "",
                          {-1, {}},
                          -1,
                          0,
                          {}},
                         {Op::Binary,
                          {4, Type::Bool},
                          {{3, Type::I32}, {3, Type::I32}},
                          {},
                          "==",
                          {-1, {}},
                          -1,
                          0,
                          {}}},
                        {Exit::Branch, {4, Type::Bool}, 1, 1}};
  function.blocks[3] = {
      {{Op::Constant, {1, Type::Never}, {}, {}, "", {-1, {}}, -1, 0, {}},
       {Op::Constant, {2, Type::I32}, {}, {}, "", {-1, {}}, -1, 1, {}}},
      {Exit::Jump, {}, 2}};
  function.blocks[4] = {
      {{Op::Constant, {5, Type::I32}, {}, {}, "", {-1, {}}, -1, 42, {}}},
      {Exit::Jump, {}, 1}};
  program.functions.push_back(std::move(function));
  mettle::Diagnostics diagnostics;
  auto specialized = mettle::instances::specialize(program, diagnostics);
  require(specialized && diagnostics.empty(),
          "empty specialization propagation failed");
  const auto &blocks = specialized->program.functions[0].blocks;
  require(blocks[3].exit.kind == Exit::Unreachable &&
              blocks[2].exit.kind == Exit::Unreachable &&
              blocks[2].instructions[0].op == Op::Constant &&
              blocks[2].instructions[1].op == Op::Constant,
          "empty values did not propagate through a reverse-ordered join");
  require(blocks[1].instructions[0].op == Op::Phi &&
              blocks[1].instructions[0].operands ==
                  std::vector<Value>{{5, Type::I32}} &&
              blocks[1].instructions[0].predecessors == std::vector<int>{4} &&
              blocks[1].exit.kind == Exit::Return,
          "empty specialization removed a live phi input");
}
void coherenceCandidateCases() {
  mettle::TypeStore types;
  mettle::interfaces::Database database;
  database.definitions.resize(2);
  for (auto &definition : database.definitions)
    definition.package = 0;
  mettle::ErasedType first{};
  first.declaration = 0;
  auto firstType = types.erasedType(first);
  first.declaration = 1;
  auto secondType = types.erasedType(first);
  auto append = [&](Type interface, bool imported, bool fallback) {
    mettle::interfaces::Implementation implementation{};
    implementation.target = Type::I32;
    implementation.interfaceType = interface;
    implementation.package = 0;
    implementation.span = {database.implementations.size() * 2,
                           database.implementations.size() * 2 + 1};
    implementation.checkedImport = imported;
    implementation.fallback = fallback;
    database.implementations.push_back(std::move(implementation));
  };
  append(firstType, true, false);
  append(firstType, true, false);
  append(secondType, false, false);
  append(firstType, false, true);
  mettle::Diagnostics disjoint;
  require(mettle::interfaces::Solver(types, database, disjoint).coherent(),
          "unrelated interfaces, fallback or trusted pairs overlapped");
  append(firstType, false, false);
  append(secondType, false, false);
  mettle::Diagnostics overlapping;
  require(
      !mettle::interfaces::Solver(types, database, overlapping).coherent() &&
          overlapping.items.size() == 2,
      "indexed coherence missed a local/imported overlap");
  database.implementations.clear();
  append(Type::Unknown, false, false);
  database.implementations[0].inherent = {{"alpha", {}}, {"beta", {}}};
  append(Type::Unknown, false, false);
  database.implementations[1].inherent = {{"gamma", {}}};
  append(Type::Unknown, true, false);
  database.implementations[2].inherent = {{"alpha", {}}, {"beta", {}}};
  mettle::Diagnostics inherent;
  require(!mettle::interfaces::Solver(types, database, inherent).coherent() &&
              inherent.items.size() == 1,
          "inherent candidate indexing missed or duplicated a conflict");
  auto parameter = types.declareParameter("T", false);
  auto phantom = types.declareProduct("Phantom", true);
  types.setGenericParameters(phantom, {parameter});
  types.defineProduct(phantom, {});
  auto instance = types.instantiateProduct(phantom, {Type::I32});
  mettle::Diagnostics matching;
  mettle::interfaces::Solver matcher(types, database, matching);
  auto bindings = matcher.match(phantom, instance);
  require(bindings && bindings->size() == 1 &&
              bindings->front().parameter == parameter &&
              bindings->front().argument == Type::I32,
          "nominal matching depended on an unused parameter's private fields");
  auto actualParameter = types.declareParameter("U", false);
  require(!matcher.match(phantom, parameter) &&
              matcher.match(phantom, actualParameter, true) &&
              matcher.match(phantom, Type::Unknown, false, nullptr, true),
          "nominal rejection changed symmetric or partial matching");
  require(!matcher.match(parameter, phantom),
          "nominal identity matching admitted a recursive parameter binding");
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
  auto &f = program.functions.edit(0);
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
  {
    auto program = simple();
    auto types = std::make_shared<mettle::TypeStore>();
    auto unused = types->declareImportedType(mettle::ImportedTypeKind::Product);
    std::size_t loaded = 0;
    auto loader =
        std::make_shared<const mettle::TypeStore::ImportedDefinitionLoader>(
            [&](std::size_t) -> mettle::ImportedTypeDefinition {
              ++loaded;
              mettle::ImportedProduct product{};
              product.descriptor.name = "Unused";
              product.descriptor.fields = {{"invalid", Type::Unknown}};
              return product;
            });
    types->deferImportedDefinitions(
        std::array{unused}, std::array{mettle::ImportedTypeIndex{}}, loader);
    program.types = types;
    Function declaration{"unused", Type::I32, 1, {{"value", unused, false, {}}},
                         {},       0};
    declaration.declarationOnly = true;
    program.functions.push_back(std::move(declaration));
    const std::vector<bool> trusted{false, true};
    mettle::Diagnostics unusedDiagnostics;
    require(verify(program, unusedDiagnostics, {}, {}, &trusted) && loaded == 0,
            "unused trusted library declarations forced type expansion");
    program.functions.edit(0).locals.push_back({"used", unused, false, {}});
    mettle::Diagnostics usedDiagnostics;
    require(!verify(program, usedDiagnostics, {}, {}, &trusted) && loaded == 1,
            "trusted library types bypassed verification when used by source");
  }
  {
    auto shared = std::make_shared<const Function>(simple().functions[0]);
    Program imported;
    imported.functions.push_shared(shared);
    auto consumer = imported;
    auto retained = imported.functions.retain(0);
    require(&consumer.functions[0] == shared.get(),
            "native header read copied its immutable definition");
    shared.reset();
    imported.functions.clear();
    consumer.functions.edit(0).blocks[0].instructions[0].number = 42;
    require(retained->blocks[0].instructions[0].number == 0 &&
                consumer.functions[0].blocks[0].instructions[0].number == 42,
            "consumer mutation changed a retained native definition");
  }
  {
    auto cached = simple();
    auto types = std::make_shared<mettle::TypeStore>();
    auto payload = types->declareProduct("payload", true);
    types->defineProduct(payload, {{"value", Type::I32}});
    auto view = types->viewType(payload, mettle::ParameterMode::Read);
    cached.types = types;
    cached.functions.edit(0).locals.push_back({"view", view, false, {}});
    TypeVerificationCache cache;
    mettle::Diagnostics first;
    require(verify(cached, first, {}, {}, nullptr, &cache),
            "valid cached type graph rejected");
    types->defineProduct(payload, {{"recursive", payload}});
    mettle::Diagnostics changed;
    require(!verify(cached, changed, {}, {}, nullptr, &cache) &&
                !changed.empty(),
            "cached view hid a changed recursive payload");
    types->defineProduct(payload, {{"value", Type::I32}});
    mettle::Diagnostics restored;
    require(verify(cached, restored, {}, {}, nullptr, &cache),
            "failed verification poisoned the type cache");
  }
  {
    auto recursive = simple();
    auto types = std::make_shared<mettle::TypeStore>();
    const auto first = types->declareProduct("first", true);
    const auto second = types->declareProduct("second", true);
    const auto view = types->viewType(second, mettle::ParameterMode::Read);
    types->defineProduct(first, {{"indirect", view}, {"direct", second}});
    types->defineProduct(second, {{"recursive", first}});
    recursive.types = types;
    recursive.functions.edit(0).locals.push_back({"value", first, false, {}});
    rejected(recursive, "recursive by-value layout");
  }
  auto program = simple();
  program.functions.edit(0).blocks[0].exit = {};
  rejected(program, "terminator");
  program = simple();
  program.functions.edit(0).blocks[0].exit = {Exit::Jump, {}, 99};
  rejected(program, "successor");
  program = simple();
  program.functions.edit(0).blocks[0].exit.value = {99, Type::I32};
  rejected(program, "operand");
  program = simple();
  program.functions.edit(0).blocks[0].exit.value.type = Type::Bool;
  rejected(program, "type");
  rejected(diamond(false), "dominate");
  require(verify(diamond(true), diagnostics), "valid phi CFG rejected");
  program = diamond(true);
  program.functions.edit(0).blocks[3].instructions[0].predecessors = {1, 1};
  rejected(program, "instruction");
  program = simple();
  program.functions.edit(0).blocks[0].instructions[0] = {
      Op::Call, {0, Type::I32}, {}, {}, "", {-1, {}}, 5, 0, {}};
  rejected(program, "callee");
  program = simple();
  program.functions.edit(0).locals.push_back({"x", Type::I32, false, {}});
  program.functions.edit(0).blocks[0].instructions[0].place = {0, {}};
  require(verify(program, diagnostics), "valid attached place rejected");
  program.functions.edit(0).blocks[0].instructions[0].place.fields = {
      mettle::Projection::field(0)};
  rejected(program, "projected place");
  program.functions.edit(0).blocks[0].instructions[0].place.root = -1;
  rejected(program, "local slot");
  program.functions.edit(0).blocks[0].instructions[0].place = {99, {}};
  rejected(program, "local slot");
  program.functions.edit(0).blocks[0].instructions[0].place.root = -2;
  rejected(program, "local slot");
  program = simple();
  program.functions.edit(0).locals.push_back({"x", Type::I32, false, {}});
  program.functions.edit(0).blocks[0].instructions[0] = {
      Op::Load, {0, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}};
  require(verify(program, diagnostics),
          "typed uninitialized load was not structurally valid");
  mettle::analysis::initialization(program, diagnostics);
  require(!diagnostics.empty() && diagnostics.items.back().phase == "type",
          "independent initialization analysis missed uninitialized load");
  program.functions.edit(0).blocks[0].instructions[0].place.fields = {
      mettle::Projection::field(0)};
  rejected(program, "projected place");
  program = simple();
  program.functions.edit(0).locals.push_back({"x", Type::I32, true, {}});
  program.functions.edit(0).blocks[0].instructions[0] = {
      Op::BorrowRead,
      {0, Type::I32, Access::Read},
      {},
      {},
      "",
      {0, {}},
      -1,
      0,
      {}};
  program.functions.edit(0).blocks[0].exit.value = {0, Type::I32, Access::Read};
  rejected(program, "return type");
  program = simple();
  program.functions.edit(0).locals.push_back({"x", Type::I32, true, {}});
  program.functions.edit(0).blocks[0].instructions = {
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
  program.functions.edit(0).values = 3;
  program.functions.edit(0).blocks[0].exit.value = {2, Type::I32};
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
void functionAddressCases() {
  auto program = simple();
  program.target = mettle::targetFacts("x86_64-unknown-linux-gnu");
  auto types = std::make_shared<mettle::TypeStore>();
  program.types = types;
  Function callee{
      "target", Type::I32, 1, {{"value", Type::I32, false, {}}}, {}};
  callee.externalName = "target";
  program.functions.push_back(std::move(callee));
  mettle::CallableType signature;
  signature.result = signature.abiResult = Type::I32;
  signature.parameters.push_back({Type::I32});
  auto initializer = std::make_shared<mettle::StaticConstant>();
  initializer->kind = mettle::StaticConstant::Kind::Function;
  initializer->symbol = 1;
  program.statics.push_back(
      {"callback", "", "", Type::Unknown, false, false, {}, initializer});
  Instruction address;
  address.op = Op::FunctionAddress;
  address.callee = 1;
  address.result.id = 1;
  program.functions.edit(0).blocks[0].instructions.push_back(address);
  program.functions.edit(0).values = 2;
  auto pointer = [&](const mettle::CallableType &contract) {
    auto type = types->callableType(contract);
    program.statics[0].type = type;
    initializer->type = type;
    program.functions.edit(0).blocks[0].instructions[1].result.type = type;
  };
  auto accepted = [&] {
    mettle::Diagnostics diagnostics;
    require(verify(program, diagnostics),
            diagnostics.empty() ? "valid function address rejected"
                                : diagnostics.items.front().message.c_str());
  };
  auto invalid = [&] {
    rejected(program, "static initializer");
    auto instructionOnly = program;
    instructionOnly.statics.clear();
    rejected(instructionOnly, "function address");
  };
  pointer(signature);
  accepted();
  auto mismatch = signature;
  mismatch.result = mismatch.abiResult = Type::Bool;
  pointer(mismatch);
  invalid();
  mismatch = signature;
  mismatch.parameters[0].type = Type::Bool;
  pointer(mismatch);
  invalid();
  mismatch = signature;
  mismatch.parameters[0].mode = mettle::ParameterMode::Read;
  pointer(mismatch);
  invalid();
  mismatch.parameters.clear();
  pointer(mismatch);
  invalid();
  pointer(signature);
  auto &target = program.functions.edit(1);
  target.unsafeFunction = true;
  invalid();
  signature.unsafeCall = true;
  pointer(signature);
  accepted();
  target.unsafeFunction = false;
  accepted();
  target.abi = "C";
  invalid();
  signature.abi = "C";
  pointer(signature);
  accepted();
  target.variadic = true;
  invalid();
  signature.variadic = true;
  pointer(signature);
  accepted();
  target.targetFeatures = {"sse2"};
  invalid();
  signature.targetFeatures = {"sse2"};
  pointer(signature);
  accepted();
  signature.targetFeatures.insert("avx");
  pointer(signature);
  accepted();
  target.genericParameters = {types->declareParameter("T", true)};
  invalid();
  target.genericParameters.clear();
  target.indirectContract = true;
  invalid();
  target.indirectContract = false;
  target.declarationOnly = true;
  invalid();
  target.declarationOnly = false;
  target.parameters = 2;
  invalid();
  target.parameters = 1;

  auto view = types->viewType(Type::I32, mettle::ParameterMode::Read);
  target.result = view;
  target.resultSources = {0};
  target.locals[0].mode = mettle::ParameterMode::Read;
  signature.result = signature.abiResult = view;
  signature.resultSources = {0};
  signature.parameters[0].mode = mettle::ParameterMode::Read;
  pointer(signature);
  accepted();
  mismatch = signature;
  mismatch.resultSources.clear();
  pointer(mismatch);
  invalid();
  mismatch = signature;
  mismatch.result = mismatch.abiResult = types->viewType(
      Type::I32, mettle::ParameterMode::Read, mettle::RegionId::Static);
  pointer(mismatch);
  invalid();
}
void floatingCarrierCases() {
  auto program = simple();
  Instruction instruction;
  instruction.op = Op::Constant;
  instruction.result = {1, Type::F32};
  instruction.numeric = mettle::NumericLiteral{};
  instruction.numeric->floatingBits = 0x80000000u;
  program.functions.edit(0).blocks[0].instructions.push_back(instruction);
  program.functions.edit(0).values = 2;
  mettle::Diagnostics diagnostics;
  require(verify(program, diagnostics), "raw binary32 signed zero rejected");
  auto &constant = program.functions.edit(0).blocks[0].instructions.back();
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
  auto initializer = std::make_shared<mettle::StaticConstant>();
  initializer->type = Type::Bool;
  initializer->scalar.floatingBits = 0;
  program.statics.push_back(
      {"bad", "", "", Type::Bool, false, false, {}, initializer});
  rejected(program, "static initializer");
  program.statics[0].type = Type::Char;
  initializer->type = Type::Char;
  rejected(program, "static initializer");

  program = simple();
  auto types = std::make_shared<mettle::TypeStore>();
  auto parameter = types->declareParameter("T", false, false);
  program.types = types;
  auto function = program.functions[0];
  function.name = "scoped";
  function.genericParameters = {parameter};
  function.parameters = 1;
  function.locals.push_back(
      {"value", parameter, false, {}, mettle::ParameterMode::Take});
  program.functions.push_back(std::move(function));
  rejected(program, "unsized owned storage");
  program.functions.edit(1).sizedBounds = {parameter};
  mettle::Diagnostics scoped;
  auto valid = verify(program, scoped);
  require(valid, scoped.empty() ? "contextual Sized storage rejected"
                                : scoped.items.front().message.c_str());
  require(!program.types->isSized(parameter), "contextual Sized bound leaked");
  program.functions.edit(1).sizedBounds.clear();
  rejected(program, "unsized owned storage");
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
  for (auto &block : malformed.functions.edit(0).blocks)
    for (auto &instruction : block.instructions)
      if (!instruction.place.fields.empty())
        instruction.place.fields.back() = mettle::Projection::field(999);
  rejected(malformed, "projected place");
  malformed = constructed->program();
  for (auto &block : malformed.functions.edit(0).blocks)
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
    return program.functions.edit(
        std::distance(program.functions.begin(), found));
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
  auto leaking = route;
  leaking.result = Type::Unit;
  leaking.blocks[3] = {
      {{Op::Constant, {2, Type::Unit}, {}, {}, "", {-1, {}}, -1, 0, {}}},
      {Exit::Return, {2, Type::Unit}}};
  mettle::Diagnostics leaked;
  mettle::analysis::valueOwnership(leaking, *branch.types, leaked);
  require(!leaked.empty() &&
              leaked.items.front().message.find(
                  "without transfer or cleanup") != std::string::npos,
          "unused owned SSA value disappeared across empty blocks");
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
       static_cast<int>(std::distance(branch.functions.begin(), consume)),
       0,
       {}});
  route.values = 4;
  rejectedOwner(std::move(branch), "already have been consumed");
}
void initializationLivenessCases() {
  Program program;
  auto types = std::make_shared<mettle::TypeStore>();
  program.types = types;
  Function assigned{"assigned", Type::I32, 0, {{"value", Type::I32, false, {}}},
                    {},         7};
  assigned.blocks = {
      {{{Op::Declare, {0, Type::Unit}, {}, {}, "", {0, {}}, -1, 0, {}},
        {Op::Constant, {1, Type::I32}, {}, {}, "", {-1, {}}, -1, 1, {}},
        {Op::Store,
         {2, Type::Unit},
         {{1, Type::I32}},
         {},
         "",
         {0, {}},
         -1,
         0,
         {}},
        {Op::Move, {3, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}}},
       {Exit::Jump, {}, 1}},
      {{}, {Exit::Jump, {}, 2}},
      {{{Op::Constant, {4, Type::I32}, {}, {}, "", {-1, {}}, -1, 2, {}},
        {Op::Store,
         {5, Type::Unit},
         {{4, Type::I32}},
         {},
         "",
         {0, {}},
         -1,
         0,
         {}},
        {Op::Load, {6, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}}},
       {Exit::Return, {6, Type::I32}}}};
  program.functions.push_back(std::move(assigned));
  mettle::Diagnostics reassigned;
  mettle::analysis::initialization(program, reassigned);
  require(reassigned.items.size() == 1 &&
              reassigned.items.front().message.find("more than once") !=
                  std::string::npos,
          "moving an immutable place forgot its assignment history");

  auto pair = types->declareProduct("Pair", true);
  types->defineProduct(pair, {{"first", Type::I32}, {"second", Type::I32}});
  auto &function = program.functions.edit(0);
  function.result = pair;
  function.parameters = 1;
  function.locals = {{"flag", Type::Bool, false, {}}, {"pair", pair, true, {}}};
  function.blocks = {
      {{{Op::Load, {0, Type::Bool}, {}, {}, "", {0, {}}, -1, 0, {}},
        {Op::Declare, {1, Type::Unit}, {}, {}, "", {1, {}}, -1, 0, {}}},
       {Exit::Branch, {0, Type::Bool}, 1, 2}},
      {{{Op::Constant, {2, Type::I32}, {}, {}, "", {-1, {}}, -1, 1, {}},
        {Op::Store,
         {3, Type::Unit},
         {{2, Type::I32}},
         {},
         "",
         {1, {mettle::Projection::field(0)}},
         -1,
         0,
         {}}},
       {Exit::Jump, {}, 3}},
      {{{Op::Constant, {4, Type::I32}, {}, {}, "", {-1, {}}, -1, 2, {}},
        {Op::Store,
         {5, Type::Unit},
         {{4, Type::I32}},
         {},
         "",
         {1, {mettle::Projection::field(1)}},
         -1,
         0,
         {}}},
       {Exit::Jump, {}, 3}},
      {{{Op::Load, {6, pair}, {}, {}, "", {1, {}}, -1, 0, {}}},
       {Exit::Return, {6, pair}}}};
  mettle::Diagnostics partial;
  mettle::analysis::initialization(program, partial);
  require(partial.items.size() == 1 &&
              partial.items.front().message.find("may be uninitialized") !=
                  std::string::npos,
          "disjoint branch writes initialized an entire product");
}
void variantRefinementCases() {
  mettle::Diagnostics diagnostics;
  auto compiled = mettle::pipeline::compile(
      mettle::Source{"variants.mt",
                     "copy enum Value { Empty; Held(i32) }\n"
                     "fn unpack(value: Value) { match value { "
                     "Value.Held(payload) => payload, Value.Empty => 0 } }\n"
                     "fn main() { unpack(Value.Held(42)) }\n"},
      diagnostics);
  require(compiled.has_value(), "valid tagged pattern CFG rejected");
  auto malformed = compiled->program();
  for (std::size_t f = 0; f < malformed.functions.size(); ++f)
    if (malformed.functions[f].name == "unpack")
      for (auto &block : malformed.functions.edit(f).blocks)
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
  auto sameTarget = compiled->program();
  bool redirected = false;
  for (std::size_t f = 0; f < sameTarget.functions.size(); ++f)
    if (sameTarget.functions[f].name == "unpack")
      for (auto &block : sameTarget.functions.edit(f).blocks)
        for (const auto &instruction : block.instructions)
          if (instruction.op == Op::VariantTest && instruction.number == 1 &&
              block.exit.kind == Exit::Branch &&
              block.exit.value.id == instruction.result.id) {
            block.exit.second = block.exit.first;
            redirected = true;
          }
  require(redirected, "missing held-variant branch");
  mettle::Diagnostics unrefinedEdge;
  mettle::analysis::initialization(sameTarget, unrefinedEdge);
  require(std::any_of(unrefinedEdge.items.begin(), unrefinedEdge.items.end(),
                      [](const auto &item) {
                        return item.phase == "internal" &&
                               item.message.find("tag refinement") !=
                                   std::string::npos;
                      }),
          "same-target branch incorrectly refined a variant");
  malformed = compiled->program();
  for (std::size_t f = 0; f < malformed.functions.size(); ++f)
    for (auto &block : malformed.functions.edit(f).blocks)
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
    for (std::size_t f = 0; f < program.functions.size(); ++f)
      for (auto &block : program.functions.edit(f).blocks)
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
    auto &contract = malformed.functions.edit(instruction.callee);
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
  types.refreshProductInstances(std::array{root, pattern});
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
  types.refreshProductInstances(std::array{root});
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
    calls.set(0, info.effects);
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
  program.functions.edit(0).name = "value";
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
  changed.functions.edit(0).blocks[0].instructions[0].number = 42;
  auto invalidated =
      mettle::analysis::loans(changed, diagnostics, &program, &checked);
  require(diagnostics.empty() && invalidated.reusedFunctions == 1,
          "changed callee did not invalidate its unchanged caller");
  changed.functions.edit(0).locals.push_back({"x", Type::I32, false, {}});
  changed.functions.edit(0).blocks[0].instructions[0] = {
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
        import);
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
    dominanceCases();
    emptySpecializationCases();
    inferenceWakeupCases();
    constantValueSnapshotCases();
    coherenceCandidateCases();
    verifierCases();
    functionAddressCases();
    floatingCarrierCases();
    staticConsumptionCases();
    phaseOwnership();
    ownedValueCases();
    initializationLivenessCases();
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
