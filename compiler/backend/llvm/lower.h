#pragma once
#include "ir/verified.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

namespace mettle::backend {
std::unique_ptr<llvm::Module> lower(const ir::VerifiedProgram &program,
                                    llvm::LLVMContext &context, bool checked);
}
