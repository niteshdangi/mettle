#include "types/type.h"
#include <algorithm>
#include <functional>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <tuple>
#include <unordered_set>

namespace mettle {
namespace {
constexpr std::uint32_t builtins = builtinTypeCount;
} // namespace
Type TypeStore::declareParameter(std::string name, bool copyRequested,
                                 bool sized) {
  if (entries.size() >= std::numeric_limits<std::uint32_t>::max() - builtins)
    throw std::length_error("type identity limit exceeded");
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Parameter, parameters.size()});
  parameters.push_back({std::move(name), copyRequested, sized});
  return result;
}
Type TypeStore::declareConstParameter(std::string name, Type valueType) {
  auto result = declareParameter(std::move(name), false);
  auto &record = parameters.back();
  record.kind = TypeParameterKind::Constant;
  record.valueType = valueType;
  return result;
}
void TypeStore::setConstantParameterType(Type type, Type valueType) {
  if (!isConstant(type) || parameter(type).kind != TypeParameterKind::Constant)
    throw std::invalid_argument(
        "constant type update requires a const parameter");
  parameters.at(entries.at(type.index() - builtins).index).valueType =
      valueType;
}
Type TypeStore::constant(Type valueType, std::int64_t value) {
  return constant(valueType, integerLiteral(value));
}
Type TypeStore::constant(Type valueType, NumericLiteral value) {
  if (value.magnitude == std::array<std::uint64_t, 2>{})
    value.negative = false;
  if (!integerLiteralFits(value, valueType))
    throw std::invalid_argument(
        "required scalar constant is outside its type range");
  syncLookup();
  if (auto existing = findIndexed(
          found(lookup.constants, std::pair{valueType, value.magnitude}),
          [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Parameter)
              return false;
            const auto &record = parameters[entries[i].index];
            return record.kind == TypeParameterKind::Value &&
                   record.valueType == valueType && record.numeric == value;
          }))
    return *existing;
  auto result = declareParameter(integerLiteralName(value), false);
  auto &record = parameters.back();
  record.kind = TypeParameterKind::Value;
  record.valueType = valueType;
  record.numeric = std::move(value);
  return result;
}
Type TypeStore::constantExpression(std::string operation,
                                   std::vector<Type> operands) {
  if (operands.size() != 2)
    throw std::invalid_argument("constant expression requires two operands");
  auto operandType = parameter(operands[0]).valueType;
  bool shift = operation == "<<" || operation == ">>";
  auto rightType = parameter(operands[1]).valueType;
  if (shift ? !isInteger(operandType) || !isInteger(rightType)
            : operandType != rightType)
    throw std::invalid_argument("constant operands have different types");
  auto comparison = operation == "==" || operation == "!=" ||
                    operation == "<" || operation == "<=" || operation == ">" ||
                    operation == ">=";
  auto logical = operation == "&&" || operation == "||";
  auto booleanBits = operation == "&" || operation == "|" || operation == "^";
  if ((operandType == Type::Bool && !comparison && !logical && !booleanBits) ||
      (operandType == Type::Char && !comparison))
    throw std::invalid_argument(
        "constant arithmetic requires integer operands");
  if (operandType != Type::Bool && logical)
    throw std::invalid_argument(
        "constant logical operation requires bool operands");
  auto left = scalarConstantValue(operands[0]),
       right = scalarConstantValue(operands[1]);
  if ((operation == "/" || operation == "%") && right &&
      right->magnitude == std::array<std::uint64_t, 2>{})
    throw std::invalid_argument("division by zero in constant expression");
  if ((operation == "<<" || operation == ">>") && right &&
      (right->negative || right->magnitude[1] ||
       right->magnitude[0] >= integerWidth(operandType, pointerBits)))
    throw std::invalid_argument("invalid shift in constant expression");
  if (left && right) {
    auto value = evaluateIntegerConstant(operation, operandType, *left, *right,
                                         pointerBits);
    return constant(comparison || logical ? Type::Bool : operandType,
                    std::move(value));
  }
  syncLookup();
  if (auto existing =
          findIndexed(found(lookup.operands, operands), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Parameter)
              return false;
            const auto &record = parameters[entries[i].index];
            return record.kind == TypeParameterKind::Expression &&
                   record.operation == operation && record.operands == operands;
          }))
    return *existing;
  auto display = "(" + std::string(name(operands[0])) + operation +
                 std::string(name(operands[1])) + ")";
  auto result = declareParameter(std::move(display), false);
  auto &record = parameters.back();
  record.kind = TypeParameterKind::Expression;
  record.valueType = comparison || logical ? Type::Bool : operandType;
  record.operation = std::move(operation);
  record.operands = std::move(operands);
  return result;
}
bool TypeStore::isParameter(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Parameter &&
         (parameter(type).kind == TypeParameterKind::Type ||
          (parameter(type).kind == TypeParameterKind::Projection &&
           parameter(type).valueType == Type::Unknown));
}
bool TypeStore::isConstant(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Parameter &&
         parameter(type).kind != TypeParameterKind::Type &&
         (parameter(type).kind != TypeParameterKind::Projection ||
          parameter(type).valueType != Type::Unknown);
}
bool TypeStore::isProjection(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Parameter &&
         parameter(type).kind == TypeParameterKind::Projection;
}
Type TypeStore::projection(Type subject, Type interfaceType,
                           std::size_t associated, std::vector<Type> arguments,
                           Type valueType, bool copyRequested, bool sized,
                           std::vector<RegionId> regions) {
  arguments.insert(arguments.begin(), interfaceType);
  arguments.insert(arguments.begin(), subject);
  syncLookup();
  if (auto existing =
          findIndexed(found(lookup.operands, arguments), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Parameter)
              return false;
            const auto &record = parameters[entries[i].index];
            return record.kind == TypeParameterKind::Projection &&
                   record.operands == arguments &&
                   record.value == static_cast<std::int64_t>(associated) &&
                   record.valueType == valueType &&
                   record.copyRequested == copyRequested &&
                   record.sized == sized && record.regionArguments == regions;
          }))
    return *existing;
  auto display = std::string(name(subject)) + "::<associated." +
                 std::to_string(associated) + ">";
  auto result = declareParameter(std::move(display), copyRequested, sized);
  auto &record = parameters.back();
  record.kind = TypeParameterKind::Projection;
  record.valueType = valueType;
  record.value = static_cast<std::int64_t>(associated);
  record.operands = std::move(arguments);
  record.regionArguments = std::move(regions);
  return result;
}
const TypeParameter &TypeStore::parameter(Type type) const {
  if (type.index() < builtins || !contains(type) ||
      entries[type.index() - builtins].kind != EntryKind::Parameter)
    throw std::invalid_argument("type is not a parameter or constant");
  return parameters.at(entries[type.index() - builtins].index);
}
void TypeStore::constrainParameter(Type type, bool copyRequested, bool sized) {
  if (!isParameter(type))
    throw std::invalid_argument(
        "capability constraint requires a type parameter");
  auto &record = parameters.at(entries.at(type.index() - builtins).index);
  record.copyRequested |= copyRequested;
  record.sized |= sized;
}
std::optional<std::int64_t> TypeStore::constantValue(Type type) const {
  auto scalar = scalarConstantValue(type);
  if (!scalar || scalar->magnitude[1])
    return std::nullopt;
  auto low = scalar->magnitude[0];
  if (!scalar->negative && low <= std::numeric_limits<std::int64_t>::max())
    return static_cast<std::int64_t>(low);
  if (scalar->negative && low <= (std::uint64_t{1} << 63))
    return low == (std::uint64_t{1} << 63)
               ? std::numeric_limits<std::int64_t>::min()
               : -static_cast<std::int64_t>(low);
  return std::nullopt;
}
std::optional<NumericLiteral> TypeStore::scalarConstantValue(Type type) const {
  if (isConstant(type) && parameter(type).kind == TypeParameterKind::Value)
    return parameter(type).numeric;
  return std::nullopt;
}
bool TypeStore::isSized(Type type) const {
  std::set<Type> active;
  std::map<Type, bool> known;
  std::function<bool(Type)> visit = [&](Type current) {
    if (isSlice(current) || isErased(current))
      return false;
    if (isParameter(current))
      return parameter(current).sized;
    if (!isProduct(current))
      return contains(current);
    if (auto found = known.find(current); found != known.end())
      return found->second;
    if (active.size() >= 128 || !active.insert(current).second)
      return false;
    bool sized = true;
    const auto &record = product(current);
    if (record.kind == AggregateKind::Array && !record.components.empty())
      sized = visit(record.components[0]);
    else
      for (const auto &field : record.fields)
        sized &= visit(field.type);
    active.erase(current);
    known[current] = sized;
    return sized;
  };
  return visit(type);
}
bool TypeStore::isSymbolic(Type type) const {
  std::set<Type> visited;
  std::function<bool(Type)> symbolic = [&](Type current) {
    if (!visited.insert(current).second)
      return false;
    if (isParameter(current))
      return true;
    if (isConstant(current))
      return !scalarConstantValue(current);
    if (isView(current) || isPointer(current))
      return symbolic(view(current).payload);
    if (isSlice(current))
      return symbolic(slice(current).element);
    if (isErased(current)) {
      const auto &descriptor = erased(current);
      for (auto argument : descriptor.arguments)
        if (symbolic(argument))
          return true;
      for (const auto &binding : descriptor.associated)
        if (symbolic(binding.argument))
          return true;
    }
    if (isFunctionPointer(current)) {
      const auto &descriptor = callable(current);
      for (const auto &parameter : descriptor.parameters)
        if (symbolic(parameter.type))
          return true;
      return symbolic(descriptor.result) || symbolic(descriptor.error);
    }
    if (isProduct(current)) {
      const auto &record = product(current);
      for (auto argument : record.genericArguments)
        if (symbolic(argument))
          return true;
      if (record.arrayCount != Type::Unknown && symbolic(record.arrayCount))
        return true;
      for (auto bound : record.opaqueBounds)
        if (symbolic(bound))
          return true;
      for (const auto &field : record.fields)
        if (symbolic(field.type))
          return true;
    }
    return false;
  };
  return symbolic(type);
}
std::vector<Type> TypeStore::typeParameters(Type type) const {
  std::vector<Type> result;
  std::unordered_set<std::uint32_t> visited;
  std::function<void(Type)> visit = [&](Type current) {
    if (!visited.insert(current.index()).second)
      return;
    if (isProjection(current)) {
      for (auto operand : parameter(current).operands)
        visit(operand);
      return;
    }
    if (isParameter(current) ||
        (isConstant(current) &&
         parameter(current).kind == TypeParameterKind::Constant)) {
      result.push_back(current);
      return;
    }
    if (isConstant(current)) {
      for (auto operand : parameter(current).operands)
        visit(operand);
    } else if (isView(current) || isPointer(current))
      visit(view(current).payload);
    else if (isSlice(current))
      visit(slice(current).element);
    else if (isErased(current)) {
      for (auto argument : erased(current).arguments)
        visit(argument);
      for (const auto &binding : erased(current).associated)
        visit(binding.argument);
    } else if (isProduct(current)) {
      const auto &record = product(current);
      for (auto argument : record.genericArguments)
        visit(argument);
      for (const auto &field : record.fields)
        visit(field.type);
      // A symbolically sized array has no fields; its element is a component.
      if (record.kind == AggregateKind::Array)
        for (auto component : record.components)
          visit(component);
      if (record.arrayCount != Type::Unknown)
        visit(record.arrayCount);
    }
    if (isCallable(current)) {
      const auto &descriptor = callable(current);
      for (const auto &parameter : descriptor.parameters)
        visit(parameter.type);
      visit(descriptor.result);
      visit(descriptor.error);
    }
  };
  visit(type);
  return result;
}
void TypeStore::setGenericParameters(Type type, std::vector<Type> values) {
  products.at(entries.at(type.index() - builtins).index).genericParameters =
      std::move(values);
}
Type TypeStore::instantiateProduct(Type origin, std::vector<Type> arguments) {
  if (instanceDepth >= 128)
    throw std::length_error("generic type expansion limit exceeded");
  struct Depth {
    unsigned &value;
    explicit Depth(unsigned &value) : value(value) { ++value; }
    ~Depth() { --value; }
  } depth(instanceDepth);
  if (product(origin).genericParameters.size() != arguments.size())
    throw std::invalid_argument("generic type argument count does not match");
  syncLookup();
  if (auto existing = findIndexed(
          found(lookup.genericInstances, origin), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Product)
              return false;
            const auto &record = products[entries[i].index];
            return record.regionOrigin == Type::Unknown &&
                   record.genericOrigin == origin &&
                   record.genericArguments == arguments;
          }))
    return *existing;
  // Interning below can reallocate the product table, so keep a copy.
  const auto source = product(origin);
  std::string display = source.name + "<";
  std::vector<TypeBinding> bindings;
  for (std::size_t i = 0; i < arguments.size(); ++i) {
    if (i)
      display += ", ";
    display += name(arguments[i]);
    bindings.push_back({source.genericParameters[i], arguments[i]});
  }
  display += ">";
  auto result = declareProduct(std::move(display), source.copyRequested);
  auto index = entries.at(result.index() - builtins).index;
  products[index].genericOrigin = origin;
  products[index].genericArguments = std::move(arguments);
  std::vector<TypeField> fields;
  for (const auto &field : source.fields)
    fields.push_back({field.name, substitute(field.type, bindings)});
  products[index].fields = std::move(fields);
  products[index].kind = source.kind;
  products[index].layout = source.layout;
  products[index].variants = source.variants;
  for (auto bound : source.opaqueBounds)
    products[index].opaqueBounds.push_back(substitute(bound, bindings));
  products[index].hasDestructor = source.hasDestructor;
  products[index].destructor = source.destructor;
  if (source.callable >= 0) {
    auto descriptor = callables.at(static_cast<std::size_t>(source.callable));
    for (auto &parameter : descriptor.parameters)
      parameter.type = substitute(parameter.type, bindings);
    descriptor.result = substitute(descriptor.result, bindings);
    descriptor.error = substitute(descriptor.error, bindings);
    descriptor.abiResult = substitute(descriptor.abiResult, bindings);
    descriptor.environment = result;
    products[index].callable = static_cast<int>(callables.size());
    callables.push_back(std::move(descriptor));
  }
  return result;
}
void TypeStore::refreshProductInstances() {
  for (std::size_t i = 0; i < entries.size(); ++i) {
    if (entries[i].kind != EntryKind::Product)
      continue;
    auto index = entries[i].index;
    auto instance = products[index];
    if (instance.genericOrigin == Type::Unknown ||
        instance.kind == AggregateKind::Opaque)
      continue;
    auto source = product(instance.genericOrigin);
    std::vector<TypeBinding> bindings;
    for (std::size_t j = 0; j < source.genericParameters.size(); ++j)
      bindings.push_back(
          {source.genericParameters[j], instance.genericArguments[j]});
    std::vector<TypeField> fields;
    for (const auto &field : source.fields)
      fields.push_back({field.name, substitute(field.type, bindings)});
    products[index].fields = std::move(fields);
    products[index].kind = source.kind;
    products[index].layout = source.layout;
    products[index].variants = source.variants;
    products[index].hasDestructor = source.hasDestructor;
    products[index].destructor = source.destructor;
    if (source.callable >= 0) {
      auto descriptor = callables.at(static_cast<std::size_t>(source.callable));
      for (auto &parameter : descriptor.parameters)
        parameter.type = substitute(parameter.type, bindings);
      descriptor.result = substitute(descriptor.result, bindings);
      descriptor.error = substitute(descriptor.error, bindings);
      descriptor.abiResult = substitute(descriptor.abiResult, bindings);
      descriptor.environment = Type(builtins + static_cast<std::uint32_t>(i));
      if (instance.callable >= 0)
        callables.at(static_cast<std::size_t>(instance.callable)) =
            std::move(descriptor);
      else {
        products[index].callable = static_cast<int>(callables.size());
        callables.push_back(std::move(descriptor));
      }
    }
  }
}
Type TypeStore::canonicalCount(Type count) {
  if (auto value = constantValue(count))
    return constant(*value <= std::numeric_limits<std::int32_t>::max()
                        ? Type::I32
                        : Type::I64,
                    *value);
  return count;
}
std::optional<std::uint64_t> TypeStore::arrayLength(Type array) const {
  const auto &record = product(array);
  if (record.arrayCount == Type::Unknown)
    return record.fields.size();
  if (auto value = constantValue(record.arrayCount))
    return static_cast<std::uint64_t>(*value);
  return std::nullopt;
}
bool TypeStore::compactArray(Type array) const {
  return isProduct(array) && product(array).kind == AggregateKind::Array &&
         product(array).arrayCount != Type::Unknown &&
         constantValue(product(array).arrayCount).has_value();
}
bool TypeStore::compactArrayShape(Type payload, std::uint64_t count) const {
  // Compact arrays have no per-element drop state, so droppable elements keep
  // one place per element.
  if (needsDrop(payload))
    return false;
  // Nested arrays multiply the expanded place count.
  std::uint64_t total = count;
  for (auto walk = payload;
       isProduct(walk) && product(walk).kind == AggregateKind::Array &&
       !product(walk).components.empty();
       walk = product(walk).components[0]) {
    auto inner = std::max<std::uint64_t>(1, arrayLength(walk).value_or(1));
    if (total > expandedArrayTotal / inner)
      return true;
    total *= inner;
  }
  return count > expandedArrayLimit || total > expandedArrayTotal;
}
Type TypeStore::arrayType(Type payload, Type count) {
  if (scalarConstantValue(count) && !constantValue(count))
    throw std::length_error("array length exceeds compiler resource limit");
  if (auto value = constantValue(count)) {
    if (*value < 0)
      throw std::length_error("array length exceeds compiler resource limit");
    auto length = static_cast<std::uint64_t>(*value);
    if (needsDrop(payload)) {
      // Droppable elements keep a cleanup place each, so their total is
      // bounded.
      std::uint64_t total = length;
      for (auto walk = payload;
           isProduct(walk) && product(walk).kind == AggregateKind::Array &&
           !product(walk).components.empty();
           walk = product(walk).components[0])
        total *= std::max<std::uint64_t>(1, arrayLength(walk).value_or(1));
      if (length > droppableArrayElements || total > droppableArrayElements)
        throw std::length_error("array length exceeds compiler resource limit");
    }
    if (!compactArrayShape(payload, length))
      return structural(AggregateKind::Array, {payload},
                        static_cast<std::uint32_t>(length));
    count = canonicalCount(count);
  }
  syncLookup();
  const std::vector<Type> component{payload};
  if (auto existing =
          findIndexed(found(lookup.aggregates, component), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Product)
              return false;
            const auto &record = products[entries[i].index];
            return record.kind == AggregateKind::Array &&
                   record.components == component && record.arrayCount == count;
          }))
    return *existing;
  auto result = declareProduct("[" + std::string(name(payload)) + "; " +
                                   std::string(name(count)) + "]",
                               isCopy(payload));
  auto &record = products.at(entries.at(result.index() - builtins).index);
  record.kind = AggregateKind::Array;
  record.components = {payload};
  record.arrayCount = count;
  return result;
}
Type TypeStore::substitute(Type type, std::span<const TypeBinding> bindings) {
  for (const auto &binding : bindings)
    if (type == binding.parameter)
      return binding.argument;
  if (isProjection(type)) {
    auto descriptor = parameter(type);
    for (auto &operand : descriptor.operands)
      operand = substitute(operand, bindings);
    auto subject = descriptor.operands[0];
    auto interfaceType = descriptor.operands[1];
    descriptor.operands.erase(descriptor.operands.begin(),
                              descriptor.operands.begin() + 2);
    auto result = projection(
        subject, interfaceType, static_cast<std::size_t>(descriptor.value),
        std::move(descriptor.operands), descriptor.valueType,
        descriptor.copyRequested, descriptor.sized,
        std::move(descriptor.regionArguments));
    return result;
  }
  if (isConstant(type) &&
      parameter(type).kind == TypeParameterKind::Expression) {
    auto expression = parameter(type);
    for (auto &operand : expression.operands)
      operand = substitute(operand, bindings);
    return constantExpression(expression.operation,
                              std::move(expression.operands));
  }
  if (isView(type)) {
    auto record = view(type);
    return viewType(substitute(record.payload, bindings), record.mode,
                    record.region);
  }
  if (isPointer(type)) {
    auto record = pointer(type);
    return pointerType(substitute(record.payload, bindings), record.mode);
  }
  if (isSlice(type))
    return sliceType(substitute(slice(type).element, bindings));
  if (isErased(type)) {
    // Substitution can add types, so snapshot the small parts and avoid
    // copying the method tables when no argument changes.
    auto arguments = erased(type).arguments;
    auto bound = erased(type).associated;
    bool changed = false;
    for (auto &argument : arguments) {
      auto next = substitute(argument, bindings);
      changed |= next != argument;
      argument = next;
    }
    for (auto &associated : bound) {
      auto next = substitute(associated.argument, bindings);
      changed |= next != associated.argument;
      associated.argument = next;
    }
    if (!changed)
      return type;
    auto descriptor = erased(type);
    descriptor.arguments = std::move(arguments);
    descriptor.associated = std::move(bound);
    auto methods = std::move(descriptor.methods);
    auto owners = std::move(descriptor.methodOwners);
    auto slots = std::move(descriptor.methodSlots);
    auto parents = std::move(descriptor.parentInterfaces);
    descriptor.methodTypes.clear();
    // Dispatch signatures can refer to their own erased receiver identity.
    auto result = erasedType(std::move(descriptor));
    if (result == type)
      return result;
    std::vector<TypeBinding> methodBindings{{type, result}};
    methodBindings.insert(methodBindings.end(), bindings.begin(),
                          bindings.end());
    std::vector<Type> rebasedParents;
    for (auto parent : parents) {
      parent = substitute(parent, methodBindings);
      if (std::find(rebasedParents.begin(), rebasedParents.end(), parent) ==
          rebasedParents.end())
        rebasedParents.push_back(parent);
    }
    if (!rebasedParents.empty())
      setErasedParents(result, std::move(rebasedParents));
    if (!erased(result).methods.empty())
      return result;
    for (auto &owner : owners)
      owner = substitute(owner, methodBindings);
    for (auto &method : methods) {
      for (auto &parameter : method.parameters)
        parameter.type = substitute(parameter.type, methodBindings);
      method.result = substitute(method.result, methodBindings);
      method.error = substitute(method.error, methodBindings);
      method.abiResult = substitute(method.abiResult, methodBindings);
    }
    if (owners.size() == methods.size() && slots.size() == methods.size()) {
      using MethodKey =
          std::tuple<Type, std::size_t, Type, Type, ParameterMode>;
      std::set<MethodKey> seen;
      std::vector<Type> uniqueOwners;
      std::vector<std::size_t> uniqueSlots;
      std::vector<CallableType> uniqueMethods;
      for (std::size_t i = 0; i < methods.size(); ++i) {
        auto signature = methods[i].result == Type::Unknown
                             ? Type::Unknown
                             : callableType(methods[i]);
        if (signature != Type::Unknown &&
            !seen.emplace(owners[i], slots[i], signature, methods[i].abiResult,
                          methods[i].environmentMode)
                 .second)
          continue;
        uniqueOwners.push_back(owners[i]);
        uniqueSlots.push_back(slots[i]);
        uniqueMethods.push_back(std::move(methods[i]));
      }
      owners = std::move(uniqueOwners);
      slots = std::move(uniqueSlots);
      methods = std::move(uniqueMethods);
    }
    if (!owners.empty())
      setErasedDispatch(result, std::move(owners), std::move(slots));
    setErasedMethods(result, std::move(methods));
    return result;
  }
  if (isFunctionPointer(type)) {
    auto descriptor = callable(type);
    for (auto &parameter : descriptor.parameters)
      parameter.type = substitute(parameter.type, bindings);
    descriptor.result = substitute(descriptor.result, bindings);
    descriptor.error = substitute(descriptor.error, bindings);
    descriptor.abiResult = substitute(descriptor.abiResult, bindings);
    return callableType(std::move(descriptor));
  }
  if (!isProduct(type))
    return type;
  {
    // Plain nominal products have nothing to substitute; skip the layout copy.
    const auto &plain = product(type);
    if ((plain.kind == AggregateKind::Product ||
         plain.kind == AggregateKind::Enumeration ||
         plain.kind == AggregateKind::NativeVector) &&
        plain.genericOrigin == Type::Unknown &&
        plain.regionOrigin == Type::Unknown &&
        !(plain.callable >= 0 && !plain.genericParameters.empty()))
      return type;
  }
  auto record = product(type);
  if (isOpaque(type)) {
    auto origin =
        record.genericOrigin == Type::Unknown ? type : record.genericOrigin;
    // A generic declaration's opaque result is named by its parameters.
    if (record.genericOrigin == Type::Unknown)
      record.genericArguments = record.genericParameters;
    bool changed = false;
    for (auto &argument : record.genericArguments) {
      auto replacement = substitute(argument, bindings);
      changed |= replacement != argument;
      argument = replacement;
    }
    for (auto &field : record.fields) {
      auto replacement = substitute(field.type, bindings);
      changed |= replacement != field.type;
      field.type = replacement;
    }
    for (auto &bound : record.opaqueBounds) {
      auto replacement = substitute(bound, bindings);
      changed |= replacement != bound;
      bound = replacement;
    }
    if (!changed)
      return type;
    syncLookup();
    if (auto existing = findIndexed(
            found(lookup.genericInstances, origin), [&](std::size_t i) {
              if (entries[i].kind != EntryKind::Product)
                return false;
              const auto &prior = products[entries[i].index];
              if (prior.kind != AggregateKind::Opaque ||
                  prior.genericOrigin != origin ||
                  prior.genericArguments != record.genericArguments ||
                  prior.opaqueBounds != record.opaqueBounds ||
                  prior.fields.size() != record.fields.size())
                return false;
              for (std::size_t field = 0; field < prior.fields.size(); ++field)
                if (prior.fields[field].type != record.fields[field].type)
                  return false;
              return true;
            }))
      return *existing;
    auto result = declareProduct(record.name, record.copyRequested);
    record.genericOrigin = origin;
    products.at(entries.at(result.index() - builtins).index) =
        std::move(record);
    return result;
  }
  if (record.regionOrigin != Type::Unknown) {
    if (record.regionPattern != Type::Unknown) {
      auto parameters = typeParameters(type);
      bool relevant = std::any_of(
          bindings.begin(), bindings.end(), [&](const auto &binding) {
            return binding.argument != binding.parameter &&
                   std::find(parameters.begin(), parameters.end(),
                             binding.parameter) != parameters.end();
          });
      if (!relevant)
        return type;
      if (regionalSubstitutionDepth >= 128)
        throw std::length_error("regional type substitution limit exceeded");
      if (regionalSubstitutionDepth++ == 0)
        regionalSubstitutions.clear();
      struct Scope {
        TypeStore &store;
        ~Scope() {
          if (--store.regionalSubstitutionDepth == 0)
            store.regionalSubstitutions.clear();
        }
      } scope{*this};
      std::vector<std::pair<Type, Type>> canonical;
      for (const auto &binding : bindings)
        canonical.emplace_back(binding.parameter, binding.argument);
      std::sort(canonical.begin(), canonical.end());
      RegionalSubstitution key{type, std::move(canonical)};
      if (auto found = regionalSubstitutions.find(key);
          found != regionalSubstitutions.end())
        return found->second;
      auto result =
          regionalShell(record.regionOrigin, record.regionArguments,
                        record.genericArguments, record.regionPattern);
      regionalSubstitutions.emplace(std::move(key), result);
      auto origin = substitute(record.regionOrigin, bindings);
      for (auto &argument : record.genericArguments)
        argument = substitute(argument, bindings);
      auto index = entries.at(result.index() - builtins).index;
      products[index].regionOrigin = origin;
      syncLookup();
      lookup.regionInstances[origin].push_back(
          static_cast<std::uint32_t>(result.index() - builtins));
      products[index].genericArguments = std::move(record.genericArguments);
      for (auto &field : record.fields)
        field.type = substitute(field.type, bindings);
      defineProduct(result, std::move(record.fields));
      return result;
    }
    auto origin = substitute(record.regionOrigin, bindings);
    for (auto &field : record.fields)
      field.type = substitute(field.type, bindings);
    return regionalProduct(origin, std::move(record.fields),
                           std::move(record.regionArguments),
                           record.normalizedFields);
  }
  if (record.callable >= 0 && record.genericOrigin == Type::Unknown &&
      !record.genericParameters.empty()) {
    auto arguments = record.genericParameters;
    for (auto &argument : arguments)
      argument = substitute(argument, bindings);
    // An identity substitution names the closure itself, not a new instance.
    if (arguments == record.genericParameters)
      return type;
    return instantiateProduct(type, std::move(arguments));
  }
  if (record.genericOrigin != Type::Unknown) {
    for (auto &argument : record.genericArguments)
      argument = substitute(argument, bindings);
    return instantiateProduct(record.genericOrigin,
                              std::move(record.genericArguments));
  }
  if (record.kind == AggregateKind::Product ||
      record.kind == AggregateKind::Enumeration ||
      record.kind == AggregateKind::NativeVector)
    return type;
  for (auto &component : record.components)
    component = substitute(component, bindings);
  if (record.kind == AggregateKind::Array && record.arrayCount != Type::Unknown)
    return arrayType(record.components[0],
                     substitute(record.arrayCount, bindings));
  return structural(record.kind, std::move(record.components),
                    static_cast<std::uint32_t>(record.fields.size()));
}
bool TypeStore::matchesSubstitution(
    Type pattern, Type actual, std::span<const TypeBinding> bindings) const {
  std::function<std::optional<NumericLiteral>(Type)> value = [&](Type type) {
    for (const auto &binding : bindings)
      if (type == binding.parameter)
        return scalarConstantValue(binding.argument);
    if (!isConstant(type))
      return std::optional<NumericLiteral>{};
    const auto &record = parameter(type);
    if (record.kind == TypeParameterKind::Value)
      return std::optional<NumericLiteral>{record.numeric};
    if (record.kind != TypeParameterKind::Expression)
      return std::optional<NumericLiteral>{};
    auto a = value(record.operands[0]), b = value(record.operands[1]);
    if (a && b)
      try {
        return std::optional<NumericLiteral>{evaluateIntegerConstant(
            record.operation, parameter(record.operands[0]).valueType, *a, *b)};
      } catch (const std::invalid_argument &) {
        return std::optional<NumericLiteral>{};
      }
    return std::optional<NumericLiteral>{};
  };
  for (const auto &binding : bindings)
    if (pattern == binding.parameter)
      return actual == binding.argument;
  if (pattern == actual)
    return true;
  if (isProjection(pattern) && isProjection(actual)) {
    const auto &left = parameter(pattern), &right = parameter(actual);
    if (left.value != right.value || left.valueType != right.valueType ||
        left.operands.size() != right.operands.size() ||
        left.regionArguments != right.regionArguments)
      return false;
    for (std::size_t i = 0; i < left.operands.size(); ++i)
      if (!matchesSubstitution(left.operands[i], right.operands[i], bindings))
        return false;
    return true;
  }
  if (isConstant(pattern) && isConstant(actual))
    return parameter(pattern).valueType == parameter(actual).valueType &&
           value(pattern) && value(pattern) == value(actual);
  if ((isView(pattern) && isView(actual)) ||
      (isPointer(pattern) && isPointer(actual)))
    return view(pattern).mode == view(actual).mode &&
           view(pattern).region == view(actual).region &&
           matchesSubstitution(view(pattern).payload, view(actual).payload,
                               bindings);
  if (isSlice(pattern) && isSlice(actual))
    return matchesSubstitution(slice(pattern).element, slice(actual).element,
                               bindings);
  if (isErased(pattern) && isErased(actual)) {
    const auto &left = erased(pattern), &right = erased(actual);
    if (left.declaration != right.declaration ||
        left.arguments.size() != right.arguments.size() ||
        left.associated.size() != right.associated.size())
      return false;
    for (std::size_t i = 0; i < left.arguments.size(); ++i)
      if (!matchesSubstitution(left.arguments[i], right.arguments[i], bindings))
        return false;
    for (std::size_t i = 0; i < left.associated.size(); ++i)
      if (left.associated[i].parameter != right.associated[i].parameter ||
          !matchesSubstitution(left.associated[i].argument,
                               right.associated[i].argument, bindings))
        return false;
    return true;
  }
  if (isFunctionPointer(pattern) && isFunctionPointer(actual)) {
    const auto &left = callable(pattern), &right = callable(actual);
    if (left.mode != right.mode ||
        left.parameters.size() != right.parameters.size())
      return false;
    for (std::size_t i = 0; i < left.parameters.size(); ++i)
      if (left.parameters[i].mode != right.parameters[i].mode ||
          !matchesSubstitution(left.parameters[i].type,
                               right.parameters[i].type, bindings))
        return false;
    return matchesSubstitution(left.result, right.result, bindings) &&
           matchesSubstitution(left.error, right.error, bindings);
  }
  if (!isProduct(pattern) || !isProduct(actual))
    return false;
  const auto &left = product(pattern), &right = product(actual);
  if (left.kind != right.kind)
    return false;
  if (left.kind == AggregateKind::Opaque) {
    auto leftOrigin =
        left.genericOrigin == Type::Unknown ? pattern : left.genericOrigin;
    auto rightOrigin =
        right.genericOrigin == Type::Unknown ? actual : right.genericOrigin;
    if (leftOrigin != rightOrigin || left.fields.size() != right.fields.size())
      return false;
    for (std::size_t i = 0; i < left.fields.size(); ++i)
      if (!matchesSubstitution(left.fields[i].type, right.fields[i].type,
                               bindings))
        return false;
    return true;
  }
  if (left.genericOrigin != Type::Unknown &&
      left.genericOrigin == right.genericOrigin) {
    if (left.genericArguments.size() != right.genericArguments.size())
      return false;
    for (std::size_t i = 0; i < left.genericArguments.size(); ++i)
      if (!matchesSubstitution(left.genericArguments[i],
                               right.genericArguments[i], bindings))
        return false;
    return true;
  }
  if (left.kind == AggregateKind::Product ||
      left.kind == AggregateKind::Enumeration ||
      left.kind == AggregateKind::NativeVector ||
      left.components.size() != right.components.size())
    return false;
  if (left.kind == AggregateKind::Array) {
    Type count = left.arrayCount;
    for (const auto &binding : bindings)
      if (count == binding.parameter)
        count = binding.argument;
    auto expected = value(count);
    if (right.arrayCount != Type::Unknown) {
      if (count == Type::Unknown ||
          !matchesSubstitution(count, right.arrayCount, bindings))
        return false;
    } else if (expected ? *expected != integerLiteral(static_cast<std::int64_t>(
                                           right.fields.size()))
                        : left.fields.size() != right.fields.size())
      return false;
  }
  for (std::size_t i = 0; i < left.components.size(); ++i)
    if (!matchesSubstitution(left.components[i], right.components[i], bindings))
      return false;
  return true;
}
} // namespace mettle
