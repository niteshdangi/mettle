#include "lowering/builder.h"
#include <algorithm>

namespace mettle::lowering {
bool witnessSlots(ir::Instruction &instruction, const TypeStore &types,
                  Diagnostics &diagnostics) {
  auto fail = [&] {
    diagnostics.error("internal", instruction.span,
                      "checked erased dispatch has no matching witness entry");
    return false;
  };
  if (instruction.op == ir::Op::WitnessMethod) {
    if (instruction.operands.empty())
      return fail();
    auto receiver = instruction.operands[0].type;
    // A pinned receiver (`Future.poll`) wraps the erased view in `Pin`.
    if (types.isProduct(receiver) &&
        types.product(receiver).kind == AggregateKind::Pin &&
        !types.product(receiver).components.empty() &&
        types.isView(types.product(receiver).components.front()))
      receiver = types.view(types.product(receiver).components.front()).payload;
    if (!types.isErased(receiver))
      return fail();
    const auto &descriptor = types.erased(receiver);
    if (!types.isErased(instruction.interfaceType))
      return fail();
    const auto &wanted = types.erased(instruction.interfaceType);
    for (std::size_t p = 0; p < descriptor.methodSlots.size(); ++p) {
      const auto &provided = types.erased(descriptor.methodOwners[p]);
      bool compatible = provided.declaration == wanted.declaration &&
                        provided.arguments == wanted.arguments &&
                        provided.regionArguments == wanted.regionArguments;
      for (const auto &binding : wanted.associated)
        compatible &=
            std::any_of(provided.associated.begin(), provided.associated.end(),
                        [&](auto value) {
                          return value.parameter == binding.parameter &&
                                 value.argument == binding.argument;
                        });
      if (compatible &&
          descriptor.methodSlots[p] ==
              static_cast<std::size_t>(instruction.interfaceMethod)) {
        instruction.number = static_cast<std::int32_t>(p);
        instruction.interfaceType = descriptor.methodOwners[p];
        return true;
      }
    }
    return fail();
  }
  if (instruction.op == ir::Op::ErasedUpcast) {
    if (!types.isErased(instruction.interfaceSelf))
      return fail();
    const auto &parents =
        types.erased(instruction.interfaceSelf).parentInterfaces;
    auto found =
        std::find(parents.begin(), parents.end(), instruction.interfaceType);
    if (found == parents.end())
      return fail();
    instruction.number = static_cast<std::int32_t>(found - parents.begin());
    return true;
  }
  if (instruction.op != ir::Op::EraseView &&
      instruction.op != ir::Op::OwnerUnsize)
    return true;
  if (!types.isErased(instruction.interfaceType))
    return fail();
  const auto &descriptor = types.erased(instruction.interfaceType);
  const std::size_t prefix =
      instruction.op == ir::Op::OwnerUnsize ? 1 : 0;
  if (instruction.operands.size() < prefix ||
      instruction.witnessEntries.size() !=
          instruction.operands.size() - prefix)
    return fail();
  std::vector<ir::Value> operands;
  std::vector<ir::Instruction::WitnessEntry> entries;
  if (prefix)
    operands.push_back(instruction.operands.front());
  for (std::size_t p = 0; p < descriptor.methodSlots.size(); ++p) {
    std::size_t found = instruction.witnessEntries.size();
    for (std::size_t i = 0; i < instruction.witnessEntries.size(); ++i)
      if (instruction.witnessEntries[i].owner == descriptor.methodOwners[p] &&
          instruction.witnessEntries[i].method == descriptor.methodSlots[p]) {
        found = i;
        break;
      }
    if (found == instruction.witnessEntries.size())
      return fail();
    operands.push_back(instruction.operands[found + prefix]);
    entries.push_back(instruction.witnessEntries[found]);
  }
  instruction.operands = std::move(operands);
  instruction.witnessEntries = std::move(entries);
  return true;
}

void Builder::dynamicDispatch(Instruction &call, const NodeFacts &facts,
                              Span span) {
  if (!module.typeStore()->isErased(facts.interfaceSelf))
    return;
  const auto &descriptor = module.typeStore()->erased(facts.interfaceSelf);
  std::size_t slot = descriptor.methodSlots.size();
  const auto wanted = module.typeStore()->erased(facts.interfaceType);
  for (std::size_t candidate = 0; candidate < descriptor.methodSlots.size();
       ++candidate)
    if (descriptor.methodSlots[candidate] ==
            static_cast<std::size_t>(facts.interfaceMethod) &&
        module.typeStore()
                ->erased(descriptor.methodOwners[candidate])
                .declaration == wanted.declaration &&
        module.typeStore()
                ->erased(descriptor.methodOwners[candidate])
                .arguments == wanted.arguments &&
        module.typeStore()
                ->erased(descriptor.methodOwners[candidate])
                .regionArguments == wanted.regionArguments)
      slot = candidate;
  auto signature = descriptor.methodTypes.at(slot);
  Instruction witness{ir::Op::WitnessMethod,
                      {},
                      {call.operands[0]},
                      {},
                      "",
                      {-1, {}},
                      -1,
                      static_cast<std::int32_t>(slot),
                      span};
  witness.interfaceType = facts.interfaceType;
  witness.interfaceMethod = facts.interfaceMethod;
  call.target = emit(std::move(witness), signature);
  call.op = ir::Op::IndirectCall;
  call.indirectType = signature;
  call.erasedDispatch = true;
  call.callee = -1;
  call.typeArguments.clear();
  call.interfaceMethod = -1;
  call.interfaceSelf = call.interfaceType = Type::Unknown;
}
Builder::Value Builder::erasedView(Place source, Type concrete, Type view,
                                   Span span) {
  const auto &types = *module.typeStore();
  auto conversion = types.erasedTail(concrete, types.view(view).payload);
  if (!conversion)
    throw std::runtime_error("checked erasure has no metadata-compatible tail");
  concrete = conversion->first;
  auto interface = conversion->second;
  const auto &descriptor = types.erased(interface);
  if (types.isErased(concrete)) {
    if (concrete == interface)
      return emit({types.view(view).mode == ParameterMode::Read
                       ? ir::Op::ViewRead
                       : ir::Op::ViewMut,
                   {},
                   {},
                   {},
                   "",
                   std::move(source),
                   -1,
                   0,
                   span},
                  view);
    const auto &parents = types.erased(concrete).parentInterfaces;
    auto found = std::find(parents.begin(), parents.end(), interface);
    if (found == parents.end())
      throw std::runtime_error("checked erased upcast has no parent witness");
    Instruction upcast{ir::Op::ErasedUpcast,
                       {},
                       {},
                       {},
                       "",
                       std::move(source),
                       -1,
                       static_cast<std::int32_t>(found - parents.begin()),
                       span};
    upcast.interfaceType = interface;
    upcast.interfaceSelf = concrete;
    return emit(std::move(upcast), view);
  }
  std::vector<Value> methods;
  for (std::size_t method = 0; method < descriptor.methods.size(); ++method) {
    const auto &owner = types.erased(descriptor.methodOwners[method]);
    const auto &definition =
        module.interfaceDatabase().definitions[owner.declaration];
    const auto &signature = descriptor.methods[method];
    if (signature.result == Type::Unknown) {
      methods.push_back(unit());
      continue;
    }
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
        span};
    address.interfaceSelf = concrete;
    address.interfaceType = descriptor.methodOwners[method];
    address.interfaceMethod = static_cast<int>(descriptor.methodSlots[method]);
    address.erasedDispatch = true;
    address.number = static_cast<std::int32_t>(descriptor.methodSlots[method]);
    address.typeArguments.push_back(concrete);
    address.typeArguments.insert(address.typeArguments.end(),
                                 owner.arguments.begin(),
                                 owner.arguments.end());
    methods.push_back(emit(std::move(address), pointer));
  }
  Instruction erase{ir::Op::EraseView,
                    {},
                    std::move(methods),
                    {},
                    "",
                    std::move(source),
                    -1,
                    0,
                    span};
  erase.interfaceSelf = concrete;
  erase.interfaceType = interface;
  for (std::size_t method = 0; method < descriptor.methodSlots.size(); ++method)
    erase.witnessEntries.push_back(
        {descriptor.methodOwners[method], descriptor.methodSlots[method]});
  return emit(std::move(erase), view);
}

Builder::Value Builder::erasedArgument(const Node &node, ParameterMode mode) {
  const auto &facts = module.facts(node);
  auto location = place(node, false, mode == ParameterMode::Mut, false);
  auto concrete = facts.erasedSource;
  while (module.typeStore()->isView(concrete)) {
    location.fields.push_back(Projection::dereference());
    concrete = module.typeStore()->view(concrete).payload;
  }
  auto view = mode == ParameterMode::Mut ? facts.mutView : facts.readView;
  auto value = erasedView(std::move(location), concrete, view, node.span);
  auto stored = materialize(value, node.span, temporaryScope);
  stored.fields.push_back(Projection::dereference());
  return emit(
      {mode == ParameterMode::Mut ? ir::Op::BorrowMut : ir::Op::BorrowRead,
       {},
       {},
       {},
       "",
       stored,
       -1,
       0,
       node.span},
      facts.type,
      mode == ParameterMode::Mut ? ir::Access::Mut : ir::Access::Read);
}
} // namespace mettle::lowering
