#include "semantics/checker.h"
#include "support/limits.h"

namespace mettle {

Checker::Binding Checker::lookup(const std::string &name, Span span) {
  for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
    auto found = it->find(name);
    if (found != it->end())
      return found->second;
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
  scopes.back()[name] = {variable, slot};
  return slot;
}
} // namespace mettle
