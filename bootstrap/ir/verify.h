#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include <functional>

namespace mettle::ir {
using TypeNormalizer =
    std::function<Type(Type, std::span<const TypeBinding>, const Function &)>;
using UnpinProof = std::function<bool(Type, Type, const Function &, Span)>;
// Reuse only within an unchanged declaration/normalizer context.
class TypeVerificationCache {
private:
  struct Destructor {
    int index = -1;
    Type result = Type::Unknown, parameter = Type::Unknown;
    std::size_t parameters = 0;
    ParameterMode mode = ParameterMode::Value;
    std::vector<Type> generics;
    std::vector<std::pair<Type, Type>> bounds;
    std::vector<TypeBinding> equalities;
    bool matches(const Program &program) const {
      if (index < 0 ||
          static_cast<std::size_t>(index) >= program.functions.size())
        return false;
      const auto &function = program.functions[index];
      return !function.locals.empty() && function.result == result &&
             function.parameters == parameters &&
             function.locals.front().type == parameter &&
             function.locals.front().mode == mode &&
             function.genericParameters == generics &&
             function.interfaceBounds == bounds &&
             function.genericEqualities == equalities;
    }
  };
  struct Node {
    std::vector<Type> dependencies;
    std::shared_ptr<const Destructor> destructor;
  };
  struct State {
    std::shared_ptr<const TypeStore::DefinitionSnapshot> types;
    unsigned pointerBits = 0;
    VaListAbi variadicAbi = VaListAbi::SysV64;
    TargetFacts target;
    std::vector<std::shared_ptr<const Node>> nodes;
    std::vector<bool> checked;
    std::vector<std::size_t> offsets;
    std::vector<std::uint32_t> dependents;
  };
  std::shared_ptr<const State> state;
  friend bool verify(const Program &, Diagnostics &, const TypeNormalizer &,
                     const UnpinProof &, const std::vector<bool> *,
                     TypeVerificationCache *);
};
bool verify(const Program &program, Diagnostics &diagnostics,
            const TypeNormalizer &normalize = {},
            const UnpinProof &unpinProof = {},
            // Functions already verified when their library was built.
            const std::vector<bool> *trusted = nullptr,
            TypeVerificationCache *typeCache = nullptr);
} // namespace mettle::ir
