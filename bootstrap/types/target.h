#pragma once

#include "types/type.h"
#include <set>

namespace mettle {
enum class TargetArch { Unknown, X86_64, Aarch64 };
enum class TargetSystem { Unknown, Linux, Darwin };
struct TargetFacts {
  TargetArch arch = TargetArch::Unknown;
  TargetSystem system = TargetSystem::Unknown;
  unsigned pointerBits = 0;
  bool littleEndian = true;
  std::string triple{};
  std::set<std::string> baseline{};
  bool initialProfile() const;
};
TargetFacts targetFacts(std::string_view triple);
bool recognizedFeature(TargetArch arch, std::string_view feature);
std::set<std::string> featureClosure(TargetArch arch,
                                     std::set<std::string> features);
bool featuresAvailable(const TargetFacts &target,
                       const std::set<std::string> &enabled,
                       const std::set<std::string> &required);
struct TargetVector {
  TargetArch arch;
  std::string name;
  Type element;
  unsigned lanes, alignment;
  std::string feature;
};
std::optional<TargetVector> targetVector(std::string_view name);
struct TargetOperation {
  enum class Kind {
    Splat,
    Set,
    Add,
    Sub,
    Mul,
    And,
    Or,
    Xor,
    Load,
    Store,
    Extract,
    Insert
  };
  std::string name, vector, feature;
  Kind kind;
  Type element;
  unsigned lanes, arguments;
  bool reverse = false;
};
std::optional<TargetOperation> targetOperation(std::string_view name);
bool nativeVector(const TypeStore &types, Type type);
} // namespace mettle
