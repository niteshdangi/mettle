#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
ir::Value Builder::expression(const Node &node, bool consume, bool valueUsed) {
  const auto &facts = module.facts(node);
  if (facts.viewConversion) {
    auto value = convertedView(node);
    if (live())
      for (auto type : facts.injections)
        value = variant(type, 1, {value}, node.span);
    return value;
  }
  bool adapted = module.typeStore()->isView(facts.type) &&
                 (facts.erasedSource != Type::Unknown ||
                  facts.unsizedSource != Type::Unknown ||
                  facts.reborrowSource != Type::Unknown);
  auto value = facts.ownerUnsizeSource != Type::Unknown ? ownerCoercion(node)
               : adapted ? viewCoercion(node)
                         : rawValue(node, consume, valueUsed);
  if (live() && facts.opaqueSource != Type::Unknown)
    value = track(emit({Op::Construct,
                        {},
                        {use(value)},
                        {},
                        "",
                        {-1, {}},
                        -1,
                        0,
                        node.span},
                       facts.type),
                  node.span);
  if (live() && facts.callableCoercion != Type::Unknown &&
      value.type != facts.callableCoercion) {
    if (module.typeStore()->isFunctionPointer(value.type))
      value = emit(
          {Op::CallableCoerce, {}, {value}, {}, "", {-1, {}}, -1, 0, node.span},
          facts.callableCoercion);
    else {
      auto closure = module.typeStore()->callable(value.type).function;
      Instruction address{Op::FunctionAddress,
                          {},
                          {},
                          {},
                          "",
                          {-1, {}},
                          closureIndex(static_cast<std::size_t>(closure)),
                          0,
                          node.span};
      address.typeArguments = closureArguments(value.type);
      value = emit(std::move(address), facts.callableCoercion);
    }
  }
  if (live())
    for (auto type : module.facts(node).injections)
      value = variant(type, 1, {value}, node.span);
  return value;
}
ir::Value Builder::rawValue(const Node &node, bool consume, bool valueUsed) {
  auto value = rawExpression(node, consume, valueUsed);
  const auto &facts = module.facts(node);
  if (live() && (node.kind == Kind::Call || facts.operatorCall) &&
      facts.effect != Type::Unknown && !facts.optional && callHasFailure(node))
    value = unwrapOutcome(value, node.span);
  return value;
}
// Reading a Copy value through a view copies it; only owned places move.
static bool throughView(const Place &place) {
  return std::any_of(place.fields.begin(), place.fields.end(),
                     [](const Projection &projection) {
                       return projection.kind == Projection::Kind::Dereference;
                     });
}
ir::Value Builder::rawExpression(const Node &node, bool consume,
                                 bool valueUsed) {
  if (!live())
    return {};
  const auto &facts = module.facts(node);
  if (facts.operatorCall)
    return operatorExpression(node);
  switch (node.kind) {
  case Kind::Assembly:
    return assemblyExpression(node);
  case Kind::FeatureTest:
    return emit(
        {Op::FeatureTest, {}, {}, {}, node.text, {-1, {}}, -1, 0, node.span},
        Type::Bool);
  case Kind::Integer:
  case Kind::Floating:
    if (facts.numeric) {
      Instruction instruction{Op::Constant, {}, {}, {},       "",
                              {-1, {}},     -1, 0,  node.span};
      instruction.numeric = facts.numeric;
      return emit(std::move(instruction), sourceType(node));
    }
    return constant(sourceType(node), facts.number);
  case Kind::Text:
    return emit(
        {Op::TextLiteral, {}, {}, {}, facts.text, {-1, {}}, -1, 0, node.span},
        sourceType(node));
  case Kind::Boolean:
  case Kind::Character:
    return constant(sourceType(node), facts.number);
  case Kind::Unit:
    return unit();
  case Kind::Unsafe: {
    auto depth = unsafeDepth;
    ++unsafeDepth;
    auto value = expression(*node.children[0], consume, valueUsed);
    unsafeDepth = depth;
    return value;
  }
  case Kind::Group:
    return expression(*node.children[0], consume, valueUsed);
  case Kind::Name:
  case Kind::Field: {
    if (facts.machineOperation == "marker.phantom_pinned")
      return emit({Op::Construct, {}, {}, {}, "", {-1, {}}, -1, 0, node.span},
                  sourceType(node));
    if (facts.numeric) {
      Instruction instruction{Op::Constant, {}, {}, {},       "",
                              {-1, {}},     -1, 0,  node.span};
      instruction.numeric = facts.numeric;
      return emit(std::move(instruction), sourceType(node));
    }
    if (node.kind == Kind::Name && facts.callee >= 0)
      return callableExpression(node);
    if (facts.constantParameter != Type::Unknown) {
      Instruction instruction{Op::Constant, {}, {}, {},       "",
                              {-1, {}},     -1, 0,  node.span};
      instruction.constantParameter = facts.constantParameter;
      return emit(std::move(instruction), sourceType(node));
    }
    if (facts.optional)
      return optionalExpression(node);
    if (facts.variant >= 0)
      return sumExpression(node);
    auto location = place(node, false, false, false);
    if (!live())
      return {};
    auto loadedType = sourceType(node);
    return track(emit({(consume && !throughView(location)) ||
                               !module.typeStore()->isCopy(loadedType)
                           ? Op::Move
                           : Op::Load,
                       {},
                       {},
                       {},
                       "",
                       location,
                       -1,
                       0,
                       node.span},
                      loadedType),
                 node.span);
  }
  case Kind::Tuple:
  case Kind::Array:
  case Kind::Index:
  case Kind::Range:
  case Kind::For:
  case Kind::Coalesce:
    return aggregateExpression(node, valueUsed, consume);
  case Kind::Unary: {
    if (node.text == "take")
      return expression(*node.children[0], true);
    if (node.text == "read" || node.text == "mut")
      return borrow(*node.children[0],
                    node.text == "read" ? ParameterMode::Read
                                        : ParameterMode::Mut,
                    false, true, sourceType(node));
    if (node.text == "*") {
      auto location = place(node, false, false, false);
      if (!live())
        return {};
      auto loadedType = sourceType(node);
      return track(emit({(consume && !throughView(location)) ||
                                 !module.typeStore()->isCopy(loadedType)
                             ? Op::Move
                             : Op::Load,
                         {},
                         {},
                         {},
                         "",
                         location,
                         -1,
                         0,
                         node.span},
                        loadedType),
                   node.span);
    }
    if (facts.foldedNegativeLiteral) {
      Instruction instruction{Op::Constant, {}, {}, {},       "",
                              {-1, {}},     -1, 0,  node.span};
      instruction.numeric = facts.numeric;
      return emit(std::move(instruction), sourceType(node));
    }
    auto value = use(expression(*node.children[0]));
    if (!live())
      return {};
    return emit(
        {Op::Unary, {}, {value}, {}, node.text, {-1, {}}, -1, 0, node.span},
        sourceType(node));
  }
  case Kind::Call:
    if (!facts.machineOperation.empty())
      return machineExpression(node);
    if (facts.optional)
      return optionalExpression(node);
    if (facts.indirect)
      return indirectCallExpression(node);
    if (facts.variant >= 0)
      return sumExpression(node);
    return callExpression(node);
  case Kind::Cast: {
    auto operand = use(expression(*node.children[0]));
    if (!live())
      return {};
    return emit({Op::Cast, {}, {operand}, {}, "", {-1, {}}, -1, 0, node.span},
                sourceType(node));
  }
  case Kind::Closure:
    return callableExpression(node);
  case Kind::None:
  case Kind::Variant:
  case Kind::Throw:
  case Kind::Try:
  case Kind::Capture:
    return sumExpression(node);
  case Kind::Match:
    return matchExpression(node, valueUsed);
  case Kind::Arm:
    throw std::runtime_error("match arm lowered outside its match");
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
                  sourceType(node));
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
    if (!node.patterns.empty() ||
        node.children[0]->kind == Kind::ConditionChain)
      return conditionalPatternExpression(node, valueUsed);
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
        merge(valueUsed ? sourceType(node) : Type::Unit, values, predecessors),
        node.span);
  }
  case Kind::Binding: {
    if (!node.patterns.empty())
      return bindingPatternExpression(node);
    if (facts.slot >= 0) {
      int slot = localSlot(facts.slot);
      function.locals[slot].scope = blockScope;
      function.locals[slot].order = order++;
      emit({Op::Declare, {}, {}, {}, "", {slot, {}}, -1, 0, node.span},
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
              {localSlot(facts.slot), {}},
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
    auto location = place(*node.children[0], false, true);
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
  case Kind::Loop:
    return loopExpression(node);
  case Kind::Break:
  case Kind::Continue:
    return transferExpression(node);
  case Kind::Condition:
  case Kind::ConditionChain:
    throw std::runtime_error(
        "condition lowered outside its control-flow header");
  }
  throw std::runtime_error("unhandled checked syntax node");
}
} // namespace mettle::lowering
