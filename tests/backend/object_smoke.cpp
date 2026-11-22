#include "backend/llvm/object.h"

#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/ArchiveWriter.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"

#include <string>
#include <utility>
#include <vector>

int main(int argc, char **argv) {
  if (argc != 2 && argc != 3) {
    llvm::errs() << "Usage: mettle-object-smoke output.o "
                    "[target-triple|--invalid-module|--units]\n";
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
  const bool units = argc == 3 && std::string(argv[2]) == "--units";
  if (invalid) {
    builder.CreateRetVoid();
  } else if (units) {
    auto *storage = new llvm::GlobalVariable(
        module, builder.getInt32Ty(), false, llvm::GlobalValue::InternalLinkage,
        builder.getInt32(37), "storage");
    auto *worker = llvm::Function::Create(
        type, llvm::GlobalValue::InternalLinkage, "worker", module);
    worker->setCallingConv(llvm::CallingConv::Fast);
    worker->addFnAttr(llvm::Attribute::NoInline);
    worker->addFnAttr(llvm::Attribute::OptimizeNone);
    llvm::IRBuilder<> body(llvm::BasicBlock::Create(context, "entry", worker));
    auto *load = body.CreateLoad(body.getInt32Ty(), storage);
    load->setVolatile(true);
    body.CreateRet(load);
    auto *call = builder.CreateCall(worker);
    call->setCallingConv(llvm::CallingConv::Fast);
    builder.CreateRet(call);
    auto *unused = llvm::Function::Create(
        type, llvm::GlobalValue::ExternalLinkage, "unused", module);
    auto missing = module.getOrInsertFunction("missing_unused_reference", type);
    body.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", unused));
    body.CreateRet(body.CreateCall(missing));
  } else {
    builder.CreateRet(
        llvm::ConstantInt::get(llvm::Type::getInt32Ty(context), 37));
  }
  const auto triple = argc == 3 && !invalid && !units
                          ? std::string(argv[2])
                          : llvm::sys::getDefaultTargetTriple();
  if (units) {
    std::vector<llvm::NewArchiveMember> members;
    std::vector<std::string> paths;
    auto error = mettle::backend::emitObjectUnits(
        module, triple, "smoke", true,
        [&](llvm::Module &,
            mettle::backend::ObjectUnitEmitter emit) -> llvm::Error {
          paths.push_back(std::string(argv[1]) + "." +
                          std::to_string(paths.size()) + ".o");
          if (auto error = emit(paths.back()))
            return error;
          auto member = llvm::NewArchiveMember::getFile(paths.back(), true);
          if (!member)
            return member.takeError();
          members.push_back(std::move(*member));
          return llvm::Error::success();
        });
    if (!error)
      error = llvm::writeArchive(
          argv[1], members, llvm::SymtabWritingMode::NormalSymtab,
          llvm::object::Archive::getDefaultKindForTriple(llvm::Triple(triple)),
          true, false);
    for (const auto &path : paths)
      llvm::sys::fs::remove(path);
    if (error) {
      llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                                  "mettle-object-smoke: ");
      return 1;
    }
    return 0;
  }
  if (auto error = mettle::backend::emitObject(module, triple, argv[1])) {
    llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                                "mettle-object-smoke: ");
    return 1;
  }
  return 0;
}
