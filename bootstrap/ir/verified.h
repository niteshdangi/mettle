#pragma once

#include "ir/ir.h"
#include <memory>
#include <vector>

namespace mettle::cleanup {
struct Plan;
}
namespace mettle::pipeline {
class Compiler;
}
namespace mettle::ir {
class VerifiedProgram {
public:
  VerifiedProgram(VerifiedProgram &&) noexcept;
  VerifiedProgram &operator=(VerifiedProgram &&) noexcept;
  ~VerifiedProgram();
  const Program &program() const { return value; }
  const std::vector<cleanup::Plan> &cleanupPlans() const { return *plans; }

private:
  friend class mettle::pipeline::Compiler;
  VerifiedProgram(Program program,
                  std::unique_ptr<const std::vector<cleanup::Plan>> plans);
  Program value;
  std::unique_ptr<const std::vector<cleanup::Plan>> plans;
};
} // namespace mettle::ir
