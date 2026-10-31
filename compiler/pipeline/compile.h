#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/verified.h"
#include "resolution/load.h"
#include "semantics/checked.h"
#include "syntax/ast.h"
#include "types/target.h"
#include <functional>
#include <map>
#include <optional>
#include <string>

namespace mettle::pipeline {
using PackageOwners = std::map<SourceId, std::string>;
// Called once with the checked module, before lowering. The module is alive
// only for the call; observers collect facts and never alter the compilation.
using CheckedObserver = std::function<void(const CheckedModule &)>;
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
        const PackageOwners &packageOwners = {});
} // namespace mettle::pipeline
