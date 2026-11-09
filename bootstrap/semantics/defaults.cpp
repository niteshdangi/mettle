#include "semantics/checker.h"
#include <functional>

namespace mettle {
void Checker::parameterDefaults(Function &function) {
  auto parameterScope = scopes.back();
  facts(function).defaultAbiResults.resize(function.parameters.size(),
                                           Type::Unknown);
  facts(function).defaultValueTypes.resize(function.parameters.size(),
                                           Type::Unknown);
  facts(function).defaultBorrowed.resize(function.parameters.size());
  facts(function).defaultBorrowOperand.resize(function.parameters.size());
  scopes.back().clear();
  bool defaulted = false;
  for (std::size_t i = 0; i < function.parameters.size(); ++i) {
    auto &parameter = function.parameters[i];
    if (parameter.defaultValue.get()) {
      defaulted = true;
      auto type =
          annotation(parameter.annotation, parameter.span, function.owner);
      flow(*parameter.defaultValue, function.owner);
      auto value = node(*parameter.defaultValue, true);
      fields(false);
      auto actual = inference.value(value);
      auto mode = facts(function).locals[i].mode;
      bool borrowed = mode == ParameterMode::Read || mode == ParameterMode::Mut;
      const auto *place = parameter.defaultValue.get();
      while (place->kind == Kind::Group || place->kind == Kind::Field ||
             (place->kind == Kind::Unary && place->text == "*"))
        place = place->children[0].get();
      bool earlierPlace =
          place->kind == Kind::Name && facts(*place).slot >= 0 &&
          (static_cast<std::size_t>(facts(*place).slot) < i ||
           (facts(function).parameterBindings.contains(facts(*place).slot) &&
            facts(function).parameterBindings.at(facts(*place).slot) < i));
      Type output = type;
      if (borrowed && checked.types->isView(actual) &&
          checked.types->view(actual).payload == type) {
        output = actual;
        value = inference.fresh(type);
        facts(function).defaultBorrowed[i] = true;
        const auto *expression = parameter.defaultValue.get();
        while (expression->kind == Kind::Group)
          expression = expression->children[0].get();
        if (expression->kind == Kind::Unary &&
            (expression->text == "read" || expression->text == "mut") &&
            (mode == ParameterMode::Read || expression->text == "mut")) {
          const auto &operand = *expression->children[0];
          if (operand.kind == Kind::Call || operand.kind == Kind::Integer ||
              operand.kind == Kind::Boolean || operand.kind == Kind::Unit) {
            output = type;
            facts(function).defaultBorrowed[i] = false;
            facts(function).defaultBorrowOperand[i] = true;
          }
        }
      } else if (borrowed && earlierPlace) {
        output = checked.types->viewType(type, mode);
        facts(function).defaultBorrowed[i] = true;
      }
      if (checked.types->isView(type) && actual == type) {
        const auto *expression = parameter.defaultValue.get();
        while (expression->kind == Kind::Group)
          expression = expression->children[0].get();
        if (expression->kind == Kind::Unary &&
            (expression->text == "read" || expression->text == "mut")) {
          const auto &operand = *expression->children[0];
          if (operand.kind == Kind::Call || operand.kind == Kind::Integer ||
              operand.kind == Kind::Boolean || operand.kind == Kind::Unit) {
            output = checked.types->view(type).payload;
            facts(function).defaultBorrowed[i] = false;
            facts(function).defaultBorrowOperand[i] = true;
          }
        }
      }
      coerce(*parameter.defaultValue, value, inference.fresh(type),
             parameter.span);
      facts(function).defaultValueTypes[i] = output;
      facts(function).defaultAbiResults[i] =
          facts(function).error == Type::Unknown
              ? output
              : checked.types->structural(AggregateKind::Outcome,
                                          {output, facts(function).error});
    } else if (defaulted)
      error("type", parameter.span,
            "required parameters cannot follow defaulted parameters");
    if (auto found = parameterScope.find(parameter.name);
        found != parameterScope.end()) {
      if (scopes.back().contains(parameter.name))
        error("name", parameter.span,
              "duplicate parameter binding '" + parameter.name + "'");
      scopes.back()[parameter.name] = found->second;
    }
    if (parameter.pattern) {
      auto variable = localVariables[&function][i];
      auto type = inference.value(variable);
      auto mode = facts(function).locals[i].mode;
      while (checked.types->isView(type)) {
        const auto &view = checked.types->view(type);
        mode = mode == ParameterMode::Read ? ParameterMode::Read : view.mode;
        type = view.payload;
        variable = inference.fresh(type);
      }
      irrefutable.emplace_back(&*parameter.pattern, variable);
      pattern(*parameter.pattern, variable, mode);
      std::function<void(const Pattern &)> bindings = [&](const Pattern &p) {
        if (facts(p).slot >= 0) {
          facts(function).parameterBindings[facts(p).slot] = i;
          auto type = inference.value(patternVariables.at(&p));
          facts(function).parameterViewTypes[facts(p).slot] = {
              checked.types->viewType(type, ParameterMode::Read),
              checked.types->viewType(type, ParameterMode::Mut)};
        }
        for (const auto &child : p.children)
          bindings(child);
      };
      bindings(*parameter.pattern);
    }
  }
}

void Checker::completeArguments(Node &node, Function &function,
                                const std::vector<bool> &used,
                                bool reportMissing) {
  for (std::size_t i = 0; i < function.parameters.size(); ++i) {
    if (i < used.size() && used[i])
      continue;
    if (function.parameters[i].defaultValue.get())
      facts(node).defaultArguments.push_back(i);
    else if (reportMissing)
      error("type", node.span,
            "missing required argument '" + function.parameters[i].name + "'");
  }
}
} // namespace mettle
