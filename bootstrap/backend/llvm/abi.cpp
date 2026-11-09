#include "backend/llvm/abi.h"
#include "llvm/IR/Intrinsics.h"
#include <algorithm>
#include <functional>
#include <set>

namespace mettle::backend {
std::optional<unsigned> CAbi::transparentField(Type type) {
  if (!context.program.types->isProduct(type))
    return std::nullopt;
  const auto &record = context.program.types->product(type);
  if (record.layout.kind != LayoutKind::Transparent)
    return std::nullopt;
  for (std::size_t i = record.kind == AggregateKind::Enumeration ? 1 : 0;
       i < record.fields.size(); ++i)
    if (context.layout(record.fields[i].type).size)
      return i;
  return std::nullopt;
}
CAbiValue CAbi::classify(Type type, bool result) {
  CAbiValue value{type};
  value.scalarType = type;
  if (type == Type::Unit || type == Type::Never)
    return value;
  if (!context.program.types->isProduct(type) ||
      context.program.types->product(type).vector) {
    value.pieces.push_back(context.type(type));
    value.offsets.push_back(0);
    return value;
  }
  if (auto field = transparentField(type)) {
    auto forwarded = classify(
        context.program.types->product(type).fields[*field].type, result);
    forwarded.type = type;
    forwarded.scalar = false;
    return forwarded;
  }
  value.scalar = false;
  value.aggregate = true;
  if (fieldlessEnumeration(*context.program.types, type)) {
    value.scalarType = context.program.types->product(type).layout.tag;
    value.aggregate = false;
    value.pieces = {
        context.type(context.program.types->product(type).layout.tag)};
    value.offsets = {0};
    return value;
  }
  auto layout = context.layout(type);
  if (!layout.size)
    return value;
  std::vector<std::pair<Type, std::uint64_t>> leaves;
  std::function<void(Type, std::uint64_t)> flatten = [&](Type current,
                                                         std::uint64_t offset) {
    if (!context.program.types->isProduct(current) ||
        context.program.types->product(current).vector) {
      if (context.layout(current).size)
        leaves.emplace_back(current, offset);
      return;
    }
    const auto &record = context.program.types->product(current);
    const auto &fields = record.fields;
    auto offsets = context.layout(current).fields;
    for (std::size_t i = record.kind == AggregateKind::Enumeration &&
                                 record.layout.kind == LayoutKind::Transparent
                             ? 1
                             : 0;
         i < fields.size(); ++i)
      flatten(i == 0 && context.program.types->product(current).kind ==
                            AggregateKind::Enumeration
                  ? context.program.types->product(current).layout.tag
                  : fields[i].type,
              offset + offsets[i]);
  };
  flatten(type, 0);
  std::sort(leaves.begin(), leaves.end());
  leaves.erase(std::unique(leaves.begin(), leaves.end()), leaves.end());
  if (aarch64) {
    bool vectorLeaf = !leaves.empty() &&
                      context.program.types->isProduct(leaves[0].first) &&
                      context.program.types->product(leaves[0].first).vector;
    std::set<std::uint64_t> memberOffsets;
    for (const auto &leaf : leaves)
      memberOffsets.insert(leaf.second);
    auto members = vectorLeaf ? memberOffsets.size() : leaves.size();
    bool homogeneous =
        !leaves.empty() && members <= 4 &&
        (isFloating(leaves[0].first) || vectorLeaf) &&
        std::all_of(leaves.begin(), leaves.end(), [&](const auto &leaf) {
          return vectorLeaf
                     ? context.program.types->isProduct(leaf.first) &&
                           context.program.types->product(leaf.first).vector &&
                           context.layout(leaf.first).size ==
                               context.layout(leaves[0].first).size
                     : leaf.first == leaves[0].first;
        });
    if (homogeneous) {
      std::vector<llvm::Type *> fields(members, context.type(leaves[0].first));
      value.pieces.push_back(
          result ? static_cast<llvm::Type *>(
                       llvm::StructType::get(context.context, fields))
                 : llvm::ArrayType::get(fields[0], fields.size()));
      value.offsets.push_back(0);
      return value;
    }
    if (layout.size <= 16) {
      value.pieces.push_back(
          layout.alignment >= 16
              ? static_cast<llvm::Type *>(context.builder.getInt128Ty())
          : layout.size <= 8
              ? static_cast<llvm::Type *>(
                    context.builder.getIntNTy(result ? layout.size * 8 : 64))
              : llvm::ArrayType::get(context.builder.getInt64Ty(), 2));
      value.offsets.push_back(0);
      return value;
    }
    value.indirect = true;
    return value;
  }
  if (layout.size > 16 || layout.unaligned) {
    value.indirect = true;
    value.byValue = !result;
    return value;
  }
  enum class RegisterClass { None, Integer, Sse, SseUp };
  struct Chunk {
    RegisterClass kind = RegisterClass::None;
    bool wideFloat = false;
    unsigned used = 0;
  };
  Chunk chunks[2];
  for (auto [leaf, offset] : leaves) {
    auto size = context.layout(leaf).size;
    bool vector = context.program.types->isProduct(leaf) &&
                  context.program.types->product(leaf).vector;
    for (std::uint64_t byte = offset; byte < offset + size; ++byte) {
      auto &chunk = chunks[byte / 8];
      auto kind = vector ? (byte - offset < 8 ? RegisterClass::Sse
                                              : RegisterClass::SseUp)
                  : isFloating(leaf) ? RegisterClass::Sse
                                     : RegisterClass::Integer;
      if (chunk.kind == RegisterClass::None || kind == RegisterClass::Integer)
        chunk.kind = kind;
      else if (chunk.kind != RegisterClass::Integer &&
               kind == RegisterClass::Sse)
        chunk.kind = kind;
      chunk.wideFloat |= leaf == Type::F64 || vector;
      chunk.used = std::max(chunk.used, static_cast<unsigned>(byte % 8 + 1));
    }
  }
  if (chunks[0].kind == RegisterClass::Sse &&
      chunks[1].kind == RegisterClass::SseUp) {
    value.pieces.push_back(
        llvm::FixedVectorType::get(context.builder.getInt64Ty(), 2));
    value.offsets.push_back(0);
    return value;
  }
  for (unsigned i = 0; i < 2; ++i) {
    auto &chunk = chunks[i];
    if (!chunk.used)
      continue;
    llvm::Type *physical;
    if (chunk.kind == RegisterClass::Integer)
      physical = context.builder.getIntNTy(chunk.used * 8);
    else if (chunk.wideFloat)
      physical = context.builder.getDoubleTy();
    else if (chunk.used > 4)
      physical = llvm::FixedVectorType::get(context.builder.getFloatTy(), 2);
    else
      physical = context.builder.getFloatTy();
    value.pieces.push_back(physical);
    value.offsets.push_back(i * 8);
  }
  return value;
}
CAbiSignature CAbi::signature(const ir::Function &function) {
  CAbiSignature signature;
  signature.result = classify(function.result, true);
  signature.variadic = function.variadic;
  std::vector<llvm::Type *> parameters;
  if (signature.result.indirect) {
    parameters.push_back(context.builder.getPtrTy());
    signature.integerRegisters = 1;
  }
  for (std::size_t p = 0; p < function.parameters; ++p) {
    const auto &source = function.locals[p];
    CAbiValue value{source.type};
    if (source.mode == ParameterMode::Read ||
        source.mode == ParameterMode::Mut) {
      value.pieces = {context.builder.getPtrTy()};
      value.offsets = {0};
    } else
      value = classify(source.type, false);
    if (!aarch64 && !value.indirect) {
      unsigned integers = 0, floats = 0;
      for (auto *piece : value.pieces)
        if (piece->isFloatingPointTy() || piece->isVectorTy())
          ++floats;
        else
          integers += piece->isIntegerTy(128) ? 2 : 1;
      if (value.aggregate && (signature.integerRegisters + integers > 6 ||
                              signature.floatRegisters + floats > 8)) {
        value.indirect = value.byValue = true;
        value.pieces.clear();
        value.offsets.clear();
      } else {
        if (signature.integerRegisters + integers <= 6)
          signature.integerRegisters += integers;
        if (signature.floatRegisters + floats <= 8)
          signature.floatRegisters += floats;
      }
    }
    if (value.indirect)
      parameters.push_back(context.builder.getPtrTy());
    else
      parameters.insert(parameters.end(), value.pieces.begin(),
                        value.pieces.end());
    signature.parameters.push_back(std::move(value));
  }
  llvm::Type *result = context.builder.getVoidTy();
  if (!signature.result.indirect && signature.result.pieces.size() == 1)
    result = signature.result.pieces[0];
  else if (!signature.result.indirect && !signature.result.pieces.empty())
    result = llvm::StructType::get(context.context, signature.result.pieces);
  signature.type =
      llvm::FunctionType::get(result, parameters, function.variadic);
  return signature;
}
void CAbi::attributes(llvm::Function &function,
                      const CAbiSignature &signature) {
  unsigned index = 0;
  if (signature.result.indirect) {
    function.addParamAttr(
        index, llvm::Attribute::getWithStructRetType(
                   context.context, context.type(signature.result.type)));
    function.addParamAttr(
        index, llvm::Attribute::getWithAlignment(
                   context.context,
                   llvm::Align(context.alignment(signature.result.type))));
    ++index;
  } else if (!signature.result.aggregate &&
             signature.type->getReturnType()->isIntegerTy() &&
             integerWidth(signature.result.scalarType) < 32)
    function.addRetAttr(isSignedInteger(signature.result.scalarType)
                            ? llvm::Attribute::SExt
                            : llvm::Attribute::ZExt);
  for (const auto &value : signature.parameters) {
    if (value.indirect) {
      if (value.byValue)
        function.addParamAttr(
            index, llvm::Attribute::getWithByValType(context.context,
                                                     context.type(value.type)));
      function.addParamAttr(
          index,
          llvm::Attribute::getWithAlignment(
              context.context,
              llvm::Align(value.byValue ? std::max<std::uint64_t>(
                                              8, context.alignment(value.type))
                                        : context.alignment(value.type))));
      ++index;
    } else {
      for (auto *piece : value.pieces) {
        if (!value.aggregate && piece->isIntegerTy() &&
            integerWidth(value.scalarType) < 32)
          function.addParamAttr(index, isSignedInteger(value.scalarType)
                                           ? llvm::Attribute::SExt
                                           : llvm::Attribute::ZExt);
        ++index;
      }
    }
  }
}
std::vector<llvm::Value *> CAbi::encode(const CAbiValue &value,
                                        llvm::Value *source) {
  if (customRepresentation(*context.program.types, value.type))
    source = context.builder.CreateFreeze(source);
  if (value.scalar)
    return value.pieces.empty() ? std::vector<llvm::Value *>{}
                                : std::vector<llvm::Value *>{source};
  if (value.indirect) {
    auto *storage = context.temporary(value.type);
    storage->setAlignment(
        llvm::Align(std::max<std::uint64_t>(8, context.alignment(value.type))));
    context.builder.CreateStore(source, storage);
    return {storage};
  }
  auto size = context.layout(value.type).size;
  for (std::size_t i = 0; i < value.pieces.size(); ++i)
    size =
        std::max(size, value.offsets[i] + context.module.getDataLayout()
                                              .getTypeAllocSize(value.pieces[i])
                                              .getFixedValue());
  auto *buffer = llvm::ArrayType::get(context.builder.getInt8Ty(), size);
  auto *storage = context.temporary(buffer);
  storage->setAlignment(
      llvm::Align(std::max<std::uint64_t>(16, context.alignment(value.type))));
  context.builder.CreateStore(llvm::Constant::getNullValue(buffer), storage);
  context.builder.CreateStore(source, storage);
  std::vector<llvm::Value *> result;
  for (std::size_t i = 0; i < value.pieces.size(); ++i) {
    auto *pointer =
        context.builder.CreateGEP(context.builder.getInt8Ty(), storage,
                                  context.builder.getInt64(value.offsets[i]));
    result.push_back(context.builder.CreateAlignedLoad(value.pieces[i], pointer,
                                                       llvm::Align(1)));
  }
  return result;
}
llvm::Value *CAbi::decode(const CAbiValue &value,
                          llvm::ArrayRef<llvm::Value *> pieces) {
  if (value.scalar)
    return pieces.empty()
               ? llvm::Constant::getNullValue(context.type(value.type))
               : pieces[0];
  if (value.indirect)
    return context.builder.CreateAlignedLoad(context.type(value.type),
                                             pieces[0], llvm::Align(1));
  auto size = context.layout(value.type).size;
  for (std::size_t i = 0; i < value.pieces.size(); ++i)
    size =
        std::max(size, value.offsets[i] + context.module.getDataLayout()
                                              .getTypeAllocSize(value.pieces[i])
                                              .getFixedValue());
  auto *buffer = llvm::ArrayType::get(context.builder.getInt8Ty(), size);
  auto *storage = context.temporary(buffer);
  storage->setAlignment(
      llvm::Align(std::max<std::uint64_t>(16, context.alignment(value.type))));
  context.builder.CreateStore(llvm::Constant::getNullValue(buffer), storage);
  for (std::size_t i = 0; i < pieces.size(); ++i) {
    auto *pointer =
        context.builder.CreateGEP(context.builder.getInt8Ty(), storage,
                                  context.builder.getInt64(value.offsets[i]));
    context.builder.CreateAlignedStore(pieces[i], pointer, llvm::Align(1));
  }
  return context.builder.CreateLoad(context.type(value.type), storage);
}
void CAbi::callAttributes(llvm::CallBase &call,
                          const CAbiSignature &signature) {
  std::vector<llvm::Type *> parameters;
  for (auto &argument : call.args())
    parameters.push_back(argument->getType());
  auto *type = llvm::FunctionType::get(signature.type->getReturnType(),
                                       parameters, false);
  auto *temporary = llvm::Function::Create(
      type, llvm::GlobalValue::ExternalLinkage, "", context.module);
  attributes(*temporary, signature);
  call.setAttributes(temporary->getAttributes());
  temporary->eraseFromParent();
}
llvm::Value *CAbi::call(llvm::Value *target, const CAbiSignature &signature,
                        llvm::ArrayRef<llvm::Value *> arguments,
                        llvm::ArrayRef<Type> argumentTypes) {
  std::vector<llvm::Value *> physical;
  auto callSignature = signature;
  llvm::Value *returned = nullptr;
  if (signature.result.indirect) {
    returned = context.temporary(signature.result.type);
    physical.push_back(returned);
  }
  for (std::size_t i = 0; i < arguments.size(); ++i) {
    if (i < signature.parameters.size()) {
      auto pieces = encode(signature.parameters[i], arguments[i]);
      physical.insert(physical.end(), pieces.begin(), pieces.end());
    } else {
      auto value = arguments[i];
      auto type = argumentTypes[i];
      while (auto field = transparentField(type)) {
        value = context.extract(value, type, *field);
        type = context.program.types->product(type).fields[*field].type;
      }
      if (fieldlessEnumeration(*context.program.types, type)) {
        auto *storage = context.temporary(type);
        context.builder.CreateStore(value, storage);
        value = context.enumTag(type, storage, false);
        type = context.program.types->product(type).layout.tag;
      }
      if (type == Type::F32) {
        value =
            context.builder.CreateFPExt(value, context.builder.getDoubleTy());
        type = Type::F64;
      } else if (type == Type::Bool ||
                 (isInteger(type) && integerWidth(type) < 32)) {
        value = context.builder.CreateIntCast(
            value, context.builder.getInt32Ty(), isSignedInteger(type));
        type = Type::I32;
      }
      auto parameter = classify(type, false);
      unsigned integers = 0, floats = 0;
      for (auto *piece : parameter.pieces)
        if (piece->isFloatingPointTy() || piece->isVectorTy())
          ++floats;
        else
          integers += piece->isIntegerTy(128) ? 2 : 1;
      // SysV unnamed wide vectors are stack arguments. Their LLVM vector type
      // drives that lowering; they do not consume later aggregates' SSE budget.
      if (!aarch64 && context.program.types->isProduct(type) &&
          context.program.types->product(type).vector &&
          context.layout(type).size > 16)
        floats = 0;
      if (!aarch64 && parameter.aggregate &&
          (callSignature.integerRegisters + integers > 6 ||
           callSignature.floatRegisters + floats > 8)) {
        parameter.indirect = parameter.byValue = true;
        parameter.pieces.clear();
        parameter.offsets.clear();
      } else if (!parameter.indirect) {
        if (callSignature.integerRegisters + integers <= 6)
          callSignature.integerRegisters += integers;
        if (callSignature.floatRegisters + floats <= 8)
          callSignature.floatRegisters += floats;
      }
      auto pieces = encode(parameter, value);
      physical.insert(physical.end(), pieces.begin(), pieces.end());
      callSignature.parameters.push_back(std::move(parameter));
    }
  }
  auto *call = context.builder.CreateCall(signature.type, target, physical);
  callAttributes(*call, callSignature);
  if (returned)
    return context.builder.CreateLoad(context.type(signature.result.type),
                                      returned);
  std::vector<llvm::Value *> result;
  if (signature.result.pieces.size() == 1)
    result.push_back(call);
  else
    for (unsigned i = 0; i < signature.result.pieces.size(); ++i)
      result.push_back(context.builder.CreateExtractValue(call, i));
  return decode(signature.result, result);
}
void CAbi::exportBody(llvm::Function &external, llvm::Function &body,
                      const CAbiSignature &signature) {
  auto saved = context.builder.saveIP();
  context.builder.SetInsertPoint(
      llvm::BasicBlock::Create(context.context, "entry", &external));
  unsigned index = signature.result.indirect ? 1 : 0;
  std::vector<llvm::Value *> arguments;
  for (const auto &parameter : signature.parameters) {
    std::vector<llvm::Value *> pieces;
    auto count = parameter.indirect ? 1 : parameter.pieces.size();
    for (std::size_t p = 0; p < count; ++p)
      pieces.push_back(external.getArg(index++));
    arguments.push_back(decode(parameter, pieces));
  }
  const bool cursor = signature.variadic && body.arg_size() > arguments.size();
  if (cursor) {
    // This must remain in the physical variadic entry: the logical cleanup
    // wrapper has no access to the caller's incoming argument registers.
    auto *cursor = context.temporary(
        llvm::ArrayType::get(context.builder.getInt64Ty(), 3));
    cursor->setAlignment(llvm::Align(8));
    context.builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
                                   &context.module, llvm::Intrinsic::vastart,
                                   {context.builder.getPtrTy()}),
                               {cursor});
    arguments.push_back(cursor);
  }
  auto *result = context.builder.CreateCall(&body, arguments);
  if (cursor)
    // va_start and va_end stay in this physical entry. An unwinding callee
    // skips this, which is harmless where va_end is a no-op (the supported
    // Darwin ARM64 and Linux x86-64 ABIs); the frame's copy has its own end.
    context.builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
                                   &context.module, llvm::Intrinsic::vaend,
                                   {context.builder.getPtrTy()}),
                               {arguments.back()});
  if (signature.result.indirect) {
    context.builder.CreateStore(result, external.getArg(0));
    context.builder.CreateRetVoid();
  } else {
    auto pieces = encode(signature.result, result);
    if (pieces.empty())
      context.builder.CreateRetVoid();
    else if (pieces.size() == 1)
      context.builder.CreateRet(pieces[0]);
    else {
      llvm::Value *value =
          llvm::Constant::getNullValue(signature.type->getReturnType());
      for (unsigned p = 0; p < pieces.size(); ++p)
        value = context.builder.CreateInsertValue(value, pieces[p], p);
      context.builder.CreateRet(value);
    }
  }
  context.builder.restoreIP(saved);
}
llvm::Value *CAbi::variadicArgument(llvm::Value *cursor, Type type) {
  auto &builder = context.builder;
  auto classified = classify(type, false);
  if (!context.layout(type).size)
    return llvm::Constant::getNullValue(context.type(type));
  auto *function = builder.GetInsertBlock()->getParent();
  auto alignPointer = [&](llvm::Value *pointer, std::uint64_t alignment) {
    auto *bits = builder.CreatePtrToInt(pointer, builder.getInt64Ty());
    bits = builder.CreateAnd(
        builder.CreateAdd(bits, builder.getInt64(alignment - 1)),
        builder.getInt64(~(alignment - 1)));
    return builder.CreateIntToPtr(bits, builder.getPtrTy());
  };
  auto stackArgument = [&](llvm::Value *slot, bool indirect) {
    auto *next = builder.CreateLoad(builder.getPtrTy(), slot);
    auto alignment =
        indirect ? 8 : std::max<std::uint64_t>(8, context.alignment(type));
    auto *address = alignPointer(next, alignment);
    auto size = indirect ? 8 : context.layout(type).size;
    builder.CreateStore(
        builder.CreateGEP(builder.getInt8Ty(), address,
                          builder.getInt64((size + 7) & ~std::uint64_t{7})),
        slot);
    if (indirect)
      address = builder.CreateLoad(builder.getPtrTy(), address);
    return builder.CreateAlignedLoad(context.type(type), address,
                                     llvm::Align(1));
  };
  if (aarch64)
    return stackArgument(cursor, classified.indirect);
  auto *vaType = llvm::StructType::get(
      context.context, {builder.getInt32Ty(), builder.getInt32Ty(),
                        builder.getPtrTy(), builder.getPtrTy()});
  auto *overflow = builder.CreateStructGEP(vaType, cursor, 2);
  if (classified.indirect || classified.pieces.empty() ||
      (classified.pieces.size() == 1 && classified.pieces[0]->isVectorTy() &&
       context.layout(type).size > 16))
    return stackArgument(overflow, false);
  unsigned integers = 0, floats = 0;
  for (auto *piece : classified.pieces)
    if (piece->isFloatingPointTy() || piece->isVectorTy())
      ++floats;
    else
      integers += piece->isIntegerTy(128) ? 2 : 1;
  auto *gpSlot = builder.CreateStructGEP(vaType, cursor, 0);
  auto *fpSlot = builder.CreateStructGEP(vaType, cursor, 1);
  llvm::Value *gp = builder.CreateLoad(builder.getInt32Ty(), gpSlot);
  llvm::Value *fp = builder.CreateLoad(builder.getInt32Ty(), fpSlot);
  auto *available = builder.CreateAnd(
      builder.CreateICmpULE(gp, builder.getInt32(48 - integers * 8)),
      builder.CreateICmpULE(fp, builder.getInt32(176 - floats * 16)));
  auto *registers =
      llvm::BasicBlock::Create(context.context, "va.registers", function);
  auto *stack = llvm::BasicBlock::Create(context.context, "va.stack", function);
  auto *done = llvm::BasicBlock::Create(context.context, "va.done", function);
  builder.CreateCondBr(available, registers, stack);
  builder.SetInsertPoint(registers);
  auto *save = builder.CreateLoad(builder.getPtrTy(),
                                  builder.CreateStructGEP(vaType, cursor, 3));
  std::vector<llvm::Value *> pieces;
  for (auto *piece : classified.pieces) {
    bool floating = piece->isFloatingPointTy() || piece->isVectorTy();
    auto *address = builder.CreateGEP(
        builder.getInt8Ty(), save,
        builder.CreateZExt(floating ? fp : gp, builder.getInt64Ty()));
    pieces.push_back(builder.CreateAlignedLoad(piece, address, llvm::Align(1)));
    if (floating)
      fp = builder.CreateAdd(fp, builder.getInt32(16));
    else
      gp = builder.CreateAdd(
          gp, builder.getInt32(piece->isIntegerTy(128) ? 16 : 8));
  }
  builder.CreateStore(gp, gpSlot);
  builder.CreateStore(fp, fpSlot);
  auto *fromRegisters = decode(classified, pieces);
  builder.CreateBr(done);
  auto *registerEnd = builder.GetInsertBlock();
  builder.SetInsertPoint(stack);
  auto *fromStack = stackArgument(overflow, false);
  builder.CreateBr(done);
  auto *stackEnd = builder.GetInsertBlock();
  builder.SetInsertPoint(done);
  auto *result = builder.CreatePHI(context.type(type), 2);
  result->addIncoming(fromRegisters, registerEnd);
  result->addIncoming(fromStack, stackEnd);
  return result;
}
} // namespace mettle::backend
