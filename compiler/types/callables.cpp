#include "types/type.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace mettle {
namespace {
constexpr std::uint32_t builtins = builtinTypeCount;
bool sameSignature(const CallableType &a, const CallableType &b) {
  if (a.variadic != b.variadic || a.targetFeatures != b.targetFeatures)
    return false;
  if (a.parameters.size() != b.parameters.size() || a.result != b.result ||
      a.error != b.error || a.mode != b.mode || a.unsafeCall != b.unsafeCall ||
      a.abi != b.abi || a.resultSources != b.resultSources ||
      a.resultFromEnvironment != b.resultFromEnvironment ||
      a.regions.size() != b.regions.size() ||
      a.regionParameters != b.regionParameters ||
      a.parameterRegions != b.parameterRegions ||
      a.regionUniverse != b.regionUniverse ||
      a.regionRequirements != b.regionRequirements)
    return false;
  for (std::size_t i = 0; i < a.parameters.size(); ++i)
    if (a.parameters[i].type != b.parameters[i].type ||
        a.parameters[i].mode != b.parameters[i].mode)
      return false;
  return true;
}
} // namespace
std::vector<Type> TypeStore::callableKey(const CallableType &descriptor) {
  std::vector<Type> key{descriptor.result, descriptor.error};
  for (const auto &parameter : descriptor.parameters)
    key.push_back(parameter.type);
  return key;
}
Type TypeStore::callableType(CallableType descriptor) {
  syncLookup();
  if (auto existing = findIndexed(
          found(lookup.callables, callableKey(descriptor)), [&](std::size_t i) {
            return sameSignature(callables[entries[i].index], descriptor);
          }))
    return *existing;
  if (entries.size() >= std::numeric_limits<std::uint32_t>::max() - builtins)
    throw std::length_error("type identity limit exceeded");
  descriptor.environment = Type::Unknown;
  descriptor.function = -1;
  descriptor.name = descriptor.mode == ParameterMode::Mut    ? "mut fn("
                    : descriptor.mode == ParameterMode::Take ? "take fn("
                                                             : "fn(";
  for (std::size_t i = 0; i < descriptor.parameters.size(); ++i) {
    if (i)
      descriptor.name += ", ";
    const auto &parameter = descriptor.parameters[i];
    if (parameter.mode == ParameterMode::Read)
      descriptor.name += "read ";
    else if (parameter.mode == ParameterMode::Mut)
      descriptor.name += "mut ";
    else if (parameter.mode == ParameterMode::Take)
      descriptor.name += "take ";
    descriptor.name += name(parameter.type);
  }
  if (descriptor.variadic)
    descriptor.name += descriptor.parameters.empty() ? "..." : ", ...";
  descriptor.name += "): " + std::string(name(descriptor.result));
  if (descriptor.error != Type::Unknown)
    descriptor.name += " throws " + std::string(name(descriptor.error));
  if (!descriptor.abi.empty())
    descriptor.name = "extern \"" + descriptor.abi + "\" " + descriptor.name;
  if (descriptor.unsafeCall)
    descriptor.name = "unsafe " + descriptor.name;
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Callable, callables.size()});
  callables.push_back(std::move(descriptor));
  return result;
}
Type TypeStore::closureType(std::string name, std::vector<TypeField> captures,
                            CallableType descriptor) {
  bool copy = descriptor.mode != ParameterMode::Take;
  for (const auto &capture : captures)
    copy &= isCopy(capture.type);
  auto result = declareProduct(std::move(name), copy);
  defineProduct(result, std::move(captures));
  auto &record = products.at(entries.at(result.index() - builtins).index);
  record.callable = static_cast<int>(callables.size());
  descriptor.environment = result;
  descriptor.name = record.name;
  callables.push_back(std::move(descriptor));
  return result;
}
void TypeStore::defineClosure(Type type, std::vector<TypeField> captures,
                              CallableType descriptor) {
  if (!isProduct(type) || product(type).callable < 0)
    throw std::invalid_argument("closure definition requires a closure type");
  descriptor.environment = type;
  descriptor.name = product(type).name;
  bool copy = descriptor.mode != ParameterMode::Take;
  for (const auto &capture : captures)
    copy &= isCopy(capture.type);
  auto &record = products.at(entries.at(type.index() - builtins).index);
  record.fields = std::move(captures);
  record.copyRequested = copy;
  callables.at(static_cast<std::size_t>(record.callable)) =
      std::move(descriptor);
}
bool TypeStore::isFunctionPointer(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Callable;
}
bool TypeStore::isCallable(Type type) const {
  return isFunctionPointer(type) ||
         (isParameter(type) &&
          parameter(type).callableConstraint != Type::Unknown) ||
         (isProduct(type) && product(type).callable >= 0);
}
const CallableType &TypeStore::callable(Type type) const {
  if (isParameter(type))
    return callable(parameter(type).callableConstraint);
  return callables.at(isProduct(type)
                          ? product(type).callable
                          : entries.at(type.index() - builtins).index);
}
bool TypeStore::satisfiesCallable(Type actual, Type contract) const {
  if (!isCallable(actual) || !isFunctionPointer(contract))
    return false;
  const auto &source = callable(actual), &target = callable(contract);
  if (source.variadic != target.variadic)
    return false;
  if ((source.unsafeCall && !target.unsafeCall) || source.abi != target.abi)
    return false;
  if (!std::includes(target.targetFeatures.begin(), target.targetFeatures.end(),
                     source.targetFeatures.begin(),
                     source.targetFeatures.end()))
    return false;
  if (source.result != target.result || source.error != target.error ||
      source.resultSources != target.resultSources ||
      source.resultFromEnvironment != target.resultFromEnvironment ||
      source.parameters.size() != target.parameters.size())
    return false;
  if ((source.mode == ParameterMode::Take &&
       target.mode != ParameterMode::Take) ||
      (source.mode == ParameterMode::Mut && target.mode == ParameterMode::Read))
    return false;
  for (std::size_t p = 0; p < source.parameters.size(); ++p)
    if (source.parameters[p].type != target.parameters[p].type ||
        source.parameters[p].mode != target.parameters[p].mode)
      return false;
  return true;
}
bool TypeStore::constrainCallableParameter(Type type, Type contract) {
  if (!isParameter(type) || !isFunctionPointer(contract))
    return false;
  auto prior = parameter(type).callableConstraint;
  if (prior != Type::Unknown && !satisfiesCallable(prior, contract) &&
      !satisfiesCallable(contract, prior))
    return false;
  if (prior == Type::Unknown || satisfiesCallable(contract, prior))
    parameters.at(entries.at(type.index() - builtins).index)
        .callableConstraint = contract;
  return true;
}
} // namespace mettle
