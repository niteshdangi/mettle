#include "semantics/inference.h"
#include <algorithm>

namespace mettle {
int TypeInference::fresh(Type type) {
  int index = static_cast<int>(variables.size());
  variables.push_back({index, type});
  return index;
}
int TypeInference::numeric(bool floating, Type type) {
  auto variable = fresh(type);
  variables[variable].numeric =
      floating ? Variable::Numeric::Floating : Variable::Numeric::Integer;
  return variable;
}
int TypeInference::root(int v) {
  if (variables[v].parent != v)
    variables[v].parent = root(variables[v].parent);
  return variables[v].parent;
}
bool TypeInference::depends(int variable,
                            const std::set<int> &representatives) {
  variable = root(variable);
  if (representatives.contains(variable))
    return true;
  auto children = variables[variable].components;
  return std::any_of(children.begin(), children.end(), [&](int child) {
    return depends(child, representatives);
  });
}
Type TypeInference::value(int v) {
  v = root(v);
  if (variables[v].type != Type::Unknown)
    return variables[v].type;
  if (!variables[v].kind)
    return variables[v].numeric == Variable::Numeric::Integer ? Type::I32
           : variables[v].numeric == Variable::Numeric::Floating
               ? Type::F64
               : Type::Unknown;
  auto kind = *variables[v].kind;
  auto children = variables[v].components;
  auto count = variables[v].count;
  std::vector<Type> components;
  for (auto child : children) {
    auto type = value(child);
    if (type == Type::Unknown)
      return Type::Unknown;
    components.push_back(type);
  }
  auto type =
      kind == AggregateKind::Array &&
              variables[v].symbolicCount != Type::Unknown
          ? types.arrayType(components.at(0), variables[v].symbolicCount)
          : types.structural(kind, std::move(components), count);
  return type;
}
int TypeInference::composite(AggregateKind kind, std::vector<int> components,
                             std::uint32_t count, Type symbolicCount) {
  auto variable = fresh();
  variables[variable].kind = kind;
  variables[variable].components = std::move(components);
  variables[variable].count = count;
  variables[variable].symbolicCount = symbolicCount;
  return variable;
}
bool TypeInference::occurs(int variable, int within) {
  within = root(within);
  if (variable == within)
    return true;
  for (auto child : variables[within].components)
    if (occurs(variable, child))
      return true;
  return false;
}
std::vector<int> TypeInference::components(int variable, AggregateKind kind,
                                           Span span) {
  variable = root(variable);
  if (!variables[variable].kind) {
    auto type = variables[variable].type;
    if (type != Type::Unknown) {
      if (!types.isProduct(type) || types.product(type).kind != kind) {
        diagnostics.error("type", span, "incompatible aggregate shape");
        return {};
      }
      auto typesOfChildren = types.product(type).components;
      std::vector<int> children;
      for (auto child : typesOfChildren)
        children.push_back(fresh(child));
      variables[variable].kind = kind;
      variables[variable].components = std::move(children);
      if (kind == AggregateKind::Array) {
        variables[variable].count = types.product(type).fields.size();
        variables[variable].symbolicCount = types.product(type).arrayCount;
      }
    } else {
      variables[variable].kind = kind;
      auto count = kind == AggregateKind::Outcome ? 2 : 1;
      std::vector<int> children;
      for (int i = 0; i < count; ++i)
        children.push_back(fresh());
      variables[variable].components = std::move(children);
    }
  }
  if (*variables[variable].kind != kind) {
    diagnostics.error("type", span, "incompatible aggregate shape");
    return {};
  }
  return variables[variable].components;
}
void TypeInference::equal(int a, int b, Span span, bool coercion) {
  a = root(a);
  b = root(b);
  if (a == b)
    return;
  auto at = variables[a].type, bt = variables[b].type;
  if (coercion && at == Type::Never)
    return;
  auto an = variables[a].numeric, bn = variables[b].numeric;
  auto accepts = [](Variable::Numeric constraint, Type type) {
    return constraint == Variable::Numeric::None || type == Type::Unknown ||
           (constraint == Variable::Numeric::Integer && isInteger(type)) ||
           (constraint == Variable::Numeric::Floating && isFloating(type));
  };
  if (!accepts(an, bt) || !accepts(bn, at) ||
      (an != Variable::Numeric::None && bn != Variable::Numeric::None &&
       an != bn)) {
    diagnostics.error("type", span,
                      "expected " + std::string(types.name(value(b))) +
                          ", found " + std::string(types.name(value(a))));
    return;
  }
  if (variables[a].kind || variables[b].kind) {
    auto kind = variables[a].kind ? *variables[a].kind : *variables[b].kind;
    if ((variables[a].kind && variables[b].kind &&
         variables[a].kind != variables[b].kind) ||
        (at != Type::Unknown &&
         (!types.isProduct(at) || types.product(at).kind != kind)) ||
        (bt != Type::Unknown &&
         (!types.isProduct(bt) || types.product(bt).kind != kind))) {
      diagnostics.error("type", span, "incompatible aggregate shape");
      return;
    }
    if (!variables[a].kind && at == Type::Unknown) {
      if (occurs(a, b)) {
        diagnostics.error("type", span, "recursive inferred type");
        return;
      }
      variables[a].parent = b;
      return;
    }
    if (!variables[b].kind && bt == Type::Unknown) {
      if (occurs(b, a)) {
        diagnostics.error("type", span, "recursive inferred type");
        return;
      }
      variables[b].parent = a;
      return;
    }
    auto ac = components(a, kind, span), bc = components(b, kind, span);
    auto count = [&](int variable) {
      return types.canonicalCount(
          variables[variable].symbolicCount != Type::Unknown
              ? variables[variable].symbolicCount
              : types.constant(Type::I32, variables[variable].count));
    };
    if (ac.size() != bc.size() ||
        (kind == AggregateKind::Array && count(a) != count(b))) {
      diagnostics.error("type", span, "aggregate lengths do not match");
      return;
    }
    for (std::size_t i = 0; i < ac.size(); ++i)
      equal(ac[i], bc[i], span);
    variables[a].parent = b;
    return;
  }
  if (at != Type::Unknown && bt != Type::Unknown && at != bt) {
    diagnostics.error("type", span,
                      "expected " + std::string(types.name(bt)) + ", found " +
                          std::string(types.name(at)));
    return;
  }
  variables[a].parent = b;
  if (bt == Type::Unknown)
    variables[b].type = at;
  if (bn == Variable::Numeric::None)
    variables[b].numeric = an;
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
