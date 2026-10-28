#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
Builder::Value Builder::callExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto count = node.children.size() - 1 + (facts.method ? 1 : 0);
  std::vector<Value> arguments(count);
  int previousExtension = extensionScope;
  if (!facts.constructor)
    extensionScope = -1;
  auto argument = [&](const Node &expression, std::size_t target, bool reserve,
                      bool receiver = false) {
    auto mode = facts.constructor
                    ? ParameterMode::Value
                    : module.function(facts.callee).locals[target].mode;
    if (mode == ParameterMode::Read || mode == ParameterMode::Mut) {
      auto actual = module.facts(expression).type;
      auto expected = module.function(facts.callee).locals[target].type;
      auto dereferences = receiver ? facts.dereferences
                                   : static_cast<unsigned>(actual != expected);
      return borrow(expression, mode, reserve, false, Type::Unknown,
                    dereferences);
    }
    if (receiver && facts.dereferences) {
      auto location = place(expression);
      for (unsigned i = 0; i < facts.dereferences; ++i)
        location.fields.push_back(Projection::dereference());
      auto type = module.function(facts.callee).locals[0].type;
      return track(
          emit({mode == ParameterMode::Take || !module.typeStore()->isCopy(type)
                    ? Op::Move
                    : Op::Load,
                {},
                {},
                {},
                "",
                location,
                -1,
                0,
                expression.span},
               type),
          expression.span);
    }
    return this->expression(expression, mode == ParameterMode::Take);
  };
  if (facts.method) {
    arguments[0] = argument(*node.children[0]->children[0], 0,
                            facts.receiverReservation, true);
    if (!live()) {
      extensionScope = previousExtension;
      return {};
    }
  }
  for (std::size_t i = 1; i < node.children.size(); ++i) {
    auto target = facts.argumentOrder[i - 1];
    arguments[target] = argument(*node.children[i], target, false);
    if (!live()) {
      extensionScope = previousExtension;
      return {};
    }
  }
  for (auto &value : arguments)
    value = use(value);
  if (facts.receiverReservation)
    emit({Op::Activate, {}, {arguments[0]}, {}, "", {-1, {}}, -1, 0, node.span},
         Type::Unit);
  auto result = emit({facts.constructor ? Op::Construct : Op::Call,
                      {},
                      arguments,
                      {},
                      "",
                      {-1, {}},
                      facts.constructor ? -1 : facts.callee,
                      0,
                      node.span},
                     facts.type);
  extensionScope = previousExtension;
  if (facts.type == Type::Never)
    terminate({Exit::Unreachable});
  return track(result, node.span);
}
} // namespace mettle::lowering
