#pragma once

#include "backend/llvm/cleanup.h"
#include "types/assembly.h"
#include <functional>

namespace mettle::backend {
using AssemblySymbolResolver =
    std::function<llvm::GlobalValue *(AssemblyOperand::SymbolKind, int)>;
void targetAttributes(llvm::Function &function, const TargetFacts &target,
                      const std::set<std::string> &features);
llvm::Value *targetOperation(LoweringContext &context,
                             const ir::Instruction &instruction,
                             llvm::ArrayRef<llvm::Value *> operands);
llvm::Value *detectFeature(LoweringContext &context, std::string_view feature);
llvm::Value *emitAssembly(LoweringContext &context, const Assembly &assembly,
                          Type result, llvm::ArrayRef<llvm::Value *> inputs,
                          const AssemblySymbolResolver &symbols);
std::string globalAssembly(LoweringContext &context, const Assembly &assembly,
                           const AssemblySymbolResolver &symbols);
} // namespace mettle::backend
