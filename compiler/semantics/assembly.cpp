#include "semantics/checker.h"
#include <algorithm>
#include <functional>

namespace mettle {
namespace {
AssemblyMode operandMode(std::string_view mode) {
  return mode == "in"          ? AssemblyMode::In
         : mode == "out"       ? AssemblyMode::Out
         : mode == "lateout"   ? AssemblyMode::LateOut
         : mode == "inout"     ? AssemblyMode::InOut
         : mode == "inlateout" ? AssemblyMode::InLateOut
         : mode == "const"     ? AssemblyMode::Const
                               : AssemblyMode::Sym;
}
} // namespace
int Checker::assemblyExpression(Node &n, bool reachable) {
  const auto &syntax = *n.assembly;
  Assembly assembly;
  assembly.variant = syntax.variant == "asm"         ? AssemblyVariant::Inline
                     : syntax.variant == "naked_asm" ? AssemblyVariant::Naked
                                                     : AssemblyVariant::Global;
  if (assembly.variant == AssemblyVariant::Inline)
    requireUnsafe(n.span);
  if (assembly.variant == AssemblyVariant::Naked &&
      (!current || !facts(*current).naked))
    error("attribute", n.span, "naked_asm requires a naked function");
  if (assembly.variant == AssemblyVariant::Global &&
      syntax.variant == "global_asm" && current)
    error("attribute", n.span, "global_asm is only permitted at module scope");
  assembly.templates = syntax.templates;
  assembly.options.insert(syntax.options.begin(), syntax.options.end());
  assembly.clobberAbis.insert(syntax.clobberAbis.begin(),
                              syntax.clobberAbis.end());
  for (const auto &operand : syntax.operands) {
    AssemblyOperand checkedOperand;
    checkedOperand.mode = operandMode(operand.mode);
    checkedOperand.name = operand.name;
    checkedOperand.reg = operand.reg;
    checkedOperand.explicitRegister = operand.explicitRegister;
    checkedOperand.discard = operand.discard;
    if (operand.mode == "sym") {
      auto &symbol = *n.children[operand.input];
      auto name = symbol.kind == Kind::Name
                      ? callableName(symbol.text, current ? current->owner : "",
                                     symbol.span)
                      : std::string{};
      auto found = names.find(name);
      if (found != names.end()) {
        functionValue(symbol, found->second);
        checkedOperand.symbol = static_cast<int>(found->second);
        checkedOperand.symbolArguments = facts(symbol).typeArguments;
      } else if (symbol.kind == Kind::Name) {
        if (auto storage = staticName(symbol.text, symbol.span)) {
          checkedOperand.symbolKind = AssemblyOperand::SymbolKind::Static;
          checkedOperand.symbol =
              static_cast<int>(checked.staticStorage[*storage].identity);
        }
      }
      if (checkedOperand.symbol < 0)
        error("name", symbol.span,
              "assembly sym requires a resolved function or static symbol");
      facts(symbol).type = Type::Unit;
    } else {
      int input = -1, output = -1;
      if (operand.input >= 0) {
        auto &value = *n.children[operand.input];
        if (checkedOperand.mode == AssemblyMode::Const) {
          auto identity = constantType(value, constantContext(value));
          checkedOperand.constantIdentity = identity;
          facts(value).type = checked.types->isConstant(identity)
                                  ? checked.types->parameter(identity).valueType
                                  : Type::Unknown;
          input = inference.fresh(facts(value).type);
        } else
          input = node(value, reachable);
      }
      if (operand.output >= 0) {
        auto &destination = *n.children[operand.output];
        requireMutablePlace(destination);
        auto *place = &destination;
        while (place->kind == Kind::Group)
          place = place->children[0].get();
        if (place->kind != Kind::Name && place->kind != Kind::Field &&
            place->kind != Kind::Index &&
            !(place->kind == Kind::Unary && place->text == "*"))
          error("type", place->span,
                "assembly output requires a mutable place");
        facts(*place).writeOnly = !assemblyInput(checkedOperand.mode);
        output = operand.output == operand.input ? input
                                                 : node(destination, reachable);
        if (input >= 0 && output >= 0) {
          auto a = inference.value(input), b = inference.value(output);
          auto width = [&](Type type) {
            return isInteger(type) ? integerWidth(type)
                   : checked.types->isPointer(type) ||
                           checked.types->isFunctionPointer(type)
                       ? 64u
                       : 0u;
          };
          if (!width(a) || width(a) != width(b))
            inference.equal(input, output, operand.span, true);
        }
      }
      checkedOperand.type = output >= 0  ? inference.value(output)
                            : input >= 0 ? inference.value(input)
                                         : Type::I64;
    }
    assembly.operands.push_back(std::move(checkedOperand));
  }
  facts(n).assembly = std::move(assembly);
  facts(n).targetFeatures = availableFeatures();
  return inference.fresh(syntax.variant == "naked_asm" ||
                                 facts(n).assembly->options.contains("noreturn")
                             ? Type::Never
                             : Type::Unit);
}
void Checker::finishAssembly() {
  auto finish = [&](Node &n) {
    auto &assembly = *facts(n).assembly;
    const auto &syntax = *n.assembly;
    std::vector<Type> outputs;
    bool constantFailed = false;
    for (std::size_t i = 0; i < assembly.operands.size(); ++i) {
      auto &operand = assembly.operands[i];
      const auto &source = syntax.operands[i];
      if (operand.mode == AssemblyMode::Sym)
        continue;
      if (source.input >= 0)
        operand.inputType = facts(*n.children[source.input]).type;
      if (source.output >= 0)
        operand.type = facts(*n.children[source.output]).type;
      else if (source.input >= 0)
        operand.type = operand.inputType;
      else {
        operand.type = operand.reg == "reg_byte" ? Type::I8
                       : operand.reg == "kreg"   ? Type::I16
                                                 : Type::I64;
        std::string vectorName;
        auto reg = std::string_view(operand.reg);
        if (checked.targetDescription.arch == TargetArch::Aarch64 &&
            (reg == "vreg" || reg == "vreg_low16" ||
             (operand.explicitRegister &&
              canonicalRegister(checked.targetDescription.arch, reg)
                  .starts_with("v"))))
          vectorName = "core::arch::aarch64::int64x2_t";
        else if (checked.targetDescription.arch == TargetArch::X86_64) {
          if (reg == "xmm_reg" || reg.starts_with("xmm"))
            vectorName = "core::arch::x86_64::__m128i";
          else if (reg == "ymm_reg" || reg.starts_with("ymm"))
            vectorName = "core::arch::x86_64::__m256i";
          else if (reg == "zmm_reg" || reg.starts_with("zmm"))
            vectorName = "core::arch::x86_64::__m512i";
        }
        if (auto descriptor = targetVector(vectorName))
          operand.type = checked.types->vectorType(
              descriptor->name, descriptor->element, descriptor->lanes,
              descriptor->alignment);
      }
      if (operand.mode == AssemblyMode::Const) {
        if (auto value =
                checked.types->scalarConstantValue(operand.constantIdentity))
          operand.constant = *value;
        else
          constantFailed = true;
      }
      if (assemblyOutput(operand.mode) && !operand.discard)
        outputs.push_back(operand.type);
    }
    if (auto failure =
            constantFailed
                ? std::nullopt
                : validateAssembly(*checked.types, checked.targetDescription,
                                   facts(n).targetFeatures, assembly))
      error("assembly", n.span, *failure);
    facts(n).machineType =
        checked.types->structural(AggregateKind::Tuple, std::move(outputs));
  };
  for (auto &function : module.functions) {
    current = &function;
    std::function<void(Node &)> visit = [&](Node &node) {
      if (node.kind == Kind::Assembly && facts(node).assembly)
        finish(node);
      for (auto &child : node.children)
        visit(*child);
    };
    if (function.body.get())
      visit(*function.body);
    for (auto &parameter : function.parameters)
      if (parameter.defaultValue.get())
        visit(*parameter.defaultValue);
  }
  current = nullptr;
  for (auto &node : module.globalAssembly) {
    assemblyExpression(*node, true);
    finish(*node);
    checked.assemblyItems.push_back(*facts(*node).assembly);
  }
}
} // namespace mettle
