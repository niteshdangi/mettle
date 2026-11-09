#include "consteval/evaluate.h"
#include "diagnostics/diagnostics.h"
#include "support/path.h"
#include "syntax/lexer.h"
#include "types/machine.h"
#include <algorithm>
#include <deque>
#include <exception>
#include <pthread.h>
#include <stdexcept>

namespace mettle::evaluation {
namespace {
Shape scalarShape(Type type) {
  Shape shape;
  shape.type = type;
  return shape;
}

Value integerValue(Type type, NumericLiteral number) {
  Value value;
  value.kind = Value::Kind::Integer;
  value.type = type;
  value.number = std::move(number);
  return value;
}
Value boolValue(bool truth) {
  Value value;
  value.kind = Value::Kind::Bool;
  value.type = Type::Bool;
  value.number = integerLiteral(truth ? 1 : 0);
  return value;
}
Value charValue(std::uint32_t code) {
  Value value;
  value.kind = Value::Kind::Char;
  value.type = Type::Char;
  value.number = integerLiteral(code);
  return value;
}
Value unitValue() { return Value{}; }

bool truth(const Value &value) { return value.number.magnitude[0] != 0; }

Shape shapeOfValue(const Value &value) {
  Shape shape;
  switch (value.kind) {
  case Value::Kind::Unit:
    shape.kind = Shape::Kind::Unit;
    break;
  case Value::Kind::Tuple:
    shape.kind = Shape::Kind::Tuple;
    for (const auto &element : value.elements)
      shape.elements.push_back(shapeOfValue(element));
    break;
  case Value::Kind::Array:
    shape.kind = Shape::Kind::Array;
    shape.count = value.elements.size();
    if (!value.elements.empty())
      shape.elements.push_back(shapeOfValue(value.elements.front()));
    else
      shape.elements.push_back(scalarShape(Type::Unknown));
    break;
  default:
    shape.type = value.type;
  }
  return shape;
}

bool complete(const Shape &shape) {
  if (shape.kind == Shape::Kind::Scalar)
    return shape.type != Type::Unknown;
  return std::all_of(shape.elements.begin(), shape.elements.end(),
                     [](const Shape &element) { return complete(element); });
}

std::string describe(const Value &value) {
  switch (value.kind) {
  case Value::Kind::Integer:
    return value.type == Type::Unknown ? "integer" : displayType(value.type);
  case Value::Kind::Floating:
    return value.type == Type::Unknown ? "floating point"
                                       : displayType(value.type);
  case Value::Kind::Enum:
    return displayType(value.type);
  case Value::Kind::Bool:
    return "bool";
  case Value::Kind::Char:
    return "char";
  case Value::Kind::Unit:
    return "Unit";
  case Value::Kind::Tuple:
    return "a tuple";
  case Value::Kind::Array:
    return "an array";
  }
  return "value";
}
std::string describe(const Shape &shape) {
  switch (shape.kind) {
  case Shape::Kind::Scalar:
    return shape.type == Type::Unknown ? "integer" : displayType(shape.type);
  case Shape::Kind::Unit:
    return "Unit";
  case Shape::Kind::Tuple:
    return "a tuple";
  case Shape::Kind::Array:
    return "an array";
  }
  return "value";
}

struct Local {
  std::string name;
  Value value;
  bool mutableBinding = false;
};
struct Frame {
  std::deque<Local> locals;
  Shape result;
  bool inFunction = false;
};

struct Integer {
  NumericLiteral number;
  Type suffix = Type::Unknown;
};

std::optional<Integer> parseInteger(std::string spelling, bool negative) {
  Integer result;
  result.number.negative = negative;
  for (auto type :
       {Type::I128, Type::U128, Type::Isize, Type::Usize, Type::I64, Type::U64,
        Type::I32, Type::U32, Type::I16, Type::U16, Type::I8, Type::U8}) {
    auto name = typeName(type);
    if (spelling.ends_with(name)) {
      spelling.resize(spelling.size() - name.size());
      result.suffix = type;
      break;
    }
  }
  spelling.erase(std::remove(spelling.begin(), spelling.end(), '_'),
                 spelling.end());
  unsigned radix = 10;
  std::size_t position = 0;
  if (spelling.starts_with("0x") || spelling.starts_with("0o") ||
      spelling.starts_with("0b")) {
    radix = spelling[1] == 'x' ? 16 : spelling[1] == 'o' ? 8 : 2;
    position = 2;
  }
  if (position == spelling.size())
    return std::nullopt;
  std::array<std::uint32_t, 4> limbs{};
  for (; position < spelling.size(); ++position) {
    auto c = spelling[position];
    unsigned digit = c >= '0' && c <= '9'   ? c - '0'
                     : c >= 'a' && c <= 'f' ? c - 'a' + 10
                     : c >= 'A' && c <= 'F' ? c - 'A' + 10
                                            : 255;
    if (digit >= radix)
      return std::nullopt;
    std::uint64_t carry = digit;
    for (auto &limb : limbs) {
      auto product = std::uint64_t{limb} * radix + carry;
      limb = static_cast<std::uint32_t>(product);
      carry = product >> 32;
    }
    if (carry)
      return std::nullopt;
  }
  result.number.magnitude = {
      std::uint64_t{limbs[0]} | (std::uint64_t{limbs[1]} << 32),
      std::uint64_t{limbs[2]} | (std::uint64_t{limbs[3]} << 32)};
  return result;
}

class Interpreter {
public:
  Interpreter(Host &host, const Options &options)
      : host(host), options(options) {
    if (!this->options.pointerBits)
      this->options.pointerBits = 64;
    unsafeDepth = options.unsafeContext ? 1 : 0;
  }

  Result run(const Node &node, const Expectation &expected) {
    Result result;
    std::optional<Shape> want;
    if (expected.shape)
      want = *expected.shape;
    else if (expected.scalar != Type::Unknown)
      want = scalarShape(expected.scalar);
    frames.emplace_back();
    auto value = eval(node, want ? &*want : nullptr);
    if (value && want && !coerce(*value, *want, node.span))
      value.reset();
    if (value && !defaultTypes(*value, node.span))
      value.reset();
    if (!value && !failed)
      fail("constant", node.span,
           "'break', 'continue' or 'return' outside a loop or const function");
    result.value = std::move(value);
    return finish(result);
  }

private:
  using Opt = std::optional<Value>;
  enum class Signal { None, Break, Continue, Return };
  struct Fault {
    std::string phase;
    Span span;
    std::string message;
  };
  struct Scope {
    explicit Scope(Frame &frame) : frame(frame), mark(frame.locals.size()) {}
    ~Scope() {
      while (frame.locals.size() > mark)
        frame.locals.pop_back();
    }
    Scope(const Scope &) = delete;
    Scope &operator=(const Scope &) = delete;
    Frame &frame;
    std::size_t mark;
  };

  Host &host;
  Options options;
  std::deque<Frame> frames;
  std::size_t steps = 0;
  unsigned unsafeDepth = 0;
  bool failed = false, symbolic = false, reported = false;
  std::optional<Fault> fault;
  Signal signal = Signal::None;
  std::string signalLabel;
  Value signalValue;

