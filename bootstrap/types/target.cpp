#include "types/target.h"
#include <algorithm>
#include <tuple>

namespace mettle {
bool TargetFacts::initialProfile() const {
  return pointerBits == 64 && littleEndian &&
         ((arch == TargetArch::X86_64 && system == TargetSystem::Linux) ||
          (arch == TargetArch::Aarch64 && system == TargetSystem::Darwin));
}
TargetFacts targetFacts(std::string_view triple) {
  TargetFacts facts;
  facts.triple = triple;
  if (triple.starts_with("x86_64-"))
    facts.arch = TargetArch::X86_64;
  else if (triple.starts_with("aarch64-") || triple.starts_with("arm64-"))
    facts.arch = TargetArch::Aarch64;
  if (triple.find("-linux") != std::string_view::npos)
    facts.system = TargetSystem::Linux;
  else if (triple.find("-darwin") != std::string_view::npos ||
           triple.find("-macos") != std::string_view::npos)
    facts.system = TargetSystem::Darwin;
  if (facts.arch != TargetArch::Unknown)
    facts.pointerBits = 64;
  if (facts.initialProfile())
    facts.baseline = facts.arch == TargetArch::X86_64
                         ? std::set<std::string>{"sse", "sse2"}
                         : std::set<std::string>{"neon"};
  return facts;
}
bool recognizedFeature(TargetArch arch, std::string_view feature) {
  static const std::set<std::string_view> x86{
      "sse",       "sse2",     "sse3",     "ssse3",    "sse4.1",
      "sse4.2",    "avx",      "avx2",     "fma",      "aes",
      "pclmulqdq", "popcnt",   "bmi1",     "bmi2",     "lzcnt",
      "avx512f",   "avx512bw", "avx512vl", "avx512dq", "avx512cd"};
  static const std::set<std::string_view> arm{"neon", "aes",  "sha2",    "crc",
                                              "lse",  "fp16", "dotprod", "rdm"};
  return arch == TargetArch::X86_64    ? x86.contains(feature)
         : arch == TargetArch::Aarch64 ? arm.contains(feature)
                                       : false;
}
std::set<std::string> featureClosure(TargetArch arch,
                                     std::set<std::string> features) {
  if (arch == TargetArch::X86_64) {
    bool changed;
    do {
      auto old = features.size();
      auto imply = [&](std::string_view feature, std::string_view dependency) {
        if (features.contains(std::string(feature)))
          features.insert(std::string(dependency));
      };
      for (auto feature : {"avx512bw", "avx512vl", "avx512dq", "avx512cd"})
        imply(feature, "avx512f");
      imply("avx512f", "avx2");
      imply("avx2", "avx");
      imply("fma", "avx");
      imply("avx", "sse4.2");
      imply("sse4.2", "sse4.1");
      imply("sse4.1", "ssse3");
      imply("ssse3", "sse3");
      imply("sse3", "sse2");
      imply("sse2", "sse");
      changed = old != features.size();
    } while (changed);
  }
  return features;
}
bool featuresAvailable(const TargetFacts &target,
                       const std::set<std::string> &enabled,
                       const std::set<std::string> &required) {
  auto available = enabled;
  available.insert(target.baseline.begin(), target.baseline.end());
  available = featureClosure(target.arch, std::move(available));
  return target.initialProfile() &&
         std::includes(available.begin(), available.end(), required.begin(),
                       required.end());
}
std::optional<TargetVector> targetVector(std::string_view name) {
  constexpr std::string_view x86 = "core::arch::x86_64::";
  constexpr std::string_view arm = "core::arch::aarch64::";
  auto result = [&](TargetArch arch, Type element, unsigned lanes,
                    unsigned alignment, std::string feature) {
    return TargetVector{arch,  std::string(name), element,
                        lanes, alignment,         std::move(feature)};
  };
  if (name.starts_with(x86)) {
    auto shortName = name.substr(x86.size());
    for (unsigned bits : {128u, 256u, 512u}) {
      auto prefix = "__m" + std::to_string(bits);
      auto feature = bits == 128 ? "sse" : bits == 256 ? "avx" : "avx512f";
      if (shortName == prefix)
        return result(TargetArch::X86_64, Type::F32, bits / 32, bits / 8,
                      feature);
      if (shortName == prefix + "d")
        return result(TargetArch::X86_64, Type::F64, bits / 64, bits / 8,
                      bits == 128 ? "sse2" : feature);
      if (shortName == prefix + "i")
        return result(TargetArch::X86_64, Type::I64, bits / 64, bits / 8,
                      bits == 128 ? "sse2" : feature);
    }
  } else if (name.starts_with(arm)) {
    auto shortName = name.substr(arm.size());
    for (auto [prefix, element, width] : {std::tuple{"int8", Type::I8, 8u},
                                          {"uint8", Type::U8, 8u},
                                          {"int16", Type::I16, 16u},
                                          {"uint16", Type::U16, 16u},
                                          {"int32", Type::I32, 32u},
                                          {"uint32", Type::U32, 32u},
                                          {"int64", Type::I64, 64u},
                                          {"uint64", Type::U64, 64u},
                                          {"float32", Type::F32, 32u},
                                          {"float64", Type::F64, 64u}}) {
      for (unsigned bits : {64u, 128u})
        if (shortName ==
            std::string(prefix) + "x" + std::to_string(bits / width) + "_t")
          return result(TargetArch::Aarch64, element, bits / width, bits / 8,
                        "neon");
    }
  }
  return std::nullopt;
}
bool nativeVector(const TypeStore &types, Type type) {
  return types.isProduct(type) &&
         types.product(type).kind == AggregateKind::NativeVector;
}
std::optional<TargetOperation> targetOperation(std::string_view name) {
  using K = TargetOperation::Kind;
  constexpr std::string_view x86 = "core::arch::x86_64::";
  constexpr std::string_view arm = "core::arch::aarch64::";
  if (name.starts_with(x86)) {
    auto shortName = name.substr(x86.size());
    for (unsigned bits : {128u, 256u}) {
      auto prefix = bits == 128 ? "_mm_" : "_mm256_";
      for (auto [suffix, element, width, vectorSuffix] :
           {std::tuple{"epi8", Type::I8, 8u, "i"},
            {"epi16", Type::I16, 16u, "i"},
            {"epi32", Type::I32, 32u, "i"},
            {"epi64", Type::I64, 64u, "i"},
            {"ps", Type::F32, 32u, ""},
            {"pd", Type::F64, 64u, "d"}}) {
        for (auto [operation, kind, arguments] :
             {std::tuple{"set1_", K::Splat, 1u},
              {"set_", K::Set, bits / width},
              {"add_", K::Add, 2u},
              {"sub_", K::Sub, 2u},
              {"mul_", K::Mul, 2u}}) {
          auto spelling =
              std::string(prefix) + operation + suffix +
              (element == Type::I64 && (kind == K::Set || kind == K::Splat)
                   ? "x"
                   : "");
          if (shortName != spelling)
            continue;
          if (kind == K::Mul && !isFloating(element))
            continue;
          return TargetOperation{
              std::string(name),
              std::string(x86) + "__m" + std::to_string(bits) + vectorSuffix,
              bits == 256
                  ? (isInteger(element) && kind != K::Set && kind != K::Splat
                         ? "avx2"
                         : "avx")
              : element == Type::F32 ? "sse"
                                     : "sse2",
              kind,
              element,
              bits / width,
              arguments,
              kind == K::Set};
        }
      }
      for (auto [operation, kind] : {std::pair{"and_", K::And},
                                     {"or_", K::Or},
                                     {"xor_", K::Xor},
                                     {"loadu_", K::Load},
                                     {"storeu_", K::Store}}) {
        auto suffix = "si" + std::to_string(bits);
        if (shortName == std::string(prefix) + operation + suffix)
          return TargetOperation{std::string(name),
                                 std::string(x86) + "__m" +
                                     std::to_string(bits) + "i",
                                 bits == 128                           ? "sse2"
                                 : kind == K::Load || kind == K::Store ? "avx"
                                                                       : "avx2",
                                 kind,
                                 Type::I64,
                                 bits / 64,
                                 kind == K::Load ? 1u : 2u};
      }
    }
  } else if (name.starts_with(arm)) {
    auto shortName = name.substr(arm.size());
    for (auto [suffix, vectorPrefix, element, width] :
         {std::tuple{"s8", "int8", Type::I8, 8u},
          {"u8", "uint8", Type::U8, 8u},
          {"s16", "int16", Type::I16, 16u},
          {"u16", "uint16", Type::U16, 16u},
          {"s32", "int32", Type::I32, 32u},
          {"u32", "uint32", Type::U32, 32u},
          {"s64", "int64", Type::I64, 64u},
          {"u64", "uint64", Type::U64, 64u},
          {"f32", "float32", Type::F32, 32u},
          {"f64", "float64", Type::F64, 64u}}) {
      for (unsigned bits : {64u, 128u}) {
        auto q = bits == 128 ? "q" : "";
        for (auto [operation, kind, arguments] :
             {std::tuple{"vdup", K::Splat, 1u},
              {"vadd", K::Add, 2u},
              {"vsub", K::Sub, 2u},
              {"vmul", K::Mul, 2u},
              {"vand", K::And, 2u},
              {"vorr", K::Or, 2u},
              {"veor", K::Xor, 2u},
              {"vld1", K::Load, 1u},
              {"vst1", K::Store, 2u},
              {"vget", K::Extract, 2u},
              {"vset", K::Insert, 3u}}) {
          auto spelling = std::string(operation) + q +
                          (kind == K::Splat                          ? "_n_"
                           : kind == K::Extract || kind == K::Insert ? "_lane_"
                                                                     : "_") +
                          suffix;
          if (shortName != spelling ||
              ((kind == K::And || kind == K::Or || kind == K::Xor) &&
               isFloating(element)) ||
              (kind == K::Mul && isInteger(element) && width == 64))
            continue;
          return TargetOperation{std::string(name),
                                 std::string(arm) + vectorPrefix + "x" +
                                     std::to_string(bits / width) + "_t",
                                 "neon",
                                 kind,
                                 element,
                                 bits / width,
                                 arguments};
        }
      }
    }
  }
  return std::nullopt;
}
} // namespace mettle
