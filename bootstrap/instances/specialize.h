#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include <functional>
#include <optional>

namespace mettle::instances {
struct Hooks {
  std::function<Type(Type, std::span<const TypeBinding>, TypeStore &,
                     Diagnostics &)>
      normalizeType{};
  std::function<bool(ir::Instruction &, std::span<const TypeBinding>,
                     TypeStore &, Diagnostics &)>
      selectCall{};
  // Turns the constant of an aggregate-typed interface constant, named by its
  // projection, into a call of the implementation's initializer.
  std::function<bool(ir::Instruction &, Type, TypeStore &, Diagnostics &)>
      aggregateConstant{};
  std::function<Type(Type, std::span<const TypeBinding>, const ir::Function &,
                     Span, TypeStore &, Diagnostics &)>
      validateUnpin{};
  std::function<Type(Type, std::span<const TypeBinding>, TypeStore &,
                     Diagnostics &)>
      normalizeRegionSignature{};
};
std::optional<ir::Program> specialize(const ir::Program &declarations,
                                      Diagnostics &diagnostics,
                                      const Hooks &hooks = {});
} // namespace mettle::instances
