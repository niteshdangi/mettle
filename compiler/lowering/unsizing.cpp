#include "lowering/builder.h"

namespace mettle::lowering {
Builder::Value Builder::ownerCoercion(const Node &node) {
  if (!live())
    return {};
  const auto &facts = module.facts(node);
  const auto &types = *module.typeStore();
  auto sourceOwner = facts.ownerUnsizeSource;
  auto targetOwner = facts.rebuiltType;
  auto sourcePayload = types.product(sourceOwner).genericArguments.front();
  auto targetPayload = types.product(targetOwner).genericArguments.front();
  auto owner = use(rawExpression(node, true, true));
  if (!live())
    return {};

  Instruction conversion{
      ir::Op::OwnerUnsize, {}, {owner}, {}, "", {-1, {}}, -1, 0, node.span};
  if (types.pointerMetadata(targetPayload) == PointerMetadata::ElementCount) {
    auto array = types.unsizedArray(sourcePayload, targetPayload);
    if (!array)
      throw std::runtime_error(
          "checked owner unsizing has no compatible array payload");
    const auto &descriptor = types.product(*array);
    if (descriptor.arrayCount == Type::Unknown) {
      conversion.operands.push_back(constant(
          Type::I32, static_cast<std::int32_t>(descriptor.fields.size())));
    } else {
      Instruction length{ir::Op::Constant, {}, {}, {},       "",
                         {-1, {}},         -1, 0,  node.span};
      length.constantParameter = descriptor.arrayCount;
      conversion.operands.push_back(emit(std::move(length), Type::I32));
    }
  } else {
    if (!types.isErased(targetPayload))
      throw std::runtime_error(
          "checked owner unsizing has an unsupported target payload");
    conversion.interfaceSelf = sourcePayload;
    conversion.interfaceType = targetPayload;
    const auto &descriptor = types.erased(targetPayload);
    for (std::size_t method = 0; method < descriptor.methodSlots.size();
         ++method) {
      if (descriptor.methodTypes[method] == Type::Unknown) {
        conversion.operands.push_back(unit());
        conversion.witnessEntries.push_back(
            {descriptor.methodOwners[method], descriptor.methodSlots[method]});
        continue;
      }
      const auto &ownerType = types.erased(descriptor.methodOwners[method]);
      const auto &definition =
          module.interfaceDatabase().definitions[ownerType.declaration];
      auto pointer = descriptor.methodTypes[method];
      Instruction address{
          ir::Op::FunctionAddress,
          {},
          {},
          {},
          "",
          {-1, {}},
          definition.methods[descriptor.methodSlots[method]].function,
          0,
          node.span};
      address.interfaceSelf = sourcePayload;
      address.interfaceType = descriptor.methodOwners[method];
      address.interfaceMethod =
          static_cast<int>(descriptor.methodSlots[method]);
      address.erasedDispatch = true;
      address.number =
          static_cast<std::int32_t>(descriptor.methodSlots[method]);
      address.typeArguments.push_back(sourcePayload);
      address.typeArguments.insert(address.typeArguments.end(),
                                   ownerType.arguments.begin(),
                                   ownerType.arguments.end());
      conversion.operands.push_back(emit(std::move(address), pointer));
      conversion.witnessEntries.push_back(
          {descriptor.methodOwners[method], descriptor.methodSlots[method]});
    }
  }
  return track(emit(std::move(conversion), targetOwner), node.span);
}

Builder::Value Builder::viewCoercion(const Node &node) {
  if (!live())
    return {};
  const auto &facts = module.facts(node);
  auto sourceType = facts.unsizedSource != Type::Unknown ? facts.unsizedSource
                    : facts.erasedSource != Type::Unknown
                        ? facts.erasedSource
                        : facts.reborrowSource;
  Place source;
  bool located = node.kind == Kind::Name || node.kind == Kind::Field ||
                 node.kind == Kind::Index || node.kind == Kind::Group ||
                 (node.kind == Kind::Unary && node.text == "*");
  if (located)
    source = place(
        node, true,
        module.typeStore()->view(facts.type).mode == ParameterMode::Mut, false);
  else {
    auto value = rawExpression(node, false, true);
    if (!live())
      return {};
    source = materialize(value, node.span,
                         extensionScope >= 0 ? extensionScope : temporaryScope);
  }
  source.fields.push_back(Projection::dereference());
  source = capturePlace(std::move(source));
  if (facts.unsizedSource != Type::Unknown)
    return unsizedView(std::move(source), facts.type, facts.unsizedCount,
                       node.span);
  if (facts.erasedSource != Type::Unknown)
    return erasedView(std::move(source),
                      module.typeStore()->view(sourceType).payload, facts.type,
                      node.span);
  return emit(
      {ir::Op::ViewRead, {}, {}, {}, "", std::move(source), -1, 0, node.span},
      facts.type);
}
Builder::Value Builder::unsizedView(Place source, Type view, Type count,
                                    Span span) {
  Instruction length{ir::Op::Constant, {}, {}, {}, "", {-1, {}}, -1, 0, span};
  length.constantParameter = count;
  auto size = emit(std::move(length), Type::I32);
  return emit(
      {ir::Op::UnsizeView, {}, {size}, {}, "", std::move(source), -1, 0, span},
      view);
}
Builder::Value Builder::unsizedArgument(const Node &node, ParameterMode mode) {
  const auto &facts = module.facts(node);
  auto source = place(node, false, mode == ParameterMode::Mut, false);
  auto type = facts.unsizedSource;
  while (module.typeStore()->isView(type)) {
    source.fields.push_back(Projection::dereference());
    type = module.typeStore()->view(type).payload;
  }
  source = capturePlace(std::move(source));
  auto view = mode == ParameterMode::Read ? facts.readView : facts.mutView;
  auto value =
      unsizedView(std::move(source), view, facts.unsizedCount, node.span);
  auto stored = materialize(value, node.span, temporaryScope);
  stored.fields.push_back(Projection::dereference());
  return emit(
      {mode == ParameterMode::Read ? ir::Op::BorrowRead : ir::Op::BorrowMut,
       {},
       {},
       {},
       "",
       std::move(stored),
       -1,
       0,
       node.span},
      facts.type,
      mode == ParameterMode::Read ? ir::Access::Read : ir::Access::Mut);
}
} // namespace mettle::lowering
