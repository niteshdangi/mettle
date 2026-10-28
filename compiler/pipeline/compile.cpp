#include "pipeline/compile.h"
#include "analysis/initialization.h"
#include "analysis/loans.h"
#include "ir/verify.h"
#include "lowering/scalar.h"
#include "semantics/check.h"
#include "syntax/parser.h"

namespace mettle::pipeline {
class Compiler {
public:
  static std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                                  Diagnostics &diagnostics) {
    if (!diagnostics.empty() || !ir::verify(program, diagnostics))
      return std::nullopt;
    analysis::initialization(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::loans(program, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    return ir::VerifiedProgram(std::move(program));
  }
  static std::optional<ir::VerifiedProgram> run(const Source &source,
                                                Diagnostics &diagnostics) {
    if (!diagnostics.empty())
      return std::nullopt;
    auto tree = parse(source, diagnostics);
    if (!diagnostics.empty())
      return std::nullopt;
    auto checked = check(std::move(tree), diagnostics);
    if (!checked)
      return std::nullopt;
    auto program = lowering::lower(*checked, diagnostics);
    return admit(std::move(program), diagnostics);
  }
};
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics) {
  return Compiler::admit(std::move(program), diagnostics);
}
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics) {
  return Compiler::run(source, diagnostics);
}
} // namespace mettle::pipeline
