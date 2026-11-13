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
  shape.type = value.type;
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
  case Value::Kind::Product:
    shape.kind = Shape::Kind::Product;
    for (const auto &element : value.elements)
      shape.elements.push_back(shapeOfValue(element));
    break;
  case Value::Kind::Variant:
    shape.kind = Shape::Kind::Variant;
    break;
  case Value::Kind::Reference:
    shape.kind = Shape::Kind::Reference;
    shape.exclusive = value.exclusive;
    break;
  case Value::Kind::Pointer:
    shape.kind = Shape::Kind::Pointer;
    shape.exclusive = value.exclusive;
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
  case Value::Kind::Product:
    return "a product";
  case Value::Kind::Variant:
    return "a variant";
  case Value::Kind::Reference:
    return "a constant view";
  case Value::Kind::Pointer:
    return "a constant pointer";
  case Value::Kind::Function:
    return "a function address";
  case Value::Kind::Uninitialized:
    return "an uninitialized value";
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
  case Shape::Kind::Product:
    return "a product";
  case Shape::Kind::Variant:
    return "a variant";
  case Shape::Kind::Reference:
    return "a constant view";
  case Shape::Kind::Pointer:
    return "a constant pointer";
  }
  return "value";
}

struct Local {
  std::string name;
  std::shared_ptr<Value> value;
  bool mutableBinding = false;
  SyntaxContextPtr context{};
  Local(std::string name, Value value, bool mutableBinding,
        SyntaxContextPtr context)
      : name(std::move(name)), value(std::make_shared<Value>(std::move(value))),
        mutableBinding(mutableBinding), context(std::move(context)) {}
};
bool namesLocal(const Local &local, const Node &name) {
  auto binding = local.context ? local.context->identity : 0;
  auto reference = name.context ? name.context->identity : 0;
  return local.name == name.text && binding == reference;
}
struct Frame {
  std::deque<Local> locals;
  Shape result;
  bool inFunction = false;
  Span callSpan{};
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
    primitiveTypes.setPointerBits(this->options.pointerBits);
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
    if (value && !exportable(*value, node.span))
      value.reset();
    if (!value && !failed)
      fail("constant", node.span,
           signal == Signal::Throw
               ? "uncaught typed error in a constant expression"
               : "'break', 'continue' or 'return' outside a loop or const "
                 "function");
    result.value = std::move(value);
    return finish(result);
  }

