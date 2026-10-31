#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>

namespace mettle {
bool Checker::eraseCoercion(Node &expression, Type source, Type target,
                            Span span) {
  auto self = source, interface = target;
  if (checked.types->isView(target)) {
    if (!checked.types->isView(source))
      return false;
    const auto &actual = checked.types->view(source);
    const auto &expected = checked.types->view(target);
    if (expected.mode == ParameterMode::Mut &&
        actual.mode != ParameterMode::Mut)
      return false;
    self = actual.payload;
    interface = expected.payload;
  } else if (checked.types->isView(self))
    self = checked.types->view(self).payload;
  auto conversion = checked.types->erasedTail(self, interface);
  if (!conversion)
    return false;
  self = conversion->first;
  interface = conversion->second;
  if (checked.types->isErased(self)) {
    auto parents = interfaces::hierarchy(*checked.types, *checked.interfaceData,
                                         self, self, span, diagnostics);
    if (std::find(parents.begin(), parents.end(), interface) == parents.end()) {
      error(
          "feature", span,
          "this erased conversion requires an explicit sized metadata adapter");
      return true;
    }
  } else if (checked.types->pointerMetadata(self) == PointerMetadata::Witness) {
    error("feature", span,
          "this unsized receiver requires an explicit sized metadata adapter");
    return true;
  }
  if (!interfaceObligation(self, interface, span))
    return true;
  facts(expression).erasedSource = source;
  facts(expression).rebuiltType = target;
  facts(expression).readView =
      checked.types->viewType(target, ParameterMode::Read);
  facts(expression).mutView =
      checked.types->viewType(target, ParameterMode::Mut);
  erasedUses.emplace(interface, span);
  return true;
}

void Checker::finalizeErasure() {
  std::vector<std::pair<Type, Span>> uses(erasedUses.begin(), erasedUses.end());
  std::set<Type> visitedInterfaces;
  std::size_t slotsUsed = 0;
  for (std::size_t next = 0; next < uses.size(); ++next) {
    auto [interface, span] = uses[next];
    if (!visitedInterfaces.insert(interface).second)
      continue;
    std::vector<CallableType> signatures;
    std::vector<Type> owners;
    std::vector<std::size_t> slots;
    auto hierarchy =
        interfaces::hierarchy(*checked.types, *checked.interfaceData, interface,
                              interface, span, diagnostics);
    std::vector<Type> parents(hierarchy.begin() + 1, hierarchy.end());
    for (auto parent : parents)
      uses.emplace_back(parent, span);
    checked.types->setErasedParents(interface, std::move(parents));
    for (auto bound : hierarchy) {
      const auto descriptor = checked.types->erased(bound);
      const auto &definition =
          checked.interfaceData->definitions[descriptor.declaration];
      std::vector<TypeBinding> bindings{{definition.self, interface}};
      interfaces::Solver signatureSolver(*checked.types, *checked.interfaceData,
                                         diagnostics, {{interface, bound}});
      for (std::size_t p = 0;
           p < definition.parameters.size() && p < descriptor.arguments.size();
           ++p)
        bindings.push_back({definition.parameters[p], descriptor.arguments[p]});
      for (std::size_t slot = 0; slot < definition.methods.size(); ++slot) {
        const auto &method = definition.methods[slot];
        owners.push_back(bound);
        slots.push_back(slot);
        const auto &source = module.functions[method.function];
        const auto &function = checked.functions[method.function];
        if (source.asynchronous) {
          error("feature", span,
                "erased async methods require an explicit future-storage "
                "erasure contract");
          signatures.emplace_back();
          signatures.back().result = Type::Unknown;
          continue;
        }
        bool sizedOnly = false;
        for (const auto &constraint : source.constraints)
          if (constraint.subject.name == "Self")
            for (const auto &bound : constraint.bounds)
              sizedOnly |= intrinsicProperty(bound, "Sized", source.span);
        if (sizedOnly) {
          signatures.emplace_back();
          signatures.back().result = Type::Unknown;
          continue;
        }
        bool valid = source.receiver != "static" &&
                     (source.receiver == "read" || source.receiver == "mut" ||
                      source.receiver.empty());
        if (definition.name == "core::future::Future" &&
            method.name == "poll" && source.receiver == "take" &&
            !method.signature.parameters.empty()) {
          const auto receiver = method.signature.parameters.front().type;
          if (checked.types->isProduct(receiver)) {
            const auto &pin = checked.types->product(receiver);
            valid |= pin.kind == AggregateKind::Pin &&
                     !pin.components.empty() &&
                     checked.types->isView(pin.components.front()) &&
                     checked.types->view(pin.components.front()).mode ==
                         ParameterMode::Mut &&
                     (checked.types->view(pin.components.front()).payload ==
                          definition.self ||
                      (!function.genericParameters.empty() &&
                       checked.types->view(pin.components.front()).payload ==
                           function.genericParameters.front()));
          }
        }
        valid &=
            function.genericParameters.size() == method.implicitParameters &&
            !method.signature.parameters.empty();
        auto signature = method.signature;
        std::set<Type> fixedParameters;
        for (auto argument : descriptor.arguments) {
          auto parameters = checked.types->typeParameters(argument);
          fixedParameters.insert(parameters.begin(), parameters.end());
        }
        for (auto associated : descriptor.associated) {
          auto parameters = checked.types->typeParameters(associated.argument);
          fixedParameters.insert(parameters.begin(), parameters.end());
        }
        if (!function.genericParameters.empty())
          bindings.push_back({function.genericParameters[0], interface});
        for (std::size_t p = 1; p < method.implicitParameters &&
                                p < function.genericParameters.size() &&
                                p - 1 < descriptor.arguments.size();
             ++p)
          bindings.push_back(
              {function.genericParameters[p], descriptor.arguments[p - 1]});
        auto normalized = [&](Type type, bool receiver = false) {
          auto result = signatureSolver.normalize(type, bindings, span);
          const auto parameters = checked.types->typeParameters(result);
          valid &= std::all_of(parameters.begin(), parameters.end(),
                               [&](auto parameter) {
                                 return fixedParameters.contains(parameter);
                               });
          if (!receiver) {
            // Test the unsubstituted type: `Self` is bound to the erased
            // interface, which an explicit `any Interface` result also names.
            const auto self = function.genericParameters.empty()
                                  ? Type::Unknown
                                  : function.genericParameters.front();
            std::set<Type> visited;
            std::function<bool(Type)> hasSelf = [&](Type current) {
              if (current == definition.self || current == self)
                return true;
              if (!visited.insert(current).second)
                return false;
              if (checked.types->isView(current))
                return hasSelf(checked.types->view(current).payload);
              if (checked.types->isProduct(current))
                for (const auto &field : checked.types->product(current).fields)
                  if (hasSelf(field.type))
                    return true;
              if (checked.types->isSlice(current))
                return hasSelf(checked.types->slice(current).element);
              if (checked.types->isFunctionPointer(current)) {
                const auto &callable = checked.types->callable(current);
                if (hasSelf(callable.result) ||
                    (callable.error != Type::Unknown &&
                     hasSelf(callable.error)))
                  return true;
                for (const auto &parameter : callable.parameters)
                  if (hasSelf(parameter.type))
                    return true;
              }
              if (checked.types->isErased(current)) {
                const auto &erased = checked.types->erased(current);
                for (auto argument : erased.arguments)
                  if (hasSelf(argument))
                    return true;
                for (const auto &associated : erased.associated)
                  if (hasSelf(associated.argument))
                    return true;
              }
              return false;
            };
            valid &= !hasSelf(type);
          }
          return result;
        };
        for (std::size_t p = 0; p < signature.parameters.size(); ++p)
          signature.parameters[p].type =
              normalized(signature.parameters[p].type, p == 0);
        signature.result = normalized(signature.result);
        if (signature.error != Type::Unknown)
          signature.error = normalized(signature.error);
        signature.abiResult = normalized(signature.abiResult);
        if (checked.types->containsViews(signature.abiResult) ||
            checked.types->isSymbolic(signature.abiResult)) {
          const auto transported =
              checked.types->typeParameters(method.signature.abiResult);
          auto captures = [&](Type type) {
            const auto parameters = checked.types->typeParameters(type);
            return std::any_of(
                parameters.begin(), parameters.end(), [&](auto parameter) {
                  return std::find(transported.begin(), transported.end(),
                                   parameter) != transported.end();
                });
          };
          for (std::size_t p = 0; p < method.signature.parameters.size(); ++p) {
            bool carries = captures(method.signature.parameters[p].type);
            if (p == 0)
              for (std::size_t i = 1; i < method.implicitParameters &&
                                      i < function.genericParameters.size();
                   ++i)
                carries |= captures(function.genericParameters[i]);
            if (carries && std::find(signature.resultSources.begin(),
                                     signature.resultSources.end(),
                                     p) == signature.resultSources.end())
              signature.resultSources.push_back(p);
          }
          std::sort(signature.resultSources.begin(),
                    signature.resultSources.end());
        }
        signature.mode = ParameterMode::Take;
        if (!valid)
          error(
              "type", span,
              "interface method is not dispatchable with this erased contract");
        signatures.push_back(std::move(signature));
      }
    }
    checked.types->setErasedMethods(interface, std::move(signatures));
    checked.types->setErasedDispatch(interface, std::move(owners),
                                     std::move(slots));
    const auto &completed = checked.types->erased(interface);
    slotsUsed +=
        5 + completed.methodTypes.size() + completed.parentInterfaces.size();
    if (slotsUsed > limits::witnessSlots) {
      error("limit", span, "erased witness table limit exceeded");
      return;
    }
  }
}
} // namespace mettle
