#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
ir::Value Builder::expression(const Node &node, bool consume, bool valueUsed) {
  if (!live())
    return {};
  const auto &facts = module.facts(node);
  switch (node.kind) {
  case Kind::Integer:
  case Kind::Boolean:
    return constant(facts.type, facts.number);
  case Kind::Unit:
    return unit();
  case Kind::Group:
    return expression(*node.children[0], consume, valueUsed);
  case Kind::Name:
  case Kind::Field: {
    auto location = place(node);
    if (!live())
      return {};
    return track(
        emit({consume || !module.typeStore()->isCopy(facts.type) ? Op::Move
                                                                 : Op::Load,
              {},
              {},
              {},
              "",
              location,
              -1,
              0,
              node.span},
             facts.type),
        node.span);
  }
  case Kind::Unary: {
    if (node.text == "take")
      return expression(*node.children[0], true);
    if (node.text == "read" || node.text == "mut")
      return borrow(*node.children[0],
                    node.text == "read" ? ParameterMode::Read
                                        : ParameterMode::Mut,
                    false, true, facts.type);
    if (node.text == "*") {
      auto location = place(node);
      if (!live())
        return {};
      return track(
          emit({consume || !module.typeStore()->isCopy(facts.type) ? Op::Move
                                                                   : Op::Load,
                {},
                {},
                {},
                "",
                location,
                -1,
                0,
                node.span},
               facts.type),
          node.span);
    }
    if (facts.foldedNegativeLiteral)
      return constant(Type::I32, facts.number);
    auto value = use(expression(*node.children[0]));
    if (!live())
      return {};
    return emit(
        {Op::Unary, {}, {value}, {}, node.text, {-1, {}}, -1, 0, node.span},
        facts.type);
  }
  case Kind::Call:
    return callExpression(node);
  case Kind::Block:
    return blockExpression(node, valueUsed);
  case Kind::Binary: {
    int savedTemporary = temporaryScope;
    bool shortCircuit = node.text == "&&" || node.text == "||";
    if (shortCircuit)
      temporaryScope = scope();
    auto left = use(expression(*node.children[0]));
    if (shortCircuit) {
      endScope();
      temporaryScope = savedTemporary;
    }
    if (!live())
      return {};
    if (!shortCircuit) {
      auto right = use(expression(*node.children[1]));
      if (!live())
        return {};
      return emit({Op::Binary,
                   {},
                   {left, right},
                   {},
                   node.text,
                   {-1, {}},
                   -1,
                   0,
                   node.span},
                  facts.type);
    }
    auto literal = booleanLiteral(*node.children[0]);
    if ((node.text == "&&" && literal == false) ||
        (node.text == "||" && literal == true))
      return left;
    int right = block(), shortcut = block(), done = block();
    branch(*node.children[0], left, node.text == "&&" ? right : shortcut,
           node.text == "&&" ? shortcut : right);
    std::vector<Value> values;
    std::vector<int> predecessors;
    current = shortcut;
    values.push_back(constant(Type::Bool, node.text == "||"));
    predecessors.push_back(current);
    jump(done);
    current = right;
    temporaryScope = scope();
    auto value = use(expression(*node.children[1]));
    endScope();
    temporaryScope = savedTemporary;
    if (live()) {
      values.push_back(value);
      predecessors.push_back(current);
      jump(done);
    }
    current = done;
    return merge(Type::Bool, values, predecessors);
  }
  case Kind::If: {
    int savedTemporary = temporaryScope;
    temporaryScope = scope();
    auto condition = use(expression(*node.children[0]));
    endScope();
    temporaryScope = savedTemporary;
    if (!live())
      return {};
    int yes = block(), no = block(), done = block();
    branch(*node.children[0], condition, yes, no);
    std::vector<Value> values;
    std::vector<int> predecessors;
    auto literal = booleanLiteral(*node.children[0]);
    current = yes;
    if (literal == false)
      terminate({Exit::Unreachable});
    auto a = expression(*node.children[1], false, valueUsed);
    if (live()) {
      values.push_back(use(a));
      predecessors.push_back(current);
      jump(done);
    }
    current = no;
    if (literal == true)
      terminate({Exit::Unreachable});
    auto b = node.children.size() == 3
                 ? expression(*node.children[2], false, valueUsed)
                 : unit();
    if (live()) {
      values.push_back(use(b));
      predecessors.push_back(current);
      jump(done);
    }
    current = done;
    if (!facts.flow.normal) {
      terminate({Exit::Unreachable});
      return {};
    }
    return track(
        merge(valueUsed ? facts.type : Type::Unit, values, predecessors),
        node.span);
  }
  case Kind::Binding: {
    if (facts.slot >= 0) {
      function.locals[facts.slot].scope = blockScope;
      function.locals[facts.slot].order = order++;
      emit({Op::Declare, {}, {}, {}, "", {facts.slot, {}}, -1, 0, node.span},
           Type::Unit);
    }
    if (!node.children.empty()) {
      if (facts.slot < 0 && module.facts(*node.children[0]).place)
        return unit();
      int saved = extensionScope;
      extensionScope = blockScope;
      auto value = expression(*node.children[0], false, facts.slot >= 0);
      extensionScope = saved;
      if (live() && facts.slot >= 0)
        emit({Op::Store,
              {},
              {use(value)},
              {},
              "",
              {facts.slot, {}},
              -1,
              0,
              node.span},
             Type::Unit);
    }
    return unit();
  }
  case Kind::Assign: {
    auto value = expression(*node.children[1]);
    if (!live())
      return {};
    auto location = place(*node.children[0]);
    if (!live())
      return {};
    if (node.text != "=") {
      auto old = emit({Op::Load, {}, {}, {}, "", location, -1, 0, node.span},
                      module.facts(*node.children[0]).type);
      value = emit({Op::Binary,
                    {},
                    {old, use(value)},
                    {},
                    node.text.substr(0, node.text.size() - 1),
                    {-1, {}},
                    -1,
                    0,
                    node.span},
                   old.type);
    }
    emit({Op::Store, {}, {use(value)}, {}, "", location, -1, 0, node.span},
         Type::Unit);
    return unit();
  }
  case Kind::Return: {
    auto value = node.children.empty() ? unit() : expression(*node.children[0]);
    if (live())
      returnValue(value, node.span);
    return {};
  }
  case Kind::While:
  case Kind::Loop: {
    int header = block(), body = block(), done = block();
    jump(header);
    current = header;
    if (node.kind == Kind::While) {
      int savedTemporary = temporaryScope;
      temporaryScope = scope();
      auto condition = use(expression(*node.children[0]));
      endScope();
      temporaryScope = savedTemporary;
      branch(*node.children[0], condition, body, done);
    } else
      jump(body);
    current = body;
    loops.push_back({header, done, scopes.size()});
    if (node.kind == Kind::While &&
        (!module.facts(*node.children[0]).flow.normal ||
         booleanLiteral(*node.children[0]) == false))
      terminate({Exit::Unreachable});
    blockExpression(*node.children.back(), false);
    loops.pop_back();
    jump(header);
    current = done;
    if (!facts.flow.normal) {
      terminate({Exit::Unreachable});
      return {};
    }
    return unit();
  }
  case Kind::Break:
    exitTo(loops.back().depth);
    jump(loops.back().done);
    return {};
  case Kind::Continue:
    exitTo(loops.back().depth);
    jump(loops.back().header);
    return {};
  }
  throw std::runtime_error("unhandled checked syntax node");
}
} // namespace mettle::lowering
