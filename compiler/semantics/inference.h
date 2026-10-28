#pragma once

#include "diagnostics/diagnostics.h"
#include "types/type.h"

namespace mettle {
class TypeInference {
public:
  TypeInference(Diagnostics &diagnostics, const TypeStore &types)
      : diagnostics(diagnostics), types(types) {}
  int fresh(Type type = Type::Unknown);
  Type value(int variable);
  void equal(int a, int b, Span span, bool coercion = false);
  int joined(int a, int b, Span span);
  void set(int variable, Type type);

private:
  struct Variable {
    int parent;
    Type type;
  };
  Diagnostics &diagnostics;
  const TypeStore &types;
  std::vector<Variable> variables;
  int root(int variable);
};
} // namespace mettle
