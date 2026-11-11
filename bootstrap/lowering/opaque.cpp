#include "lowering/builder.h"
#include "lowering/scalar.h"
#include <algorithm>
#include <functional>
#include <map>
#include <set>
#include <tuple>

namespace mettle::lowering {
void opaqueAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database,
                    Diagnostics &diagnostics) {
  using Key = std::tuple<Type, Type, int, std::vector<Type>>;
  std::map<Key, int> cache;
  std::vector<ir::Function> adapters;
  interfaces::Solver solver(types, database, diagnostics, {}, {}, true);
  auto adapt = [&](ir::Instruction &call) {
    if (call.op != ir::Op::Call || call.interfaceMethod < 0 ||
        !types.isOpaque(call.interfaceSelf))
      return;
    auto opaque = call.interfaceSelf;
    auto hidden = types.product(opaque).fields[0].type;
    if (hidden == Type::Unknown) {
      diagnostics.error("type", call.span,
                        "opaque result has no established hidden type");
      return;
    }
    Key key{opaque, call.interfaceType, call.interfaceMethod,
            call.typeArguments};
    auto [found, inserted] = cache.try_emplace(
        key, static_cast<int>(program.functions.size() + adapters.size()));
    const auto &definition =
        database.definitions[types.erased(call.interfaceType).declaration];
    auto prefix = definition.methods[call.interfaceMethod].implicitParameters;
    if (inserted)
      for (const auto &existing : program.opaqueAdapters)
        if (existing.self == opaque &&
            existing.interfaceType == call.interfaceType &&
            existing.method == call.interfaceMethod &&
            call.typeArguments.size() >= prefix &&
            existing.methodArguments ==
                std::vector<Type>(call.typeArguments.begin() + prefix,
                                  call.typeArguments.end())) {
          found->second = existing.function;
          inserted = false;
          break;
        }
    if (inserted) {
      ir::Function adapter{"<opaque-adapter." +
                               std::to_string(adapters.size()) + ">",
                           call.result.type,
                           call.operands.size(),
                           {},
                           {},
                           0};
      adapter.blocks.emplace_back();
      auto &instructions = adapter.blocks[0].instructions;
      auto emit = [&](ir::Instruction instruction, Type type,
                      ir::Access access = ir::Access::Owned) {
        instruction.result = {adapter.values++, type, access};
        auto result = instruction.result;
        instructions.push_back(std::move(instruction));
        return result;
      };
      auto parameters = types.typeParameters(opaque);
      for (auto type : call.typeArguments) {
        auto extra = types.typeParameters(type);
        parameters.insert(parameters.end(), extra.begin(), extra.end());
      }
      std::sort(parameters.begin(), parameters.end());
      parameters.erase(std::unique(parameters.begin(), parameters.end()),
                       parameters.end());
      adapter.genericParameters = std::move(parameters);
      const auto &declaration = program.functions[call.callee];
      adapter.targetFeatures = declaration.targetFeatures;
      adapter.resultSources = declaration.resultSources;
      adapter.genericResultSources = declaration.genericResultSources;
      std::vector<TypeBinding> signatureBindings;
      for (std::size_t p = 0; p < declaration.genericParameters.size(); ++p)
        signatureBindings.push_back(
            {declaration.genericParameters[p], call.typeArguments[p]});
      adapter.regionSignature = solver.normalize(declaration.regionSignature,
                                                 signatureBindings, call.span);
      std::vector<TypeBinding> reveal{{opaque, hidden}};
      std::vector<ir::Value> operands;
      for (std::size_t p = 0; p < call.operands.size(); ++p) {
        auto type = call.operands[p].type;
        auto mode = declaration.locals[p].mode;
        adapter.locals.push_back({"argument", type, false, call.span, mode, 0,
                                  static_cast<std::uint32_t>(p)});
        auto access = call.operands[p].access;
        auto value = emit({access == ir::Access::Read  ? ir::Op::BorrowRead
                           : access == ir::Access::Mut ? ir::Op::BorrowMut
                           : mode == ParameterMode::Take || !types.isCopy(type)
                               ? ir::Op::Move
                               : ir::Op::Load,
                           {},
                           {},
                           {},
                           "",
                           {static_cast<int>(p), {}},
                           -1,
                           0,
                           call.span},
                          type, access);
        auto target = solver.normalize(type, reveal, call.span);
        if (target != type) {
          ir::Instruction repack{ir::Op::OpaqueRepack,
                                 {},
                                 {value},
                                 {},
                                 "",
                                 {-1, {}},
                                 -1,
                                 0,
                                 call.span};
          repack.opaqueType = opaque;
          value = emit(std::move(repack), target, access);
        }
        operands.push_back(value);
      }
      auto implementation = call;
      implementation.operands = std::move(operands);
      implementation.interfaceSelf = hidden;
      implementation.interfaceType =
          solver.normalize(implementation.interfaceType, reveal, call.span);
      for (auto &argument : implementation.typeArguments)
        argument = solver.normalize(argument, reveal, call.span);
      auto resultType = solver.normalize(call.result.type, reveal, call.span);
      auto result = emit(std::move(implementation), resultType);
      if (resultType != call.result.type) {
        ir::Instruction repack{ir::Op::OpaqueRepack,
                               {},
                               {result},
                               {},
                               "",
                               {-1, {}},
                               -1,
                               0,
                               call.span};
        repack.opaqueType = opaque;
        result = emit(std::move(repack), call.result.type);
      }
      emit({ir::Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, 0, call.span},
           Type::Unit);
      adapter.blocks[0].exit = call.result.type == Type::Never
                                   ? ir::Terminator{ir::Exit::Unreachable}
                                   : ir::Terminator{ir::Exit::Return, result};
      adapters.push_back(std::move(adapter));
      program.opaqueAdapters.push_back(
          {opaque,
           call.interfaceType,
           call.interfaceMethod,
           found->second,
           {call.typeArguments.begin() + prefix, call.typeArguments.end()}});
    }
    call.callee = found->second;
    call.typeArguments =
        found->second < static_cast<int>(program.functions.size())
            ? program.functions[found->second].genericParameters
            : adapters[found->second - program.functions.size()]
                  .genericParameters;
    call.interfaceMethod = -1;
    call.interfaceSelf = call.interfaceType = Type::Unknown;
  };
  std::set<Type> visited, opaqueTypes;
  std::function<void(Type)> visit = [&](Type type) {
    if (!visited.insert(type).second)
      return;
    if (types.isOpaque(type))
      opaqueTypes.insert(type);
    if (types.isView(type))
      visit(types.view(type).payload);
    if (types.isProduct(type))
      for (const auto &field : types.product(type).fields)
        visit(field.type);
  };
  for (const auto &function : program.functions) {
    visit(function.result);
    for (const auto &local : function.locals)
      visit(local.type);
  }
  for (auto opaque : opaqueTypes) {
    std::vector<Type> bounds;
    const auto declaredBounds = types.product(opaque).opaqueBounds;
    for (auto declared : declaredBounds) {
      auto inherited = interfaces::hierarchy(types, database, opaque, declared,
                                             {}, diagnostics);
      bounds.insert(bounds.end(), inherited.begin(), inherited.end());
    }
    for (auto bound : bounds) {
      const auto descriptor = types.erased(bound);
      const auto &definition = database.definitions[descriptor.declaration];
      for (std::size_t method = 0; method < definition.methods.size();
           ++method) {
        const auto &contract = definition.methods[method];
        const auto &declaration = program.functions[contract.function];
        std::vector<Type> arguments{opaque};
        arguments.insert(arguments.end(), descriptor.arguments.begin(),
                         descriptor.arguments.end());
        arguments.insert(arguments.end(),
                         declaration.genericParameters.begin() +
                             contract.implicitParameters,
                         declaration.genericParameters.end());
        std::vector<TypeBinding> bindings;
        for (std::size_t p = 0; p < declaration.genericParameters.size(); ++p)
          bindings.push_back({declaration.genericParameters[p], arguments[p]});
        ir::Instruction prototype{ir::Op::Call,      {}, {}, {}, "", {-1, {}},
                                  contract.function, 0,  {}};
        prototype.result.type =
            solver.normalize(declaration.result, bindings, {});
        prototype.interfaceSelf = opaque;
        prototype.interfaceType = bound;
        prototype.interfaceMethod = static_cast<int>(method);
        prototype.typeArguments = std::move(arguments);
        for (std::size_t p = 0; p < declaration.parameters; ++p) {
          auto mode = declaration.locals[p].mode;
          prototype.operands.push_back(
              {-1, solver.normalize(declaration.locals[p].type, bindings, {}),
               mode == ParameterMode::Read  ? ir::Access::Read
               : mode == ParameterMode::Mut ? ir::Access::Mut
                                            : ir::Access::Owned});
        }
        adapt(prototype);
      }
    }
  }
  for (auto &function : program.functions)
    for (auto &block : function.blocks)
      for (auto &call : block.instructions)
        adapt(call);
  for (auto &adapter : adapters)
    program.functions.push_back(std::move(adapter));
}

void erasedAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database) {
  Diagnostics quiet;
  interfaces::Solver solver(types, database, quiet, {}, {}, true);
  std::set<Type> visited, erasedTypes;
  std::function<void(Type)> visit = [&](Type type) {
    if (type == Type::Unknown || !visited.insert(type).second)
      return;
    if (types.isErased(type))
      erasedTypes.insert(type);
    if (types.isView(type))
      visit(types.view(type).payload);
    if (types.isPointer(type))
      visit(types.pointer(type).payload);
    if (types.isProduct(type)) {
      const auto &product = types.product(type);
      for (const auto &field : product.fields)
        visit(field.type);
      for (auto argument : product.genericArguments)
        visit(argument);
      for (auto component : product.components)
        visit(component);
    }
  };
  for (const auto &function : program.functions) {
    visit(function.result);
    for (const auto &local : function.locals)
      visit(local.type);
  }
  for (auto erased : erasedTypes) {
    const auto &descriptor = types.erased(erased);
    auto parameters = types.typeParameters(erased);
    std::sort(parameters.begin(), parameters.end());
    parameters.erase(std::unique(parameters.begin(), parameters.end()),
                     parameters.end());
    for (std::size_t slot = 0; slot < descriptor.methodSlots.size(); ++slot) {
      if (descriptor.methods[slot].result == Type::Unknown)
        continue;
      const auto ownerType = descriptor.methodOwners[slot];
      const auto &owner = types.erased(ownerType);
      const auto method = descriptor.methodSlots[slot];
      if (std::any_of(program.opaqueAdapters.begin(),
                      program.opaqueAdapters.end(), [&](const auto &existing) {
                        return existing.self == erased &&
                               existing.interfaceType == ownerType &&
                               existing.method == static_cast<int>(method) &&
                               existing.methodArguments.empty();
                      }))
        continue;
      const auto &contract =
          database.definitions[owner.declaration].methods[method];
      const auto &declaration = program.functions[contract.function];
      std::vector<Type> arguments{erased};
      arguments.insert(arguments.end(), owner.arguments.begin(),
                       owner.arguments.end());
      if (arguments.size() != declaration.genericParameters.size())
        continue;
      std::vector<TypeBinding> bindings;
      for (std::size_t p = 0; p < arguments.size(); ++p)
        bindings.push_back({declaration.genericParameters[p], arguments[p]});
      ir::Function adapter{"<erased-adapter." +
                               std::to_string(program.functions.size()) + ">",
                           solver.normalize(declaration.result, bindings, {}),
                           declaration.parameters,
                           {},
                           {},
                           0};
      adapter.genericParameters = parameters;
      adapter.targetFeatures = declaration.targetFeatures;
      adapter.twoPhaseReceiver = declaration.twoPhaseReceiver;
      adapter.resultSources = declaration.resultSources;
      adapter.genericResultSources = declaration.genericResultSources;
      adapter.regionSignature =
          solver.normalize(declaration.regionSignature, bindings, {});
      adapter.blocks.emplace_back();
      auto &instructions = adapter.blocks[0].instructions;
      auto emit = [&](ir::Instruction instruction, Type type,
                      ir::Access access = ir::Access::Owned) {
        instruction.result = {adapter.values++, type, access};
        auto result = instruction.result;
        instructions.push_back(std::move(instruction));
        return result;
      };
      std::vector<ir::Value> operands;
      for (std::size_t p = 0; p < declaration.parameters; ++p) {
        auto mode = declaration.locals[p].mode;
        auto type = solver.normalize(declaration.locals[p].type, bindings, {});
        adapter.locals.push_back({"argument",
                                  type,
                                  false,
                                  {},
                                  mode,
                                  0,
                                  static_cast<std::uint32_t>(p)});
        auto access = mode == ParameterMode::Read  ? ir::Access::Read
                      : mode == ParameterMode::Mut ? ir::Access::Mut
                                                   : ir::Access::Owned;
        operands.push_back(
            emit({access == ir::Access::Read  ? ir::Op::BorrowRead
                  : access == ir::Access::Mut ? ir::Op::BorrowMut
                  : mode == ParameterMode::Take || !types.isCopy(type)
                      ? ir::Op::Move
                      : ir::Op::Load,
                  {},
                  {},
                  {},
                  "",
                  {static_cast<int>(p), {}},
                  -1,
                  0,
                  {}},
                 type, access));
      }
      const auto signature = descriptor.methodTypes[slot];
      ir::Instruction witness{ir::Op::WitnessMethod,
                              {},
                              {operands.front()},
                              {},
                              "",
                              {-1, {}},
                              -1,
                              static_cast<std::int32_t>(slot),
                              {}};
      witness.interfaceType = ownerType;
      witness.interfaceMethod = static_cast<int>(method);
      ir::Instruction call{ir::Op::IndirectCall,
                           {},
                           std::move(operands),
                           {},
                           "",
                           {-1, {}},
                           -1,
                           0,
                           {}};
      call.target = emit(std::move(witness), signature);
      call.indirectType = signature;
      call.erasedDispatch = true;
      // As in direct erased dispatch, an access parameter without a declared
      // region is call-local and the implementation cannot retain it.
      const auto regionSignature = declaration.regionSignature;
      if (types.isFunctionPointer(regionSignature)) {
        const auto &regions = types.callable(regionSignature);
        for (std::size_t p = 0; p < regions.parameters.size() &&
                                p < regions.parameterRegions.size();
             ++p)
          if ((regions.parameters[p].mode == ParameterMode::Read ||
               regions.parameters[p].mode == ParameterMode::Mut) &&
              types.regions().get(regions.parameterRegions[p]).name ==
                  regions.parameters[p].name)
            call.callLocalParameters.push_back(p);
      }
      auto result = emit(std::move(call), adapter.result);
      emit({ir::Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, 0, {}},
           Type::Unit);
      adapter.blocks[0].exit = adapter.result == Type::Never
                                   ? ir::Terminator{ir::Exit::Unreachable}
                                   : ir::Terminator{ir::Exit::Return, result};
      program.opaqueAdapters.push_back(
          {erased,
           ownerType,
           static_cast<int>(method),
           static_cast<int>(program.functions.size()),
           {}});
      program.functions.push_back(std::move(adapter));
    }
  }
  callableContracts(program);
}
} // namespace mettle::lowering
