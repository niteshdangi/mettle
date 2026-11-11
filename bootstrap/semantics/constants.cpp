#include "semantics/checker.h"
#include "types/layout.h"
#include <algorithm>
#include <deque>
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
  Type substitute(Type type) {
    for (auto context = contexts.rbegin(); context != contexts.rend();
         ++context)
      type = checker.typeStore().substitute(type, context->bindings);
    return type;
  }
  const NodeFacts *nodeFacts(const Node &node) {
    if (auto found = syntheticFacts.find(&node); found != syntheticFacts.end())
      return &found->second;
    if (auto imported = checker.importedExpressions.find(&node);
        imported != checker.importedExpressions.end())
      return &imported->second->facts.at(&node);
    return checker.checked.find(node);
  }
  const Node *receiver(const Node &node) override {
    auto facts = nodeFacts(node);
    if (!facts || !facts->receiverPlan || node.children.empty() ||
        node.children[0]->kind != Kind::Field)
      return nullptr;
    NodeOwner expression = NodeOwner::borrow(
        *const_cast<Node *>(node.children[0]->children[0].get()));
    bool projected = false;
    for (const auto &step : facts->receiverPlan->steps) {
      if (step.kind != ReceiverStep::Kind::Projection)
        continue;
      auto call = std::make_unique<Node>();
      call->kind = Kind::Call;
      call->span = node.children[0]->children[0]->span;
      auto callee = std::make_unique<Node>();
      callee->kind = Kind::Field;
      callee->text = "deref";
      callee->span = call->span;
      callee->children.push_back(std::move(expression));
      call->children.emplace_back(std::move(callee));
      auto &prepared = syntheticFacts[call.get()];
      prepared.callee = step.callee;
      prepared.type = step.resultView;
      prepared.typeArguments = step.typeArguments;
      prepared.interfaceSelf = step.interfaceSelf;
      prepared.interfaceType = step.interfaceType;
      prepared.interfaceMethod = step.interfaceMethod;
      expression = NodeOwner(std::move(call));
      projected = true;
    }
    if (!projected)
      return nullptr;
    receiverExpressions.push_back(std::move(expression));
    return receiverExpressions.back().get();
  }
  std::optional<evaluation::Shape> typeShape(Type type) override {
    return checker.constantShape(substitute(type));
  }
  Type referenceType(Type type, bool exclusive, bool pointer) override {
    auto mode = exclusive ? ParameterMode::Mut : ParameterMode::Read;
    return pointer ? checker.typeStore().pointerType(type, mode)
                   : checker.typeStore().viewType(type, mode);
  }
  Type valueType(const Value &value) override {
    if (value.type != Type::Unknown)
      return substitute(value.type);
    auto &types = checker.typeStore();
    if (value.kind == Value::Kind::Array) {
      auto element = value.elements.empty() ? Type::Unit
                                            : valueType(value.elements.front());
      return types.arrayType(
          element,
          types.constant(Type::Usize, integerLiteral(value.elements.size())));
    }
    if (value.kind == Value::Kind::Tuple) {
      std::vector<Type> elements;
      for (const auto &element : value.elements)
        elements.push_back(valueType(element));
      return types.structural(AggregateKind::Tuple, std::move(elements));
    }
    return value.kind == Value::Kind::Integer ? Type::I32 : value.type;
  }
  std::optional<Layout> layout(Type type) override {
    auto result = objectLayout(checker.typeStore(), substitute(type));
    if (!result)
      return std::nullopt;
    return Layout{result->size, result->alignment, result->fields};
  }
  bool needsDrop(Type type) override {
    return checker.typeStore().needsDrop(substitute(type));
  }
  bool copy(Type type) override {
    return checker.typeStore().isCopy(substitute(type));
  }
  std::optional<Value> storage(int symbol) override {
    auto value = checker.staticValue(symbol);
    return value ? checker.constantValueOf(*value) : std::nullopt;
  }
  Operation operation(const Node &node) override {
    if (auto facts = nodeFacts(node)) {
      if (!facts->machineOperation.empty())
        return {facts->machineOperation, substitute(facts->machineType),
                facts->field};
      if (facts->callee >= 0) {
        const auto &function = checker.module.functions.at(facts->callee);
        auto name = checker.definitionName(function.span, function.name);
        if (name == "core::panic::panic" ||
            name == "alloc::alloc::panic_precondition")
          return {"panic"};
      }
    }
    if (node.kind != Kind::Call)
      return {};
    const auto &callee = *node.children[0];
    if (callee.kind == Kind::Name) {
      auto text = callee.text;
      if (text.starts_with("core::ptr::"))
        return {"ptr." + text.substr(11)};
      if (text.starts_with("core::mem::"))
        return {"mem." + text.substr(11)};
    }
    return {};
  }
  void enter(const evaluation::CheckedFunction &function) override {
    Context context;
    context.previous = checker.genericEnvironment;
    context.bindings = function.bindings;
    if (function.declaration) {
      auto found = checker.functionGenerics.find(function.declaration);
      if (found != checker.functionGenerics.end())
        context.environment = found->second;
    }
    contexts.push_back(std::move(context));
    checker.genericEnvironment = &contexts.back().environment;
  }
  void leave() override {
    checker.genericEnvironment = contexts.back().previous;
    contexts.pop_back();
  }
  Lookup prepare(const Node &node, const Value *receiver,
                 std::span<const Value> arguments,
                 const evaluation::Shape *expected) override {
    Lookup result;
    auto &types = checker.typeStore();
    const auto &callee = *node.children[0];
    const Function *declaration = nullptr;
    auto facts = nodeFacts(node);
    auto typeArguments = facts ? facts->typeArguments : std::vector<Type>{};
    if (facts && facts->interfaceMethod >= 0) {
      const auto &database = checker.checked.interfaceDatabase();
      interfaces::Solver solver(types, database, checker.diagnostics, {}, {},
                                true);
      std::vector<RegionId> checkedRegions;
      solver.collectStaticRegions(&checkedRegions);
      auto self = types.eraseRegions(
          solver.normalize(substitute(facts->interfaceSelf), {}, node.span));
      auto interface =
          solver.normalize(substitute(facts->interfaceType), {}, node.span);
      const auto &definition =
          database.definitions[types.erased(interface).declaration];
      auto prefix =
          definition.methods[facts->interfaceMethod].implicitParameters;
      std::vector<Type> methodArguments;
      for (std::size_t i = prefix; i < typeArguments.size(); ++i)
        methodArguments.push_back(
            solver.normalize(substitute(typeArguments[i]), {}, node.span));
      auto selected = solver.method(self, interface, facts->interfaceMethod,
                                    methodArguments, node.span);
      if (!selected) {
        result.kind = Lookup::Kind::Failed;
        return result;
      }
      declaration = &checker.module.functions.at(selected->function);
      typeArguments = std::move(selected->arguments);
    } else if (facts && facts->callee >= 0)
      declaration = &checker.module.functions.at(facts->callee);
    Type constructed = Type::Unknown;
    if (!declaration && receiver) {
      auto type = valueType(*receiver);
      while (types.isView(type))
        type = types.view(type).payload;
      if (types.isProduct(type) &&
          types.product(type).kind == AggregateKind::Array)
        type = types.sliceType(types.product(type).components.front());
      auto found = method(type, node);
      declaration = found.function ? found.function : found.declaration;
      if (found.kind == Lookup::Kind::Failed)
        return found;
    }
    if (!declaration && callee.kind == Kind::Name) {
      std::size_t remaining = limits::constEvalSteps;
      auto found = lookup(callee, remaining);
      declaration = found.function ? found.function : found.declaration;
      if (found.kind == Lookup::Kind::Failed)
        return found;
      if (!declaration) {
        TypeSyntax syntax;
        syntax.name = callee.text;
        syntax.context = callee.context;
        syntax.arguments = callee.genericArguments;
        constructed = facts ? substitute(facts->type) : Type::Unknown;
        if (constructed == Type::Unknown && expected)
          constructed = expected->type;
        if (constructed == Type::Unknown)
          constructed = resolveType(syntax, callee.span);
        if (constructed != Type::Unknown && types.isProduct(constructed)) {
          auto origin = types.product(constructed).genericOrigin;
          if (origin == Type::Unknown)
            origin = constructed;
          if (auto candidates = checker.constructors.find(origin);
              candidates != checker.constructors.end())
            for (const auto &candidate : candidates->second) {
              const auto &function =
                  checker.module.functions[candidate.function];
              if (checker.constructorShapeMatches(function, node)) {
                declaration = &function;
                break;
              }
            }
          if (!declaration) {
            result.kind = Lookup::Kind::Constant;
            result.value.kind = Value::Kind::Product;
            result.value.type = constructed;
            return result;
          }
        }
      }
    }
    if (!declaration)
      return result;
    if (!checker.imported(declaration->span))
      checker.inferFunctionResult(
          checker.module
              .functions[declaration - checker.module.functions.data()]);
    result.kind = Lookup::Kind::Function;
    result.declaration = declaration;
    auto prepared = std::make_shared<evaluation::CheckedFunction>();
    prepared->declaration = declaration;
    prepared->unsafeFunction = declaration->unsafeFunction;
    auto foundEnvironment = checker.functionGenerics.find(declaration);
    if (foundEnvironment == checker.functionGenerics.end())
      return result;
    auto &environment = foundEnvironment->second;
    for (auto parameter : environment.parameters)
      prepared->bindings.push_back({parameter, Type::Unknown});
    for (std::size_t i = 0;
         i < typeArguments.size() && i < prepared->bindings.size(); ++i)
      prepared->bindings[i].argument = substitute(typeArguments[i]);
    if (typeArguments.empty())
      checker.explicitGenericBindings(*declaration, callee, environment,
                                      prepared->bindings, node.span);
    auto index = declaration - checker.module.functions.data();
    const auto &signature = checker.facts(*declaration);
    auto parameterType = [&](std::size_t slot) {
      auto type = signature.locals.at(slot).type;
      if (type == Type::Unknown) {
        auto variables =
            checker.localVariables.find(&checker.module.functions[index]);
        if (variables != checker.localVariables.end())
          type = checker.inference.value(variables->second.at(slot));
      }
      return type;
    };
    if (constructed != Type::Unknown)
      checker.inferGeneric(signature.result, constructed, prepared->bindings,
                           node.span);
    if (expected && expected->type != Type::Unknown)
      checker.inferFromExpected(signature.result, expected->type,
                                prepared->bindings);
    std::size_t positional = receiver ? 1 : 0;
    if (receiver && !signature.locals.empty()) {
      auto actual = valueType(*receiver);
      if (types.isView(actual))
        actual = types.view(actual).payload;
      auto pattern = parameterType(0);
      if (types.isProduct(actual) &&
          types.product(actual).kind == AggregateKind::Array &&
          types.isSlice(pattern))
        actual = types.sliceType(types.product(actual).components.front());
      checker.inferGeneric(pattern, actual, prepared->bindings, node.span);
    }
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      auto slot = positional++;
      const auto &argument = *node.children[i + 1];
      if (!argument.name.empty()) {
        auto found = std::find_if(declaration->parameters.begin(),
                                  declaration->parameters.end(),
                                  [&](const auto &parameter) {
                                    return parameter.name == argument.name;
                                  });
        slot = found - declaration->parameters.begin();
      }
      if (slot >= declaration->parameters.size() ||
          slot >= signature.locals.size())
        continue;
      auto actual = valueType(arguments[i]);
      auto pattern = parameterType(slot);
      if (types.isView(actual) && !types.isView(pattern))
        actual = types.view(actual).payload;
      checker.inferGeneric(pattern, actual, prepared->bindings, argument.span);
    }
    auto *previous = checker.genericEnvironment;
    checker.genericEnvironment = &environment;
    checker.completeGenericBindings(environment, prepared->bindings, node.span);
    checker.genericObligations(environment, prepared->bindings, node.span);
    checker.genericEnvironment = previous;
    auto concrete = [&](Type type) {
      return types.substitute(type, prepared->bindings);
    };
    auto resultShape = typeShape(concrete(signature.result));
    if (!resultShape)
      return result;
    prepared->result = std::move(*resultShape);
    prepared->body = declaration->body.get();
    const ImportedFunction *imported = nullptr;
    if (checker.checked.importedDeclarations) {
      auto found = checker.checked.importedDeclarations->functions.find(index);
      if (found != checker.checked.importedDeclarations->functions.end()) {
        imported = &found->second;
        if (imported->body)
          prepared->body = imported->body->syntax.get();
      }
    }
    for (std::size_t i = 0; i < declaration->parameters.size(); ++i) {
      const auto &parameter = declaration->parameters[i];
      auto shape = typeShape(concrete(parameterType(i)));
      if (!shape)
        return result;
      auto mode = parameter.mode == "mut"     ? ParameterMode::Mut
                  : parameter.mode == "read"  ? ParameterMode::Read
                  : parameter.mode == "take"  ? ParameterMode::Take
                  : types.isCopy(shape->type) ? ParameterMode::Value
                                              : ParameterMode::Read;
      const Node *defaultValue = parameter.defaultValue.get();
      if (imported && i < imported->defaults.size() && imported->defaults[i])
        defaultValue = imported->defaults[i]->syntax.get();
      prepared->parameters.push_back({parameter.name, std::move(*shape),
                                      parameter.span, defaultValue,
                                      parameter.context, mode});
    }
    result.prepared = std::move(prepared);
    result.checkedFunction = result.prepared.get();
    return result;
  }
  void report(const std::string &phase, Span span,
              const std::string &message) override {
    checker.error(phase, span, message);
  }
  std::optional<evaluation::Shape> expressionShape(const Node &node) override {
    if (auto found = syntheticFacts.find(&node); found != syntheticFacts.end())
      return typeShape(found->second.type);
    if (auto imported = checker.importedExpressions.find(&node);
        imported != checker.importedExpressions.end())
      return typeShape(imported->second->facts.at(&node).type);
    auto found = checker.checked.find(node);
    if (found && found->type != Type::Unknown)
      return typeShape(found->type);
    if (auto found = checker.nodeVariables.find(&node);
        found != checker.nodeVariables.end())
      return typeShape(checker.inference.value(found->second));
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
      return substitute(imported->second);
    const bool builtin = builtinType(syntax.name) != Type::Unknown;
    bool generic = checker.genericEnvironment &&
                   checker.genericEnvironment->names.contains(
                       checker.nameKey(syntax.name, syntax.context));
    if (syntax.form == TypeForm::Named && !syntax.name.empty() && !builtin &&
        !generic &&
        !checker.checked.namespaces().lookup(
            checker.nameModule(span, syntax.context), syntax.name,
            resolution::Namespace::Type, span))
      return Type::Unknown;
    return substitute(checker.annotation(syntax, span));
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
      result.staticSymbol = static_cast<int>(*storage);
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
  struct Context {
    Checker::GenericEnvironment environment;
    Checker::GenericEnvironment *previous = nullptr;
    std::vector<TypeBinding> bindings;
  };
  std::deque<Context> contexts;
  std::map<const Node *, NodeFacts> syntheticFacts;
  std::deque<NodeOwner> receiverExpressions;
  // A constant parameter or associated constant is concrete once its generic
  // arguments are bound.
  Lookup carrier(Type identity) {
    Lookup result;
    identity = substitute(identity);
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
  shape.type = type;
  if (checked.types->isView(type) || checked.types->isPointer(type)) {
    const auto &view = checked.types->view(type);
    evaluation::Shape element;
    element.type = view.payload;
    shape.kind = checked.types->isPointer(type)
                     ? evaluation::Shape::Kind::Pointer
                     : evaluation::Shape::Kind::Reference;
    shape.exclusive = view.mode == ParameterMode::Mut;
    shape.elements.push_back(std::move(element));
    return shape;
  }
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
    if (host.enumeration(type))
      return shape;
    shape.kind = evaluation::Shape::Kind::Variant;
    const auto record = checked.types->product(type);
    for (const auto &field : record.fields) {
      auto element = constantShape(field.type);
      if (!element)
        return std::nullopt;
      shape.elements.push_back(std::move(*element));
      shape.names.push_back(field.name);
    }
    for (const auto &variant : record.variants)
      shape.variants.emplace_back(variant.fields.begin(), variant.fields.end());
    return shape;
  }
  if (checked.types->isSlice(type)) {
    auto element = constantShape(checked.types->slice(type).element);
    if (!element)
      return std::nullopt;
    shape.kind = evaluation::Shape::Kind::Array;
    shape.count = UINT64_MAX;
    shape.elements.push_back(std::move(*element));
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
  if (record.kind == AggregateKind::Product) {
    shape.kind = evaluation::Shape::Kind::Product;
    for (const auto &field : record.fields) {
      auto element = constantShape(field.type);
      if (!element)
        return std::nullopt;
      shape.elements.push_back(std::move(*element));
      shape.names.push_back(field.name);
    }
    return shape;
  }
  return std::nullopt;
}

std::optional<Value> Checker::constantValueOf(const StaticConstant &constant) {
  Value value;
  if (constant.kind == StaticConstant::Kind::Address ||
      constant.kind == StaticConstant::Kind::Pointer) {
    if (!checked.types->isView(constant.type) &&
        !checked.types->isPointer(constant.type))
      return std::nullopt;
    value.kind = checked.types->isPointer(constant.type)
                     ? Value::Kind::Pointer
                     : Value::Kind::Reference;
    value.type = constant.type;
    value.exclusive =
        checked.types->view(constant.type).mode == ParameterMode::Mut;
    value.symbol = constant.symbol;
    value.offset = constant.byteOffset;
    value.count = constant.scalar.magnitude[0];
    value.addressOnly = constant.kind == StaticConstant::Kind::Pointer;
    if (value.addressOnly)
      value.offset = constant.scalar.magnitude[0];
    else {
      auto type = checked.staticStorage.at(constant.symbol).type;
      value.storageType = type;
      for (auto field : constant.projections) {
        auto layout = objectLayout(*checked.types, type);
        if (!layout || field >= layout->fields.size())
          return std::nullopt;
        value.offset += layout->fields[field];
        type = checked.types->product(type).fields.at(field).type;
      }
    }
    if (value.addressOnly)
      value.count = constant.fields.empty()
                        ? 0
                        : constant.fields.front().scalar.magnitude[0];
    return value;
  }
  if (constant.kind == StaticConstant::Kind::Scalar) {
    if (constant.type == Type::Unit)
      return value;
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
    if (constant.selection < 0)
      return std::nullopt;
    value.kind = host.enumeration(constant.type) ? Value::Kind::Enum
                                                 : Value::Kind::Variant;
    value.type = constant.type;
    value.number.magnitude[0] = constant.selection;
    value.selection = constant.selection;
    const auto &record = checked.types->product(constant.type);
    auto start = record.layout.kind == LayoutKind::Transparent ? 0 : 1;
    for (std::size_t i = start;
         value.kind == Value::Kind::Variant && i < constant.fields.size();
         ++i) {
      auto field = constantValueOf(constant.fields[i]);
      if (!field)
        return std::nullopt;
      value.elements.push_back(std::move(*field));
    }
    return value;
  }
  if ((constant.kind != StaticConstant::Kind::Aggregate &&
       constant.kind != StaticConstant::Kind::Repeat) ||
      !checked.types->isProduct(constant.type) ||
      checked.types->isSum(constant.type))
    return std::nullopt;
  auto record = checked.types->product(constant.type);
  value.type = constant.type;
  if (record.kind == AggregateKind::Tuple)
    value.kind = Value::Kind::Tuple;
  else if (record.kind == AggregateKind::Array)
    value.kind = Value::Kind::Array;
  else if (record.kind == AggregateKind::Product)
    value.kind = Value::Kind::Product;
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
  case Value::Kind::Unit:
    if (type != Type::Unit)
      return mismatch();
    return result;
  case Value::Kind::Reference:
  case Value::Kind::Pointer:
    if ((!checked.types->isView(type) && !checked.types->isPointer(type)) ||
        (value.addressOnly && value.kind == Value::Kind::Reference &&
         value.offset == 0))
      return mismatch();
    result.kind = value.addressOnly ? StaticConstant::Kind::Pointer
                                    : StaticConstant::Kind::Address;
    result.symbol = value.symbol;
    result.byteOffset = value.addressOnly ? 0 : value.offset;
    result.scalar.magnitude[0] = value.addressOnly ? value.offset : value.count;
    if (value.addressOnly &&
        checked.types->pointerMetadata(checked.types->view(type).payload) ==
            PointerMetadata::ElementCount) {
      StaticConstant count;
      count.type = Type::Usize;
      count.scalar = integerLiteral(value.count);
      result.fields.push_back(std::move(count));
    }
    if (!value.addressOnly && value.symbol < 0)
      return mismatch();
    return result;
  case Value::Kind::Variant: {
    if (!checked.types->isSum(type) || value.selection < 0)
      return mismatch();
    const auto record = checked.types->product(type);
    if (std::size_t(value.selection) >= record.variants.size())
      return mismatch();
    const auto &fields = record.variants[value.selection].fields;
    if (fields.size() != value.elements.size())
      return mismatch();
    result.kind = StaticConstant::Kind::Aggregate;
    result.selection = value.selection;
    if (record.layout.kind != LayoutKind::Transparent) {
      StaticConstant tag;
      tag.type = record.layout.tag;
      tag.scalar = record.layout.discriminants.empty()
                       ? integerLiteral(value.selection)
                       : record.layout.discriminants[value.selection];
      result.fields.push_back(std::move(tag));
    }
    for (std::size_t i = 0; i < fields.size(); ++i) {
      auto field = staticFromValue(value.elements[i],
                                   record.fields[fields[i]].type, span);
      if (!field)
        return std::nullopt;
      result.fields.push_back(std::move(*field));
    }
    return result;
  }
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
  case Value::Kind::Array:
  case Value::Kind::Product: {
    if (!checked.types->isProduct(type) || checked.types->isSum(type))
      return mismatch();
    auto record = checked.types->product(type);
    bool tuple = value.kind != Value::Kind::Array;
    auto kind = value.kind == Value::Kind::Product ? AggregateKind::Product
                : tuple                            ? AggregateKind::Tuple
                                                   : AggregateKind::Array;
    if (record.kind != kind ||
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
