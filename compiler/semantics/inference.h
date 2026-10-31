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
  void equal(int a, int b, Span span, bool coercion = false);
  int joined(int a, int b, Span span);
  void set(int variable, Type type);
  int composite(AggregateKind kind, std::vector<int> components,
                std::uint32_t count = 0, Type symbolicCount = Type::Unknown);
  std::vector<int> components(int variable, AggregateKind kind, Span span);
  int representative(int variable) { return root(variable); }
  // Whether the variable is, or structurally contains, a listed representative.
  bool depends(int variable, const std::set<int> &representatives);
  // An unsuffixed integer whose type has not been fixed yet. `value` reports
  // that variable as `i32` without committing the default.
  bool unresolvedInteger(int variable);

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
