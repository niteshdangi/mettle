#include "backend/llvm/object.h"

#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Host.h"

#include <string>
#include <utility>

int main(int argc, char **argv) {
  if (argc != 2 && argc != 3) {
    llvm::errs() << "Usage: mettle-object-smoke output.o "
                    "[target-triple|--invalid-module]\n";
    return 2;
  }
  llvm::LLVMContext context;
  llvm::Module module("mettle-foundation-smoke", context);
  auto *type = llvm::FunctionType::get(llvm::Type::getInt32Ty(context), false);
  auto *function = llvm::Function::Create(type, llvm::Function::ExternalLinkage,
                                          "main", module);
  llvm::IRBuilder<> builder(
      llvm::BasicBlock::Create(context, "entry", function));
  const bool invalid = argc == 3 && std::string(argv[2]) == "--invalid-module";
  if (invalid) {
    builder.CreateRetVoid();
  } else {
    builder.CreateRet(
        llvm::ConstantInt::get(llvm::Type::getInt32Ty(context), 37));
  }
  const auto triple = argc == 3 && !invalid
                          ? std::string(argv[2])
                          : llvm::sys::getDefaultTargetTriple();
  if (auto error = mettle::backend::emitObject(module, triple, argv[1])) {
    llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                                "mettle-object-smoke: ");
    return 1;
  }
  return 0;
}