  Result finish(Result &result) {
    if (failed && !symbolic && !reported && fault)
      host.report(fault->phase, fault->span, fault->message);
    result.symbolic = symbolic;
    if (failed)
      result.value.reset();
    return std::move(result);
  }
  std::nullopt_t fail(const std::string &phase, Span span,
                      const std::string &message) {
    if (!failed)
      fault = Fault{phase, span, message};
    failed = true;
    return std::nullopt;
  }
  std::nullopt_t unsupported(Span span, const std::string &what) {
    return fail("feature", span,
                what + " is not supported in constant evaluation");
  }
  Frame &frame() { return frames.back(); }

  Opt numericOperation(std::string_view operation, Type owner,
                       std::span<const Value> values, Span span) {
    if (!options.numericEvaluator)
      return unsupported(span, "floating evaluation without a numeric adapter");
    std::vector<NumericConstant> arguments;
    for (const auto &value : values)
      arguments.push_back(
          {integerEquivalent(value.type, options.pointerBits), value.number});
    auto result = options.numericEvaluator(operation, owner, arguments);
    if (!result)
      return unsupported(span, "this numeric operation");
    Value value;
    value.type = result->type;
    value.number = std::move(result->literal);
    if (isFloating(value.type)) {
      if (!validFloatingConstant(value.number, value.type))
        return fail("internal", span, "invalid evaluated floating value");
      value.kind = Value::Kind::Floating;
    } else if (value.type == Type::Bool) {
      if (!integerLiteralFits(value.number, Type::Bool))
        return fail("internal", span, "invalid evaluated boolean value");
      value.kind = Value::Kind::Bool;
    } else if (isInteger(value.type)) {
      if (!integerLiteralFits(value.number, value.type, options.pointerBits))
        return fail("internal", span, "invalid evaluated integer value");
      value.kind = Value::Kind::Integer;
    } else
      return fail("internal", span, "invalid numeric evaluation result type");
    return value;
  }
  Opt numericOperation(std::string_view operation, Type owner,
                       std::initializer_list<Value> values, Span span) {
    return numericOperation(operation, owner,
                            std::span(values.begin(), values.size()), span);
  }
  bool realizeFloating(Value &value, Type type, Span span) {
    if (!isFloating(type) ||
        (value.type != Type::Unknown && value.type != type)) {
      fail("type", span, "mismatched floating types in constant expression");
      return false;
    }
    value.type = type;
    if (value.number.floatingBits)
      return validFloatingConstant(value.number, type);
    auto result = numericOperation("literal", type, {value}, span);
    if (!result)
      return false;
    value = std::move(*result);
    return true;
  }

  Type namedType(const Node &node) {
    if (node.kind != Kind::Name)
      return Type::Unknown;
    for (const auto &local : frame().locals)
      if (local.name == node.text)
        return Type::Unknown;
    TypeSyntax syntax;
    syntax.name = node.text;
    return host.resolveType(syntax, node.span);
  }

  Opt primitiveCall(const Node &node, Type owner, std::string_view name,
                    const std::optional<Value> &receiver) {
    bool constructor = name == "from_bits" || name == "from_be_bytes" ||
                       name == "from_le_bytes" || name == "from_ne_bytes";
    if (constructor == receiver.has_value())
      return fail("type", node.span,
                  "float constructor and receiver call forms do not match");
    bool bytes = name.ends_with("_bytes");
    std::size_t count = constructor                            ? 1
                        : name == "mul_add" || name == "clamp" ? 2
                        : name == "copysign" || name == "min" ||
                                name == "max" || name == "midpoint"
                            ? 1
                            : 0;
    if (node.children.size() != count + 1)
      return fail("type", node.span, "wrong number of float method arguments");
    std::vector<Value> arguments;
    if (receiver)
      arguments.push_back(*receiver);
    auto bitsType = owner == Type::F32 ? Type::U32 : Type::U64;
    auto byteCount = owner == Type::F32 ? 4u : 8u;
    Shape argumentShape = scalarShape(constructor ? bitsType : owner);
    if (constructor && bytes) {
      argumentShape.kind = Shape::Kind::Array;
      argumentShape.count = byteCount;
      argumentShape.elements.push_back(scalarShape(Type::U8));
    }
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      auto value = eval(*node.children[i], &argumentShape);
      if (!value || !coerce(*value, argumentShape, node.children[i]->span))
        return std::nullopt;
      arguments.push_back(std::move(*value));
    }
    if (name == "clamp") {
      auto ordered = numericOperation("<=", owner, {arguments[1], arguments[2]},
                                      node.span);
      if (!ordered)
        return std::nullopt;
      if (!truth(*ordered))
        return fail("constant", node.span,
                    "clamp bounds require non-NaN min <= max");
    }
    bool little = name == "from_le_bytes" || name == "to_le_bytes" ||
                  (name.ends_with("ne_bytes") && options.littleEndian);
    if (constructor && bytes) {
      NumericLiteral bits;
      for (unsigned i = 0; i < byteCount; ++i) {
        auto shift = (little ? i : byteCount - 1 - i) * 8;
        bits.magnitude[0] |= arguments[0].elements[i].number.magnitude[0]
                             << shift;
      }
      return numericOperation("from_bits", owner,
                              {integerValue(bitsType, bits)}, node.span);
    }
    if (!constructor && bytes) {
      auto bits = numericOperation("to_bits", owner, arguments, node.span);
      if (!bits)
        return std::nullopt;
      Value array;
      array.kind = Value::Kind::Array;
      array.type = Type::Unknown;
      for (unsigned i = 0; i < byteCount; ++i) {
        auto shift = (little ? i : byteCount - 1 - i) * 8;
        array.elements.push_back(integerValue(
            Type::U8,
            integerLiteral((bits->number.magnitude[0] >> shift) & 0xff)));
      }
      return array;
    }
    return numericOperation(name, owner, arguments, node.span);
  }

  // Type structure of a declared type.
  std::optional<Shape> shape(const TypeSyntax &type, Span span) {
    if (!type.view.empty() || !type.regions.empty() || type.nested ||
        !type.arguments.empty()) {
      unsupported(span, "this type");
      return std::nullopt;
    }
    switch (type.form) {
    case TypeForm::Named: {
      auto builtin = host.resolveType(type, span);
      if (builtin == Type::Unit) {
        Shape result;
        result.kind = Shape::Kind::Unit;
        return result;
      }
      if (builtin == Type::Unknown || builtin == Type::Never ||
          (!isNumeric(builtin) && builtin != Type::Bool &&
           builtin != Type::Char && !host.enumeration(builtin))) {
        unsupported(span, "type '" + displayPath(type.name) + "'");
        return std::nullopt;
      }
      return scalarShape(builtin);
    }
    case TypeForm::Tuple: {
      Shape result;
      result.kind = Shape::Kind::Tuple;
      for (const auto &element : type.elements) {
        auto inner = shape(element, span);
        if (!inner)
          return std::nullopt;
        result.elements.push_back(std::move(*inner));
      }
      return result;
    }
    case TypeForm::Array: {
      Shape result;
      result.kind = Shape::Kind::Array;
      auto inner = shape(type.elements.front(), span);
      if (!inner || !type.countExpression)
        return std::nullopt;
      result.elements.push_back(std::move(*inner));
      auto count = length(*type.countExpression);
      if (!count)
        return std::nullopt;
      result.count = *count;
      return result;
    }
    default:
      unsupported(span, "this type");
      return std::nullopt;
    }
  }
  std::optional<std::uint64_t> length(const Node &node) {
    auto usize = scalarShape(Type::Usize);
    auto value = eval(node, &usize);
    if (!value || !coerce(*value, usize, node.span))
      return std::nullopt;
    if (value->number.magnitude[1] ||
        value->number.magnitude[0] > options.stepBudget) {
      fail("limit", node.span,
           "constant evaluation exceeded the aggregate size limit");
      return std::nullopt;
    }
    return value->number.magnitude[0];
  }

