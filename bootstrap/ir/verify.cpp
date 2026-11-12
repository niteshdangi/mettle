#include "ir/verify.h"
#include "ir/dominance.h"
#include "ir/target.h"
#include "support/path.h"
#include "types/layout.h"
#include "types/machine.h"
#include <algorithm>
#include <functional>
#include <numeric>
#include <set>
#include <unordered_set>

namespace mettle::ir {
namespace {
std::optional<Type> pinnedViewPayload(const TypeStore &types, Type type) {
  if (!types.isProduct(type) ||
      types.product(type).kind != AggregateKind::Pin ||
      types.product(type).components.empty())
    return std::nullopt;
  auto view = types.product(type).components.front();
  if (!types.isView(view) || types.view(view).mode != ParameterMode::Mut)
    return std::nullopt;
  return types.view(view).payload;
}

Type erasedReceiver(const TypeStore &types, Type type) {
  if (types.isErased(type))
    return type;
  auto pinned = pinnedViewPayload(types, type);
  return pinned && types.isErased(*pinned) ? *pinned : Type::Unknown;
}

bool scalar(Type type) {
  return isNumeric(type) || type == Type::Bool || type == Type::Unit ||
         type == Type::Char || type == Type::U8;
}

std::optional<std::uint64_t> unsignedConstant(const Instruction &instruction,
                                              const TypeStore &types) {
  if (instruction.op != Op::Constant)
    return std::nullopt;
  auto numeric = instruction.constantParameter == Type::Unknown
                     ? instruction.numeric
                     : types.scalarConstantValue(instruction.constantParameter);
  if (numeric) {
    if (numeric->negative || numeric->magnitude[1] || numeric->floatingBits ||
        !numeric->floating.empty())
      return std::nullopt;
    return numeric->magnitude[0];
  }
  if (instruction.constantParameter != Type::Unknown || instruction.number < 0)
    return std::nullopt;
  return static_cast<std::uint32_t>(instruction.number);
}

bool arrayCount(const Instruction &length, Type array, const TypeStore &types) {
  if (length.op != Op::Constant || length.result.type != Type::Usize)
    return false;
  auto count = types.product(array).arrayCount;
  if (count != Type::Unknown && types.isSymbolic(count))
    return length.constantParameter == count;
  auto actual = unsignedConstant(length, types);
  auto expected = types.arrayLength(array);
  return actual && expected && *actual == *expected;
}

bool function(const Function &f, const Program &program,
              Diagnostics &diagnostics, const TypeNormalizer &normalize,
              const UnpinProof &unpinProof) {
  auto known = [&](Type type) {
    return program.types->contains(type) && !program.types->isConstant(type);
  };
  auto concrete = [&](Type type) { return known(type) && type != Type::Never; };
  bool valid = true;
  auto fail = [&](Span span, std::string message) {
    diagnostics.error("internal", span,
                      "invalid CFG in '" + displayPath(f.name) +
                          "': " + message);
    valid = false;
  };
  if ((f.blocks.empty() && f.externalName.empty()) || !known(f.result) ||
      f.parameters > f.locals.size()) {
    fail({}, "invalid function signature or empty block list");
    return false;
  }
  for (const auto &local : f.locals) {
    if (!known(local.type))
      fail(local.span, "unresolved local type");
    if (local.storage == StorageDuration::Static &&
        (local.staticIndex < 0 ||
         static_cast<std::size_t>(local.staticIndex) >=
             program.statics.size() ||
         local.type != program.statics[local.staticIndex].type ||
         local.mutableBinding !=
             program.statics[local.staticIndex].mutableBinding))
      fail(local.span, "invalid static storage identity");
  }
  if (f.variadicCursor >= 0 &&
      (!f.variadic || f.abi.empty() ||
       f.variadicCursor < static_cast<int>(f.parameters) ||
       static_cast<std::size_t>(f.variadicCursor) >= f.locals.size() ||
       !program.types->isProduct(f.locals[f.variadicCursor].type) ||
       program.types->product(f.locals[f.variadicCursor].type).kind !=
           AggregateKind::VarArgs))
    fail({}, "invalid hidden variadic invocation context");
  if (!program.types->isSized(f.result))
    fail({}, "unsized function result requires a view or owner");
  for (std::size_t p = 0; p < f.locals.size(); ++p)
    if (!program.types->isSized(f.locals[p].type) &&
        !(p < f.parameters && (f.locals[p].mode == ParameterMode::Read ||
                               f.locals[p].mode == ParameterMode::Mut)))
      fail(f.locals[p].span, "unsized owned storage");
  for (std::size_t p = 0; p < f.parameters; ++p) {
    auto mode = f.locals[p].mode;
    if (mode != ParameterMode::Value && mode != ParameterMode::Take &&
        mode != ParameterMode::Read && mode != ParameterMode::Mut)
      fail(f.locals[p].span, "invalid parameter mode");
    if (mode == ParameterMode::Value &&
        !program.types->isCopy(f.locals[p].type))
      fail(f.locals[p].span,
           "non-Copy value parameter requires an explicit consuming contract");
  }
  if (f.twoPhaseReceiver &&
      (f.parameters == 0 || f.locals[0].mode != ParameterMode::Mut))
    fail({}, "invalid two-phase receiver signature");
  if (f.constructorSelfSlot >= 0) {
    auto slot = static_cast<std::size_t>(f.constructorSelfSlot);
    if (slot < f.parameters || slot >= f.locals.size() ||
        !program.types->isProduct(f.locals[slot].type))
      fail({}, "invalid constructor storage");
    else {
      auto result = f.result;
      if (program.types->isSum(result) &&
          program.types->product(result).kind == AggregateKind::Outcome)
        result = program.types->product(result).components[0];
      if (result != f.locals[slot].type)
        fail({}, "constructor result does not match self storage");
    }
  }
  for (std::size_t local = f.parameters; local < f.locals.size(); ++local)
    if (f.locals[local].mode != ParameterMode::Value)
      fail(f.locals[local].span,
           "parameter mode attached to owned local storage");
  if (f.exportedDefinition && (f.externalName.empty() || f.foreignDeclaration))
    fail({}, "invalid exported function definition");
  if (!f.externalName.empty() && !f.exportedDefinition) {
    if (!f.blocks.empty() || f.parameters != f.locals.size())
      fail({}, "external function has a body or owned locals");
    return valid;
  }
  if (f.nakedAssembly)
    return valid;
  if (f.scopes.empty() || f.scopes[0].parent != -1)
    fail({}, "invalid root scope");
  for (std::size_t s = 1; s < f.scopes.size(); ++s)
    if (f.scopes[s].parent < 0 ||
        static_cast<std::size_t>(f.scopes[s].parent) >= s)
      fail({}, "invalid scope parent");
  for (const auto &local : f.locals)
    if (local.scope < -2 || local.scope >= static_cast<int>(f.scopes.size()))
      fail(local.span, "invalid local scope");
  for (auto source : f.resultSources)
    if (source >= f.parameters)
      fail({}, "invalid result source");
  auto count = std::accumulate(f.blocks.begin(), f.blocks.end(), std::size_t{0},
                               [](std::size_t sum, const Block &block) {
                                 return sum + block.instructions.size();
                               });
  if (f.values < 0 || static_cast<std::size_t>(f.values) != count) {
    fail({}, "value count does not match definitions");
    return false;
  }
  struct Definition {
    int block = -1;
    std::size_t position = 0;
    Type type = Type::Unknown;
    Access access = Access::Owned;
  };
  std::vector<Definition> definitions(count);
  auto blockIndex = [&](int block) {
    return block >= 0 && static_cast<std::size_t>(block) < f.blocks.size();
  };
  for (std::size_t b = 0; b < f.blocks.size(); ++b) {
    const auto &block = f.blocks[b];
    for (std::size_t i = 0; i < block.instructions.size(); ++i) {
      const auto &n = block.instructions[i];
      if (n.scope < 0 || static_cast<std::size_t>(n.scope) >= f.scopes.size())
        fail(n.span, "invalid instruction scope");
      if (n.result.id < 0 || static_cast<std::size_t>(n.result.id) >= count ||
          !known(n.result.type)) {
        fail(n.span, "invalid value definition");
        continue;
      }
      if (n.result.access == Access::Owned && n.result.type != Type::Never &&
          !program.types->isSized(n.result.type))
        fail(n.span, "unsized owned SSA value");
      auto &definition = definitions[n.result.id];
      if (definition.block >= 0)
        fail(n.span, "duplicate value definition");
      definition = {static_cast<int>(b), i, n.result.type, n.result.access};
    }
    const auto &exit = block.exit;
    switch (exit.kind) {
    case Exit::Suspend:
      if (!f.coroutine)
        fail(exit.span, "suspension outside a coroutine body");
      [[fallthrough]];
    case Exit::Jump:
    case Exit::Branch:
      if (!blockIndex(exit.first) ||
          (exit.kind == Exit::Branch && !blockIndex(exit.second)))
        fail({}, "invalid successor block");
      break;
    case Exit::Return:
    case Exit::Unreachable:
      break;
    default:
      fail({}, "missing or unknown terminator");
      break;
    }
  }
  if (!valid)
    return false;
  for (const auto &definition : definitions)
    if (definition.block < 0)
      fail({}, "missing value definition");
  if (!valid)
    return false;
  Dominance graph(f);
  if (!graph.predecessors[0].empty())
    fail({}, "entry block has predecessors");
  auto value = [&](Value operand, int block, std::size_t position, Span span) {
    if (operand.id < 0 || static_cast<std::size_t>(operand.id) >= count) {
      fail(span, "invalid value operand");
      return;
    }
    const auto &definition = definitions[operand.id];
    if (operand.type != definition.type || operand.type == Type::Never ||
        operand.access != definition.access)
      fail(span, "operand type does not match an available value");
    if ((definition.block == block && definition.position >= position) ||
        (graph.reachable(block) && !graph.dominates(definition.block, block)))
      fail(span, "value definition does not dominate its use");
  };
  for (std::size_t b = 0; b < f.blocks.size(); ++b) {
    const auto &block = f.blocks[b];
    bool pastPhi = false;
    for (std::size_t i = 0; i < block.instructions.size(); ++i) {
      const auto &n = block.instructions[i];
      auto result = n.result.type;
      auto arity = [&](std::size_t wanted) {
        if (n.operands.size() != wanted) {
          fail(n.span, "invalid operand count");
          return false;
        }
        return true;
      };
      auto require = [&](bool condition) {
        if (!condition)
          fail(n.span, "invalid instruction types or operation");
      };
      for (auto [subject, runtime] : n.unpinProofs)
        require(unpinProof && unpinProof(subject, runtime, f, n.span));
      auto slot = [&] {
        if (n.place.root < 0 ||
            static_cast<std::size_t>(n.place.root) >= f.locals.size()) {
          fail(n.span, "invalid local slot");
          return false;
        }
        if (analysisOnly(n.place) ||
            !projectedType(*program.types, f.locals[n.place.root].type,
                           n.place.fields)) {
          fail(n.span, "invalid projected place");
          return false;
        }
        for (std::size_t p = 0; p < n.place.fields.size(); ++p) {
          auto owner =
              projectedType(*program.types, f.locals[n.place.root].type,
                            std::span(n.place.fields).first(p));
          bool directWrite =
              n.op == Op::Store && p + 1 == n.place.fields.size();
          if (owner && program.types->isProduct(*owner) &&
              program.types->product(*owner).layout.unionType && !directWrite &&
              n.op != Op::Declare && !n.unsafeAllowed) {
            fail(n.span, "union field access lacks an unsafe context");
            return false;
          }
        }
        return true;
      };
      bool borrow = n.op == Op::BorrowRead || n.op == Op::BorrowMut ||
                    n.op == Op::ReserveMut || n.op == Op::OpaqueRepack;
      if (!borrow)
        require(n.result.access == Access::Owned);
      if (n.op != Op::Call && n.op != Op::IndirectCall &&
          n.op != Op::CatchCall && n.op != Op::Activate &&
          n.op != Op::WitnessMethod && n.op != Op::OpaqueRepack)
        for (auto operand : n.operands)
          require(operand.access == Access::Owned);
      if (n.op != Op::Phi) {
        pastPhi = true;
        for (auto operand : n.operands)
          value(operand, static_cast<int>(b), i, n.span);
      }
      switch (n.op) {
      case Op::TextLiteral:
        arity(0);
        require(
            program.types->isView(result) &&
            program.types->view(result).mode == ParameterMode::Read &&
            (program.types->pointerMetadata(
                 program.types->view(result).payload) ==
                 PointerMetadata::ElementCount ||
             (program.types->isProduct(program.types->view(result).payload) &&
              program.types->product(program.types->view(result).payload)
                      .kind == AggregateKind::Array)));
        break;
      case Op::FeatureTest:
        arity(0);
        require(result == Type::Bool);
        break;
      case Op::Assembly: {
        require(n.assembly.has_value() && n.unsafeAllowed &&
                n.assembly->variant == AssemblyVariant::Inline);
        if (!n.assembly)
          break;
        std::vector<Type> inputs, outputs;
        for (const auto &operand : n.assembly->operands) {
          if (assemblyInput(operand.mode))
            inputs.push_back(operand.inputType);
          if (assemblyOutput(operand.mode) && !operand.discard)
            outputs.push_back(operand.type);
        }
        if (arity(inputs.size()))
          for (std::size_t i = 0; i < inputs.size(); ++i)
            require(n.operands[i].type == inputs[i] &&
                    n.operands[i].access == Access::Owned);
        require(program.types->isProduct(result));
        if (program.types->isProduct(result)) {
          const auto &record = program.types->product(result);
          require(record.kind == AggregateKind::Tuple &&
                  record.fields.size() == outputs.size());
          if (record.fields.size() == outputs.size())
            for (std::size_t i = 0; i < outputs.size(); ++i)
              require(record.fields[i].type == outputs[i]);
        }
        if (n.assembly->options.contains("noreturn"))
          require(i + 1 == block.instructions.size() &&
                  block.exit.kind == Exit::Unreachable);
        break;
      }
      case Op::SliceLength:
        arity(0);
        require(result == Type::Usize);
        if (slot())
          require(program.types->isSlice(*projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields)));
        break;
      case Op::UnsizeView:
        require(program.types->isView(result));
        if (arity(1))
          require(n.operands[0].type == Type::Usize);
        if (slot() && program.types->isView(result) && n.operands.size() == 1) {
          auto source = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          auto array = program.types->unsizedArray(
              source, program.types->view(result).payload);
          require(array.has_value());
          if (array && n.operands[0].id >= 0 &&
              static_cast<std::size_t>(n.operands[0].id) < definitions.size()) {
            const auto &where = definitions[n.operands[0].id];
            if (where.block >= 0) {
              const auto &length =
                  f.blocks[where.block].instructions[where.position];
              require(arrayCount(length, *array, *program.types));
            }
          }
        }
        break;
      case Op::SliceBorrowRead:
      case Op::SliceBorrowMut: {
        require(program.types->isView(result));
        // One operand borrows an element; start and end borrow a subslice.
        const bool range = n.operands.size() == 2;
        if (range)
          require(n.operands[0].type == Type::Usize &&
                  n.operands[1].type == Type::Usize);
        else if (arity(1))
          require(n.operands[0].type == Type::I32 ||
                  n.operands[0].type == Type::Usize);
        if (slot() && program.types->isView(result)) {
          auto slice = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          require(program.types->isSlice(slice));
          if (program.types->isSlice(slice))
            require(program.types->view(result).payload ==
                        (range ? slice : program.types->slice(slice).element) &&
                    program.types->view(result).mode ==
                        (n.op == Op::SliceBorrowRead ? ParameterMode::Read
                                                     : ParameterMode::Mut));
        }
        if (!range && n.number >= 0 && !n.operands.empty() &&
            n.operands[0].id >= 0 &&
            static_cast<std::size_t>(n.operands[0].id) < definitions.size()) {
          const auto &where = definitions[n.operands[0].id];
          if (where.block >= 0) {
            const auto &index =
                f.blocks[where.block].instructions[where.position];
            bool ordinal = index.numeric
                               ? !index.numeric->negative &&
                                     index.numeric->magnitude[1] == 0 &&
                                     index.numeric->magnitude[0] ==
                                         static_cast<std::uint32_t>(n.number)
                               : index.number == n.number;
            require(index.op == Op::Constant &&
                    index.constantParameter == Type::Unknown && ordinal);
          }
        }
        break;
      }
      case Op::OpaqueRepack:
        require(program.types->isOpaque(n.opaqueType));
        if (arity(1) && program.types->isOpaque(n.opaqueType)) {
          require(n.operands[0].access == n.result.access);
          auto hidden = program.types->product(n.opaqueType).fields[0].type;
          std::vector<TypeBinding> bindings{{n.opaqueType, hidden}};
          require(program.types->matchesSubstitution(n.operands[0].type, result,
                                                     bindings) ||
                  program.types->matchesSubstitution(result, n.operands[0].type,
                                                     bindings));
        }
        break;
      case Op::EraseView:
        require(program.types->isView(result));
        if (slot() && program.types->isView(result)) {
          auto source = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          auto conversion = program.types->erasedTail(
              source, program.types->view(result).payload);
          require(conversion && conversion->first == n.interfaceSelf &&
                  conversion->second == n.interfaceType &&
                  program.types->pointerMetadata(n.interfaceSelf) !=
                      PointerMetadata::Witness);
          if (conversion && program.types->isErased(n.interfaceType)) {
            const auto &descriptor = program.types->erased(n.interfaceType);
            bool metadata =
                descriptor.methodOwners.size() ==
                    descriptor.methodTypes.size() &&
                descriptor.methodSlots.size() == descriptor.methodTypes.size();
            require(metadata);
            require(n.witnessEntries.size() == n.operands.size());
            if (arity(descriptor.methodTypes.size()) && metadata)
              for (std::size_t method = 0; method < n.operands.size();
                   ++method) {
                require(n.operands[method].type ==
                        (descriptor.methodTypes[method] == Type::Unknown
                             ? Type::Unit
                             : descriptor.methodTypes[method]));
                if (descriptor.methodTypes[method] != Type::Unknown &&
                    n.operands[method].id >= 0 &&
                    static_cast<std::size_t>(n.operands[method].id) <
                        definitions.size()) {
                  const auto &definition = definitions[n.operands[method].id];
                  if (definition.block >= 0) {
                    const auto &address =
                        f.blocks[definition.block]
                            .instructions[definition.position];
                    require(
                        address.op == Op::FunctionAddress &&
                        address.erasedDispatch &&
                        address.interfaceSelf == n.interfaceSelf &&
                        address.interfaceType ==
                            descriptor.methodOwners[method] &&
                        address.number ==
                            static_cast<int>(descriptor.methodSlots[method]));
                  }
                }
              }
          }
        }
        break;
      case Op::OwnerUnsize:
        if (!n.operands.empty() && program.types->isProduct(result) &&
            program.types->isProduct(n.operands[0].type)) {
          const auto &source = program.types->product(n.operands[0].type);
          const auto &target = program.types->product(result);
          auto isOwner = [&](Type type) {
            if (!program.types->isProduct(type))
              return false;
            auto origin = program.types->product(type).genericOrigin;
            if (origin == Type::Unknown)
              return false;
            return !ownerSpelling(program.types->product(origin).name).empty();
          };
          bool compatible = isOwner(n.operands[0].type) && isOwner(result) &&
                            source.genericOrigin == target.genericOrigin &&
                            source.genericArguments.size() >= 2 &&
                            source.genericArguments.size() ==
                                target.genericArguments.size() &&
                            source.fields.size() == target.fields.size() &&
                            !source.fields.empty() &&
                            n.operands[0].access == Access::Owned;
          require(compatible);
          if (compatible) {
            auto sourcePayload = source.genericArguments.front();
            auto targetPayload = target.genericArguments.front();
            auto sourcePointer = source.fields.front().type;
            auto targetPointer = target.fields.front().type;
            require(program.types->isSized(sourcePayload) &&
                    program.types->isPointer(sourcePointer) &&
                    program.types->isPointer(targetPointer) &&
                    program.types->pointer(sourcePointer).payload ==
                        sourcePayload &&
                    program.types->pointer(targetPointer).payload ==
                        targetPayload);
            for (std::size_t p = 1; p < source.genericArguments.size(); ++p)
              require(source.genericArguments[p] == target.genericArguments[p]);
            for (std::size_t p = 1; p < source.fields.size(); ++p)
              require(source.fields[p].type == target.fields[p].type);
            if (program.types->pointerMetadata(targetPayload) ==
                PointerMetadata::ElementCount) {
              auto array =
                  program.types->unsizedArray(sourcePayload, targetPayload);
              require(array && arity(2) && n.operands[1].type == Type::Usize &&
                      n.witnessEntries.empty() &&
                      n.interfaceSelf == Type::Unknown &&
                      n.interfaceType == Type::Unknown);
              if (array && n.operands.size() == 2 && n.operands[1].id >= 0 &&
                  static_cast<std::size_t>(n.operands[1].id) <
                      definitions.size()) {
                const auto &where = definitions[n.operands[1].id];
                if (where.block >= 0) {
                  const auto &length =
                      f.blocks[where.block].instructions[where.position];
                  require(arrayCount(length, *array, *program.types));
                }
              }
            } else {
              require(program.types->isErased(targetPayload) &&
                      n.interfaceSelf == sourcePayload &&
                      n.interfaceType == targetPayload &&
                      n.witnessEntries.size() + 1 == n.operands.size());
              if (program.types->isErased(targetPayload)) {
                const auto &descriptor = program.types->erased(targetPayload);
                require(n.operands.size() == descriptor.methodTypes.size() + 1);
                for (std::size_t method = 0;
                     method < descriptor.methodTypes.size() &&
                     method + 1 < n.operands.size();
                     ++method)
                  require(n.operands[method + 1].type ==
                          (descriptor.methodTypes[method] == Type::Unknown
                               ? Type::Unit
                               : descriptor.methodTypes[method]));
              }
            }
          }
        } else
          require(false);
        break;
      case Op::ErasedUpcast:
        arity(0);
        require(program.types->isView(result));
        if (slot() && program.types->isView(result)) {
          auto source = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          auto conversion = program.types->erasedTail(
              source, program.types->view(result).payload);
          require(conversion && conversion->first == n.interfaceSelf &&
                  conversion->second == n.interfaceType &&
                  program.types->isErased(n.interfaceSelf));
          if (program.types->isErased(n.interfaceSelf)) {
            const auto &parents =
                program.types->erased(n.interfaceSelf).parentInterfaces;
            require(n.number >= 0 &&
                    static_cast<std::size_t>(n.number) < parents.size());
            if (n.number >= 0 &&
                static_cast<std::size_t>(n.number) < parents.size())
              require(parents[n.number] == n.interfaceType);
          }
        }
        break;
      case Op::WitnessMethod:
        if (arity(1)) {
          auto interface = n.operands[0].type;
          auto erased = erasedReceiver(*program.types, interface);
          bool pinned = erased != interface;
          require(erased != Type::Unknown &&
                  (pinned || n.operands[0].access != Access::Owned));
          if (erased != Type::Unknown) {
            const auto &methods = program.types->erased(erased).methodTypes;
            require(n.number >= 0 &&
                    static_cast<std::size_t>(n.number) < methods.size());
            if (n.number >= 0 &&
                static_cast<std::size_t>(n.number) < methods.size())
              require(result == methods[n.number] &&
                      program.types->isFunctionPointer(result));
          }
        }
        break;
      case Op::CallableCoerce:
        require(program.types->isFunctionPointer(result));
        if (arity(1)) {
          require(program.types->isFunctionPointer(n.operands[0].type));
          if (program.types->isFunctionPointer(result) &&
              program.types->isFunctionPointer(n.operands[0].type)) {
            const auto &source = program.types->callable(n.operands[0].type);
            const auto &target = program.types->callable(result);
            require(source.result == target.result &&
                    source.error == target.error &&
                    source.resultSources == target.resultSources &&
                    source.parameters.size() == target.parameters.size());
            if (source.parameters.size() == target.parameters.size())
              for (std::size_t p = 0; p < source.parameters.size(); ++p)
                require(source.parameters[p].type ==
                            target.parameters[p].type &&
                        source.parameters[p].mode == target.parameters[p].mode);
            require(source.mode == target.mode ||
                    source.mode == ParameterMode::Read ||
                    (source.mode == ParameterMode::Mut &&
                     target.mode == ParameterMode::Take));
          }
        }
        break;
      case Op::FunctionAddress:
        arity(0);
        require(program.types->isFunctionPointer(result));
        if (n.callee < 0 ||
            static_cast<std::size_t>(n.callee) >= program.functions.size()) {
          fail(n.span, "invalid function address");
          break;
        }
        if (program.types->isFunctionPointer(result)) {
          const auto &signature = program.types->callable(result);
          bool pinnedDispatch = false;
          if (n.erasedDispatch) {
            auto receiver = signature.parameters.empty()
                                ? Type::Unknown
                                : signature.parameters[0].type;
            auto erased = erasedReceiver(*program.types, receiver);
            pinnedDispatch = erased != Type::Unknown && erased != receiver;
            require(
                erased != Type::Unknown &&
                (pinnedDispatch
                     ? signature.parameters[0].mode == ParameterMode::Take
                     : signature.parameters[0].mode == ParameterMode::Read ||
                           signature.parameters[0].mode == ParameterMode::Mut));
          }
          const auto &callee = program.functions[n.callee];
          require(!callee.indirectContract &&
                  (!callee.declarationOnly ||
                   (n.erasedDispatch && n.interfaceMethod >= 0)));
          std::vector<TypeBinding> bindings;
          require(n.typeArguments.size() == callee.genericParameters.size());
          for (std::size_t p = 0; p < n.typeArguments.size() &&
                                  p < callee.genericParameters.size();
               ++p)
            bindings.push_back(
                {callee.genericParameters[p], n.typeArguments[p]});
          auto matches = [&](Type pattern, Type actual) {
            return normalize ? normalize(pattern, bindings, f) ==
                                   normalize(actual, {}, f)
                             : program.types->matchesSubstitution(
                                   pattern, actual, bindings);
          };
          require(matches(callee.result, signature.abiResult) &&
                  signature.parameters.size() == callee.parameters &&
                  (signature.resultSources == callee.resultSources ||
                   (n.erasedDispatch &&
                    std::all_of(callee.resultSources.begin(),
                                callee.resultSources.end(), [&](auto source) {
                                  return std::find(
                                             signature.resultSources.begin(),
                                             signature.resultSources.end(),
                                             source) !=
                                         signature.resultSources.end();
                                }))));
          if (signature.parameters.size() == callee.parameters)
            for (std::size_t p = 0; p < callee.parameters; ++p)
              require((n.erasedDispatch && p == 0 && pinnedDispatch
                           ? ([&] {
                               auto payload = pinnedViewPayload(
                                   *program.types, callee.locals[p].type);
                               return payload &&
                                      matches(*payload, n.interfaceSelf);
                             })()
                           : matches(callee.locals[p].type,
                                     n.erasedDispatch && p == 0
                                         ? n.interfaceSelf
                                         : signature.parameters[p].type)) &&
                      signature.parameters[p].mode == callee.locals[p].mode);
        }
        break;
      case Op::Constant:
        arity(0);
        require(scalar(result));
        if (n.numeric)
          require(isFloating(result) ? validFloatingConstant(*n.numeric, result)
                                     : integerLiteralFits(*n.numeric, result));
        else
          require(!isFloating(result));
        if (result == Type::Bool)
          require(n.number == 0 || n.number == 1);
        if (result == Type::U8)
          require(n.number >= 0 && n.number <= 255);
        if (result == Type::Char)
          require(n.number >= 0 && n.number <= 0x10ffff &&
                  !(n.number >= 0xd800 && n.number <= 0xdfff));
        break;
      case Op::Declare:
        arity(0);
        slot();
        require(n.place.fields.empty());
        require(result == Type::Unit);
        break;
      case Op::Load:
      case Op::Move:
      case Op::BorrowRead:
      case Op::BorrowMut:
      case Op::ReserveMut:
        arity(0);
        if (slot())
          require(result == *projectedType(*program.types,
                                           f.locals[n.place.root].type,
                                           n.place.fields) &&
                  concrete(result));
        if (n.op == Op::Load)
          require(program.types->isCopy(result));
        if (borrow)
          require(n.result.access ==
                  (n.op == Op::BorrowRead ? Access::Read : Access::Mut));
        break;
      case Op::ViewRead:
      case Op::ViewMut:
        arity(0);
        require(program.types->isView(result));
        if (slot() && program.types->isView(result)) {
          const auto &view = program.types->view(result);
          require(view.payload == *projectedType(*program.types,
                                                 f.locals[n.place.root].type,
                                                 n.place.fields) &&
                  view.mode == (n.op == Op::ViewRead ? ParameterMode::Read
                                                     : ParameterMode::Mut));
        }
        break;
      case Op::ArrayBorrowRead:
      case Op::ArrayBorrowMut:
        require(program.types->isView(result));
        if (arity(1))
          require(n.operands[0].type == Type::I32 ||
                  n.operands[0].type == Type::Usize);
        if (slot() && program.types->isView(result)) {
          auto array = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          require(program.types->isProduct(array) &&
                  program.types->product(array).kind == AggregateKind::Array);
          if (program.types->isProduct(array) &&
              program.types->product(array).kind == AggregateKind::Array) {
            const auto &view = program.types->view(result);
            require(view.payload ==
                        program.types->product(array).components.at(0) &&
                    view.mode == (n.op == Op::ArrayBorrowRead
                                      ? ParameterMode::Read
                                      : ParameterMode::Mut));
          }
        }
        break;
      case Op::ArrayRepeat:
        require(program.types->isProduct(result) &&
                program.types->product(result).kind == AggregateKind::Array);
        if (arity(1) && program.types->isProduct(result)) {
          const auto &array = program.types->product(result);
          require(array.kind == AggregateKind::Array &&
                  array.components.size() == 1 &&
                  n.operands[0].type == array.components[0] &&
                  program.types->isCopy(n.operands[0].type));
        }
        break;
      case Op::ArrayTake: {
        bool iteration = false;
        for (const auto &loop : f.arrayLoops)
          if (loop.body == static_cast<int>(b) && i == 0 &&
              loop.element == n.result.id && loop.mode == ParameterMode::Take &&
              loop.source == n.place && n.operands.size() == 1 &&
              loop.index.id == n.operands[0].id && blockIndex(loop.header) &&
              blockIndex(loop.step) && blockIndex(loop.done)) {
            const auto &header = f.blocks[loop.header].exit;
            const auto &step = f.blocks[loop.step].exit;
            const auto &tests = f.blocks[loop.header].instructions;
            const auto &advance = f.blocks[loop.step].instructions;
            bool cursor = tests.size() == 3 && advance.size() == 3;
            if (cursor) {
              cursor =
                  tests[0].op == Op::Load &&
                  tests[0].result.id == loop.index.id &&
                  loop.index.type == Type::Usize &&
                  arrayCount(tests[1],
                             *projectedType(*program.types,
                                            f.locals[loop.source.root].type,
                                            loop.source.fields),
                             *program.types) &&
                  tests[2].op == Op::Binary && tests[2].text == "<" &&
                  tests[2].operands.size() == 2 &&
                  tests[2].operands[0].id == loop.index.id &&
                  tests[2].operands[1].id == tests[1].result.id &&
                  tests[2].result.id == header.value.id &&
                  advance[0].result.type == Type::Usize &&
                  unsignedConstant(advance[0], *program.types) == 1 &&
                  advance[1].op == Op::Binary && advance[1].text == "+" &&
                  advance[1].operands.size() == 2 &&
                  advance[1].operands[0].id == loop.index.id &&
                  advance[1].operands[1].id == advance[0].result.id &&
                  advance[2].op == Op::Store &&
                  advance[2].place == tests[0].place &&
                  advance[2].operands.size() == 1 &&
                  advance[2].operands[0].id == advance[1].result.id;
              for (auto block : loop.blocks)
                if (!blockIndex(block))
                  cursor = false;
                else
                  for (const auto &operation : f.blocks[block].instructions)
                    if (operation.place.root == tests[0].place.root)
                      cursor = false;
            }
            iteration |= cursor && header.kind == Exit::Branch &&
                         header.first == loop.body &&
                         header.second == loop.done &&
                         step.kind == Exit::Jump && step.first == loop.header &&
                         graph.predecessors[b].size() == 1 &&
                         graph.predecessors[b][0] == loop.header;
          }
        require(iteration && n.result.access == Access::Owned);
        if (arity(1))
          require(n.operands[0].type == Type::Usize);
        if (slot()) {
          auto array = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          require(program.types->isProduct(array) &&
                  program.types->product(array).kind == AggregateKind::Array);
          if (program.types->isProduct(array) &&
              program.types->product(array).kind == AggregateKind::Array)
            require(result == program.types->product(array).components.at(0));
          require(f.locals[n.place.root].mode != ParameterMode::Read &&
                  f.locals[n.place.root].mode != ParameterMode::Mut &&
                  std::none_of(n.place.fields.begin(), n.place.fields.end(),
                               [](const auto &projection) {
                                 return projection.kind ==
                                        Projection::Kind::Dereference;
                               }));
        }
        break;
      }
      case Op::Activate:
        if (arity(1)) {
          require(n.operands[0].access == Access::Mut);
          auto id = n.operands[0].id;
          if (id >= 0 && static_cast<std::size_t>(id) < definitions.size()) {
            const auto &definition = definitions[id];
            require(f.blocks[definition.block]
                        .instructions[definition.position]
                        .op == Op::ReserveMut);
          }
        }
        require(result == Type::Unit);
        break;
      case Op::ScopeExit:
        arity(0);
        require(result == Type::Unit && n.number >= 0 &&
                n.number < static_cast<int>(f.scopes.size()));
        break;
      case Op::VariantTest:
        arity(0);
        require(result == Type::Bool);
        if (slot()) {
          auto type = *projectedType(
              *program.types, f.locals[n.place.root].type, n.place.fields);
          require(program.types->isSum(type));
          if (program.types->isSum(type))
            require(n.number >= 0 &&
                    static_cast<std::size_t>(n.number) <
                        program.types->product(type).variants.size());
        }
        break;
      case Op::Panic:
        arity(0);
        require(result == Type::Never && i + 1 == block.instructions.size() &&
                block.exit.kind == Exit::Unreachable);
        break;
      case Op::VariantConstruct:
        require(program.types->isSum(result));
        if (program.types->isSum(result)) {
          const auto &sum = program.types->product(result);
          if (n.number < 0 ||
              static_cast<std::size_t>(n.number) >= sum.variants.size())
            fail(n.span, "invalid variant constructor");
          else if (arity(sum.variants[n.number].fields.size()))
            for (std::size_t field = 0; field < n.operands.size(); ++field)
              require(n.operands[field].type ==
                      sum.fields[sum.variants[n.number].fields[field]].type);
        }
        break;
      case Op::Store:
        if (arity(1) && slot())
          require(n.operands[0].type ==
                  *projectedType(*program.types, f.locals[n.place.root].type,
                                 n.place.fields));
        require(result == Type::Unit);
        break;
      case Op::StorageWrite:
        if (arity(1) && slot()) {
          auto parent = n.place;
          require(!parent.fields.empty());
          if (!parent.fields.empty()) {
            auto field = parent.fields.back();
            parent.fields.pop_back();
            auto owner = projectedType(
                *program.types, f.locals[parent.root].type, parent.fields);
            require(field.kind == Projection::Kind::Field && field.index == 0 &&
                    owner && program.types->isProduct(*owner) &&
                    program.types->product(*owner).kind ==
                        AggregateKind::Uninit);
            require(n.operands[0].access == Access::Owned &&
                    n.operands[0].type ==
                        *projectedType(*program.types,
                                       f.locals[n.place.root].type,
                                       n.place.fields));
          }
        }
        require(result == Type::Unit);
        break;
      case Op::DropPlace:
        arity(0);
        if (slot()) {
          bool owned =
              n.place.fields.empty() &&
              (static_cast<std::size_t>(n.place.root) >= f.parameters ||
               (f.locals[n.place.root].mode != ParameterMode::Read &&
                f.locals[n.place.root].mode != ParameterMode::Mut));
          require(result == Type::Unit && (n.unsafeAllowed || owned));
        }
        break;
      case Op::Unary:
        if (arity(1)) {
          auto operand = n.operands[0].type;
          require((n.text == "-" &&
                   (isSignedInteger(operand) || isFloating(operand)) &&
                   result == operand) ||
                  (n.text == "!" &&
                   (isInteger(operand) || operand == Type::Bool) &&
                   result == operand));
        }
        break;
      case Op::Binary:
        if (arity(2)) {
          auto a = n.operands[0].type, c = n.operands[1].type;
          bool compare = n.text == "==" || n.text == "!=" || n.text == "<" ||
                         n.text == "<=" || n.text == ">" || n.text == ">=";
          bool bit = n.text == "&" || n.text == "|" || n.text == "^";
          bool arithmetic = n.text == "+" || n.text == "-" || n.text == "*" ||
                            n.text == "/" || n.text == "%";
          bool shift = n.text == "<<" || n.text == ">>";
          require((shift && isInteger(a) && isInteger(c) && result == a) ||
                  (a == c &&
                   ((compare && (scalar(a) || program.types->isPointer(a)) &&
                     result == Type::Bool) ||
                    (bit && (a == Type::Bool || isInteger(a)) && result == a) ||
                    (arithmetic && isNumeric(a) && result == a))));
        }
        break;
      case Op::Cast:
        if (arity(1))
          require(
              machineCastAllowed(*program.types, n.operands[0].type, result));
        break;
      case Op::Machine: {
        if (n.text == "coroutine.context")
          require(f.coroutine);
        if (n.text == "va.start")
          require(f.variadicCursor >= 0 &&
                  n.result.type == f.locals[f.variadicCursor].type);
        std::vector<Type> operands;
        for (auto operand : n.operands)
          operands.push_back(operand.type);
        require(n.typeArguments.size() <= 1);
        std::vector<Type> proofs;
        for (auto [subject, runtime] : n.unpinProofs) {
          (void)subject;
          proofs.push_back(runtime);
        }
        auto signature = machineSignature(
            *program.types, n.text, operands,
            n.typeArguments.empty() ? Type::Unknown : n.typeArguments[0],
            proofs);
        require(signature &&
                machineResultMatches(*program.types, *signature, result));
        if (signature && signature->unsafeCall)
          require(n.unsafeAllowed);
        if (auto operation = targetOperation(n.text);
            operation && (operation->kind == TargetOperation::Kind::Extract ||
                          operation->kind == TargetOperation::Kind::Insert)) {
          auto lane =
              operation->kind == TargetOperation::Kind::Extract ? 1u : 2u;
          if (lane < n.operands.size()) {
            auto id = n.operands[lane].id;
            if (id >= 0 && static_cast<std::size_t>(id) < definitions.size() &&
                definitions[id].block >= 0) {
              const auto &definition =
                  f.blocks[definitions[id].block]
                      .instructions[definitions[id].position];
              require(definition.op == Op::Constant && !definition.numeric &&
                      definition.number >= 0 &&
                      static_cast<unsigned>(definition.number) <
                          operation->lanes);
            } else
              require(false);
          }
        }
        break;
      }
      case Op::Call:
      case Op::IndirectCall:
      case Op::CatchCall:
        if (n.erasedDispatch)
          require(n.op == Op::IndirectCall && !n.operands.empty() &&
                  erasedReceiver(*program.types, n.operands[0].type) !=
                      Type::Unknown &&
                  (erasedReceiver(*program.types, n.operands[0].type) !=
                       n.operands[0].type ||
                   n.operands[0].access != Access::Owned));
        if (n.op == Op::IndirectCall) {
          value(n.target, static_cast<int>(b), i, n.span);
          require(program.types->isFunctionPointer(n.indirectType) &&
                  (n.target.type == n.indirectType ||
                   (program.types->isParameter(n.target.type) &&
                    program.types->parameter(n.target.type)
                            .erasedCallableConstraint == n.indirectType)));
          if (program.types->isFunctionPointer(n.indirectType)) {
            const auto &signature = program.types->callable(n.indirectType);
            require(n.target.access ==
                    (signature.mode == ParameterMode::Read  ? Access::Read
                     : signature.mode == ParameterMode::Mut ? Access::Mut
                                                            : Access::Owned));
            require(signature.abiResult == result);
            bool matches =
                signature.variadic
                    ? n.operands.size() >= signature.parameters.size()
                    : arity(signature.parameters.size());
            require(matches);
            if (matches)
              for (std::size_t p = 0; p < signature.parameters.size(); ++p) {
                const auto &parameter = signature.parameters[p];
                require(n.operands[p].type == parameter.type &&
                        n.operands[p].access ==
                            (parameter.mode == ParameterMode::Read
                                 ? Access::Read
                             : parameter.mode == ParameterMode::Mut
                                 ? Access::Mut
                                 : Access::Owned));
              }
          }
        }
        if (n.callee < 0 ||
            static_cast<std::size_t>(n.callee) >= program.functions.size()) {
          fail(n.span, "invalid callee");
          break;
        case Op::Construct:
          require(program.types->isProduct(result) &&
                  !program.types->isSum(result));
          if (program.types->isProduct(result)) {
            const auto &fields = program.types->product(result).fields;
            if (program.types->compactArray(result)) {
              auto element = program.types->product(result).components[0];
              if (arity(static_cast<std::size_t>(
                      *program.types->arrayLength(result))))
                for (const auto &operand : n.operands)
                  require(operand.type == element);
            } else if (program.types->product(result).layout.unionType) {
              if (arity(1)) {
                require(n.number >= 0 &&
                        static_cast<std::size_t>(n.number) < fields.size());
                if (n.number >= 0 &&
                    static_cast<std::size_t>(n.number) < fields.size())
                  require(n.operands[0].type == fields[n.number].type);
              }
            } else if (arity(fields.size()))
              for (std::size_t p = 0; p < fields.size(); ++p)
                require(n.operands[p].type == fields[p].type);
          }
          break;
        case Op::Project:
          if (arity(1)) {
            auto base = n.operands[0].type;
            if (!program.types->isProduct(base)) {
              require(false);
              break;
            }
            const auto &fields = program.types->product(base).fields;
            require(!program.types->isSum(base));
            if (n.number < 0 ||
                static_cast<std::size_t>(n.number) >= fields.size()) {
              fail(n.span, "invalid field projection");
              break;
            }
            require(result == fields[n.number].type);
            require(program.types->isCopy(result));
          }
          break;
        } else {
          const auto &callee = program.functions[n.callee];
          std::vector<TypeBinding> bindings;
          require(n.typeArguments.size() == callee.genericParameters.size());
          for (std::size_t p = 0; p < n.typeArguments.size() &&
                                  p < callee.genericParameters.size();
               ++p)
            bindings.push_back(
                {callee.genericParameters[p], n.typeArguments[p]});
          require(callee.indirectContract == (n.op == Op::IndirectCall));
          auto matches = [&](Type pattern, Type actual) {
            return normalize ? normalize(pattern, bindings, f) ==
                                   normalize(actual, {}, f)
                             : program.types->matchesSubstitution(
                                   pattern, actual, bindings);
          };
          if (n.op == Op::IndirectCall &&
              program.types->isFunctionPointer(n.indirectType)) {
            const auto &signature = program.types->callable(n.indirectType);
            require(signature.resultSources == callee.resultSources &&
                    signature.parameters.size() == callee.parameters &&
                    signature.abi == callee.abi &&
                    signature.variadic == callee.variadic &&
                    signature.unsafeCall == callee.unsafeFunction &&
                    signature.targetFeatures == callee.targetFeatures &&
                    n.callLocalParameters == callee.callLocalParameters &&
                    callee.twoPhaseReceiver ==
                        (n.erasedDispatch && !signature.parameters.empty() &&
                         signature.parameters[0].mode == ParameterMode::Mut) &&
                    callee.blocks.empty() && !callee.externalName.empty() &&
                    !callee.foreignDeclaration && !callee.exportedDefinition);
          }
          auto declared =
              n.interfaceMethod >= 0 && callee.interfaceResult != Type::Unknown
                  ? callee.interfaceResult
                  : callee.result;
          require(n.op == Op::CatchCall
                      ? result == Type::I32 && matches(declared, Type::Unit)
                      : matches(declared, result));
          if (callee.parameters > callee.locals.size()) {
            fail(n.span, "invalid callee signature");
            break;
          }
          bool countMatches = callee.variadic
                                  ? n.operands.size() >= callee.parameters
                                  : arity(callee.parameters);
          require(countMatches);
          if (countMatches)
            for (std::size_t p = 0; p < n.operands.size(); ++p) {
              if (p >= callee.parameters) {
                require(!callee.abi.empty() &&
                        n.operands[p].access == Access::Owned &&
                        cCompatible(*program.types, n.operands[p].type));
                continue;
              }
              require(matches(callee.locals[p].type, n.operands[p].type));
              auto mode = callee.locals[p].mode;
              auto access = mode == ParameterMode::Read  ? Access::Read
                            : mode == ParameterMode::Mut ? Access::Mut
                                                         : Access::Owned;
              require(n.operands[p].access == access);
              auto id = n.operands[p].id;
              if (id >= 0 &&
                  static_cast<std::size_t>(id) < definitions.size()) {
                const auto &definition = definitions[id];
                if (f.blocks[definition.block]
                        .instructions[definition.position]
                        .op == Op::ReserveMut)
                  require(p == 0 && callee.twoPhaseReceiver);
              }
              if (access == Access::Mut)
                for (std::size_t previous = 0; previous < p; ++previous)
                  if (n.operands[previous].id == n.operands[p].id)
                    fail(n.span,
                         "exclusive loan value used for multiple parameters");
            }
          if (result == Type::Never)
            require(i + 1 == block.instructions.size() &&
                    block.exit.kind == Exit::Unreachable);
        }
        break;
      case Op::Phi: {
        require(!pastPhi && concrete(result) && !n.operands.empty());
        auto expected = graph.predecessors[b];
        auto actual = n.predecessors;
        std::sort(expected.begin(), expected.end());
        std::sort(actual.begin(), actual.end());
        require(expected == actual &&
                n.operands.size() == n.predecessors.size());
        for (std::size_t p = 0;
             p < n.operands.size() && p < n.predecessors.size(); ++p) {
          int predecessor = n.predecessors[p];
          if (!blockIndex(predecessor)) {
            fail(n.span, "invalid phi predecessor");
            continue;
          }
          require(n.operands[p].type == result);
          value(n.operands[p], predecessor,
                f.blocks[predecessor].instructions.size(), n.span);
        }
        break;
      }
      default:
        fail(n.span, "unknown instruction");
        break;
      }
    }
    const auto &exit = block.exit;
    if (exit.kind == Exit::Branch || exit.kind == Exit::Return) {
      value(exit.value, static_cast<int>(b), block.instructions.size(), {});
      if (exit.kind == Exit::Branch &&
          (exit.value.type != Type::Bool || exit.value.access != Access::Owned))
        fail({}, "branch requires bool");
      if (exit.kind == Exit::Return &&
          (f.result == Type::Never || exit.value.type != f.result ||
           exit.value.access != Access::Owned))
        fail({}, "return type does not match function");
    }
  }
  return valid;
}
} // namespace
bool verify(const Program &program, Diagnostics &diagnostics,
            const TypeNormalizer &normalize, const UnpinProof &unpinProof) {
  if (!program.types) {
    diagnostics.error("internal", {}, "CFG has no owned type store");
    return false;
  }
  bool valid = true;
  std::set<std::uint32_t> seen;
  std::function<void(Type, std::set<std::uint32_t>)> type =
      [&](Type current, std::set<std::uint32_t> owned) {
        auto invalid = [&](std::string message) {
          diagnostics.error("internal", {}, "invalid CFG type: " + message);
          valid = false;
        };
        if (!program.types->contains(current) ||
            program.types->isConstant(current)) {
          invalid("unresolved type");
          return;
        }
        if (owned.contains(current.index())) {
          invalid("recursive by-value layout");
          return;
        }
        if (!seen.insert(current.index()).second)
          return;
        if (program.types->isView(current)) {
          const auto &view = program.types->view(current);
          if (view.mode != ParameterMode::Read &&
              view.mode != ParameterMode::Mut)
            invalid("invalid view access");
          type(view.payload, {});
        } else if (program.types->isSlice(current)) {
          auto element = program.types->slice(current).element;
          type(element, {});
          if (valid && !program.types->isSized(element))
            invalid("unsized slice element");
        } else if (program.types->isFunctionPointer(current)) {
          const auto &signature = program.types->callable(current);
          if (signature.resultFromEnvironment)
            invalid("thin callable result refers to a captured environment");
          type(signature.result, {});
          type(signature.abiResult, {});
          if (signature.error == Type::Unknown) {
            if (signature.abiResult != signature.result)
              invalid("callable ABI result does not match success type");
          } else if (!program.types->isProduct(signature.abiResult) ||
                     program.types->product(signature.abiResult).kind !=
                         AggregateKind::Outcome ||
                     program.types->product(signature.abiResult).components !=
                         std::vector<Type>{signature.result, signature.error})
            invalid("callable ABI result does not preserve typed failure");
          if (signature.error != Type::Unknown)
            type(signature.error, {});
          if (signature.mode != ParameterMode::Read &&
              signature.mode != ParameterMode::Mut &&
              signature.mode != ParameterMode::Take)
            invalid("invalid callable capability");
          for (const auto &parameter : signature.parameters) {
            type(parameter.type, {});
            if (parameter.mode == ParameterMode::Value &&
                !program.types->isCopy(parameter.type))
              invalid("non-Copy callable value parameter");
          }
          for (auto source : signature.resultSources)
            if (source >= signature.parameters.size())
              invalid("invalid callable result source");
        } else if (program.types->isProduct(current)) {
          owned.insert(current.index());
          const auto product = program.types->product(current);
          if (product.vector) {
            auto descriptor = targetVector(product.name);
            if (!descriptor || product.kind != AggregateKind::NativeVector ||
                !product.fields.empty() || !product.copyRequested ||
                product.hasDestructor ||
                descriptor->element != product.vector->element ||
                descriptor->lanes != product.vector->lanes ||
                descriptor->alignment != product.vector->alignment)
              invalid("invalid native target vector descriptor");
            else if (!program.target.initialProfile() ||
                     descriptor->arch != program.target.arch)
              invalid("native vector is unavailable on the selected target");
          } else if (product.kind == AggregateKind::NativeVector)
            invalid("native vector is missing its element/lane shape");
          for (std::size_t index = 0; index < product.fields.size(); ++index) {
            const auto &field = product.fields[index];
            type(field.type, owned);
            if (valid && !program.types->isSized(field.type) &&
                index + 1 != product.fields.size())
              invalid("unsized field is not the final field");
            if (product.copyRequested && !program.types->isCopy(field.type))
              invalid("non-Copy field in Copy product");
          }
          if (product.hasDestructor) {
            if (product.copyRequested)
              invalid("Copy product has a user destructor");
            if (product.destructor < 0 ||
                static_cast<std::size_t>(product.destructor) >=
                    program.functions.size())
              invalid("invalid user destructor");
            else {
              const auto &destructor = program.functions[product.destructor];
              Type parameter = destructor.locals.empty()
                                   ? Type::Unknown
                                   : destructor.locals[0].type;
              if (normalize && !destructor.genericParameters.empty()) {
                const auto &arguments = product.genericArguments.empty()
                                            ? product.genericParameters
                                            : product.genericArguments;
                std::vector<TypeBinding> bindings;
                if (arguments.size() == destructor.genericParameters.size())
                  for (std::size_t p = 0; p < arguments.size(); ++p)
                    bindings.push_back(
                        {destructor.genericParameters[p], arguments[p]});
                parameter = normalize(parameter, bindings, destructor);
              }
              bool self = !destructor.locals.empty() && parameter == current;
              if (!destructor.locals.empty() &&
                  !product.layout.pinnedFields.empty()) {
                self = program.types->isProduct(parameter) &&
                       program.types->product(parameter).kind ==
                           AggregateKind::Pin;
                if (self) {
                  auto view = program.types->product(parameter).components[0];
                  self = program.types->isView(view) &&
                         program.types->view(view).mode == ParameterMode::Mut &&
                         program.types->view(view).payload == current;
                }
              }
              if (destructor.result != Type::Unit ||
                  destructor.parameters != 1 || destructor.locals.empty() ||
                  !self || destructor.locals[0].mode != ParameterMode::Mut)
                invalid("invalid user destructor signature");
            }
          }
        }
      };
  for (const auto &f : program.functions) {
    type(f.result, {});
    for (const auto &local : f.locals)
      type(local.type, {});
    for (const auto &block : f.blocks)
      for (const auto &instruction : block.instructions) {
        type(instruction.result.type, {});
        if (instruction.op == Op::DropPlace && instruction.place.root >= 0 &&
            static_cast<std::size_t>(instruction.place.root) < f.locals.size())
          if (auto payload = projectedType(
                  *program.types, f.locals[instruction.place.root].type,
                  instruction.place.fields))
            type(*payload, {});
      }
  }
  std::function<bool(const StaticConstant &, Type)> constant =
      [&](const StaticConstant &value, Type expected) {
        if (value.type != expected || !program.types->contains(expected))
          return false;
        if (value.kind != StaticConstant::Kind::Scalar &&
            (value.scalar.floatingBits || !value.scalar.floating.empty()))
          return false;
        if (value.kind == StaticConstant::Kind::Pointer) {
          if (!(program.types->isPointer(expected) ||
                program.types->isView(expected)) ||
              value.scalar.negative || value.scalar.magnitude[1] ||
              !integerLiteralFits(value.scalar, Type::Usize,
                                  program.types->targetPointerBits()) ||
              value.byteOffset != 0 || !value.projections.empty() ||
              value.symbol != -1)
            return false;
          auto target = program.types->view(expected).payload;
          auto metadata = program.types->pointerMetadata(target);
          if (program.types->isPointer(expected) &&
              metadata == PointerMetadata::None)
            return value.fields.empty();
          auto element = program.types->isSlice(target)
                             ? program.types->slice(target).element
                             : target;
          auto extent = objectLayout(*program.types, element);
          if (!extent || value.scalar.magnitude[0] == 0 ||
              value.scalar.magnitude[0] % extent->alignment)
            return false;
          if (metadata == PointerMetadata::None)
            return value.fields.empty() && extent->size == 0;
          return metadata == PointerMetadata::ElementCount &&
                 value.fields.size() == 1 &&
                 constant(value.fields.front(), Type::Usize) &&
                 (value.fields.front().scalar.magnitude[0] == 0 ||
                  extent->size == 0);
        }
        if (value.kind == StaticConstant::Kind::Address) {
          if (value.scalar.negative || value.scalar.magnitude[1] ||
              value.symbol < 0 ||
              static_cast<std::size_t>(value.symbol) >=
                  program.statics.size() ||
              !(program.types->isView(expected) ||
                program.types->isPointer(expected)))
            return false;
          auto payload = program.statics[value.symbol].type;
          for (auto field : value.projections) {
            if (!program.types->isProduct(payload) ||
                field >= program.types->product(payload).fields.size())
              return false;
            payload = program.types->product(payload).fields[field].type;
          }
          auto target = program.types->view(expected).payload;
          if (program.types->isView(expected) &&
              (program.types->view(expected).mode == ParameterMode::Mut ||
               program.statics[value.symbol].mutableBinding))
            return false;
          if (program.types->view(expected).mode == ParameterMode::Mut &&
              !program.statics[value.symbol].mutableBinding)
            return false;
          if (payload == target && value.byteOffset == 0)
            return true;
          if (value.byteOffset == 0 && program.types->isSlice(target) &&
              program.types->isProduct(payload) &&
              program.types->product(payload).kind == AggregateKind::Array &&
              program.types->slice(target).element ==
                  program.types->product(payload).components[0] &&
              value.scalar.magnitude[0] == program.types->arrayLength(payload))
            return true;
          auto leaf = [&](Type type) {
            while (program.types->isProduct(type) &&
                   program.types->product(type).kind == AggregateKind::Array)
              type = program.types->product(type).components.front();
            return type;
          };
          auto element = program.types->isSlice(target)
                             ? program.types->slice(target).element
                             : target;
          if (leaf(payload) != leaf(element))
            return false;
          auto backing = objectLayout(*program.types, payload);
          auto extent = objectLayout(*program.types, element);
          auto unit = objectLayout(*program.types, leaf(element));
          if (!backing || !extent || !unit ||
              (unit->size && value.byteOffset % unit->size) ||
              value.byteOffset > backing->size ||
              value.byteOffset % extent->alignment)
            return false;
          auto remaining = backing->size - value.byteOffset;
          if (program.types->isSlice(target))
            return !extent->size ||
                   value.scalar.magnitude[0] <= remaining / extent->size;
          return program.types->isPointer(expected) ||
                 extent->size <= remaining;
        }
        if (value.kind == StaticConstant::Kind::Text) {
          return textConstantCount(*program.types, value).has_value();
        }
        if (value.kind == StaticConstant::Kind::Function)
          return program.types->isFunctionPointer(expected) &&
                 value.symbol >= 0 &&
                 static_cast<std::size_t>(value.symbol) <
                     program.functions.size();
        if (value.kind == StaticConstant::Kind::Repeat)
          return program.types->compactArray(expected) &&
                 value.fields.size() == 1 &&
                 constant(value.fields[0],
                          program.types->product(expected).components[0]);
        if (value.kind == StaticConstant::Kind::Aggregate) {
          if (!program.types->isProduct(expected))
            return false;
          auto fields = staticConstantFields(*program.types, value);
          if (!fields || fields->size() != value.fields.size())
            return false;
          const auto &record = program.types->product(expected);
          if (program.types->isSum(expected) &&
              record.layout.kind != LayoutKind::Transparent) {
            NumericLiteral tag;
            tag.magnitude[0] = value.selection;
            if (!record.layout.discriminants.empty())
              tag = record.layout.discriminants[value.selection];
            if (value.fields[0].scalar.magnitude != tag.magnitude ||
                value.fields[0].scalar.negative != tag.negative)
              return false;
          }
          for (std::size_t i = 0; i < fields->size(); ++i)
            if (!constant(value.fields[i], (*fields)[i].second))
              return false;
          return true;
        }
        if (isInteger(expected))
          return integerLiteralFits(value.scalar, expected);
        if (isFloating(expected))
          return validFloatingConstant(value.scalar, expected);
        if (expected == Type::Bool || expected == Type::Char)
          return integerLiteralFits(value.scalar, expected);
        return expected == Type::Unit && value.scalar == NumericLiteral{};
      };
  for (const auto &storage : program.statics) {
    type(storage.type, {});
    if (!program.types->isSized(storage.type) ||
        program.types->uninhabited(storage.type) ||
        storage.foreignDeclaration == storage.initializer.has_value() ||
        (storage.initializer &&
         !constant(*storage.initializer, storage.type))) {
      diagnostics.error("internal", storage.span,
                        "invalid typed static initializer or storage contract");
      valid = false;
    }
  }
  if (!valid)
    return false;
  bool entry = false;
  std::unordered_set<std::string> names;
  for (const auto &f : program.functions) {
    if (!names.insert(f.name).second) {
      diagnostics.error("internal", {}, "duplicate CFG function");
      valid = false;
    }
    if (f.name == "main")
      entry = f.parameters == 0 && f.result == Type::I32;
    valid = function(f, program, diagnostics, normalize, unpinProof) && valid;
  }
  if (program.requireEntry && !entry) {
    diagnostics.error("internal", {}, "invalid or absent CFG entry function");
    valid = false;
  }
  return valid && verifyTarget(program, diagnostics);
}
} // namespace mettle::ir
