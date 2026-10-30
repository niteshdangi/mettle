#include "backend/llvm/debug.h"
#include "types/layout.h"
#include "llvm/ADT/APInt.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Metadata.h"
#include <algorithm>

namespace mettle::backend {
namespace {
bool known(Span span) { return span.begin != 0 || span.end != 0; }

std::pair<unsigned, unsigned> position(const std::vector<std::size_t> &lines,
                                       std::size_t offset) {
  auto next = std::upper_bound(lines.begin(), lines.end(), offset);
  auto line = static_cast<unsigned>(next - lines.begin());
  return {line, static_cast<unsigned>(offset - lines[line - 1] + 1)};
}
} // namespace

DebugInfo::DebugInfo(llvm::Module &module, const ir::Program &program,
                     const DebugInfoRequest &request)
    : module(module), program(program), request(request), dib(module) {
  module.addModuleFlag(llvm::Module::Warning, "Debug Info Version",
                       llvm::DEBUG_METADATA_VERSION);
  module.addModuleFlag(llvm::Module::Max, "Dwarf Version", 4);
  auto *root = info(0);
  rootFile = root ? root->file : dib.createFile("<unknown>", request.directory);
  // Mettle has no DWARF language code; C11 is the closest data model.
  unit = dib.createCompileUnit(
      llvm::DISourceLanguageName(llvm::dwarf::DW_LANG_C11), rootFile, "mettle",
      false, "", 0);
  subroutine = dib.createSubroutineType(
      dib.getOrCreateTypeArray(llvm::ArrayRef<llvm::Metadata *>()));
}

DebugInfo::SourceInfo *DebugInfo::info(SourceId id) {
  auto [entry, inserted] = infos.try_emplace(id);
  if (inserted) {
    auto found = std::find_if(
        request.sources.begin(), request.sources.end(),
        [&](const Source &candidate) { return candidate.id == id; });
    if (found != request.sources.end()) {
      entry->second.source = &*found;
      entry->second.file = dib.createFile(found->path, request.directory);
      entry->second.lines.push_back(0);
      for (std::size_t i = 0; i < found->text.size(); ++i)
        if (found->text[i] == '\n')
          entry->second.lines.push_back(i + 1);
    }
  }
  return entry->second.source ? &entry->second : nullptr;
}

llvm::DISubprogram *DebugInfo::attach(llvm::Function &function,
                                      const ir::Function &source,
                                      bool artificial) {
  auto *file = rootFile;
  unsigned line = 0;
  auto span = request.sourceSpan ? request.sourceSpan(source.span) : source.span;
  if (auto *found = known(span) ? info(span.source) : nullptr) {
    file = found->file;
    line = position(found->lines,
                    std::min(span.begin, found->source->text.size()))
               .first;
  }
  auto local = function.hasLocalLinkage();
  auto flags = local ? (llvm::DISubprogram::SPFlagDefinition |
                        llvm::DISubprogram::SPFlagLocalToUnit)
                     : llvm::DISubprogram::SPFlagDefinition;
  auto name = source.name + (artificial ? ".frame" : "");
  auto *subprogram = dib.createFunction(
      file, name, function.getName(), file, line, subroutine, line,
      artificial || source.name.starts_with('<') ? llvm::DINode::FlagArtificial
                                                 : llvm::DINode::FlagZero,
      flags);
  function.setSubprogram(subprogram);
  return subprogram;
}

void DebugInfo::begin(llvm::IRBuilder<> &builder,
                      llvm::DISubprogram *subprogram, bool statements) {
  current = subprogram;
  following = statements;
  last = llvm::DILocation::get(module.getContext(),
                               statements ? subprogram->getLine() : 0, 0,
                               subprogram);
  builder.SetCurrentDebugLocation(last);
}

llvm::DILocation *DebugInfo::location(Span span) {
  if (!current)
    return nullptr;
  if (request.sourceSpan)
    span = request.sourceSpan(span);
  auto *found = known(span) ? info(span.source) : nullptr;
  if (!found)
    return last;
  auto [line, column] =
      position(found->lines, std::min(span.begin, found->source->text.size()));
  llvm::DIScope *scope = current;
  // Code expanded from another file keeps the function's subprogram.
  if (found->file != current->getFile()) {
    auto &cached = scopes[{current, span.source}];
    if (!cached)
      cached = dib.createLexicalBlockFile(current, found->file);
    scope = cached;
  }
  last = llvm::DILocation::get(module.getContext(), line, column, scope);
  return last;
}

void DebugInfo::locate(llvm::IRBuilder<> &builder, Span span) {
  if (following)
    builder.SetCurrentDebugLocation(location(span));
}

void DebugInfo::clear(llvm::IRBuilder<> &builder) {
  current = nullptr;
  last = nullptr;
  builder.SetCurrentDebugLocation(llvm::DebugLoc());
}

void DebugInfo::declare(llvm::IRBuilder<> &builder, const ir::Local &local,
                        unsigned argument, bool borrowed,
                        llvm::Value *storage) {
  if (!current)
    return;
  auto *valueType = describe(local.type);
  if (!valueType)
    return;
  if (borrowed)
    valueType = dib.createPointerType(valueType, 64);
  auto span = request.sourceSpan ? request.sourceSpan(local.span) : local.span;
  auto *found = known(span) ? info(span.source) : nullptr;
  auto *file = found ? found->file : current->getFile();
  auto *place = location(local.span);
  auto *variable =
      argument
          ? dib.createParameterVariable(current, local.name, argument, file,
                                        place->getLine(), valueType, true)
          : dib.createAutoVariable(current, local.name, file, place->getLine(),
                                   valueType, true);
  // The slot holds the variable's address: frame fields are not allocas, which
  // a debug declaration needs to survive every code generator.
  auto &entry = builder.GetInsertBlock()->getParent()->getEntryBlock();
  llvm::IRBuilder<> allocation(&entry, entry.begin());
  auto *slot = allocation.CreateAlloca(builder.getPtrTy());
  builder.CreateStore(storage, slot);
  const std::uint64_t dereference[] = {llvm::dwarf::DW_OP_deref};
  static_cast<void>(dib.insertDeclare(slot, variable,
                                      dib.createExpression(dereference), place,
                                      builder.GetInsertBlock()));
}

llvm::DIType *DebugInfo::describe(Type type) {
  if (auto found = types.find(type.index()); found != types.end())
    return found->second;
  if (!building.insert(type.index()).second)
    return nullptr;
  auto *result = build(type);
  building.erase(type.index());
  return types[type.index()] = result;
}

llvm::DIType *DebugInfo::build(Type type) {
  const auto &store = *program.types;
  if (type == Type::Unknown)
    return nullptr;
  const auto layout = objectLayout(store, type);
  if (!layout)
    return nullptr;
  const std::string name(store.name(type));
  const std::uint64_t bits = layout->size * 8;
  const auto alignment = static_cast<std::uint32_t>(layout->alignment * 8);
  if (type == Type::Bool || type == Type::Char || isInteger(type) ||
      isFloating(type))
    return dib.createBasicType(name, bits,
                               type == Type::Bool ? llvm::dwarf::DW_ATE_boolean
                               : type == Type::Char ? llvm::dwarf::DW_ATE_UTF
                               : isFloating(type)   ? llvm::dwarf::DW_ATE_float
                               : isSignedInteger(type)
                                   ? llvm::dwarf::DW_ATE_signed
                                   : llvm::dwarf::DW_ATE_unsigned);
  if (store.isOpaque(type))
    return describe(store.product(type).fields[0].type);
  // Erased values and unsupported representations retain their exact size.
  auto opaque = [&] {
    return dib.createStructType(unit, name, rootFile, 0, bits, alignment,
                                llvm::DINode::FlagZero, nullptr,
                                llvm::DINodeArray());
  };
  if (store.isFunctionPointer(type))
    return dib.createPointerType(nullptr, 64, 0, std::nullopt, name);
  if (store.isView(type) || store.isPointer(type)) {
    auto payload = store.isView(type) ? store.view(type).payload
                                      : store.pointer(type).payload;
    auto metadata = store.pointerMetadata(payload);
    auto pointerBits = store.targetPointerBits();
    if (metadata == PointerMetadata::None)
      return dib.createPointerType(describe(payload), pointerBits, 0,
                                   std::nullopt, name);
    if (metadata != PointerMetadata::ElementCount)
      return opaque();
    auto element = store.isSlice(payload) ? store.slice(payload).element
                                          : payload;
    auto *pointer = dib.createPointerType(describe(element), pointerBits);
    auto *length = describe(Type::Usize);
    std::vector<llvm::Metadata *> members{
        dib.createMemberType(unit, "ptr", rootFile, 0, pointerBits, pointerBits,
                             0, llvm::DINode::FlagZero, pointer),
        dib.createMemberType(unit, "len", rootFile, 0, pointerBits, pointerBits,
                             pointerBits, llvm::DINode::FlagZero, length)};
    return dib.createStructType(unit, name, rootFile, 0, bits, alignment,
                                llvm::DINode::FlagZero, nullptr,
                                dib.getOrCreateArray(members));
  }
  if (!store.isProduct(type))
    return opaque();
  const auto &record = store.product(type);
  if (record.vector || record.layout.unionType)
    return opaque();
  if (record.kind == AggregateKind::Array) {
    auto count = store.arrayLength(type);
    auto *element = describe(record.components.at(0));
    auto stride = objectLayout(store, record.components.at(0));
    if (!count || !element || !stride || stride->size * *count != layout->size)
      return opaque();
    return dib.createArrayType(bits, alignment, element,
                               dib.getOrCreateArray({dib.getOrCreateSubrange(
                                   0, static_cast<std::int64_t>(*count))}));
  }
  if (layout->fields.size() != record.fields.size())
    return opaque();
  auto *temporary = dib.createReplaceableCompositeType(
      llvm::dwarf::DW_TAG_structure_type, name, unit, rootFile, 0, 0, bits,
      alignment);
  types[type.index()] = temporary;
  std::vector<llvm::Metadata *> members;
  if (store.isSum(type) && !record.fields.empty() &&
      record.layout.kind != LayoutKind::Transparent) {
    auto tagIdentity = record.layout.discriminants.empty()
                           ? record.fields[0].type
                           : record.layout.tag;
    auto *tagType = describe(tagIdentity);
    auto tagLayout = objectLayout(store, tagIdentity);
    if (tagType && tagLayout) {
      auto *tag = dib.createMemberType(
          temporary, "discriminant", rootFile, 0, tagLayout->size * 8,
          static_cast<std::uint32_t>(tagLayout->alignment * 8),
          layout->fields[0] * 8, llvm::DINode::FlagZero, tagType);
      std::vector<llvm::Metadata *> variants;
      for (std::size_t index = 0; index < record.variants.size(); ++index) {
        const auto &variant = record.variants[index];
        std::vector<llvm::Metadata *> fields;
        for (auto fieldIndex : variant.fields) {
          const auto &field = record.fields[fieldIndex];
          auto fieldLayout = objectLayout(store, field.type);
          if (auto *member = describe(field.type); member && fieldLayout)
            fields.push_back(dib.createMemberType(
                temporary, field.name, rootFile, 0, fieldLayout->size * 8,
                static_cast<std::uint32_t>(fieldLayout->alignment * 8),
                layout->fields[fieldIndex] * 8, llvm::DINode::FlagZero,
                member));
        }
        auto *payload = dib.createStructType(
            unit, variant.name, rootFile, 0, bits, alignment,
            llvm::DINode::FlagZero, nullptr, dib.getOrCreateArray(fields));
        auto width = static_cast<unsigned>(tagLayout->size * 8);
        llvm::APInt value(width, index);
        if (!record.layout.discriminants.empty()) {
          const auto &literal = record.layout.discriminants[index];
          value = llvm::APInt(128, literal.magnitude).zextOrTrunc(width);
          if (literal.negative)
            value = -value;
        }
        auto *constant = llvm::ConstantInt::get(module.getContext(), value);
        variants.push_back(dib.createVariantMemberType(
            temporary, variant.name, rootFile, 0, bits, alignment, 0, constant,
            llvm::DINode::FlagZero, payload));
      }
      members.push_back(dib.createVariantPart(
          temporary, "", rootFile, 0, bits, alignment, llvm::DINode::FlagZero,
          tag, dib.getOrCreateArray(variants)));
    }
    auto *composite = dib.createStructType(
        unit, name, rootFile, 0, bits, alignment, llvm::DINode::FlagZero,
        nullptr, dib.getOrCreateArray(members));
    return dib.replaceTemporary(llvm::TempMDNode(temporary), composite);
  }
  auto first = store.isSum(type) && record.layout.kind == LayoutKind::Transparent
                   ? 1u
                   : 0u;
  for (std::size_t i = first; i < record.fields.size(); ++i)
    if (auto *member = describe(record.fields[i].type)) {
      const auto &field = record.fields[i];
      auto fieldLayout = objectLayout(store, field.type);
      members.push_back(dib.createMemberType(
          temporary, field.name, rootFile, 0,
          fieldLayout ? fieldLayout->size * 8 : 0,
          fieldLayout ? static_cast<std::uint32_t>(fieldLayout->alignment * 8)
                      : 0,
          layout->fields[i] * 8, llvm::DINode::FlagZero, member));
    }
  auto *composite = dib.createStructType(
      unit, name, rootFile, 0, bits, alignment, llvm::DINode::FlagZero, nullptr,
      dib.getOrCreateArray(members));
  return dib.replaceTemporary(llvm::TempMDNode(temporary), composite);
}

void DebugInfo::finalize() {
  for (auto &function : module) {
    auto *subprogram = function.getSubprogram();
    auto *fallback = subprogram ? llvm::DILocation::get(module.getContext(), 0,
                                                        0, subprogram)
                                : nullptr;
    for (auto &block : function)
      for (auto &instruction : block) {
        auto *location = instruction.getDebugLoc().get();
        if (!subprogram) {
          if (location)
            instruction.setDebugLoc(llvm::DebugLoc());
          continue;
        }
        if (location && location->getScope()->getSubprogram() == subprogram)
          continue;
        // Helper functions the lowering creates mid-function inherit the
        // builder's location; a call without one cannot be inlined.
        if (location || llvm::isa<llvm::CallBase>(instruction))
          instruction.setDebugLoc(fallback);
      }
  }
  dib.finalize();
}
} // namespace mettle::backend
