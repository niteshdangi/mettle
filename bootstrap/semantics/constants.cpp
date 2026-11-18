#include "semantics/checker.h"
#include "support/limits.h"
#include "types/layout.h"
#include "types/machine.h"
#include <algorithm>
#include <deque>
#include <limits>

namespace mettle {
using evaluation::Lookup;
using evaluation::Value;

namespace {
NumericLiteral enumDiscriminant(const TypeStore &types, Type type,
                                std::size_t selection) {
  const auto &values = types.product(type).layout.discriminants;
  return values.empty() ? integerLiteral(selection) : values.at(selection);
}
bool chargeConstant(const TypeStore &types, const StaticConstant &constant,
                    std::size_t &budget) {
  if (!budget)
    return false;
  --budget;
  if (constant.kind == StaticConstant::Kind::Text) {
    if (constant.text.size() > budget)
      return false;
    budget -= constant.text.size();
  } else if (constant.kind == StaticConstant::Kind::Repeat) {
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
  } else if (constant.kind == StaticConstant::Kind::Aggregate)
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
  explicit ConstantHost(Checker &checker,
                        std::span<const TypeBinding> bindings = {})
      : originalEnvironment(checker.genericEnvironment), checker(checker) {
    if (bindings.empty() || !checker.genericEnvironment)
      return;
    Context context;
    context.previous = checker.genericEnvironment;
    context.environment = *checker.genericEnvironment;
    context.bindings.assign(bindings.begin(), bindings.end());
    bind(context);
    contexts.push_back(std::move(context));
    checker.genericEnvironment = &contexts.back().environment;
  }
  ~ConstantHost() override { checker.genericEnvironment = originalEnvironment; }
  Type substitute(Type type) {
    for (auto context = contexts.rbegin(); context != contexts.rend();
         ++context)
      type = checker.typeStore().substitute(type, context->bindings);
    return type;
  }
  const NodeFacts *nodeFacts(const Node &node) {
    if (auto found = syntheticFacts.find(&node); found != syntheticFacts.end())
      return &found->second;
    if (auto imported = checker.importedExpression(node))
      return &imported->facts.at(&node);
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
      if (step.kind == ReceiverStep::Kind::Borrow) {
        auto view = std::make_unique<Node>();
        view->kind = Kind::Unary;
        view->text = step.mode == ParameterMode::Mut ? "mut" : "read";
        view->span = node.children[0]->children[0]->span;
        view->children.push_back(std::move(expression));
        syntheticFacts[view.get()].type = step.target;
        expression = NodeOwner(std::move(view));
        projected = true;
        continue;
      }
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
    if (auto shape = concreteShape(substitute(type)))
      return shape->shape;
    return std::nullopt;
  }
  bool project(Type type, std::size_t field, const Node &node) override {
    if (auto facts = nodeFacts(node); facts && facts->field >= 0)
      return true;
    return checker.visibleField(substitute(type), field, node.span,
                                node.context);
  }
  Type referenceType(Type type, bool exclusive, bool pointer) override {
    auto mode = exclusive ? ParameterMode::Mut : ParameterMode::Read;
    return pointer ? checker.typeStore().pointerType(type, mode)
                   : checker.typeStore().viewType(type, mode);
  }
  bool pointerCastAllowed(Type source, Type target) override {
    return machineCastAllowed(checker.typeStore(), substitute(source),
                              substitute(target));
  }
  bool callableCoercion(Type source, Type target) override {
    return checker.compatibleCallable(substitute(source), substitute(target));
  }
  std::string typeIdentity(Type type) override {
    return mettle::typeIdentity(checker.typeStore(), substitute(type));
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
  // A type's stored destructor index is local to the module that declared it,
  // so the declaration is found through its owner type.
  const Function *destructorOf(Type origin) {
    if (auto cached = destructorCache.find(origin);
        cached != destructorCache.end())
      return cached->second;
    if (checker.checked.importedDeclarations &&
        checker.checked.importedDeclarations->catalog)
      if (auto native =
              checker.checked.importedDeclarations->catalog->destructor(
                  checker.checked.types->product(origin).name))
        return destructorCache
            .emplace(origin, &checker.module.functions[*native])
            .first->second;
    const Function *found = nullptr;
    for (const auto &function : checker.module.functions.localHeaders()) {
      if (!function.destructor)
        continue;
      auto name = checker.typeName(function.owner, function.span);
      if (auto type = checker.typeNames.find(name);
          type != checker.typeNames.end() && type->second == origin) {
        found = &function;
        break;
      }
    }
    return destructorCache.emplace(origin, found).first->second;
  }
  Lookup destructor(Type type, Span) override {
    Lookup result;
    auto &types = checker.typeStore();
    type = substitute(type);
    if (!types.isProduct(type))
      return result;
    auto origin = types.product(type).genericOrigin;
    if (origin == Type::Unknown)
      origin = type;
    if (!types.product(origin).hasDestructor)
      return result;
    result.kind = Lookup::Kind::Failed;
    const Function *declaration = destructorOf(origin);
    if (!declaration)
      return result;
    if (checker.imported(declaration->span))
      checker.functionEnvironment(*declaration);
    auto foundEnvironment = checker.functionGenerics.find(declaration);
    if (foundEnvironment == checker.functionGenerics.end())
      return result;
    auto prepared = std::make_shared<evaluation::CheckedFunction>();
    prepared->declaration = declaration;
    const auto &arguments = types.product(type).genericArguments;
    if (foundEnvironment->second.parameters.size() != arguments.size())
      return result;
    for (std::size_t i = 0; i < arguments.size(); ++i)
      prepared->bindings.push_back(
          {foundEnvironment->second.parameters[i], arguments[i]});
    auto shape = typeShape(type);
    auto unit = typeShape(Type::Unit);
    if (!shape || !unit)
      return result;
    prepared->result = std::move(*unit);
    prepared->body = declaration->body.get();
    if (checker.checked.importedDeclarations) {
      auto imported = checker.checked.importedDeclarations->functions.find(
          checker.module.functions.indexOf(declaration));
      if (imported != checker.checked.importedDeclarations->functions.end() &&
          imported->second->body)
        prepared->body =
            checker.importExpression(imported->second->body).syntax.get();
    }
    if (!prepared->body)
      return result;
    prepared->parameters.push_back(
        {"self", std::move(*shape), declaration->span, nullptr,
         declaration->lexicalContext, ParameterMode::Mut});
    result.kind = Lookup::Kind::Function;
    result.declaration = declaration;
    result.prepared = std::move(prepared);
    result.checkedFunction = result.prepared.get();
    return result;
  }
  bool copy(Type type) override {
    return checker.typeStore().isCopy(substitute(type));
  }
  Lookup storage(int symbol, std::size_t &remaining) override {
    Lookup result;
    auto value = checker.staticValue(symbol);
    if (!value) {
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    auto budget = remaining;
    if (!chargeConstant(checker.typeStore(), *value, budget)) {
      checker.error("limit", checker.module.statics.at(symbol).span,
                    "constant evaluation exceeded the aggregate size limit");
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    if (auto converted = checker.constantValueOf(*value, *this)) {
      remaining = budget;
      result.kind = Lookup::Kind::Constant;
      result.value = std::move(*converted);
    }
    return result;
  }
  std::shared_ptr<Value> literalStorage(std::string_view bytes) override {
    auto [found, inserted] = literalRoots.try_emplace(std::string(bytes));
    if (inserted) {
      auto root = std::make_shared<Value>();
      root->kind = Value::Kind::Array;
      root->type = checker.typeStore().arrayType(
          Type::U8, checker.typeStore().constant(Type::Usize,
                                                 integerLiteral(bytes.size())));
      root->immutableLiteral = true;
      root->elements.reserve(bytes.size());
      for (unsigned char byte : bytes) {
        Value element;
        element.kind = Value::Kind::Integer;
        element.type = Type::U8;
        element.number = integerLiteral(byte);
        root->elements.push_back(std::move(element));
      }
      found->second = std::move(root);
    }
    return found->second;
  }
  Lookup literal(const Node &node, std::size_t &remaining) override {
    Lookup result;
    auto errors = checker.diagnostics.count();
    auto type = checker.textLiteralType(node);
    if (type == Type::Unknown || checker.diagnostics.count() != errors) {
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    StaticConstant constant;
    constant.kind = StaticConstant::Kind::Text;
    constant.type = type;
    constant.text = checker.facts(node).text;
    if (constant.text.size() >
        integerMaximum(Type::Isize, checker.pointerBits()).magnitude[0]) {
      checker.error("limit", node.span,
                    "literal backing exceeds target address space");
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    auto budget = remaining;
    if (!chargeConstant(checker.typeStore(), constant, budget)) {
      checker.error("limit", node.span,
                    "constant evaluation exceeded the aggregate size limit");
      result.kind = Lookup::Kind::Failed;
    } else if (auto value = checker.constantValueOf(constant, *this)) {
      remaining = budget;
      result.kind = Lookup::Kind::Constant;
      result.value = std::move(*value);
    }
    return result;
  }
  Operation operation(const Node &node) override {
    if (auto facts = nodeFacts(node)) {
      if (node.kind == Kind::Try && facts->outcomePropagation)
        return {"try.outcome"};
      if (!facts->machineOperation.empty())
        return {facts->machineOperation, substitute(facts->machineType),
                facts->field, facts->argumentOrder};
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
    context.declaration = function.declaration;
    if (function.declaration) {
      if (checker.imported(function.declaration->span))
        checker.functionEnvironment(*function.declaration);
      auto found = checker.functionGenerics.find(function.declaration);
      if (found != checker.functionGenerics.end())
        context.environment = found->second;
    }
    bind(context);
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
    if (facts && facts->variant >= 0) {
      auto type = substitute(facts->type);
      if (types.isSum(type)) {
        const auto &record = types.product(type);
        if (std::size_t(facts->variant) >= record.variants.size()) {
          checker.error("metadata", node.span,
                        "checked constant contains an invalid enum variant");
          result.kind = Lookup::Kind::Failed;
          return result;
        }
        result.kind = Lookup::Kind::Constant;
        result.value.kind =
            enumeration(type) ? Value::Kind::Enum : Value::Kind::Variant;
        result.value.type = type;
        result.value.selection = facts->variant;
        result.value.number = enumDiscriminant(types, type, facts->variant);
        return result;
      }
    }
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
      declaration = checker.resolvedCall(facts);
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
      if (found.kind == Lookup::Kind::Constant)
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
      checker.inferFunctionResult(checker.module.functions.edit(
          checker.module.functions.indexOf(declaration)));
    result.kind = Lookup::Kind::Function;
    result.declaration = declaration;
    auto prepared = std::make_shared<evaluation::CheckedFunction>();
    prepared->declaration = declaration;
    prepared->unsafeFunction = declaration->unsafeFunction;
    if (checker.imported(declaration->span))
      checker.functionEnvironment(*declaration);
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
    auto index = checker.module.functions.indexOf(declaration);
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
        imported = found->second.get();
        if (imported->body)
          prepared->body =
              checker.importExpression(imported->body).syntax.get();
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
        defaultValue =
            checker.importExpression(imported->defaults[i]).syntax.get();
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
    if (auto imported = checker.importedExpression(node))
      return typeShape(imported->facts.at(&node).type);
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
      checker.inferFunctionResult(checker.module.functions.edit(
          checker.module.functions.indexOf(&function)));
    if (auto shape = concreteShape(checker.facts(function).result))
      return shape->shape;
    return std::nullopt;
  }
  Type resolveType(const TypeSyntax &syntax, Span span) override {
    if (auto imported = checker.importedAnnotation(syntax))
      return substitute(*imported);
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
    // A bare generic type name used as a path owner names no concrete type.
    if (syntax.form == TypeForm::Named && syntax.arguments.empty() &&
        !generic && !builtin && syntax.name != "Self")
      for (const auto *product : checker.productsNamed(
               checker.typeName(syntax.name, span, {}, syntax.context)))
        if (!checker.typeEnvironment(*product).parameters.empty())
          return Type::Unknown;
    return substitute(checker.annotation(syntax, span));
  }
  Type resolveAlias(const TypeSyntax &syntax, Span span) override {
    auto canonical = checker.checked.namespaces().lookup(
        checker.nameModule(span, syntax.context), syntax.name,
        resolution::Namespace::Type, span);
    if (!canonical || !checker.aliases.contains(*canonical))
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
    if (!checker.typeStore().isSum(type))
      return result;
    const auto &record = checker.typeStore().product(type);
    for (std::size_t i = 0; i < record.variants.size(); ++i) {
      if (record.variants[i].name != name)
        continue;
      result.kind = Lookup::Kind::Constant;
      result.value.kind =
          enumeration(type) ? Value::Kind::Enum : Value::Kind::Variant;
      result.value.type = type;
      result.value.selection = i;
      result.value.number = enumDiscriminant(checker.typeStore(), type, i);
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
                imported->second->body) {
              result.checkedFunction =
                  &checker.evaluationContract(*imported->second);
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
    auto functionLookup = [&](const Function &function) {
      Lookup found;
      found.kind = Lookup::Kind::Function;
      auto index = checker.module.functions.indexOf(&function);
      found.value = functionValue(index);
      if (checker.checked.importedDeclarations) {
        auto imported =
            checker.checked.importedDeclarations->functions.find(index);
        if (imported != checker.checked.importedDeclarations->functions.end() &&
            imported->second->body) {
          found.checkedFunction =
              &checker.evaluationContract(*imported->second);
          found.declaration = &function;
          return found;
        }
      }
      found.function = &function;
      return found;
    };
    auto materialized = [&](const StaticConstant &constant,
                            bool fresh = false) {
      Lookup found;
      auto budget = remaining;
      if (!chargeConstant(checker.typeStore(), constant, budget)) {
        checker.error("limit", name.span,
                      "constant evaluation exceeded the aggregate size limit");
        found.kind = Lookup::Kind::Failed;
        return found;
      }
      if (auto value = checker.constantValueOf(constant, *this)) {
        remaining = budget;
        found.kind = Lookup::Kind::Constant;
        found.value = std::move(*value);
        found.freshValue = fresh;
      }
      return found;
    };
    if (auto imported = checker.importedExpression(name)) {
      const auto &expression = *imported;
      const auto &facts = expression.facts.at(&name);
      if (facts.slot >= 0 && !contexts.empty() && contexts.back().declaration) {
        const auto &locals = checker.facts(*contexts.back().declaration).locals;
        if (static_cast<std::size_t>(facts.slot) < locals.size() &&
            locals[facts.slot].storage == StorageDuration::Static) {
          const auto &local = locals[facts.slot];
          if (local.mutableBinding) {
            checker.error(
                "constant", name.span,
                "required initialization cannot read mutable storage");
            result.kind = Lookup::Kind::Failed;
            return result;
          }
          auto found = storage(local.staticIndex, remaining);
          found.staticSymbol = local.staticIndex;
          return found;
        }
      }
      if (auto constant = expression.constants.find(&name);
          constant != expression.constants.end()) {
        auto value = materialized(constant->second);
        if (value.kind != Lookup::Kind::Missing)
          return value;
      }
      if (facts.constantValue)
        return materialized(*facts.constantValue, true);
      if (facts.callee >= 0) {
        if (auto function = checker.resolvedCall(&facts))
          return functionLookup(*function);
      }
      if (facts.constantParameter != Type::Unknown) {
        auto identity = substitute(facts.constantParameter);
        if (checker.typeStore().isProjection(identity)) {
          auto reported = checker.reportedErrors;
          if (auto associated = checker.associatedConstant(name))
            return carrier(*associated);
          if (checker.reportedErrors != reported) {
            result.kind = Lookup::Kind::Failed;
            return result;
          }
        }
        return carrier(identity);
      }
      if (facts.variant >= 0 &&
          checker.typeStore().isSum(substitute(facts.type))) {
        auto type = substitute(facts.type);
        const auto &variants = checker.typeStore().product(type).variants;
        if (std::size_t(facts.variant) >= variants.size()) {
          checker.error("metadata", name.span,
                        "checked constant contains an invalid enum variant");
          result.kind = Lookup::Kind::Failed;
          return result;
        }
        result.kind = Lookup::Kind::Constant;
        result.value.kind =
            enumeration(type) ? Value::Kind::Enum : Value::Kind::Variant;
        result.value.type = type;
        result.value.selection = facts.variant;
        result.value.number =
            enumDiscriminant(checker.typeStore(), type, facts.variant);
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
      if (facts.type != Type::Unknown &&
          checker.typeStore().isProduct(substitute(facts.type))) {
        auto reported = checker.reportedErrors;
        if (auto associated = checker.associatedConstant(name))
          return carrier(*associated);
        if (auto local = checker.checked.find(name);
            local && local->constantValue)
          return materialized(*local->constantValue, true);
        if (checker.reportedErrors != reported)
          result.kind = Lookup::Kind::Failed;
        if (result.kind != Lookup::Kind::Missing)
          return result;
      }
      if (facts.type != Type::Unknown)
        return result;
      checker.error("metadata", name.span,
                    "checked constant contains an unresolved external name");
      result.kind = Lookup::Kind::Failed;
      return result;
    }
    if (auto facts = checker.checked.find(name); facts && facts->callee >= 0)
      if (auto function = checker.resolvedCall(facts))
        return functionLookup(*function);
    auto separator = name.text.rfind("::");
    if (separator != std::string::npos) {
      TypeSyntax syntax;
      syntax.name = name.text.substr(0, separator);
      syntax.context = name.context;
      syntax.arguments = name.ownerGenericArguments;
      auto type = resolveType(syntax, name.span);
      if (checker.typeStore().isSum(type)) {
        auto found = variant(type, name.text.substr(separator + 2), name.span);
        if (found.kind != Lookup::Kind::Missing)
          return found;
      } else if (isFloating(type)) {
        auto found =
            floatingValue(type, name.text.substr(separator + 2), name.span);
        if (found.kind != Lookup::Kind::Missing)
          return found;
      }
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
      auto converted = checker.constantValueOf(*value, *this);
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
      return functionLookup(checker.module.functions[function->second]);
    }
    auto reported = checker.reportedErrors;
    if (auto associated = checker.associatedConstant(name))
      return carrier(*associated);
    if (auto facts = checker.checked.find(name); facts && facts->constantValue)
      return materialized(*facts->constantValue, true);
    if (checker.reportedErrors != reported)
      result.kind = Lookup::Kind::Failed;
    return result;
  }

private:
  struct CachedShape {
    evaluation::Shape shape;
    unsigned height = 0;
    bool ready = false;
  };
  bool productShapeComplete(Type type) {
    auto &types = checker.typeStore();
    const auto &product = types.product(type);
    auto origin = type;
    unsigned depth = 0;
    while (true) {
      if (depth++ > limits::typeDepth)
        return false;
      const auto &record = types.product(origin);
      auto next = record.regionOrigin != Type::Unknown ? record.regionOrigin
                                                       : record.genericOrigin;
      if (next == Type::Unknown)
        break;
      if (!types.isProduct(next))
        return false;
      origin = next;
    }
    for (const auto *declaration :
         checker.productsNamed(types.product(origin).name)) {
      if (checker.imported(declaration->span))
        continue;
      if (!declaration->enumeration)
        return product.fields.size() == declaration->fields.size();
      if (product.variants.size() != declaration->variants.size())
        return false;
      std::size_t fields = 1;
      for (std::size_t i = 0; i < declaration->variants.size(); ++i) {
        if (product.variants[i].fields.size() !=
            declaration->variants[i].fields.size())
          return false;
        fields += declaration->variants[i].fields.size();
      }
      return product.fields.size() == fields;
    }
    return true;
  }
  const CachedShape *concreteShape(Type type, unsigned depth = 0) {
    auto [found, inserted] = shapes.try_emplace(type);
    auto &cached = found->second;
    if (!inserted) {
      if (!cached.ready ||
          (cached.height && (depth > limits::typeDepth ||
                             cached.height - 1 > limits::typeDepth - depth)))
        return nullptr;
      return &cached;
    }
    struct Restore {
      std::map<Type, CachedShape> &shapes;
      std::map<Type, CachedShape>::iterator found;
      ~Restore() {
        if (!found->second.ready)
          shapes.erase(found);
      }
    } restore{shapes, found};
    auto &types = checker.typeStore();
    const auto aggregate = types.isProduct(type) || types.isSlice(type);
    if (aggregate && (depth > limits::typeDepth ||
                      (types.isProduct(type) && !productShapeComplete(type))))
      return nullptr;
    unsigned height = aggregate ? 1 : 0;
    auto shape = buildShape(type, depth, height);
    if (!shape)
      return nullptr;
    cached.shape = std::move(*shape);
    cached.height = height;
    cached.ready = true;
    return &cached;
  }
  std::optional<evaluation::Shape> buildShape(Type type, unsigned depth,
                                              unsigned &height) {
    using Shape = evaluation::Shape;
    auto &types = checker.typeStore();
    Shape shape;
    shape.type = type;
    if (types.isView(type) || types.isPointer(type)) {
      const auto &view = types.view(type);
      Shape element;
      element.type = view.payload;
      shape.kind =
          types.isPointer(type) ? Shape::Kind::Pointer : Shape::Kind::Reference;
      shape.exclusive = view.mode == ParameterMode::Mut;
      shape.aggregate = std::make_shared<const Shape::Aggregate>(
          Shape::Aggregate{{std::move(element)}, {}, {}});
      return shape;
    }
    if (isNumeric(type) || type == Type::Bool || type == Type::Char ||
        types.isFunctionPointer(type) || enumeration(type))
      return shape;
    if (type == Type::Unit) {
      shape.kind = Shape::Kind::Unit;
      return shape;
    }
    if (types.isSlice(type)) {
      auto element = concreteShape(types.slice(type).element, depth + 1);
      if (!element)
        return std::nullopt;
      shape.kind = Shape::Kind::Array;
      shape.count = UINT64_MAX;
      height = std::max(height, element->height + 1);
      shape.aggregate = std::make_shared<const Shape::Aggregate>(
          Shape::Aggregate{{element->shape}, {}, {}});
      return shape;
    }
    if (!types.isProduct(type))
      return std::nullopt;
    const auto &record = types.product(type);
    if (record.kind == AggregateKind::Array) {
      auto length = types.arrayLength(type);
      auto element = concreteShape(record.components[0], depth + 1);
      if (!length || !element)
        return std::nullopt;
      shape.kind = Shape::Kind::Array;
      shape.count = *length;
      height = std::max(height, element->height + 1);
      shape.aggregate = std::make_shared<const Shape::Aggregate>(
          Shape::Aggregate{{element->shape}, {}, {}});
      return shape;
    }
    if (types.isSum(type))
      shape.kind = Shape::Kind::Variant;
    else if (record.kind == AggregateKind::Tuple)
      shape.kind = Shape::Kind::Tuple;
    else if (record.kind == AggregateKind::Product ||
             record.kind == AggregateKind::Cell ||
             record.kind == AggregateKind::UnsafeCell ||
             record.kind == AggregateKind::Uninit ||
             record.kind == AggregateKind::ManualDrop) {
      shape.kind = Shape::Kind::Product;
      shape.uninitializedStorage = record.kind == AggregateKind::Uninit;
    } else
      return std::nullopt;
    auto aggregate = std::make_shared<Shape::Aggregate>();
    aggregate->elements.reserve(record.fields.size());
    if (shape.kind != Shape::Kind::Tuple)
      aggregate->names.reserve(record.fields.size());
    for (const auto &field : record.fields) {
      auto element = concreteShape(field.type, depth + 1);
      if (!element)
        return std::nullopt;
      height = std::max(height, element->height + 1);
      aggregate->elements.push_back(element->shape);
      if (shape.kind != Shape::Kind::Tuple)
        aggregate->names.push_back(field.name);
    }
    if (shape.kind == Shape::Kind::Variant) {
      aggregate->variants.reserve(record.variants.size());
      for (const auto &variant : record.variants)
        aggregate->variants.emplace_back(variant.fields.begin(),
                                         variant.fields.end());
    }
    shape.aggregate = std::move(aggregate);
    return shape;
  }
  struct Context {
    Checker::GenericEnvironment environment;
    Checker::GenericEnvironment *previous = nullptr;
    std::vector<TypeBinding> bindings;
    const Function *declaration = nullptr;
  };
  void bind(Context &context) {
    for (auto &[name, type] : context.environment.names)
      type = checker.typeStore().substitute(type, context.bindings);
  }
  Checker::GenericEnvironment *originalEnvironment;
  std::deque<Context> contexts;
  std::map<Type, CachedShape> shapes;
  std::map<const Node *, NodeFacts> syntheticFacts;
  std::deque<NodeOwner> receiverExpressions;
  // Host ownership keeps literal roots live through checked serialization.
  std::map<Type, const Function *> destructorCache;
  std::map<std::string, std::shared_ptr<Value>, std::less<>> literalRoots;
  Value functionValue(std::size_t index) {
    Value value;
    value.kind = Value::Kind::Function;
    value.type =
        checker.typeStore().callableType(checker.functionSignature(index));
    value.symbol = static_cast<int>(index);
    return value;
  }
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
  if (node.kind != Kind::Call)
    return false;
  const NodeFacts *facts = checked.find(node);
  if (!facts)
    if (auto imported = importedExpression(node))
      facts = &imported->facts.at(&node);
  if (!facts)
    return false;
  if (!facts->machineOperation.empty())
    return facts->machineOperation != "atomic.new" &&
           facts->machineOperation != "storage.new" &&
           facts->machineOperation != "cell.new";
  if (facts->constructor)
    return false;
  auto function = resolvedCall(facts);
  return function && function->constFunction;
}

const Function *Checker::resolvedCall(const NodeFacts *facts) const {
  if (!facts || facts->callee < 0)
    return nullptr;
  return &module.functions.at(facts->callee);
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
  ConstantHost host(*this);
  return host.typeShape(type);
}

std::optional<Value> Checker::constantValueOf(const StaticConstant &constant,
                                              evaluation::Host &host) {
  Value value;
  if (constant.kind == StaticConstant::Kind::Function) {
    if (!checked.types->isFunctionPointer(constant.type) ||
        constant.symbol < 0 ||
        static_cast<std::size_t>(constant.symbol) >= module.functions.size())
      return std::nullopt;
    value.kind = Value::Kind::Function;
    value.type = constant.type;
    value.symbol = constant.symbol;
    return value;
  }
  if (constant.kind == StaticConstant::Kind::Text) {
    auto count = textConstantCount(*checked.types, constant);
    if (!count)
      return std::nullopt;
    auto root = host.literalStorage(constant.text);
    if (!root)
      return std::nullopt;
    value.kind = checked.types->isPointer(constant.type)
                     ? Value::Kind::Pointer
                     : Value::Kind::Reference;
    value.type = constant.type;
    value.exclusive =
        checked.types->view(constant.type).mode == ParameterMode::Mut;
    value.storage = root;
    value.storageType = root->type;
    value.offset = constant.byteOffset;
    value.count = *count;
    return value;
  }
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
    if (constant.selection < 0)
      return std::nullopt;
    value.kind = host.enumeration(constant.type) ? Value::Kind::Enum
                                                 : Value::Kind::Variant;
    value.type = constant.type;
    value.number =
        enumDiscriminant(*checked.types, constant.type, constant.selection);
    value.selection = constant.selection;
    const auto &record = checked.types->product(constant.type);
    auto start = record.layout.kind == LayoutKind::Transparent ? 0 : 1;
    for (std::size_t i = start;
         value.kind == Value::Kind::Variant && i < constant.fields.size();
         ++i) {
      auto field = constantValueOf(constant.fields[i], host);
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
    auto element = constantValueOf(constant.fields.front(), host);
    if (!element)
      return std::nullopt;
    value.elements.assign(static_cast<std::size_t>(*length), *element);
    return value;
  }
  for (const auto &field : constant.fields) {
    auto element = constantValueOf(field, host);
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
  case Value::Kind::Function:
    if (!checked.types->isFunctionPointer(type) || value.symbol < 0 ||
        static_cast<std::size_t>(value.symbol) >= module.functions.size() ||
        !compatibleCallable(value.type, type))
      return mismatch();
    result.kind = StaticConstant::Kind::Function;
    result.symbol = value.symbol;
    return result;
  case Value::Kind::TypeIdentity:
    if (type != Type::U64 || value.identity.empty())
      return mismatch();
    result.kind = StaticConstant::Kind::TypeIdentity;
    result.text = value.identity;
    return result;
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
    if (auto root = value.storage.lock(); root && root->immutableLiteral) {
      if (value.addressOnly || value.symbol >= 0 || value.writable ||
          (value.kind == Value::Kind::Reference && value.exclusive))
        return mismatch();
      result.kind = StaticConstant::Kind::Text;
      result.byteOffset = value.offset;
      result.text.reserve(root->elements.size());
      for (const auto &element : root->elements) {
        if (element.kind != Value::Kind::Integer || element.type != Type::U8 ||
            !integerLiteralFits(element.number, Type::U8))
          return mismatch();
        result.text.push_back(static_cast<char>(element.number.magnitude[0]));
      }
      if (checked.types->pointerMetadata(checked.types->view(type).payload) ==
          PointerMetadata::ElementCount) {
        StaticConstant count;
        count.type = Type::Usize;
        count.scalar = integerLiteral(value.count);
        result.fields.push_back(std::move(count));
      }
      if (!textConstantCount(*checked.types, result))
        return mismatch();
      return result;
    }
    result.kind = value.addressOnly ? StaticConstant::Kind::Pointer
                                    : StaticConstant::Kind::Address;
    result.symbol = value.symbol;
    result.byteOffset = value.addressOnly ? 0 : value.offset;
    result.scalar.magnitude[0] =
        value.addressOnly ? value.offset
        : checked.types->pointerMetadata(checked.types->view(type).payload) ==
                PointerMetadata::ElementCount
            ? value.count
            : 0;
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

std::optional<StaticConstant>
Checker::evaluatedStatic(const Node &node, Type type,
                         std::span<const TypeBinding> bindings) {
  auto shape = constantShape(type);
  if (!shape) {
    error("constant", node.span,
          "static initializer type is not supported by the constant "
          "evaluator");
    return std::nullopt;
  }
  ConstantHost host(*this, bindings);
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
                                                   Type subject,
                                                   const Node *use) {
  auto &constant = inherentConstants.at(index);
  constant.materializeSyntax();
  auto &environment = typeEnvironment(*constant.implementation);
  const bool genericNominal =
      checked.types->isProduct(constant.declaredType) &&
      (!environment.parameters.empty() ||
       checked.types->isSymbolic(constant.target) ||
       checked.types->isSymbolic(constant.declaredType));
  if (genericNominal) {
    if (checked.types->isSymbolic(subject)) {
      if (use)
        error("feature", use->span,
              "generic nominal associated constant requires a concrete "
              "owner type");
      return std::nullopt;
    }

    auto savedEnvironment = genericEnvironment;
    auto *savedFunction = current;
    genericEnvironment = &environment;
    current = nullptr;
    std::vector<TypeBinding> bindings;
    for (auto parameter : environment.parameters)
      bindings.push_back({parameter, Type::Unknown});
    const auto span = use ? use->span : constant.declaration->span;
    if (!inferGeneric(constant.target, subject, bindings, span)) {
      error("type", span,
            "associated constant owner does not match its implementation");
      genericEnvironment = savedEnvironment;
      current = savedFunction;
      return std::nullopt;
    }
    completeGenericBindings(environment, bindings, span);
    bool complete = true;
    std::vector<Type> arguments;
    for (const auto &binding : bindings) {
      complete &= binding.argument != Type::Unknown;
      arguments.push_back(binding.argument);
    }
    if (!complete) {
      error("type", span, "cannot infer generic associated constant arguments");
      genericEnvironment = savedEnvironment;
      current = savedFunction;
      return std::nullopt;
    }
    if (!genericObligations(environment, bindings, span)) {
      genericEnvironment = savedEnvironment;
      current = savedFunction;
      return std::nullopt;
    }
    genericEnvironment = savedEnvironment;
    current = savedFunction;

    auto &instance = constant.instances[arguments];
    if (instance.state == 1) {
      error("constant", constant.declaration->span,
            "cycle in associated constant definition");
      return std::nullopt;
    }
    if (instance.state == 0) {
      if (constantEvaluationDepth >= limits::constEvalDepth) {
        error("limit", constant.declaration->span,
              "associated constant evaluation exceeded the nesting limit");
        return std::nullopt;
      }
      instance.state = 1;
      ++constantEvaluationDepth;
      struct DepthGuard {
        unsigned &depth;
        ~DepthGuard() { --depth; }
      } depthGuard{constantEvaluationDepth};

      auto *savedEvaluationEnvironment = genericEnvironment;
      auto *savedEvaluationFunction = current;
      auto savedUnsafeDepth = unsafeDepth;
      genericEnvironment = &environment;
      current = nullptr;
      unsafeDepth = 0;
      const auto *initializer =
          constant.initializer
              ? importExpression(constant.initializer).syntax.get()
              : constant.declaration->constantValue.get();
      if (initializer && !constant.initializer)
        qualifyDottedPaths(const_cast<Node &>(*initializer));
      const auto concreteType =
          checked.types->substitute(constant.declaredType, bindings);
      if (initializer)
        instance.materialized =
            evaluatedStatic(*initializer, concreteType, bindings);
      else
        error("type", constant.declaration->span,
              "associated constant requires a definition");
      auto supported = [&](auto &&self, const StaticConstant &value) -> bool {
        if (value.kind == StaticConstant::Kind::Scalar)
          return value.type == Type::Unit || isNumeric(value.type) ||
                 value.type == Type::Bool || value.type == Type::Char;
        if (value.kind != StaticConstant::Kind::Aggregate &&
            value.kind != StaticConstant::Kind::Repeat)
          return false;
        if (!checked.types->isProduct(value.type))
          return false;
        const auto &record = checked.types->product(value.type);
        if (record.layout.unionType || (!checked.types->isSum(value.type) &&
                                        record.kind != AggregateKind::Product &&
                                        record.kind != AggregateKind::Tuple &&
                                        record.kind != AggregateKind::Array))
          return false;
        return std::all_of(
            value.fields.begin(), value.fields.end(),
            [&](const auto &field) { return self(self, field); });
      };
      if (instance.materialized &&
          !supported(supported, *instance.materialized)) {
        error("feature", constant.declaration->span,
              "associated constant payload cannot yet be freshly materialized");
        instance.materialized.reset();
      }
      instance.state = 2;
      genericEnvironment = savedEvaluationEnvironment;
      current = savedEvaluationFunction;
      unsafeDepth = savedUnsafeDepth;
    }
    if (instance.materialized && use)
      facts(*use).constantValue = instance.materialized;
    return std::nullopt;
  }

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
    genericEnvironment = &typeEnvironment(*constant.implementation);
    current = nullptr;
    unsafeDepth = 0;
    const auto *initializer =
        constant.initializer
            ? importExpression(constant.initializer).syntax.get()
            : constant.declaration->constantValue.get();
    if (initializer && !constant.initializer)
      qualifyDottedPaths(const_cast<Node &>(*initializer));
    if (checked.types->isProduct(constant.declaredType)) {
      if (initializer)
        constant.materialized =
            staticInitializer(*initializer, constant.declaredType);
      auto supported = [&](auto &&self, const StaticConstant &value) -> bool {
        if (value.kind == StaticConstant::Kind::Scalar)
          return value.type == Type::Unit || isNumeric(value.type) ||
                 value.type == Type::Bool || value.type == Type::Char;
        if (value.kind != StaticConstant::Kind::Aggregate &&
            value.kind != StaticConstant::Kind::Repeat)
          return false;
        if (!checked.types->isProduct(value.type))
          return false;
        const auto &record = checked.types->product(value.type);
        if (record.layout.unionType || (!checked.types->isSum(value.type) &&
                                        record.kind != AggregateKind::Product &&
                                        record.kind != AggregateKind::Tuple &&
                                        record.kind != AggregateKind::Array))
          return false;
        return std::all_of(
            value.fields.begin(), value.fields.end(),
            [&](const auto &field) { return self(self, field); });
      };
      if (constant.materialized &&
          !supported(supported, *constant.materialized)) {
        error("feature", constant.declaration->span,
              "associated constant payload cannot yet be freshly materialized");
        constant.materialized.reset();
      }
    } else {
      auto value = initializer
                       ? constantType(*initializer, constant.declaredType)
                       : Type::Unknown;
      if (value != Type::Unknown &&
          (!checked.types->isConstant(value) ||
           checked.types->parameter(value).valueType !=
               constant.declaredType)) {
        error("type", constant.declaration->span,
              "associated constant value does not match its declared type");
        value = Type::Unknown;
      }
      constant.value = value;
    }
    constant.state = 2;
    genericEnvironment = savedEnvironment;
    current = savedFunction;
    unsafeDepth = savedUnsafeDepth;
  }
  if (constant.materialized) {
    if (use)
      facts(*use).constantValue = constant.materialized;
    return std::nullopt;
  }
  if (constant.value == Type::Unknown)
    return std::nullopt;

  std::vector<TypeBinding> bindings;
  if (checked.types->isProduct(constant.target) &&
      checked.types->isProduct(subject)) {
    const auto &pattern = checked.types->product(constant.target);
    const auto &actual = checked.types->product(subject);
    const auto &parameters =
        typeEnvironment(*constant.implementation).parameters;
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
