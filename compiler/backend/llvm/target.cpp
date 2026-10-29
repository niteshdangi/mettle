#include "backend/llvm/target.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/Mangler.h"
#include "llvm/Support/ModRef.h"
#include "llvm/Transforms/Utils/ModuleUtils.h"
#include <charconv>

namespace mettle::backend {
void targetAttributes(llvm::Function &function, const TargetFacts &target,
                      const std::set<std::string> &features) {
  auto enabled = features;
  enabled.insert(target.baseline.begin(), target.baseline.end());
  enabled = featureClosure(target.arch, std::move(enabled));
  std::string attributes;
  for (const auto &feature : enabled) {
    if (!attributes.empty())
      attributes += ',';
    attributes += "+" + (feature == "bmi1" ? std::string("bmi") : feature);
  }
  if (!attributes.empty())
    function.addFnAttr("target-features", attributes);
  if (target.arch == TargetArch::X86_64)
    function.addFnAttr("target-cpu", "x86-64");
  else if (target.arch == TargetArch::Aarch64)
    function.addFnAttr("target-cpu", "generic");
}
static llvm::Value *
emitTargetOperation(LoweringContext &context,
                    const ir::Instruction &instruction,
                    llvm::ArrayRef<llvm::Value *> operands) {
  const auto operation = *mettle::targetOperation(instruction.text);
  auto &builder = context.builder;
  auto *shape = llvm::FixedVectorType::get(context.type(operation.element),
                                           operation.lanes);
  auto vectorType = instruction.typeArguments[0];
  auto cast = [&](llvm::Value *value) {
    return builder.CreateBitCast(value, shape);
  };
  llvm::Value *result = nullptr;
  using K = TargetOperation::Kind;
  switch (operation.kind) {
  case K::Splat:
    result = builder.CreateVectorSplat(operation.lanes, operands[0]);
    break;
  case K::Set:
    result = llvm::UndefValue::get(shape);
    for (unsigned i = 0; i < operands.size(); ++i)
      result = builder.CreateInsertElement(
          result, operands[i],
          builder.getInt32(operation.reverse ? operation.lanes - 1 - i : i));
    break;
  case K::Add:
    result = isFloating(operation.element)
                 ? builder.CreateFAdd(cast(operands[0]), cast(operands[1]))
                 : builder.CreateAdd(cast(operands[0]), cast(operands[1]));
    break;
  case K::Sub:
    result = isFloating(operation.element)
                 ? builder.CreateFSub(cast(operands[0]), cast(operands[1]))
                 : builder.CreateSub(cast(operands[0]), cast(operands[1]));
    break;
  case K::Mul:
    result = isFloating(operation.element)
                 ? builder.CreateFMul(cast(operands[0]), cast(operands[1]))
                 : builder.CreateMul(cast(operands[0]), cast(operands[1]));
    break;
  case K::And:
    result = builder.CreateAnd(cast(operands[0]), cast(operands[1]));
    break;
  case K::Or:
    result = builder.CreateOr(cast(operands[0]), cast(operands[1]));
    break;
  case K::Xor:
    result = builder.CreateXor(cast(operands[0]), cast(operands[1]));
    break;
  case K::Load:
    result = builder.CreateAlignedLoad(shape, operands[0], llvm::Align(1));
    break;
  case K::Store:
    builder.CreateAlignedStore(cast(operands[1]), operands[0], llvm::Align(1));
    return llvm::UndefValue::get(context.type(Type::Unit));
  case K::Extract:
    return builder.CreateExtractElement(cast(operands[0]), operands[1]);
  case K::Insert:
    result = builder.CreateInsertElement(cast(operands[1]), operands[0],
                                         operands[2]);
    break;
  }
  return builder.CreateBitCast(result, context.type(vectorType));
}
llvm::Value *targetOperation(LoweringContext &context,
                             const ir::Instruction &instruction,
                             llvm::ArrayRef<llvm::Value *> operands) {
  const auto operation = *mettle::targetOperation(instruction.text);
  auto &builder = context.builder;
  auto name = "mettle.target." + instruction.text;
  auto *helper = context.module.getFunction(name);
  if (!helper) {
    std::vector<llvm::Type *> parameters(operands.size() + 1,
                                         builder.getPtrTy());
    helper = llvm::Function::Create(
        llvm::FunctionType::get(builder.getVoidTy(), parameters, false),
        llvm::GlobalValue::InternalLinkage, name, context.module);
    targetAttributes(*helper, context.program.target, {operation.feature});
    helper->addFnAttr(llvm::Attribute::NoUnwind);
    helper->addFnAttr(
        context.program.target.baseline.contains(operation.feature)
            ? llvm::Attribute::AlwaysInline
            : llvm::Attribute::NoInline);
    auto saved = builder.saveIP();
    builder.SetInsertPoint(
        llvm::BasicBlock::Create(context.context, "entry", helper));
    std::vector<llvm::Value *> arguments;
    for (std::size_t i = 0; i < operands.size(); ++i)
      arguments.push_back(builder.CreateAlignedLoad(
          operands[i]->getType(), helper->getArg(i + 1), llvm::Align(1)));
    auto *result = emitTargetOperation(context, instruction, arguments);
    if (instruction.result.type != Type::Unit)
      builder.CreateAlignedStore(result, helper->getArg(0), llvm::Align(1));
    builder.CreateRetVoid();
    builder.restoreIP(saved);
  }
  // Optional instructions stay inside a feature-bearing physical helper.
  // Passing storage, not vectors, keeps its ABI identical on the baseline
  // caller and the accelerated callee; a dispatch guard never enables an
  // instruction in the caller's unguarded prologue.
  llvm::IRBuilder<> entry(
      &builder.GetInsertBlock()->getParent()->getEntryBlock(),
      builder.GetInsertBlock()->getParent()->getEntryBlock().begin());
  auto *result = entry.CreateAlloca(context.type(instruction.result.type));
  std::vector<llvm::Value *> arguments{result};
  for (auto *operand : operands) {
    auto *storage = entry.CreateAlloca(operand->getType());
    builder.CreateStore(operand, storage);
    arguments.push_back(storage);
  }
  auto *call = builder.CreateCall(helper, arguments);
  call->addFnAttr(llvm::Attribute::NoUnwind);
  return instruction.result.type == Type::Unit
             ? static_cast<llvm::Value *>(
                   llvm::UndefValue::get(context.type(Type::Unit)))
             : builder.CreateLoad(context.type(instruction.result.type),
                                  result);
}
llvm::Value *detectFeature(LoweringContext &context, std::string_view feature) {
  auto &builder = context.builder;
  if (context.program.target.baseline.contains(std::string(feature)))
    return builder.getTrue();
  // CPUID is baseline x86-64. XGETBV is executed only under OSXSAVE, and AVX
  // families require the OS to preserve all of their architectural state.
  auto *quad = llvm::StructType::get(
      context.context, {builder.getInt32Ty(), builder.getInt32Ty(),
                        builder.getInt32Ty(), builder.getInt32Ty()});
  auto *cpuid = llvm::InlineAsm::get(
      llvm::FunctionType::get(
          quad, {builder.getInt32Ty(), builder.getInt32Ty()}, false),
      "cpuid", "={ax},={bx},={cx},={dx},0,2", false);
  auto query = [&](unsigned leaf) {
    auto *call = builder.CreateCall(
        cpuid, {builder.getInt32(leaf), builder.getInt32(0)});
    call->addFnAttr(llvm::Attribute::NoUnwind);
    return call;
  };
  auto *maximum = builder.CreateExtractValue(query(0), 0);
  auto *leaf1 = query(1);
  auto bit = [&](llvm::Value *value, unsigned number) -> llvm::Value * {
    return builder.CreateICmpNE(
        builder.CreateAnd(value, builder.getInt32(std::uint32_t{1} << number)),
        builder.getInt32(0));
  };
  auto *ecx = builder.CreateExtractValue(leaf1, 2);
  llvm::Value *hardware = builder.getFalse();
  bool avx = feature == "avx" || feature == "avx2" || feature == "fma" ||
             feature.starts_with("avx512");
  for (auto [name, position] : {std::pair{"sse3", 0u},
                                {"pclmulqdq", 1u},
                                {"ssse3", 9u},
                                {"fma", 12u},
                                {"sse4.1", 19u},
                                {"sse4.2", 20u},
                                {"popcnt", 23u},
                                {"aes", 25u},
                                {"avx", 28u}})
    if (feature == name)
      hardware = bit(ecx, position);
  if (feature == "lzcnt") {
    auto *maxExtended = builder.CreateExtractValue(query(0x80000000u), 0);
    auto *function = builder.GetInsertBlock()->getParent();
    auto *supported =
        llvm::BasicBlock::Create(context.context, "cpuid.ext", function);
    auto *done =
        llvm::BasicBlock::Create(context.context, "cpuid.end", function);
    auto *before = builder.GetInsertBlock();
    builder.CreateCondBr(
        builder.CreateICmpUGE(maxExtended, builder.getInt32(0x80000001u)),
        supported, done);
    builder.SetInsertPoint(supported);
    auto *value = bit(builder.CreateExtractValue(query(0x80000001u), 2), 5);
    builder.CreateBr(done);
    builder.SetInsertPoint(done);
    auto *phi = builder.CreatePHI(builder.getInt1Ty(), 2);
    phi->addIncoming(builder.getFalse(), before);
    phi->addIncoming(value, supported);
    return phi;
  }
  if (feature == "avx2" || feature == "bmi1" || feature == "bmi2" ||
      feature.starts_with("avx512")) {
    auto *function = builder.GetInsertBlock()->getParent();
    auto *supported =
        llvm::BasicBlock::Create(context.context, "cpuid.7", function);
    auto *done =
        llvm::BasicBlock::Create(context.context, "cpuid.end", function);
    auto *before = builder.GetInsertBlock();
    builder.CreateCondBr(builder.CreateICmpUGE(maximum, builder.getInt32(7)),
                         supported, done);
    builder.SetInsertPoint(supported);
    auto *ebx = builder.CreateExtractValue(query(7), 1);
    unsigned position = feature == "bmi1"       ? 3
                        : feature == "avx2"     ? 5
                        : feature == "bmi2"     ? 8
                        : feature == "avx512dq" ? 17
                        : feature == "avx512cd" ? 28
                        : feature == "avx512bw" ? 30
                        : feature == "avx512vl" ? 31
                                                : 16;
    auto *value = bit(ebx, position);
    if (feature.starts_with("avx512"))
      value = builder.CreateAnd(value, bit(ebx, 16));
    builder.CreateBr(done);
    builder.SetInsertPoint(done);
    auto *phi = builder.CreatePHI(builder.getInt1Ty(), 2);
    phi->addIncoming(builder.getFalse(), before);
    phi->addIncoming(value, supported);
    hardware = phi;
  }
  if (!avx)
    return hardware;
  auto *function = builder.GetInsertBlock()->getParent();
  auto *state = llvm::BasicBlock::Create(context.context, "xgetbv", function);
  auto *done =
      llvm::BasicBlock::Create(context.context, "feature.end", function);
  auto *before = builder.GetInsertBlock();
  auto *enabled = builder.CreateAnd(
      builder.CreateAnd(bit(ecx, 26), bit(ecx, 27)), bit(ecx, 28));
  builder.CreateCondBr(builder.CreateAnd(hardware, enabled), state, done);
  builder.SetInsertPoint(state);
  auto *pair = llvm::StructType::get(
      context.context, {builder.getInt32Ty(), builder.getInt32Ty()});
  auto *xgetbv = llvm::InlineAsm::get(
      llvm::FunctionType::get(pair, {builder.getInt32Ty()}, false), "xgetbv",
      "={ax},={dx},{cx}", false);
  auto *call = builder.CreateCall(xgetbv, {builder.getInt32(0)});
  call->addFnAttr(llvm::Attribute::NoUnwind);
  auto *xcr0 = builder.CreateExtractValue(call, 0);
  unsigned mask = feature.starts_with("avx512") ? 0xe6 : 6;
  auto *available = builder.CreateICmpEQ(
      builder.CreateAnd(xcr0, builder.getInt32(mask)), builder.getInt32(mask));
  builder.CreateBr(done);
  builder.SetInsertPoint(done);
  auto *phi = builder.CreatePHI(builder.getInt1Ty(), 2);
  phi->addIncoming(builder.getFalse(), before);
  phi->addIncoming(available, state);
  return phi;
}
namespace {
std::string constantText(const NumericLiteral &literal) {
  auto words = literal.magnitude;
  std::string result;
  do {
    unsigned remainder = 0;
    for (int i = 127; i >= 0; --i) {
      remainder = remainder * 2 + ((words[i / 64] >> (i % 64)) & 1);
      if (remainder >= 10) {
        words[i / 64] |= std::uint64_t{1} << (i % 64);
        remainder -= 10;
      } else
        words[i / 64] &= ~(std::uint64_t{1} << (i % 64));
    }
    result.insert(result.begin(), static_cast<char>('0' + remainder));
  } while (words[0] || words[1]);
  return literal.negative ? "-" + result : result;
}
std::string
templates(const Assembly &assembly,
          const std::function<std::string(std::size_t, char)> &operand,
          bool llvmEscape) {
  std::string result;
  std::size_t implicit = 0;
  for (const auto &text : assembly.templates) {
    if (!result.empty())
      result += '\n';
    for (std::size_t i = 0; i < text.size(); ++i) {
      if (text[i] == '$' && llvmEscape) {
        result += "$$";
        continue;
      }
      if (assembly.options.contains("raw")) {
        result += text[i];
        continue;
      }
      if ((text[i] == '{' || text[i] == '}') && i + 1 < text.size() &&
          text[i + 1] == text[i]) {
        result += text[i++];
        continue;
      }
      if (text[i] != '{') {
        result += text[i];
        continue;
      }
      auto end = text.find('}', i + 1);
      auto placeholder = text.substr(i + 1, end - i - 1);
      auto colon = placeholder.find(':');
      auto name = placeholder.substr(0, colon);
      std::size_t index = 0;
      if (name.empty())
        index = implicit++;
      else {
        auto parsed =
            std::from_chars(name.data(), name.data() + name.size(), index);
        if (parsed.ec != std::errc{})
          for (std::size_t n = 0; n < assembly.operands.size(); ++n)
            if (assembly.operands[n].name == name)
              index = n;
      }
      result += operand(
          index, colon == std::string::npos ? '\0' : placeholder[colon + 1]);
      i = end;
    }
  }
  return result;
}
std::string constraint(const AssemblyOperand &operand, TargetArch arch) {
  if (operand.explicitRegister) {
    auto reg = canonicalRegister(arch, operand.reg);
    if (arch == TargetArch::X86_64 && reg.starts_with("v"))
      reg = "xmm" + reg.substr(1);
    if (reg == "rax" || reg == "rbx" || reg == "rcx" || reg == "rdx")
      reg = reg.substr(1);
    if (arch == TargetArch::Aarch64 && reg == "x30")
      reg = "lr";
    if (reg == "st(0)")
      reg = "st";
    return "{" + reg + "}";
  }
  if (operand.reg == "reg")
    return "r";
  if (operand.reg == "reg_abcd")
    return "Q";
  if (operand.reg == "reg_byte")
    return "q";
  if (operand.reg == "xmm_reg" || operand.reg == "ymm_reg")
    return "x";
  if (operand.reg == "zmm_reg")
    return "v";
  if (operand.reg == "kreg")
    return "Yk";
  return operand.reg == "vreg_low16" ? "x" : "w";
}
} // namespace
llvm::Value *emitAssembly(LoweringContext &context, const Assembly &assembly,
                          Type resultType, llvm::ArrayRef<llvm::Value *> inputs,
                          const AssemblySymbolResolver &symbols) {
  auto &builder = context.builder;
  auto arch = context.program.target.arch;
  auto required = assemblyFeatures(context.program.target, assembly);
  auto *parent = builder.GetInsertBlock()->getParent();
  std::set<std::string> enabled;
  auto attributes =
      parent->getFnAttribute("target-features").getValueAsString();
  for (const auto &feature : required)
    if (attributes.contains("+" + feature))
      enabled.insert(feature);
  if (!featuresAvailable(context.program.target, enabled, required)) {
    std::vector<llvm::Type *> parameters(inputs.size() + 1, builder.getPtrTy());
    auto *helper = llvm::Function::Create(
        llvm::FunctionType::get(builder.getVoidTy(), parameters, false),
        llvm::GlobalValue::InternalLinkage, "mettle.target.asm",
        context.module);
    targetAttributes(*helper, context.program.target, required);
    helper->addFnAttr(llvm::Attribute::NoInline);
    helper->addFnAttr(llvm::Attribute::NoUnwind);
    auto saved = builder.saveIP();
    builder.SetInsertPoint(
        llvm::BasicBlock::Create(context.context, "entry", helper));
    std::vector<llvm::Value *> operands;
    for (std::size_t i = 0; i < inputs.size(); ++i)
      operands.push_back(builder.CreateAlignedLoad(
          inputs[i]->getType(), helper->getArg(i + 1), llvm::Align(1)));
    auto *result =
        emitAssembly(context, assembly, resultType, operands, symbols);
    if (assembly.options.contains("noreturn"))
      builder.CreateUnreachable();
    else {
      builder.CreateAlignedStore(result, helper->getArg(0), llvm::Align(1));
      builder.CreateRetVoid();
    }
    builder.restoreIP(saved);
    llvm::IRBuilder<> entry(&parent->getEntryBlock(),
                            parent->getEntryBlock().begin());
    auto *output = entry.CreateAlloca(context.type(resultType));
    std::vector<llvm::Value *> arguments{output};
    for (auto *input : inputs) {
      auto *storage = entry.CreateAlloca(input->getType());
      builder.CreateStore(input, storage);
      arguments.push_back(storage);
    }
    auto *call = builder.CreateCall(helper, arguments);
    call->addFnAttr(llvm::Attribute::NoUnwind);
    if (assembly.options.contains("noreturn"))
      call->addFnAttr(llvm::Attribute::NoReturn);
    return assembly.options.contains("noreturn")
               ? static_cast<llvm::Value *>(
                     llvm::UndefValue::get(context.type(resultType)))
               : builder.CreateLoad(context.type(resultType), output);
  }
  std::vector<std::string> constraints;
  std::vector<llvm::Type *> outputs;
  std::vector<Type> publishedTypes;
  std::vector<int> indices(assembly.operands.size(), -1), published;
  std::vector<llvm::Value *> arguments;
  auto append = [&](std::string value) {
    constraints.push_back(std::move(value));
  };
  std::set<std::string> explicitOutputs;
  auto physicalType = [&](const AssemblyOperand &operand, Type logical) {
    auto reg = operand.explicitRegister ? canonicalRegister(arch, operand.reg)
                                        : operand.reg;
    bool general = reg == "reg" || reg == "reg_abcd" || reg == "reg_byte" ||
                   (operand.explicitRegister &&
                    (reg.starts_with("r") || reg.starts_with("x")));
    if (context.program.types->isPointer(logical) ||
        context.program.types->isFunctionPointer(logical))
      return static_cast<llvm::Type *>(builder.getInt64Ty());
    if (isFloating(logical) && general)
      return static_cast<llvm::Type *>(
          builder.getIntNTy(logical == Type::F32 ? 32 : 64));
    if (isInteger(logical) && integerWidth(logical) == 128 && !general)
      return static_cast<llvm::Type *>(
          llvm::FixedVectorType::get(builder.getInt64Ty(), 2));
    return context.type(logical);
  };
  auto encode = [&](const AssemblyOperand &operand, llvm::Value *value) {
    auto *physical = physicalType(operand, operand.inputType);
    return value->getType()->isPointerTy()
               ? builder.CreatePtrToInt(value, physical)
               : builder.CreateBitCast(value, physical);
  };
  auto onlyClobber = [&](const AssemblyOperand &operand) {
    return operand.explicitRegister && operand.discard &&
           !assemblyInput(operand.mode);
  };
  for (std::size_t i = 0; i < assembly.operands.size(); ++i) {
    const auto &operand = assembly.operands[i];
    if (!assemblyOutput(operand.mode))
      continue;
    if (operand.explicitRegister)
      explicitOutputs.insert(canonicalRegister(arch, operand.reg));
    if (onlyClobber(operand))
      continue;
    indices[i] = static_cast<int>(outputs.size());
    outputs.push_back(physicalType(operand, operand.type));
    append(std::string(assemblyLate(operand.mode) ? "=" : "=&") +
           constraint(operand, arch));
    if (!operand.discard) {
      published.push_back(indices[i]);
      publishedTypes.push_back(operand.type);
    }
  }
  auto outputCount = outputs.size();
  std::size_t input = 0;
  for (std::size_t i = 0; i < assembly.operands.size(); ++i) {
    const auto &operand = assembly.operands[i];
    if (assemblyInput(operand.mode)) {
      if (!assemblyOutput(operand.mode))
        indices[i] = static_cast<int>(constraints.size());
      append(assemblyOutput(operand.mode) ? std::to_string(indices[i])
                                          : constraint(operand, arch));
      arguments.push_back(encode(operand, inputs[input++]));
    } else if (operand.mode == AssemblyMode::Sym) {
      indices[i] = static_cast<int>(constraints.size());
      append(arch == TargetArch::X86_64 ? "s" : "S");
      arguments.push_back(symbols(operand.symbolKind, operand.symbol));
    }
  }
  for (const auto &operand : assembly.operands)
    if (onlyClobber(operand))
      append("~" + constraint(operand, arch));
  if (!assembly.clobberAbis.empty()) {
    std::vector<std::string> clobbers;
    if (arch == TargetArch::X86_64) {
      clobbers = {"rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"};
      for (unsigned i = 0; i < 32; ++i)
        clobbers.push_back("v" + std::to_string(i));
      for (unsigned i = 0; i < 8; ++i) {
        clobbers.push_back("k" + std::to_string(i));
        clobbers.push_back("st(" + std::to_string(i) + ")");
        clobbers.push_back("mm" + std::to_string(i));
        clobbers.push_back("tmm" + std::to_string(i));
      }
    } else {
      for (unsigned i = 0; i <= 30; ++i)
        if (i <= 17 || i == 30)
          clobbers.push_back("x" + std::to_string(i));
      for (unsigned i = 0; i < 32; ++i)
        clobbers.push_back("v" + std::to_string(i));
    }
    for (auto reg : clobbers)
      if (!explicitOutputs.contains(reg)) {
        if (arch == TargetArch::X86_64 && reg.starts_with("v"))
          reg = "xmm" + reg.substr(1);
        if (arch == TargetArch::Aarch64 && reg == "x30")
          reg = "lr";
        if (reg == "st(0)")
          reg = "st";
        append("~{" + reg + "}");
      }
  }
  if (!assembly.options.contains("preserves_flags")) {
    if (arch == TargetArch::X86_64) {
      append("~{dirflag}");
      append("~{fpsr}");
      append("~{flags}");
    } else
      append("~{cc}");
  }
  if (!assembly.options.contains("nomem"))
    append("~{memory}");
  auto text = templates(
      assembly,
      [&](std::size_t index, char modifier) {
        const auto &operand = assembly.operands[index];
        if (operand.mode == AssemblyMode::Const)
          return constantText(operand.constant);
        if (operand.mode == AssemblyMode::Sym && arch == TargetArch::X86_64)
          modifier = 'c';
        else if (arch == TargetArch::X86_64) {
          if (!modifier && (operand.reg == "reg" || operand.reg == "reg_abcd"))
            modifier = 'q';
          else if (!modifier && operand.reg == "ymm_reg")
            modifier = 't';
          else if (!modifier && operand.reg == "zmm_reg")
            modifier = 'g';
          else if (modifier == 'l')
            modifier = 'b';
          else if (modifier == 'x')
            modifier =
                operand.reg == "reg" || operand.reg == "reg_abcd" ? 'w' : 'x';
          else if (modifier == 'e')
            modifier = 'k';
          else if (modifier == 'r')
            modifier = 'q';
          else if (modifier == 'y')
            modifier = 't';
          else if (modifier == 'z')
            modifier = 'g';
        } else {
          if (!modifier && operand.reg == "reg")
            modifier = 'x';
          else if (modifier == 'v')
            modifier = '\0';
        }
        return modifier ? "${" + std::to_string(indices[index]) + ":" +
                              modifier + "}"
                        : "$" + std::to_string(indices[index]);
      },
      true);
  std::string joined;
  for (const auto &value : constraints) {
    if (!joined.empty())
      joined += ',';
    joined += value;
  }
  std::vector<llvm::Type *> parameters;
  for (auto *argument : arguments)
    parameters.push_back(argument->getType());
  llvm::Type *physicalResult =
      outputs.empty()       ? builder.getVoidTy()
      : outputs.size() == 1 ? outputs[0]
                            : llvm::StructType::get(context.context, outputs);
  auto *signature = llvm::FunctionType::get(physicalResult, parameters, false);
  auto *code = llvm::InlineAsm::get(
      signature, text, joined, !assembly.options.contains("pure"),
      !assembly.options.contains("nostack"),
      arch == TargetArch::X86_64 && !assembly.options.contains("att_syntax")
          ? llvm::InlineAsm::AD_Intel
          : llvm::InlineAsm::AD_ATT,
      false);
  auto *call = builder.CreateCall(code, arguments);
  call->addFnAttr(llvm::Attribute::NoUnwind);
  if (assembly.options.contains("nomem"))
    call->setMemoryEffects(llvm::MemoryEffects::none());
  else if (assembly.options.contains("readonly"))
    call->setMemoryEffects(llvm::MemoryEffects::readOnly());
  if (assembly.options.contains("noreturn"))
    call->addFnAttr(llvm::Attribute::NoReturn);
  llvm::Value *result = llvm::UndefValue::get(context.type(resultType));
  for (std::size_t i = 0; i < published.size(); ++i) {
    auto *value = outputCount == 1
                      ? static_cast<llvm::Value *>(call)
                      : builder.CreateExtractValue(call, published[i]);
    auto *logical = context.type(publishedTypes[i]);
    value = logical->isPointerTy() ? builder.CreateIntToPtr(value, logical)
                                   : builder.CreateBitCast(value, logical);
    result = builder.CreateInsertValue(result, value, i);
  }
  return result;
}
std::string globalAssembly(LoweringContext &context, const Assembly &assembly,
                           const AssemblySymbolResolver &symbols) {
  std::vector<llvm::GlobalValue *> retained;
  auto text = templates(
      assembly,
      [&](std::size_t index, char) {
        const auto &operand = assembly.operands[index];
        if (operand.mode == AssemblyMode::Const)
          return constantText(operand.constant);
        auto *symbol = symbols(operand.symbolKind, operand.symbol);
        retained.push_back(symbol);
        llvm::SmallString<128> name;
        llvm::Mangler().getNameWithPrefix(name, symbol, false);
        std::string quoted = "\"";
        for (char character : name) {
          if (character == '"' || character == '\\')
            quoted += '\\';
          quoted += character;
        }
        return quoted + '"';
      },
      false);
  if (!retained.empty())
    llvm::appendToCompilerUsed(context.module, retained);
  if (context.program.target.arch == TargetArch::X86_64 &&
      !assembly.options.contains("att_syntax"))
    return ".intel_syntax noprefix\n" + text + "\n.att_syntax\n";
  return text;
}
} // namespace mettle::backend
