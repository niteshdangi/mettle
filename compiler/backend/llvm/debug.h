#pragma once

#include "ir/ir.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"
#include <functional>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

namespace mettle::backend {
// What the backend needs to describe source positions: every source a span
// may name and the directory recorded as the compilation directory.
struct DebugInfoRequest {
  const std::vector<Source> &sources;
  std::string directory;
  std::function<Span(Span)> sourceSpan;
};

// Source-level DWARF for one module. It owns the DIBuilder, maps spans to
// line/column locations and describes local variables and their types from
// compiler-owned layouts. Each source function gets a subprogram for its body
// callback (the code the user wrote) and an artificial one for the frame
// wrapper that owns the locals.
class DebugInfo {
public:
  DebugInfo(llvm::Module &module, const ir::Program &program,
            const DebugInfoRequest &request);
  llvm::DISubprogram *attach(llvm::Function &function,
                             const ir::Function &source, bool artificial);
  // Makes `subprogram` the scope of the following locations. Statement
  // functions follow spans; the others stay at line 0.
  void begin(llvm::IRBuilder<> &builder, llvm::DISubprogram *subprogram,
             bool statements);
  void locate(llvm::IRBuilder<> &builder, Span span);
  void clear(llvm::IRBuilder<> &builder);
  // Declares a named local whose storage address is `storage`. A borrowed
  // local's storage holds a pointer to the value.
  void declare(llvm::IRBuilder<> &builder, const ir::Local &local,
               unsigned argument, bool borrowed, llvm::Value *storage);
  // Resolves types, drops locations that do not belong to the function that
  // carries them and gives every call a location.
  void finalize();

private:
  struct SourceInfo {
    const Source *source = nullptr;
    llvm::DIFile *file = nullptr;
    std::vector<std::size_t> lines;
  };
  llvm::Module &module;
  const ir::Program &program;
  const DebugInfoRequest &request;
  llvm::DIBuilder dib;
  llvm::DICompileUnit *unit = nullptr;
  llvm::DIFile *rootFile = nullptr;
  llvm::DISubroutineType *subroutine = nullptr;
  std::unordered_map<SourceId, SourceInfo> infos;
  std::map<std::pair<llvm::DISubprogram *, SourceId>, llvm::DIScope *> scopes;
  std::unordered_map<std::uint32_t, llvm::DIType *> types;
  std::set<std::uint32_t> building;
  llvm::DISubprogram *current = nullptr;
  llvm::DILocation *last = nullptr;
  bool following = false;

  SourceInfo *info(SourceId id);
  llvm::DILocation *location(Span span);
  llvm::DIType *describe(Type type);
  llvm::DIType *build(Type type);
};
} // namespace mettle::backend
