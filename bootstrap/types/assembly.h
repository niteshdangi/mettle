#pragma once

#include "types/target.h"

namespace mettle {
enum class AssemblyVariant { Inline, Global, Naked };
enum class AssemblyMode { In, Out, LateOut, InOut, InLateOut, Const, Sym };
bool assemblyInput(AssemblyMode mode);
bool assemblyOutput(AssemblyMode mode);
bool assemblyLate(AssemblyMode mode);
struct AssemblyOperand {
  AssemblyMode mode = AssemblyMode::In;
  std::string name{}, reg{};
  bool explicitRegister = false, discard = false;
  Type type = Type::Unknown;
  Type inputType = Type::Unknown;
  NumericLiteral constant{};
  Type constantIdentity = Type::Unknown;
  enum class SymbolKind { Function, Static };
  SymbolKind symbolKind = SymbolKind::Function;
  int symbol = -1;
  std::vector<Type> symbolArguments{};
  bool operator==(const AssemblyOperand &) const = default;
};
struct Assembly {
  AssemblyVariant variant = AssemblyVariant::Inline;
  std::vector<std::string> templates{};
  std::vector<AssemblyOperand> operands{};
  std::set<std::string> options{}, clobberAbis{};
  bool operator==(const Assembly &) const = default;
};
// Returns a source diagnostic, never defers ordinary constraint errors to LLVM.
std::optional<std::string>
validateAssembly(const TypeStore &types, const TargetFacts &target,
                 const std::set<std::string> &features,
                 const Assembly &assembly);
std::string canonicalRegister(TargetArch arch, std::string_view reg);
std::set<std::string> assemblyFeatures(const TargetFacts &target,
                                       const Assembly &assembly);
} // namespace mettle
