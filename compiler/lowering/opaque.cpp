#include "lowering/scalar.h"
#include <algorithm>
#include <functional>
#include <map>
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
      const auto &definition =
          database.definitions[types.erased(call.interfaceType).declaration];
      auto prefix = definition.methods[call.interfaceMethod].implicitParameters;
      program.opaqueAdapters.push_back(
          {opaque,
           call.interfaceType,
           call.interfaceMethod,
           found->second,
           {call.typeArguments.begin() + prefix, call.typeArguments.end()}});
    }
    call.callee = found->second;
    call.typeArguments =
        adapters[found->second - program.functions.size()].genericParameters;
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
} // namespace mettle::lowering
