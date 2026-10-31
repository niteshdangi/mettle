#include "instances/specialize.h"
#include "instances/arrays.h"
#include "instances/callables.h"
#include "support/limits.h"
#include "support/path.h"
#include "types/layout.h"
#include <algorithm>
#include <functional>
#include <map>
#include <set>
#include <stdexcept>

namespace mettle::instances {
namespace {
struct LocatedLimit : std::length_error {
  LocatedLimit(const std::string &message, Span span)
      : std::length_error(message), span(span) {}
  Span span;
};
class Planner {
public:
  Planner(const ir::Program &source, Diagnostics &diagnostics,
          const Hooks &hooks)
      : source(source), diagnostics(diagnostics),
        types(std::make_shared<TypeStore>(*source.types)), hooks(hooks) {
    result.types = types;
    result.requireEntry = source.requireEntry;
    result.statics = source.statics;
    result.staticPackages = source.staticPackages;
    result.libraries = source.libraries;
    result.target = source.target;
  }
  std::optional<ir::Program> run() {
    try {
      for (std::size_t i = 0; i < source.functions.size(); ++i)
        if (source.functions[i].genericParameters.empty() &&
            !source.functions[i].declarationOnly)
          instance(i, {}, {});
      prepareDynamicDrops();
      std::function<void(StaticConstant &)> constant =
          [&](StaticConstant &value) {
            if (value.kind == StaticConstant::Kind::Function)
              value.symbol = instance(value.symbol, {}, {});
            for (auto &field : value.fields)
              constant(field);
          };
      for (auto &storage : result.statics)
        if (storage.initializer) {
          destructor(storage.type, storage.span);
          constant(*storage.initializer);
        }
      result.globalAssembly = source.globalAssembly;
      for (auto &assembly : result.globalAssembly)
        specializeAssembly(assembly, {});
    } catch (const std::invalid_argument &failure) {
      diagnostics.error("type", {}, failure.what());
    } catch (const LocatedLimit &failure) {
      diagnostics.error("limit", failure.span, failure.what());
    } catch (const std::length_error &failure) {
      diagnostics.error("limit", {}, failure.what());
    }
    if (!diagnostics.empty())
      return std::nullopt;
    return std::move(result);
  }

private:
  const ir::Program &source;
  Diagnostics &diagnostics;
  std::shared_ptr<TypeStore> types;
  const Hooks &hooks;
  ir::Program result;
  using Key = std::pair<std::size_t, std::vector<Type>>;
  std::map<Key, int> instances;
  std::map<std::pair<Type, Type>, int> callableAdapters;
  std::map<Type, int> callableContracts;
  std::map<Type, int> coroutineBodies;
  std::set<Type> visitedTypes;
  unsigned instanceDepth = 0;
  Type dropElement(Type payload) const {
    if (types->isSlice(payload))
      return types->slice(payload).element;
    return types->isSized(payload) ? payload : Type::Unknown;
  }
  void prepareDynamicDrops() {
    int helper = -1;
    for (std::size_t i = 0; i < source.functions.size(); ++i)
      if (displayPath(source.functions[i].name) ==
          "core.slice.drop_values") {
        helper = static_cast<int>(i);
        break;
      }

    std::map<Type, Span> requested;
    auto request = [&](Type payload, Span span) {
      auto element = dropElement(payload);
      if (element != Type::Unknown && types->needsDrop(element))
        requested.try_emplace(element, span);
    };
    for (const auto &function : result.functions)
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions) {
          if (instruction.op == ir::Op::OwnerUnsize) {
            auto sourcePayload =
                types->product(instruction.operands.front().type)
                    .genericArguments.front();
            auto targetPayload =
                types->product(instruction.result.type).genericArguments.front();
            if (types->isSlice(targetPayload))
              request(targetPayload, instruction.span);
            else if (instruction.interfaceType != Type::Unknown)
              request(sourcePayload, instruction.span);
            else if (types->needsDrop(targetPayload))
              diagnostics.error(
                  "feature", instruction.span,
                  "dynamic drop for this unsized owner payload is unsupported");
          } else if (instruction.op == ir::Op::EraseView) {
            if (dropElement(instruction.interfaceSelf) == Type::Unknown &&
                types->needsDrop(instruction.interfaceSelf))
              diagnostics.error(
                  "feature", instruction.span,
                  "dynamic drop for this erased unsized payload is unsupported");
            else
              request(instruction.interfaceSelf, instruction.span);
          } else if (instruction.op == ir::Op::DropPlace) {
            auto payload = projectedType(
                *types, function.locals[instruction.place.root].type,
                instruction.place.fields);
            if (payload && (types->isSlice(*payload) ||
                            types->isErased(*payload))) {
              if (!types->isErased(*payload))
                request(*payload, instruction.span);
            } else if (payload &&
                       types->pointerMetadata(*payload) ==
                           PointerMetadata::ElementCount &&
                       types->needsDrop(*payload))
              diagnostics.error(
                  "feature", instruction.span,
                  "dynamic drop for this unsized payload is unsupported");
            }
          }
        }

