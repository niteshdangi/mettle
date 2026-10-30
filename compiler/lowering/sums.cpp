#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Op;
void Builder::fail(Value error, Span span) {
  if (effectHandlers.empty()) {
    returnValue(error, span, true);
    return;
  }
  auto pending = materialize(error, span, -2);
  auto depth = effectHandlers.back().depth;
  exitTo(depth, span);
  auto value =
      emit({Op::Move, {}, {}, {}, "", pending, -1, 0, span}, error.type);
  effectHandlers.back().errors.push_back(value);
  effectHandlers.back().predecessors.push_back(current);
  jump(effectHandlers.back().failed);
}
Builder::Value Builder::unwrapOutcome(Value outcome, Span span) {
  auto storage = materialize(outcome, span, temporaryScope);
  const auto &sum = module.typeStore()->product(outcome.type);
  auto test =
      emit({Op::VariantTest, {}, {}, {}, "", storage, -1, 0, span}, Type::Bool);
  int success = block(), failure = block();
  terminate({ir::Exit::Branch, test, success, failure});
  current = failure;
  auto failed = storage;
  failed.fields.push_back(Projection::field(2));
  auto error =
      track(emit({module.typeStore()->isCopy(sum.fields[2].type) ? Op::Load
                                                                 : Op::Move,
                  {},
                  {},
                  {},
                  "",
                  failed,
                  -1,
                  0,
                  span},
                 sum.fields[2].type),
            span);
  fail(error, span);
  current = success;
  if (sum.fields[1].type == Type::Never) {
    terminate({ir::Exit::Unreachable});
    return {};
  }
  auto passed = storage;
  passed.fields.push_back(Projection::field(1));
  return track(emit({module.typeStore()->isCopy(sum.fields[1].type) ? Op::Load
                                                                    : Op::Move,
                     {},
                     {},
                     {},
                     "",
                     passed,
                     -1,
                     0,
                     span},
                    sum.fields[1].type),
               span);
}
Builder::Value Builder::variant(Type type, int tag, std::vector<Value> operands,
                                Span span) {
  for (auto &operand : operands)
    operand = use(operand);
  return track(emit({Op::VariantConstruct,
                     {},
                     std::move(operands),
                     {},
                     "",
                     {-1, {}},
                     -1,
                     tag,
                     span},
                    type),
               span);
}
Builder::Value Builder::optionalExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto produced = sourceType(node);
  const Node &receiver = node.kind == Kind::Call
                             ? *node.children[0]->children[0]
                             : *node.children[0];
  auto source = place(receiver, false, facts.receiverReservation);
  if (!live())
    return {};
  auto type = *projectedType(*module.typeStore(),
                             function.locals[source.root].type, source.fields);
  while (module.typeStore()->isView(type)) {
    source.fields.push_back(Projection::dereference());
    type = module.typeStore()->view(type).payload;
  }
  auto test = emit({Op::VariantTest, {}, {}, {}, "", source, -1, 1, node.span},
                   Type::Bool);
  int yes = block(), no = block(), done = block();
  terminate({ir::Exit::Branch, test, yes, no});
  std::vector<Value> values;
  std::vector<int> predecessors;
  current = yes;
  auto payload = source;
  payload.fields.push_back(Projection::field(1));
  Value selected;
  if (node.kind == Kind::Call) {
    auto old = placeOverrides.find(&receiver);
    std::optional<Place> previous;
    if (old != placeOverrides.end())
      previous = old->second;
    placeOverrides[&receiver] = payload;
    const auto &callee = *node.children[0];
    std::optional<Place> previousCallee;
    if (facts.indirect) {
      auto old = placeOverrides.find(&callee);
      if (old != placeOverrides.end())
        previousCallee = old->second;
      auto field = payload;
      const auto &member = module.facts(callee);
      for (unsigned i = 0; i < member.dereferences; ++i)
        field.fields.push_back(Projection::dereference());
      field.fields.push_back(
          Projection::field(static_cast<std::uint32_t>(member.field)));
      placeOverrides[&callee] = std::move(field);
    }
    selected =
        facts.indirect ? indirectCallExpression(node) : callExpression(node);
    if (facts.indirect) {
      if (previousCallee)
        placeOverrides[&callee] = *previousCallee;
      else
        placeOverrides.erase(&callee);
    }
    if (previous)
      placeOverrides[&receiver] = *previous;
    else
      placeOverrides.erase(&receiver);
    if (live() && facts.effect != Type::Unknown && callHasFailure(node))
      selected = unwrapOutcome(selected, node.span);
  } else {
    for (unsigned i = 0; i < facts.dereferences; ++i)
      payload.fields.push_back(Projection::dereference());
    payload.fields.push_back(
        Projection::field(static_cast<std::uint32_t>(facts.field)));
    auto fieldType = module.typeStore()->product(produced).components[0];
    selected =
        track(emit({module.typeStore()->isCopy(fieldType) ? Op::Load : Op::Move,
                    {},
                    {},
                    {},
                    "",
                    payload,
                    -1,
                    0,
                    node.span},
                   fieldType),
              node.span);
  }
  if (live()) {
    values.push_back(use(variant(produced, 1, {selected}, node.span)));
    predecessors.push_back(current);
    jump(done);
  }
  current = no;
  values.push_back(use(variant(produced, 0, {}, node.span)));
  predecessors.push_back(current);
  jump(done);
  current = done;
  return track(merge(produced, values, predecessors), node.span);
}
Builder::Value Builder::sumExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto produced = sourceType(node);
  if (node.kind == Kind::None || node.kind == Kind::Name)
    return variant(produced, facts.variant, {}, node.span);
  if (node.kind == Kind::Variant) {
    auto value = expression(*node.children[0]);
    if (!live())
      return {};
    return variant(produced, facts.variant, {value}, node.span);
  }
  if (node.kind == Kind::Call) {
    const auto &sum = module.typeStore()->product(produced);
    std::vector<Value> operands(sum.variants[facts.variant].fields.size());
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      auto value = expression(*node.children[i]);
      if (!live())
        return {};
      operands[facts.argumentOrder[i - 1]] = value;
    }
    return variant(produced, facts.variant, std::move(operands), node.span);
  }
  if (node.kind == Kind::Throw) {
    auto error = expression(*node.children[0]);
    if (live())
      fail(error, node.span);
    return {};
  }
  if (node.kind == Kind::Try)
    return expression(*node.children[0]);
  int failed = block(), done = block();
  auto depth = scopes.size();
  int savedTemporary = temporaryScope;
  temporaryScope = scope();
  effectHandlers.push_back({depth, failed, {}, {}});
  auto result = expression(*node.children[0]);
  std::vector<Value> values;
  std::vector<int> predecessors;
  if (live()) {
    auto pending = materialize(result, node.span, -2);
    endScope(node.span);
    temporaryScope = savedTemporary;
    result = emit({Op::Move, {}, {}, {}, "", pending, -1, 0, node.span},
                  result.type);
    auto success = variant(produced, 0, {result}, node.span);
    values.push_back(use(success));
    predecessors.push_back(current);
    jump(done);
  } else
    endScope(node.span);
  auto handler = std::move(effectHandlers.back());
  effectHandlers.pop_back();
  temporaryScope = savedTemporary;
  current = failed;
  if (handler.errors.empty())
    terminate({ir::Exit::Unreachable});
  else {
    auto errorType = module.typeStore()->product(produced).components[1];
    auto error = merge(errorType, handler.errors, handler.predecessors);
    auto failure = variant(produced, 1, {error}, node.span);
    values.push_back(use(failure));
    predecessors.push_back(current);
    jump(done);
  }
  current = done;
  return track(merge(produced, values, predecessors), node.span);
}
} // namespace mettle::lowering
