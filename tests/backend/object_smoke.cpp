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
    llvm::errs()
        << "Usage: mettle-object-smoke output.o "
           "[target-triple|--invalid-module|--units|--indexed-stores]\n";
    return 2;
  }
  llvm::LLVMContext context;
  llvm::Module module("mettle-foundation-smoke", context);
  const bool indexed = argc == 3 && std::string(argv[2]) == "--indexed-stores";
  auto *i32 = llvm::Type::getInt32Ty(context);
  auto *type = indexed ? llvm::FunctionType::get(
                             llvm::Type::getInt64Ty(context), {i32}, false)
                       : llvm::FunctionType::get(i32, false);
  auto *function =
      llvm::Function::Create(type, llvm::Function::ExternalLinkage,
                             indexed ? "indexed_store_probe" : "main", module);
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
  } else if (indexed) {
    auto *word = builder.getInt64Ty();
    auto *pointer = builder.getPtrTy();
    auto *entry = builder.GetInsertBlock();
    auto *loop = llvm::BasicBlock::Create(context, "loop", function);
    auto *done = llvm::BasicBlock::Create(context, "done", function);
    auto *frame = builder.CreateAlloca(word, builder.getInt64(8));
    auto *lengthAddress =
        builder.CreateInBoundsGEP(word, frame, builder.getInt64(1));
    auto setup = module.getOrInsertFunction("init_indexed_store_frame",
                                            builder.getInt1Ty(), pointer,
                                            pointer, builder.getInt32Ty());
    auto *enter =
        builder.CreateCall(setup, {frame, lengthAddress, function->getArg(0)});
    builder.CreateCondBr(enter, loop, done);
    builder.SetInsertPoint(loop);
    auto *index = builder.CreatePHI(word, 2);
    index->addIncoming(builder.getInt64(0), entry);
    auto *data = builder.CreateLoad(pointer, frame);
    auto *element = builder.CreateInBoundsGEP(word, data, index);
    builder.CreateStore(builder.getInt64(1), element);
    auto *step = builder.CreateAdd(index, builder.getInt64(1));
    index->addIncoming(step, loop);
    auto *length = builder.CreateLoad(word, lengthAddress);
    builder.CreateCondBr(builder.CreateICmpULT(step, length), loop, done);
    builder.SetInsertPoint(done);
    auto *result = builder.CreatePHI(word, 2);
    result->addIncoming(builder.getInt64(0), entry);
    result->addIncoming(length, loop);
    builder.CreateRet(result);
  } else {
    builder.CreateRet(
        llvm::ConstantInt::get(llvm::Type::getInt32Ty(context), 37));
  }
  const auto triple = argc == 3 && !invalid && !units && !indexed
                          ? std::string(argv[2])
                          : llvm::sys::getDefaultTargetTriple();
  if (units) {
    std::vector<std::string> paths;
    auto error = mettle::backend::emitObjectUnits(
        module, triple, "smoke", true,
        [&](llvm::StringRef,
            mettle::backend::ObjectUnitKind) -> llvm::Expected<std::string> {
          paths.push_back(std::string(argv[1]) + "." +
                          std::to_string(paths.size()) + ".o");
          return paths.back();
        });
    std::vector<llvm::NewArchiveMember> members;
    for (const auto &path : paths) {
      if (error)
        break;
      auto member = llvm::NewArchiveMember::getFile(path, true);
      if (!member)
        error = member.takeError();
      else
        members.push_back(std::move(*member));
    }
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
  if (auto error =
          mettle::backend::emitObject(module, triple, argv[1], indexed)) {
    llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                                "mettle-object-smoke: ");
    return 1;
  }
  if (indexed) {
    for (const auto &block : *function)
      if (block.getName().ends_with(".disjoint"))
        return 0;
    llvm::errs() << "indexed store loop did not get a guarded fast path\n";
    function->print(llvm::errs());
    return 1;
  }
  return 0;
}