private:
  using Opt = std::optional<Value>;
  enum class Signal { None, Break, Continue, Return, Throw };
  struct Fault {
    std::string phase;
    Span span;
    std::string message;
  };
  struct Scope {
    explicit Scope(Interpreter &interpreter, Span span)
        : interpreter(interpreter), frame(interpreter.frame()),
          mark(frame.locals.size()), span(span) {}
    ~Scope() {
      while (frame.locals.size() > mark) {
        interpreter.discard(*frame.locals.back().value, span);
        frame.locals.pop_back();
      }
    }
    Scope(const Scope &) = delete;
    Scope &operator=(const Scope &) = delete;
    Interpreter &interpreter;
    Frame &frame;
    std::size_t mark;
    Span span;
  };

  Host &host;
  Options options;
  TypeStore primitiveTypes;
  std::deque<Frame> frames;
  std::map<int, std::shared_ptr<Value>> staticRoots;
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
  // Runs a value's destructor and then drops its fields in declaration order,
  // as at runtime. A type whose destructor cannot be evaluated stays an error.
  void discard(Value &value, Span span) {
    if (failed || value.kind == Value::Kind::Uninitialized ||
        value.kind == Value::Kind::Reference)
      return;
    auto type = host.valueType(value);
    if (!host.needsDrop(type))
      return;
    auto found = host.destructor(type, span);
    const bool aggregate = value.kind == Value::Kind::Product ||
                           value.kind == Value::Kind::Tuple ||
                           value.kind == Value::Kind::Array ||
                           value.kind == Value::Kind::Variant;
    if (found.kind == Lookup::Kind::Function && found.checkedFunction) {
      runDestructor(value, type, *found.checkedFunction, span);
      if (failed)
        return;
    } else if (found.kind != Lookup::Kind::Missing || !aggregate) {
      fail("constant", span,
           "destruction is not permitted during constant evaluation");
      return;
    }
    for (auto &element : value.elements)
      discard(element, span);
    value.kind = Value::Kind::Uninitialized;
  }
  void runDestructor(Value &value, Type type, const CheckedFunction &function,
                     Span span) {
    if (frames.size() > options.callDepth) {
      fail("limit", span,
           "const function call depth exceeded the limit of " +
               std::to_string(options.callDepth));
      return;
    }
    auto storage = std::make_shared<Value>(std::move(value));
    Value self;
    self.kind = Value::Kind::Reference;
    self.type = host.referenceType(type, true, false);
    self.storage = storage;
    self.storageType = type;
    self.count = storage->elements.size();
    self.exclusive = true;
    self.writable = true;
    const auto parameterContext = function.parameters.front().context;
    // The destructor may run while a `return` or `break` is unwinding.
    auto savedSignal = signal;
    auto savedLabel = std::move(signalLabel);
    auto savedValue = std::move(signalValue);
    signal = Signal::None;
    frames.emplace_back();
    host.enter(function);
    {
      struct Restore {
        Interpreter &interpreter;
        unsigned unsafeDepth;
        Span span;
        ~Restore() {
          for (const auto &local : interpreter.frame().locals)
            interpreter.discard(*local.value, span);
          interpreter.unsafeDepth = unsafeDepth;
          interpreter.host.leave();
          interpreter.frames.pop_back();
        }
      } restore{*this, unsafeDepth, span};
      unsafeDepth = 0;
      frame().inFunction = true;
      frame().callSpan = span;
      frame().result = function.result;
      frame().locals.emplace_back("self", std::move(self), false,
                                  parameterContext);
      eval(*function.body, &function.result);
      if (signal == Signal::Return)
        signal = Signal::None;
    }
    signal = savedSignal;
    signalLabel = std::move(savedLabel);
    signalValue = std::move(savedValue);
    value = std::move(*storage);
  }

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
      if (namesLocal(local, node))
        return Type::Unknown;
    TypeSyntax syntax;
    syntax.name = node.text;
    syntax.context = node.context;
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

  Opt integerCall(const Node &node, Type owner, std::vector<Value> values,
                  const Shape *want) {
    const auto &callee = *node.children[0];
    auto name = std::string_view(callee.text);
    if (auto separator = name.rfind("::"); separator != std::string_view::npos)
      name.remove_prefix(separator + 2);
    const auto width = integerWidth(owner, options.pointerBits);
    const auto byteCount = width / 8;
    const bool fromBytes = name == "from_be_bytes" || name == "from_le_bytes" ||
                           name == "from_ne_bytes";
    const bool toBytes =
        name == "to_be_bytes" || name == "to_le_bytes" || name == "to_ne_bytes";
    const bool mutates =
        name == "make_ascii_lowercase" || name == "make_ascii_uppercase";
    std::vector<Type> operands;
    std::vector<NumericLiteral> numbers;
    for (std::size_t i = 0; i < values.size(); ++i) {
      auto &value = values[i];
      if (value.kind == Value::Kind::Reference) {
        auto target = pointee(value);
        if (target && (isInteger(target->type) || target->type == Type::Bool ||
                       (fromBytes && target->kind == Shape::Kind::Array)))
          if (!coerce(value, *target, callee.span))
            return std::nullopt;
      }
      if (fromBytes && value.kind == Value::Kind::Array) {
        auto element = scalarShape(Type::U8);
        for (auto &byte : value.elements)
          if (!coerce(byte, element, callee.span))
            return std::nullopt;
        operands.push_back(primitiveTypes.arrayType(
            Type::U8, primitiveTypes.constant(
                          Type::Usize, integerLiteral(value.elements.size()))));
      } else {
        auto type = value.type;
        if (value.kind == Value::Kind::Integer && type == Type::Unknown) {
          type = owner;
          if (i == 1 && (name.ends_with("pow") || name.ends_with("shl") ||
                         name.ends_with("shr") || name == "rotate_left" ||
                         name == "rotate_right"))
            type = Type::U32;
          else if (i == 1 &&
                   (name.ends_with("_signed") || name.ends_with("_unsigned")) &&
                   name != "cast_signed" && name != "cast_unsigned") {
            auto spelling = std::string(typeName(owner));
            spelling[0] = isSignedInteger(owner) ? 'u' : 'i';
            type = builtinType(spelling);
          }
        }
        operands.push_back(
            isNumeric(type) || type == Type::Bool ? type : Type::Unknown);
      }
      numbers.push_back(value.number);
    }
    Type argument = owner;
    if (toBytes)
      argument = primitiveTypes.arrayType(
          Type::U8,
          primitiveTypes.constant(Type::Usize, integerLiteral(byteCount)));
    if (mutates && !operands.empty())
      operands[0] = primitiveTypes.viewType(owner, ParameterMode::Mut);
    auto signature = machineSignature(
        primitiveTypes, "numeric." + std::string(name), operands, argument);
    if (!signature) {
      if (!fromBytes && !toBytes) {
        try {
          if (!evaluateIntegerMethod(name, owner, numbers, options.pointerBits,
                                     options.littleEndian))
            return std::nullopt;
        } catch (const std::invalid_argument &error) {
          return fail("type", callee.span, error.what());
        }
      }
      return fail("type", callee.span,
                  "invalid arguments to integer method '" + std::string(name) +
                      "'");
    }
    if (!callee.genericArguments.empty() ||
        !callee.ownerGenericArguments.empty())
      return fail("type", callee.span,
                  "unexpected integer method type arguments");
    if (signature->unsafeCall && !unsafeDepth)
      return fail("constant", callee.span,
                  "unsafe integer method requires an unsafe context");
    for (std::size_t i = 0; i < values.size(); ++i)
      if (values[i].kind != Value::Kind::Array) {
        auto target = scalarShape(mutates && i == 0 ? owner : operands[i]);
        if (!coerce(values[i], target, callee.span))
          return std::nullopt;
        numbers[i] = values[i].number;
      }
    const bool little =
        name.starts_with("from_le") || name.starts_with("to_le") ||
        ((name.starts_with("from_ne") || name.starts_with("to_ne")) &&
         options.littleEndian);
    if (fromBytes) {
      NumericLiteral bits;
      for (std::size_t i = 0; i < byteCount; ++i) {
        auto position = little ? i : byteCount - i - 1;
        bits.magnitude[position / 8] |=
            values.front().elements[i].number.magnitude[0]
            << ((position % 8) * 8);
      }
      return integerValue(owner, castInteger(bits, owner, options.pointerBits));
    }
    if (toBytes) {
      auto bits = castInteger(numbers.front(), Type::U128, options.pointerBits);
      Value bytes;
      bytes.kind = Value::Kind::Array;
      if (want && want->kind == Shape::Kind::Array)
        bytes.type = want->type;
      for (std::size_t i = 0; i < byteCount; ++i) {
        auto position = little ? i : byteCount - i - 1;
        auto byte =
            (bits.magnitude[position / 8] >> ((position % 8) * 8)) & 255;
        bytes.elements.push_back(integerValue(Type::U8, integerLiteral(byte)));
      }
      return bytes;
    }
    auto operation = mutates ? name == "make_ascii_lowercase"
                                   ? "to_ascii_lowercase"
                                   : "to_ascii_uppercase"
                             : name;
    std::optional<IntegerMethodResult> calculated;
    try {
      calculated = evaluateIntegerMethod(
          operation, owner, numbers, options.pointerBits, options.littleEndian);
    } catch (const std::invalid_argument &error) {
      return fail("constant", callee.span, error.what());
    }
    if (!calculated)
      return unsupported(callee.span,
                         "integer method '" + std::string(name) + "'");
    auto value = calculated->type == Type::Bool
                     ? boolValue(calculated->value.magnitude[0] != 0)
                     : integerValue(calculated->type, calculated->value);
    if (mutates)
      return value;
    if (calculated->type != signature->value)
      return fail("internal", callee.span,
                  "integer constant method result type does not match");
    if (signature->shape == MachineSignature::Shape::Optional) {
      Value optional;
      optional.kind = Value::Kind::Variant;
      optional.type = want ? want->type : Type::Unknown;
      optional.selection = calculated->failed ? 0 : 1;
      if (!calculated->failed)
        optional.elements.push_back(std::move(value));
      return optional;
    }
    if (signature->shape == MachineSignature::Shape::Overflow) {
      Value pair;
      pair.kind = Value::Kind::Tuple;
      pair.type = want ? want->type : Type::Unknown;
      pair.elements = {std::move(value), boolValue(calculated->failed)};
      return pair;
    }
    if (signature->shape != MachineSignature::Shape::Value)
      return unsupported(callee.span, "this integer method result shape");
    return value;
  }

  // Type structure of a declared type.
  std::optional<Shape> shape(const TypeSyntax &type, Span span) {
    if (auto resolved = host.resolveType(type, span); resolved != Type::Unknown)
      if (auto result = host.typeShape(resolved))
        return result;
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
    auto value = eval(node, nullptr);
    if (!value)
      return std::nullopt;
    if (value->kind != Value::Kind::Integer) {
      fail("type", node.span, "an array count must be an integer");
      return std::nullopt;
    }
    if (value->number.negative &&
        (value->number.magnitude[0] || value->number.magnitude[1])) {
      fail("constant", node.span, "an array count cannot be negative");
      return std::nullopt;
    }
    if (value->number.magnitude[1]) {
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

  Lookup lookup(const Node &node) {
    auto remaining = options.stepBudget - steps;
    auto result = host.lookup(node, remaining);
    steps = options.stepBudget - remaining;
    return result;
  }

  // Gives an unsuffixed integer its type or checks a typed value against the
  // declared one.
  bool coerce(Value &value, const Shape &want, Span span) {
    if (value.kind == Value::Kind::Uninitialized)
      return true;
    if (value.kind == Value::Kind::Reference &&
        want.kind != Shape::Kind::Reference) {
      auto loaded = readAddress(value, span);
      if (!loaded)
        return false;
      value = std::move(*loaded);
    }
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
      } else if (value.kind == Value::Kind::Function &&
                 host.callableCoercion(value.type, want.type)) {
        value.type = want.type;
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
        value.type = want.type;
        return true;
      }
      break;
    case Shape::Kind::Array:
      if (value.kind == Value::Kind::Array) {
        if (want.count != UINT64_MAX && value.elements.size() != want.count) {
          fail("type", span,
               "expected an array of " + std::to_string(want.count) +
                   " elements, found " + std::to_string(value.elements.size()));
          return false;
        }
        for (auto &element : value.elements)
          if (!coerce(element, want.elements.front(), span))
            return false;
        value.type = want.type;
        return true;
      }
      break;
    case Shape::Kind::Product:
      if (value.kind == Value::Kind::Product && value.type == want.type &&
          value.elements.size() == want.elements.size()) {
        for (std::size_t i = 0; i < value.elements.size(); ++i)
          if (!coerce(value.elements[i], want.elements[i], span))
            return false;
        return true;
      }
      break;
    case Shape::Kind::Variant:
      if (value.kind == Value::Kind::Variant &&
          (value.type == Type::Unknown || value.type == want.type)) {
        value.type = want.type;
        if (value.selection < 0 ||
            std::size_t(value.selection) >= want.variants.size())
          break;
        const auto &fields = want.variants[value.selection];
        if (fields.size() != value.elements.size())
          break;
        for (std::size_t i = 0; i < fields.size(); ++i)
          if (!coerce(value.elements[i], want.elements[fields[i]], span))
            return false;
        return true;
      }
      break;
    case Shape::Kind::Reference:
    case Shape::Kind::Pointer:
      if (value.kind == (want.kind == Shape::Kind::Reference
                             ? Value::Kind::Reference
                             : Value::Kind::Pointer) &&
          (!want.exclusive || value.exclusive)) {
        value.type = want.type;
        value.exclusive = want.exclusive;
        return value.kind == Value::Kind::Pointer ||
               validReference(value, span);
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
    if (left.kind == Value::Kind::Reference) {
      auto value = readAddress(left, span);
      if (!value)
        return std::nullopt;
      left = std::move(*value);
    }
    if (right.kind == Value::Kind::Reference) {
      auto value = readAddress(right, span);
      if (!value)
        return std::nullopt;
      right = std::move(*value);
    }
    if (left.kind == Value::Kind::Pointer &&
        right.kind == Value::Kind::Pointer && (op == "==" || op == "!=")) {
      if (!sameAllocation(left, right))
        return fail("constant", span,
                    "constant pointer comparison requires common provenance");
      auto layout = host.layout(left.type);
      auto equal = left.offset == right.offset &&
                   (!layout || layout->size <= options.pointerBits / 8 ||
                    left.count == right.count);
      return boolValue(op == "==" ? equal : !equal);
    }
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
      auto result = integerOperation(op, Type::Bool, left, right, span);
      return result ? Opt(boolValue(truth(*result))) : std::nullopt;
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
    if (target->kind == Shape::Kind::Pointer &&
        (value.kind == Value::Kind::Pointer ||
         value.kind == Value::Kind::Reference)) {
      if (!host.pointerCastAllowed(value.type, target->type))
        return fail("type", node.span, "invalid constant pointer cast");
      value.kind = Value::Kind::Pointer;
      value.type = target->type;
      value.exclusive = target->exclusive;
      return value;
    }
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
    if ((value.kind == Value::Kind::Bool || value.kind == Value::Kind::Char ||
         value.kind == Value::Kind::Enum) &&
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

  std::optional<Shape> pointee(const Value &address) {
    auto shape = host.typeShape(address.type);
    if (!shape || shape->elements.empty())
      return std::nullopt;
    auto result = shape->elements.front();
    if (auto expanded = host.typeShape(result.type))
      result = std::move(*expanded);
    return result;
  }
  Value *locate(Value &root, Type type, std::uint64_t offset, Type target) {
    if (offset == 0 && type == target)
      return &root;
    auto shape = host.typeShape(type);
    auto layout = host.layout(type);
    if (!shape || !layout)
      return nullptr;
    if (shape->kind == Shape::Kind::Array && !shape->elements.empty()) {
      auto element = host.layout(shape->elements.front().type);
      if (!element)
        return nullptr;
      auto index = element->size ? offset / element->size : 0;
      if (index >= root.elements.size())
        return nullptr;
      return locate(root.elements[index], shape->elements.front().type,
                    element->size ? offset % element->size : 0, target);
    }
    if (root.kind != Value::Kind::Product && root.kind != Value::Kind::Tuple &&
        root.kind != Value::Kind::Variant)
      return nullptr;
    for (std::size_t i = 0; i < root.elements.size(); ++i) {
      auto index = i;
      if (root.kind == Value::Kind::Variant) {
        if (root.selection < 0 ||
            std::size_t(root.selection) >= shape->variants.size() ||
            i >= shape->variants[root.selection].size())
          return nullptr;
        index = shape->variants[root.selection][i];
      }
      if (index >= layout->fields.size() || index >= shape->elements.size())
        return nullptr;
      auto field = host.layout(shape->elements[index].type);
      auto start = layout->fields[index];
      if (field && offset >= start && offset - start <= field->size)
        if (auto found = locate(root.elements[i], shape->elements[index].type,
                                offset - start, target))
          return found;
    }
    return nullptr;
  }
  std::shared_ptr<Value> rootOf(const Value &address) {
    if (auto root = address.storage.lock())
      return root;
    if (address.symbol < 0)
      return {};
    auto &root = staticRoots[address.symbol];
    if (!root) {
      auto remaining = options.stepBudget - steps;
      auto found = host.storage(address.symbol, remaining);
      steps = options.stepBudget - remaining;
      if (found.kind == Lookup::Kind::Failed)
        failed = reported = true;
      else if (found.kind == Lookup::Kind::Constant)
        root = std::make_shared<Value>(std::move(found.value));
    }
    return root;
  }
  bool addressBounds(const Value &address, Type type, std::uint64_t size,
                     Span span, bool aligned = true) {
    auto root = rootOf(address);
    auto backing = host.layout(address.storageType);
    auto target = host.layout(type);
    if (address.addressOnly && size == 0 && target && address.offset != 0 &&
        (!aligned || address.offset % target->alignment == 0))
      return true;
    if (!root || address.addressOnly || !backing || !target ||
        address.offset > backing->size ||
        size > backing->size - address.offset ||
        (aligned && (target->alignment > backing->alignment ||
                     address.offset % target->alignment)))
      return fail("constant", span,
                  "constant pointer is dangling, misaligned or out of bounds"),
             false;
    return true;
  }
  bool sameAllocation(const Value &left, const Value &right) {
    return left.addressOnly == right.addressOnly &&
           left.symbol == right.symbol &&
           !left.storage.owner_before(right.storage) &&
           !right.storage.owner_before(left.storage);
  }
  Value::Byte *storageByte(Value &value, Type type, std::uint64_t offset,
                           Span span) {
    if (!step(span))
      return nullptr;
    auto shape = host.typeShape(type);
    auto layout = host.layout(type);
    if (!shape || !layout || offset >= layout->size)
      return nullptr;
    if (shape->kind == Shape::Kind::Array && !shape->elements.empty()) {
      auto element = host.layout(shape->elements.front().type);
      if (!element || !element->size ||
          offset / element->size >= value.elements.size())
        return nullptr;
      return storageByte(value.elements[offset / element->size],
                         shape->elements.front().type, offset % element->size,
                         span);
    }
    if (shape->kind == Shape::Kind::Product ||
        shape->kind == Shape::Kind::Tuple) {
      for (std::size_t i = 0;
           i < shape->elements.size() && i < layout->fields.size() &&
           i < value.elements.size();
           ++i) {
        auto field = host.layout(shape->elements[i].type);
        if (field && offset >= layout->fields[i] &&
            offset - layout->fields[i] < field->size)
          return storageByte(value.elements[i], shape->elements[i].type,
                             offset - layout->fields[i], span);
      }
    } else if (isInteger(type) || isFloating(type) || type == Type::Bool ||
               type == Type::Char) {
      if (value.bytes.empty()) {
        value.bytes.resize(layout->size);
        if (value.kind != Value::Kind::Uninitialized) {
          auto bits = isInteger(type) ? castInteger(value.number, Type::U128,
                                                    options.pointerBits)
                                      : value.number;
          if (isFloating(type) && value.number.floatingBits) {
            bits = integerLiteral(0);
            bits.magnitude[0] = *value.number.floatingBits;
          }
          for (std::uint64_t i = 0; i < layout->size; ++i) {
            auto shift = options.littleEndian ? i : layout->size - i - 1;
            value.bytes[i].value = static_cast<std::uint8_t>(
                bits.magnitude[shift / 8] >> (shift % 8 * 8));
          }
        }
      }
      return &value.bytes[offset];
    } else if (value.bytes.empty()) {
      if (layout->size > options.stepBudget - steps) {
        fail("limit", span, "constant byte storage exceeds the step budget");
        return nullptr;
      }
      auto provenance = value.kind == Value::Kind::Uninitialized
                            ? std::shared_ptr<const Value>{}
                            : std::make_shared<const Value>(value);
      value.bytes.resize(layout->size);
      for (std::size_t i = 0; i < value.bytes.size(); ++i)
        value.bytes[i] = {{}, provenance, i};
    }
    if (value.bytes.empty()) {
      if (layout->size > options.stepBudget - steps) {
        fail("limit", span, "constant byte storage exceeds the step budget");
        return nullptr;
      }
      value.bytes.resize(layout->size);
    }
    return &value.bytes[offset];
  }
  void materializeBytes(Value &value, Type type, std::uint64_t start = 0,
                        std::uint64_t size = UINT64_MAX) {
    auto shape = host.typeShape(type);
    auto layout = host.layout(type);
    if (!shape || !layout || start > layout->size)
      return;
    size = std::min(size, layout->size - start);
    if (shape->kind == Shape::Kind::Array && !shape->elements.empty()) {
      auto element = host.layout(shape->elements.front().type);
      if (!element || !element->size || !size)
        return;
      auto first = start / element->size;
      auto last = (start + size - 1) / element->size;
      for (auto i = first; i <= last && i < value.elements.size(); ++i) {
        auto offset = i * element->size;
        auto begin = std::max(start, offset);
        auto end = std::min(start + size, offset + element->size);
        materializeBytes(value.elements[i], shape->elements.front().type,
                         begin - offset, end - begin);
      }
    } else if (shape->kind == Shape::Kind::Product ||
               shape->kind == Shape::Kind::Tuple) {
      for (std::size_t i = 0;
           i < shape->elements.size() && i < value.elements.size() &&
           i < layout->fields.size();
           ++i) {
        auto field = host.layout(shape->elements[i].type);
        auto offset = layout->fields[i];
        if (field && offset < start + size && start < offset + field->size) {
          auto begin = std::max(start, offset);
          auto end = std::min(start + size, offset + field->size);
          materializeBytes(value.elements[i], shape->elements[i].type,
                           begin - offset, end - begin);
        }
      }
    } else if (!value.bytes.empty()) {
      auto provenance = value.bytes.front().provenance;
      bool preserved =
          provenance && (((shape->kind == Shape::Kind::Pointer ||
                           shape->kind == Shape::Kind::Reference) &&
                          (provenance->kind == Value::Kind::Pointer ||
                           provenance->kind == Value::Kind::Reference)) ||
                         provenance->type == type);
      for (std::size_t i = 0; preserved && i < value.bytes.size(); ++i)
        preserved = value.bytes[i].provenance == provenance &&
                    value.bytes[i].index == i;
      if (preserved) {
        auto bytes = std::move(value.bytes);
        value = *provenance;
        value.type = type;
        value.bytes = std::move(bytes);
        if (shape->kind == Shape::Kind::Pointer ||
            shape->kind == Shape::Kind::Reference) {
          value.kind = shape->kind == Shape::Kind::Pointer
                           ? Value::Kind::Pointer
                           : Value::Kind::Reference;
          value.exclusive = shape->exclusive;
        }
        return;
      }
      if ((shape->kind == Shape::Kind::Pointer ||
           shape->kind == Shape::Kind::Reference) &&
          std::all_of(
              value.bytes.begin(), value.bytes.end(),
              [](const auto &byte) { return byte.value.has_value(); })) {
        auto wordSize = options.pointerBits / 8;
        auto word = [&](std::size_t offset) {
          std::uint64_t result = 0;
          for (std::size_t i = 0; i < wordSize; ++i) {
            auto shift = options.littleEndian ? i : wordSize - i - 1;
            result |= std::uint64_t{*value.bytes[offset + i].value}
                      << (8 * shift);
          }
          return result;
        };
        auto bytes = std::move(value.bytes);
        value = Value{};
        value.type = type;
        value.bytes = std::move(bytes);
        value.kind = shape->kind == Shape::Kind::Pointer
                         ? Value::Kind::Pointer
                         : Value::Kind::Reference;
        value.addressOnly = value.writable = true;
        value.exclusive = shape->exclusive;
        value.offset = word(0);
        if (value.bytes.size() > wordSize)
          value.count = word(wordSize);
        return;
      }
      if (!isInteger(type) && !isFloating(type) && type != Type::Bool &&
          type != Type::Char) {
        value.kind = Value::Kind::Uninitialized;
        return;
      }
      NumericLiteral bits;
      bool valid = true;
      for (std::size_t i = 0; i < value.bytes.size(); ++i) {
        if (!value.bytes[i].value) {
          valid = false;
          break;
        }
        auto shift = options.littleEndian ? i : value.bytes.size() - i - 1;
        bits.magnitude[shift / 8] |= std::uint64_t{*value.bytes[i].value}
                                     << (shift % 8 * 8);
      }
      value.kind = Value::Kind::Uninitialized;
      if (!valid)
        return;
      if (isInteger(type)) {
        value.number = castInteger(bits, type, options.pointerBits);
        value.kind = Value::Kind::Integer;
      } else if (isFloating(type)) {
        bits.floatingBits = bits.magnitude[0];
        bits.magnitude = {};
        value.number = bits;
        value.kind = Value::Kind::Floating;
      } else if (type == Type::Bool && bits.magnitude[0] <= 1) {
        value.number = bits;
        value.kind = Value::Kind::Bool;
      } else if (type == Type::Char && bits.magnitude[0] <= 0x10ffff &&
                 (bits.magnitude[0] < 0xd800 || bits.magnitude[0] > 0xdfff)) {
        value.number = bits;
        value.kind = Value::Kind::Char;
      }
    }
  }
  Opt readMemory(const Value &address, const Shape &shape, Span span,
                 bool aligned = true, bool raw = false) {
    auto layout = host.layout(shape.type);
    if (!layout ||
        !addressBounds(address, shape.type, layout->size, span, aligned))
      return std::nullopt;
    auto root = rootOf(address);
    if (!root)
      return readObject(address, shape, span);
    if (auto found =
            locate(*root, address.storageType, address.offset, shape.type)) {
      if (!raw && !initialized(*found, span))
        return std::nullopt;
      return *found;
    }
    auto result = uninitialized(shape);
    if (layout->size > options.stepBudget - steps)
      return fail("limit", span, "constant read exceeds the step budget");
    for (std::uint64_t i = 0; i < layout->size; ++i) {
      auto byte =
          storageByte(*root, address.storageType, address.offset + i, span);
      auto destination = storageByte(result, shape.type, i, span);
      if (!byte || !destination)
        return std::nullopt;
      *destination = *byte;
    }
    materializeBytes(result, shape.type);
    if (!raw && !initialized(result, span))
      return std::nullopt;
    if (!raw && result.kind == Value::Kind::Reference &&
        !validReference(result, span))
      return std::nullopt;
    return result;
  }
  bool writableMemory(const Value &address, Span span) {
    auto root = rootOf(address);
    if (!address.exclusive || !address.writable ||
        (root && root->immutableLiteral)) {
      fail("constant", span,
           "constant write requires exclusive writable provenance");
      return false;
    }
    return true;
  }
  bool writeMemory(const Value &address, const Value &value, Type type,
                   Span span, bool aligned = true) {
    auto layout = host.layout(type);
    if (!layout || !writableMemory(address, span) ||
        !addressBounds(address, type, layout->size, span, aligned))
      return false;
    auto root = rootOf(address);
    if (!root)
      return layout->size == 0;
    if (auto target =
            locate(*root, address.storageType, address.offset, type)) {
      *target = value;
      return true;
    }
    auto copy = value;
    for (std::uint64_t i = 0; i < layout->size; ++i) {
      auto from = storageByte(copy, type, i, span);
      auto to =
          storageByte(*root, address.storageType, address.offset + i, span);
      if (!from || !to)
        return false;
      *to = *from;
    }
    materializeBytes(*root, address.storageType, address.offset, layout->size);
    return true;
  }
  bool validReference(const Value &address, Span span) {
    auto target = pointee(address);
    if (!target)
      return false;
    if (auto root = rootOf(address);
        root && root->immutableLiteral && address.exclusive)
      return fail("constant", span,
                  "constant exclusive borrow requires writable provenance"),
             false;
    while (target->kind == Shape::Kind::Product &&
           target->elements.size() == 1) {
      auto layout = host.layout(target->type);
      if (!layout || layout->size || layout->fields.size() != 1 ||
          layout->fields.front() != 0)
        break;
      if (!addressBounds(address, target->type, 0, span))
        return false;
      auto tail = host.typeShape(target->elements.front().type);
      if (!tail)
        break;
      target = std::move(tail);
    }
    if (target->kind == Shape::Kind::Array && target->count == UINT64_MAX) {
      auto element = host.layout(target->elements.front().type);
      if (!element ||
          (element->size && address.count > UINT64_MAX / element->size))
        return fail("constant", span, "constant slice extent overflow"), false;
      return addressBounds(address, target->elements.front().type,
                           address.count * element->size, span);
    }
    auto layout = host.layout(target->type);
    return layout && addressBounds(address, target->type, layout->size, span);
  }
  Opt readObject(const Value &address, const Shape &shape, Span span) {
    if (!step(span))
      return std::nullopt;
    if (shape.kind == Shape::Kind::Array) {
      auto count = shape.count == UINT64_MAX ? address.count : shape.count;
      if (shape.elements.empty() || count > options.stepBudget - steps)
        return fail("limit", span,
                    "constant aggregate exceeds the step budget");
      auto element = host.layout(shape.elements.front().type);
      if (!element || (element->size && count > UINT64_MAX / element->size) ||
          !addressBounds(address, shape.elements.front().type,
                         element->size * count, span))
        return std::nullopt;
      Value value;
      value.kind = Value::Kind::Array;
      value.type = shape.type;
      for (std::uint64_t i = 0; i < count; ++i) {
        auto current = address;
        current.offset += i * element->size;
        auto item = readObject(current, shape.elements.front(), span);
        if (!item)
          return std::nullopt;
        value.elements.push_back(std::move(*item));
      }
      return value;
    }
    auto layout = host.layout(shape.type);
    if (!layout || !addressBounds(address, shape.type, layout->size, span))
      return std::nullopt;
    auto root = rootOf(address);
    if (!root && address.addressOnly && layout->size == 0) {
      auto value = uninitialized(shape);
      if (shape.kind == Shape::Kind::Unit)
        value.kind = Value::Kind::Unit;
      if (initialized(value, span))
        return value;
      return std::nullopt;
    }
    auto found = locate(*root, address.storageType, address.offset, shape.type);
    if (!found || found->kind == Value::Kind::Uninitialized)
      return fail("constant", span,
                  "constant read requires an initialized value of its type");
    return *found;
  }
  Opt readAddress(const Value &address, Span span) {
    auto target = pointee(address);
    if (!target)
      return unsupported(span, "this constant pointee");
    return readMemory(address, *target, span);
  }
  bool writeObject(const Value &address, const Value &value, Span span) {
    if (!address.exclusive || !address.writable) {
      fail("constant", span, "constant write requires exclusive access");
      return false;
    }
    auto type = host.valueType(value);
    auto layout = host.layout(type);
    if (!layout || !addressBounds(address, type, layout->size, span))
      return false;
    auto root = rootOf(address);
    if (!root && address.addressOnly && layout->size == 0)
      return true;
    if (root && root->immutableLiteral) {
      fail("constant", span, "constant write requires writable provenance");
      return false;
    }
    if (auto target =
            locate(*root, address.storageType, address.offset, type)) {
      *target = value;
      return true;
    }
    auto shape = host.typeShape(type);
    if (value.kind == Value::Kind::Array && shape && !shape->elements.empty()) {
      auto element = host.layout(shape->elements.front().type);
      if (!element)
        return false;
      for (std::size_t i = 0; i < value.elements.size(); ++i) {
        auto current = address;
        current.offset += i * element->size;
        if (!writeObject(current, value.elements[i], span))
          return false;
      }
      return true;
    }
    fail("constant", span, "constant write has an incompatible storage type");
    return false;
  }

  struct Place {
    Value *value = nullptr;
    Value *rootValue = nullptr;
    std::vector<std::size_t> path;
    bool mutableBinding = false;
    std::string root;
    std::shared_ptr<Value> storage;
    std::uint64_t offset = 0;
    std::optional<Value> address = std::nullopt;
    int symbol = -1;
  };
  Value addressOf(const Place &place, bool exclusive) {
    if (place.address) {
      auto result = *place.address;
      result.kind = Value::Kind::Reference;
      result.exclusive &= exclusive;
      if (auto target = pointee(result))
        result.type = host.referenceType(target->type, result.exclusive, false);
      return result;
    }
    if (place.value->kind == Value::Kind::Reference) {
      auto result = *place.value;
      result.exclusive &= exclusive;
      if (auto target = pointee(result))
        result.type = host.referenceType(target->type, result.exclusive, false);
      return result;
    }
    Value result;
    result.kind = Value::Kind::Reference;
    auto type = host.valueType(*place.value);
    result.type = host.referenceType(type, exclusive, false);
    result.storage = place.storage;
    result.storageType = host.valueType(*place.rootValue);
    result.offset = place.offset;
    result.count = place.value->elements.size();
    result.exclusive = exclusive;
    result.writable = exclusive;
    result.symbol = place.symbol;
    return result;
  }
  bool refresh(Place &place, Span span) {
    place.value = place.rootValue;
    for (auto index : place.path) {
      if ((place.value->kind != Value::Kind::Array &&
           place.value->kind != Value::Kind::Tuple &&
           place.value->kind != Value::Kind::Product) ||
          index >= place.value->elements.size()) {
        fail("constant", span,
             "constant place changed while evaluating its index");
        return false;
      }
      place.value = &place.value->elements[index];
    }
    return true;
  }
  Place place(const Node &node) {
    if (failed)
      return {};
    switch (node.kind) {
    case Kind::Group:
      return place(*node.children[0]);
    case Kind::Text: {
      auto value = eval(node, nullptr);
      if (!value)
        return {};
      Place result;
      result.address = std::move(*value);
      result.root = "text literal";
      return result;
    }
    case Kind::Unary:
      if (node.text == "*") {
        auto pointer = eval(*node.children[0], nullptr);
        if (!pointer)
          return {};
        if (pointer->kind != Value::Kind::Pointer &&
            pointer->kind != Value::Kind::Reference)
          return {};
        if (pointer->kind == Value::Kind::Pointer && !unsafeDepth) {
          fail("unsafe", node.span,
               "operation requires an unsafe block or unsafe function");
          return {};
        }
        Place result;
        result.address = std::move(*pointer);
        result.mutableBinding = result.address->exclusive;
        result.root = "constant pointee";
        return result;
      }
      return {};
    case Kind::Name: {
      auto &locals = frame().locals;
      for (auto it = locals.rbegin(); it != locals.rend(); ++it)
        if (namesLocal(*it, node))
          return {it->value.get(),
                  it->value.get(),
                  {},
                  it->mutableBinding ||
                      (it->value->kind == Value::Kind::Reference &&
                       it->value->exclusive),
                  it->name,
                  it->value};
      auto found = lookup(node);
      if (found.kind == Lookup::Kind::Constant && found.staticSymbol >= 0) {
        auto &root = staticRoots[found.staticSymbol];
        if (!root)
          root = std::make_shared<Value>(std::move(found.value));
        Place result{root.get(), root.get(), {}, false, node.text, root};
        result.symbol = found.staticSymbol;
        return result;
      }
      if (found.kind == Lookup::Kind::Constant && found.freshValue) {
        if (!host.copy(host.valueType(found.value))) {
          fail("feature", node.span,
               "required projection or borrow of a non-Copy associated value "
               "is not implemented");
          return {};
        }
        frame().locals.emplace_back("<associated>", std::move(found.value),
                                    true, nullptr);
        const auto &local = frame().locals.back();
        return {local.value.get(), local.value.get(), {}, true,
                node.text,         local.value};
      }
      return {};
    }
    case Kind::Field: {
      auto base = place(*node.children[0]);
      if (base.value && base.value->kind == Value::Kind::Reference) {
        base.address = *base.value;
        base.mutableBinding = base.address->exclusive;
        base.value = nullptr;
      }
      auto type =
          base.address
              ? pointee(*base.address)
              : (base.value ? host.typeShape(host.valueType(*base.value))
                            : std::nullopt);
      if (!type)
        return {};
      std::uint64_t index = 0;
      if (type->kind == Shape::Kind::Product) {
        auto field =
            std::find(type->names.begin(), type->names.end(), node.text);
        if (field == type->names.end())
          return {};
        index = field - type->names.begin();
      } else if (node.text.empty() ||
                 !std::all_of(node.text.begin(), node.text.end(),
                              [](char c) { return c >= '0' && c <= '9'; }) ||
                 node.text.size() > 9)
        return {};
      else
        index = std::stoull(node.text);
      if (index >= type->elements.size())
        return {};
      if (!host.project(type->type, static_cast<std::size_t>(index), node)) {
        failed = reported = true;
        return {};
      }
      auto layout = host.layout(type->type);
      if (!layout || index >= layout->fields.size())
        return {};
      if (base.address) {
        base.address->offset += layout->fields[index];
        base.address->type = host.referenceType(type->elements[index].type,
                                                base.address->exclusive, false);
        return base;
      }
      base.offset += layout->fields[index];
      base.path.push_back(static_cast<std::size_t>(index));
      base.value = &base.value->elements[index];
      return base;
    }
    case Kind::Index: {
      auto base = place(*node.children[0]);
      if (!base.value && !base.address) {
        auto value = eval(*node.children[0], nullptr);
        if (!value)
          return {};
        auto root = std::make_shared<Value>(std::move(*value));
        base = {root.get(), root.get(), {}, false, {}, root};
      }
      if (base.value && base.value->kind == Value::Kind::Reference) {
        base.address = *base.value;
        base.mutableBinding = base.address->exclusive;
        base.value = nullptr;
      }
      auto type =
          base.address
              ? pointee(*base.address)
              : (base.value ? host.typeShape(host.valueType(*base.value))
                            : std::nullopt);
      if (!type || type->kind != Shape::Kind::Array || type->elements.empty()) {
        fail("type", node.span, "cannot index this value in a constant");
        return {};
      }
      auto usize = scalarShape(Type::Usize);
      auto index = eval(*node.children[1], &usize);
      if (!index)
        return {};
      if (!base.address && !refresh(base, node.span))
        return {};
      if (!base.address && base.value->kind != Value::Kind::Array) {
        fail("constant", node.span,
             "constant place changed while evaluating its index");
        return {};
      }
      if (index->kind != Value::Kind::Integer ||
          (index->type != Type::Unknown && index->type != Type::Usize &&
           index->type != Type::I32)) {
        fail("type", node.children[1]->span,
             "array index must be i32 or usize, found " + describe(*index));
        return {};
      }
      auto count = base.address && type->count == UINT64_MAX
                       ? base.address->count
                       : type->count;
      if (index->number.negative || index->number.magnitude[1] ||
          index->number.magnitude[0] >= count) {
        fail("constant", node.span,
             "index out of bounds in constant expression: the length is " +
                 std::to_string(count) + " but the index is " +
                 integerLiteralName(index->number));
        return {};
      }
      auto element = host.layout(type->elements.front().type);
      if (!element)
        return {};
      if (base.address) {
        base.address->offset += index->number.magnitude[0] * element->size;
        base.address->type = host.referenceType(type->elements.front().type,
                                                base.address->exclusive, false);
        return base;
      }
      base.offset += index->number.magnitude[0] * element->size;
      base.path.push_back(static_cast<std::size_t>(index->number.magnitude[0]));
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
    if (value.kind == Value::Kind::Reference &&
        pattern.kind != PatternKind::Wildcard) {
      auto target = pointee(value);
      if (!target)
        return unsupported(pattern.span, "this borrowed constant pattern");
      bool binding = pattern.kind == PatternKind::Binding ||
                     pattern.kind == PatternKind::At;
      if (!binding || host.copy(target->type)) {
        auto loaded = readAddress(value, pattern.span);
        if (!loaded)
          return std::nullopt;
        auto layout = host.layout(target->type);
        for (std::size_t i = 0; i < loaded->elements.size(); ++i) {
          auto type = host.valueType(loaded->elements[i]);
          if (host.copy(type))
            continue;
          auto projected = value;
          if (target->kind == Shape::Kind::Array) {
            auto element = host.layout(type);
            if (!element)
              return unsupported(pattern.span,
                                 "this borrowed constant pattern");
            projected.offset += i * element->size;
          } else {
            auto field = i;
            if (loaded->kind == Value::Kind::Variant) {
              if (loaded->selection < 0 ||
                  std::size_t(loaded->selection) >= target->variants.size() ||
                  i >= target->variants[loaded->selection].size())
                return fail("type", pattern.span,
                            "invalid constant enum variant");
              field = target->variants[loaded->selection][i];
            }
            if (!layout || field >= layout->fields.size())
              return unsupported(pattern.span,
                                 "this borrowed constant pattern");
            projected.offset += layout->fields[field];
          }
          projected.type = host.referenceType(type, false, false);
          projected.exclusive = false;
          loaded->elements[i] = std::move(projected);
        }
        return matches(pattern, *loaded, binds, mutableBinding);
      }
    }
    switch (pattern.kind) {
    case PatternKind::Wildcard:
      return true;
    case PatternKind::Binding: {
      Node name;
      name.kind = Kind::Name;
      name.span = pattern.span;
      name.text = pattern.text;
      name.context = pattern.context;
      auto found = lookup(name);
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
      binds.push_back({pattern.text, value, mutableBinding, pattern.context});
      return true;
    }
    case PatternKind::At: {
      auto inner = matches(pattern.children[0], value, binds, mutableBinding);
      if (inner && *inner)
        binds.push_back({pattern.text, value, mutableBinding, pattern.context});
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
    case PatternKind::Variant: {
      if (value.kind != Value::Kind::Variant && value.kind != Value::Kind::Enum)
        return false;
      auto name = pattern.text;
      auto separator = name.rfind("::");
      if (separator != std::string::npos)
        name = name.substr(separator + 2);
      auto selection = name == "present" || name == "failure" ? 1 : 0;
      auto found = host.variant(value.type, name, pattern.span);
      if (found.kind == Lookup::Kind::Constant)
        selection = found.value.selection;
      else if (name != "present" && name != "none" && name != "success" &&
               name != "failure")
        return unsupported(pattern.span, "this constant variant pattern");
      auto active = value.kind == Value::Kind::Enum
                        ? int(value.number.magnitude[0])
                        : value.selection;
      if (active != selection ||
          value.elements.size() != pattern.children.size())
        return false;
      for (std::size_t i = 0; i < pattern.children.size(); ++i) {
        auto matched = matches(pattern.children[i], value.elements[i], binds,
                               mutableBinding);
        if (!matched || !*matched)
          return matched;
      }
      return true;
    }
    case PatternKind::Product: {
      if (value.kind != Value::Kind::Product &&
          value.kind != Value::Kind::Variant)
        return false;
      auto shape = host.typeShape(value.type);
      if (!shape)
        return unsupported(pattern.span, "this constant product pattern");
      std::vector<std::size_t> fields;
      if (value.kind == Value::Kind::Variant) {
        auto name = std::string_view(pattern.text);
        if (auto separator = name.rfind("::");
            separator != std::string_view::npos)
          name.remove_prefix(separator + 2);
        auto found = host.variant(value.type, name, pattern.span);
        if (found.kind != Lookup::Kind::Constant)
          return unsupported(pattern.span, "this constant variant pattern");
        if (found.value.selection != value.selection)
          return false;
        if (value.selection < 0 ||
            std::size_t(value.selection) >= shape->variants.size())
          return fail("type", pattern.span, "invalid constant enum variant");
        fields = shape->variants[value.selection];
      } else
        for (std::size_t i = 0; i < shape->elements.size(); ++i)
          fields.push_back(i);
      for (const auto &child : pattern.children) {
        auto field =
            std::find_if(fields.begin(), fields.end(), [&](std::size_t index) {
              return index < shape->names.size() &&
                     shape->names[index] == child.field;
            });
        if (field == fields.end() ||
            std::size_t(field - fields.begin()) >= value.elements.size())
          return fail("type", child.span, "unknown constant pattern field");
        auto matched = matches(child, value.elements[field - fields.begin()],
                               binds, mutableBinding);
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
    Scope scope(*this, node.span);
    Opt last = unitValue();
    for (std::size_t i = 0; i < node.children.size(); ++i) {
      bool tail = i + 1 == node.children.size() && !node.children[i]->semicolon;
      auto value = eval(*node.children[i], tail ? want : nullptr);
      if (!value)
        return std::nullopt;
      if (!tail)
        discard(*value, node.children[i]->span);
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
    if (node.children.empty()) {
      if (!declared)
        return unsupported(node.span, "an untyped uninitialized declaration");
      frame().locals.emplace_back(node.text, uninitialized(*declared), true,
                                  node.context);
      return unitValue();
    }
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
      frame().locals.push_back(
          {node.text, std::move(*value), node.flag, node.context});
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

  std::optional<Shape> placeShape(const Node &node) {
    if (node.kind == Kind::Group)
      return placeShape(*node.children[0]);
    if (node.kind == Kind::Name) {
      for (auto it = frame().locals.rbegin(); it != frame().locals.rend(); ++it)
        if (namesLocal(*it, node))
          return shapeOfValue(*it->value);
      return std::nullopt;
    }
    if (node.kind != Kind::Field && node.kind != Kind::Index)
      return std::nullopt;
    auto base = placeShape(*node.children[0]);
    if (!base)
      return std::nullopt;
    if (node.kind == Kind::Index)
      return base->kind == Shape::Kind::Array
                 ? std::optional<Shape>(base->elements.front())
                 : std::nullopt;
    if (base->kind != Shape::Kind::Tuple || node.text.empty() ||
        node.text.size() > 9 ||
        !std::all_of(node.text.begin(), node.text.end(),
                     [](char c) { return c >= '0' && c <= '9'; }))
      return std::nullopt;
    auto index = std::stoull(node.text);
    return index < base->elements.size()
               ? std::optional<Shape>(base->elements[index])
               : std::nullopt;
  }

  Opt assign(const Node &node) {
    const Node &target = *node.children[0];
    auto hint = placeShape(target);
    auto value = eval(*node.children[1], hint ? &*hint : nullptr);
    if (!value)
      return std::nullopt;
    auto target_ = place(target);
    if (!target_.value && !target_.address)
      return fail("constant", target.span,
                  "assignment target is not a constant place");
    if (!target_.mutableBinding)
      return fail("constant", target.span,
                  "cannot assign to immutable binding '" + target_.root +
                      "' in a constant expression");
    if (node.text != "=") {
      auto op = node.text.substr(0, node.text.size() - 1);
      auto current = target_.address ? readAddress(*target_.address, node.span)
                                     : Opt(*target_.value);
      if (!current)
        return std::nullopt;
      auto combined =
          binary(op, std::move(*current), std::move(*value), node.span);
      if (!combined)
        return std::nullopt;
      value = std::move(combined);
    }
    auto shape = target_.address
                     ? pointee(*target_.address)
                     : host.typeShape(host.valueType(*target_.value));
    if (!shape && target_.value)
      shape = shapeOfValue(*target_.value);
    if (shape && !coerce(*value, *shape, node.span))
      return std::nullopt;
    if (target_.address) {
      if (!writeObject(*target_.address, *value, node.span))
        return std::nullopt;
      return unitValue();
    }
    *target_.value = std::move(*value);
    return unitValue();
  }

  // Runs one loop iteration's signal handling. Returns true to leave the loop;
  // `escaped` is set when the signal belongs to an outer construct or error.
  bool loopControl(const Node &loop, bool &escaped) {
    escaped = false;
    if (failed || signal == Signal::Return || signal == Signal::Throw ||
        signal == Signal::None) {
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
      Scope scope(*this, node.span);
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
    Opt current, high;
    if (iterable.kind == Kind::Range && iterable.name.empty()) {
      auto low = eval(*iterable.children[0], nullptr);
      if (!low)
        return std::nullopt;
      auto hint = shapeOfValue(*low);
      high = eval(*iterable.children[1], &hint);
      if (!high || !unify(*low, *high, iterable.span))
        return std::nullopt;
      if (low->kind != Value::Kind::Integer && low->kind != Value::Kind::Char)
        return fail("type", iterable.span, "a range needs integer bounds");
      if (low->type == Type::Unknown &&
          (!coerce(*low, scalarShape(Type::I32), iterable.span) ||
           !coerce(*high, scalarShape(Type::I32), iterable.span)))
        return std::nullopt;
      current = std::move(low);
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
    std::size_t position = 0;
    while (true) {
      if (current) {
        auto bound = iterable.text == "..=" ? 1 : 0;
        if (compareIntegers(current->number, high->number) >= bound)
          break;
        if (!step(iterable.span))
          return std::nullopt;
      } else if (position == items.size())
        break;
      auto item = current ? *current : std::move(items[position++]);
      Scope scope(*this, node.span);
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
      if (current) {
        if (compareIntegers(current->number, high->number) == 0)
          break;
        auto kernel =
            current->kind == Value::Kind::Char ? Type::U32 : current->type;
        auto next = integerOperation("+", kernel, *current,
                                     integerValue(kernel, integerLiteral(1)),
                                     iterable.span);
        if (!next)
          return std::nullopt;
        current->number = next->number;
        if (current->kind == Value::Kind::Char &&
            compareIntegers(current->number, integerLiteral(0xd800)) == 0)
          current->number = integerLiteral(0xe000);
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
      Scope scope(*this, node.span);
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

  Value uninitialized(const Shape &shape) {
    Value value;
    value.type = shape.type;
    value.kind = Value::Kind::Uninitialized;
    if (shape.kind == Shape::Kind::Product ||
        shape.kind == Shape::Kind::Tuple) {
      value.kind = shape.kind == Shape::Kind::Product ? Value::Kind::Product
                                                      : Value::Kind::Tuple;
      for (const auto &field : shape.elements)
        value.elements.push_back(uninitialized(field));
    }
    return value;
  }
  bool initialized(const Value &value, Span span) {
    if (value.kind == Value::Kind::Uninitialized) {
      fail("constant", span, "constant value is not fully initialized");
      return false;
    }
    for (const auto &element : value.elements)
      if (!initialized(element, span))
        return false;
    return true;
  }
  bool exportable(const Value &value, Span span) {
    auto root = value.storage.lock();
    if ((value.kind == Value::Kind::Reference ||
         value.kind == Value::Kind::Pointer) &&
        !value.addressOnly && value.symbol < 0 &&
        !(root && root->immutableLiteral)) {
      fail("constant", span,
           "constant result cannot retain a pointer or view of local storage");
      return false;
    }
    for (const auto &element : value.elements)
      if (!exportable(element, span))
        return false;
    return true;
  }
  std::optional<Type> typeArgument(const Node &callee,
                                   const Host::Operation &operation) {
    if (!callee.genericArguments.empty() &&
        callee.genericArguments.front().type)
      return host.resolveType(*callee.genericArguments.front().type,
                              callee.span);
    if (operation.type != Type::Unknown)
      return operation.type;
    return std::nullopt;
  }
  Opt intrinsic(const Node &node, const Host::Operation &operation,
                const Value *receiver, std::span<const Value> arguments) {
    const auto &callee = *node.children[0];
    auto argumentType = typeArgument(callee, operation);
    auto name = operation.name;
    std::optional<Value> pointerReceiver;
    std::vector<Value> pointerArguments;
    if (name.starts_with("ptr.") && name != "ptr.from_ref" &&
        name != "ptr.from_mut") {
      auto loadPointer = [&](const Value &value) -> Opt {
        auto shape = value.kind == Value::Kind::Reference ? pointee(value)
                                                          : std::nullopt;
        return shape && shape->kind == Shape::Kind::Pointer
                   ? readAddress(value, node.span)
                   : Opt{value};
      };
      if (receiver) {
        pointerReceiver = loadPointer(*receiver);
        if (!pointerReceiver)
          return std::nullopt;
        receiver = &*pointerReceiver;
      }
      pointerArguments.assign(arguments.begin(), arguments.end());
      for (std::size_t i = 0; i < pointerArguments.size(); ++i)
        if (i == 0 || (i == 1 && (name == "ptr.copy" ||
                                  name == "ptr.copy_nonoverlapping" ||
                                  name == "ptr.swap"))) {
          auto loaded = loadPointer(pointerArguments[i]);
          if (!loaded)
            return std::nullopt;
          pointerArguments[i] = std::move(*loaded);
        }
      arguments = pointerArguments;
    }
    if (name == "storage.new" || name == "storage.into_inner") {
      if (name == "storage.new") {
        auto target = host.typeShape(operation.type);
        if (!target || target->kind != Shape::Kind::Product ||
            target->elements.size() != 1 || arguments.size() != 1)
          return unsupported(node.span, "this constant storage constructor");
        auto payload = arguments.front();
        if (!initialized(payload, node.span) ||
            !coerce(payload, target->elements.front(), node.span))
          return std::nullopt;
        Value value;
        value.kind = Value::Kind::Product;
        value.type = target->type;
        value.elements.push_back(std::move(payload));
        return value;
      }
      if (receiver && !initialized(*receiver, node.span))
        return std::nullopt;
      if (!receiver || receiver->kind != Value::Kind::Product ||
          receiver->elements.size() != 1 || !arguments.empty())
        return unsupported(node.span, "this constant storage extraction");
      return receiver->elements.front();
    }
    if (name == "cell.as_ptr") {
      if (!receiver || receiver->kind != Value::Kind::Reference ||
          !arguments.empty())
        return unsupported(node.span, "this constant Cell pointer projection");
      auto storage = pointee(*receiver);
      if (!storage || storage->kind != Shape::Kind::Product ||
          storage->elements.size() != 1)
        return unsupported(node.span, "this constant Cell storage");
      auto value = *receiver;
      value.kind = Value::Kind::Pointer;
      value.type =
          host.referenceType(storage->elements.front().type, true, true);
      value.exclusive = true;
      return value;
    }
    if (name == "size_of" || name == "align_of" || name == "mem.size_of" ||
        name == "mem.align_of") {
      auto layout = argumentType ? host.layout(*argumentType) : std::nullopt;
      if (!layout)
        return unsupported(node.span, "this constant layout");
      return integerValue(Type::Usize, integerLiteral(name.ends_with("align_of")
                                                          ? layout->alignment
                                                          : layout->size));
    }
    if (name == "slice.len" || (receiver && callee.text == "len" &&
                                (receiver->kind == Value::Kind::Array ||
                                 receiver->kind == Value::Kind::Reference))) {
      if (!arguments.empty())
        return fail("type", node.span, "len requires no arguments");
      auto count = receiver->kind == Value::Kind::Array
                       ? receiver->elements.size()
                       : receiver->count;
      if (receiver->kind == Value::Kind::Reference) {
        auto shape = pointee(*receiver);
        if (!shape || shape->kind != Shape::Kind::Array)
          return unsupported(node.span, "this constant length");
        if (shape->count != UINT64_MAX)
          count = shape->count;
      }
      return integerValue(Type::Usize, integerLiteral(count));
    }
    if (name == "ptr.from_ref" || name == "ptr.from_mut") {
      if (arguments.size() != 1 || arguments[0].kind != Value::Kind::Reference)
        return fail("constant", node.span,
                    "constant pointer construction requires a live view");
      if (name == "ptr.from_mut" &&
          (!arguments[0].exclusive || !arguments[0].writable))
        return fail("constant", node.span,
                    "constant mutable pointer requires writable provenance");
      auto value = arguments[0];
      auto target = pointee(value);
      if (!target)
        return std::nullopt;
      value.kind = Value::Kind::Pointer;
      value.exclusive = name == "ptr.from_mut" && value.exclusive;
      value.type = host.referenceType(target->type, value.exclusive, true);
      value.bytes.clear();
      return value;
    }
    if (name == "ptr.null" || name == "ptr.null_mut" ||
        name == "ptr.without_provenance") {
      if (!argumentType)
        return unsupported(node.span, "this constant null pointer type");
      Value value;
      value.kind = Value::Kind::Pointer;
      value.addressOnly = true;
      value.exclusive = name == "ptr.null_mut";
      value.writable = true;
      if (name == "ptr.without_provenance") {
        if (arguments.size() != 1 ||
            arguments.front().kind != Value::Kind::Integer)
          return fail("type", node.span, "pointer address requires usize");
        value.offset = arguments.front().number.magnitude[0];
      }
      value.type = host.referenceType(*argumentType, value.exclusive, true);
      return value;
    }
    if (receiver && receiver->kind == Value::Kind::Pointer) {
      auto value = *receiver;
      value.bytes.clear();
      auto target = pointee(value);
      if (!target)
        return std::nullopt;
      if (name == "ptr.is_null")
        return boolValue(value.addressOnly && value.offset == 0);
      if (name == "ptr.cast" || name == "ptr.cast_const" ||
          name == "ptr.cast_mut") {
        if (name == "ptr.cast")
          value.count = 0;
        if (name == "ptr.cast_mut")
          value.exclusive = true;
        if (name == "ptr.cast_const")
          value.exclusive = false;
        value.type = host.referenceType(
            name == "ptr.cast" && argumentType ? *argumentType : target->type,
            value.exclusive, true);
        return value;
      }
      if (name == "ptr.add" || name == "ptr.sub" || name == "ptr.offset" ||
          name == "ptr.byte_add" || name == "ptr.byte_sub" ||
          name == "ptr.byte_offset") {
        if (!unsafeDepth)
          return fail("unsafe", node.span,
                      "operation requires an unsafe block or unsafe function");
        if (arguments.size() != 1 || arguments[0].kind != Value::Kind::Integer)
          return fail("type", node.span, "pointer offset requires usize");
        auto layout = host.layout(name.starts_with("ptr.byte_") ? Type::U8
                                                                : target->type);
        auto count = arguments[0].number;
        auto limit =
            integerMaximum(Type::Isize, options.pointerBits).magnitude[0];
        if (!layout || count.magnitude[1] ||
            (layout->size && count.magnitude[0] > limit / layout->size))
          return fail("constant", node.span,
                      "constant pointer offset overflow");
        auto bytes = count.magnitude[0] * layout->size;
        if (value.addressOnly && bytes)
          return fail(
              "constant", node.span,
              "constant pointer arithmetic requires allocation provenance");
        bool subtract =
            count.negative != (name == "ptr.sub" || name == "ptr.byte_sub");
        if ((!subtract && bytes > UINT64_MAX - value.offset) ||
            (subtract && bytes > value.offset))
          return fail("constant", node.span,
                      "constant pointer offset overflow");
        value.offset = subtract ? value.offset - bytes : value.offset + bytes;
        if (!addressBounds(value, Type::U8, 0, node.span, false))
          return std::nullopt;
        return value;
      }
      if (name == "ptr.offset_from" || name == "ptr.offset_from_unsigned" ||
          name == "ptr.byte_offset_from" ||
          name == "ptr.byte_offset_from_unsigned") {
        if (!unsafeDepth)
          return fail("unsafe", node.span,
                      "operation requires an unsafe block or unsafe function");
        if (arguments.size() != 1 ||
            arguments.front().kind != Value::Kind::Pointer)
          return fail("type", node.span, "pointer distance requires an origin");
        const auto &origin = arguments.front();
        auto layout = host.layout(name.starts_with("ptr.byte_") ? Type::U8
                                                                : target->type);
        if (!layout || !layout->size)
          return fail(
              "constant", node.span,
              "constant pointer distance requires a nonzero-sized type");
        if (!sameAllocation(value, origin) ||
            (value.addressOnly && value.offset != origin.offset))
          return fail("constant", node.span,
                      "constant pointer distance requires common provenance");
        if (!addressBounds(value, Type::U8, 0, node.span, false) ||
            !addressBounds(origin, Type::U8, 0, node.span, false))
          return std::nullopt;
        bool negative = value.offset < origin.offset;
        auto bytes = negative ? origin.offset - value.offset
                              : value.offset - origin.offset;
        auto limit =
            integerMaximum(Type::Isize, options.pointerBits).magnitude[0];
        if (bytes > limit || bytes % layout->size ||
            (name.ends_with("_unsigned") && negative))
          return fail("constant", node.span,
                      "constant pointer distance is outside its result domain");
        auto result = integerLiteral(bytes / layout->size);
        result.negative = negative && bytes != 0;
        return integerValue(
            name.ends_with("_unsigned") ? Type::Usize : Type::Isize, result);
      }
    }
    if (name == "ptr.read" || name == "ptr.read_unaligned" ||
        name == "ptr.write" || name == "ptr.write_unaligned" ||
        name == "ptr.copy" || name == "ptr.copy_nonoverlapping" ||
        name == "ptr.swap" || name == "ptr.write_bytes") {
      if (!unsafeDepth)
        return fail("unsafe", node.span,
                    "operation requires an unsafe block or unsafe function");
      auto operands = std::vector<Value>(arguments.begin(), arguments.end());
      if (receiver)
        operands.insert(operands.begin(), *receiver);
      if (operands.empty() || operands.front().kind != Value::Kind::Pointer)
        return fail("type", node.span, "memory operation requires a pointer");
      auto address = operands.front();
      auto target = pointee(address);
      auto layout = target ? host.layout(target->type) : std::nullopt;
      if (!target || !layout)
        return unsupported(node.span, "this constant memory layout");
      if (name == "ptr.read" || name == "ptr.read_unaligned")
        return readMemory(address, *target, node.span, name == "ptr.read");
      if (name == "ptr.write" || name == "ptr.write_unaligned") {
        if (operands.size() != 2)
          return fail("type", node.span, "pointer write requires one value");
        return writeMemory(address, operands[1], target->type, node.span,
                           name == "ptr.write")
                   ? Opt{unitValue()}
                   : std::nullopt;
      }
      if (name == "ptr.swap") {
        if (operands.size() != 2)
          return fail("type", node.span, "pointer swap requires two pointers");
        auto first = readMemory(address, *target, node.span, true, true);
        auto second = readMemory(operands[1], *target, node.span, true, true);
        if (!first || !second ||
            !writeMemory(address, *second, target->type, node.span) ||
            !writeMemory(operands[1], *first, target->type, node.span))
          return std::nullopt;
        return unitValue();
      }
      if (operands.size() != 3 || operands[2].kind != Value::Kind::Integer)
        return fail("type", node.span, "memory operation requires a count");
      const auto count = operands[2].number;
      if (count.negative || count.magnitude[1] ||
          (layout->size &&
           count.magnitude[0] >
               integerMaximum(Type::Isize, options.pointerBits).magnitude[0] /
                   layout->size))
        return fail("constant", node.span, "constant memory extent overflow");
      const auto size = count.magnitude[0] * layout->size;
      auto destination = name == "ptr.write_bytes" ? address : operands[1];
      if (!addressBounds(address, target->type, size, node.span) ||
          !addressBounds(destination, target->type, size, node.span) ||
          !writableMemory(destination, node.span))
        return std::nullopt;
      if (!size)
        return unitValue();
      if (name == "ptr.write_bytes") {
        auto root = rootOf(destination);
        for (std::uint64_t i = 0; i < size; ++i) {
          auto to = storageByte(*root, destination.storageType,
                                destination.offset + i, node.span);
          if (!to)
            return std::nullopt;
          *to = {static_cast<std::uint8_t>(operands[1].number.magnitude[0]),
                 {},
                 0};
        }
        materializeBytes(*root, destination.storageType, destination.offset,
                         size);
        return unitValue();
      }
      if (name == "ptr.copy_nonoverlapping" &&
          sameAllocation(address, destination) &&
          (address.offset < destination.offset
               ? destination.offset - address.offset < size
               : address.offset - destination.offset < size))
        return fail("constant", node.span,
                    "constant nonoverlapping copy has overlapping ranges");
      if (count.magnitude[0] > options.stepBudget - steps)
        return fail("limit", node.span,
                    "constant copy exceeds the step budget");
      std::vector<Value> copied;
      for (std::uint64_t i = 0; i < count.magnitude[0]; ++i) {
        auto source = address;
        source.offset += i * layout->size;
        auto item = readMemory(source, *target, node.span, true, true);
        if (!item)
          return std::nullopt;
        copied.push_back(std::move(*item));
      }
      for (std::size_t i = 0; i < copied.size(); ++i) {
        auto to = destination;
        to.offset += i * layout->size;
        if (!writeMemory(to, copied[i], target->type, node.span))
          return std::nullopt;
      }
      return unitValue();
    }
    if (name == "mem.transmute") {
      if (!unsafeDepth)
        return fail("unsafe", node.span,
                    "operation requires an unsafe block or unsafe function");
      auto target = argumentType ? host.typeShape(*argumentType) : std::nullopt;
      if (!target || arguments.size() != 1)
        return unsupported(node.span, "this constant transmute");
      auto value = arguments[0];
      if (value.kind == Value::Kind::Reference) {
        auto loaded = readAddress(value, node.span);
        if (!loaded)
          return std::nullopt;
        value = std::move(*loaded);
      }
      auto sourceLayout = host.layout(host.valueType(value));
      auto targetLayout = host.layout(target->type);
      if (!sourceLayout || !targetLayout ||
          sourceLayout->size != targetLayout->size)
        return fail("constant", node.span,
                    "constant transmute requires equal target layouts");
      if (target->kind == Shape::Kind::Pointer) {
        if (value.kind == Value::Kind::Integer && isInteger(value.type) &&
            integerWidth(value.type, options.pointerBits) ==
                options.pointerBits) {
          value.kind = Value::Kind::Pointer;
          value.addressOnly = true;
          value.offset =
              castInteger(value.number, Type::Usize, options.pointerBits)
                  .magnitude[0];
          value.writable = target->exclusive;
        } else if (value.kind == Value::Kind::Product &&
                   value.elements.size() == 2 &&
                   value.elements[0].kind == Value::Kind::Pointer &&
                   value.elements[1].kind == Value::Kind::Integer) {
          auto count = value.elements[1].number;
          if (count.negative || count.magnitude[1])
            return fail("constant", node.span,
                        "constant slice metadata is outside usize");
          auto data = value.elements[0];
          data.count = count.magnitude[0];
          value = std::move(data);
        } else if (value.kind != Value::Kind::Pointer)
          return unsupported(node.span, "this constant pointer representation");
        value.type = target->type;
        value.exclusive = target->exclusive;
        value.bytes.clear();
        return value;
      }
      if (target->kind == Shape::Kind::Product &&
          target->elements.size() == 2 &&
          target->elements[0].kind == Shape::Kind::Pointer &&
          target->elements[1].type == Type::Usize &&
          value.kind == Value::Kind::Pointer) {
        Value raw;
        raw.kind = Value::Kind::Product;
        raw.type = target->type;
        auto count = integerValue(Type::Usize, integerLiteral(value.count));
        value.type = target->elements[0].type;
        value.exclusive = target->elements[0].exclusive;
        value.bytes.clear();
        raw.elements = {std::move(value), std::move(count)};
        return raw;
      }
      return unsupported(node.span, "this constant transmute representation");
    }
    return unsupported(node.span, "operation '" + name + "'");
  }
  Opt aggregateCall(const Node &node, const Shape *want) {
    const auto &callee = *node.children[0];
    auto operation = host.operation(node);
    if (operation.name == "panic" ||
        (callee.kind == Kind::Name &&
         (callee.text == "core::panic::panic" ||
          callee.text == "alloc::alloc::panic_precondition")))
      return fail("constant", frame().callSpan,
                  "panic during constant evaluation");
    std::optional<Value> receiver;
    Place receiverPlace;
    auto primitiveOwner = callee.kind == Kind::Field
                              ? namedType(*callee.children[0])
                              : Type::Unknown;
    if (callee.kind == Kind::Name && operation.name.starts_with("numeric.") &&
        isInteger(operation.type))
      primitiveOwner = operation.type;
    if (callee.kind == Kind::Field && !isInteger(primitiveOwner)) {
      auto converted = host.receiver(node);
      if (converted)
        receiver = eval(*converted, nullptr);
      else
        receiverPlace = place(*callee.children[0]);
      if (!converted && receiverPlace.address)
        receiver = *receiverPlace.address;
      else if (!converted && receiverPlace.value)
        receiver = *receiverPlace.value;
      else if (!converted)
        receiver = eval(*callee.children[0], nullptr);
      if (!receiver)
        return std::nullopt;
      if (receiver->kind == Value::Kind::Reference) {
        auto target = pointee(*receiver);
        if (target && isFloating(target->type)) {
          auto loaded = readMemory(*receiver, *target, callee.span);
          if (!loaded)
            return std::nullopt;
          receiver = std::move(*loaded);
        }
      }
      if (receiver->kind == Value::Kind::Floating) {
        if (!defaultTypes(*receiver, callee.span))
          return std::nullopt;
        if (constantFloatMethod(callee.text))
          return primitiveCall(node, receiver->type, callee.text, receiver);
        // Other float methods are library const functions.
        auto library = host.method(receiver->type, node);
        if (library.kind == Lookup::Kind::Missing)
          return fail("constant", callee.span,
                      "call to non-const or unavailable float method '" +
                          callee.text + "'");
      }
      if (operation.name.empty()) {
        if (receiver->kind == Value::Kind::Pointer)
          operation.name = "ptr." + callee.text;
        else if (callee.text == "len") {
          auto target = receiver->kind == Value::Kind::Reference
                            ? pointee(*receiver)
                            : host.typeShape(host.valueType(*receiver));
          if (target && target->kind == Shape::Kind::Array)
            operation.name = "slice.len";
        }
      }
    }
    std::vector<Value> arguments;
    std::vector<Place> places;
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      auto where = place(*node.children[i]);
      Opt value;
      if (where.address)
        value = *where.address;
      else if (where.value)
        value = *where.value;
      else
        value = eval(*node.children[i], nullptr);
      if (!value)
        return std::nullopt;
      if ((operation.name == "ptr.from_ref" ||
           operation.name == "ptr.from_mut") &&
          value->kind != Value::Kind::Reference &&
          (where.value || where.address)) {
        if (operation.name == "ptr.from_mut" && !where.mutableBinding)
          return fail("constant", node.span,
                      "constant mutable pointer requires a mutable place");
        value = addressOf(where, operation.name == "ptr.from_mut");
      }
      arguments.push_back(std::move(*value));
      places.push_back(std::move(where));
    }
    if (receiver && receiver->kind == Value::Kind::Reference) {
      auto target = pointee(*receiver);
      if (target && isInteger(target->type))
        primitiveOwner = target->type;
    } else if (receiver && receiver->kind == Value::Kind::Integer) {
      if (!defaultTypes(*receiver, callee.span))
        return std::nullopt;
      primitiveOwner = receiver->type;
    }
    if (isInteger(primitiveOwner)) {
      auto values = arguments;
      if (receiver)
        values.insert(values.begin(), *receiver);
      auto value = integerCall(node, primitiveOwner, std::move(values), want);
      if (failed)
        return std::nullopt;
      if (value) {
        if (callee.text == "make_ascii_lowercase" ||
            callee.text == "make_ascii_uppercase") {
          if (!receiver && arguments.empty())
            return fail("type", callee.span, "missing mutable receiver");
          auto &where = receiver ? receiverPlace : places.front();
          auto &original = receiver ? *receiver : arguments.front();
          if (original.kind == Value::Kind::Reference) {
            if (!writeObject(original, *value, callee.span))
              return std::nullopt;
          } else if (where.address) {
            if (!writeObject(*where.address, *value, callee.span))
              return std::nullopt;
          } else if (where.value && where.mutableBinding)
            *where.value = std::move(*value);
          else
            return fail("constant", callee.span,
                        "integer mutation requires a mutable place");
          return unitValue();
        }
        return value;
      }
    }
    if (operation.name == "cell.as_ptr" && receiver &&
        receiver->kind != Value::Kind::Reference) {
      if (!receiverPlace.value && !receiverPlace.address) {
        frame().locals.emplace_back("<temporary>", std::move(*receiver), false,
                                    nullptr);
        const auto &local = frame().locals.back();
        receiverPlace = {local.value.get(), local.value.get(), {}, false,
                         local.name,        local.value};
      }
      receiver = addressOf(receiverPlace, false);
    }
    if (!operation.name.empty()) {
      auto value = intrinsic(node, operation, receiver ? &*receiver : nullptr,
                             arguments);
      if (value && operation.name == "storage.into_inner" &&
          receiverPlace.value)
        receiverPlace.value->kind = Value::Kind::Uninitialized;
      if (value && operation.name == "storage.new" && !arguments.empty() &&
          !host.copy(host.valueType(arguments.front())) && places.front().value)
        places.front().value->kind = Value::Kind::Uninitialized;
      return value;
    }
    auto found =
        host.prepare(node, receiver ? &*receiver : nullptr, arguments, want);
    if (found.kind == Lookup::Kind::Missing && callee.kind == Kind::Name)
      found = lookup(callee);
    if (found.kind == Lookup::Kind::Symbolic) {
      symbolic = failed = true;
      return std::nullopt;
    }
    if (found.kind == Lookup::Kind::Failed) {
      failed = reported = true;
      return std::nullopt;
    }
    if (found.kind == Lookup::Kind::Constant &&
        found.value.kind == Value::Kind::Enum && arguments.empty())
      return found.value;
    if (found.kind == Lookup::Kind::Constant &&
        (found.value.kind == Value::Kind::Product ||
         found.value.kind == Value::Kind::Variant)) {
      auto shape = host.typeShape(found.value.type);
      if (!shape)
        return unsupported(node.span, "this constant constructor");
      if (found.value.kind == Value::Kind::Variant) {
        auto selection = found.value.selection;
        if (selection < 0 || std::size_t(selection) >= shape->variants.size())
          return fail("type", callee.span, "invalid constant enum variant");
        auto fields = shape->variants[selection];
        std::vector<Shape> elements;
        std::vector<std::string> names;
        for (auto field : fields) {
          if (field >= shape->elements.size() || field >= shape->names.size())
            return fail("type", callee.span, "invalid constant variant field");
          elements.push_back(shape->elements[field]);
          names.push_back(shape->names[field]);
        }
        shape->kind = Shape::Kind::Product;
        shape->elements = std::move(elements);
        shape->names = std::move(names);
      }
      auto value = uninitialized(*shape);
      value.kind = found.value.kind;
      value.selection = found.value.selection;
      std::vector<bool> used(shape->elements.size());
      for (std::size_t i = 0; i < arguments.size(); ++i) {
        std::size_t slot = i;
        auto &argument = *node.children[i + 1];
        if (!argument.name.empty())
          slot = std::find(shape->names.begin(), shape->names.end(),
                           argument.name) -
                 shape->names.begin();
        if (slot >= value.elements.size() || used[slot])
          return fail("type", argument.span,
                      "invalid constant constructor argument");
        used[slot] = true;
        if (!coerce(arguments[i], shape->elements[slot], argument.span))
          return std::nullopt;
        value.elements[slot] = std::move(arguments[i]);
      }
      if (!initialized(value, node.span))
        return std::nullopt;
      return value;
    }
    auto declaration = found.declaration;
    auto function = found.checkedFunction;
    if (declaration && !declaration->constFunction)
      return fail("constant", node.span,
                  "call to non-const function '" + displayPath(callee.text) +
                      "' in a constant expression");
    if (!function || !function->body)
      return unsupported(node.span, "this constant call");
    if (declaration && (declaration->variadic || declaration->destructor ||
                        declaration->foreignDeclaration))
      return unsupported(node.span, "this constant function effect");
    if (function->unsafeFunction && !unsafeDepth)
      return fail("unsafe", node.span,
                  "operation requires an unsafe block or unsafe function");
    if (frames.size() > options.callDepth)
      return fail("limit", node.span,
                  "const function call depth exceeded the limit of " +
                      std::to_string(options.callDepth));
    std::vector<Opt> bound(function->parameters.size());
    auto bind = [&](std::size_t slot, Value value, const Place &where,
                    Span span) {
      if (slot >= bound.size() || bound[slot])
        return fail("type", span, "invalid constant call argument"), false;
      const auto &parameter = function->parameters[slot];
      if (parameter.mode == ParameterMode::Read ||
          parameter.mode == ParameterMode::Mut) {
        const bool exclusive = parameter.mode == ParameterMode::Mut;
        if (value.kind != Value::Kind::Reference) {
          if (!where.value && !where.address) {
            frame().locals.emplace_back("<argument>", std::move(value),
                                        exclusive, nullptr);
            const auto &local = frame().locals.back();
            Place temporary{local.value.get(), local.value.get(), {},
                            exclusive,         local.name,        local.value};
            value = addressOf(temporary, exclusive);
          } else {
            if (exclusive && !where.mutableBinding)
              return fail("constant", span,
                          "constant exclusive argument requires a mutable "
                          "place"),
                     false;
            value = addressOf(where, exclusive);
          }
        }
        if (exclusive && !value.exclusive)
          return fail("constant", span,
                      "constant exclusive argument requires exclusive access"),
                 false;
        auto target = parameter.shape;
        value.type = host.referenceType(target.type, exclusive, false);
        value.exclusive = exclusive;
        if (target.kind == Shape::Kind::Array && target.count == UINT64_MAX) {
          auto source = pointee(value);
          if (where.value && where.value->kind == Value::Kind::Array)
            value.count = where.value->elements.size();
          (void)source;
        }
      } else {
        if (!coerce(value, parameter.shape, span))
          return false;
        if (parameter.mode == ParameterMode::Take && where.value)
          where.value->kind = Value::Kind::Uninitialized;
      }
      bound[slot] = std::move(value);
      return true;
    };
    if (receiver && !bind(0, std::move(*receiver), receiverPlace, callee.span))
      return std::nullopt;
    std::size_t position = receiver ? 1 : 0;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      auto slot = position++;
      const auto &argument = *node.children[i + 1];
      if (!argument.name.empty())
        slot = std::find_if(function->parameters.begin(),
                            function->parameters.end(),
                            [&](const auto &parameter) {
                              return parameter.name == argument.name;
                            }) -
               function->parameters.begin();
      if (!bind(slot, std::move(arguments[i]), places[i], argument.span))
        return std::nullopt;
    }
    frames.emplace_back();
    host.enter(*function);
    struct Restore {
      Interpreter &interpreter;
      unsigned unsafeDepth;
      Span span;
      ~Restore() {
        for (const auto &local : interpreter.frame().locals)
          interpreter.discard(*local.value, span);
        interpreter.unsafeDepth = unsafeDepth;
        interpreter.host.leave();
        interpreter.frames.pop_back();
      }
    } restore{*this, unsafeDepth, node.span};
    unsafeDepth = function->unsafeFunction ? 1 : 0;
    frame().inFunction = true;
    frame().callSpan = node.span;
    frame().result = function->result;
    for (std::size_t i = 0; i < bound.size(); ++i) {
      const auto &parameter = function->parameters[i];
      if (!bound[i]) {
        if (!parameter.defaultValue)
          return fail("type", node.span, "missing constant call argument");
        bound[i] = eval(*parameter.defaultValue, &parameter.shape);
        if (!bound[i] || !coerce(*bound[i], parameter.shape, node.span))
          return std::nullopt;
      }
      frame().locals.emplace_back(parameter.name, std::move(*bound[i]), false,
                                  parameter.context);
    }
    std::shared_ptr<Value> self;
    if (declaration && declaration->constructor) {
      frame().locals.emplace_back("self", uninitialized(function->result), true,
                                  declaration->lexicalContext);
      self = frame().locals.back().value;
    }
    auto value = eval(*function->body, declaration && declaration->constructor
                                           ? nullptr
                                           : &function->result);
    if (!value && !failed && signal == Signal::Return) {
      value = std::move(signalValue);
      signal = Signal::None;
    }
    if (value && self) {
      value = *self;
      self->kind = Value::Kind::Uninitialized;
    }
    if (!value || !initialized(*value, node.span) ||
        !coerce(*value, function->result, node.span))
      return std::nullopt;
    return value;
  }
  // A float type named directly or through an alias.
  Type floatingOwner(const Node &callee, std::size_t separator) {
    auto owner = builtinType(callee.text.substr(0, separator));
    if (owner != Type::Unknown || !callee.ownerGenericArguments.empty())
      return owner;
    TypeSyntax syntax;
    syntax.name = callee.text.substr(0, separator);
    syntax.context = callee.context;
    auto resolved = host.resolveType(syntax, callee.span);
    return isFloating(resolved) ? resolved : Type::Unknown;
  }
  Opt call(const Node &node, const Shape *want) {
    const Node &callee = *node.children[0];
    Type floating = Type::Unknown;
    if (callee.kind == Kind::Field) {
      floating = namedType(*callee.children[0]);
      if (!isFloating(floating)) {
        auto shape = placeShape(*callee.children[0]);
        if (shape)
          floating = shape->type;
      }
    } else if (callee.kind == Kind::Name) {
      auto separator = callee.text.rfind("::");
      if (separator != std::string::npos)
        floating = floatingOwner(callee, separator);
    }
    if (!isFloating(floating))
      return aggregateCall(node, want);
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
        // Only a float owner changes how the call evaluates; resolving any other
        // owner here would reject generic types named without arguments.
        owner = floatingOwner(callee, separator);
        method = callee.text.substr(separator + 2);
      }
      if (!isFloating(owner))
        found = lookup(callee);
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
    if (found.kind != Lookup::Kind::Function ||
        (!found.function && !found.checkedFunction))
      return fail("name", callee.span,
                  "unknown function '" + displayPath(callee.text) +
                      "' in a constant expression");
    if (found.function && found.checkedFunction)
      return fail("internal", callee.span,
                  "constant function lookup returned conflicting bodies");
    const bool unsafeFunction = found.checkedFunction
                                    ? found.checkedFunction->unsafeFunction
                                    : found.function->unsafeFunction;
    if (unsafeFunction && !unsafeDepth)
      return fail("unsafe", node.span,
                  "operation requires an unsafe block or unsafe function");
    CheckedFunction sourceFunction;
    const auto *declaration =
        found.function ? found.function : found.declaration;
    if (declaration) {
      const Function &function = *declaration;
      if (!function.constFunction)
        return fail("constant", node.span,
                    "call to non-const function '" + displayPath(callee.text) +
                        "' in a constant expression");
      if (!function.genericParameters.empty() || function.constructor ||
          (!function.owner.empty() && !receiver) || function.variadic ||
          function.explicitReceiver ||
          (!found.checkedFunction && !function.body.get()) ||
          function.destructor || function.foreignDeclaration)
        return unsupported(callee.span, "calling '" + displayPath(callee.text) +
                                            "' (generic, method or variadic "
                                            "const functions)");
    }
    if (frames.size() > options.callDepth)
      return fail("limit", node.span,
                  "const function call depth exceeded the limit of " +
                      std::to_string(options.callDepth) +
                      " (recursion without a base case?)");
    if (found.function) {
      const Function &function = *found.function;
      sourceFunction.body = function.body.get();
      sourceFunction.unsafeFunction = function.unsafeFunction;
      for (const auto &parameter : function.parameters) {
        if (parameter.mode == "mut" ||
            (parameter.pattern.has_value() &&
             parameter.pattern->kind != PatternKind::Binding))
          return unsupported(callee.span, "this parameter of '" +
                                              displayPath(callee.text) + "'");
        auto parameterShape = shape(parameter.annotation, parameter.span);
        if (!parameterShape)
          return std::nullopt;
        sourceFunction.parameters.push_back(
            {parameter.name, std::move(*parameterShape), parameter.span,
             parameter.defaultValue.get(), parameter.context});
      }
      if (!function.annotation.empty()) {
        auto resultShape = shape(function.annotation, function.span);
        if (!resultShape)
          return std::nullopt;
        sourceFunction.result = std::move(*resultShape);
      } else if (auto inferred = host.functionResult(function))
        sourceFunction.result = std::move(*inferred);
      else
        return unsupported(callee.span, "this inferred const function result");
    }
    if (found.checkedFunction && declaration) {
      for (const auto &parameter : declaration->parameters) {
        if (parameter.mode == "mut" ||
            (parameter.pattern.has_value() &&
             parameter.pattern->kind != PatternKind::Binding))
          return unsupported(callee.span, "this parameter of '" +
                                              displayPath(callee.text) + "'");
        if (!found.checkedFunction->body &&
            !shape(parameter.annotation, parameter.span))
          return std::nullopt;
      }
      if (!found.checkedFunction->body) {
        if (!declaration->annotation.empty()) {
          if (!shape(declaration->annotation, declaration->span))
            return std::nullopt;
        } else if (!host.functionResult(*declaration))
          return unsupported(callee.span,
                             "this inferred const function result");
      }
    }
    const auto &function =
        found.checkedFunction ? *found.checkedFunction : sourceFunction;
    if (!function.body)
      return fail("internal", callee.span,
                  "checked constant function has no body");
    const auto &result = function.result;
    std::vector<Opt> arguments(function.parameters.size());
    std::size_t position = receiver ? 1 : 0;
    if (receiver) {
      if (arguments.empty() ||
          !coerce(*receiver, function.parameters[0].shape, node.span))
        return std::nullopt;
      arguments[0] = std::move(*receiver);
    }
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      const Node &argument = *node.children[i];
      std::size_t slot = position;
      if (!argument.name.empty()) {
        auto named =
            std::find_if(function.parameters.begin(), function.parameters.end(),
                         [&](const CheckedFunction::Parameter &parameter) {
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
      auto value = eval(argument, &function.parameters[slot].shape);
      if (!value ||
          !coerce(*value, function.parameters[slot].shape, argument.span))
        return std::nullopt;
      arguments[slot] = std::move(value);
    }
    frames.emplace_back();
    struct RestoreCall {
      Interpreter &interpreter;
      unsigned unsafeDepth;
      ~RestoreCall() {
        interpreter.unsafeDepth = unsafeDepth;
        interpreter.frames.pop_back();
      }
    } restore{*this, unsafeDepth};
    unsafeDepth = function.unsafeFunction ? 1 : 0;
    frame().inFunction = true;
    frame().result = result;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      if (!arguments[i]) {
        const auto &parameter = function.parameters[i];
        if (!parameter.defaultValue)
          return fail("type", node.span,
                      "missing argument '" + parameter.name + "' in call to '" +
                          displayPath(callee.text) + "'");
        arguments[i] = eval(*parameter.defaultValue, &parameter.shape);
        if (!arguments[i] ||
            !coerce(*arguments[i], parameter.shape, parameter.span))
          return std::nullopt;
      }
      frame().locals.push_back({function.parameters[i].name,
                                std::move(*arguments[i]), false,
                                function.parameters[i].context});
    }
    auto value = eval(*function.body, &result);
    if (!value && !failed && signal == Signal::Return) {
      value = std::move(signalValue);
      signal = Signal::None;
    }
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
    auto checkedShape = host.expressionShape(node);
    if (checkedShape)
      want = &*checkedShape;
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
    case Kind::Text: {
      auto remaining = options.stepBudget - steps;
      auto found = host.literal(node, remaining);
      steps = options.stepBudget - remaining;
      if (found.kind == Lookup::Kind::Constant)
        return std::move(found.value);
      if (found.kind == Lookup::Kind::Failed) {
        failed = reported = true;
        return std::nullopt;
      }
      return unsupported(node.span, "this text literal");
    }
    case Kind::Unit:
      return unitValue();
    case Kind::None:
    case Kind::Variant: {
      Value value;
      value.kind = Value::Kind::Variant;
      value.type = want ? want->type : Type::Unknown;
      value.selection =
          node.kind == Kind::None || node.text == "success" ? 0 : 1;
      for (std::size_t i = 0; i < node.children.size(); ++i) {
        const Shape *payload = nullptr;
        if (want && want->kind == Shape::Kind::Variant &&
            std::size_t(value.selection) < want->variants.size() &&
            i < want->variants[value.selection].size())
          payload = &want->elements[want->variants[value.selection][i]];
        auto item = eval(*node.children[i], payload);
        if (!item)
          return std::nullopt;
        value.elements.push_back(std::move(*item));
      }
      return value;
    }
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
        if (namesLocal(*it, node)) {
          if (want && want->kind == Shape::Kind::Scalar &&
              it->value->kind == Value::Kind::Integer &&
              it->value->type == Type::Unknown &&
              !coerce(*it->value, *want, node.span))
            return std::nullopt;
          auto result = *it->value;
          if (want && want->kind != Shape::Kind::Reference &&
              result.kind != Value::Kind::Reference &&
              !host.copy(host.valueType(result)))
            it->value->kind = Value::Kind::Uninitialized;
          return result;
        }
      auto found = lookup(node);
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
        if (found.value.kind == Value::Kind::Function)
          return std::move(found.value);
        return unsupported(node.span, "a function used as a value");
      default:
        return fail("name", node.span,
                    "unknown name '" + displayPath(node.text) +
                        "' in a constant expression");
      }
    }
    case Kind::Unary: {
      if (node.text == "take") {
        auto where = place(*node.children[0]);
        if (where.value) {
          auto value = *where.value;
          where.value->kind = Value::Kind::Uninitialized;
          return value;
        }
        return eval(*node.children[0], want);
      }
      if (node.text == "read" || node.text == "mut") {
        auto where = place(*node.children[0]);
        if (!where.value && !where.address)
          return fail("constant", node.span,
                      "constant borrow requires a live place");
        if (node.text == "mut" && !where.mutableBinding)
          return fail("constant", node.span,
                      "constant exclusive borrow requires a mutable place");
        if (node.text == "mut" && where.address && !where.address->writable)
          return fail("constant", node.span,
                      "constant exclusive borrow requires writable provenance");
        auto value = addressOf(where, node.text == "mut");
        if (!validReference(value, node.span))
          return std::nullopt;
        return value;
      }
      if (node.text == "*") {
        auto pointer = eval(*node.children[0], nullptr);
        if (!pointer)
          return std::nullopt;
        if (pointer->kind == Value::Kind::Pointer && !unsafeDepth)
          return fail("unsafe", node.span,
                      "operation requires an unsafe block or unsafe function");
        if (pointer->kind != Value::Kind::Reference &&
            pointer->kind != Value::Kind::Pointer)
          return fail("type", node.span,
                      "constant dereference requires a pointer or view");
        return readAddress(*pointer, node.span);
      }
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
      Scope scope(*this, node.span);
      auto mark = frame().locals.size();
      auto value =
          condition(*node.children[0],
                    node.patterns.empty() ? nullptr : &node.patterns[0]);
      if (!value)
        return std::nullopt;
      if (truth(*value))
        return eval(*node.children[1], want);
      while (frame().locals.size() > mark) {
        discard(*frame().locals.back().value, node.span);
        frame().locals.pop_back();
      }
      if (node.children.size() > 2)
        return eval(*node.children[2], want);
      return unitValue();
    }
    case Kind::Condition:
    case Kind::ConditionChain:
      return condition(node);
    case Kind::Match:
      return matchExpression(node, want);
    case Kind::Throw: {
      auto value = eval(*node.children[0], nullptr);
      if (!value)
        return std::nullopt;
      signal = Signal::Throw;
      signalLabel.clear();
      signalValue = std::move(*value);
      return std::nullopt;
    }
    case Kind::Try: {
      auto value = eval(*node.children[0], nullptr);
      if (!value || host.operation(node).name != "try.outcome")
        return value;
      if (value->kind != Value::Kind::Variant || value->elements.size() != 1 ||
          (value->selection != 0 && value->selection != 1))
        return fail("internal", node.span,
                    "checked outcome propagation has an invalid value");
      if (value->selection == 0)
        return std::move(value->elements.front());
      signal = Signal::Throw;
      signalLabel.clear();
      signalValue = std::move(value->elements.front());
      return std::nullopt;
    }
    case Kind::Capture: {
      auto value = eval(*node.children[0], nullptr);
      if (!value && (failed || signal != Signal::Throw))
        return std::nullopt;
      if (!want || want->kind != Shape::Kind::Variant ||
          want->variants.size() != 2)
        return unsupported(node.span, "this typed capture result");
      Value captured;
      captured.kind = Value::Kind::Variant;
      captured.type = want->type;
      captured.selection = value ? 0 : 1;
      captured.elements.push_back(value ? std::move(*value)
                                        : std::move(signalValue));
      signal = Signal::None;
      return captured;
    }
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
      if (where.address)
        return readAddress(*where.address, node.span);
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
      if (where.address)
        return readAddress(*where.address, node.span);
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
          (index->type != Type::Unknown && index->type != Type::Usize &&
           index->type != Type::I32))
        return fail("type", node.children[1]->span,
                    "array index must be i32 or usize, found " +
                        describe(*index));
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

  std::optional<std::uint64_t> copyCost(const Value &value,
                                        std::uint64_t remaining) {
    if (!remaining)
      return std::nullopt;
    std::uint64_t cost = 1;
    for (const auto &element : value.elements) {
      auto nested = copyCost(element, remaining - cost);
      if (!nested)
        return std::nullopt;
      cost += *nested;
    }
    return cost;
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
      auto remaining = options.stepBudget - steps;
      auto cost = *count ? copyCost(*first, remaining / *count)
                         : std::optional<std::uint64_t>(0);
      if (!cost)
        return fail("limit", node.span,
                    "constant evaluation exceeded the step budget of " +
                        std::to_string(options.stepBudget) + " steps");
      steps += *count * *cost;
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
