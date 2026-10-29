#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
int Builder::scope() {
  int id = static_cast<int>(function.scopes.size());
  function.scopes.push_back({scopes.back()});
  scopes.push_back(id);
  return id;
}
void Builder::endScope() {
  if (live())
    emit({Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, scopes.back(), {}},
         Type::Unit);
  scopes.pop_back();
}
void Builder::exitTo(std::size_t depth) {
  for (std::size_t i = scopes.size(); i-- > depth;)
    emit({Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, scopes[i], {}},
         Type::Unit);
}
Place Builder::materialize(Value value, Span span, int targetScope) {
  if (function.locals.size() >= limits::locals)
    throw LoweringLimit("lowering temporary limit exceeded");
  Place place{static_cast<int>(function.locals.size()), {}};
  function.locals.push_back({"<temporary>", value.type, true, span,
                             ParameterMode::Value, targetScope, order++});
  emit({Op::Declare, {}, {}, {}, "", place, -1, 0, span}, Type::Unit);
  emit({Op::Store, {}, {use(value)}, {}, "", place, -1, 0, span}, Type::Unit);
  return place;
}
Builder::Value Builder::track(Value value, Span span, int targetScope) {
  if (!live() || !module.typeStore()->needsDrop(value.type))
    return value;
  auto place =
      materialize(value, span, targetScope < 0 ? temporaryScope : targetScope);
  owners[value.id] = place;
  return value;
}
Builder::Value Builder::use(Value value) {
  auto found = owners.find(value.id);
  if (found == owners.end())
    return value;
  auto place = found->second;
  owners.erase(found);
  return emit({Op::Move, {}, {}, {}, "", place, -1, 0, {}}, value.type);
}
void Builder::returnValue(Value value, Span span, bool failure) {
  if (constructorSelfSlot >= 0 && !failure)
    value =
        emit({Op::Move, {}, {}, {}, "", {constructorSelfSlot, {}}, -1, 0, span},
             function.locals[constructorSelfSlot].type);
  if (errorType != Type::Unknown)
    value = variant(function.result, failure ? 1 : 0, {value}, span);
  std::optional<Place> pending;
  if (module.typeStore()->needsDrop(value.type))
    pending = materialize(value, span, -2);
  exitTo(0);
  if (pending)
    value = emit({Op::Move, {}, {}, {}, "", *pending, -1, 0, span}, value.type);
  else
    value = use(value);
  terminate({Exit::Return, value});
}
Builder::Value Builder::blockExpression(const Node &node, bool valueUsed) {
  int previousBlock = blockScope, previousTemporary = temporaryScope;
  blockScope = scope();
  Value result = unit();
  for (std::size_t i = 0; i < node.children.size(); ++i) {
    auto &child = *node.children[i];
    temporaryScope = scope();
    bool tail = i + 1 == node.children.size() && !isStatement(child.kind) &&
                !child.semicolon;
    result = expression(child, false, tail && valueUsed);
    if (live() && tail && valueUsed &&
        module.typeStore()->needsDrop(result.type)) {
      auto owner = owners.find(result.id);
      if (owner != owners.end())
        function.locals[owner->second.root].scope = previousTemporary;
      else
        result = track(result, child.span, previousTemporary);
    }
    if (live() && (!tail || !valueUsed))
      result = unit();
    endScope();
    if (!live())
      break;
  }
  endScope();
  blockScope = previousBlock;
  temporaryScope = previousTemporary;
  return result;
}
Place Builder::place(const Node &node, bool extend, bool exclusive,
                     bool adapt) {
  if (auto found = placeOverrides.find(&node); found != placeOverrides.end())
    return found->second;
  const auto &facts = module.facts(node);
  if (adapt &&
      (facts.viewConversion || (module.typeStore()->isView(facts.type) &&
                                (facts.unsizedSource != Type::Unknown ||
                                 facts.erasedSource != Type::Unknown ||
                                 facts.reborrowSource != Type::Unknown)))) {
    auto value = expression(node);
    if (!live())
      return {-1, {}};
    return materialize(value, node.span,
                       extend && extensionScope >= 0 ? extensionScope
                                                     : temporaryScope);
  }
  if (adapt && (module.facts(node).callableCoercion != Type::Unknown ||
                !module.facts(node).injections.empty())) {
    auto value = expression(node);
    if (!live())
      return {-1, {}};
    return materialize(value, node.span,
                       extend && extensionScope >= 0 ? extensionScope
                                                     : temporaryScope);
  }
  if (module.facts(node).place &&
      (!adapt || (module.facts(node).injections.empty() &&
                  module.facts(node).callableCoercion == Type::Unknown))) {
    auto result = *module.facts(node).place;
    auto captured = capturePlace(result);
    if (captured != result)
      return captured;
    if (auto found = projectedLocals.find(result.root);
        found != projectedLocals.end()) {
      auto mapped = found->second.place;
      mapped.fields.insert(mapped.fields.end(),
                           result.fields.begin() + found->second.skip,
                           result.fields.end());
      return mapped;
    }
    result.root = localSlot(result.root);
    return result;
  }
  if (node.kind == Kind::Group)
    return place(*node.children[0], extend, exclusive);
  if (node.kind == Kind::Index)
    return indexPlace(node, exclusive);
  if (node.kind == Kind::Unary && node.text == "*") {
    auto result = place(*node.children[0], extend, exclusive);
    result.fields.push_back(Projection::dereference());
    return result;
  }
  if (node.kind == Kind::Field) {
    auto result = place(*node.children[0], extend, exclusive);
    for (unsigned i = 0; i < module.facts(node).dereferences; ++i)
      result.fields.push_back(Projection::dereference());
    result.fields.push_back(Projection::field(
        static_cast<std::uint32_t>(module.facts(node).field)));
    return result;
  }
  auto value = expression(node);
  if (!live())
    return {-1, {}};
  return materialize(value, node.span,
                     extend && extensionScope >= 0 ? extensionScope
                                                   : temporaryScope);
}
Builder::Value Builder::borrow(const Node &node, ParameterMode mode,
                               bool reserved, bool firstClass, Type resultType,
                               unsigned dereferences) {
  auto location = place(node, firstClass, mode == ParameterMode::Mut);
  if (!live())
    return {};
  auto payload =
      *projectedType(*module.typeStore(), function.locals[location.root].type,
                     location.fields);
  if (!firstClass) {
    for (unsigned i = 0; i < dereferences; ++i) {
      location.fields.push_back(Projection::dereference());
      payload = module.typeStore()->view(payload).payload;
    }
  }
  auto op = firstClass
                ? (mode == ParameterMode::Read ? Op::ViewRead : Op::ViewMut)
            : mode == ParameterMode::Read ? Op::BorrowRead
            : reserved                    ? Op::ReserveMut
                                          : Op::BorrowMut;
  return emit({op, {}, {}, {}, "", location, -1, 0, node.span},
              firstClass ? resultType : payload,
              firstClass                    ? ir::Access::Owned
              : mode == ParameterMode::Read ? ir::Access::Read
                                            : ir::Access::Mut);
}
} // namespace mettle::lowering
