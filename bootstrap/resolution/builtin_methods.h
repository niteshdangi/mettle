#pragma once

#include "syntax/ast.h"
#include <string_view>

namespace mettle::resolution {
inline bool isImplicitBuiltinMethod(std::string_view module,
                                    const Function &function) {
  return (module == "option" || module == "outcome" || module == "slice") &&
         function.implementation >= 0 && function.interfaceOwner.empty() &&
         function.item.visibility.publicItem &&
         function.item.visibility.restriction.empty() &&
         !function.receiver.empty() && function.receiver != "static";
}
} // namespace mettle::resolution
