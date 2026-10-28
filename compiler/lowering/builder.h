#pragma once

#include "lowering/scalar.h"
#include "support/limits.h"
#include <map>
#include <stdexcept>

namespace mettle::lowering {
struct LoweringLimit : std::runtime_error {
  explicit LoweringLimit(const char *message) : std::runtime_error(message) {}
};
class Builder {
public:
  explicit Builder(const CheckedModule &module) : module(module) {}
  ir::Function run(const mettle::Function &source, std::size_t index);

private:
  using Value = ir::Value;
  using Instruction = ir::Instruction;
  using Terminator = ir::Terminator;
  const CheckedModule &module;
  ir::Function function;
  int current = 0, blockScope = 0, temporaryScope = 0, extensionScope = -1;
  std::uint32_t order = 0;
  struct Loop {
    int header, done;
    std::size_t depth;
  };
  std::vector<Loop> loops;
  std::vector<int> scopes{0};
  std::map<int, Place> owners;
  int block();
  bool live();
  void terminate(Terminator exit);
  Value emit(Instruction instruction, Type type,
             ir::Access access = ir::Access::Owned);
  Value constant(Type type, std::int32_t number = 0);
  Value unit();
  void jump(int target);
  void branch(const Node &condition, Value value, int a, int b);
  Value merge(Type type, const std::vector<Value> &values,
              const std::vector<int> &blocks);
  Value expression(const Node &node, bool consume = false,
                   bool valueUsed = true);
  Value callExpression(const Node &node);
  Value blockExpression(const Node &node, bool valueUsed = true);
  int scope();
  void endScope();
  void exitTo(std::size_t depth);
  Value track(Value value, Span span, int targetScope = -1);
  Value use(Value value);
  Place materialize(Value value, Span span, int targetScope);
  Place place(const Node &node, bool extend = false);
  Value borrow(const Node &node, ParameterMode mode, bool reserved = false,
               bool firstClass = false, Type resultType = Type::Unknown,
               unsigned dereferences = 0);
  void returnValue(Value value, Span span);
};
} // namespace mettle::lowering
