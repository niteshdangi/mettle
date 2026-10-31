#include "backend/llvm/debug.h"
#include "backend/llvm/cleanup.h"
#include "support/path.h"
#include "types/layout.h"
#include "llvm/ADT/APInt.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Metadata.h"
#include <algorithm>
#include <deque>
#include <iterator>
#include <set>

namespace mettle::backend {
namespace {
bool known(Span span) { return span.begin != 0 || span.end != 0; }

std::pair<unsigned, unsigned> position(const std::vector<std::size_t> &lines,
                                       std::size_t offset) {
  auto next = std::upper_bound(lines.begin(), lines.end(), offset);
  auto line = static_cast<unsigned>(next - lines.begin());
  return {line, static_cast<unsigned>(offset - lines[line - 1] + 1)};
}

std::vector<std::set<int>>
initializedAtSuspensions(const ir::Function &source) {
  // Only expose locals definitely initialized and still in scope on every
  // path to a suspension.
  const auto count = source.blocks.size();
  std::vector<std::vector<int>> predecessors(count);
  auto edge = [&](std::size_t from, int to) {
    if (to >= 0 && static_cast<std::size_t>(to) < count)
      predecessors[to].push_back(static_cast<int>(from));
  };
  for (std::size_t i = 0; i < count; ++i) {
    const auto &exit = source.blocks[i].exit;
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Suspend)
      edge(i, exit.first);
    else if (exit.kind == ir::Exit::Branch) {
      edge(i, exit.first);
      edge(i, exit.second);
    }
  }
  std::vector<bool> reachable(count);
  if (!count)
    return {};
  std::deque<int> work{0};
  reachable[0] = true;
  while (!work.empty()) {
    auto block = work.front();
    work.pop_front();
    for (auto successor :
         {source.blocks[block].exit.first, source.blocks[block].exit.second})
      if (successor >= 0 && static_cast<std::size_t>(successor) < count &&
          !reachable[successor]) {
        reachable[successor] = true;
        work.push_back(successor);
      }
  }

  std::set<int> allScopes;
  for (std::size_t i = 0; i < source.scopes.size(); ++i)
    allScopes.insert(static_cast<int>(i));
  for (const auto &local : source.locals)
    allScopes.insert(local.scope);
  std::set<int> allLocals;
  for (std::size_t i = 0; i < source.locals.size(); ++i)
    allLocals.insert(static_cast<int>(i));
  using State = std::pair<std::set<int>, std::set<int>>;
  std::vector<State> in(count, {allScopes, allLocals});
  std::vector<State> out(count, {allScopes, allLocals});
  std::set<int> entryScopes{0};
  std::set<int> entryLocals;
  for (std::size_t i = 0; i < source.parameters && i < source.locals.size();
       ++i) {
    entryScopes.insert(source.locals[i].scope);
    entryLocals.insert(static_cast<int>(i));
  }
  in[0] = {entryScopes, entryLocals};

  bool changed = true;
  while (changed) {
    changed = false;
    for (std::size_t block = 0; block < count; ++block) {
      if (!reachable[block])
        continue;
      if (block != 0) {
        bool first = true;
        State joined;
        for (auto predecessor : predecessors[block]) {
          if (!reachable[predecessor])
            continue;
          if (first) {
            joined = out[predecessor];
            first = false;
            continue;
          }
          std::set<int> scopes, locals;
          std::set_intersection(joined.first.begin(), joined.first.end(),
                                out[predecessor].first.begin(),
                                out[predecessor].first.end(),
                                std::inserter(scopes, scopes.end()));
          std::set_intersection(joined.second.begin(), joined.second.end(),
                                out[predecessor].second.begin(),
                                out[predecessor].second.end(),
                                std::inserter(locals, locals.end()));
          joined = {std::move(scopes), std::move(locals)};
        }
        if (!first)
          in[block] = std::move(joined);
      }
      auto state = in[block];
      for (const auto &instruction : source.blocks[block].instructions) {
        if (instruction.op == ir::Op::Declare && instruction.place.root >= 0 &&
            static_cast<std::size_t>(instruction.place.root) <
                source.locals.size()) {
          auto root = instruction.place.root;
          state.first.insert(source.locals[root].scope);
          state.second.erase(root);
        } else if (instruction.op == ir::Op::Store &&
                   instruction.place.root >= 0 &&
                   instruction.place.fields.empty() &&
                   static_cast<std::size_t>(instruction.place.root) <
                       source.locals.size()) {
          state.second.insert(instruction.place.root);
        } else if ((instruction.op == ir::Op::Move ||
                    instruction.op == ir::Op::DropPlace) &&
                   instruction.place.root >= 0 &&
                   static_cast<std::size_t>(instruction.place.root) <
                       source.locals.size()) {
          state.second.erase(instruction.place.root);
        } else if (instruction.op == ir::Op::ScopeExit) {
          state.first.erase(instruction.number);
          for (std::size_t i = 0; i < source.locals.size(); ++i)
            if (source.locals[i].scope == instruction.number)
              state.second.erase(static_cast<int>(i));
        }
      }
      if (out[block] != state) {
        out[block] = std::move(state);
        changed = true;
      }
    }
  }

