#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include "metadata/references.h"
#include "semantics/checked.h"
#include <functional>
#include <map>
#include <span>
#include <string>

namespace mettle::lowering {
struct ImportedBodies {
  TypeRecords<ir::Function, true> headers;
  std::shared_ptr<const std::vector<ir::FunctionIndex>> headerIndex =
      std::make_shared<const std::vector<ir::FunctionIndex>>();
  std::map<std::size_t, ir::Function> functions;
  std::vector<ir::Program::Static> statics;
  std::map<std::pair<std::size_t, std::size_t>, ir::Function> defaults;
  std::vector<ir::Function> support;
  std::vector<int> closureFunctions;
  std::vector<std::optional<std::size_t>> functionRecords;
  std::map<std::pair<std::size_t, std::size_t>, std::size_t> defaultRecords;
  std::vector<std::optional<std::size_t>> supportRecords;
  std::vector<std::size_t> functionBodySizes;
  std::function<std::optional<ir::Function>(std::size_t, const ir::Function &,
                                            std::string &)>
      loadFunction;
  std::function<std::span<const std::uint8_t>(std::size_t, std::string &)>
      loadSummary;
  metadata::DecodeReferences summaryReferences;
};
// Imported headers remain immutable; concrete bodies are loaded on demand.
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics,
                  std::shared_ptr<const ImportedBodies> imported = nullptr,
                  const std::map<std::size_t, ir::Function> *queries = nullptr);
void opaqueAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database,
                    Diagnostics &diagnostics);
// One dispatching function per erasable method of each `any` type in the
// program, selected when a generic `T: unsized + I` is instantiated with it.
void erasedAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database);
bool witnessSlots(ir::Instruction &instruction, const TypeStore &types,
                  Diagnostics &diagnostics);
} // namespace mettle::lowering
