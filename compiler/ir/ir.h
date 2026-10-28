#pragma once

#include "places/place.h"
#include "source/source.h"
#include "types/type.h"
#include <cstdint>
#include <memory>
#include <ostream>
#include <vector>

namespace mettle::ir {
enum class Access { Owned, Read, Mut };
struct Value {
  int id = -1;
  Type type = Type::Never;
  Access access = Access::Owned;
};
struct Local {
  std::string name;
  Type type;
  bool mutableBinding;
  Span span;
  ParameterMode mode = ParameterMode::Value;
  int scope = 0;
  std::uint32_t order = 0;
};
enum class Op {
  Constant,
  Declare,
  Load,
  Store,
  Unary,
  Binary,
  Call,
  Phi,
  Construct,
  Project,
  Move,
  BorrowRead,
  BorrowMut,
  ReserveMut,
  Activate,
  ViewRead,
  ViewMut,
  ScopeExit,
  CatchCall
};
struct Instruction {
  Op op;
  Value result;
  std::vector<Value> operands;
  std::vector<int> predecessors;
  std::string text;
  Place place;
  int callee = -1;
  std::int32_t number = 0;
  Span span;
};
enum class Exit { None, Jump, Branch, Return, Unreachable };
struct Terminator {
  Exit kind = Exit::None;
  Value value{};
  int first = -1;
  int second = -1;
};
struct Block {
  std::vector<Instruction> instructions;
  Terminator exit;
};
struct Function {
  std::string name;
  Type result;
  std::size_t parameters;
  std::vector<Local> locals;
  std::vector<Block> blocks;
  int values = 0;
  struct Scope {
    int parent = -1;
  };
  std::vector<Scope> scopes{{-1}};
  std::vector<std::size_t> resultSources{};
  std::string externalName{};
  bool twoPhaseReceiver = false;
};
struct Program {
  std::vector<Function> functions;
  std::shared_ptr<const TypeStore> types = std::make_shared<const TypeStore>();
};

void print(const Program &program, std::ostream &out);
} // namespace mettle::ir