  std::vector<std::set<int>> result(count);
  for (std::size_t block = 0; block < count; ++block)
    if (reachable[block] && source.blocks[block].exit.kind == ir::Exit::Suspend)
      result[block] = out[block].second;
  return result;
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
  auto span =
      request.sourceSpan ? request.sourceSpan(source.span) : source.span;
  if (auto *found = known(span) ? info(span.source) : nullptr) {
    file = found->file;
    line =
        position(found->lines, std::min(span.begin, found->source->text.size()))
            .first;
  }
  auto local = function.hasLocalLinkage();
  auto flags = local ? (llvm::DISubprogram::SPFlagDefinition |
                        llvm::DISubprogram::SPFlagLocalToUnit)
                     : llvm::DISubprogram::SPFlagDefinition;
  auto name = displayPath(source.name) + (artificial ? ".frame" : "");
  auto *subprogram = dib.createFunction(
      file, name, function.getName(), file, line, subroutine, line,
      artificial || source.name.starts_with('<') ? llvm::DINode::FlagArtificial
                                                 : llvm::DINode::FlagZero,
      flags);
  function.setSubprogram(subprogram);
  return subprogram;
}

void DebugInfo::begin(llvm::IRBuilder<> &builder,
                      llvm::DISubprogram *subprogram,
                      const ir::Function *source, bool statements) {
  current = subprogram;
  following = statements;
  variables.clear();
  lexicalScopes.clear();
  lexicalScopes.push_back(subprogram);
  if (source && statements) {
    lexicalScopes.resize(source->scopes.size(), nullptr);
    lexicalScopes[0] = subprogram;
    std::vector<Span> spans(source->scopes.size());
    auto remember = [&](int index, Span span) {
      if (index < 0)
        return;
      auto slot = static_cast<std::size_t>(index);
      if (slot < spans.size() && !known(spans[slot]) && known(span))
        spans[slot] = span;
    };
    for (const auto &local : source->locals)
      remember(local.scope, local.span);
    for (const auto &block : source->blocks)
      for (const auto &instruction : block.instructions)
        remember(instruction.scope, instruction.span);
    for (std::size_t index = 1; index < lexicalScopes.size(); ++index) {
      auto parent = source->scopes[index].parent;
      if (parent < 0 || static_cast<std::size_t>(parent) >= index)
        continue;
      auto *parentScope = lexicalScopes[static_cast<std::size_t>(parent)];
      auto span =
          request.sourceSpan ? request.sourceSpan(spans[index]) : spans[index];
      auto *found = known(span) ? info(span.source) : nullptr;
      if (parentScope && found) {
        auto [line, column] = position(
            found->lines, std::min(span.begin, found->source->text.size()));
        lexicalScopes[index] =
            dib.createLexicalBlock(parentScope, found->file, line, column);
      } else
        lexicalScopes[index] = parentScope;
    }
  }
  last = llvm::DILocation::get(module.getContext(),
                               statements ? subprogram->getLine() : 0, 0,
                               subprogram);
  builder.SetCurrentDebugLocation(last);
}

llvm::DILocalScope *DebugInfo::scope(int index) const {
  if (index >= 0) {
    auto slot = static_cast<std::size_t>(index);
    if (slot < lexicalScopes.size() && lexicalScopes[slot])
      return lexicalScopes[slot];
  }
  return current;
}

llvm::DILocation *DebugInfo::location(Span span, int scopeIndex) {
  if (!current)
    return nullptr;
  if (request.sourceSpan)
    span = request.sourceSpan(span);
  auto *locationScope = scope(scopeIndex);
  auto *found = known(span) ? info(span.source) : nullptr;
  if (!found)
    return last;
  auto [line, column] =
      position(found->lines, std::min(span.begin, found->source->text.size()));
  // Code expanded from another file retains its lexical ancestry.
  if (found->file != locationScope->getFile()) {
    auto &cached = scopes[{locationScope, span.source}];
    if (!cached)
      cached = dib.createLexicalBlockFile(locationScope, found->file);
    locationScope = cached;
  }
  last =
      llvm::DILocation::get(module.getContext(), line, column, locationScope);
  return last;
}

void DebugInfo::locate(llvm::IRBuilder<> &builder, Span span, int scopeIndex) {
  if (following)
    builder.SetCurrentDebugLocation(location(span, scopeIndex));
}

void DebugInfo::clear(llvm::IRBuilder<> &builder) {
  current = nullptr;
  last = nullptr;
  builder.SetCurrentDebugLocation(llvm::DebugLoc());
}

void DebugInfo::declare(llvm::IRBuilder<> &builder, std::size_t index,
                        const ir::Local &local, unsigned argument,
                        bool borrowed, llvm::Value *storage) {
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
  auto *variableScope = scope(local.scope);
  auto *place = location(local.span, local.scope);
  auto *variable =
      argument
          ? dib.createParameterVariable(variableScope, local.name, argument,
                                        file, place->getLine(), valueType, true)
          : dib.createAutoVariable(variableScope, local.name, file,
                                   place->getLine(), valueType, true);
  variables[index] = variable;
  if (!dereference) {
    const std::uint64_t operation[] = {llvm::dwarf::DW_OP_deref};
    dereference = dib.createExpression(operation);
  }
  if (argument || local.storage == StorageDuration::Static) {
    // The slot holds the variable's address: frame fields are not allocas,
    // which a debug declaration needs to survive every code generator.
    auto &entry = builder.GetInsertBlock()->getParent()->getEntryBlock();
    llvm::IRBuilder<> allocation(&entry, entry.begin());
    auto *slot = allocation.CreateAlloca(builder.getPtrTy());
    builder.CreateStore(storage, slot);
    static_cast<void>(dib.insertDeclare(slot, variable, dereference, place,
                                        builder.GetInsertBlock()));
  } else
    static_cast<void>(dib.insertDbgValueIntrinsic(
        llvm::UndefValue::get(builder.getPtrTy()), variable, dereference, place,
        builder.GetInsertBlock()));
}

void DebugInfo::invalidate(llvm::IRBuilder<> &builder, std::size_t index,
                           Span span, int scopeIndex) {
  auto found = variables.find(index);
  if (found == variables.end())
    return;
  if (!dereference) {
    const std::uint64_t operation[] = {llvm::dwarf::DW_OP_deref};
    dereference = dib.createExpression(operation);
  }
  static_cast<void>(dib.insertDbgValueIntrinsic(
      llvm::UndefValue::get(builder.getPtrTy()), found->second, dereference,
      location(span, scopeIndex), builder.GetInsertBlock()));
}

void DebugInfo::restore(llvm::IRBuilder<> &builder, std::size_t index,
                        Span span, int scopeIndex, llvm::Value *storage) {
  auto found = variables.find(index);
  if (found == variables.end())
    return;
  if (!dereference) {
    const std::uint64_t operation[] = {llvm::dwarf::DW_OP_deref};
    dereference = dib.createExpression(operation);
  }
  static_cast<void>(dib.insertDbgValueIntrinsic(
      storage, found->second, dereference, location(span, scopeIndex),
      builder.GetInsertBlock()));
}

void DebugInfo::endScope(llvm::IRBuilder<> &builder, const ir::Function &source,
                         int scopeIndex, Span span) {
  for (std::size_t index = 0; index < source.locals.size(); ++index)
    if (source.locals[index].scope == scopeIndex)
      invalidate(builder, index, span, scopeIndex);
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
  if (store.isProduct(type) &&
      store.product(type).kind == AggregateKind::Coroutine) {
    if (auto found = types.find(type.index()); found != types.end())
      return found->second;
  }
  std::string name = displayPath(store.name(type));
  // Views of erased interfaces read as written: `read any I`.
  if (store.isView(type) && store.isErased(store.view(type).payload))
    name.insert(name.find(' ') + 1, "any ");
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
    if (metadata != PointerMetadata::ElementCount &&
        metadata != PointerMetadata::Witness)
      return opaque();
    const auto metadataFields =
        metadata == PointerMetadata::ElementCount ? 2u : 3u;
    if (layout->fields.size() != metadataFields)
      return opaque();
    auto element =
        store.isSlice(payload) ? store.slice(payload).element : payload;
    auto *pointee =
        metadata == PointerMetadata::ElementCount ? describe(element) : nullptr;
    if (metadata == PointerMetadata::ElementCount && !pointee)
      return opaque();
    auto *pointer = dib.createPointerType(pointee, pointerBits);
    auto *length = describe(Type::Usize);
    std::vector<llvm::Metadata *> members;
    members.push_back(dib.createMemberType(
        unit, "data_ptr", rootFile, 0, pointerBits, pointerBits,
        layout->fields[0] * 8, llvm::DINode::FlagZero, pointer));
    auto lengthLayout = objectLayout(store, Type::Usize);
    if (!length || !lengthLayout)
      return opaque();
    members.push_back(dib.createMemberType(
        unit,
        metadata == PointerMetadata::ElementCount ? "length" : "alignment",
        rootFile, 0, lengthLayout->size * 8,
        static_cast<std::uint32_t>(lengthLayout->alignment * 8),
        layout->fields[1] * 8, llvm::DINode::FlagZero, length));
    if (metadata == PointerMetadata::Witness) {
      auto erased = payload;
      while (!store.isErased(erased) && store.isProduct(erased) &&
             !store.product(erased).fields.empty())
        erased = store.product(erased).fields.back().type;
      if (!store.isErased(erased))
        return opaque();
      const auto &descriptor = store.erased(erased);
      auto *pointer = dib.createPointerType(nullptr, pointerBits);
      auto tableLength = 2 + descriptor.methodSlots.size() +
                         descriptor.parentInterfaces.size();
      auto tableBits = static_cast<std::uint64_t>(tableLength) * pointerBits;
      std::vector<llvm::Metadata *> tableMembers;
      tableMembers.push_back(dib.createMemberType(
          unit, "metadata_marker", rootFile, 0, pointerBits, pointerBits, 0,
          llvm::DINode::FlagZero, pointer));
      tableMembers.push_back(dib.createMemberType(
          unit, "alignment", rootFile, 0, lengthLayout->size * 8,
          static_cast<std::uint32_t>(lengthLayout->alignment * 8), pointerBits,
          llvm::DINode::FlagZero, length));
      for (std::size_t method = 0; method < descriptor.methodSlots.size();
           ++method)
        tableMembers.push_back(dib.createMemberType(
            unit, "method." + std::to_string(method), rootFile, 0, pointerBits,
            pointerBits, (method + 2) * pointerBits, llvm::DINode::FlagZero,
            pointer));
      for (std::size_t parent = 0; parent < descriptor.parentInterfaces.size();
           ++parent)
        tableMembers.push_back(dib.createMemberType(
            unit,
            "parent." +
                displayPath(store.name(descriptor.parentInterfaces[parent])),
            rootFile, 0, pointerBits, pointerBits,
            (descriptor.methodSlots.size() + parent + 2) * pointerBits,
            llvm::DINode::FlagZero, pointer));
      auto *table = dib.createStructType(
          unit, "MettleWitness<" + displayPath(store.name(erased)) + ">",
          rootFile, 0, tableBits, pointerBits, llvm::DINode::FlagZero, nullptr,
          dib.getOrCreateArray(tableMembers));
      members.push_back(dib.createMemberType(
          unit, "witness", rootFile, 0, pointerBits, pointerBits,
          layout->fields[2] * 8, llvm::DINode::FlagZero,
          dib.createPointerType(table, pointerBits)));
    }
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
    auto tagIdentity = record.layout.tag;
    auto *tagType = describe(tagIdentity);
    auto tagLayout = objectLayout(store, tagIdentity);
    if (tagType && tagLayout && !layout->fields.empty()) {
      auto *tag = dib.createMemberType(
          temporary, "discriminant", rootFile, 0, tagLayout->size * 8,
          static_cast<std::uint32_t>(tagLayout->alignment * 8),
          layout->fields[0] * 8, llvm::DINode::FlagZero, tagType);
      std::vector<llvm::Metadata *> variants;
      auto payloadOffset = layout->size;
      for (const auto &variant : record.variants)
        for (auto fieldIndex : variant.fields)
          payloadOffset = std::min(payloadOffset, layout->fields[fieldIndex]);
      for (std::size_t index = 0; index < record.variants.size(); ++index) {
        const auto &variant = record.variants[index];
        std::vector<llvm::Metadata *> fields;
        auto variantOffset = layout->size;
        for (auto fieldIndex : variant.fields)
          variantOffset = std::min(variantOffset, layout->fields[fieldIndex]);
        if (variant.fields.empty())
          variantOffset = payloadOffset;
        const auto variantBits = (layout->size - variantOffset) * 8;
        auto *payloadTemporary = dib.createReplaceableCompositeType(
            llvm::dwarf::DW_TAG_structure_type, variant.name, unit, rootFile, 0,
            0, variantBits, alignment);
        for (auto fieldIndex : variant.fields) {
          const auto &field = record.fields[fieldIndex];
          auto fieldLayout = objectLayout(store, field.type);
          if (auto *member = describe(field.type); member && fieldLayout)
            fields.push_back(dib.createMemberType(
                payloadTemporary, field.name, rootFile, 0,
                fieldLayout->size * 8,
                static_cast<std::uint32_t>(fieldLayout->alignment * 8),
                (layout->fields[fieldIndex] - variantOffset) * 8,
                llvm::DINode::FlagZero, member));
        }
        auto *payloadComposite = dib.createStructType(
            unit, variant.name, rootFile, 0, variantBits, alignment,
            llvm::DINode::FlagZero, nullptr, dib.getOrCreateArray(fields));
        auto *payload = dib.replaceTemporary(llvm::TempMDNode(payloadTemporary),
                                             payloadComposite);
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
            temporary, variant.name, rootFile, 0, variantBits, alignment,
            variantOffset * 8, constant, llvm::DINode::FlagZero, payload));
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
  auto first =
      store.isSum(type) && record.layout.kind == LayoutKind::Transparent ? 1u
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

void DebugInfo::describeCoroutine(Type type, const ir::Function &source,
                                  llvm::StructType *frame, unsigned stateField,
                                  unsigned outputField,
                                  const std::vector<unsigned> &localFields) {
  if (!frame || !frame->isSized())
    return;
  const auto &store = *program.types;
  const auto name = displayPath(store.name(type));
  const auto &dataLayout = module.getDataLayout();
  const auto *frameLayout = dataLayout.getStructLayout(frame);
  const auto frameBits = dataLayout.getTypeAllocSize(frame).getFixedValue() * 8;
  const auto frameAlignment =
      static_cast<std::uint32_t>(dataLayout.getABITypeAlign(frame).value() * 8);
  auto *temporary = dib.createReplaceableCompositeType(
      llvm::dwarf::DW_TAG_structure_type, name, unit, rootFile, 0, 0, frameBits,
      frameAlignment);
  types[type.index()] = temporary;

  struct Suspension {
    std::int32_t state;
    std::string name;
    std::size_t block;
  };
  std::vector<Suspension> suspensions;
  std::int32_t index = 0;
  for (std::size_t block = 0; block < source.blocks.size(); ++block) {
    const auto &exit = source.blocks[block].exit;
    if (exit.kind != ir::Exit::Suspend)
      continue;
    auto span = request.sourceSpan ? request.sourceSpan(exit.span) : exit.span;
    unsigned line = 0;
    if (known(span))
      if (auto *found = info(span.source))
        line = position(found->lines,
                        std::min(span.begin, found->source->text.size()))
                   .first;
    ++index;
    suspensions.push_back({index,
                           "await #" + std::to_string(index) + " (line " +
                               std::to_string(line) + ")",
                           block});
  }

  std::vector<std::pair<std::int32_t, std::string>> states{{0, "start"}};
  for (const auto &suspension : suspensions)
    states.emplace_back(suspension.state, suspension.name);
  constexpr std::int32_t running = CleanupFrame::running;
  constexpr std::int32_t complete = CleanupFrame::complete;
  states.emplace_back(running, "running");
  states.emplace_back(complete, "done");
  std::vector<llvm::Metadata *> enumerators;
  for (const auto &[value, label] : states) {
    enumerators.push_back(
        dib.createEnumerator(label, static_cast<std::uint64_t>(value), false));
  }
  auto *stateType = dib.createEnumerationType(
      unit, name + ".ResumeState", rootFile, 0, 32, 32,
      dib.getOrCreateArray(enumerators), describe(Type::I32), true);
  auto *stateMember =
      dib.createMemberType(temporary, "state", rootFile, 0, 32, 32,
                           frameLayout->getElementOffset(stateField) * 8,
                           llvm::DINode::FlagZero, stateType);

  auto member = [&](std::vector<llvm::Metadata *> &members,
                    llvm::DIScope *scope, const std::string &fieldName,
                    Type fieldType, unsigned physicalField, bool borrowed,
                    Span span) {
    auto *debugType = describe(fieldType);
    if (!debugType)
      return;
    auto fieldLayout = objectLayout(store, fieldType);
    auto size = fieldLayout ? fieldLayout->size * 8 : 0;
    auto alignment =
        fieldLayout ? static_cast<std::uint32_t>(fieldLayout->alignment * 8)
                    : 0;
    if (borrowed) {
      debugType = dib.createPointerType(debugType, store.targetPointerBits());
      size = store.targetPointerBits();
      alignment = store.targetPointerBits();
    }
    auto sourceSpan = request.sourceSpan ? request.sourceSpan(span) : span;
    auto *file = rootFile;
    unsigned line = 0;
    if (known(sourceSpan))
      if (auto *found = info(sourceSpan.source)) {
        file = found->file;
        line = position(found->lines,
                        std::min(sourceSpan.begin, found->source->text.size()))
                   .first;
      }
    members.push_back(
        dib.createMemberType(scope, fieldName, file, line, size, alignment,
                             frameLayout->getElementOffset(physicalField) * 8,
                             llvm::DINode::FlagZero, debugType));
  };

  std::vector<llvm::Metadata *> members{stateMember};
  for (std::size_t i = 0; i < source.parameters && i < source.locals.size() &&
                          i < localFields.size();
       ++i) {
    const auto &local = source.locals[i];
    bool borrowed = local.storage == StorageDuration::Static ||
                    local.mode == ParameterMode::Read ||
                    local.mode == ParameterMode::Mut;
    member(members, temporary, i == 0 ? "captures" : local.name, local.type,
           localFields[i], borrowed, local.span);
  }

  const auto initialized = initializedAtSuspensions(source);
  auto variant = [&](const std::string &label, std::int32_t value,
                     const std::set<int> *saved, bool output) {
    std::vector<llvm::Metadata *> fields;
    auto *payloadTemporary = dib.createReplaceableCompositeType(
        llvm::dwarf::DW_TAG_structure_type, label, unit, rootFile, 0, 0,
        frameBits, frameAlignment);
    if (saved)
      for (auto localIndex : *saved) {
        if (localIndex < static_cast<int>(source.parameters) ||
            static_cast<std::size_t>(localIndex) >= source.locals.size() ||
            static_cast<std::size_t>(localIndex) >= localFields.size())
          continue;
        const auto &local = source.locals[localIndex];
        bool borrowed =
            local.storage == StorageDuration::Static ||
            (static_cast<std::size_t>(localIndex) < source.parameters &&
             (local.mode == ParameterMode::Read ||
              local.mode == ParameterMode::Mut));
        member(fields, payloadTemporary, local.name, local.type,
               localFields[localIndex], borrowed, local.span);
      }
    if (output && source.result != Type::Unit && source.result != Type::Never &&
        outputField < frame->getNumElements())
      member(fields, payloadTemporary, "output", source.result, outputField,
             false, source.span);
    auto *payloadComposite = dib.createStructType(
        unit, label, rootFile, 0, frameBits, frameAlignment,
        llvm::DINode::FlagZero, nullptr, dib.getOrCreateArray(fields));
    auto *payload = dib.replaceTemporary(llvm::TempMDNode(payloadTemporary),
                                         payloadComposite);
    llvm::APInt tag(32, static_cast<std::uint64_t>(value), true);
    auto *constant = llvm::ConstantInt::get(module.getContext(), tag);
    return dib.createVariantMemberType(temporary, label, rootFile, 0, frameBits,
                                       frameAlignment, 0, constant,
                                       llvm::DINode::FlagZero, payload);
  };

  std::vector<llvm::Metadata *> variants;
  variants.push_back(variant("start", 0, nullptr, false));
  for (const auto &suspension : suspensions) {
    const auto *saved = suspension.block < initialized.size()
                            ? &initialized[suspension.block]
                            : nullptr;
    variants.push_back(
        variant(suspension.name, suspension.state, saved, false));
  }
  variants.push_back(variant("running", running, nullptr, false));
  variants.push_back(variant("done", complete, nullptr, true));
  members.push_back(dib.createVariantPart(
      temporary, "", rootFile, 0, frameBits, frameAlignment,
      llvm::DINode::FlagZero, stateMember, dib.getOrCreateArray(variants)));
  auto *composite = dib.createStructType(
      unit, name, rootFile, 0, frameBits, frameAlignment,
      llvm::DINode::FlagZero, nullptr, dib.getOrCreateArray(members));
  types[type.index()] =
      dib.replaceTemporary(llvm::TempMDNode(temporary), composite);
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
