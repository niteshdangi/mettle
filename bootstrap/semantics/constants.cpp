#include "semantics/checker.h"
#include <algorithm>
#include <limits>

namespace mettle {
using evaluation::Lookup;
using evaluation::Value;

// Lets the evaluator read the checker's names and constants and report through
// its diagnostics.
class ConstantHost : public evaluation::Host {
public:
  explicit ConstantHost(Checker &checker) : checker(checker) {}
  void report(const std::string &phase, Span span,
              const std::string &message) override {
    checker.error(phase, span, message);
  }
  Type resolveType(const TypeSyntax &syntax, Span span) override {
    if (auto builtin = builtinType(syntax.name); builtin != Type::Unknown)
      return builtin;
    if (!checker.checked.namespaces().lookup(
            checker.checked.namespaces().moduleOf(span), syntax.name,
            resolution::Namespace::Type, span))
      return Type::Unknown;
    return checker.annotation(syntax, span);
  }
  bool enumeration(Type type) override {
    if (!checker.typeStore().isSum(type))
      return false;
    const auto &record = checker.typeStore().product(type);
    return std::all_of(
        record.variants.begin(), record.variants.end(),
        [](const auto &variant) { return variant.fields.empty(); });
  }
  Lookup variant(Type type, std::string_view name, Span) override {
    Lookup result;
    if (!enumeration(type))
      return result;
    const auto &record = checker.typeStore().product(type);
    for (std::size_t i = 0; i < record.variants.size(); ++i) {
      if (record.variants[i].name != name)
        continue;
      result.kind = Lookup::Kind::Constant;
      result.value.kind = Value::Kind::Enum;
      result.value.type = type;
      result.value.number.magnitude[0] = i;
      return result;
    }
    return result;
  }
  Lookup floatingValue(Type type, std::string_view name, Span) override {
    Lookup result;
    if (auto constant = checker.machineFloatingValue(type, name)) {
      result.kind = Lookup::Kind::Constant;
      result.value.kind = isFloating(constant->type) ? Value::Kind::Floating
                                                     : Value::Kind::Integer;
      result.value.type = constant->type;
      result.value.number = std::move(constant->literal);
    }
    return result;
  }
  Lookup method(Type type, const Node &node) override {
    Lookup result;
    auto before = checker.diagnostics.items.size();
    for (auto mode :
         {ParameterMode::Take, ParameterMode::Read, ParameterMode::Mut}) {
      auto selected =
          checker.receiverCandidate(type, mode, node.children[0]->text, node);
      if (selected) {
        const auto &function = checker.module.functions[*selected];
        if (!checker.checked.namespaces().accessible(
                function.span,
                checker.checked.namespaces().moduleOf(node.span))) {
          checker.error("name", node.span, "constant method is not accessible");
          result.kind = Lookup::Kind::Failed;
        } else {
          result.kind = Lookup::Kind::Function;
          result.function = &function;
        }
        return result;
      }
      if (checker.diagnostics.items.size() != before) {
        result.kind = Lookup::Kind::Failed;
        return result;
      }
    }
    return result;
  }
  Lookup lookup(const Node &name) override {
    Lookup result;
    if (name.kind != Kind::Name)
      return result;
    auto separator = name.text.rfind("::");
    if (separator != std::string::npos) {
      TypeSyntax syntax;
      syntax.name = name.text.substr(0, separator);
      auto type = resolveType(syntax, name.span);
      if (enumeration(type))
        return variant(type, name.text.substr(separator + 2), name.span);
      if (isFloating(type))
        return floatingValue(type, name.text.substr(separator + 2), name.span);
    }
    auto failure = [&](const std::string &message) {
      checker.error("constant", name.span, message);
      result.kind = Lookup::Kind::Failed;
      return result;
    };
    if (auto storage = checker.staticName(name.text, name.span)) {
      if (checker.module.statics[*storage].mutableBinding)
        return failure("required initialization cannot read mutable storage");
      auto value = checker.staticValue(*storage);
      if (!value) {
        result.kind = Lookup::Kind::Failed;
        return result;
      }
      auto converted = checker.constantValueOf(*value);
      if (!converted)
        return failure("storage of this type cannot be read in a constant "
                       "expression");
      result.kind = Lookup::Kind::Constant;
      result.value = std::move(*converted);
      return result;
    }
    if (auto primitive = checker.machineValue(name);
        primitive && checker.facts(name).numeric &&
        isNumeric(checker.inference.value(*primitive))) {
      result.kind = Lookup::Kind::Constant;
      result.value.kind = isFloating(checker.inference.value(*primitive))
                              ? Value::Kind::Floating
                              : Value::Kind::Integer;
      result.value.type = checker.inference.value(*primitive);
      result.value.number = *checker.facts(name).numeric;
      return result;
    }
    if (checker.genericEnvironment) {
      auto found = checker.genericEnvironment->names.find(name.text);
      if (found != checker.genericEnvironment->names.end() &&
          checker.typeStore().isConstant(found->second))
        return carrier(found->second);
    }
    auto canonical = checker.callableName(name.text, "", name.span);
    if (auto function = checker.names.find(canonical);
        !canonical.empty() && function != checker.names.end()) {
      result.kind = Lookup::Kind::Function;
      result.function = &checker.module.functions[function->second];
      return result;
    }
    auto reported = checker.reportedErrors;
    if (auto associated = checker.associatedConstant(name))
      return carrier(*associated);
    if (checker.reportedErrors != reported)
      result.kind = Lookup::Kind::Failed;
    return result;
  }

private:
  // A constant parameter or associated constant is concrete once its generic
  // arguments are bound.
  Lookup carrier(Type identity) {
    Lookup result;
    auto number = checker.typeStore().scalarConstantValue(identity);
    if (!number) {
      result.kind = Lookup::Kind::Symbolic;
      return result;
    }
    auto valueType = checker.typeStore().parameter(identity).valueType;
    result.kind = Lookup::Kind::Constant;
    result.value.kind = valueType == Type::Bool   ? Value::Kind::Bool
                        : valueType == Type::Char ? Value::Kind::Char
                                                  : Value::Kind::Integer;
    result.value.type = valueType;
    result.value.number = *number;
    return result;
  }
  Checker &checker;
};

std::optional<std::int32_t> Checker::constantInteger(const Node &node) {
  auto identity = constantType(node, Type::I32);
  if (identity == Type::Unknown)
    return std::nullopt;
  auto value = checked.types->constantValue(identity);
  if (!value || !isInteger(checked.types->parameter(identity).valueType) ||
      *value < std::numeric_limits<std::int32_t>::min() ||
      *value > std::numeric_limits<std::int32_t>::max()) {
    error("type", node.span,
          "required integer constant is outside the i32 range");
    return std::nullopt;
  }
  return static_cast<std::int32_t>(*value);
}

bool Checker::needsEvaluator(const Node &node) const {
  switch (node.kind) {
  case Kind::Integer:
  case Kind::Boolean:
  case Kind::Character:
  case Kind::Name:
    return false;
  case Kind::Group:
  case Kind::Binary:
    break;
  case Kind::Unary:
    if (node.text != "-" && node.text != "!")
      return true;
    break;
  default:
    return true;
  }
  return std::any_of(
      node.children.begin(), node.children.end(),
      [&](const NodeOwner &child) { return needsEvaluator(*child); });
}

bool Checker::constFunctionCall(const Node &node) {
  if (node.kind != Kind::Call || node.children.empty())
    return false;
  if (node.children[0]->kind == Kind::Field)
    return true;
  if (node.children[0]->kind != Kind::Name)
    return false;
  const auto &callee = *node.children[0];
  auto separator = callee.text.rfind("::");
  if (separator != std::string::npos) {
    TypeSyntax syntax;
    syntax.name = callee.text.substr(0, separator);
    ConstantHost host(*this);
    if (isFloating(host.resolveType(syntax, callee.span)))
      return true;
  }
  auto canonical = callableName(callee.text, "", callee.span);
  auto found = names.find(canonical);
  return !canonical.empty() && found != names.end() &&
         module.functions[found->second].constFunction;
}

Type Checker::evaluatedConstant(const Node &node, Type expected) {
  ConstantHost host(*this);
  evaluation::Options options;
  options.pointerBits = pointerBits();
  options.littleEndian = checked.targetDescription.littleEndian;
  options.numericEvaluator = numericEvaluator;
  options.unsafeContext = unsafeDepth != 0;
  evaluation::Expectation want;
  if (isInteger(expected) || expected == Type::Bool || expected == Type::Char)
    want.scalar = expected;
  auto result = evaluation::evaluate(host, options, node, want);
  if (result.symbolic) {
    error("type", node.span,
          "unsupported operation in required constant integer/scalar "
          "expression");
    return Type::Unknown;
  }
  if (!result.value)
    return Type::Unknown;
  const auto &value = *result.value;
  if (value.kind != Value::Kind::Integer && value.kind != Value::Kind::Bool &&
      value.kind != Value::Kind::Char) {
    error("type", node.span, "required constant must be a scalar value");
    return Type::Unknown;
  }
  return checked.types->constant(value.type, value.number);
}

std::optional<evaluation::Shape> Checker::constantShape(Type type) {
  evaluation::Shape shape;
  if (isNumeric(type) || type == Type::Bool || type == Type::Char) {
    shape.type = type;
    return shape;
  }
  if (type == Type::Unit) {
    shape.kind = evaluation::Shape::Kind::Unit;
    return shape;
  }
  if (checked.types->isSum(type)) {
    ConstantHost host(*this);
    if (!host.enumeration(type))
      return std::nullopt;
    shape.type = type;
    return shape;
  }
  if (!checked.types->isProduct(type))
    return std::nullopt;
  auto record = checked.types->product(type);
  if (record.kind == AggregateKind::Tuple) {
    shape.kind = evaluation::Shape::Kind::Tuple;
    for (const auto &field : record.fields) {
      auto element = constantShape(field.type);
      if (!element)
        return std::nullopt;
      shape.elements.push_back(std::move(*element));
    }
    return shape;
  }
  if (record.kind == AggregateKind::Array) {
    auto length = checked.types->arrayLength(type);
    auto element = constantShape(record.components[0]);
    if (!length || !element)
      return std::nullopt;
    shape.kind = evaluation::Shape::Kind::Array;
    shape.count = *length;
    shape.elements.push_back(std::move(*element));
    return shape;
  }
  return std::nullopt;
}

std::optional<Value> Checker::constantValueOf(const StaticConstant &constant) {
  Value value;
  if (constant.kind == StaticConstant::Kind::Scalar) {
    if (!isNumeric(constant.type) && constant.type != Type::Bool &&
        constant.type != Type::Char)
      return std::nullopt;
    value.kind = isFloating(constant.type)     ? Value::Kind::Floating
                 : constant.type == Type::Bool ? Value::Kind::Bool
                 : constant.type == Type::Char ? Value::Kind::Char
                                               : Value::Kind::Integer;
    value.type = constant.type;
    value.number = constant.scalar;
    return value;
  }
  if (constant.kind == StaticConstant::Kind::Aggregate &&
      checked.types->isSum(constant.type)) {
    ConstantHost host(*this);
    if (!host.enumeration(constant.type) || constant.selection < 0)
      return std::nullopt;
    value.kind = Value::Kind::Enum;
    value.type = constant.type;
    value.number.magnitude[0] = constant.selection;
    return value;
  }
  if ((constant.kind != StaticConstant::Kind::Aggregate &&
       constant.kind != StaticConstant::Kind::Repeat) ||
      !checked.types->isProduct(constant.type) ||
      checked.types->isSum(constant.type))
    return std::nullopt;
  auto record = checked.types->product(constant.type);
  value.type = Type::Unknown;
  if (record.kind == AggregateKind::Tuple)
    value.kind = Value::Kind::Tuple;
  else if (record.kind == AggregateKind::Array)
    value.kind = Value::Kind::Array;
  else
    return std::nullopt;
  if (constant.kind == StaticConstant::Kind::Repeat) {
    auto length = checked.types->arrayLength(constant.type);
    auto element = constantValueOf(constant.fields.front());
    if (!length || !element || *length > limits::constEvalSteps)
      return std::nullopt;
    value.elements.assign(static_cast<std::size_t>(*length), *element);
    return value;
  }
  for (const auto &field : constant.fields) {
    auto element = constantValueOf(field);
    if (!element)
      return std::nullopt;
    value.elements.push_back(std::move(*element));
  }
  return value;
}

std::optional<StaticConstant> Checker::staticFromValue(const Value &value,
                                                       Type type, Span span) {
  StaticConstant result;
  result.type = type;
  auto mismatch = [&]() -> std::optional<StaticConstant> {
    error("constant", span,
          "evaluated constant does not match the declared type");
    return std::nullopt;
  };
  switch (value.kind) {
  case Value::Kind::Integer:
  case Value::Kind::Floating:
  case Value::Kind::Bool:
  case Value::Kind::Char:
    if (value.type != type)
      return mismatch();
    result.scalar = value.number;
    return result;
  case Value::Kind::Enum: {
    if (value.type != type || !checked.types->isSum(type))
      return mismatch();
    const auto &record = checked.types->product(type);
    auto selection = value.number.magnitude[0];
    if (value.number.magnitude[1] || value.number.negative ||
        selection >= record.variants.size() ||
        !record.variants[selection].fields.empty())
      return mismatch();
    result.kind = StaticConstant::Kind::Aggregate;
    result.selection = static_cast<int>(selection);
    if (record.layout.kind != LayoutKind::Transparent) {
      StaticConstant tag;
      tag.type = record.layout.tag;
      tag.scalar = record.layout.discriminants.empty()
                       ? integerLiteral(static_cast<std::int64_t>(selection))
                       : record.layout.discriminants[selection];
      result.fields.push_back(std::move(tag));
    }
    return result;
  }
  case Value::Kind::Tuple:
  case Value::Kind::Array: {
    if (!checked.types->isProduct(type) || checked.types->isSum(type))
      return mismatch();
    auto record = checked.types->product(type);
    bool tuple = value.kind == Value::Kind::Tuple;
    if (record.kind != (tuple ? AggregateKind::Tuple : AggregateKind::Array) ||
        value.elements.size() !=
            (tuple ? record.fields.size()
                   : checked.types->arrayLength(type).value_or(~0ull)))
      return mismatch();
    result.kind = StaticConstant::Kind::Aggregate;
    for (std::size_t i = 0; i < value.elements.size(); ++i) {
      auto element = staticFromValue(
          value.elements[i],
          tuple ? record.fields[i].type : record.components[0], span);
      if (!element)
        return std::nullopt;
      result.fields.push_back(std::move(*element));
    }
    return result;
  }
  default:
    return mismatch();
  }
}

std::optional<StaticConstant> Checker::evaluatedStatic(const Node &node,
                                                       Type type) {
  auto shape = constantShape(type);
  if (!shape) {
    error("constant", node.span,
          "static initializer type is not supported by the constant "
          "evaluator");
    return std::nullopt;
  }
  ConstantHost host(*this);
  evaluation::Options options;
  options.pointerBits = pointerBits();
  options.littleEndian = checked.targetDescription.littleEndian;
  options.numericEvaluator = numericEvaluator;
  options.unsafeContext = unsafeDepth != 0;
  evaluation::Expectation want;
  want.shape = &*shape;
  auto result = evaluation::evaluate(host, options, node, want);
  if (result.symbolic) {
    error("constant", node.span,
          "static initializer depends on an unbound generic parameter");
    return std::nullopt;
  }
  if (!result.value)
    return std::nullopt;
  return staticFromValue(*result.value, type, node.span);
}

std::optional<Type> Checker::inherentConstantValue(std::size_t index,
                                                   Type subject) {
  auto &constant = inherentConstants.at(index);
  if (constant.state == 1) {
    error("constant", constant.declaration->span,
          "cycle in associated constant definition");
    return std::nullopt;
  }
  if (constant.state == 0) {
    constant.state = 1;
    auto *savedEnvironment = genericEnvironment;
    auto *savedFunction = current;
    auto savedUnsafeDepth = unsafeDepth;
    genericEnvironment = &implementationGenerics.at(constant.implementation);
    current = nullptr;
    unsafeDepth = 0;
    auto value = constant.declaration->constantValue
                     ? constantType(*constant.declaration->constantValue,
                                    constant.declaredType)
                     : Type::Unknown;
    if (value != Type::Unknown &&
        (!checked.types->isConstant(value) ||
         checked.types->parameter(value).valueType != constant.declaredType)) {
      error("type", constant.declaration->span,
            "associated constant value does not match its declared type");
      value = Type::Unknown;
    }
    constant.value = value;
    constant.state = 2;
    genericEnvironment = savedEnvironment;
    current = savedFunction;
    unsafeDepth = savedUnsafeDepth;
  }
  if (constant.value == Type::Unknown)
    return std::nullopt;

  std::vector<TypeBinding> bindings;
  if (checked.types->isProduct(constant.target) &&
      checked.types->isProduct(subject)) {
    const auto &pattern = checked.types->product(constant.target);
    const auto &actual = checked.types->product(subject);
    const auto &parameters =
        implementationGenerics.at(constant.implementation).parameters;
    for (std::size_t i = 0; i < pattern.genericArguments.size() &&
                            i < actual.genericArguments.size();
         ++i)
      if (std::find(parameters.begin(), parameters.end(),
                    pattern.genericArguments[i]) != parameters.end())
        bindings.push_back(
            {pattern.genericArguments[i], actual.genericArguments[i]});
  }
  return checked.types->substitute(constant.value, bindings);
}
} // namespace mettle