  bool step(Span span) {
    if (++steps > options.stepBudget) {
      fail("limit", span,
           "constant evaluation exceeded the step budget of " +
               std::to_string(options.stepBudget) +
               " steps (unbounded loop or recursion?)");
      return false;
    }
    return true;
  }

  // Gives an unsuffixed integer its type or checks a typed value against the
  // declared one.
  bool coerce(Value &value, const Shape &want, Span span) {
    switch (want.kind) {
    case Shape::Kind::Unit:
      if (value.kind == Value::Kind::Unit)
        return true;
      break;
    case Shape::Kind::Scalar:
      if (want.type == Type::Unknown)
        return true;
      if (want.type == Type::Bool) {
        if (value.kind == Value::Kind::Bool)
          return true;
      } else if (want.type == Type::Char) {
        if (value.kind == Value::Kind::Char)
          return true;
      } else if (isFloating(want.type) && value.kind == Value::Kind::Floating) {
        return realizeFloating(value, want.type, span);
      } else if (value.kind == Value::Kind::Enum && value.type == want.type) {
        return true;
      } else if (value.kind == Value::Kind::Integer) {
        if (value.type == want.type)
          return true;
        if (value.type == Type::Unknown) {
          if (!integerLiteralFits(value.number, want.type,
                                  options.pointerBits)) {
            fail("constant", span,
                 "integer constant " + integerLiteralName(value.number) +
                     " does not fit type " + displayType(want.type));
            return false;
          }
          value.type = want.type;
          return true;
        }
      }
      break;
    case Shape::Kind::Tuple:
      if (value.kind == Value::Kind::Tuple &&
          value.elements.size() == want.elements.size()) {
        for (std::size_t i = 0; i < value.elements.size(); ++i)
          if (!coerce(value.elements[i], want.elements[i], span))
            return false;
        return true;
      }
      break;
    case Shape::Kind::Array:
      if (value.kind == Value::Kind::Array) {
        if (value.elements.size() != want.count) {
          fail("type", span,
               "expected an array of " + std::to_string(want.count) +
                   " elements, found " + std::to_string(value.elements.size()));
          return false;
        }
        for (auto &element : value.elements)
          if (!coerce(element, want.elements.front(), span))
            return false;
        return true;
      }
      break;
    }
    fail("type", span,
         "expected " + describe(want) + ", found " + describe(value));
    return false;
  }
  // Remaining unsuffixed integers are i32, as in checked code.
  bool defaultTypes(Value &value, Span span) {
    if (value.kind == Value::Kind::Floating)
      return realizeFloating(
          value, value.type == Type::Unknown ? Type::F64 : value.type, span);
    if (value.kind == Value::Kind::Integer && value.type == Type::Unknown)
      return coerce(value, scalarShape(Type::I32), span);
    for (auto &element : value.elements)
      if (!defaultTypes(element, span))
        return false;
    return true;
  }
  bool unify(Value &left, Value &right, Span span) {
    if (left.kind != right.kind) {
      fail("type", span,
           "mismatched operand types " + describe(left) + " and " +
               describe(right));
      return false;
    }
    if (left.kind == Value::Kind::Floating) {
      auto type = left.type != Type::Unknown    ? left.type
                  : right.type != Type::Unknown ? right.type
                                                : Type::F64;
      return coerce(left, scalarShape(type), span) &&
             coerce(right, scalarShape(type), span);
    }
    if (left.kind == Value::Kind::Enum && left.type != right.type) {
      fail("type", span, "mismatched enum types in constant expression");
      return false;
    }
    if (left.kind != Value::Kind::Integer)
      return true;
    if (left.type == Type::Unknown && right.type != Type::Unknown)
      return coerce(left, scalarShape(right.type), span);
    if (right.type == Type::Unknown && left.type != Type::Unknown)
      return coerce(right, scalarShape(left.type), span);
    if (left.type != right.type) {
      fail("type", span,
           "mismatched integer types " + describe(left) + " and " +
               describe(right));
      return false;
    }
    return true;
  }

  Opt integerOperation(const std::string &op, Type type, const Value &left,
                       const Value &right, Span span) {
    auto kernel = type == Type::Unknown ? Type::I128 : type;
    try {
      auto number = evaluateIntegerConstant(op, kernel, left.number,
                                            right.number, options.pointerBits);
      return integerValue(type, number);
    } catch (const std::invalid_argument &error) {
      std::string message = error.what();
      if (message == "required integer constant overflows")
        message = "integer overflow in constant expression (" + op + " on " +
                  (type == Type::Unknown ? "integer" : displayType(type)) + ")";
      return fail("constant", span, message);
    }
  }

  Opt binary(const std::string &op, Value left, Value right, Span span) {
    bool comparison = op == "==" || op == "!=" || op == "<" || op == "<=" ||
                      op == ">" || op == ">=";
    if (op == "<<" || op == ">>") {
      if (left.kind != Value::Kind::Integer ||
          right.kind != Value::Kind::Integer)
        return fail("type", span, "shifts require integer operands");
      return integerOperation(op, left.type, left, right, span);
    }
    if (!unify(left, right, span))
      return std::nullopt;
    if (left.kind == Value::Kind::Floating)
      return numericOperation(op, left.type, {left, right}, span);
    if (left.kind == Value::Kind::Enum) {
      if (op != "==" && op != "!=")
        return unsupported(span, "this enum operator");
      bool equal = left.number == right.number;
      return boolValue(op == "==" ? equal : !equal);
    }
    if (left.kind == Value::Kind::Bool) {
      bool a = truth(left), b = truth(right);
      if (op == "==")
        return boolValue(a == b);
      if (op == "!=" || op == "^")
        return boolValue(a != b);
      if (op == "&")
        return boolValue(a && b);
      if (op == "|")
        return boolValue(a || b);
      return fail("type", span, "operator '" + op + "' does not apply to bool");
    }
    if (left.kind == Value::Kind::Char) {
      if (!comparison)
        return fail("type", span,
                    "operator '" + op + "' does not apply to char");
      return integerOperation(op, Type::Bool, left, right, span);
    }
    if (left.kind != Value::Kind::Integer)
      return fail("type", span,
                  "operator '" + op + "' does not apply to " + describe(left));
    auto result = integerOperation(op, left.type, left, right, span);
    if (result && comparison)
      return boolValue(truth(*result));
    return result;
  }

  Opt cast(const Node &node, Value value) {
    auto target = shape(node.annotation, node.span);
    if (!target)
      return std::nullopt;
    if (target->kind != Shape::Kind::Scalar)
      return fail("type", node.span, "casts apply to scalar types only");
    auto to = target->type;
    if (isNumeric(to) &&
        (value.kind == Value::Kind::Floating ||
         (value.kind == Value::Kind::Integer && isFloating(to)))) {
      if (!defaultTypes(value, node.span))
        return std::nullopt;
      auto result =
          numericOperation("cast", integerEquivalent(to, options.pointerBits),
                           {value}, node.span);
      if (result)
        result->type = to;
      return result;
    }
    if (value.kind == Value::Kind::Integer && isInteger(to))
      return integerValue(to,
                          castInteger(value.number, to, options.pointerBits));
    if ((value.kind == Value::Kind::Bool || value.kind == Value::Kind::Char) &&
        isInteger(to))
      return integerValue(to,
                          castInteger(value.number, to, options.pointerBits));
    if (value.kind == Value::Kind::Bool && to == Type::Bool)
      return value;
    if (value.kind == Value::Kind::Char && to == Type::Char)
      return value;
    if (to == Type::Char && value.kind == Value::Kind::Integer &&
        (value.type == Type::U8 ||
         (value.type == Type::Unknown &&
          integerLiteralFits(value.number, Type::U8, options.pointerBits))))
      return charValue(static_cast<std::uint32_t>(value.number.magnitude[0]));
    return fail("type", node.span,
                "cannot cast " + describe(value) + " to " + describe(*target));
  }

