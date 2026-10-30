#pragma once

#include "llvm/ADT/StringRef.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/Support/Error.h"
#include <string>

namespace llvm {
class Module;
}

namespace mettle {
class TypeStore;
}

namespace mettle::backend {

// The target used when none is requested. On Darwin ARM64 it carries the
// documented deployment target instead of the host kernel version.
std::string defaultTargetTriple();

// The data layout the LLVM target machine selects for the triple.
llvm::Expected<llvm::DataLayout> targetDataLayout(llvm::StringRef triple);

// Fails when the compiler-owned scalar and pointer sizes/alignments disagree
// with the target machine's data layout.
llvm::Error checkTargetLayout(const TypeStore &types, llvm::StringRef triple);

llvm::Error emitObject(llvm::Module &module, llvm::StringRef triple,
                       llvm::StringRef output, bool optimize = false);

} // namespace mettle::backend
