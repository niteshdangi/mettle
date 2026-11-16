#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include <functional>

namespace mettle::ir {
using TypeNormalizer =
    std::function<Type(Type, std::span<const TypeBinding>, const Function &)>;
using UnpinProof = std::function<bool(Type, Type, const Function &, Span)>;
bool verify(const Program &program, Diagnostics &diagnostics,
            const TypeNormalizer &normalize = {},
            const UnpinProof &unpinProof = {},
            // Functions already verified when their library was built.
            const std::vector<bool> *trusted = nullptr);
} // namespace mettle::ir
