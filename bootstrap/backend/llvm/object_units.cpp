#include "backend/llvm/object.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/ValueMapper.h"

#include <map>
#include <memory>
#include <numeric>
#include <vector>

namespace mettle::backend {
namespace {
class UnitMaterializer final : public llvm::ValueMaterializer {
public:
  explicit UnitMaterializer(llvm::Module &unit) : unit(unit) {}

  llvm::Value *materialize(llvm::Value *value) override {
    if (auto *function = llvm::dyn_cast<llvm::Function>(value)) {
      auto *copy = llvm::Function::Create(
          function->getFunctionType(), llvm::GlobalValue::ExternalLinkage,
          function->getAddressSpace(), function->getName(), &unit);
      copy->copyAttributesFrom(function);
      copy->setLinkage(llvm::GlobalValue::ExternalLinkage);
      copy->setComdat(nullptr);
      copy->setPersonalityFn(nullptr);
      if (copy->hasPrefixData())
        copy->setPrefixData(nullptr);
      if (copy->hasPrologueData())
        copy->setPrologueData(nullptr);
      return copy;
    }
    if (auto *global = llvm::dyn_cast<llvm::GlobalVariable>(value)) {
      auto *copy = new llvm::GlobalVariable(
          unit, global->getValueType(), global->isConstant(),
          llvm::GlobalValue::ExternalLinkage, nullptr, global->getName(),
          nullptr, global->getThreadLocalMode(), global->getAddressSpace(),
          global->isExternallyInitialized());
      copy->copyAttributesFrom(global);
      copy->setLinkage(llvm::GlobalValue::ExternalLinkage);
      copy->setComdat(nullptr);
      return copy;
    }
    return nullptr;
  }

private:
  llvm::Module &unit;
};

llvm::Error consumeUnit(llvm::Module &module,
                        const std::vector<llvm::GlobalObject *> &definitions,
                        UnitConsumer consume) {
  auto owner = std::make_unique<llvm::Module>(module.getModuleIdentifier(),
                                              module.getContext());
  auto &unit = *owner;
  unit.setSourceFileName(module.getSourceFileName());
  unit.setTargetTriple(module.getTargetTriple());
  unit.setDataLayout(module.getDataLayout());
  llvm::ValueToValueMapTy values;
  UnitMaterializer materializer(unit);
  llvm::ValueMapper mapper(values, llvm::RF_None, nullptr, &materializer);
  for (auto *definition : definitions)
    mapper.mapValue(*definition);
  for (auto *definition : definitions) {
    auto *copy = llvm::cast<llvm::GlobalObject>(values[definition]);
    copy->setLinkage(definition->getLinkage());
    if (auto *comdat = definition->getComdat()) {
      auto *cloned = unit.getOrInsertComdat(comdat->getName());
      cloned->setSelectionKind(comdat->getSelectionKind());
      copy->setComdat(cloned);
    }
    if (auto *function = llvm::dyn_cast<llvm::Function>(definition)) {
      auto *cloned = llvm::cast<llvm::Function>(copy);
      auto argument = cloned->arg_begin();
      for (auto &original : function->args())
        values[&original] = &*argument++;
      llvm::SmallVector<llvm::ReturnInst *, 8> returns;
      llvm::CloneFunctionInto(cloned, function, values,
                              llvm::CloneFunctionChangeType::DifferentModule,
                              returns, "", nullptr, nullptr, &materializer);
    } else {
      auto *global = llvm::cast<llvm::GlobalVariable>(definition);
      llvm::cast<llvm::GlobalVariable>(copy)->setInitializer(
          mapper.mapConstant(*global->getInitializer()));
    }
    llvm::SmallVector<std::pair<unsigned, llvm::MDNode *>, 8> metadata;
    definition->getAllMetadata(metadata);
    for (const auto &[kind, node] : metadata)
      copy->setMetadata(kind, mapper.mapMDNode(*node));
  }
  for (const auto &metadata : module.named_metadata()) {
    auto *cloned = unit.getOrInsertNamedMetadata(metadata.getName());
    for (auto *operand : metadata.operands())
      cloned->addOperand(mapper.mapMDNode(*operand));
  }
  if (auto *units = unit.getNamedMetadata("llvm.dbg.cu");
      units && units->getNumOperands() == 0)
    unit.eraseNamedMetadata(units);
  std::string diagnostic;
  llvm::raw_string_ostream stream(diagnostic);
  if (llvm::verifyModule(unit, &stream))
    return llvm::createStringError(llvm::inconvertibleErrorCode(),
                                   "invalid object unit: " + diagnostic);
  return consume(unit, std::move(owner));
}
} // namespace

llvm::Error partitionObjectModule(llvm::Module &module,
                                  llvm::StringRef symbolNamespace,
                                  UnitConsumer consume) {
  if (!module.getModuleInlineAsm().empty() || !module.alias_empty() ||
      !module.ifunc_empty() || module.getNamedMetadata("llvm.dbg.cu"))
    return consume(module, nullptr);
  for (const auto &global : module.global_values())
    if (global.hasExternalWeakLinkage())
      return consume(module, nullptr);
  for (const auto &global : module.globals())
    if (global.hasAppendingLinkage() || global.getName().starts_with("llvm."))
      return consume(module, nullptr);
  llvm::SmallPtrSet<const llvm::GlobalObject *, 32> assemblyLocals;
  for (const auto &function : module)
    for (const auto &block : function)
      if (block.hasAddressTaken())
        return consume(module, nullptr);
  for (const auto &function : module)
    for (const auto &block : function)
      for (const auto &instruction : block)
        for (const auto &operand : instruction.operands())
          if (auto *assembly = llvm::dyn_cast<llvm::InlineAsm>(operand)) {
            llvm::StringRef text = assembly->getAsmString();
            if (text.empty())
              continue;
            llvm::SmallVector<llvm::StringRef, 8> lines;
            std::string separated = text.str();
            for (auto &character : separated)
              if (character == ';')
                character = '\n';
            llvm::StringRef(separated).split(lines, '\n');
            for (auto line : lines)
              if (line.trim().starts_with("."))
                return consume(module, nullptr);
            for (const auto &global : module.global_objects())
              if (global.hasLocalLinkage() && global.hasName() &&
                  text.contains(global.getName()))
                assemblyLocals.insert(&global);
          }
  std::vector<llvm::GlobalObject *> definitions;
  llvm::DenseMap<const llvm::GlobalObject *, std::size_t> ordinals;
  for (auto &global : module.global_objects())
    if (!global.isDeclaration() && !global.hasAvailableExternallyLinkage()) {
      ordinals[&global] = definitions.size();
      definitions.push_back(&global);
    }
  if (definitions.size() < 2)
    return consume(module, nullptr);
  for (auto *global : definitions)
    if (global->hasLocalLinkage() && !assemblyLocals.contains(global)) {
      global->setName("mettle.unit." + symbolNamespace + "." +
                      global->getName());
      global->setLinkage(llvm::GlobalValue::ExternalLinkage);
      global->setVisibility(llvm::GlobalValue::HiddenVisibility);
      global->setDSOLocal(true);
    }
  std::vector<std::size_t> parents(definitions.size());
  std::iota(parents.begin(), parents.end(), 0);
  auto root = [&](std::size_t index) {
    while (parents[index] != index) {
      parents[index] = parents[parents[index]];
      index = parents[index];
    }
    return index;
  };
  auto join = [&](std::size_t a, std::size_t b) { parents[root(b)] = root(a); };
  std::map<std::string, std::vector<std::size_t>> families;
  std::vector<std::vector<std::size_t>> dataReferences(definitions.size());
  for (std::size_t index = 0; index < definitions.size(); ++index)
    if (auto *function = llvm::dyn_cast<llvm::Function>(definitions[index])) {
      std::string family = function->getName().str();
      if (auto *metadata = function->getMetadata("mettle.codegen.family"))
        if (auto *name =
                llvm::dyn_cast<llvm::MDString>(metadata->getOperand(0)))
          family = name->getString().str();
      auto &members = families[family];
      if (!members.empty())
        join(members.front(), index);
      members.push_back(index);
    }
  llvm::DenseMap<const llvm::Comdat *, std::size_t> comdats;
  for (std::size_t index = 0; index < definitions.size(); ++index) {
    auto *definition = definitions[index];
    if (auto *comdat = definition->getComdat()) {
      auto [found, inserted] = comdats.try_emplace(comdat, index);
      if (!inserted)
        join(index, found->second);
    }
    if (auto *associated =
            definition->getMetadata(llvm::LLVMContext::MD_associated))
      if (auto *value =
              llvm::dyn_cast<llvm::ValueAsMetadata>(associated->getOperand(0)))
        if (auto *global =
                llvm::dyn_cast<llvm::GlobalObject>(value->getValue());
            global && ordinals.contains(global))
          join(index, ordinals.lookup(global));
    llvm::SmallPtrSet<const llvm::Value *, 32> visited;
    std::vector<const llvm::Value *> pending{definition};
    while (!pending.empty()) {
      auto *value = pending.back();
      pending.pop_back();
      if (!visited.insert(value).second)
        continue;
      if (auto *assembly = llvm::dyn_cast<llvm::InlineAsm>(value))
        for (auto *global : assemblyLocals)
          if (llvm::StringRef(assembly->getAsmString())
                  .contains(global->getName()))
            join(index, ordinals.lookup(global));
      if (auto *global = llvm::dyn_cast<llvm::GlobalObject>(value);
          global && value != definition) {
        auto found = ordinals.find(global);
        if (found != ordinals.end()) {
          if (global->hasLocalLinkage())
            join(index, found->second);
          if (llvm::isa<llvm::GlobalVariable>(global))
            dataReferences[index].push_back(found->second);
        }
      }
      if (value != definition && llvm::isa<llvm::GlobalValue>(value))
        continue;
      if (auto *user = llvm::dyn_cast<llvm::User>(value))
        for (const auto &operand : user->operands())
          pending.push_back(operand);
      if (auto *function = llvm::dyn_cast<llvm::Function>(value))
        for (const auto &block : *function)
          for (const auto &instruction : block)
            pending.push_back(&instruction);
    }
  }
  std::vector<bool> assigned(definitions.size(), false);
  for (const auto &[family, members] : families) {
    std::vector<std::size_t> pending;
    for (auto member : members)
      pending.insert(pending.end(), dataReferences[member].begin(),
                     dataReferences[member].end());
    while (!pending.empty()) {
      const auto index = pending.back();
      pending.pop_back();
      if (assigned[index])
        continue;
      assigned[index] = true;
      join(members.front(), index);
      pending.insert(pending.end(), dataReferences[index].begin(),
                     dataReferences[index].end());
    }
  }
  std::map<std::size_t, std::vector<llvm::GlobalObject *>> groups;
  for (std::size_t index = 0; index < definitions.size(); ++index)
    groups[root(index)].push_back(definitions[index]);
  for (const auto &[index, group] : groups)
    if (auto error = consumeUnit(module, group, consume))
      return error;
  return llvm::Error::success();
}
} // namespace mettle::backend
