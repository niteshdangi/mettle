#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>

namespace mettle {

Checker::Binding Checker::lookup(const std::string &name, Span span) {
  for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
    auto found = it->find(name);
    if (found != it->end()) {
      auto binding = found->second;
      auto sourceScope = static_cast<std::size_t>(
          std::distance(scopes.begin(), it.base()) - 1);
      for (auto [closure, boundary] : closureScopes) {
        if (boundary <= sourceScope || binding.owner == closure)
          continue;
        auto &captures = captureBindings[closure];
        auto capture = std::find_if(
            captures.begin(), captures.end(), [&](const auto &capture) {
              return capture.source.owner == binding.owner &&
                     capture.source.slot == binding.slot;
            });
        int slot;
        if (capture != captures.end())
          slot = capture->proxy;
        else {
          auto &locals = facts(*closure).locals;
          if (locals.size() >= limits::locals) {
            error("limit", span, "closure capture limit exceeded");
            return {inference.fresh(), -1, closure};
          }
          slot = static_cast<int>(locals.size());
          locals.push_back({name, Type::Unknown, true, span});
          localVariables[closure].push_back(binding.variable);
          captures.push_back({binding, slot, span});
        }
        binding = {binding.variable, slot, closure};
        scopes[boundary][name] = binding;
      }
      return binding;
    }
  }
  if (auto storage = staticName(name, span)) {
    for (std::size_t i = 0; i < facts(*current).locals.size(); ++i) {
      const auto &local = facts(*current).locals[i];
      if (local.storage != StorageDuration::Static ||
          local.staticIndex !=
              static_cast<int>(checked.staticStorage[*storage].identity))
        continue;
      if (local.mutableBinding)
        requireUnsafe(span);
      return {localVariables[current][i], static_cast<int>(i), current};
    }
  }
  error("name", span, "unresolved value '" + name + "'");
  return {inference.fresh(), -1};
}
int Checker::local(std::string name, int variable, bool mutableBinding,
                   Span span) {
  if (facts(*current).locals.size() >= limits::locals) {
    error("limit", span, "local binding limit exceeded");
    return -1;
  }
  int slot = static_cast<int>(facts(*current).locals.size());
  facts(*current).locals.push_back({name, Type::Unknown, mutableBinding, span});
  localVariables[current].push_back(variable);
  scopes.back()[name] = {variable, slot, current};
  return slot;
}
} // namespace mettle