  // The storage of a place rooted at a local of the current frame.
  struct Place {
    Value *value = nullptr;
    bool mutableBinding = false;
    std::string root;
  };
  Place place(const Node &node) {
    if (failed)
      return {};
    switch (node.kind) {
    case Kind::Group:
      return place(*node.children[0]);
    case Kind::Name: {
      auto &locals = frame().locals;
      for (auto it = locals.rbegin(); it != locals.rend(); ++it)
        if (it->name == node.text)
          return {&it->value, it->mutableBinding, it->name};
      return {};
    }
    case Kind::Field: {
      auto base = place(*node.children[0]);
      if (!base.value || base.value->kind != Value::Kind::Tuple)
        return {};
      std::uint64_t index = 0;
      if (node.text.empty() ||
          !std::all_of(node.text.begin(), node.text.end(),
                       [](char c) { return c >= '0' && c <= '9'; }) ||
          node.text.size() > 9)
        return {};
      index = std::stoull(node.text);
      if (index >= base.value->elements.size())
        return {};
      base.value = &base.value->elements[index];
      return base;
    }
    case Kind::Index: {
      auto base = place(*node.children[0]);
      if (!base.value || base.value->kind != Value::Kind::Array)
        return {};
      auto usize = scalarShape(Type::Usize);
      auto index = eval(*node.children[1], &usize);
      if (!index)
        return {};
      if (index->kind != Value::Kind::Integer ||
          (index->type != Type::Unknown && index->type != Type::Usize)) {
        fail("type", node.children[1]->span,
             "array index must be usize, found " + describe(*index));
        return {};
      }
      if (index->number.negative || index->number.magnitude[1] ||
          index->number.magnitude[0] >= base.value->elements.size()) {
        fail("constant", node.span,
             "index out of bounds in constant expression: the length is " +
                 std::to_string(base.value->elements.size()) +
                 " but the index is " + integerLiteralName(index->number));
        return {};
      }
      base.value = &base.value->elements[index->number.magnitude[0]];
      return base;
    }
    default:
      return {};
    }
  }

  // Matches a pattern; bindings go to `binds`. Empty on error.
  std::optional<bool> matches(const Pattern &pattern, const Value &value,
                              std::vector<Local> &binds, bool mutableBinding) {
    switch (pattern.kind) {
    case PatternKind::Wildcard:
      return true;
    case PatternKind::Binding: {
      Node name;
      name.kind = Kind::Name;
      name.span = pattern.span;
      name.text = pattern.text;
      auto found = host.lookup(name);
      switch (found.kind) {
      case Lookup::Kind::Constant: {
        if (found.value.kind == Value::Kind::Integer ||
            found.value.kind == Value::Kind::Bool ||
            found.value.kind == Value::Kind::Char)
          return sameScalar(found.value, value);
        break;
      }
      case Lookup::Kind::Symbolic:
        symbolic = true;
        failed = true;
        return std::nullopt;
      case Lookup::Kind::Failed:
        failed = true;
        reported = true;
        return std::nullopt;
      default:
        break;
      }
      binds.push_back({pattern.text, value, mutableBinding});
      return true;
    }
    case PatternKind::At: {
      auto inner = matches(pattern.children[0], value, binds, mutableBinding);
      if (inner && *inner)
        binds.push_back({pattern.text, value, mutableBinding});
      return inner;
    }
    case PatternKind::Literal: {
      auto literal = patternLiteral(pattern);
      if (!literal)
        return std::nullopt;
      return sameScalar(*literal, value);
    }
    case PatternKind::Range: {
      auto lower = patternLiteral(pattern);
      auto upper = patternLiteral(pattern.children[0]);
      if (!lower || !upper)
        return std::nullopt;
      if (value.kind != lower->kind)
        return fail("type", pattern.span,
                    "range pattern does not match " + describe(value));
      auto above = compareIntegers(value.number, lower->number) >= 0;
      auto order = compareIntegers(value.number, upper->number);
      return above && (pattern.inclusive ? order <= 0 : order < 0);
    }
    case PatternKind::Or:
      for (const auto &alternative : pattern.children) {
        std::vector<Local> attempt;
        auto matched = matches(alternative, value, attempt, mutableBinding);
        if (!matched)
          return std::nullopt;
        if (*matched) {
          binds.insert(binds.end(), attempt.begin(), attempt.end());
          return true;
        }
      }
      return false;
    case PatternKind::Tuple:
    case PatternKind::Array: {
      bool tuple = pattern.kind == PatternKind::Tuple;
      if (value.kind != (tuple ? Value::Kind::Tuple : Value::Kind::Array))
        return fail("type", pattern.span,
                    "pattern does not match " + describe(value));
      auto rest = std::find_if(
          pattern.children.begin(), pattern.children.end(),
          [](const Pattern &child) { return child.kind == PatternKind::Rest; });
      auto prefix = static_cast<std::size_t>(rest - pattern.children.begin());
      auto suffix =
          rest == pattern.children.end()
              ? 0
              : static_cast<std::size_t>(pattern.children.end() - rest - 1);
      auto fixed = rest == pattern.children.end() ? pattern.children.size()
                                                  : prefix + suffix;
      if (rest == pattern.children.end() ? value.elements.size() != fixed
                                         : value.elements.size() < fixed) {
        if (tuple)
          return fail("type", pattern.span, "tuple pattern arity mismatch");
        return false;
      }
      for (std::size_t i = 0; i < prefix; ++i) {
        auto matched = matches(pattern.children[i], value.elements[i], binds,
                               mutableBinding);
        if (!matched || !*matched)
          return matched;
      }
      for (std::size_t i = 0; i < suffix; ++i) {
        auto matched =
            matches(pattern.children[prefix + 1 + i],
                    value.elements[value.elements.size() - suffix + i], binds,
                    mutableBinding);
        if (!matched || !*matched)
          return matched;
      }
      return true;
    }
    default:
      unsupported(pattern.span, "this pattern");
      return std::nullopt;
    }
  }
  bool sameScalar(const Value &left, const Value &right) {
    return left.kind == right.kind &&
           compareIntegers(left.number, right.number) == 0;
  }
  Opt patternLiteral(const Pattern &pattern) {
    if (pattern.literalKind == TokenKind::Integer) {
      bool negative = pattern.text.starts_with("-");
      auto parsed = parseInteger(
          negative ? pattern.text.substr(1) : pattern.text, negative);
      if (!parsed)
        return fail("lex", pattern.span, "malformed integer literal");
      return integerValue(parsed->suffix, parsed->number);
    }
    if (pattern.literalKind == TokenKind::Character ||
        pattern.literalKind == TokenKind::Byte) {
      Diagnostics scratch;
      auto code =
          characterLiteral(pattern.text, pattern.literalKind == TokenKind::Byte,
                           scratch, pattern.span);
      if (!code)
        return fail("lex", pattern.span, "malformed character literal");
      return pattern.literalKind == TokenKind::Byte
                 ? integerValue(Type::U8, integerLiteral(*code))
                 : charValue(*code);
    }
    return boolValue(pattern.text == "true");
  }

