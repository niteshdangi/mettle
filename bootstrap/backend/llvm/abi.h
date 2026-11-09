#pragma once

#include "backend/llvm/cleanup.h"
#include <optional>

namespace mettle::backend {
struct CAbiValue {
  Type type;
  bool scalar = true, indirect = false, byValue = false;
  std::vector<llvm::Type *> pieces{};
  std::vector<std::uint64_t> offsets{};
  Type scalarType = Type::Unknown;
  bool aggregate = false;
};
struct CAbiSignature {
  CAbiValue result;
  std::vector<CAbiValue> parameters;
  llvm::FunctionType *type = nullptr;
  unsigned integerRegisters = 0, floatRegisters = 0;
  bool variadic = false;
};
class CAbi {
public:
  CAbi(LoweringContext &context, bool aarch64)
      : context(context), aarch64(aarch64) {}
  CAbiSignature signature(const ir::Function &function);
  void attributes(llvm::Function &function, const CAbiSignature &signature);
  llvm::Value *call(llvm::Value *target, const CAbiSignature &signature,
                    llvm::ArrayRef<llvm::Value *> arguments,
                    llvm::ArrayRef<Type> argumentTypes);
  void exportBody(llvm::Function &external, llvm::Function &body,
                  const CAbiSignature &signature);
  llvm::Value *variadicArgument(llvm::Value *cursor, Type type);

private:
  LoweringContext &context;
  bool aarch64;
  std::optional<unsigned> transparentField(Type type);
  CAbiValue classify(Type type, bool result);
  std::vector<llvm::Value *> encode(const CAbiValue &value,
                                    llvm::Value *source);
  llvm::Value *decode(const CAbiValue &value,
                      llvm::ArrayRef<llvm::Value *> pieces);
  void callAttributes(llvm::CallBase &call, const CAbiSignature &signature);
};
} // namespace mettle::backend
