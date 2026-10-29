#include "types/assembly.h"
#include <algorithm>
#include <charconv>
#include <functional>
#include <map>

namespace mettle {
bool assemblyInput(AssemblyMode mode) {
  return mode == AssemblyMode::In || mode == AssemblyMode::InOut ||
         mode == AssemblyMode::InLateOut;
}
bool assemblyOutput(AssemblyMode mode) {
  return mode == AssemblyMode::Out || mode == AssemblyMode::LateOut ||
         mode == AssemblyMode::InOut || mode == AssemblyMode::InLateOut;
}
bool assemblyLate(AssemblyMode mode) {
  return mode == AssemblyMode::LateOut || mode == AssemblyMode::InLateOut;
}
namespace {
std::optional<unsigned> numbered(std::string_view text, std::string_view prefix,
                                 unsigned limit) {
  if (!text.starts_with(prefix))
    return std::nullopt;
  auto suffix = text.substr(prefix.size());
  unsigned value = 0;
  auto parsed =
      std::from_chars(suffix.data(), suffix.data() + suffix.size(), value);
  if (parsed.ec != std::errc{} || parsed.ptr != suffix.data() + suffix.size() ||
      value >= limit || suffix != std::to_string(value))
    return std::nullopt;
  return value;
}
} // namespace
std::string canonicalRegister(TargetArch arch, std::string_view reg) {
  if (arch == TargetArch::X86_64) {
    for (auto [canonical, aliases] :
         {std::pair{"rax",
                    std::set<std::string_view>{"rax", "eax", "ax", "al", "ah"}},
          {"rbx", {"rbx", "ebx", "bx", "bl", "bh"}},
          {"rcx", {"rcx", "ecx", "cx", "cl", "ch"}},
          {"rdx", {"rdx", "edx", "dx", "dl", "dh"}},
          {"rsi", {"rsi", "esi", "si", "sil"}},
          {"rdi", {"rdi", "edi", "di", "dil"}},
          {"rbp", {"rbp", "ebp", "bp", "bpl"}},
          {"rsp", {"rsp", "esp", "sp", "spl"}},
          {"rip", {"rip", "eip", "ip"}}})
      if (aliases.contains(reg))
        return canonical;
    for (unsigned i = 8; i < 16; ++i) {
      auto name = "r" + std::to_string(i);
      if (reg == name || reg == name + "b" || reg == name + "w" ||
          reg == name + "d")
        return name;
    }
    for (auto prefix : {"xmm", "ymm", "zmm"})
      if (auto index = numbered(reg, prefix, 32))
        return "v" + std::to_string(*index);
    if (numbered(reg, "k", 8) || numbered(reg, "mm", 8) ||
        numbered(reg, "tmm", 8))
      return std::string(reg);
    for (unsigned i = 0; i < 8; ++i)
      if (reg == "st(" + std::to_string(i) + ")")
        return std::string(reg);
  } else if (arch == TargetArch::Aarch64) {
    if (reg == "fp")
      return "x29";
    if (reg == "lr")
      return "x30";
    for (auto prefix : {"x", "w"})
      if (auto index = numbered(reg, prefix, 31))
        return "x" + std::to_string(*index);
    for (auto prefix : {"v", "b", "h", "s", "d", "q"})
      if (auto index = numbered(reg, prefix, 32))
        return "v" + std::to_string(*index);
    if (reg == "sp" || reg == "wsp" || reg == "xzr" || reg == "wzr")
      return "reserved";
    if (numbered(reg, "p", 16) || reg == "ffr")
      return std::string(reg);
  }
  return {};
}
std::optional<std::string>
validateAssembly(const TypeStore &types, const TargetFacts &target,
                 const std::set<std::string> &features,
                 const Assembly &assembly) {
  if (!target.initialProfile())
    return "unsupported assembly target; initial profiles are Linux x86-64 "
           "and Darwin ARM64";
  if (assembly.templates.empty())
    return "assembly requires at least one template";
  bool inlineAsm = assembly.variant == AssemblyVariant::Inline;
  auto option = [&](std::string_view name) {
    return assembly.options.contains(std::string(name));
  };
  for (const auto &name : assembly.options) {
    if (name != "nomem" && name != "readonly" && name != "preserves_flags" &&
        name != "nostack" && name != "noreturn" && name != "pure" &&
        name != "raw" && name != "att_syntax")
      return "unknown or unsupported assembly option '" + name + "'";
    if (!inlineAsm && name != "raw" && name != "att_syntax")
      return "global/naked assembly accepts only raw and target syntax options";
  }
  if (option("att_syntax") && target.arch != TargetArch::X86_64)
    return "att_syntax is only available on x86-64";
  if (option("nomem") && option("readonly"))
    return "nomem and readonly cannot be combined";
  if (option("pure") &&
      ((!option("nomem") && !option("readonly")) || option("noreturn")))
    return "pure requires nomem or readonly and cannot combine with noreturn";
  if (!inlineAsm && !assembly.clobberAbis.empty())
    return "global/naked assembly cannot declare clobber_abi";
  for (const auto &abi : assembly.clobberAbis)
    if (abi != "C" && abi != "system" &&
        !(target.arch == TargetArch::X86_64 && abi == "sysv64"))
      return "unsupported assembly clobber ABI '" + abi + "'";
  std::map<std::string, std::vector<const AssemblyOperand *>> registers;
  struct Allocation {
    std::vector<std::string> candidates;
    bool before, after;
  };
  std::vector<Allocation> allocations;
  std::set<std::string> names;
  bool observable = false;
  for (const auto &operand : assembly.operands) {
    if (!operand.name.empty() && !names.insert(operand.name).second)
      return "duplicate assembly operand name";
    if (operand.mode == AssemblyMode::Const) {
      if (!isInteger(operand.type) ||
          !integerLiteralFits(operand.constant, operand.type))
        return "assembly const requires an integer constant";
      continue;
    }
    if (operand.mode == AssemblyMode::Sym) {
      if (operand.symbol < 0)
        return "assembly sym requires a resolved function or static symbol";
      continue;
    }
    if (!inlineAsm)
      return "global/naked assembly permits only const and sym operands";
    if (option("noreturn") && assemblyOutput(operand.mode))
      return "noreturn assembly cannot have outputs";
    observable |= assemblyOutput(operand.mode) && !operand.discard;
    if (!assembly.clobberAbis.empty() && assemblyOutput(operand.mode) &&
        !operand.explicitRegister)
      return "clobber_abi requires explicit output registers";
    auto reg = operand.reg;
    std::string feature;
    bool clobberOnly = false;
    if (operand.explicitRegister) {
      auto canonical = canonicalRegister(target.arch, reg);
      if (canonical.empty())
        return "unknown assembly register '" + reg + "'";
      if (canonical == "reserved" || canonical == "rbx" || canonical == "rbp" ||
          canonical == "rsp" || canonical == "rip" || canonical == "x18" ||
          canonical == "x19" || canonical == "x29")
        return "reserved assembly register '" + reg + "'";
      auto &others = registers[canonical];
      for (const auto *other : others) {
        bool share = (operand.mode == AssemblyMode::In &&
                      other->mode == AssemblyMode::LateOut) ||
                     (operand.mode == AssemblyMode::LateOut &&
                      other->mode == AssemblyMode::In);
        if (!share)
          return "conflicting assembly registers '" + reg + "' and '" +
                 other->reg + "'";
      }
      others.push_back(&operand);
      if (target.arch == TargetArch::X86_64) {
        if (reg.starts_with("xmm"))
          reg = "xmm_reg";
        else if (reg.starts_with("ymm"))
          reg = "ymm_reg";
        else if (reg.starts_with("zmm"))
          reg = "zmm_reg";
        else if (reg.starts_with("k"))
          reg = reg == "k0" ? "kreg0" : "kreg";
        else if (reg.starts_with("mm"))
          reg = "mmx_reg";
        else if (reg.starts_with("st("))
          reg = "x87_reg";
        else if (reg.starts_with("tmm"))
          reg = "tmm_reg";
        else
          reg = operand.reg.ends_with("l") || operand.reg.ends_with("h") ||
                        (operand.reg.starts_with("r") &&
                         operand.reg.ends_with("b"))
                    ? "reg_byte"
                    : "reg";
        if (canonical.starts_with("v") &&
            numbered(canonical, "v", 32).value_or(0) >= 16)
          feature = "avx512f";
        if ((operand.reg == "ah" || operand.reg == "bh" ||
             operand.reg == "ch" || operand.reg == "dh") &&
            assemblyInput(operand.mode))
          return "high-byte explicit input registers are unsupported; use "
                 "reg_abcd with the h modifier";
      } else
        reg = canonical.starts_with("v")                         ? "vreg"
              : canonical.starts_with("p") || canonical == "ffr" ? "preg"
                                                                 : "reg";
    }
    unsigned width = isInteger(operand.type)     ? integerWidth(operand.type)
                     : operand.type == Type::F32 ? 32
                     : operand.type == Type::F64 ? 64
                                                 : 0;
    bool vector = nativeVector(types, operand.type);
    if (vector) {
      const auto &shape = *types.product(operand.type).vector;
      width = (isInteger(shape.element)     ? integerWidth(shape.element)
               : shape.element == Type::F32 ? 32
                                            : 64) *
              shape.lanes;
    }
    bool pointer =
        (types.isPointer(operand.type) &&
         types.pointerMetadata(types.pointer(operand.type).payload) ==
             PointerMetadata::None) ||
        types.isFunctionPointer(operand.type);
    if (pointer)
      width = target.pointerBits;
    bool allowed = false;
    if (target.arch == TargetArch::X86_64) {
      if (reg == "reg" || reg == "reg_abcd")
        allowed = !vector && (width == 16 || width == 32 || width == 64);
      else if (reg == "reg_byte")
        allowed = isInteger(operand.type) && width == 8;
      else if (reg == "xmm_reg" || reg == "ymm_reg" || reg == "zmm_reg") {
        auto capacity = reg == "xmm_reg"   ? 128u
                        : reg == "ymm_reg" ? 256u
                                           : 512u;
        allowed = width >= 32 && width <= capacity;
        if (feature.empty())
          feature = reg == "xmm_reg"   ? "sse"
                    : reg == "ymm_reg" ? "avx"
                                       : "avx512f";
      } else if (reg == "kreg") {
        allowed = isInteger(operand.type) && width <= 64;
        feature = width <= 16 ? "avx512f" : "avx512bw";
      } else if (reg == "kreg0" || reg == "x87_reg" || reg == "mmx_reg" ||
                 reg == "tmm_reg") {
        if (!operand.explicitRegister)
          return "clobber-only classes require an explicit register";
        clobberOnly = true;
      } else
        return "unknown assembly register class '" + reg + "'";
    } else {
      if (reg == "reg")
        allowed = !vector && width >= 8 && width <= 64;
      else if (reg == "vreg" || reg == "vreg_low16") {
        allowed = width >= 8 && (vector ? width <= 128 : width <= 64);
        feature = "neon";
      } else if (reg == "preg") {
        if (!operand.explicitRegister)
          return "clobber-only classes require an explicit register";
        clobberOnly = true;
      } else
        return "unknown assembly register class '" + reg + "'";
    }
    bool discarded = operand.discard && assemblyOutput(operand.mode) &&
                     !assemblyInput(operand.mode);
    if (clobberOnly && !discarded)
      return "this register supports only discarded output clobbers";
    if (!clobberOnly && !discarded && !allowed)
      return "assembly operand type does not match register class '" + reg +
             "'";
    if (!feature.empty() && (!discarded || !operand.explicitRegister) &&
        !featuresAvailable(target, features, {feature}))
      return "unsupported assembly register: required feature '" + feature +
             "'";
    if (!discarded && !types.isCopy(operand.type))
      return "assembly operands must be Copy register values";
    if (assemblyInput(operand.mode)) {
      auto registerWidth = [&](Type type) {
        return isInteger(type) ? integerWidth(type)
               : (types.isPointer(type) &&
                  types.pointerMetadata(types.pointer(type).payload) ==
                      PointerMetadata::None) ||
                       types.isFunctionPointer(type)
                   ? target.pointerBits
                   : 0u;
      };
      if (!types.isCopy(operand.inputType) ||
          (operand.inputType != operand.type &&
           (!registerWidth(operand.inputType) ||
            registerWidth(operand.inputType) != registerWidth(operand.type))))
        return "inout input/output register types are incompatible";
    }
    if (!clobberOnly) {
      Allocation request{
          {},
          assemblyInput(operand.mode) ||
              (assemblyOutput(operand.mode) && !assemblyLate(operand.mode)),
          assemblyOutput(operand.mode)};
      if (operand.explicitRegister)
        request.candidates.push_back(
            canonicalRegister(target.arch, operand.reg));
      else if (target.arch == TargetArch::X86_64) {
        if (reg == "reg" || reg == "reg_abcd" || reg == "reg_byte") {
          request.candidates = {"rax", "rbx", "rcx", "rdx"};
          if (reg != "reg_abcd") {
            for (auto name : {"rsi", "rdi", "rbp"})
              request.candidates.emplace_back(name);
            for (unsigned i = 8; i < 16; ++i)
              request.candidates.push_back("r" + std::to_string(i));
          }
        } else if (reg == "kreg") {
          for (unsigned i = 1; i < 8; ++i)
            request.candidates.push_back("k" + std::to_string(i));
        } else
          for (unsigned i = 0; i < (reg == "zmm_reg" ? 32u : 16u); ++i)
            request.candidates.push_back("v" + std::to_string(i));
      } else {
        auto count = reg == "reg" ? 31u : reg == "vreg_low16" ? 16u : 32u;
        for (unsigned i = 0; i < count; ++i)
          if (reg != "reg" || i != 18)
            request.candidates.push_back((reg == "reg" ? "x" : "v") +
                                         std::to_string(i));
      }
      allocations.push_back(std::move(request));
    }
  }
  // Match each simultaneous phase against the compiler-owned inventory. Late
  // outputs can reuse consumed inputs; early outputs cannot. LLVM may reserve
  // additional frame registers, but impossible user requests are rejected here.
  for (bool before : {true, false}) {
    std::map<std::string, std::size_t> assigned;
    std::function<bool(std::size_t, std::set<std::string> &)> assign =
        [&](std::size_t request, std::set<std::string> &visited) {
          for (const auto &reg : allocations[request].candidates) {
            if (!visited.insert(reg).second)
              continue;
            auto prior = assigned.find(reg);
            if (prior == assigned.end() || assign(prior->second, visited)) {
              assigned[reg] = request;
              return true;
            }
          }
          return false;
        };
    for (std::size_t i = 0; i < allocations.size(); ++i)
      if (before ? allocations[i].before : allocations[i].after) {
        std::set<std::string> visited;
        if (!assign(i, visited))
          return "assembly operands exceed the available register inventory";
      }
  }
  if (option("pure") && !observable)
    return "pure assembly requires an observable output";
  for (const auto &text : assembly.templates)
    if (text.find('\0') != std::string::npos)
      return "assembly template contains NUL";
  if (!option("raw")) {
    std::vector<bool> used(assembly.operands.size());
    std::size_t implicit = 0;
    for (const auto &text : assembly.templates) {
      if (text.find('\0') != std::string::npos)
        return "assembly template contains NUL";
      for (std::size_t i = 0; i < text.size(); ++i) {
        if ((text[i] == '{' || text[i] == '}') && i + 1 < text.size() &&
            text[i + 1] == text[i]) {
          ++i;
          continue;
        }
        if (text[i] == '}')
          return "unmatched assembly template brace";
        if (text[i] != '{')
          continue;
        auto end = text.find('}', i + 1);
        if (end == std::string::npos)
          return "unterminated assembly operand placeholder";
        auto placeholder = text.substr(i + 1, end - i - 1);
        auto colon = placeholder.find(':');
        auto name = placeholder.substr(0, colon);
        std::size_t index = assembly.operands.size();
        if (name.empty())
          index = implicit++;
        else {
          auto parsed =
              std::from_chars(name.data(), name.data() + name.size(), index);
          if (parsed.ec != std::errc{} ||
              parsed.ptr != name.data() + name.size())
            for (std::size_t n = 0; n < assembly.operands.size(); ++n)
              if (assembly.operands[n].name == name)
                index = n;
        }
        if (index >= assembly.operands.size())
          return "unknown assembly template operand '" + name + "'";
        const auto &operand = assembly.operands[index];
        if (operand.explicitRegister)
          return "explicit registers cannot appear in template placeholders";
        if (colon != std::string::npos) {
          auto modifier = placeholder.substr(colon + 1);
          std::string allowed;
          if (target.arch == TargetArch::X86_64) {
            if (operand.reg == "reg")
              allowed = "lxer";
            else if (operand.reg == "reg_abcd")
              allowed = "lhxer";
            else if (operand.reg == "xmm_reg" || operand.reg == "ymm_reg" ||
                     operand.reg == "zmm_reg")
              allowed = "xyz";
          } else if (operand.reg == "reg")
            allowed = "wx";
          else if (operand.reg == "vreg" || operand.reg == "vreg_low16")
            allowed = "bhsdqv";
          if (modifier.size() != 1 ||
              allowed.find(modifier) == std::string::npos)
            return "invalid assembly register template modifier";
        }
        used[index] = true;
        i = end;
      }
    }
    for (std::size_t i = 0; i < used.size(); ++i)
      if (!used[i] && !assembly.operands[i].explicitRegister)
        return "unused assembly operand";
  }
  return std::nullopt;
}
std::set<std::string> assemblyFeatures(const TargetFacts &target,
                                       const Assembly &assembly) {
  std::set<std::string> result;
  for (const auto &operand : assembly.operands) {
    if (operand.mode == AssemblyMode::Const ||
        operand.mode == AssemblyMode::Sym ||
        (operand.explicitRegister && operand.discard &&
         !assemblyInput(operand.mode)))
      continue;
    auto reg = std::string_view(operand.reg);
    if (target.arch == TargetArch::Aarch64) {
      if (reg == "vreg" || reg == "vreg_low16" ||
          (operand.explicitRegister &&
           canonicalRegister(target.arch, reg).starts_with("v")))
        result.insert("neon");
      continue;
    }
    if (reg == "xmm_reg" || reg.starts_with("xmm"))
      result.insert("sse");
    else if (reg == "ymm_reg" || reg.starts_with("ymm"))
      result.insert("avx");
    else if (reg == "zmm_reg" || reg.starts_with("zmm"))
      result.insert("avx512f");
    else if (reg == "kreg" || reg.starts_with("k"))
      result.insert(integerWidth(operand.type) <= 16 ? "avx512f" : "avx512bw");
    if (operand.explicitRegister) {
      auto canonical = canonicalRegister(target.arch, reg);
      if (canonical.starts_with("v") &&
          numbered(canonical, "v", 32).value_or(0) >= 16)
        result.insert("avx512f");
    }
  }
  return result;
}
} // namespace mettle
