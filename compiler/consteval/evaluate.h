#pragma once

#include "source/source.h"
#include "support/limits.h"
#include "syntax/ast.h"
#include "types/type.h"
#include <optional>
#include <string>
#include <vector>

// The compiler-owned compile-time evaluator. It interprets checked-syntax
// expressions and `const fn` bodies as a pure function of the program text and
// the target's integer widths: no host integer, clock, environment or address
// is observable, and every fault is a spanned diagnostic.
namespace mettle::evaluation {
// A compile-time value. Integers carry 128-bit magnitudes; `type` is Unknown
// for an unsuffixed literal that has not met a typed operand yet.
struct Value {
  enum class Kind { Integer, Floating, Enum, Bool, Char, Unit, Tuple, Array };
  Kind kind = Kind::Unit;
  Type type = Type::Unit;
  NumericLiteral number{};
  std::vector<Value> elements{};
};

struct Lookup {
  // Missing: no such name. Constant: an immutable value. Function: a callable
  // item. Symbolic: depends on an unbound generic parameter, so the
  // expression cannot be evaluated here and no diagnostic is produced.
  // Failed: the host already reported why the name cannot be used.
  enum class Kind { Missing, Constant, Function, Symbolic, Failed };
  Kind kind = Kind::Missing;
  Value value{};
  const Function *function = nullptr;
};

// Name resolution and diagnostics belong to the caller, so the evaluator
// depends on neither the checker nor the resolver.
class Host {
public:
  virtual ~Host() = default;
  virtual void report(const std::string &phase, Span span,
                      const std::string &message) = 0;
  virtual Lookup lookup(const Node &name) = 0;
  virtual Type resolveType(const TypeSyntax &type, Span) {
    return builtinType(type.name);
  }
  virtual bool enumeration(Type) { return false; }
  virtual Lookup variant(Type, std::string_view, Span) { return {}; }
  virtual Lookup floatingValue(Type, std::string_view, Span) { return {}; }
  virtual Lookup method(Type, const Node &) { return {}; }
};

struct Options {
  // 16, 32 or 64; 0 selects 64. Selects usize/isize widths.
  unsigned pointerBits = 64;
  bool littleEndian = true;
  NumericEvaluator numericEvaluator = nullptr;
  bool unsafeContext = false;
  std::size_t stepBudget = limits::constEvalSteps;
  unsigned callDepth = limits::constEvalDepth;
};

// The type structure the evaluator can represent: scalars, Unit, tuples and
// fixed-length arrays of those.
struct Shape {
  enum class Kind { Scalar, Unit, Tuple, Array };
  Kind kind = Kind::Scalar;
  Type type = Type::Unknown;
  std::vector<Shape> elements{};
  std::uint64_t count = 0;
};

struct Expectation {
  // A scalar type the result must have, or the declared structure of the
  // item; `shape` takes precedence.
  Type scalar = Type::Unknown;
  const Shape *shape = nullptr;
};

struct Result {
  std::optional<Value> value;
  // The expression names an unbound generic parameter; nothing was reported.
  bool symbolic = false;
};

// Evaluates `node`. On failure the diagnostic has been reported to the host
// (unless the result is symbolic) and the value is empty. Unsuffixed integer
// results without an expectation are i32.
Result evaluate(Host &host, const Options &options, const Node &node,
                const Expectation &expected);
// Applies the target-width cast rules of the language to an integer.
NumericLiteral castInteger(const NumericLiteral &value, Type target,
                           unsigned pointerBits);
} // namespace mettle::evaluation
