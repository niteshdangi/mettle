#pragma once

#include "analysis/loans.h"
#include "diagnostics/diagnostics.h"
#include "ir/verified.h"
#include "ir/verify.h"
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
namespace mettle::instances {
class Queries;
}

namespace mettle::pipeline {
using PackageOwners = std::map<SourceId, std::string>;
// Called once with the checked module, before lowering. The module is alive
// only for the call; observers collect facts and never alter the compilation.
using CheckedObserver = std::function<void(const CheckedModule &)>;
struct ImportedProgram {
  std::shared_ptr<const ImportedDeclarations> declarations;
  std::shared_ptr<const lowering::ImportedBodies> bodies;
  std::optional<ir::Program> metadata;
};
using LibraryImporter = std::function<std::optional<ImportedProgram>(
    const Module &, const resolution::Resolution &, Diagnostics &)>;
class Compiler;
class FunctionQueries {
public:
  std::size_t hits() const { return reused; }
  std::size_t specializationHits() const;

private:
  friend class Compiler;
  struct State {
    DeclarationQueryInputs inputs;
    std::shared_ptr<const ImportedDeclarations> native, declarations;
    std::map<std::size_t, ir::Function> functions;
    std::map<std::size_t, std::vector<std::size_t>> dependencies;
    TargetFacts target;
    NumericEvaluator numericEvaluator = nullptr;
    resolution::SourcePackages packages;
    bool requireEntry = true;
    std::shared_ptr<instances::Queries> instances;
    ir::TypeVerificationCache typeVerification;
  };
  std::optional<State> state;
  std::size_t reused = 0;
  std::size_t specialized = 0;
};
class PreparedProgram {
public:
  PreparedProgram(PreparedProgram &&) = default;
  PreparedProgram &operator=(PreparedProgram &&) = default;
  const ir::Program &program() const { return declarations; }
  const interfaces::Database &interfaceDatabase() const {
    return *interfaceData;
  }
  const analysis::LoanResults &loanResults() const { return loans; }

private:
  friend class Compiler;
  PreparedProgram(
      ir::Program program, std::shared_ptr<const interfaces::Database> database,
      analysis::LoanResults loans,
      std::shared_ptr<const lowering::ImportedBodies> importedBodies,
      std::shared_ptr<instances::Queries> instances)
      : declarations(std::move(program)), interfaceData(std::move(database)),
        loans(std::move(loans)), importedBodies(std::move(importedBodies)),
        instances(std::move(instances)) {}
  ir::Program declarations;
  std::shared_ptr<const interfaces::Database> interfaceData;
  analysis::LoanResults loans;
  std::shared_ptr<const lowering::ImportedBodies> importedBodies;
  std::shared_ptr<instances::Queries> instances;
};
std::optional<PreparedProgram>
prepare(Module module, Diagnostics &diagnostics, bool requireEntry = true,
        TargetFacts target = {}, const CheckedObserver &observe = {},
        const PackageOwners &packageOwners = {},
        NumericEvaluator numericEvaluator = nullptr,
        const resolution::SourcePackages &sourcePackages = {},
        const LibraryImporter &importLibrary = {},
        FunctionQueries *queries = nullptr);
std::optional<ir::VerifiedProgram> compile(const PreparedProgram &program,
                                           Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram>
compileWithLibraryObjects(const PreparedProgram &program,
                          Diagnostics &diagnostics, bool optimize);
// Every non-generic package-owned body, independent of the program's own code.
std::optional<ir::VerifiedProgram>
compileLibrary(const PreparedProgram &program, Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram>
compileLibrary(const PreparedProgram &program, Diagnostics &diagnostics,
               const ir::Program &consumer);
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