  Opt literal(const Node &node, bool negative, const Shape *want) {
    if (node.kind == Kind::Floating) {
      Value value;
      value.kind = Value::Kind::Floating;
      value.type = Type::Unknown;
      auto spelling = node.text;
      for (auto type : {Type::F32, Type::F64}) {
        auto suffix = typeName(type);
        if (spelling.ends_with(suffix)) {
          spelling.resize(spelling.size() - suffix.size());
          value.type = type;
          break;
        }
      }
      spelling.erase(std::remove(spelling.begin(), spelling.end(), '_'),
                     spelling.end());
      if (negative)
        spelling.insert(spelling.begin(), '-');
      value.number.floating = std::move(spelling);
      value.number.negative = negative;
      if (!validFloatingLiteral(value.number.floating))
        return fail("lex", node.span, "malformed floating literal");
      auto type = value.type;
      if (type == Type::Unknown && want && want->kind == Shape::Kind::Scalar &&
          isFloating(want->type))
        type = want->type;
      if (type != Type::Unknown && !realizeFloating(value, type, node.span))
        return std::nullopt;
      return value;
    }
    auto parsed = parseInteger(node.text, negative);
    if (!parsed)
      return fail("lex", node.span, "malformed integer literal");
    auto value = integerValue(parsed->suffix, parsed->number);
    if (value.type != Type::Unknown) {
      if (!integerLiteralFits(value.number, value.type, options.pointerBits))
        return fail("constant", node.span,
                    "integer literal does not fit type " +
                        displayType(value.type));
      return value;
    }
    if (want && want->kind == Shape::Kind::Scalar && isInteger(want->type) &&
        !coerce(value, *want, node.span))
      return std::nullopt;
    return value;
  }

  Opt block(const Node &node, const Shape *want) {
    Scope scope(frame());
    Opt last = unitValue();
    for (std::size_t i = 0; i < node.children.size(); ++i) {
      bool tail = i + 1 == node.children.size() && !node.children[i]->semicolon;
      auto value = eval(*node.children[i], tail ? want : nullptr);
      if (!value)
        return std::nullopt;
      last = tail ? std::move(value) : Opt(unitValue());
    }
    return last;
  }

  Opt binding(const Node &node) {
    std::optional<Shape> declared;
    if (!node.annotation.empty()) {
      declared = shape(node.annotation, node.span);
      if (!declared)
        return std::nullopt;
    }
    if (node.children.empty())
      return unsupported(node.span, "a declaration without an initializer");
    auto value = eval(*node.children[0], declared ? &*declared : nullptr);
    if (!value)
      return std::nullopt;
    if (declared && !coerce(*value, *declared, node.span))
      return std::nullopt;
    // A mutable local keeps an unsuffixed integer open so later assignments
    // and uses fix its type, as ordinary checking infers it.
    bool open = node.flag && !declared && node.text != "<pattern>" &&
                value->kind == Value::Kind::Integer &&
                value->type == Type::Unknown;
    if (!open && !defaultTypes(*value, node.span))
      return std::nullopt;
    if (node.text != "<pattern>") {
      frame().locals.push_back({node.text, std::move(*value), node.flag});
      return unitValue();
    }
    std::vector<Local> binds;
    auto matched = matches(node.patterns[0], *value, binds, node.flag);
    if (!matched)
      return std::nullopt;
    if (!*matched) {
      if (node.children.size() < 2)
        return fail("constant", node.span,
                    "refutable pattern did not match in constant evaluation");
      auto diverged = eval(*node.children[1], nullptr);
      if (!diverged)
        return std::nullopt;
      return fail("constant", node.span, "let-else block did not diverge");
    }
    for (auto &bound : binds)
      frame().locals.push_back(std::move(bound));
    return unitValue();
  }

  Opt assign(const Node &node) {
    const Node &target = *node.children[0];
    auto before = place(target);
    if (failed)
      return std::nullopt;
    if (!before.value)
      return fail("constant", target.span,
                  "assignment target is not a local place in a constant "
                  "expression");
    auto hint = shapeOfValue(*before.value);
    auto value = eval(*node.children[1], &hint);
    if (!value)
      return std::nullopt;
    auto target_ = place(target);
    if (!target_.value)
      return std::nullopt;
    if (!target_.mutableBinding)
      return fail("constant", target.span,
                  "cannot assign to immutable binding '" + target_.root +
                      "' in a constant expression");
    if (node.text != "=") {
      auto op = node.text.substr(0, node.text.size() - 1);
      auto combined = binary(op, *target_.value, std::move(*value), node.span);
      if (!combined)
        return std::nullopt;
      value = std::move(combined);
    }
    if (!coerce(*value, shapeOfValue(*target_.value), node.span))
      return std::nullopt;
    *target_.value = std::move(*value);
    return unitValue();
  }

  // Runs one loop iteration's signal handling. Returns true to leave the loop;
  // `escaped` is set when the signal belongs to an outer construct or error.
  bool loopControl(const Node &loop, bool &escaped) {
    escaped = false;
    if (failed || signal == Signal::Return || signal == Signal::None) {
      escaped = true;
      return true;
    }
    if (!signalLabel.empty() && signalLabel != loop.label) {
      escaped = true;
      return true;
    }
    auto leave = signal == Signal::Break;
    if (!leave)
      signal = Signal::None;
    return leave;
  }

  Opt condition(const Node &node, const Pattern *pattern = nullptr) {
    if (node.kind == Kind::ConditionChain) {
      for (const auto &clause : node.children) {
        auto value = condition(*clause);
        if (!value || !truth(*value))
          return value;
      }
      return boolValue(true);
    }
    if (node.kind == Kind::Condition)
      return condition(*node.children[0],
                       node.patterns.empty() ? nullptr : &node.patterns[0]);
    if (pattern) {
      auto subject = eval(node, nullptr);
      if (!subject)
        return std::nullopt;
      std::vector<Local> binds;
      auto matched = matches(*pattern, *subject, binds, false);
      if (!matched)
        return std::nullopt;
      if (*matched)
        for (auto &bound : binds)
          frame().locals.push_back(std::move(bound));
      return boolValue(*matched);
    }
    auto boolean = scalarShape(Type::Bool);
    auto value = eval(node, &boolean);
    if (!value)
      return std::nullopt;
    if (value->kind != Value::Kind::Bool)
      return fail("type", node.span,
                  "condition must be bool, found " + describe(*value));
    return value;
  }

  Opt loopExpression(const Node &node) {
    Value result = unitValue();
    while (true) {
      Scope scope(frame());
      if (node.kind == Kind::While) {
        auto value =
            condition(*node.children[0],
                      node.patterns.empty() ? nullptr : &node.patterns[0]);
        if (!value)
          return std::nullopt;
        if (!truth(*value))
          break;
      }
      auto body = eval(*node.children.back(), nullptr);
      if (!body) {
        bool escaped = false;
        auto leave = loopControl(node, escaped);
        if (escaped)
          return std::nullopt;
        if (leave) {
          result = std::move(signalValue);
          signal = Signal::None;
          signalLabel.clear();
          break;
        }
        signalLabel.clear();
      }
    }
    return result;
  }

