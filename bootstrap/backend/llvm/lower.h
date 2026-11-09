#pragma once
#include "backend/llvm/debug.h"
#include "ir/verified.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include <string>

namespace mettle::backend {
struct CodegenPartition {
  bool split = false;
  // Empty selects the root unit; other identities select a dependency unit.
  std::string packageIdentity;
  bool emitEntry = true;
};

std::unique_ptr<llvm::Module>
lower(const ir::VerifiedProgram &program, llvm::LLVMContext &context,
      bool checked, llvm::StringRef target = {}, bool freestanding = false,
      const DebugInfoRequest *debug = nullptr, bool sanitizeAddress = false,
      bool sanitizeThread = false, CodegenPartition partition = {});
} // namespace mettle::backend
