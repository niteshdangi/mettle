#pragma once

#include "source/source.h"
#include "support/limits.h"
#include "syntax/ast.h"
#include "types/type.h"
#include <memory>
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
  enum class Kind {
    Integer,
    Floating,
    Enum,
    Bool,
    Char,
    Unit,
    Tuple,
    Array,
    Product,
    Variant,
    Reference,
    Pointer,
    Uninitialized
  };
  Kind kind = Kind::Unit;
  Type type = Type::Unit;
  NumericLiteral number{};
  std::vector<Value> elements{};
  std::weak_ptr<Value> storage{};
  Type storageType = Type::Unknown;
  std::uint64_t offset = 0, count = 0;
  int symbol = -1, selection = -1;
  bool exclusive = false, writable = false, addressOnly = false;
};

struct Shape {
  enum class Kind {
    Scalar,
    Unit,
    Tuple,
    Array,
    Product,
    Variant,
    Reference,
    Pointer
  };
  Kind kind = Kind::Scalar;
  Type type = Type::Unknown;
  std::vector<Shape> elements{};
  std::uint64_t count = 0;
  std::vector<std::string> names{};
  std::vector<std::vector<std::size_t>> variants{};
  bool exclusive = false;
};

struct CheckedFunction {
  struct Parameter {
    std::string name;
    Shape shape;
    Span span{};
    const Node *defaultValue = nullptr;
    SyntaxContextPtr context{};
    ParameterMode mode = ParameterMode::Value;
  };
  std::vector<Parameter> parameters;
  Shape result;
  // Checked expression storage outlives every evaluation using this descriptor.
  const Node *body = nullptr;
  bool unsafeFunction = false;
  const Function *declaration = nullptr;
  std::vector<TypeBinding> bindings{};
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
  const CheckedFunction *checkedFunction = nullptr;
  // Optional declaration-only eligibility contract for a checked body.
  const Function *declaration = nullptr;
  std::shared_ptr<CheckedFunction> prepared{};
  int staticSymbol = -1;
  bool freshValue = false;
};

// Name resolution and diagnostics belong to the caller, so the evaluator
// depends on neither the checker nor the resolver.
class Host {
public:
  struct Layout {
    std::uint64_t size = 0, alignment = 1;
    std::vector<std::uint64_t> fields{};
  };
  struct Operation {
    std::string name;
    Type type = Type::Unknown;
    int field = -1;
  };
  virtual ~Host() = default;
  virtual void report(const std::string &phase, Span span,
                      const std::string &message) = 0;
  virtual Lookup lookup(const Node &name, std::size_t &remaining) = 0;
  virtual Type resolveType(const TypeSyntax &type, Span) {
    return builtinType(type.name);
  }
  virtual bool enumeration(Type) { return false; }
  virtual Lookup variant(Type, std::string_view, Span) { return {}; }
  virtual Lookup floatingValue(Type, std::string_view, Span) { return {}; }
  virtual Lookup method(Type, const Node &) { return {}; }
  virtual std::optional<Shape> expressionShape(const Node &) {
    return std::nullopt;
  }
  virtual std::optional<Shape> functionResult(const Function &) {
    return std::nullopt;
  }
  virtual std::optional<Shape> typeShape(Type) { return std::nullopt; }
  virtual bool project(Type, std::size_t, const Node &) { return true; }
  virtual Type valueType(const Value &value) { return value.type; }
  virtual Type referenceType(Type, bool, bool) { return Type::Unknown; }
  virtual std::optional<Layout> layout(Type) { return std::nullopt; }
  virtual bool needsDrop(Type) { return false; }
  virtual bool copy(Type) { return true; }
  virtual std::optional<Value> storage(int) { return std::nullopt; }
  virtual Operation operation(const Node &) { return {}; }
  virtual const Node *receiver(const Node &) { return nullptr; }
  virtual Lookup prepare(const Node &, const Value *, std::span<const Value>,
                         const Shape *) {
    return {};
  }
  virtual void enter(const CheckedFunction &) {}
  virtual void leave() {}
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
