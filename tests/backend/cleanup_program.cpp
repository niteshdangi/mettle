#include "backend/llvm/lower.h"
#include "pipeline/compile.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/raw_ostream.h"
#include <iostream>

namespace {
using namespace mettle;

struct Fixture {
  ir::Function function{};
  unsigned block = 0;

  Fixture(std::string name, Type result, std::vector<ir::Local> locals = {},
          std::size_t parameters = 0) {
    function.name = std::move(name);
    function.result = result;
    function.locals = std::move(locals);
    function.parameters = parameters;
    function.blocks.resize(1);
  }

  ir::Value emit(ir::Op op, Type type, std::vector<ir::Value> operands = {},
                 Place place = {}, int callee = -1, int number = 0,
                 std::string text = {}, ir::Access access = ir::Access::Owned) {
    ir::Value result{function.values++, type, access};
    function.blocks[block].instructions.push_back({op,
                                                   result,
                                                   std::move(operands),
                                                   {},
                                                   std::move(text),
                                                   std::move(place),
                                                   callee,
                                                   number,
                                                   {}});
    return result;
  }

  ir::Value constant(int number) {
    return emit(ir::Op::Constant, Type::I32, {}, {}, -1, number);
  }

  void returnUnit() {
    emit(ir::Op::ScopeExit, Type::Unit);
    auto unit = emit(ir::Op::Constant, Type::Unit);
    function.blocks[block].exit = {ir::Exit::Return, unit};
  }
};

ir::Function external(std::string name, Type result,
                      std::vector<ir::Local> parameters) {
  ir::Function function{};
  function.name = name;
  function.externalName = std::move(name);
  function.result = result;
  function.parameters = parameters.size();
  function.locals = std::move(parameters);
  return function;
}

ir::Local parameter(std::string name, Type type, ParameterMode mode) {
  return {std::move(name), type, true, {}, mode};
}

ir::Function destructor(std::string name, Type type, int observer, int panicTag,
                        std::vector<Projection> tag) {
  Fixture fixture(std::move(name), Type::Unit,
                  {parameter("self", type, ParameterMode::Mut)}, 1);
  fixture.function.blocks.resize(3);
  auto self = fixture.emit(ir::Op::BorrowMut, type, {}, {0, {}}, -1, 0, {},
                           ir::Access::Mut);
  fixture.emit(ir::Op::Call, Type::Unit, {self}, {}, observer);
  auto value = fixture.emit(ir::Op::Load, Type::I32, {}, {0, std::move(tag)});
  auto wanted = fixture.constant(panicTag);
  auto matches = fixture.emit(ir::Op::Binary, Type::Bool, {value, wanted}, {},
                              -1, 0, "==");
  fixture.function.blocks[0].exit = {ir::Exit::Branch, matches, 1, 2};
  fixture.block = 1;
  auto one = fixture.constant(1);
  auto zero = fixture.constant(0);
  fixture.emit(ir::Op::Binary, Type::I32, {one, zero}, {}, -1, 0, "/");
  fixture.returnUnit();
  fixture.block = 2;
  fixture.returnUnit();
  return std::move(fixture.function);
}
} // namespace

int main(int argc, char **) {
  using namespace mettle;
  auto types = std::make_shared<TypeStore>();
  auto leaf = types->declareProduct("Leaf", false);
  auto resource = types->declareProduct("Resource", false);
  types->defineProduct(leaf, {{"tag", Type::I32}});
  types->defineProduct(resource, {{"first", leaf}, {"second", leaf}});
  auto view = types->viewType(resource, ParameterMode::Mut);
  ir::Program program;
  program.types = types;
  program.functions.push_back(
      external("mettle_test_cleanup_leaf", Type::Unit,
               {parameter("self", leaf, ParameterMode::Mut)}));
  program.functions.push_back(
      external("mettle_test_cleanup_parent", Type::Unit,
               {parameter("self", resource, ParameterMode::Mut)}));
  program.functions.push_back(
      external("mettle_test_cleanup_target", view,
               {parameter("mode", Type::I32, ParameterMode::Value)}));
  program.functions.push_back(
      external("mettle_test_cleanup_result", Type::I32,
               {parameter("code", Type::I32, ParameterMode::Value),
                parameter("target", resource, ParameterMode::Read)}));
  program.functions.push_back(
      destructor("drop_leaf", leaf, 0, 99, {Projection::field(0)}));
  program.functions.push_back(
      destructor("drop_resource", resource, 1, 20,
                 {Projection::field(0), Projection::field(0)}));
  types->setDestructor(leaf, 4);
  types->setDestructor(resource, 5);

  Fixture replacement(
      "replace", Type::Unit,
      {parameter("target", resource, ParameterMode::Mut),
       {"first", leaf, true, {}, ParameterMode::Value, 0, 1},
       {"second", leaf, true, {}, ParameterMode::Value, 0, 2},
       {"pending", resource, true, {}, ParameterMode::Value, 0, 3}},
      1);
  for (int local : {1, 2, 3})
    replacement.emit(ir::Op::Declare, Type::Unit, {}, {local, {}});
  for (int local : {1, 2}) {
    auto tag = replacement.constant(29 + local);
    auto value = replacement.emit(ir::Op::Construct, leaf, {tag});
    replacement.emit(ir::Op::Store, Type::Unit, {value}, {local, {}});
  }
  auto first = replacement.emit(ir::Op::Move, leaf, {}, {1, {}});
  auto second = replacement.emit(ir::Op::Move, leaf, {}, {2, {}});
  auto pending = replacement.emit(ir::Op::Construct, resource, {first, second});
  replacement.emit(ir::Op::Store, Type::Unit, {pending}, {3, {}});
  auto moved = replacement.emit(ir::Op::Move, resource, {}, {3, {}});
  replacement.emit(ir::Op::Store, Type::Unit, {moved}, {0, {}});
  replacement.returnUnit();
  program.functions.push_back(std::move(replacement.function));

  Fixture entry("main", Type::I32, {{"target", view, true, {}}});
  entry.emit(ir::Op::Declare, Type::Unit, {}, {0, {}});
  auto mode = entry.constant(argc > 1 ? 1 : 0);
  auto pointer = entry.emit(ir::Op::Call, view, {mode}, {}, 2);
  entry.emit(ir::Op::Store, Type::Unit, {pointer}, {0, {}});
  Place referent{0, {Projection::dereference()}};
  auto exclusive = entry.emit(ir::Op::BorrowMut, resource, {}, referent, -1, 0,
                              {}, ir::Access::Mut);
  auto caught = entry.emit(ir::Op::CatchCall, Type::I32, {exclusive}, {}, 6);
  auto shared = entry.emit(ir::Op::BorrowRead, resource, {}, referent, -1, 0,
                           {}, ir::Access::Read);
  auto result = entry.emit(ir::Op::Call, Type::I32, {caught, shared}, {}, 3);
  entry.emit(ir::Op::ScopeExit, Type::Unit);
  entry.function.blocks[0].exit = {ir::Exit::Return, result};
  program.functions.push_back(std::move(entry.function));

  Diagnostics diagnostics;
  auto verified = pipeline::admit(std::move(program), diagnostics);
  if (!verified) {
    for (const auto &diagnostic : diagnostics.items)
      std::cerr << diagnostic.phase << ": " << diagnostic.message << '\n';
    return 1;
  }
  llvm::LLVMContext context;
  auto module = backend::lower(*verified, context, true);
  if (llvm::verifyModule(*module, &llvm::errs()))
    return 1;
  module->print(llvm::outs(), nullptr);
}
