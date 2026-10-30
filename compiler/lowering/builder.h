#pragma once

#include "lowering/scalar.h"
#include "support/limits.h"
#include <map>
#include <stdexcept>

namespace mettle::lowering {
struct LoweringLimit : std::runtime_error {
  explicit LoweringLimit(const char *message) : std::runtime_error(message) {}
};
void callableContracts(ir::Program &program);
class Builder {
public:
  explicit Builder(const CheckedModule &module) : module(module) {}
  ir::Function run(const mettle::Function &source, std::size_t index);
  ir::Function runDefault(const mettle::Function &source, std::size_t index,
                          std::size_t parameter);
  ir::Function runClosure(std::size_t index);

private:
  using Value = ir::Value;
  using Instruction = ir::Instruction;
  using Terminator = ir::Terminator;
  const CheckedModule &module;
  ir::Function function;
  int current = 0, blockScope = 0, temporaryScope = 0, extensionScope = -1;
  std::uint32_t order = 0;
  Type errorType = Type::Unknown;
  unsigned unsafeDepth = 0;
  struct Loop {
    int header, done;
    std::size_t depth;
    int control;
    std::vector<Value> values;
    std::vector<int> predecessors;
  };
  std::vector<Loop> loops;
  std::vector<int> scopes{0};
  std::map<int, Place> owners;
  std::map<int, int> localRemap;
  std::map<const Node *, Place> placeOverrides;
  struct ProjectedLocal {
    Place place;
    unsigned skip = 0;
  };
  std::map<int, ProjectedLocal> projectedLocals;
  std::vector<std::pair<Place, Place>> capturedPlaces;
  int localSlot(int slot) const {
    auto found = localRemap.find(slot);
    return found == localRemap.end() ? slot : found->second;
  }
  int constructorSelfSlot = -1;
  struct EffectHandler {
    std::size_t depth;
    int failed;
    std::vector<Value> errors;
    std::vector<int> predecessors;
  };
  std::vector<EffectHandler> effectHandlers;
  Value unwrapOutcome(Value value, Span span);
  void fail(Value error, Span span);
  int defaultIndex(std::size_t callee, std::size_t parameter) const;
  struct DefaultFailurePaths {
    int done = -1;
    Type type = Type::Unknown;
    std::vector<Value> values;
    std::vector<int> blocks;
  };
  Value defaultArgument(std::size_t callee, std::size_t parameter,
                        std::vector<Value> &arguments,
                        std::vector<std::optional<Place>> &pending,
                        DefaultFailurePaths &failures, Span span,
                        const NodeFacts *call = nullptr);
  int block();
  bool live();
  void terminate(Terminator exit);
  Value emit(Instruction instruction, Type type,
             ir::Access access = ir::Access::Owned);
  Value constant(Type type, std::int32_t number = 0);
  Value constant(Type type, const NumericLiteral &number);
  Value unit();
  void jump(int target);
  void branch(const Node &condition, Value value, int a, int b);
  Value merge(Type type, const std::vector<Value> &values,
              const std::vector<int> &blocks);
  Value expression(const Node &node, bool consume = false,
                   bool valueUsed = true);
  Type sourceType(const Node &node) const {
    const auto &facts = module.facts(node);
    if (facts.opaqueSource != Type::Unknown)
      return facts.opaqueSource;
    if (facts.unsizedSource != Type::Unknown)
      return facts.unsizedSource;
    if (facts.erasedSource != Type::Unknown)
      return facts.erasedSource;
    if (facts.reborrowSource != Type::Unknown)
      return facts.reborrowSource;
    return facts.callableSource == Type::Unknown ? facts.type
                                                 : facts.callableSource;
  }
  Value rawExpression(const Node &node, bool consume, bool valueUsed);
  Value machineExpression(const Node &node);
  Value assemblyExpression(const Node &node);
  Value callExpression(const Node &node);
  Place receiverSource(const Node &node, bool extend = false);
  Place capturePlace(Place source) const;
  Place receiverPlace(Place source, const ReceiverPlan &plan, Span span);
  Value receiverBorrow(const Node &node, const ReceiverPlan &plan,
                       ParameterMode mode, bool reserved = false,
                       Type view = Type::Unknown);
  Value convertedView(const Node &node);
  bool callHasFailure(const Node &node) const;
  Value erasedView(Place source, Type concrete, Type view, Span span);
  Value erasedArgument(const Node &node, ParameterMode mode);
  Value unsizedView(Place source, Type view, Type count, Span span);
  Value unsizedArgument(const Node &node, ParameterMode mode);
  Value viewCoercion(const Node &node);
  void dynamicDispatch(Instruction &call, const NodeFacts &facts, Span span);
  Value operatorExpression(const Node &node);
  Place rangePlace(const Node &node, Place source, bool exclusive);
  Value callableExpression(const Node &node);
  Value indirectCallExpression(const Node &node);
  int closureIndex(std::size_t index) const;
  std::vector<Type> closureArguments(Type type) const;
  Value loopExpression(const Node &node);
  Value transferExpression(const Node &node);
  Value sumExpression(const Node &node);
  Value optionalExpression(const Node &node);
  Value aggregateExpression(const Node &node, bool valueUsed,
                            bool consume = false);
  Place indexPlace(const Node &node, bool exclusive);
  Value matchExpression(const Node &node, bool valueUsed);
  Value bindingPatternExpression(const Node &node);
  Value conditionalPatternExpression(const Node &node, bool valueUsed);
  Value whilePatternExpression(const Node &node);
  void patternTest(const Pattern &pattern, const Place &place, int yes, int no);
  void patternBind(const Pattern &pattern, const Place &place,
                   ParameterMode mode, bool guard = false);
  Value variant(Type type, int tag, std::vector<Value> operands, Span span);
  Value blockExpression(const Node &node, bool valueUsed = true);
  int scope();
  void endScope(Span span = {});
  void exitTo(std::size_t depth, Span span = {});
  void finishControlFlow();
  Value track(Value value, Span span, int targetScope = -1);
  Value use(Value value);
  Place materialize(Value value, Span span, int targetScope);
  Place place(const Node &node, bool extend = false, bool exclusive = false,
              bool adapt = true);
  Value borrow(const Node &node, ParameterMode mode, bool reserved = false,
               bool firstClass = false, Type resultType = Type::Unknown,
               unsigned dereferences = 0);
  void returnValue(Value value, Span span, bool failure = false);
};
} // namespace mettle::lowering
