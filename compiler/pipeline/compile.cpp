#include "pipeline/compile.h"
#include "analysis/initialization.h"
#include "analysis/loans.h"
#include "cleanup/plan.h"
#include "instances/specialize.h"
#include "ir/verify.h"
#include "lowering/scalar.h"
#include "resolution/load.h"
#include "resolution/resolve.h"
#include "semantics/check.h"
#include "semantics/interfaces.h"
#include "syntax/parser.h"
#include <map>

namespace mettle::pipeline {
class Compiler {
public:
  static std::optional<ir::VerifiedProgram>
  admit(ir::Program program, Diagnostics &diagnostics,
        const ir::UnpinProof &proof = {}) {
    if (!diagnostics.empty())
      return std::nullopt;
    if (!program.types) {
      ir::verify(program, diagnostics);
      return std::nullopt;
    }
    for (const auto &function : program.functions) {
      bool concrete = function.genericParameters.empty() &&
                      !function.declarationOnly &&
                      !program.types->isSymbolic(function.result);
      for (const auto &local : function.locals)
        concrete &= !program.types->isSymbolic(local.type);
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions) {
          concrete &= !program.types->isSymbolic(instruction.result.type);
          if (instruction.op == ir::Op::ArrayRepeat)
            concrete &= program.types->compactArray(instruction.result.type);
          if (instruction.op == ir::Op::ArrayTake &&
              program.types->needsDrop(instruction.result.type))
            diagnostics.error("feature", instruction.span,
                              "by-value iteration over a large array of "
                              "droppable elements is not implemented");
        }
      if (!concrete)
        diagnostics.error(
            "internal", {},
            "uninstantiated declaration reached executable admission");
    }
    if (!diagnostics.empty() || !ir::verify(program, diagnostics, {}, proof))
      return std::nullopt;
    for (const auto &function : program.functions) {
      if (function.blocks.empty())
        continue;
      try {
        cleanup::plan(function, *program.types);
      } catch (const std::length_error &error) {
        auto local = function.parameters < function.locals.size()
                         ? function.parameters
                         : std::size_t{0};
        diagnostics.error("limit",
                          function.locals.empty() ? Span{}
                                                  : function.locals[local].span,
                          error.what());
      }
    }
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::initialization(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::loans(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    return ir::VerifiedProgram(std::move(program));
  }
  static std::optional<ir::VerifiedProgram>
  run(Module tree, Diagnostics &diagnostics, bool requireEntry = true,
      TargetFacts target = {}, const CheckedObserver &observe = {}) {
    if (!diagnostics.empty())
      return std::nullopt;
    auto resolved = resolution::resolve(tree, diagnostics);
    if (!resolved)
      return std::nullopt;
    auto checked = check(std::move(tree), diagnostics, std::move(resolved),
                         requireEntry, std::move(target));
    if (!checked)
      return std::nullopt;
    if (observe)
      observe(*checked);
    auto program = lowering::lower(*checked, diagnostics);
    program.requireEntry = requireEntry;
    auto types = std::make_shared<TypeStore>(*program.types);
    program.types = types;
    auto proveUnpin = [&](TypeStore &store, Type subject, Type runtime,
                          const ir::Function &function, Span span) {
      std::vector<interfaces::Obligation> assumptions;
      for (auto [type, bound] : function.interfaceBounds)
        assumptions.push_back({type, bound});
      for (auto type : function.unpinBounds)
        assumptions.push_back(
            {type, Type::Unknown, interfaces::Property::Unpin});
      RegionEnvironment regions;
      if (store.isFunctionPointer(function.regionSignature)) {
        const auto &signature = store.callable(function.regionSignature);
        regions.universe = signature.regionUniverse;
        regions.assumptions = signature.regionRequirements;
      }
      interfaces::Solver solver(store, checked->interfaceDatabase(),
                                diagnostics, assumptions, regions);
      interfaces::Solver runtimeTypes(store, checked->interfaceDatabase(),
                                      diagnostics, std::move(assumptions),
                                      std::move(regions), true);
      solver.setEqualities(function.genericEqualities);
      runtimeTypes.setEqualities(function.genericEqualities);
      subject = solver.normalize(subject, function.genericEqualities, span);
      return solver.prove({subject, Type::Unknown, interfaces::Property::Unpin},
                          span, false) &&
             store.eraseRegions(runtimeTypes.normalize(
                 subject, function.genericEqualities, span)) == runtime;
    };
    auto declarationProof = [&](Type subject, Type runtime,
                                const ir::Function &function, Span span) {
      return proveUnpin(*types, subject, runtime, function, span);
    };
    lowering::opaqueAdapters(program, *types, checked->interfaceDatabase(),
                             diagnostics);
    // Declaration-only normalization of a type is fixed per function.
    std::map<std::pair<const ir::Function *, Type>, Type> declared;
    auto normalize = [&](Type type, std::span<const TypeBinding> bindings,
                         const ir::Function &function) {
      if (bindings.empty())
        if (auto known = declared.find({&function, type});
            known != declared.end())
          return known->second;
      std::vector<interfaces::Obligation> assumptions;
      for (auto [subject, interface] : function.interfaceBounds)
        assumptions.push_back({subject, interface});
      interfaces::Solver declarations(*types, checked->interfaceDatabase(),
                                      diagnostics, std::move(assumptions), {},
                                      true);
      std::vector<TypeBinding> substitutions(bindings.begin(), bindings.end());
      substitutions.insert(substitutions.end(),
                           function.genericEqualities.begin(),
                           function.genericEqualities.end());
      auto normalized =
          types->eraseRegions(declarations.normalize(type, substitutions, {}));
      if (bindings.empty())
        declared.emplace(std::pair{&function, type}, normalized);
      return normalized;
    };
    for (auto &function : program.functions) {
      auto valueType = [&](ir::Value &value) {
        value.type = normalize(value.type, {}, function);
      };
      function.result = normalize(function.result, {}, function);
      for (auto &local : function.locals)
        local.type = normalize(local.type, {}, function);
      for (auto &block : function.blocks) {
        for (auto &instruction : block.instructions) {
          valueType(instruction.result);
          for (auto &operand : instruction.operands)
            valueType(operand);
          valueType(instruction.target);
          instruction.indirectType =
              normalize(instruction.indirectType, {}, function);
          instruction.interfaceSelf =
              normalize(instruction.interfaceSelf, {}, function);
          instruction.interfaceType =
              normalize(instruction.interfaceType, {}, function);
          instruction.opaqueType =
              normalize(instruction.opaqueType, {}, function);
          instruction.constantParameter =
              normalize(instruction.constantParameter, {}, function);
          for (auto &argument : instruction.typeArguments)
            argument = normalize(argument, {}, function);
          for (auto &[subject, runtime] : instruction.unpinProofs)
            runtime = normalize(subject, {}, function);
          for (auto &entry : instruction.witnessEntries)
            entry.owner = normalize(entry.owner, {}, function);
          lowering::witnessSlots(instruction, *types, diagnostics);
          for (auto &projection : instruction.place.fields)
            projection.type = normalize(projection.type, {}, function);
        }
        valueType(block.exit.value);
      }
    }
    if (!diagnostics.empty() ||
        !ir::verify(program, diagnostics, normalize, declarationProof))
      return std::nullopt;
    analysis::initialization(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::loans(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    instances::Hooks hooks;
    hooks.validateUnpin = [&](Type subject,
                              std::span<const TypeBinding> bindings,
                              const ir::Function &function, Span span,
                              TypeStore &store, Diagnostics &errors) {
      RegionEnvironment regions;
      if (store.isFunctionPointer(function.regionSignature)) {
        const auto &signature = store.callable(function.regionSignature);
        regions.universe = signature.regionUniverse;
        regions.assumptions = signature.regionRequirements;
      }
      interfaces::Solver solver(store, checked->interfaceDatabase(), errors, {},
                                std::move(regions));
      auto actual = solver.normalize(subject, bindings, span);
      if (!solver.prove({actual, Type::Unknown, interfaces::Property::Unpin},
                        span, false))
        errors.error("type", span, "generic instance does not satisfy Unpin");
      return actual;
    };
    hooks.normalizeType = [&](Type type, std::span<const TypeBinding> bindings,
                              TypeStore &store, Diagnostics &errors) {
      interfaces::Solver solver(store, checked->interfaceDatabase(), errors, {},
                                {}, true);
      return store.eraseRegions(solver.normalize(type, bindings, {}));
    };
    hooks.selectCall = [&](ir::Instruction &call,
                           std::span<const TypeBinding> bindings,
                           TypeStore &store, Diagnostics &errors) {
      if (call.op == ir::Op::WitnessMethod || call.op == ir::Op::EraseView ||
          call.op == ir::Op::ErasedUpcast) {
        interfaces::Solver solver(store, checked->interfaceDatabase(), errors,
                                  {}, {}, true);
        call.interfaceType =
            solver.normalize(call.interfaceType, bindings, call.span);
        call.interfaceSelf =
            solver.normalize(call.interfaceSelf, bindings, call.span);
        for (auto &entry : call.witnessEntries)
          entry.owner = solver.normalize(entry.owner, bindings, call.span);
        return lowering::witnessSlots(call, store, errors);
      }
      if (call.interfaceMethod < 0)
        return true;
      interfaces::Solver solver(store, checked->interfaceDatabase(), errors, {},
                                {}, true);
      // Selection is by type identity; a family projection resolves to an
      // iterator type that still names the caller's regions.
      auto self = store.eraseRegions(
          solver.normalize(call.interfaceSelf, bindings, call.span));
      auto interface =
          solver.normalize(call.interfaceType, bindings, call.span);
      const auto &definition =
          checked->interfaceDatabase()
              .definitions[store.erased(interface).declaration];
      auto prefix = definition.methods[call.interfaceMethod].implicitParameters;
      std::vector<Type> methodArguments;
      for (std::size_t i = prefix; i < call.typeArguments.size(); ++i)
        methodArguments.push_back(
            solver.normalize(call.typeArguments[i], bindings, call.span));
      if (store.isOpaque(self)) {
        for (const auto &adapter : program.opaqueAdapters) {
          if (adapter.method != call.interfaceMethod ||
              store.erased(adapter.interfaceType).declaration !=
                  store.erased(interface).declaration ||
              adapter.methodArguments.size() != methodArguments.size())
            continue;
          auto substitutions = solver.match(adapter.self, self);
          if (!substitutions)
            continue;
          bool valid = true;
          for (std::size_t i = 0; i < methodArguments.size(); ++i) {
            auto pattern = adapter.methodArguments[i];
            if (store.isParameter(pattern))
              substitutions->push_back({pattern, methodArguments[i]});
            else
              valid &= solver.normalize(pattern, *substitutions, call.span) ==
                       methodArguments[i];
          }
          if (!valid)
            continue;
          call.callee = adapter.function;
          call.typeArguments.clear();
          for (auto parameter :
               program.functions[adapter.function].genericParameters)
            call.typeArguments.push_back(
                solver.normalize(parameter, *substitutions, call.span));
          call.interfaceMethod = -1;
          call.interfaceSelf = call.erasedDispatch ? self : Type::Unknown;
          call.interfaceType = call.erasedDispatch ? interface : Type::Unknown;
          return true;
        }
        errors.error("internal", call.span, "missing opaque interface adapter");
        return false;
      }
      auto selected = solver.method(self, interface, call.interfaceMethod,
                                    methodArguments, call.span);
      if (!selected)
        return false;
      call.callee = selected->function;
      call.typeArguments = std::move(selected->arguments);
      call.interfaceMethod = -1;
      call.interfaceSelf = call.erasedDispatch ? self : Type::Unknown;
      call.interfaceType = call.erasedDispatch ? interface : Type::Unknown;
      return true;
    };
    auto concrete = instances::specialize(program, diagnostics, hooks);
    if (!concrete)
      return std::nullopt;
    auto concreteTypes = std::make_shared<TypeStore>(*concrete->types);
    concrete->types = concreteTypes;
    auto concreteProof = [&](Type subject, Type runtime,
                             const ir::Function &function, Span span) {
      return proveUnpin(*concreteTypes, subject, runtime, function, span);
    };
    return admit(std::move(*concrete), diagnostics, concreteProof);
  }
};
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics) {
  return Compiler::admit(std::move(program), diagnostics);
}
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics) {
  return compile(std::vector<Source>{source}, diagnostics);
}
std::optional<ir::VerifiedProgram> compile(const std::vector<Source> &sources,
                                           Diagnostics &diagnostics,
                                           const resolution::Library &library) {
  auto tree = resolution::load(sources, diagnostics, library);
  if (!tree)
    return std::nullopt;
  return Compiler::run(std::move(*tree), diagnostics);
}
std::optional<ir::VerifiedProgram>
compile(Module module, Diagnostics &diagnostics, bool requireEntry,
        TargetFacts target, const CheckedObserver &observe) {
  return Compiler::run(std::move(module), diagnostics, requireEntry,
                       std::move(target), observe);
}
} // namespace mettle::pipeline
