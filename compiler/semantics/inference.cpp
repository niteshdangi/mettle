#include "semantics/inference.h"

namespace mettle {
int TypeInference::fresh(Type type) {
  int index = static_cast<int>(variables.size());
  variables.push_back({index, type});
  return index;
}
int TypeInference::root(int v) {
  if (variables[v].parent != v)
    variables[v].parent = root(variables[v].parent);
  return variables[v].parent;
}
Type TypeInference::value(int v) { return variables[root(v)].type; }
void TypeInference::equal(int a, int b, Span span, bool coercion) {
  a = root(a);
  b = root(b);
  if (a == b)
    return;
  auto at = variables[a].type, bt = variables[b].type;
  if (coercion && at == Type::Never)
    return;
  if (at != Type::Unknown && bt != Type::Unknown && at != bt) {
    diagnostics.error("type", span,
                      "expected " + std::string(types.name(bt)) + ", found " +
                          std::string(types.name(at)));
    return;
  }
  variables[a].parent = b;
  if (bt == Type::Unknown)
    variables[b].type = at;
}
int TypeInference::joined(int a, int b, Span span) {
  if (value(a) == Type::Never)
    return b;
  if (value(b) == Type::Never)
    return a;
  equal(a, b, span);
  return a;
}
void TypeInference::set(int variable, Type type) {
  variables[root(variable)].type = type;
}
} // namespace mettle
