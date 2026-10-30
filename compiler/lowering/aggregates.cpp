#include "lowering/builder.h"
#include <functional>
#include <limits>
#include <set>

namespace mettle::lowering {
using ir::Op;
Place Builder::indexPlace(const Node &node, bool exclusive) {
  if (module.facts(node).indexView != Type::Unknown) {
    auto value = operatorExpression(node);
    if (live() && module.facts(node).effect != Type::Unknown)
      value = unwrapOutcome(value, node.span);
    if (!live())
      return {-1, {}};
    auto result = materialize(value, node.span, temporaryScope);
    result.fields.push_back(Projection::dereference());
    return result;
  }
  auto source = place(*node.children[0], false, exclusive);
  if (!live())
    return {-1, {}};
  for (unsigned i = 0; i < module.facts(node).dereferences; ++i)
    source.fields.push_back(Projection::dereference());
  if (node.children[1]->kind == Kind::Range)
    return rangePlace(node, std::move(source), exclusive);
  auto index = use(expression(*node.children[1]));
  if (!live())
    return {-1, {}};
  auto arrayType = *projectedType(
      *module.typeStore(), function.locals[source.root].type, source.fields);
  if (module.typeStore()->isSlice(arrayType)) {
    auto reference =
        exclusive ? module.facts(node).mutView : module.facts(node).readView;
    Instruction borrow{exclusive ? Op::SliceBorrowMut : Op::SliceBorrowRead,
                       {},
                       {index},
                       {},
                       "",
                       std::move(source),
                       -1,
                       -1,
                       node.span};
    if (node.children[1]->kind == Kind::Integer) {
      const auto &facts = module.facts(*node.children[1]);
      if (facts.numeric && !facts.numeric->negative &&
          !facts.numeric->magnitude[1] &&
          facts.numeric->magnitude[0] <=
              std::numeric_limits<std::int32_t>::max())
        borrow.number = static_cast<std::int32_t>(facts.numeric->magnitude[0]);
    }
    auto selected = emit(std::move(borrow), reference);
    auto result = materialize(selected, node.span, temporaryScope);
    result.fields.push_back(Projection::dereference());
    return result;
  }
  const auto &record = module.typeStore()->product(arrayType);
  auto reference =
      exclusive ? module.facts(node).mutView : module.facts(node).readView;
  Instruction borrow{exclusive ? Op::ArrayBorrowMut : Op::ArrayBorrowRead,
                     {},
                     {index},
                     {},
                     "",
                     source,
                     -1,
                     -1,
                     node.span};
  if (node.children[1]->kind == Kind::Integer) {
    const auto &facts = module.facts(*node.children[1]);
    if (facts.numeric && !facts.numeric->negative &&
        !facts.numeric->magnitude[1] &&
        (record.arrayCount != Type::Unknown ||
         facts.numeric->magnitude[0] < record.fields.size()) &&
        facts.numeric->magnitude[0] <= std::numeric_limits<std::int32_t>::max())
      borrow.number = static_cast<std::int32_t>(facts.numeric->magnitude[0]);
  }
  auto selected = emit(std::move(borrow), reference);
  auto result = materialize(selected, node.span, temporaryScope);
  result.fields.push_back(Projection::dereference());
  return result;
}

// `base[a..b]`, `base[a..]`, `base[..b]`, `base[..=b]` and `base[..]` borrow
// the unsized subslice place; the backend checks start <= end <= length.
Place Builder::rangePlace(const Node &node, Place source, bool exclusive) {
  const auto &range = *node.children[1];
  const bool bounded = range.name.empty();
  const bool hasStart = bounded || range.name == "from";
  const bool hasEnd = bounded || range.name == "to";
  Value start = hasStart ? use(expression(*range.children.front()))
                         : constant(Type::Usize, 0);
  if (!live())
    return {-1, {}};
  Value end;
  if (hasEnd) {
    end = use(expression(*range.children.back()));
    if (!live())
      return {-1, {}};
    if (range.text == "..=")
      end = emit({Op::Binary,
                  {},
                  {end, constant(Type::Usize, 1)},
                  {},
                  "+",
                  {-1, {}},
                  -1,
                  0,
                  node.span},
                 Type::Usize);
  }
  const auto &facts = module.facts(node);
  auto view = exclusive ? facts.mutView : facts.readView;
  auto sourceType = *projectedType(
      *module.typeStore(), function.locals[source.root].type, source.fields);
  if (!module.typeStore()->isSlice(sourceType)) {
    source = capturePlace(std::move(source));
    auto value =
        unsizedView(std::move(source), view, facts.rangeArrayCount, node.span);
    source = materialize(value, node.span, temporaryScope);
    source.fields.push_back(Projection::dereference());
  }
  if (!hasEnd)
    end = emit({Op::SliceLength, {}, {}, {}, "", source, -1, 0, node.span},
               Type::Usize);
  auto selected = emit({exclusive ? Op::SliceBorrowMut : Op::SliceBorrowRead,
                        {},
                        {start, end},
                        {},
                        "",
                        std::move(source),
                        -1,
                        -1,
                        node.span},
                       view);
  auto result = materialize(selected, node.span, temporaryScope);
  result.fields.push_back(Projection::dereference());
  return result;
}

Builder::Value Builder::aggregateExpression(const Node &node, bool valueUsed,
                                            bool consume) {
  const auto &facts = module.facts(node);
  auto produced = sourceType(node);
  if (node.kind == Kind::For)
    if (const auto *plan = module.iteration(node))
      return expression(*plan->elaboration, valueUsed, consume);
  if (node.kind == Kind::Index) {
    auto source = place(node, false, false, false);
    if (!live())
      return {};
    auto loadedType = produced;
    return track(
        emit({!consume && module.typeStore()->isCopy(loadedType) ? Op::Load
                                                                 : Op::Move,
              {},
              {},
              {},
              "",
              source,
              -1,
              0,
              node.span},
             loadedType),
        node.span);
  }
  if (node.kind == Kind::Tuple || node.kind == Kind::Array ||
      node.kind == Kind::Range) {
    std::vector<Value> values;
    if (node.kind == Kind::Array && node.flag) {
      auto value = expression(*node.children[0]);
      if (!live())
        return {};
      if (facts.constantCount != Type::Unknown)
        return track(emit({Op::ArrayRepeat,
                           {},
                           {use(value)},
                           {},
                           "",
                           {-1, {}},
                           -1,
                           0,
                           node.span},
                          produced),
                     node.span);
      for (int i = 0; i < facts.number; ++i)
        values.push_back(value);
    } else
      for (const auto &child : node.children) {
        values.push_back(expression(*child));
        if (!live())
          return {};
      }
    if (node.kind == Kind::Range)
      values.push_back(constant(Type::Bool, node.text == "..=" ? 1 : 0));
    for (auto &value : values)
      value = use(value);
    return track(emit({Op::Construct,
                       {},
                       std::move(values),
                       {},
                       "",
                       {-1, {}},
                       -1,
                       0,
                       node.span},
                      produced),
                 node.span);
  }
  if (node.kind == Kind::Coalesce) {
    auto input = expression(*node.children[0]);
    if (!live())
      return {};
    auto source = materialize(input, node.span, temporaryScope);
    auto test =
        emit({Op::VariantTest, {}, {}, {}, "", source, -1, 1, node.span},
             Type::Bool);
    int yes = block(), no = block(), done = block();
    terminate({ir::Exit::Branch, test, yes, no});
    current = yes;
    auto payload = source;
    payload.fields.push_back(Projection::field(1));
    auto value =
        emit({module.typeStore()->isCopy(produced) ? Op::Load : Op::Move,
              {},
              {},
              {},
              "",
              payload,
              -1,
              0,
              node.span},
             produced);
    std::vector<Value> values{value};
    std::vector<int> predecessors{current};
    jump(done);
    current = no;
    auto fallback = expression(*node.children[1], false, valueUsed);
    if (live()) {
      values.push_back(use(fallback));
      predecessors.push_back(current);
      jump(done);
    }
    current = done;
    return track(merge(produced, values, predecessors), node.span);
  }
  int savedTemporary = temporaryScope, savedBlock = blockScope;
  temporaryScope = scope();
  Value value;
  auto inputType = module.facts(*node.children[0]).type;
  if (facts.iterationMode != ParameterMode::Take &&
      !module.typeStore()->isView(inputType) &&
      (module.typeStore()->isSlice(inputType) ||
       (module.typeStore()->isProduct(inputType) &&
        module.typeStore()->product(inputType).kind == AggregateKind::Array))) {
    auto placeOfInput = place(*node.children[0]);
    if (live())
      value =
          emit({Op::ViewRead, {}, {}, {}, "", placeOfInput, -1, 0, node.span},
               facts.readView);
  } else
    value = expression(*node.children[0]);
  if (!live()) {
    endScope();
    temporaryScope = savedTemporary;
    return {};
  }
  auto source = materialize(value, node.span, temporaryScope);
  auto type = value.type;
  while (module.typeStore()->isView(type)) {
    source.fields.push_back(Projection::dereference());
    type = module.typeStore()->view(type).payload;
  }
  int done = block();
  auto iteration = [&](const Place &element, int next) {
    loops.push_back({next, done, scopes.size(), facts.control, {}, {}});
    blockScope = scope();
    patternBind(node.patterns[0], element, facts.iterationMode);
    blockExpression(*node.children[1], false);
    endScope();
    blockScope = savedBlock;
    loops.pop_back();
    jump(next);
  };
  if (module.typeStore()->isSlice(type)) {
    auto length =
        emit({Op::SliceLength, {}, {}, {}, "", source, -1, 0, node.span},
             Type::Usize);
    auto counter =
        materialize(constant(Type::Usize, 0), node.span, temporaryScope);
    int header = block(), body = block(), step = block();
    jump(header);
    current = header;
    auto index = emit({Op::Load, {}, {}, {}, "", counter, -1, 0, node.span},
                      Type::Usize);
    auto valid = emit(
        {Op::Binary, {}, {index, length}, {}, "<", {-1, {}}, -1, 0, node.span},
        Type::Bool);
    terminate({ir::Exit::Branch, valid, body, done});
    current = body;
    auto element =
        emit({facts.iterationMode == ParameterMode::Mut ? Op::SliceBorrowMut
                                                        : Op::SliceBorrowRead,
              {},
              {index},
              {},
              "",
              source,
              -1,
              -1,
              node.span},
             facts.elementView);
    auto storage = materialize(element, node.span, temporaryScope);
    storage.fields.push_back(Projection::dereference());
    iteration(storage, step);
    current = step;
    auto next = emit({Op::Binary,
                      {},
                      {index, constant(Type::Usize, 1)},
                      {},
                      "+",
                      {-1, {}},
                      -1,
                      0,
                      node.span},
                     Type::Usize);
    emit({Op::Store, {}, {next}, {}, "", counter, -1, 0, node.span},
         Type::Unit);
    jump(header);
    current = done;
    endScope();
    temporaryScope = savedTemporary;
    blockScope = savedBlock;
    return unit();
  }
  const auto &aggregate = module.typeStore()->product(type);
  if (aggregate.kind == AggregateKind::Array) {
    if (aggregate.arrayCount != Type::Unknown) {
      auto counter =
          materialize(constant(Type::I32, 0), node.span, temporaryScope);
      auto header = block(), step = block(), body = block();
      jump(header);
      current = header;
      auto index = emit({Op::Load, {}, {}, {}, "", counter, -1, 0, node.span},
                        Type::I32);
      Instruction length{Op::Constant, {}, {}, {},       "",
                         {-1, {}},     -1, 0,  node.span};
      length.constantParameter = aggregate.arrayCount;
      auto bound = emit(std::move(length), Type::I32);
      auto test = emit(
          {Op::Binary, {}, {index, bound}, {}, "<", {-1, {}}, -1, 0, node.span},
          Type::Bool);
      terminate({ir::Exit::Branch, test, body, done});
      current = body;
      auto firstBlock = function.blocks.size();
      auto elementType = aggregate.components[0];
      auto borrowed = facts.iterationMode != ParameterMode::Take;
      auto resultType = borrowed ? facts.elementView : elementType;
      auto element = emit(
          {facts.iterationMode == ParameterMode::Take  ? Op::ArrayTake
           : facts.iterationMode == ParameterMode::Mut ? Op::ArrayBorrowMut
                                                       : Op::ArrayBorrowRead,
           {},
           {index},
           {},
           "",
           source,
           -1,
           -1,
           node.span},
          resultType);
      auto storage = materialize(element, node.span, temporaryScope);
      if (borrowed)
        storage.fields.push_back(Projection::dereference());
      iteration(storage, step);
      std::vector<int> bodyBlocks{body};
      for (std::size_t b = firstBlock; b < function.blocks.size(); ++b)
        bodyBlocks.push_back(static_cast<int>(b));
      function.arrayLoops.push_back({header, body, step, done,
                                     std::move(bodyBlocks), source, index,
                                     element.id, facts.iterationMode});
      current = step;
      auto next = emit({Op::Binary,
                        {},
                        {index, constant(Type::I32, 1)},
                        {},
                        "+",
                        {-1, {}},
                        -1,
                        0,
                        node.span},
                       Type::I32);
      emit({Op::Store, {}, {next}, {}, "", counter, -1, 0, node.span},
           Type::Unit);
      jump(header);
      current = done;
      endScope();
      temporaryScope = savedTemporary;
      blockScope = savedBlock;
      return unit();
    }
    std::set<int> declared;
    std::function<void(const Pattern &)> patternLocals =
        [&](const Pattern &pattern) {
          const auto &facts = module.facts(pattern);
          if (facts.slot >= 0)
            declared.insert(facts.slot);
          if (facts.guardSlot >= 0)
            declared.insert(facts.guardSlot);
          for (const auto &child : pattern.children)
            patternLocals(child);
        };
    std::function<void(const Node &)> bodyLocals = [&](const Node &node) {
      if (node.kind == Kind::Binding && module.facts(node).slot >= 0)
        declared.insert(module.facts(node).slot);
      for (const auto &pattern : node.patterns)
        patternLocals(pattern);
      for (const auto &child : node.children)
        bodyLocals(*child);
    };
    patternLocals(node.patterns[0]);
    bodyLocals(*node.children[1]);
    auto previousRemap = localRemap;
    for (std::size_t field = 0; field < aggregate.fields.size(); ++field) {
      if (field > 0)
        for (auto slot : declared) {
          if (function.locals.size() >= limits::locals)
            throw LoweringLimit(
                "array iteration local expansion limit exceeded");
          auto original = function.locals[localSlot(slot)];
          original.scope = -1;
          localRemap[slot] = static_cast<int>(function.locals.size());
          function.locals.push_back(std::move(original));
        }
      auto element = source;
      element.fields.push_back(
          Projection::field(static_cast<std::uint32_t>(field)));
      int next = block();
      iteration(element, next);
      current = next;
    }
    localRemap = std::move(previousRemap);
    jump(done);
  } else {
    auto load = [&](std::uint32_t field, Type type) {
      auto place = source;
      place.fields.push_back(Projection::field(field));
      return emit({Op::Load, {}, {}, {}, "", place, -1, 0, node.span}, type);
    };
    auto element = module.typeStore()->product(type).components[0];
    auto index = materialize(load(0, element), node.span, temporaryScope);
    auto end = load(1, element);
    auto inclusive = load(2, Type::Bool);
    int header = block(), body = block(), increment = block();
    jump(header);
    current = header;
    auto currentValue =
        emit({Op::Load, {}, {}, {}, "", index, -1, 0, node.span}, element);
    auto less = emit({Op::Binary,
                      {},
                      {currentValue, end},
                      {},
                      "<",
                      {-1, {}},
                      -1,
                      0,
                      node.span},
                     Type::Bool);
    auto equal = emit({Op::Binary,
                       {},
                       {currentValue, end},
                       {},
                       "==",
                       {-1, {}},
                       -1,
                       0,
                       node.span},
                      Type::Bool);
    auto includeEnd = emit({Op::Binary,
                            {},
                            {equal, inclusive},
                            {},
                            "&",
                            {-1, {}},
                            -1,
                            0,
                            node.span},
                           Type::Bool);
    auto valid = emit({Op::Binary,
                       {},
                       {less, includeEnd},
                       {},
                       "|",
                       {-1, {}},
                       -1,
                       0,
                       node.span},
                      Type::Bool);
    terminate({ir::Exit::Branch, valid, body, done});
    current = body;
    iteration(index, increment);
    current = increment;
    auto last =
        emit({Op::Load, {}, {}, {}, "", index, -1, 0, node.span}, element);
    auto finished = emit(
        {Op::Binary, {}, {last, end}, {}, "==", {-1, {}}, -1, 0, node.span},
        Type::Bool);
    int advance = block();
    terminate({ir::Exit::Branch, finished, done, advance});
    current = advance;
    auto one = constant(element, 1);
    auto next =
        emit({Op::Binary, {}, {last, one}, {}, "+", {-1, {}}, -1, 0, node.span},
             element);
    emit({Op::Store, {}, {next}, {}, "", index, -1, 0, node.span}, Type::Unit);
    jump(header);
  }
  current = done;
  endScope();
  temporaryScope = savedTemporary;
  blockScope = savedBlock;
  return unit();
}
} // namespace mettle::lowering