  Opt forExpression(const Node &node) {
    const Node &iterable = *node.children[0];
    std::vector<Value> items;
    if (iterable.kind == Kind::Range && iterable.name.empty()) {
      auto low = eval(*iterable.children[0], nullptr);
      if (!low)
        return std::nullopt;
      auto hint = shapeOfValue(*low);
      auto high = eval(*iterable.children[1], &hint);
      if (!high || !unify(*low, *high, iterable.span))
        return std::nullopt;
      if (low->kind != Value::Kind::Integer && low->kind != Value::Kind::Char)
        return fail("type", iterable.span, "a range needs integer bounds");
      if (low->type == Type::Unknown &&
          (!coerce(*low, scalarShape(Type::I32), iterable.span) ||
           !coerce(*high, scalarShape(Type::I32), iterable.span)))
        return std::nullopt;
      auto current = *low;
      auto bound = iterable.text == "..=" ? 1 : 0;
      auto kernel = low->kind == Value::Kind::Char ? Type::U32 : low->type;
      while (compareIntegers(current.number, high->number) < bound) {
        if (!step(iterable.span))
          return std::nullopt;
        items.push_back(current);
        current.number =
            evaluateIntegerConstant("+", kernel, current.number,
                                    integerLiteral(1), options.pointerBits);
      }
    } else if (iterable.kind == Kind::Range) {
      return unsupported(iterable.span, "an unbounded range");
    } else {
      auto array = eval(iterable, nullptr);
      if (!array)
        return std::nullopt;
      if (array->kind != Value::Kind::Array)
        return unsupported(iterable.span, "iteration over " + describe(*array));
      items = std::move(array->elements);
    }
    for (auto &item : items) {
      Scope scope(frame());
      std::vector<Local> binds;
      if (!defaultTypes(item, node.span))
        return std::nullopt;
      auto matched = matches(node.patterns[0], item, binds, false);
      if (!matched)
        return std::nullopt;
      if (!*matched)
        return fail("constant", node.span, "refutable pattern in for loop");
      for (auto &bound : binds)
        frame().locals.push_back(std::move(bound));
      auto body = eval(*node.children[1], nullptr);
      if (!body) {
        bool escaped = false;
        auto leave = loopControl(node, escaped);
        if (escaped)
          return std::nullopt;
        signalLabel.clear();
        if (leave) {
          signal = Signal::None;
          break;
        }
      }
    }
    return unitValue();
  }

  Opt matchExpression(const Node &node, const Shape *want) {
    auto subject = eval(*node.children[0], nullptr);
    if (!subject)
      return std::nullopt;
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      const Node &arm = *node.children[i];
      Scope scope(frame());
      std::vector<Local> binds;
      auto matched = matches(arm.patterns[0], *subject, binds, false);
      if (!matched)
        return std::nullopt;
      if (!*matched)
        continue;
      for (auto &bound : binds)
        frame().locals.push_back(std::move(bound));
      if (arm.flag) {
        auto boolean = scalarShape(Type::Bool);
        auto guard = eval(*arm.children[0], &boolean);
        if (!guard)
          return std::nullopt;
        if (guard->kind != Value::Kind::Bool)
          return fail("type", arm.children[0]->span,
                      "match guard must be bool, found " + describe(*guard));
        if (!truth(*guard))
          continue;
      }
      return eval(*arm.children.back(), want);
    }
    return fail("constant", node.span,
                "no match arm matched the value in constant evaluation");
  }

