#pragma once

#include "ir/ir.h"
#include <utility>

namespace mettle::pipeline {
class Compiler;
}
namespace mettle::ir {
class VerifiedProgram {
public:
  VerifiedProgram(VerifiedProgram &&) = default;
  VerifiedProgram &operator=(VerifiedProgram &&) = default;
  const Program &program() const { return value; }

private:
  friend class mettle::pipeline::Compiler;
  explicit VerifiedProgram(Program program) : value(std::move(program)) {}
  Program value;
};
} // namespace mettle::ir
