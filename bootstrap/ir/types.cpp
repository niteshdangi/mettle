#include "ir/ir.h"

namespace mettle::ir {
FunctionIndex indexFunction(const Function &function) {
  return {function.name,
          function.result,
          function.parameters,
          !function.genericParameters.empty(),
          function.declarationOnly,
          function.exportedDefinition,
          function.indirectContract,
          function.nakedAssembly.has_value(),
          !function.abi.empty(),
          !function.externalName.empty(),
          function.variadicCursor >= 0,
          function.targetFeatures,
          true};
}
void remapTypes(Function &function, const std::function<Type(Type)> &remap) {
  auto types = [&](auto &values) {
    for (auto &value : values)
      value = remap(value);
  };
  auto pairs = [&](auto &values) {
    for (auto &[left, right] : values) {
      left = remap(left);
      right = remap(right);
    }
  };
  auto place = [&](Place &value) {
    for (auto &projection : value.fields)
      projection.type = remap(projection.type);
  };
  auto assembly = [&](Assembly &value) {
    for (auto &operand : value.operands) {
      operand.type = remap(operand.type);
      operand.inputType = remap(operand.inputType);
      operand.constantIdentity = remap(operand.constantIdentity);
      types(operand.symbolArguments);
    }
  };
  function.result = remap(function.result);
  for (auto &local : function.locals)
    local.type = remap(local.type);
  types(function.genericParameters);
  pairs(function.interfaceBounds);
  types(function.unpinBounds);
  types(function.sizedBounds);
  function.regionSignature = remap(function.regionSignature);
  function.interfaceResult = remap(function.interfaceResult);
  for (auto &binding : function.genericEqualities) {
    binding.parameter = remap(binding.parameter);
    binding.argument = remap(binding.argument);
  }
  if (function.nakedAssembly)
    assembly(*function.nakedAssembly);
  for (auto &loop : function.arrayLoops) {
    place(loop.source);
    loop.index.type = remap(loop.index.type);
  }
  for (auto &block : function.blocks) {
    for (auto &instruction : block.instructions) {
      instruction.result.type = remap(instruction.result.type);
      for (auto &operand : instruction.operands)
        operand.type = remap(operand.type);
      instruction.target.type = remap(instruction.target.type);
      place(instruction.place);
      instruction.indirectType = remap(instruction.indirectType);
      types(instruction.typeArguments);
      instruction.constantParameter = remap(instruction.constantParameter);
      instruction.interfaceType = remap(instruction.interfaceType);
      instruction.interfaceSelf = remap(instruction.interfaceSelf);
      instruction.opaqueType = remap(instruction.opaqueType);
      for (auto &entry : instruction.witnessEntries)
        entry.owner = remap(entry.owner);
      pairs(instruction.unpinProofs);
      if (instruction.assembly)
        assembly(*instruction.assembly);
    }
    block.exit.value.type = remap(block.exit.value.type);
  }
}
} // namespace mettle::ir
