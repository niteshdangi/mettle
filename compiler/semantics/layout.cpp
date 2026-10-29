#include "semantics/checker.h"
#include <functional>

namespace mettle {
void Checker::checkBorrowAlignment() {
  auto function = [&](const Function &declaration, const FunctionFacts &owner) {
    auto aligned = [&](const Node &expression, bool throughView = false) {
      const auto &resolved = checked.nodes.at(&expression);
      if (throughView && checked.types->isView(resolved.type))
        return true;
      if (!resolved.place)
        return true;
      auto place = *resolved.place;
      if (place.root < 0 ||
          static_cast<std::size_t>(place.root) >= owner.locals.size())
        return true;
      return alignedPlace(*checked.types, owner.locals[place.root].type,
                          place.fields);
    };
    auto require = [&](const Node &expression, bool throughView = false) {
      if (!aligned(expression, throughView))
        error("alignment", expression.span,
              "unaligned storage cannot form an ordinary view; use an explicit "
              "unaligned operation");
    };
    std::function<void(const Node &)> walk = [&](const Node &node) {
      if (node.kind == Kind::Closure)
        return;
      for (const auto &child : node.children)
        walk(*child);
      const auto &resolved = checked.nodes.at(&node);
      if (node.kind == Kind::Unary &&
          (node.text == "read" || node.text == "mut"))
        require(*node.children[0]);
      if (node.kind != Kind::Call)
        return;
      if (!resolved.machineOperation.empty()) {
        std::vector<const Node *> operands;
        if (resolved.method)
          operands.push_back(node.children[0]->children[0].get());
        for (std::size_t i = 1; i < node.children.size(); ++i)
          operands.push_back(node.children[i].get());
        for (std::size_t i = 0; i < operands.size(); ++i)
          if (resolved.machineBorrowModes[i] == ParameterMode::Read ||
              resolved.machineBorrowModes[i] == ParameterMode::Mut)
            require(*operands[i], true);
      } else if (resolved.callee >= 0 && !resolved.constructor) {
        const auto &callee = checked.functions[resolved.callee];
        if (resolved.method && !callee.locals.empty() &&
            (callee.locals[0].mode == ParameterMode::Read ||
             callee.locals[0].mode == ParameterMode::Mut))
          require(*node.children[0]->children[0], true);
        for (std::size_t i = 1; i < node.children.size(); ++i) {
          auto target = resolved.argumentOrder[i - 1];
          if (target < callee.locals.size() &&
              (callee.locals[target].mode == ParameterMode::Read ||
               callee.locals[target].mode == ParameterMode::Mut))
            require(*node.children[i], true);
        }
      }
    };
    if (declaration.body.get())
      walk(*declaration.body);
    for (const auto &parameter : declaration.parameters)
      if (parameter.defaultValue.get())
        walk(*parameter.defaultValue);
  };
  for (std::size_t i = 0; i < module.functions.size(); ++i)
    function(module.functions[i], checked.functions[i]);
  for (const auto &closure : checked.closureBodies)
    function(closure->declaration, closure->function);
}
} // namespace mettle