  Opt call(const Node &node, const Shape *) {
    const Node &callee = *node.children[0];
    if (!callee.genericArguments.empty() ||
        !callee.ownerGenericArguments.empty() || callee.flag)
      return unsupported(callee.span, "this call");
    Lookup found;
    std::optional<Value> receiver;
    Type owner = Type::Unknown;
    std::string method;
    if (callee.kind == Kind::Field) {
      method = callee.text;
      owner = namedType(*callee.children[0]);
      if (!isFloating(owner)) {
        receiver = eval(*callee.children[0], nullptr);
        if (!receiver || !defaultTypes(*receiver, callee.span))
          return std::nullopt;
        if (receiver->kind != Value::Kind::Floating)
          return unsupported(callee.span, "this constant receiver");
        owner = receiver->type;
        found = host.method(owner, node);
      }
    } else if (callee.kind == Kind::Name) {
      auto separator = callee.text.rfind("::");
      if (separator != std::string::npos) {
        TypeSyntax syntax;
        syntax.name = callee.text.substr(0, separator);
        owner = host.resolveType(syntax, callee.span);
        method = callee.text.substr(separator + 2);
      }
      if (!isFloating(owner))
        found = host.lookup(callee);
    } else
      return unsupported(callee.span, "this call");
    if (isFloating(owner) && found.kind == Lookup::Kind::Missing) {
      if (!constantFloatMethod(method))
        return fail("constant", callee.span,
                    "call to non-const or unavailable float method '" + method +
                        "'");
      return primitiveCall(node, owner, method, receiver);
    }
    if (found.kind == Lookup::Kind::Symbolic) {
      symbolic = true;
      failed = true;
      return std::nullopt;
    }
    if (found.kind == Lookup::Kind::Failed) {
      failed = reported = true;
      return std::nullopt;
    }
    if (found.kind != Lookup::Kind::Function || !found.function)
      return fail("name", callee.span,
                  "unknown function '" + displayPath(callee.text) +
                      "' in a constant expression");
    const Function &function = *found.function;
    if (function.unsafeFunction && !unsafeDepth)
      return fail("unsafe", node.span,
                  "operation requires an unsafe block or unsafe function");
    if (!function.constFunction)
      return fail("constant", node.span,
                  "call to non-const function '" + displayPath(callee.text) +
                      "' in a constant expression");
    if (!function.genericParameters.empty() || function.constructor ||
        (!function.owner.empty() && !receiver) || function.variadic ||
        function.explicitReceiver || !function.body.get() ||
        function.destructor || !function.error.empty() ||
        function.foreignDeclaration)
      return unsupported(callee.span,
                         "calling '" + displayPath(callee.text) +
                             "' (generic, method, variadic or fallible "
                             "const functions)");
    if (frames.size() > options.callDepth)
      return fail("limit", node.span,
                  "const function call depth exceeded the limit of " +
                      std::to_string(options.callDepth) +
                      " (recursion without a base case?)");
    std::vector<std::optional<Shape>> parameterShapes;
    for (const auto &parameter : function.parameters) {
      if (parameter.mode == "mut" ||
          (parameter.pattern.has_value() &&
           parameter.pattern->kind != PatternKind::Binding))
        return unsupported(callee.span, "this parameter of '" +
                                            displayPath(callee.text) + "'");
      auto parameterShape = shape(parameter.annotation, parameter.span);
      if (!parameterShape)
        return std::nullopt;
      parameterShapes.push_back(std::move(parameterShape));
    }
    Shape result;
    result.kind = Shape::Kind::Unit;
    if (!function.annotation.empty()) {
      auto resultShape = shape(function.annotation, function.span);
      if (!resultShape)
        return std::nullopt;
      result = std::move(*resultShape);
    }
    std::vector<Opt> arguments(function.parameters.size());
    std::size_t position = receiver ? 1 : 0;
    if (receiver) {
      if (arguments.empty() ||
          !coerce(*receiver, *parameterShapes[0], node.span))
        return std::nullopt;
      arguments[0] = std::move(*receiver);
    }
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      const Node &argument = *node.children[i];
      std::size_t slot = position;
      if (!argument.name.empty()) {
        auto named =
            std::find_if(function.parameters.begin(), function.parameters.end(),
                         [&](const Parameter &parameter) {
                           return parameter.name == argument.name;
                         });
        if (named == function.parameters.end())
          return fail("type", argument.span,
                      "'" + displayPath(callee.text) + "' has no parameter '" +
                          argument.name + "'");
        slot = static_cast<std::size_t>(named - function.parameters.begin());
      } else
        ++position;
      if (slot >= arguments.size() || arguments[slot])
        return fail("type", argument.span,
                    "wrong arguments for '" + displayPath(callee.text) + "'");
      auto value = eval(argument, &*parameterShapes[slot]);
      if (!value || !coerce(*value, *parameterShapes[slot], argument.span))
        return std::nullopt;
      arguments[slot] = std::move(value);
    }
    for (std::size_t i = 0; i < arguments.size(); ++i)
      if (!arguments[i])
        return fail("type", node.span,
                    "missing argument '" + function.parameters[i].name +
                        "' in call to '" + displayPath(callee.text) + "'");
    frames.emplace_back();
    auto callerUnsafeDepth = unsafeDepth;
    unsafeDepth = function.unsafeFunction ? 1 : 0;
    frame().inFunction = true;
    frame().result = result;
    for (std::size_t i = 0; i < arguments.size(); ++i)
      frame().locals.push_back(
          {function.parameters[i].name, std::move(*arguments[i]), false});
    auto value = eval(*function.body, &result);
    unsafeDepth = callerUnsafeDepth;
    if (!value && !failed && signal == Signal::Return) {
      value = std::move(signalValue);
      signal = Signal::None;
    }
    frames.pop_back();
    if (!value)
      return std::nullopt;
    if (!coerce(*value, result, node.span))
      return std::nullopt;
    return value;
  }

  Opt eval(const Node &node, const Shape *want) {
    if (failed)
      return std::nullopt;
    if (!step(node.span))
      return std::nullopt;
    switch (node.kind) {
    case Kind::Integer:
    case Kind::Floating:
      return literal(node, false, want);
    case Kind::Boolean:
      return boolValue(node.text == "true");
    case Kind::Character: {
      Diagnostics scratch;
      auto code = characterLiteral(node.text, node.flag, scratch, node.span);
      if (!code)
        return fail("lex", node.span, "malformed character literal");
      return node.flag ? integerValue(Type::U8, integerLiteral(*code))
                       : charValue(*code);
    }
    case Kind::Unit:
      return unitValue();
    case Kind::Group:
      return eval(*node.children[0], want);
    case Kind::Unsafe: {
      ++unsafeDepth;
      auto value = eval(*node.children[0], want);
      --unsafeDepth;
      return value;
    }
    case Kind::Name: {
      auto &locals = frame().locals;
      for (auto it = locals.rbegin(); it != locals.rend(); ++it)
        if (it->name == node.text) {
          if (want && want->kind == Shape::Kind::Scalar &&
              it->value.kind == Value::Kind::Integer &&
              it->value.type == Type::Unknown &&
              !coerce(it->value, *want, node.span))
            return std::nullopt;
          return it->value;
        }
      auto found = host.lookup(node);
      switch (found.kind) {
      case Lookup::Kind::Constant: {
        if (want && want->kind == Shape::Kind::Scalar &&
            found.value.kind == Value::Kind::Integer &&
            found.value.type == Type::Unknown &&
            !coerce(found.value, *want, node.span))
          return std::nullopt;
        return std::move(found.value);
      }
      case Lookup::Kind::Symbolic:
        symbolic = true;
        failed = true;
        return std::nullopt;
      case Lookup::Kind::Failed:
        failed = reported = true;
        return std::nullopt;
      case Lookup::Kind::Function:
        return unsupported(node.span, "a function used as a value");
      default:
        return fail("name", node.span,
                    "unknown name '" + displayPath(node.text) +
                        "' in a constant expression");
      }
    }
    case Kind::Unary: {
      if (node.text == "-" && (node.children[0]->kind == Kind::Integer ||
                               node.children[0]->kind == Kind::Floating))
        return literal(*node.children[0], true, want);
      if (node.text != "-" && node.text != "!")
        return unsupported(node.span, "operator '" + node.text + "'");
      auto operand = eval(*node.children[0], want);
      if (!operand)
        return std::nullopt;
      if (node.text == "!" && operand->kind == Value::Kind::Bool)
        return boolValue(!truth(*operand));
      if (node.text == "-" && operand->kind == Value::Kind::Floating) {
        if (!defaultTypes(*operand, node.span))
          return std::nullopt;
        return numericOperation("neg", operand->type, {*operand}, node.span);
      }
      if (operand->kind != Value::Kind::Integer)
        return fail("type", node.span,
                    "operator '" + node.text + "' does not apply to " +
                        describe(*operand));
      if (node.text == "-")
        return integerOperation("-", operand->type,
                                integerValue(Type::Unknown, {}), *operand,
                                node.span);
      if (operand->type == Type::Unknown &&
          !coerce(*operand, scalarShape(Type::I32), node.span))
        return std::nullopt;
      auto mask = isSignedInteger(operand->type)
                      ? integerLiteral(-1)
                      : integerMaximum(operand->type, options.pointerBits);
      return integerOperation("^", operand->type, *operand,
                              integerValue(operand->type, mask), node.span);
    }
    case Kind::Binary: {
      const auto &op = node.text;
      if (op == "&&" || op == "||") {
        auto boolean = scalarShape(Type::Bool);
        auto left = eval(*node.children[0], &boolean);
        if (!left)
          return std::nullopt;
        if (left->kind != Value::Kind::Bool)
          return fail("type", node.children[0]->span,
                      "operand of '" + op + "' must be bool, found " +
                          describe(*left));
        if (truth(*left) == (op == "||"))
          return left;
        auto right = eval(*node.children[1], &boolean);
        if (!right)
          return std::nullopt;
        if (right->kind != Value::Kind::Bool)
          return fail("type", node.children[1]->span,
                      "operand of '" + op + "' must be bool, found " +
                          describe(*right));
        return right;
      }
      bool comparison = op == "==" || op == "!=" || op == "<" || op == "<=" ||
                        op == ">" || op == ">=";
      bool shift = op == "<<" || op == ">>";
      auto left = eval(*node.children[0], comparison ? nullptr : want);
      if (!left)
        return std::nullopt;
      Shape hint = shapeOfValue(*left);
      const Shape *rightWant =
          shift ? nullptr
                : (complete(hint) ? &hint : (comparison ? nullptr : want));
      auto right = eval(*node.children[1], rightWant);
      if (!right)
        return std::nullopt;
      return binary(op, std::move(*left), std::move(*right), node.span);
    }
    case Kind::Cast: {
      auto operand = eval(*node.children[0], nullptr);
      if (!operand)
        return std::nullopt;
      return cast(node, std::move(*operand));
    }
    case Kind::Block:
      return block(node, want);
    case Kind::If: {
      Scope scope(frame());
      auto mark = frame().locals.size();
      auto value =
          condition(*node.children[0],
                    node.patterns.empty() ? nullptr : &node.patterns[0]);
      if (!value)
        return std::nullopt;
      if (truth(*value))
        return eval(*node.children[1], want);
      frame().locals.resize(mark);
      if (node.children.size() > 2)
        return eval(*node.children[2], want);
      return unitValue();
    }
    case Kind::Condition:
    case Kind::ConditionChain:
      return condition(node);
    case Kind::Match:
      return matchExpression(node, want);
    case Kind::Binding:
      return binding(node);
    case Kind::Assign:
      return assign(node);
    case Kind::While:
    case Kind::Loop:
      return loopExpression(node);
    case Kind::For:
      return forExpression(node);
    case Kind::Break:
    case Kind::Continue:
    case Kind::Return: {
      Value carried = unitValue();
      if (!node.children.empty()) {
        const Shape *carriedWant =
            node.kind == Kind::Return && frame().inFunction ? &frame().result
                                                            : nullptr;
        auto value = eval(*node.children[0], carriedWant);
        if (!value)
          return std::nullopt;
        carried = std::move(*value);
      }
      if (node.kind == Kind::Return && !frame().inFunction)
        return fail("constant", node.span, "'return' outside a const function");
      signal = node.kind == Kind::Break      ? Signal::Break
               : node.kind == Kind::Continue ? Signal::Continue
                                             : Signal::Return;
      signalLabel = node.kind == Kind::Return ? std::string() : node.label;
      signalValue = std::move(carried);
      return std::nullopt;
    }
    case Kind::Tuple: {
      Value result;
      result.kind = Value::Kind::Tuple;
      result.type = Type::Unknown;
      for (std::size_t i = 0; i < node.children.size(); ++i) {
        const Shape *inner = want && want->kind == Shape::Kind::Tuple &&
                                     i < want->elements.size()
                                 ? &want->elements[i]
                                 : nullptr;
        auto value = eval(*node.children[i], inner);
        if (!value)
          return std::nullopt;
        result.elements.push_back(std::move(*value));
      }
      return result;
    }
    case Kind::Array:
      return array(node, want);
    case Kind::Field: {
      auto type = namedType(*node.children[0]);
      if (host.enumeration(type)) {
        auto found = host.variant(type, node.text, node.span);
        if (found.kind == Lookup::Kind::Constant)
          return std::move(found.value);
        if (found.kind == Lookup::Kind::Failed) {
          failed = reported = true;
          return std::nullopt;
        }
        return fail("name", node.span, "unknown constant enum variant");
      }
      if (isFloating(type)) {
        auto found = host.floatingValue(type, node.text, node.span);
        if (found.kind == Lookup::Kind::Constant)
          return std::move(found.value);
        if (found.kind == Lookup::Kind::Failed) {
          failed = reported = true;
          return std::nullopt;
        }
        return fail("name", node.span, "unknown floating associated constant");
      }
      auto where = place(node);
      if (failed)
        return std::nullopt;
      if (where.value)
        return *where.value;
      auto base = eval(*node.children[0], nullptr);
      if (!base)
        return std::nullopt;
      if (base->kind != Value::Kind::Tuple || node.text.empty() ||
          !std::all_of(node.text.begin(), node.text.end(),
                       [](char c) { return c >= '0' && c <= '9'; }) ||
          node.text.size() > 9 ||
          std::stoull(node.text) >= base->elements.size())
        return fail("type", node.span,
                    "no field '" + node.text + "' on " + describe(*base));
      return base->elements[std::stoull(node.text)];
    }
    case Kind::Index: {
      auto where = place(node);
      if (failed)
        return std::nullopt;
      if (where.value)
        return *where.value;
      auto base = eval(*node.children[0], nullptr);
      if (!base)
        return std::nullopt;
      if (base->kind != Value::Kind::Array)
        return fail("type", node.span,
                    "cannot index " + describe(*base) + " in a constant");
      auto usize = scalarShape(Type::Usize);
      auto index = eval(*node.children[1], &usize);
      if (!index)
        return std::nullopt;
      if (index->kind != Value::Kind::Integer ||
          (index->type != Type::Unknown && index->type != Type::Usize))
        return fail("type", node.children[1]->span,
                    "array index must be usize, found " + describe(*index));
      if (index->number.negative || index->number.magnitude[1] ||
          index->number.magnitude[0] >= base->elements.size())
        return fail("constant", node.span,
                    "index out of bounds in constant expression: the length "
                    "is " +
                        std::to_string(base->elements.size()) +
                        " but the index is " +
                        integerLiteralName(index->number));
      return base->elements[index->number.magnitude[0]];
    }
    case Kind::Call:
      return call(node, want);
    default:
      return unsupported(node.span, "this expression");
    }
  }

  Opt array(const Node &node, const Shape *want) {
    Value result;
    result.kind = Value::Kind::Array;
    result.type = Type::Unknown;
    const Shape *element = want && want->kind == Shape::Kind::Array
                               ? &want->elements.front()
                               : nullptr;
    if (node.flag) {
      auto first = eval(*node.children[0], element);
      if (!first)
        return std::nullopt;
      auto count = length(*node.children[1]);
      if (!count)
        return std::nullopt;
      steps += *count;
      if (steps > options.stepBudget)
        return fail("limit", node.span,
                    "constant evaluation exceeded the step budget of " +
                        std::to_string(options.stepBudget) + " steps");
      result.elements.assign(static_cast<std::size_t>(*count), *first);
      return result;
    }
    std::optional<Shape> agreed;
    for (const auto &child : node.children) {
      auto value =
          eval(*child, element ? element : (agreed ? &*agreed : nullptr));
      if (!value)
        return std::nullopt;
      if (!agreed) {
        auto candidate = shapeOfValue(*value);
        if (complete(candidate))
          agreed = std::move(candidate);
      }
      result.elements.push_back(std::move(*value));
    }
    if (agreed && !element)
      for (auto &value : result.elements)
        if (!coerce(value, *agreed, node.span))
          return std::nullopt;
    return result;
  }
};
} // namespace

