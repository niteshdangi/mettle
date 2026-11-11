#include "semantics/checker.h"
#include <algorithm>
#include <limits>

namespace mettle {
using evaluation::Lookup;
using evaluation::Value;

namespace {
bool chargeConstant(const TypeStore &types, const StaticConstant &constant,
                    std::size_t &budget) {
  if (!budget)
    return false;
  --budget;
  if (constant.kind == StaticConstant::Kind::Repeat) {
    auto length = types.arrayLength(constant.type);
    if (!length || constant.fields.empty())
      return true;
    if (*length) {
      auto elementBudget = budget / *length;
      auto before = elementBudget;
      if (!chargeConstant(types, constant.fields.front(), elementBudget))
        return false;
      budget -= (before - elementBudget) * *length;
    }
  } else if (constant.kind == StaticConstant::Kind::Aggregate &&
             !types.isSum(constant.type))
    for (const auto &field : constant.fields)
      if (!chargeConstant(types, field, budget))
        return false;
  return true;
}
} // namespace

// Lets the evaluator read the checker's names and constants and report through
// its diagnostics.
class ConstantHost : public evaluation::Host {
public:
  explicit ConstantHost(Checker &checker) : checker(checker) {}
  void report(const std::string &phase, Span span,
              const std::string &message) override {
    checker.error(phase, span, message);
  }
  std::optional<evaluation::Shape> expressionShape(const Node &node) override {
    if (auto imported = checker.importedExpressions.find(&node);
        imported != checker.importedExpressions.end())
      return checker.constantShape(imported->second->facts.at(&node).type);
    auto found = checker.checked.find(node);
    if (found && found->type != Type::Unknown)
      return checker.constantShape(found->type);
    if (auto found = checker.nodeVariables.find(&node);
        found != checker.nodeVariables.end())
      return checker.constantShape(checker.inference.value(found->second));
    return std::nullopt;
  }
  std::optional<evaluation::Shape>
  functionResult(const Function &function) override {
    if (checker.facts(function).result == Type::Unknown)
      checker.inferFunctionResult(
          checker.module
              .functions[&function - checker.module.functions.data()]);
    return checker.constantShape(checker.facts(function).result);
  }
  Type resolveType(const TypeSyntax &syntax, Span span) override {
    if (auto imported = checker.importedAnnotations.find(&syntax);
        imported != checker.importedAnnotations.end())
      return imported->second;
    if (auto builtin = builtinType(syntax.name); builtin != Type::Unknown)
      return builtin;
    bool generic = checker.genericEnvironment &&
                   checker.genericEnvironment->names.contains(
                       checker.nameKey(syntax.name, syntax.context));
    if (!generic && !checker.checked.namespaces().lookup(
                        checker.nameModule(span, syntax.context), syntax.name,
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
                function.span, checker.accessModule(node))) {
          checker.error("name", node.span, "constant method is not accessible");
          result.kind = Lookup::Kind::Failed;
        } else {
          result.kind = Lookup::Kind::Function;
          if (checker.checked.importedDeclarations) {
            auto imported =
                checker.checked.importedDeclarations->functions.find(*selected);
            if (imported !=
                    checker.checked.importedDeclarations->functions.end() &&
                imported->second.body) {
              result.checkedFunction = &imported->second.evaluation;
              result.declaration = &function;
              return result;
            }
          }
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
  Lookup lookup(const Node &name, std::size_t &remaining) override {
    Lookup result;
    if (name.kind != Kind::Name)
      return result;
    if (auto imported = checker.importedExpressions.find(&name);
        imported != checker.importedExpressions.end()) {
      const auto &expression = *imported->second;
      const auto &facts = expression.facts.at(&name);
      if (auto constant = expression.constants.find(&name);
          constant != expression.constants.end()) {
        auto budget = remaining;
        if (!chargeConstant(checker.typeStore(), constant->second, budget)) {
          checker.error(
              "limit", name.span,
              "constant evaluation exceeded the aggregate size limit");
          result.kind = Lookup::Kind::Failed;
          return result;
        }
        auto value = checker.constantValueOf(constant->second);
        if (value) {
          remaining = budget;
          result.kind = Lookup::Kind::Constant;
          result.value = std::move(*value);
          return result;
        }
      }
      if (facts.callee >= 0) {
        const auto &imports = *checker.checked.importedDeclarations;
        auto function = imports.functions.find(facts.callee);
        result.kind = Lookup::Kind::Function;
        if (function != imports.functions.end() && function->second.body) {
          result.checkedFunction = &function->second.evaluation;
          result.declaration = &checker.module.functions.at(facts.callee);
        } else
          result.function = &checker.module.functions.at(facts.callee);
        return result;
      }
      if (facts.constantParameter != Type::Unknown)
        return carrier(facts.constantParameter);
      if (facts.variant >= 0 && enumeration(facts.type)) {
        const auto &variants = checker.typeStore().product(facts.type).variants;
        if (std::size_t(facts.variant) >= variants.size()) {
          checker.error("metadata", name.span,
                        "checked constant contains an invalid enum variant");
          result.kind = Lookup::Kind::Failed;
          return result;
        }
        result.kind = Lookup::Kind::Constant;
        result.value.kind = Value::Kind::Enum;
        result.value.type = facts.type;
        result.value.number.magnitude[0] = facts.variant;
        return result;
      }
      if (facts.numeric) {
        result.kind = Lookup::Kind::Constant;
        result.value.kind = isFloating(facts.type) ? Value::Kind::Floating
                                                   : Value::Kind::Integer;
        result.value.type = facts.type;
        result.value.number = *facts.numeric;
        return result;
      }
      if (facts.type != Type::Unknown)
        return result;
      checker.error("metadata", name.span,
                    "checked constant contains an unresolved external name");
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    auto separator = name.text.rfind("::");
    if (separator != std::string::npos) {
      TypeSyntax syntax;
      syntax.name = name.text.substr(0, separator);
      syntax.context = name.context;
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
    if (checker.genericEnvironment) {
      auto found = checker.genericEnvironment->names.find(
          checker.nameKey(name.text, name.context));
      if (found != checker.genericEnvironment->names.end() &&
          checker.typeStore().isConstant(found->second))
        return carrier(found->second);
    }
    if (auto storage = checker.staticName(name.text, name.span, name.context)) {
      if (checker.module.statics[*storage].mutableBinding)
        return failure("required initialization cannot read mutable storage");
      auto value = checker.staticValue(*storage);
      if (!value) {
        result.kind = Lookup::Kind::Failed;
        return result;
      }
      auto budget = remaining;
      if (!chargeConstant(checker.typeStore(), *value, budget)) {
        checker.error("limit", name.span,
                      "constant evaluation exceeded the aggregate size limit");
        result.kind = Lookup::Kind::Failed;
        return result;
      }
      auto converted = checker.constantValueOf(*value);
      if (!converted)
        return failure("storage of this type cannot be read in a constant "
                       "expression");
      remaining = budget;
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
    auto canonical =
        checker.callableName(name.text, "", name.span, name.context);
    if (auto function = checker.names.find(canonical);
        !canonical.empty() && function != checker.names.end()) {
      result.kind = Lookup::Kind::Function;
      if (checker.checked.importedDeclarations) {
        auto imported = checker.checked.importedDeclarations->functions.find(
            function->second);
        if (imported != checker.checked.importedDeclarations->functions.end() &&
            imported->second.body) {
          result.checkedFunction = &imported->second.evaluation;
          result.declaration = &checker.module.functions[function->second];
          return result;
        }
      }
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
    syntax.context = callee.context;
    ConstantHost host(*this);
    if (isFloating(host.resolveType(syntax, callee.span)))
      return true;
  }
  auto canonical = callableName(callee.text, "", callee.span, callee.context);
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
    if (!length || constant.fields.empty())
      return std::nullopt;
    if (!*length)
      return value;
    auto element = constantValueOf(constant.fields.front());
    if (!element)
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
