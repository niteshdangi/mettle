#include "lowering/builder.h"
#include <charconv>
#include <functional>

namespace mettle::lowering {
using ir::Op;
void Builder::patternTest(const Pattern &pattern, const Place &place, int yes,
                          int no) {
  const auto &facts = module.facts(pattern);
  if (module.typeStore()->uninhabited(facts.type)) {
    jump(no);
    return;
  }
  if (facts.variant >= 0) {
    const auto &sum = module.typeStore()->product(facts.type);
    for (auto field : sum.variants[facts.variant].fields)
      if (module.typeStore()->uninhabited(sum.fields[field].type)) {
        jump(no);
        return;
      }
  }
  if (pattern.kind == PatternKind::Rest) {
    jump(yes);
    return;
  }
  if (pattern.kind == PatternKind::At) {
    patternTest(pattern.children[0], place, yes, no);
    return;
  }
  if (pattern.kind == PatternKind::Or) {
    for (std::size_t i = 0; i < pattern.children.size(); ++i) {
      int next = i + 1 == pattern.children.size() ? no : block();
      patternTest(pattern.children[i], place, yes, next);
      if (next != no)
        current = next;
    }
    return;
  }
  if (pattern.kind == PatternKind::Literal ||
      pattern.kind == PatternKind::Range) {
    auto value = emit({Op::Load, {}, {}, {}, "", place, -1, 0, pattern.span},
                      facts.type);
    auto expected = facts.numeric ? constant(facts.type, *facts.numeric)
                                  : constant(facts.type, facts.number);
    auto test = emit({Op::Binary,
                      {},
                      {value, expected},
                      {},
                      pattern.kind == PatternKind::Range ? ">=" : "==",
                      {-1, {}},
                      -1,
                      0,
                      pattern.span},
                     Type::Bool);
    if (pattern.kind == PatternKind::Range) {
      const auto &upper = module.facts(pattern.children[0]);
      auto last = upper.numeric ? constant(facts.type, *upper.numeric)
                                : constant(facts.type, upper.number);
      auto below = emit({Op::Binary,
                         {},
                         {value, last},
                         {},
                         pattern.inclusive ? "<=" : "<",
                         {-1, {}},
                         -1,
                         0,
                         pattern.span},
                        Type::Bool);
      test = emit({Op::Binary,
                   {},
                   {test, below},
                   {},
                   "&",
                   {-1, {}},
                   -1,
                   0,
                   pattern.span},
                  Type::Bool);
    }
    terminate({ir::Exit::Branch, test, yes, no});
    return;
  }
  if (facts.variant >= 0) {
    int payload = pattern.children.empty() ? yes : block();
    auto test = emit({Op::VariantTest,
                      {},
                      {},
                      {},
                      "",
                      place,
                      -1,
                      facts.variant,
                      pattern.span},
                     Type::Bool);
    terminate({ir::Exit::Branch, test, payload, no});
    if (pattern.children.empty())
      return;
    current = payload;
  }
  for (std::size_t i = 0; i < pattern.children.size(); ++i) {
    auto child = place;
    if (pattern.children[i].kind != PatternKind::Rest)
      child.fields.push_back(Projection::field(facts.fields[i]));
    int next = i + 1 == pattern.children.size() ? yes : block();
    patternTest(pattern.children[i], child, next, no);
    if (next != yes)
      current = next;
  }
  if (pattern.children.empty())
    jump(yes);
}

void Builder::patternBind(const Pattern &pattern, const Place &place,
                          ParameterMode mode, bool guard) {
  const auto &facts = module.facts(pattern);
  if (pattern.kind == PatternKind::Or) {
    int done = block();
    for (const auto &alternative : pattern.children) {
      int selected = block(), next = block();
      patternTest(alternative, place, selected, next);
      current = selected;
      patternBind(alternative, place, mode, guard);
      jump(done);
      current = next;
    }
    terminate({ir::Exit::Unreachable});
    current = done;
    return;
  }
  int slot = guard && facts.guardSlot >= 0 ? facts.guardSlot : facts.slot;
  if (slot >= 0)
    slot = localSlot(slot);
  if (pattern.kind == PatternKind::Rest) {
    if (slot < 0)
      return;
    auto &local = function.locals[slot];
    local.scope = blockScope;
    local.order = order++;
    emit({Op::Declare, {}, {}, {}, "", {slot, {}}, -1, 0, pattern.span},
         Type::Unit);
    Value value;
    if (module.typeStore()->isView(local.type) &&
        module.typeStore()->view(local.type).payload == facts.type) {
      auto subarray = place;
      subarray.fields.push_back(*facts.slice);
      value = emit({mode == ParameterMode::Mut ? Op::ViewMut : Op::ViewRead,
                    {},
                    {},
                    {},
                    "",
                    subarray,
                    -1,
                    0,
                    pattern.span},
                   local.type);
    } else {
      std::vector<Value> elements;
      for (auto field : facts.fields) {
        auto element = place;
        element.fields.push_back(Projection::field(field));
        auto type =
            *projectedType(*module.typeStore(),
                           function.locals[element.root].type, element.fields);
        elements.push_back(
            emit({mode == ParameterMode::Take ? Op::Move : Op::Load,
                  {},
                  {},
                  {},
                  "",
                  element,
                  -1,
                  0,
                  pattern.span},
                 type));
      }
      value = track(emit({Op::Construct,
                          {},
                          std::move(elements),
                          {},
                          "",
                          {-1, {}},
                          -1,
                          0,
                          pattern.span},
                         local.type),
                    pattern.span);
    }
    emit({Op::Store, {}, {use(value)}, {}, "", {slot, {}}, -1, 0, pattern.span},
         Type::Unit);
    return;
  }
  if (slot >= 0) {
    auto &local = function.locals[slot];
    local.scope = blockScope;
    local.order = order++;
    emit({Op::Declare, {}, {}, {}, "", {slot, {}}, -1, 0, pattern.span},
         Type::Unit);
    Value value;
    if (module.typeStore()->isView(local.type) &&
        module.typeStore()->view(local.type).payload == facts.type) {
      value = emit({mode == ParameterMode::Mut ? Op::ViewMut : Op::ViewRead,
                    {},
                    {},
                    {},
                    "",
                    place,
                    -1,
                    0,
                    pattern.span},
                   local.type);
    } else
      value = track(emit({(mode == ParameterMode::Take &&
                           pattern.kind != PatternKind::At) ||
                                  !module.typeStore()->isCopy(facts.type)
                              ? Op::Move
                              : Op::Load,
                          {},
                          {},
                          {},
                          "",
                          place,
                          -1,
                          0,
                          pattern.span},
                         facts.type),
                    pattern.span);
    emit({Op::Store, {}, {use(value)}, {}, "", {slot, {}}, -1, 0, pattern.span},
         Type::Unit);
  }
  if (pattern.kind == PatternKind::At) {
    patternBind(pattern.children[0], place, mode, guard);
    return;
  }
  if (pattern.kind == PatternKind::Range)
    return;
  for (std::size_t i = 0; i < pattern.children.size(); ++i) {
    auto child = place;
    if (pattern.children[i].kind != PatternKind::Rest)
      child.fields.push_back(Projection::field(facts.fields[i]));
    patternBind(pattern.children[i], child, mode, guard);
  }
}

Builder::Value Builder::matchExpression(const Node &node, bool valueUsed) {
  auto mode = node.text == "take"  ? ParameterMode::Take
              : node.text == "mut" ? ParameterMode::Mut
                                   : ParameterMode::Read;
  Place source;
  if (mode == ParameterMode::Take) {
    auto value = expression(*node.children[0], true);
    if (!live())
      return {};
    source = materialize(value, node.span, temporaryScope);
  } else
    source = place(*node.children[0]);
  if (!live())
    return {};
  for (unsigned i = 0; i < module.facts(node).dereferences; ++i)
    source.fields.push_back(Projection::dereference());
  int done = block();
  std::vector<Value> values;
  std::vector<int> predecessors;
  for (std::size_t armIndex = 1; armIndex < node.children.size(); ++armIndex) {
    const auto &arm = *node.children[armIndex];
    int matched = block(), next = block();
    patternTest(arm.patterns[0], source, matched, next);
    current = matched;
    std::function<bool(const Pattern &)> possible =
        [&](const Pattern &pattern) {
          const auto &facts = module.facts(pattern);
          if (module.typeStore()->uninhabited(facts.type))
            return false;
          if (facts.variant >= 0) {
            const auto &sum = module.typeStore()->product(facts.type);
            for (auto field : sum.variants[facts.variant].fields)
              if (module.typeStore()->uninhabited(sum.fields[field].type))
                return false;
          }
          if (pattern.kind == PatternKind::Or)
            return std::any_of(pattern.children.begin(), pattern.children.end(),
                               possible);
          for (const auto &child : pattern.children)
            if (!possible(child))
              return false;
          return true;
        };
    if (!possible(arm.patterns[0])) {
      terminate({ir::Exit::Unreachable});
      current = next;
      continue;
    }
    int savedBlock = blockScope, savedTemporary = temporaryScope;
    blockScope = scope();
    temporaryScope = blockScope;
    patternBind(arm.patterns[0], source,
                arm.flag && mode == ParameterMode::Take ? ParameterMode::Read
                                                        : mode,
                arm.flag && mode == ParameterMode::Take);
    if (arm.flag) {
      auto guard = use(expression(*arm.children[0]));
      int accepted = block(), rejected = block();
      if (live())
        terminate({ir::Exit::Branch, guard, accepted, rejected});
      current = rejected;
      emit({Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, blockScope, arm.span},
           Type::Unit);
      jump(next);
      current = accepted;
      if (mode == ParameterMode::Take)
        patternBind(arm.patterns[0], source, mode);
    }
    auto value = expression(*arm.children.back(), false, valueUsed);
    if (live()) {
      if (!valueUsed)
        value = unit();
      std::optional<Place> pending;
      if (module.typeStore()->needsDrop(value.type))
        pending = materialize(value, arm.span, -2);
      endScope();
      value = pending
                  ? emit({Op::Move, {}, {}, {}, "", *pending, -1, 0, arm.span},
                         value.type)
                  : use(value);
      values.push_back(valueUsed ? value : unit());
      predecessors.push_back(current);
      jump(done);
    } else
      endScope();
    blockScope = savedBlock;
    temporaryScope = savedTemporary;
    current = next;
  }
  terminate({ir::Exit::Unreachable});
  current = done;
  return track(
      merge(valueUsed ? sourceType(node) : Type::Unit, values, predecessors),
      node.span);
}
Builder::Value Builder::bindingPatternExpression(const Node &node) {
  auto value = expression(*node.children[0]);
  if (!live())
    return {};
  auto source = materialize(value, node.span, temporaryScope);
  int yes = block(), no = block();
  patternTest(node.patterns[0], source, yes, no);
  current = no;
  if (node.children.size() > 1)
    blockExpression(*node.children[1], false);
  if (live())
    terminate({ir::Exit::Unreachable});
  current = yes;
  patternBind(node.patterns[0], source, ParameterMode::Take);
  return unit();
}

Builder::Value Builder::conditionalPatternExpression(const Node &node,
                                                     bool valueUsed) {
  auto source = place(*node.children[0]);
  if (!live())
    return {};
  int yes = block(), no = block(), done = block();
  patternTest(node.patterns[0], source, yes, no);
  current = yes;
  int savedBlock = blockScope, savedTemporary = temporaryScope;
  blockScope = scope();
  temporaryScope = blockScope;
  patternBind(node.patterns[0], source, ParameterMode::Read);
  auto value = expression(*node.children[1], false, valueUsed);
  std::vector<Value> values;
  std::vector<int> predecessors;
  if (live()) {
    if (!valueUsed)
      value = unit();
    std::optional<Place> pending;
    if (module.typeStore()->needsDrop(value.type))
      pending = materialize(value, node.span, -2);
    endScope();
    value = pending
                ? emit({Op::Move, {}, {}, {}, "", *pending, -1, 0, node.span},
                       value.type)
                : use(value);
    values.push_back(value);
    predecessors.push_back(current);
    jump(done);
  } else
    endScope();
  blockScope = savedBlock;
  temporaryScope = savedTemporary;
  current = no;
  auto fallback = node.children.size() > 2
                      ? expression(*node.children[2], false, valueUsed)
                      : unit();
  if (live()) {
    values.push_back(valueUsed ? use(fallback) : unit());
    predecessors.push_back(current);
    jump(done);
  }
  current = done;
  return track(
      merge(valueUsed ? sourceType(node) : Type::Unit, values, predecessors),
      node.span);
}

Builder::Value Builder::whilePatternExpression(const Node &node) {
  int header = block(), body = block(), failed = block(), done = block();
  loops.push_back(
      {header, done, scopes.size(), module.facts(node).control, {}, {}});
  jump(header);
  current = header;
  int savedBlock = blockScope, savedTemporary = temporaryScope;
  blockScope = scope();
  temporaryScope = blockScope;
  auto source = place(*node.children[0]);
  if (live())
    patternTest(node.patterns[0], source, body, failed);
  current = failed;
  emit({Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, blockScope, node.span},
       Type::Unit);
  jump(done);
  current = body;
  if (!module.facts(*node.children[0]).flow.normal)
    terminate({ir::Exit::Unreachable});
  if (live())
    patternBind(node.patterns[0], source, ParameterMode::Read);
  blockExpression(*node.children[1], false);
  endScope();
  blockScope = savedBlock;
  temporaryScope = savedTemporary;
  loops.pop_back();
  jump(header);
  current = done;
  if (!module.facts(node).flow.normal) {
    terminate({ir::Exit::Unreachable});
    return {};
  }
  return unit();
}
} // namespace mettle::lowering
