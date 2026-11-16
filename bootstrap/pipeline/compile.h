#pragma once

#include "analysis/loans.h"
#include "diagnostics/diagnostics.h"
#include "ir/verified.h"
#include "resolution/load.h"
#include "semantics/checked.h"
#include "semantics/library.h"
#include "syntax/ast.h"
#include "types/target.h"
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>

namespace mettle::lowering {
struct ImportedBodies;
}

namespace mettle::pipeline {
using PackageOwners = std::map<SourceId, std::string>;
// Called once with the checked module, before lowering. The module is alive
// only for the call; observers collect facts and never alter the compilation.
using CheckedObserver = std::function<void(const CheckedModule &)>;
struct ImportedProgram {
  std::shared_ptr<const ImportedDeclarations> declarations;
  // Consumed by lowering, which moves the bodies into the program.
  std::shared_ptr<lowering::ImportedBodies> bodies;
  std::optional<ir::Program> metadata;
};
using LibraryImporter = std::function<std::optional<ImportedProgram>(
    const Module &, const resolution::Resolution &, Diagnostics &)>;
class Compiler;
class PreparedProgram {
public:
  PreparedProgram(PreparedProgram &&) = default;
  PreparedProgram &operator=(PreparedProgram &&) = default;
  const ir::Program &program() const { return declarations; }
  const interfaces::Database &interfaceDatabase() const {
    return *interfaceData;
  }

private:
  friend class Compiler;
  PreparedProgram(ir::Program program,
                  std::shared_ptr<const interfaces::Database> database,
                  analysis::LoanResults loans,
                  std::shared_ptr<lowering::ImportedBodies> importedBodies)
      : declarations(std::move(program)), interfaceData(std::move(database)),
        loans(std::move(loans)), importedBodies(std::move(importedBodies)) {}
  ir::Program declarations;
  std::shared_ptr<const interfaces::Database> interfaceData;
  analysis::LoanResults loans;
  std::shared_ptr<lowering::ImportedBodies> importedBodies;
};
std::optional<PreparedProgram>
prepare(Module module, Diagnostics &diagnostics, bool requireEntry = true,
        TargetFacts target = {}, const CheckedObserver &observe = {},
        const PackageOwners &packageOwners = {},
        NumericEvaluator numericEvaluator = nullptr,
        const resolution::SourcePackages &sourcePackages = {},
        const LibraryImporter &importLibrary = {});
std::optional<ir::VerifiedProgram> compile(const PreparedProgram &program,
                                           Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram>
compileWithLibraryObjects(const PreparedProgram &program,
                          Diagnostics &diagnostics);
// Every non-generic package-owned body, independent of the program's own code.
std::optional<ir::VerifiedProgram>
compileLibrary(const PreparedProgram &program, Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram>
compile(const std::vector<Source> &sources, Diagnostics &diagnostics,
        const resolution::Library &library = {});
std::optional<ir::VerifiedProgram>
compile(Module module, Diagnostics &diagnostics, bool requireEntry = true,
        TargetFacts target = {}, const CheckedObserver &observe = {},
        const PackageOwners &packageOwners = {},
        NumericEvaluator numericEvaluator = nullptr,
        const resolution::SourcePackages &sourcePackages = {});
} // namespace mettle::pipeline
