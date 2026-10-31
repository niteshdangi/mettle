#include "lowering/builder.h"
#include "types/target.h"

namespace mettle::lowering {
Builder::Value Builder::machineExpression(const Node &node) {
  const auto &facts = module.facts(node);
  if (facts.machineOperation == "coroutine.suspend") {
    auto resume = block();
    terminate({ir::Exit::Suspend, {}, resume, -1, node.span});
    current = resume;
    return unit();
  }
  if (facts.machineOperation == "slice.len") {
    auto location = place(*node.children[0]->children[0]);
    if (!live())
      return {};
    for (unsigned i = 0; i < facts.dereferences; ++i)
      location.fields.push_back(Projection::dereference());
    return emit(
        {ir::Op::SliceLength, {}, {}, {}, "", location, -1, 0, node.span},
        Type::Usize);
  }
  if (facts.machineOperation == "pin.inline") {
    auto value = use(expression(*node.children[1], true));
    if (!live())
      return {};
    auto location = materialize(
        value, node.span, extensionScope >= 0 ? extensionScope : blockScope);
    auto view = module.typeStore()->product(sourceType(node)).components[0];
    auto reference = emit(
        {ir::Op::ViewMut, {}, {}, {}, "", location, -1, 0, node.span}, view);
    return emit({ir::Op::Construct,
                 {},
                 {reference},
                 {},
                 "",
                 {-1, {}},
                 -1,
                 0,
                 node.span},
                sourceType(node));
  }
  if (facts.machineOperation == "pin.as_ref" ||
      facts.machineOperation == "pin.as_mut" ||
      facts.machineOperation == "pin.get_ref" ||
      facts.machineOperation == "pin.get_mut" ||
      facts.machineOperation == "pin.get_unchecked_mut" ||
      facts.machineOperation.starts_with("pin.project.")) {
    auto location = place(*node.children[0]->children[0]);
    if (!live())
      return {};
    for (unsigned i = 0; i < facts.dereferences; ++i)
      location.fields.push_back(Projection::dereference());
    location.fields.push_back(Projection::field(0));
    location.fields.push_back(Projection::dereference());
    if (facts.machineOperation.starts_with("pin.project."))
      location.fields.push_back(Projection::field(facts.field));
    bool wrapped = module.typeStore()->isProduct(sourceType(node));
    auto view =
        wrapped ? module.typeStore()->product(sourceType(node)).components[0]
                : sourceType(node);
    auto mode = module.typeStore()->view(view).mode;
    Instruction borrow{mode == ParameterMode::Mut ? ir::Op::ViewMut
                                                  : ir::Op::ViewRead,
                       {},
                       {},
                       {},
                       "",
                       location,
                       -1,
                       0,
                       node.span};
    for (auto requirement : facts.unpinRequirements)
      borrow.unpinProofs.emplace_back(requirement, requirement);
    auto reference = emit(std::move(borrow), view);
    return wrapped ? emit({ir::Op::Construct,
                           {},
                           {reference},
                           {},
                           "",
                           {-1, {}},
                           -1,
                           0,
                           node.span},
                          sourceType(node))
                   : reference;
  }
  if (facts.machineOperation == "storage.drop" ||
      facts.machineOperation == "storage.assume_init_drop" ||
      facts.machineOperation == "ptr.drop_in_place") {
    Place location;
    if (facts.machineOperation != "ptr.drop_in_place") {
      location = place(*node.children[0]->children[0]);
      if (!live())
        return {};
      for (unsigned i = 0; i < facts.dereferences; ++i)
        location.fields.push_back(Projection::dereference());
      location.fields.push_back(Projection::field(0));
    } else {
      auto &source =
          facts.method ? *node.children[0]->children[0] : *node.children[1];
      auto pointer = use(expression(source));
      if (!live())
        return {};
      location = materialize(pointer, node.span, temporaryScope);
      location.fields.push_back(Projection::dereference());
    }
    Instruction drop{ir::Op::DropPlace, {}, {}, {}, "", location, -1, 0,
                     node.span};
    drop.unsafeAllowed =
        facts.machineOperation == "ptr.drop_in_place" && unsafeDepth != 0;
    return emit(std::move(drop), Type::Unit);
  }
  if (facts.machineOperation == "storage.write") {
    auto location = place(*node.children[0]->children[0]);
    if (!live())
      return {};
    for (unsigned i = 0; i < facts.dereferences; ++i)
      location.fields.push_back(Projection::dereference());
    location.fields.push_back(Projection::field(0));
    auto value = use(expression(*node.children[1], true));
    if (!live())
      return {};
    emit(
        {ir::Op::StorageWrite, {}, {value}, {}, "", location, -1, 0, node.span},
        Type::Unit);
    return emit({ir::Op::ViewMut, {}, {}, {}, "", location, -1, 0, node.span},
                sourceType(node));
  }
  if ((facts.machineOperation == "cell.get_mut" &&
       (module.typeStore()->product(facts.machineType).kind ==
            AggregateKind::Cell ||
        module.typeStore()->product(facts.machineType).kind ==
            AggregateKind::RefCell)) ||
      facts.machineOperation == "atomic.get_mut" ||
      facts.machineOperation == "storage.get_ref" ||
      facts.machineOperation == "storage.get_mut" ||
      facts.machineOperation == "storage.assume_init_ref" ||
      facts.machineOperation == "storage.assume_init_mut") {
    auto location = place(*node.children[0]->children[0]);
    if (!live())
      return {};
    for (unsigned i = 0; i < facts.dereferences; ++i)
      location.fields.push_back(Projection::dereference());
    location.fields.push_back(Projection::field(
        facts.machineOperation == "cell.get_mut"
            ? cellPayloadField(
                  module.typeStore()->product(facts.machineType).kind)
            : 0));
    auto mode = module.typeStore()->view(sourceType(node)).mode;
    return emit(
        {mode == ParameterMode::Mut ? ir::Op::ViewMut : ir::Op::ViewRead,
         {},
         {},
         {},
         "",
         location,
         -1,
         0,
         node.span},
        sourceType(node));
  }
  std::vector<Value> operands;
  std::vector<const Node *> syntax;
  if (facts.method)
    syntax.push_back(node.children[0]->children[0].get());
  for (std::size_t i = 1; i < node.children.size(); ++i)
    syntax.push_back(node.children[i].get());
  for (std::size_t i = 0; i < syntax.size(); ++i) {
    auto &argument = *syntax[i];
    if (auto operation = targetOperation(facts.machineOperation);
        operation &&
        ((operation->kind == TargetOperation::Kind::Extract && i == 1) ||
         (operation->kind == TargetOperation::Kind::Insert && i == 2))) {
      operands.push_back(constant(Type::I32, facts.number));
      continue;
    }
    auto mode = facts.machineBorrowModes[i];
    if ((facts.method && i == 0 && facts.dereferences) ||
        mode == ParameterMode::Read || mode == ParameterMode::Mut) {
      auto location = place(argument, false, mode == ParameterMode::Mut);
      if (!live())
        return {};
      auto type = sourceType(argument);
      auto depth = facts.method && i == 0 ? facts.dereferences : 0u;
      if (mode != ParameterMode::Value && module.typeStore()->isView(type))
        depth = 1;
      for (unsigned n = 0; n < depth; ++n) {
        location.fields.push_back(Projection::dereference());
        type = module.typeStore()->view(type).payload;
      }
      if (mode == ParameterMode::Value)
        operands.push_back(
            emit({ir::Op::Load, {}, {}, {}, "", location, -1, 0, argument.span},
                 type));
      else
        operands.push_back(emit(
            {mode == ParameterMode::Mut ? ir::Op::ViewMut : ir::Op::ViewRead,
             {},
             {},
             {},
             "",
             location,
             -1,
             0,
             argument.span},
            facts.callParameterTypes[i]));
    } else
      operands.push_back(use(expression(
          argument, mode == ParameterMode::Take ||
                        !module.typeStore()->isCopy(sourceType(argument)))));
    if (!live())
      return {};
  }
  if (facts.machineOperation == "cell.set") {
    auto payload = module.typeStore()->product(facts.machineType).components[0];
    Instruction exchange{ir::Op::Machine,
                         {},
                         std::move(operands),
                         {},
                         "cell.replace",
                         {-1, {}},
                         -1,
                         0,
                         node.span};
    exchange.typeArguments.push_back(facts.machineType);
    auto old = emit(std::move(exchange), payload);
    auto location = materialize(old, node.span, temporaryScope);
    return emit({ir::Op::DropPlace, {}, {}, {}, "", location, -1, 0, node.span},
                Type::Unit);
  }
  if (facts.machineOperation == "cell.new" &&
      module.typeStore()->product(sourceType(node)).kind ==
          AggregateKind::RefCell)
    operands.insert(
        operands.begin(),
        emit({ir::Op::Constant, {}, {}, {}, "", {-1, {}}, -1, 0, node.span},
             Type::Isize));
  Instruction instruction{facts.machineOperation == "storage.new" ||
                                  facts.machineOperation == "cell.new" ||
                                  facts.machineOperation == "atomic.new" ||
                                  facts.machineOperation == "pin.new" ||
                                  facts.machineOperation == "pin.new_unchecked"
                              ? ir::Op::Construct
                              : ir::Op::Machine,
                          {},
                          std::move(operands),
                          {},
                          facts.machineOperation,
                          {-1, {}},
                          -1,
                          0,
                          node.span};
  if (facts.machineType != Type::Unknown &&
      facts.machineOperation != "storage.new" &&
      facts.machineOperation != "cell.new" &&
      facts.machineOperation != "atomic.new" &&
      facts.machineOperation != "pin.new" &&
      facts.machineOperation != "pin.new_unchecked")
    instruction.typeArguments.push_back(facts.machineType);
  for (auto requirement : facts.unpinRequirements)
    instruction.unpinProofs.emplace_back(requirement, requirement);
  auto result = emit(std::move(instruction), sourceType(node));
  if (result.type == Type::Never)
    terminate({ir::Exit::Unreachable});
  return track(result, node.span);
}
} // namespace mettle::lowering
