#pragma once

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"

namespace llvm {
class Module;
}

namespace mettle::backend {

llvm::Error emitObject(llvm::Module &module, llvm::StringRef triple,
                       llvm::StringRef output, bool optimize = false);

}