    std::map<Type, int> specialized;
    for (const auto &[element, span] : requested) {
      if (helper < 0) {
        diagnostics.error(
            "feature", span,
            "dynamic drop requires core.slice.drop_values");
        continue;
      }
      specialized.emplace(element,
                          instance(static_cast<std::size_t>(helper), {element},
                                   span));
    }

    auto functionFor = [&](Type payload) {
      auto element = dropElement(payload);
      auto found = specialized.find(element);
      return found == specialized.end() ? -1 : found->second;
    };
    std::map<Type, int> dynamicDrops;
    for (auto &function : result.functions)
      for (auto &block : function.blocks)
        for (auto &instruction : block.instructions) {
          if (instruction.op == ir::Op::OwnerUnsize) {
            auto sourcePayload =
                types->product(instruction.operands.front().type)
                    .genericArguments.front();
            auto targetPayload =
                types->product(instruction.result.type).genericArguments.front();
            instruction.dropFunction =
                instruction.interfaceType != Type::Unknown
                    ? functionFor(sourcePayload)
                : types->isSlice(targetPayload)
                    ? functionFor(targetPayload)
                    : -1;
            if (instruction.interfaceType != Type::Unknown &&
                instruction.dropFunction >= 0)
              dynamicDrops.emplace(sourcePayload,
                                   instruction.dropFunction);
          } else if (instruction.op == ir::Op::EraseView) {
            instruction.dropFunction =
                functionFor(instruction.interfaceSelf);
            if (instruction.dropFunction >= 0)
              dynamicDrops.emplace(instruction.interfaceSelf,
                                   instruction.dropFunction);
          } else if (instruction.op == ir::Op::DropPlace) {
            auto payload = projectedType(
                *types, function.locals[instruction.place.root].type,
                instruction.place.fields);
            if (payload && types->isSlice(*payload))
              instruction.dropFunction = functionFor(*payload);
          }
        }
    result.dynamicDropFunctions.assign(dynamicDrops.begin(),
                                       dynamicDrops.end());
  }
  void specializeAssembly(Assembly &assembly,
                          std::span<const TypeBinding> bindings) {
    for (auto &operand : assembly.operands) {
      if (operand.mode == AssemblyMode::Const) {
        operand.constantIdentity =
            types->substitute(operand.constantIdentity, bindings);
        auto value = types->scalarConstantValue(operand.constantIdentity);
        if (!value)
          throw std::invalid_argument(
              "assembly const requires a resolved integer constant");
        operand.constant = *value;
        operand.type = types->parameter(operand.constantIdentity).valueType;
      } else if (operand.mode == AssemblyMode::Sym &&
                 operand.symbolKind == AssemblyOperand::SymbolKind::Function) {
        auto arguments = operand.symbolArguments;
        for (auto &argument : arguments)
          argument = types->substitute(argument, bindings);
        operand.symbol = instance(operand.symbol, arguments, {});
        operand.symbolArguments.clear();
      } else if (operand.mode != AssemblyMode::Const)
        operand.type =
            types->eraseRegions(types->substitute(operand.type, bindings));
      operand.inputType =
          types->eraseRegions(types->substitute(operand.inputType, bindings));
    }
  }
  int closureBody(Type receiver, Span span) {
    const auto &signature = types->callable(receiver);
    if (signature.function < 0 ||
        static_cast<std::size_t>(signature.function) >=
            source.closureFunctions.size())
      throw std::invalid_argument("callable environment has no generated body");
    auto body = source.closureFunctions[signature.function];
    auto arguments = types->product(receiver).genericOrigin == Type::Unknown
                         ? source.functions[body].genericParameters
                         : types->product(receiver).genericArguments;
    return instance(static_cast<std::size_t>(body), arguments, span);
  }
  // The body of a coroutine state is its closure's instance, marked so the
  // backend lays out its frame inside the state.
  int coroutineBody(Type state, Span span) {
    if (auto found = coroutineBodies.find(state);
        found != coroutineBodies.end())
      return found->second;
    auto closure = types->product(state).components[1];
    if (!types->isCallable(closure) || types->isFunctionPointer(closure))
      throw std::invalid_argument("coroutine body is not a closure");
    auto function = types->callable(closure).function;
    if (function < 0 ||
        static_cast<std::size_t>(function) >= source.closureFunctions.size() ||
        !source.functions[source.closureFunctions[function]].coroutine)
      throw std::invalid_argument("coroutine body is not an async closure");
    auto body = closureBody(closure, span);
    coroutineBodies.emplace(state, body);
    result.coroutines.emplace_back(state, body);
    return body;
  }
  int adaptCallable(Type receiver, Type contract, Span span) {
    if (!types->satisfiesCallable(receiver, contract))
      throw std::invalid_argument(
          "concrete callable does not satisfy its declared capability");
    auto key = std::pair{receiver, contract};
    if (auto found = callableAdapters.find(key);
        found != callableAdapters.end())
      return found->second;
    if (result.functions.size() + 2 >= limits::functions)
      throw std::length_error("callable specialization limit exceeded");
    auto id = static_cast<int>(result.functions.size());
    callableAdapters.emplace(key, id);
    result.functions.emplace_back();
    result.functionPackages.emplace_back();
    int callee;
    if (types->isFunctionPointer(receiver)) {
      auto [entry, inserted] = callableContracts.emplace(receiver, -1);
      if (inserted) {
        entry->second = static_cast<int>(result.functions.size());
        result.functions.push_back(callableContract(receiver, *types));
        result.functionPackages.emplace_back();
      }
      callee = entry->second;
    } else
      callee = closureBody(receiver, span);
    result.functions[id] =
        callableAdapter(receiver, contract, callee, *types,
                        "<callable-adapter-" + std::to_string(id) + ">");
    return id;
  }
  void concrete(Type type, Span span) {
    if (type == Type::Unknown || types->isSymbolic(type))
      diagnostics.error("type", span,
                        "generic instance contains an unresolved parameter");
    else if (types->isProduct(type) && types->isSized(type)) {
      auto layout = objectLayout(*types, type);
      if (!layout && !coroutineDependent(*types, type))
        diagnostics.error(
            "attribute", span,
            "object layout cannot be established for this representation");
      else if (layout && layout->size > limits::objectBytes)
        diagnostics.error("limit", span,
                          "array size exceeds target address space");
    }
  }
  void destructor(Type type, Span span) {
    if (!visitedTypes.insert(type).second)
      return;
    if (types->isView(type)) {
      destructor(types->view(type).payload, span);
      return;
    }
    if (!types->isProduct(type))
      return;
    auto product = types->product(type);
    if (product.hasDestructor && product.destructor >= 0) {
      auto index = static_cast<std::size_t>(product.destructor);
      if (index >= source.functions.size())
        throw std::invalid_argument(
            "generic destructor refers to an invalid function");
      auto arguments = source.functions[index].genericParameters.empty()
                           ? std::vector<Type>{}
                           : product.genericArguments;
      auto selected = instance(index, std::move(arguments), span);
      types->setDestructor(type, selected);
    }
    for (const auto &field : product.fields)
      destructor(field.type, span);
  }
  int instance(std::size_t index, std::vector<Type> arguments, Span span) {
    if (index >= source.functions.size())
      throw std::invalid_argument(
          "generic call refers to an invalid declaration");
    const auto &declaration = source.functions[index];
    if (declaration.declarationOnly)
      throw std::invalid_argument(
          "interface call has no uniquely selected concrete implementation");
    if (declaration.genericParameters.size() != arguments.size())
      throw std::invalid_argument(
          "generic instance argument count does not match");
    Key key{index, arguments};
    if (auto found = instances.find(key); found != instances.end())
      return found->second;
    if (instanceDepth >= limits::typeDepth)
      throw LocatedLimit("generic specialization nesting limit exceeded "
                         "while instantiating '" +
                             displayPath(declaration.name) + "'",
                         span);
    for (auto argument : arguments)
      if (types->name(argument).size() > limits::typeNameBytes)
        throw LocatedLimit("generic specialization type grows beyond the "
                           "compiler size limit while instantiating '" +
                               displayPath(declaration.name) + "'",
                           span);
    struct Scope {
      unsigned &depth;
      explicit Scope(unsigned &depth) : depth(depth) { ++depth; }
      ~Scope() { --depth; }
    } scope(instanceDepth);
    if (instances.size() >= limits::functions)
      throw std::length_error("generic specialization limit exceeded");
    std::vector<TypeBinding> bindings;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      concrete(arguments[i], span);
      bindings.push_back({declaration.genericParameters[i], arguments[i]});
    }
    auto id = static_cast<int>(result.functions.size());
    const bool genericInstance = !arguments.empty();
    instances.emplace(std::move(key), id);
    result.functions.emplace_back();
    result.functionPackages.push_back(
        genericInstance || index >= source.functionPackages.size()
            ? std::string{}
            : source.functionPackages[index]);
    auto function = declaration;
    function.genericParameters.clear();
    if (!arguments.empty()) {
      function.name += ".<";
      for (std::size_t i = 0; i < arguments.size(); ++i) {
        if (i)
          function.name += ",";
        function.name += types->name(arguments[i]);
      }
      function.name += ">";
      // A generic indirect contract is declared by external name; each
      // instance has its own signature, so it needs its own symbol.
      if (function.indirectContract)
        function.externalName += "." + std::to_string(id);
    }
    // Instructions repeat a handful of types; a result is cached only after
    // it was fully validated without diagnostics.
    std::map<std::pair<Type, bool>, Type> resolved;
    auto substitute = [&](Type &type, bool runtime = true) {
      if (auto known = resolved.find({type, runtime});
          known != resolved.end()) {
        type = known->second;
        return;
      }
      const auto original = type;
      type = types->substitute(type, bindings);
      if (hooks.normalizeType)
        type = hooks.normalizeType(type, bindings, *types, diagnostics);
      if (runtime)
        type = types->eraseRegions(type);
      if (type != Type::Unknown) {
        concrete(type, span);
        destructor(type, span);
      }
      if (diagnostics.empty())
        resolved.emplace(std::pair{original, runtime}, type);
    };
    substitute(function.result);
    for (auto &local : function.locals)
      substitute(local.type);
    function.interfaceBounds.clear();
    function.unpinBounds.clear();
    function.regionSignature =
        types->substitute(function.regionSignature, bindings);
    function.genericEqualities.clear();
    if (types->containsViews(function.result))
      for (auto source : function.genericResultSources) {
        if (source >= function.parameters)
          throw std::invalid_argument(
              "generic result source is not a parameter");
        // Only views carried by the instantiated argument can flow into the
        // result; the borrow of a `read`/`mut` parameter itself does not.
        const auto &parameter = function.locals[source];
        if (!types->containsViews(parameter.type) ||
            std::find(function.resultSources.begin(),
                      function.resultSources.end(),
                      source) != function.resultSources.end())
          continue;
        function.resultSources.push_back(source);
        if (parameter.mode == ParameterMode::Read ||
            parameter.mode == ParameterMode::Mut)
          function.resultContents.push_back(source);
      }
    function.genericResultSources.clear();
    if (function.nakedAssembly)
      specializeAssembly(*function.nakedAssembly, bindings);
    for (auto &block : function.blocks) {
      if (block.exit.kind != ir::Exit::None)
        substitute(block.exit.value.type);
      for (auto &instruction : block.instructions) {
        for (auto &[subject, runtime] : instruction.unpinProofs) {
          if (!hooks.validateUnpin)
            throw std::invalid_argument("Unpin instance proof is unavailable");
          subject = hooks.validateUnpin(subject, bindings, function,
                                        instruction.span, *types, diagnostics);
          substitute(runtime);
        }
        if (instruction.assembly)
          specializeAssembly(*instruction.assembly, bindings);
        substitute(instruction.result.type);
        substitute(instruction.indirectType);
        substitute(instruction.opaqueType);
        substitute(instruction.interfaceType, false);
        substitute(instruction.interfaceSelf, false);
        substitute(instruction.target.type);
        for (auto &projection : instruction.place.fields)
          substitute(projection.type);
        for (auto &operand : instruction.operands)
          substitute(operand.type);
        for (auto &argument : instruction.typeArguments)
          substitute(argument, false);
        for (auto &entry : instruction.witnessEntries)
          substitute(entry.owner, false);
        if (instruction.constantParameter != Type::Unknown) {
          auto identity =
              types->substitute(instruction.constantParameter, bindings);
          if (hooks.normalizeType)
            identity =
                hooks.normalizeType(identity, bindings, *types, diagnostics);
          auto value = types->scalarConstantValue(identity);
          if (!value)
            diagnostics.error(
                "type", instruction.span,
                "const parameter did not evaluate in generic instance");
          else {
            instruction.numeric = *value;
            if (instruction.result.type == Type::I32 ||
                instruction.result.type == Type::Bool ||
                instruction.result.type == Type::Char ||
                instruction.result.type == Type::U8)
              instruction.number =
                  static_cast<std::int32_t>(*types->constantValue(identity));
          }
          instruction.constantParameter = Type::Unknown;
        }
        if (hooks.selectCall &&
            !hooks.selectCall(instruction, bindings, *types, diagnostics))
          continue;
        if (instruction.op == ir::Op::IndirectCall &&
            instruction.target.type != instruction.indirectType) {
          instruction.callee =
              adaptCallable(instruction.target.type, instruction.indirectType,
                            instruction.span);
          instruction.op = ir::Op::Call;
          instruction.operands.insert(instruction.operands.begin(),
                                      instruction.target);
          instruction.target = {};
          instruction.indirectType = Type::Unknown;
          instruction.typeArguments.clear();
          continue;
        }
        if (instruction.op == ir::Op::Machine &&
            (instruction.text == "coroutine.start" ||
             instruction.text == "coroutine.resume")) {
          instruction.callee =
              coroutineBody(instruction.typeArguments.at(0), instruction.span);
          continue;
        }
        if (instruction.callee >= 0) {
          instruction.callee =
              instance(static_cast<std::size_t>(instruction.callee),
                       instruction.typeArguments, instruction.span);
          instruction.typeArguments.clear();
        }
      }
    }
    for (auto &loop : function.arrayLoops) {
      substitute(loop.index.type);
      for (auto &projection : loop.source.fields)
        substitute(projection.type);
    }
    expandArrays(function, *types);
    result.functions[id] = std::move(function);
    return id;
  }
};
} // namespace
std::optional<ir::Program> specialize(const ir::Program &declarations,
                                      Diagnostics &diagnostics,
                                      const Hooks &hooks) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Planner(declarations, diagnostics, hooks).run();
}
} // namespace mettle::instances