NumericLiteral castInteger(const NumericLiteral &value, Type target,
                           unsigned pointerBits) {
  return evaluateIntegerConstant("|", target, value, integerLiteral(0),
                                 pointerBits);
}

namespace {
// Interpretation recurses natively per nested expression and call, so it runs
// on a stack sized for the call-depth limit rather than the caller's.
struct Job {
  Host &host;
  const Options &options;
  const Node &node;
  const Expectation &expected;
  Result result{};
  std::exception_ptr failure{};
};
void *runJob(void *argument) {
  auto &job = *static_cast<Job *>(argument);
  try {
    job.result = Interpreter(job.host, job.options).run(job.node, job.expected);
  } catch (...) {
    job.failure = std::current_exception();
  }
  return nullptr;
}
} // namespace

Result evaluate(Host &host, const Options &options, const Node &node,
                const Expectation &expected) {
  Job job{host, options, node, expected};
  constexpr std::size_t stackBytes = std::size_t{1} << 30;
  pthread_attr_t attributes;
  pthread_t thread;
  bool started = pthread_attr_init(&attributes) == 0;
  if (started) {
    started = pthread_attr_setstacksize(&attributes, stackBytes) == 0 &&
              pthread_create(&thread, &attributes, runJob, &job) == 0;
    pthread_attr_destroy(&attributes);
  }
  if (!started)
    runJob(&job);
  else
    pthread_join(thread, nullptr);
  if (job.failure)
    std::rethrow_exception(job.failure);
  return std::move(job.result);
}
} // namespace mettle::evaluation
