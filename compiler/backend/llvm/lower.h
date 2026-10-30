#pragma once
#include "backend/llvm/debug.h"
#include "ir/verified.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"

namespace mettle::backend {
std::unique_ptr<llvm::Module> lower(const ir::VerifiedProgram &program,
                                    llvm::LLVMContext &context, bool checked,
                                    llvm::StringRef target = {},
                                    bool freestanding = false,
                                    const DebugInfoRequest *debug = nullptr);
}
