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
  // A reusable library object: every body is lowered, the identity's own
  // functions are exported and other unowned bodies are private copies.
  bool library = false;
  // Cached native libraries cannot refer to root-owned definitions.
  bool privateRoot = false;
};

std::unique_ptr<llvm::Module>
lower(const ir::VerifiedProgram &program, llvm::LLVMContext &context,
      bool checked, llvm::StringRef target = {}, bool freestanding = false,
      const DebugInfoRequest *debug = nullptr, bool sanitizeAddress = false,
      bool sanitizeThread = false, CodegenPartition partition = {},
      const DebugInfoRequest *sourceInfo = nullptr);
} // namespace mettle::backend
