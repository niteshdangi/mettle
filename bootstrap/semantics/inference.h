#pragma once

#include "diagnostics/diagnostics.h"
#include "types/type.h"
#include <optional>
#include <set>

namespace mettle {
class TypeInference {
public:
  TypeInference(Diagnostics &diagnostics, TypeStore &types)
      : diagnostics(diagnostics), types(types) {}
  int fresh(Type type = Type::Unknown);
  int numeric(bool floating, Type type = Type::Unknown);
  Type value(int variable);
  bool equal(int a, int b, Span span, bool coercion = false);
  int joined(int a, int b, Span span);
  void set(int variable, Type type);
  int composite(AggregateKind kind, std::vector<int> components,
                std::uint32_t count = 0, Type symbolicCount = Type::Unknown);
  std::vector<int> components(int variable, AggregateKind kind, Span span);
  int representative(int variable) { return root(variable); }
  // An integer literal whose type no constraint has chosen yet (it would
  // default to i32).
  bool pendingInteger(int variable) {
    const auto &found = variables[root(variable)];
    return found.type == Type::Unknown && !found.kind &&
           found.numeric == Variable::Numeric::Integer;
  }
  // A numeric literal no constraint has typed yet (it would default).
  bool pendingNumeric(int variable) {
    const auto &found = variables[root(variable)];
    return found.type == Type::Unknown && !found.kind &&
           found.numeric != Variable::Numeric::None;
  }
  // Whether the variable is, or structurally contains, a listed representative.
  bool depends(int variable, const std::set<int> &representatives);

private:
  struct Variable {
    int parent;
    Type type;
    std::optional<AggregateKind> kind{};
    std::vector<int> components{};
    std::uint32_t count = 0;
    Type symbolicCount = Type::Unknown;
    enum class Numeric { None, Integer, Floating };
    Numeric numeric = Numeric::None;
  };
  Diagnostics &diagnostics;
  TypeStore &types;
  std::vector<Variable> variables;
  int root(int variable);
  bool occurs(int variable, int within);
};
} // namespace mettle
