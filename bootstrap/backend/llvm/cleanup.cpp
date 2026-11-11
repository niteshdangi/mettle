#include "backend/llvm/cleanup.h"

#include "llvm/IR/Intrinsics.h"
#include "llvm/Support/ErrorHandling.h"
#include <algorithm>
#include <limits>

namespace mettle::backend {
const ObjectLayout &LoweringContext::layout(Type type) {
  if (auto found = layouts.find(type.index()); found != layouts.end())
    return found->second;
  auto result = objectLayout(*program.types, type);
  if (!result)
    llvm::report_fatal_error("unresolved object layout reached LLVM");
  return layouts.emplace(type.index(), std::move(*result)).first->second;
}
std::uint64_t LoweringContext::alignment(Type type) {
  return layout(type).alignment;
}
bool LoweringContext::indirect(Type valueType) {
  if (!program.types->isProduct(valueType))
    return false;
  if (program.types->isOpaque(valueType))
    return indirect(program.types->product(valueType).fields[0].type);
  if (program.types->product(valueType).vector ||
      !program.types->isSized(valueType) ||
      program.types->pointerMetadata(valueType) != PointerMetadata::None)
    return false;
  if (auto found = indirects.find(valueType.index()); found != indirects.end())
    return found->second;
  return indirects
      .emplace(valueType.index(), layout(valueType).size > indirectThreshold)
      .first->second;
}
Type LoweringContext::fieldType(Type owner, unsigned field) {
  const auto &record = program.types->product(owner);
  return record.kind == AggregateKind::Array ? record.components[0]
                                             : record.fields.at(field).type;
}
std::uint64_t LoweringContext::fieldOffset(Type owner, unsigned field) {
  return program.types->compactArray(owner)
             ? field * layout(program.types->product(owner).components[0]).size
             : layout(owner).fields.at(field);
}
llvm::Value *LoweringContext::zero(Type valueType) {
  if (!indirect(valueType))
    return llvm::Constant::getNullValue(type(valueType));
  auto *storage = temporary(valueType);
  builder.CreateMemSet(storage, builder.getInt8(0), layout(valueType).size,
                       llvm::Align(alignment(valueType)));
  return storage;
}
llvm::Type *LoweringContext::storageType(Type valueType) {
  if (program.types->isOpaque(valueType))
    return storageType(program.types->product(valueType).fields[0].type);
  if (indirect(valueType))
    return layoutType(valueType);
  return valueType == Type::Bool ? builder.getInt8Ty() : type(valueType);
}
llvm::Value *LoweringContext::load(Type valueType, llvm::Value *address,
                                   llvm::Align alignment, bool isVolatile) {
  if (indirect(valueType)) {
    auto *copy = temporary(valueType);
    builder.CreateMemCpy(copy, copy->getAlign(), address, alignment,
                         layout(valueType).size, isVolatile);
    return copy;
  }
  auto *loaded =
      builder.CreateAlignedLoad(storageType(valueType), address, alignment);
  loaded->setVolatile(isVolatile);
  return loaded->getType() == type(valueType)
             ? loaded
             : builder.CreateTrunc(loaded, type(valueType));
}
void LoweringContext::store(Type valueType, llvm::Value *value,
                            llvm::Value *address, llvm::Align alignment,
                            bool isVolatile) {
  if (indirect(valueType)) {
    if (value == address && !isVolatile)
      return;
    builder.CreateMemMove(address, alignment, value,
                          llvm::Align(this->alignment(valueType)),
                          layout(valueType).size, isVolatile);
    return;
  }
  if (value->getType() != storageType(valueType))
    value = builder.CreateZExt(value, storageType(valueType));
  builder.CreateAlignedStore(value, address, alignment)
      ->setVolatile(isVolatile);
}
llvm::Type *LoweringContext::viewType(Type payload) {
  auto metadata = program.types->pointerMetadata(payload);
  if (metadata == PointerMetadata::ElementCount)
    return llvm::StructType::get(context,
                                 {builder.getPtrTy(), builder.getInt64Ty()});
  if (metadata == PointerMetadata::Witness)
    return llvm::StructType::get(
        context,
        {builder.getPtrTy(), builder.getInt64Ty(), builder.getPtrTy()});
  if (metadata == PointerMetadata::Dependent)
    llvm::report_fatal_error("uninstantiated pointer metadata reached LLVM");
  return builder.getPtrTy();
}
llvm::AllocaInst *LoweringContext::temporary(llvm::Type *type) {
  auto &entry = builder.GetInsertBlock()->getParent()->getEntryBlock();
  llvm::IRBuilder<> allocation(&entry, entry.begin());
  return allocation.CreateAlloca(type);
}
llvm::AllocaInst *LoweringContext::temporary(Type valueType) {
  auto *result = temporary(layoutType(valueType));
  result->setAlignment(llvm::Align(alignment(valueType)));
  return result;
}
llvm::Value *LoweringContext::fieldPointer(llvm::Value *address, Type owner,
                                           unsigned index) {
  if (program.types->isOpaque(owner))
    return address;
  if (customRepresentation(*program.types, owner))
    return builder.CreateGEP(builder.getInt8Ty(), address,
                             builder.getInt64(fieldOffset(owner, index)));
  return builder.CreateStructGEP(layoutType(owner), address, index);
}
llvm::Value *LoweringContext::construct(Type valueType,
                                        llvm::ArrayRef<llvm::Value *> values,
                                        unsigned selected) {
  if (!customRepresentation(*program.types, valueType) &&
      !indirect(valueType)) {
    auto *aggregate = type(valueType);
    std::vector<llvm::Value *> physicalValues;
    bool constant = true;
    for (unsigned i = 0; i < values.size(); ++i) {
      auto *physical =
          storageType(program.types->product(valueType).fields[i].type);
      auto *value = values[i]->getType() == physical
                        ? values[i]
                        : builder.CreateZExt(values[i], physical);
      constant &= llvm::isa<llvm::Constant>(value);
      physicalValues.push_back(value);
    }
    auto *record = llvm::dyn_cast<llvm::StructType>(aggregate);
    // Folding one insertvalue at a time rebuilds the constant per element.
    if (constant && record && record->getNumElements() == values.size()) {
      std::vector<llvm::Constant *> elements;
      for (auto *value : physicalValues)
        elements.push_back(llvm::cast<llvm::Constant>(value));
      return llvm::ConstantStruct::get(record, elements);
    }
    llvm::Value *result = llvm::Constant::getNullValue(aggregate);
    for (unsigned i = 0; i < physicalValues.size(); ++i)
      result = builder.CreateInsertValue(result, physicalValues[i], i);
    return result;
  }
  auto *storage = temporary(valueType);
  if (indirect(valueType))
    builder.CreateMemSet(storage, builder.getInt8(0), layout(valueType).size,
                         storage->getAlign());
  else
    builder.CreateStore(llvm::Constant::getNullValue(layoutType(valueType)),
                        storage);
  for (unsigned i = 0; i < values.size(); ++i) {
    auto field =
        program.types->product(valueType).layout.unionType ? selected : i;
    store(fieldType(valueType, field), values[i],
          fieldPointer(storage, valueType, field), llvm::Align(1));
  }
  return indirect(valueType)
             ? static_cast<llvm::Value *>(storage)
             : builder.CreateLoad(layoutType(valueType), storage);
}
llvm::Value *LoweringContext::extract(llvm::Value *value, Type owner,
                                      unsigned field) {
  if (program.types->isOpaque(owner))
    return value;
  if (indirect(owner)) {
    if (program.types->isSum(owner) && field == 0 &&
        !program.types->product(owner).layout.discriminants.empty())
      return enumTag(owner, value);
    return load(fieldType(owner, field), fieldPointer(value, owner, field),
                llvm::Align(1));
  }
  if (program.types->isSum(owner) && field == 0 &&
      !program.types->product(owner).layout.discriminants.empty()) {
    auto *storage = temporary(owner);
    builder.CreateStore(value, storage);
    return enumTag(owner, storage);
  }
  if (!customRepresentation(*program.types, owner)) {
    auto *result = builder.CreateExtractValue(value, field);
    auto *target = type(program.types->product(owner).fields[field].type);
    return result->getType() == target ? result
                                       : builder.CreateTrunc(result, target);
  }
  auto *storage = temporary(owner);
  builder.CreateStore(value, storage);
  return load(fieldType(owner, field), fieldPointer(storage, owner, field),
              llvm::Align(1));
}
llvm::Value *LoweringContext::enumTag(Type owner, llvm::Value *address,
                                      bool ordinal) {
  const auto &record = program.types->product(owner);
  const auto &representation = record.layout;
  if (representation.kind == LayoutKind::Transparent)
    return builder.getInt32(0);
  auto *tag = builder.CreateAlignedLoad(type(representation.tag), address,
                                        llvm::Align(1));
  if (!ordinal || representation.discriminants.empty())
    return tag;
  llvm::Value *result = llvm::PoisonValue::get(builder.getInt32Ty());
  for (std::size_t i = 0; i < representation.discriminants.size(); ++i) {
    const auto &value = representation.discriminants[i];
    llvm::APInt bits(
        integerWidth(representation.tag),
        llvm::ArrayRef<std::uint64_t>(value.magnitude)
            .take_front(integerWidth(representation.tag) > 64 ? 2 : 1));
    if (value.negative)
      bits = -bits;
    result = builder.CreateSelect(
        builder.CreateICmpEQ(tag, llvm::ConstantInt::get(context, bits)),
        builder.getInt32(i), result);
  }
  return result;
}
llvm::Value *LoweringContext::variant(Type owner, unsigned ordinal,
                                      llvm::ArrayRef<llvm::Value *> values) {
  const auto &record = program.types->product(owner);
  if (record.layout.discriminants.empty()) {
    std::vector<llvm::Value *> fields;
    for (const auto &field : record.fields)
      fields.push_back(zero(field.type));
    fields[0] = builder.getInt32(ordinal);
    for (std::size_t i = 0; i < values.size(); ++i)
      fields[record.variants[ordinal].fields[i]] = values[i];
    return construct(owner, fields);
  }
  auto *storage = temporary(owner);
  if (indirect(owner))
    builder.CreateMemSet(storage, builder.getInt8(0), layout(owner).size,
                         storage->getAlign());
  else
    builder.CreateStore(llvm::Constant::getNullValue(layoutType(owner)),
                        storage);
  if (record.layout.kind != LayoutKind::Transparent) {
    const auto &discriminant = record.layout.discriminants[ordinal];
    llvm::APInt bits(
        integerWidth(record.layout.tag),
        llvm::ArrayRef<std::uint64_t>(discriminant.magnitude)
            .take_front(integerWidth(record.layout.tag) > 64 ? 2 : 1));
    if (discriminant.negative)
      bits = -bits;
    builder.CreateAlignedStore(llvm::ConstantInt::get(context, bits), storage,
                               llvm::Align(1));
  }
  for (std::size_t i = 0; i < values.size(); ++i) {
    auto field = record.variants[ordinal].fields[i];
    store(record.fields[field].type, values[i],
          fieldPointer(storage, owner, field), llvm::Align(1));
  }
  return indirect(owner) ? static_cast<llvm::Value *>(storage)
                         : builder.CreateLoad(layoutType(owner), storage);
}
llvm::Type *LoweringContext::type(Type typeId) {
  return indirect(typeId) ? static_cast<llvm::Type *>(builder.getPtrTy())
                          : layoutType(typeId);
}
llvm::Type *LoweringContext::layoutType(Type typeId) {
  if (isInteger(typeId) || typeId == Type::Char)
    return builder.getIntNTy(integerWidth(typeId));
  if (isFloating(typeId))
    return typeId == Type::F32 ? builder.getFloatTy() : builder.getDoubleTy();
  if (typeId == Type::Bool)
    return builder.getInt1Ty();
  if (typeId == Type::Unit || typeId == Type::Never)
    return llvm::StructType::get(context);
  if (program.types->isOpaque(typeId))
    return layoutType(program.types->product(typeId).fields[0].type);
  if (program.types->isErased(typeId))
    return viewType(typeId);
  if (program.types->isView(typeId))
    return viewType(program.types->view(typeId).payload);
  if (program.types->isPointer(typeId))
    return viewType(program.types->pointer(typeId).payload);
  if (program.types->isSlice(typeId))
    return llvm::ArrayType::get(
        layoutType(program.types->slice(typeId).element), 0);
  if (program.types->isFunctionPointer(typeId))
    return builder.getPtrTy();
  if (program.types->isProduct(typeId) &&
      program.types->product(typeId).vector) {
    const auto &shape = *program.types->product(typeId).vector;
    return llvm::FixedVectorType::get(type(shape.element), shape.lanes);
  }
  if (customRepresentation(*program.types, typeId))
    return llvm::ArrayType::get(builder.getInt8Ty(), layout(typeId).size);
  if (auto found = products.find(typeId.index()); found != products.end())
    return found->second;
  if (program.types->product(typeId).kind == AggregateKind::Coroutine)
    return coroutine(typeId).structure();
  const auto &product = program.types->product(typeId);
  auto *result =
      llvm::StructType::create(context, "mettle.type." + product.name);
  products[typeId.index()] = result;
  std::vector<llvm::Type *> members;
  for (std::size_t field = 0; field < product.fields.size(); ++field) {
    auto member = product.fields[field].type;
    bool dynamicTail =
        field + 1 == product.fields.size() && !program.types->isSized(member) &&
        program.types->pointerMetadata(member) == PointerMetadata::Witness;
    members.push_back(dynamicTail ? llvm::ArrayType::get(builder.getInt8Ty(), 0)
                                  : storageType(member));
  }
  result->setBody(members);
  return result;
}

llvm::Type *LoweringContext::resultType(Type typeId) {
  return typeId == Type::Unit || typeId == Type::Never || indirect(typeId)
             ? builder.getVoidTy()
             : type(typeId);
}

llvm::FunctionCallee
LoweringContext::runtime(llvm::StringRef name, llvm::Type *result,
                         llvm::ArrayRef<llvm::Type *> parameters) {
  return module.getOrInsertFunction(
      name, llvm::FunctionType::get(result, parameters, false));
}

llvm::Function *LoweringContext::callback(const llvm::Twine &name,
                                          bool cleanup) {
  std::vector<llvm::Type *> parameters{builder.getPtrTy()};
  if (cleanup)
    parameters.push_back(builder.getInt32Ty());
  auto *function = llvm::Function::Create(
      llvm::FunctionType::get(builder.getVoidTy(), parameters, false),
      llvm::GlobalValue::InternalLinkage, name, module);
  function->setUWTableKind(llvm::UWTableKind::Default);
  if (freestanding)
    function->addFnAttr(llvm::Attribute::NoUnwind);
  return function;
}

unsigned CleanupFrame::addField(llvm::Type *type, std::uint64_t alignment) {
  auto natural = lowering.module.getDataLayout().getABITypeAlign(type).value();
  alignment = std::max(alignment, natural);
  auto offset = (frameSize + alignment - 1) & ~(alignment - 1);
  if (offset > frameSize)
    fields.push_back(
        llvm::ArrayType::get(lowering.builder.getInt8Ty(), offset - frameSize));
  unsigned index = fields.size();
  fields.push_back(type);
  frameSize =
      offset +
      lowering.module.getDataLayout().getTypeAllocSize(type).getFixedValue();
  frameAlignment = std::max(frameAlignment, alignment);
  return index;
}

unsigned CleanupFrame::addNode(const cleanup::Plan &sourcePlan, int place,
                               unsigned root, int parent,
                               std::vector<unsigned> path) {
  const auto &planned = sourcePlan.places[place];
  unsigned index = nodes.size();
  nodes.push_back({planned.type,
                   planned.destructor,
                   root,
                   addField(lowering.builder.getInt1Ty()),
                   parent,
                   path,
                   {}});
  nodes[index].nativeAction = planned.nativeAction;
  if (planned.destructor >= 0 || planned.nativeAction != NativeCleanup::None) {
    auto type = roots[root].type;
    auto alignment = lowering.alignment(type);
    for (auto field : path) {
      auto offset = lowering.layout(type).fields.at(field);
      if (offset)
        alignment = std::min(alignment, offset & (~offset + 1));
      type = lowering.program.types->product(type).fields[field].type;
    }
    if (alignment < lowering.alignment(planned.type)) {
      nodes[index].relocation = addField(lowering.layoutType(planned.type),
                                         lowering.alignment(planned.type));
      nodes[index].relocatedFlag = addField(lowering.builder.getInt1Ty());
    }
  }
  if (&sourcePlan == &plan)
    planNodes[place] = index;
  for (unsigned i = 0; i < planned.fields.size(); ++i) {
    auto childPath = path;
    childPath.push_back(i);
    auto child = addNode(sourcePlan, planned.fields[i], root,
                         static_cast<int>(index), std::move(childPath));
    nodes[index].children.push_back(child);
  }
  return index;
}

unsigned CleanupFrame::addRoot(const cleanup::Plan &sourcePlan, int place,
                               int local) {
  const auto &planned = sourcePlan.places[place];
  auto type = planned.type;
  bool indirect = planned.indirect;
  unsigned root = roots.size();
  auto field = local >= 0 ? localFields[local]
                          : addField(indirect ? lowering.builder.getPtrTy()
                                              : lowering.layoutType(type),
                                     indirect ? 8 : lowering.alignment(type));
  roots.push_back({type, field, 0, local, indirect, planned.place});
  auto node = addNode(sourcePlan, place, root, -1, {});
  roots[root].node = node;
  return root;
}

CleanupFrame::CleanupFrame(LoweringContext &lowering,
                           const ir::Function &source, llvm::Function *wrapper)
    : CleanupFrame(lowering, source, wrapper, wrapper->getName().str()) {}
CleanupFrame::CleanupFrame(LoweringContext &lowering,
                           const ir::Function &source, std::string name)
    : CleanupFrame(lowering, source, nullptr, std::move(name)) {}
CleanupFrame::CleanupFrame(LoweringContext &lowering,
                           const ir::Function &source, llvm::Function *wrapper,
                           std::string name)
    : lowering(lowering), source(source), wrapper(wrapper),
      bodyFunction(lowering.callback(name + ".body")),
      cleanupFunction(lowering.callback(name + ".unwind", true)),
      frameType(llvm::StructType::create(lowering.context, name + ".frame")),
      name(name), plan(cleanup::plan(source, *lowering.program.types)) {
  locals.resize(source.locals.size(), std::numeric_limits<unsigned>::max());
  for (std::size_t i = 0; i < source.locals.size(); ++i) {
    const auto &local = source.locals[i];
    bool borrowed =
        local.storage == StorageDuration::Static ||
        (i < source.parameters && (local.mode == ParameterMode::Read ||
                                   local.mode == ParameterMode::Mut));
    localFields.push_back(
        addField(borrowed ? lowering.builder.getPtrTy()
                          : lowering.storageType(local.type),
                 borrowed ? 8 : lowering.alignment(local.type)));
  }
  planNodes.resize(plan.places.size());
  std::vector<bool> children(plan.places.size(), false);
  for (const auto &place : plan.places)
    for (int child : place.fields)
      children[child] = true;
  for (unsigned i = 0; i < plan.places.size(); ++i)
    if (!children[i]) {
      const auto &place = plan.places[i].place;
      int local = place.fields.empty() ? place.root : -1;
      auto root = addRoot(plan, static_cast<int>(i), local);
      if (local >= 0)
        locals[local] = root;
    }
  resultField = addField(lowering.storageType(source.result),
                         lowering.alignment(source.result));
  ir::Function pendingSource{};
  std::vector<int> pendingIds;
  for (const auto &block : source.blocks)
    for (const auto &instruction : block.instructions)
      if (instruction.result.access == ir::Access::Owned &&
          lowering.program.types->needsDrop(instruction.result.type)) {
        pendingSource.locals.push_back(
            {"pending",
             instruction.result.type,
             false,
             {},
             ParameterMode::Value,
             -2,
             static_cast<std::uint32_t>(pendingIds.size())});
        pendingIds.push_back(instruction.result.id);
      }
  // SSA ownership between a Move and its consumer is physical backend scratch.
  // Its hierarchy is still supplied by the compiler-owned cleanup planner.
  auto pendingPlan = cleanup::plan(pendingSource, *lowering.program.types);
  for (int place : pendingPlan.unwind) {
    auto id = pendingIds[pendingPlan.places[place].place.root];
    values.emplace(id, addRoot(pendingPlan, place));
  }
  for (const auto &block : source.blocks)
    for (const auto &instruction : block.instructions) {
      if (instruction.op != ir::Op::Store)
        continue;
      auto type = *projectedType(*lowering.program.types,
                                 source.locals[instruction.place.root].type,
                                 instruction.place.fields);
      if (!lowering.program.types->needsDrop(type))
        continue;
      unsigned destination = planNodes[plan.indices.at(instruction.place)];
      auto pointer = addField(lowering.builder.getPtrTy());
      replacementIndices.emplace(&instruction, replacements.size());
      replacements.push_back({destination, pointer,
                              values.at(instruction.operands[0].id), nullptr,
                              nullptr});
    }
  if (source.coroutine) {
    stateField = addField(lowering.builder.getInt32Ty());
    contextField = addField(lowering.builder.getPtrTy());
    // A suspension ends the body callback, so every value used outside its
    // defining block is kept in the frame. Phi operands are used at the end
    // of their predecessor.
    std::vector<int> defined(source.values, -1);
    for (std::size_t b = 0; b < source.blocks.size(); ++b)
      for (const auto &instruction : source.blocks[b].instructions)
        if (instruction.result.id >= 0)
          defined[instruction.result.id] = static_cast<int>(b);
    auto use = [&](const ir::Value &value, int block) {
      if (value.id < 0 || defined[value.id] == block ||
          spills.contains(value.id))
        return;
      spills.emplace(value.id, addField(lowering.storageType(value.type),
                                        lowering.alignment(value.type)));
    };
    for (std::size_t b = 0; b < source.blocks.size(); ++b) {
      int block = static_cast<int>(b);
      for (const auto &instruction : source.blocks[b].instructions) {
        if (instruction.op == ir::Op::Phi) {
          for (std::size_t i = 0; i < instruction.operands.size(); ++i)
            use(instruction.operands[i], instruction.predecessors[i]);
          continue;
        }
        for (const auto &operand : instruction.operands)
          use(operand, block);
        use(instruction.target, block);
      }
      use(source.blocks[b].exit.value, block);
    }
  }
  if (source.coroutine && size() > frameSize) {
    fields.push_back(
        llvm::ArrayType::get(lowering.builder.getInt8Ty(), size() - frameSize));
    frameSize = size();
  }
  frameType->setBody(fields);
  if (!source.coroutine)
    emitCallbacks();
}

void CleanupFrame::finishCallbacks() {
  if (!callbacksEmitted)
    emitCallbacks();
}

llvm::Value *CleanupFrame::field(unsigned index) {
  return lowering.builder.CreateStructGEP(frameType, frame, index);
}

llvm::Value *CleanupFrame::nodeAddress(unsigned node) {
  const auto &entry = nodes[node];
  const auto &root = roots[entry.root];
  llvm::Value *address;
  if (entry.parent >= 0) {
    address = nodeAddress(entry.parent);
    auto type = nodes[entry.parent].type;
    address = lowering.fieldAddress(address, type, entry.path.back());
  } else {
    address = field(root.field);
    if (root.indirect)
      address =
          lowering.builder.CreateLoad(lowering.builder.getPtrTy(), address);
  }
  if (entry.relocation >= 0)
    address = lowering.builder.CreateSelect(
        lowering.builder.CreateLoad(lowering.builder.getInt1Ty(),
                                    field(entry.relocatedFlag)),
        field(entry.relocation), address);
  return address;
}
llvm::Value *LoweringContext::fieldAddress(llvm::Value *address, Type &type,
                                           unsigned index) {
  auto &lowering = *this;
  auto &builder = lowering.builder;
  llvm::Value *length = nullptr, *witness = nullptr;
  auto metadata = lowering.program.types->pointerMetadata(type);
  if (metadata == PointerMetadata::ElementCount ||
      metadata == PointerMetadata::Witness) {
    auto *handle = builder.CreateAlignedLoad(lowering.viewType(type), address,
                                             llvm::Align(1));
    address = builder.CreateExtractValue(handle, 0);
    length = builder.CreateExtractValue(handle, 1);
    if (metadata == PointerMetadata::Witness)
      witness = builder.CreateExtractValue(handle, 2);
  }
  auto fieldType = lowering.program.types->product(type).fields[index].type;
  bool witnessTail = witness && lowering.program.types->pointerMetadata(
                                    fieldType) == PointerMetadata::Witness;
  if (witnessTail) {
    auto *zero = llvm::ConstantPointerNull::get(builder.getPtrTy());
    llvm::Value *offset =
        customRepresentation(*lowering.program.types, type)
            ? builder.getInt64(lowering.layout(type).fields.at(index))
            : builder.CreatePtrToInt(
                  builder.CreateGEP(
                      lowering.layoutType(type), zero,
                      {builder.getInt32(0), builder.getInt32(index)}),
                  builder.getInt64Ty());
    auto *alignmentSlot =
        builder.CreateGEP(builder.getPtrTy(), witness, builder.getInt32(2));
    auto *alignment = builder.CreatePtrToInt(
        builder.CreateLoad(builder.getPtrTy(), alignmentSlot),
        builder.getInt64Ty());
    llvm::Value *prefixAlignment =
        lowering.program.types->isErased(fieldType)
            ? builder.getInt64(1)
            : builder.getInt64(lowering.alignment(fieldType));
    alignment =
        builder.CreateSelect(builder.CreateICmpUGT(alignment, prefixAlignment),
                             alignment, prefixAlignment);
    auto *mask = builder.CreateSub(alignment, builder.getInt64(1));
    offset = builder.CreateAnd(builder.CreateAdd(offset, mask),
                               builder.CreateNot(mask));
    address = builder.CreateGEP(builder.getInt8Ty(), address, offset);
  } else if (!lowering.program.types->isOpaque(type))
    address = lowering.fieldPointer(address, type, index);
  type = fieldType;
  if (length && lowering.program.types->pointerMetadata(type) ==
                    PointerMetadata::ElementCount) {
    auto *handleType = lowering.viewType(type);
    llvm::Value *handle = llvm::UndefValue::get(handleType);
    handle = builder.CreateInsertValue(handle, address, 0);
    handle = builder.CreateInsertValue(handle, length, 1);
    auto *stored = lowering.temporary(handleType);
    builder.CreateStore(handle, stored);
    address = stored;
  }
  if (witnessTail) {
    auto *handleType = lowering.viewType(type);
    llvm::Value *handle = llvm::UndefValue::get(handleType);
    handle = builder.CreateInsertValue(handle, address, 0);
    handle = builder.CreateInsertValue(handle, length, 1);
    handle = builder.CreateInsertValue(handle, witness, 2);
    auto *stored = lowering.temporary(handleType);
    builder.CreateStore(handle, stored);
    address = stored;
  }
  return address;
}
llvm::Value *LoweringContext::projectField(llvm::Value *handle, Type owner,
                                           unsigned index) {
  auto *address = handle;
  if (program.types->pointerMetadata(owner) != PointerMetadata::None) {
    address = temporary(viewType(owner));
    builder.CreateStore(handle, address);
  }
  auto type = owner;
  auto *result = fieldAddress(address, type, index);
  return program.types->pointerMetadata(type) != PointerMetadata::None
             ? builder.CreateLoad(viewType(type), result)
             : result;
}

unsigned CleanupFrame::placeNode(const Place &place) const {
  auto found = plan.indices.find(place);
  return found == plan.indices.end() ? std::numeric_limits<unsigned>::max()
                                     : planNodes[found->second];
}

llvm::Value *CleanupFrame::address(const Place &place) {
  const auto &local = source.locals[place.root];
  llvm::Value *address =
      local.storage == StorageDuration::Static
          ? static_cast<llvm::Value *>(lowering.statics.at(local.staticIndex))
          : field(localFields[place.root]);
  if (static_cast<std::size_t>(place.root) < source.parameters &&
      (local.mode == ParameterMode::Read || local.mode == ParameterMode::Mut))
    address = lowering.builder.CreateLoad(lowering.builder.getPtrTy(), address);
  auto type = source.locals[place.root].type;
  for (auto projection : place.fields) {
    if (projection.kind == Projection::Kind::Slice) {
      const auto &array = lowering.program.types->product(type);
      auto *elements =
          llvm::ArrayType::get(lowering.storageType(array.components[0]),
                               *lowering.program.types->arrayLength(type));
      address = lowering.builder.CreateGEP(
          elements, address,
          {lowering.builder.getInt32(0),
           lowering.builder.getInt32(projection.index)});
      type = projection.type;
    } else if (projection.kind == Projection::Kind::Dereference) {
      auto payload = lowering.program.types->view(type).payload;
      if (lowering.program.types->pointerMetadata(payload) ==
          PointerMetadata::None)
        address = lowering.builder.CreateAlignedLoad(
            lowering.builder.getPtrTy(), address, llvm::Align(1));
      type = payload;
    } else {
      address = lowering.fieldAddress(address, type, projection.index);
    }
  }
  return address;
}
llvm::Align CleanupFrame::alignment(const Place &place) {
  auto type = source.locals.at(place.root).type;
  auto result = lowering.alignment(type);
  for (auto projection : place.fields) {
    if (projection.kind == Projection::Kind::Dereference) {
      type = lowering.program.types->view(type).payload;
      result = lowering.alignment(type);
    } else if (projection.kind == Projection::Kind::Slice) {
      auto element = lowering.program.types->product(type).components[0];
      auto offset =
          std::uint64_t{projection.index} * lowering.layout(element).size;
      if (offset)
        result = std::min(result, offset & (~offset + 1));
      type = projection.type;
    } else {
      auto offset = lowering.layout(type).fields.at(projection.index);
      if (offset)
        result = std::min(result, offset & (~offset + 1));
      type = lowering.program.types->product(type)
                 .fields.at(projection.index)
                 .type;
    }
  }
  return llvm::Align(result);
}

void CleanupFrame::set(unsigned node, bool initialized) {
  initialize(node, lowering.builder.getInt1(initialized));
}
void CleanupFrame::initialize(unsigned node, llvm::Value *initialized) {
  auto &builder = lowering.builder;
  builder.CreateStore(initialized, field(nodes[node].flag));
  if (nodes[node].relocation >= 0)
    builder.CreateStore(builder.getFalse(), field(nodes[node].relocatedFlag));
  if (auto *constant = llvm::dyn_cast<llvm::ConstantInt>(initialized);
      constant && constant->isZero()) {
    for (auto child : nodes[node].children)
      initialize(child, initialized);
    return;
  }
  if (!lowering.program.types->isSum(nodes[node].type)) {
    for (auto child : nodes[node].children)
      initialize(child, initialized);
    return;
  }
  const auto &sum = lowering.program.types->product(nodes[node].type);
  auto *tag = lowering.enumTag(nodes[node].type, nodeAddress(node));
  if (!nodes[node].children.empty())
    initialize(nodes[node].children[0], initialized);
  for (std::size_t variant = 0; variant < sum.variants.size(); ++variant)
    for (auto field : sum.variants[variant].fields)
      initialize(nodes[node].children[field],
                 builder.CreateAnd(
                     initialized,
                     builder.CreateICmpEQ(tag, builder.getInt32(variant))));
}

void CleanupFrame::updateParents(unsigned node) {
  for (int parent = nodes[node].parent; parent >= 0;
       parent = nodes[parent].parent) {
    llvm::Value *ready = lowering.builder.getTrue();
    if (lowering.program.types->isSum(nodes[parent].type)) {
      lowering.builder.CreateStore(lowering.builder.getFalse(),
                                   field(nodes[parent].flag));
      continue;
    }
    for (auto child : nodes[parent].children)
      ready = lowering.builder.CreateAnd(
          ready, lowering.builder.CreateLoad(lowering.builder.getInt1Ty(),
                                             field(nodes[child].flag)));
    lowering.builder.CreateStore(ready, field(nodes[parent].flag));
  }
}

void CleanupFrame::declare(const Place &place) {
  auto node = placeNode(place);
  if (node != std::numeric_limits<unsigned>::max())
    set(node, false);
}

void CleanupFrame::move(const Place &place) {
  auto node = placeNode(place);
  if (node == std::numeric_limits<unsigned>::max())
    return;
  set(node, false);
  updateParents(node);
}

void CleanupFrame::remember(ir::Value value, llvm::Value *result) {
  if (auto found = values.find(value.id); found != values.end()) {
    const auto &root = roots[found->second];
    lowering.store(root.type, result, field(root.field),
                   llvm::Align(lowering.alignment(root.type)));
    set(root.node, true);
  }
}

void CleanupFrame::consume(ir::Value value) {
  if (auto found = values.find(value.id); found != values.end())
    set(roots[found->second].node, false);
}

void CleanupFrame::drop(unsigned node) {
  auto &builder = lowering.builder;
  const auto &entry = nodes[node];
  auto *function = builder.GetInsertBlock()->getParent();
  auto *destroy = llvm::BasicBlock::Create(lowering.context, "drop", function);
  auto *next = llvm::BasicBlock::Create(lowering.context, "next", function);
  builder.CreateCondBr(
      builder.CreateLoad(builder.getInt1Ty(), field(entry.flag)), destroy,
      next);
  builder.SetInsertPoint(destroy);
  if (entry.relocation >= 0) {
    auto *relocate =
        llvm::BasicBlock::Create(lowering.context, "relocate", function);
    auto *ready =
        llvm::BasicBlock::Create(lowering.context, "aligned", function);
    builder.CreateCondBr(
        builder.CreateLoad(builder.getInt1Ty(), field(entry.relocatedFlag)),
        ready, relocate);
    builder.SetInsertPoint(relocate);
    // The aligned copy lives in the unwind frame, including after this
    // destructor panics and cleanup resumes with its remaining fields.
    builder.CreateMemCpy(
        field(entry.relocation), llvm::Align(lowering.alignment(entry.type)),
        nodeAddress(node), llvm::Align(1), lowering.layout(entry.type).size);
    builder.CreateStore(builder.getTrue(), field(entry.relocatedFlag));
    builder.CreateBr(ready);
    builder.SetInsertPoint(ready);
  }
  // A whole sum may have changed variant through a borrow since its flags were
  // derived, so its payload flags are re-derived from the current tag.
  if (lowering.program.types->isSum(entry.type))
    initialize(node, builder.getTrue());
  // Re-entry after a panic must never repeat an already-started destructor.
  builder.CreateStore(builder.getFalse(), field(entry.flag));
  if (entry.nativeAction == NativeCleanup::RefRelease ||
      entry.nativeAction == NativeCleanup::RefMutRelease) {
    auto owner =
        lowering.program.types
            ->view(lowering.program.types->product(entry.type).components[0])
            .payload;
    auto *cell = lowering.load(
        lowering.program.types->product(entry.type).fields[0].type,
        nodeAddress(node), llvm::Align(lowering.alignment(entry.type)));
    auto *counter = lowering.projectField(cell, owner, 0);
    auto *count = builder.CreateLoad(builder.getInt64Ty(), counter);
    builder.CreateStore(entry.nativeAction == NativeCleanup::RefRelease
                            ? builder.CreateSub(count, builder.getInt64(1))
                            : builder.getInt64(0),
                        counter);
  } else if (entry.nativeAction == NativeCleanup::VaListEnd) {
    builder.CreateCall(
        llvm::Intrinsic::getOrInsertDeclaration(
            &lowering.module, llvm::Intrinsic::vaend, {builder.getPtrTy()}),
        {nodeAddress(node)});
  }
  if (lowering.program.types->isProduct(entry.type) &&
      lowering.program.types->product(entry.type).kind ==
          AggregateKind::Coroutine) {
    // Dropping a state drops whatever its body frame still owns, at any
    // suspension point; the frame's flags make this exact.
    auto *unwinding = function->arg_size() > 1
                          ? static_cast<llvm::Value *>(function->getArg(1))
                          : builder.getInt32(0);
    builder.CreateCall(lowering.coroutine(entry.type).unwind(),
                       {nodeAddress(node), unwinding});
  }
  if (entry.destructor >= 0) {
    auto parameter =
        lowering.program.functions[entry.destructor].locals[0].type;
    auto *self = nodeAddress(node);
    if (lowering.program.types->isProduct(parameter) &&
        lowering.program.types->product(parameter).kind == AggregateKind::Pin) {
      auto *storage = lowering.temporary(parameter);
      builder.CreateStore(lowering.construct(parameter, {self}), storage);
      self = storage;
    }
    builder.CreateCall(lowering.functions[entry.destructor], {self});
  }
  if (lowering.program.types->isSlice(entry.type)) {
    auto element = lowering.program.types->slice(entry.type).element;
    if (lowering.program.types->needsDrop(element)) {
      auto drop = std::find_if(
          lowering.program.dynamicDropFunctions.begin(),
          lowering.program.dynamicDropFunctions.end(),
          [&](const auto &entry) { return entry.first == element; });
      if (drop != lowering.program.dynamicDropFunctions.end()) {
        auto *handle = builder.CreateAlignedLoad(
            lowering.viewType(entry.type), nodeAddress(node), llvm::Align(1));
        auto *data = builder.CreateExtractValue(handle, 0);
        auto *count = builder.CreateExtractValue(handle, 1);
        builder.CreateCall(
            lowering.functions.at(static_cast<std::size_t>(drop->second)),
            {data, count});
      }
    }
  }
  builder.CreateBr(next);
  builder.SetInsertPoint(next);
  for (auto child : entry.children)
    drop(child);
}

llvm::Function *CleanupFrame::dropCallback(unsigned node) {
  if (auto found = drops.find(node); found != drops.end())
    return found->second;
  auto saved = lowering.builder.saveIP();
  auto *savedFrame = frame;
  auto *callback = lowering.callback(name + ".drop", true);
  drops[node] = callback;
  frame = callback->getArg(0);
  lowering.builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", callback));
  drop(node);
  lowering.builder.CreateRetVoid();
  frame = savedFrame;
  lowering.builder.restoreIP(saved);
  return callback;
}

void CleanupFrame::callDrop(unsigned node, llvm::Value *unwinding) {
  auto &builder = lowering.builder;
  if (lowering.freestanding) {
    builder.CreateCall(dropCallback(node), {frame, unwinding});
    return;
  }
  builder.CreateCall(lowering.runtime("mettle_rt_cleanup", builder.getVoidTy(),
                                      {builder.getPtrTy(), builder.getPtrTy(),
                                       builder.getInt32Ty()}),
                     {frame, dropCallback(node), unwinding});
}

std::vector<unsigned> CleanupFrame::cleanupOrder() const {
  std::vector<unsigned> order;
  for (unsigned i = 0; i < roots.size(); ++i)
    if (roots[i].local < 0 && !roots[i].indirect)
      order.push_back(i);
  for (int node : plan.unwind)
    order.push_back(nodes[planNodes[node]].root);
  return order;
}

void CleanupFrame::emitReplacement(Replacement &replacement) {
  auto &builder = lowering.builder;
  replacement.destroy = dropCallback(replacement.destination);
  replacement.install = lowering.callback(name + ".install");
  frame = replacement.install->getArg(0);
  builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", replacement.install));
  const auto &pending = roots[replacement.pending];
  auto *destination =
      builder.CreateLoad(builder.getPtrTy(), field(replacement.pointer));
  auto *value = lowering.load(pending.type, field(pending.field),
                              llvm::Align(lowering.alignment(pending.type)));
  lowering.store(pending.type, value, destination, llvm::Align(1));
  set(pending.node, false);
  set(replacement.destination, true);
  updateParents(replacement.destination);
  builder.CreateRetVoid();
  replacement.install->addFnAttr(llvm::Attribute::NoUnwind);
}

void CleanupFrame::emitCallbacks() {
  callbacksEmitted = true;
  auto saved = lowering.builder.saveIP();
  for (auto &replacement : replacements)
    emitReplacement(replacement);
  frame = cleanupFunction->getArg(0);
  lowering.builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", cleanupFunction));
  for (auto root : cleanupOrder())
    callDrop(roots[root].node, cleanupFunction->getArg(1));
  lowering.builder.CreateRetVoid();
  frame = bodyFunction->getArg(0);
  lowering.builder.restoreIP(saved);
}

llvm::Value *CleanupFrame::createWrapper() {
  auto &builder = lowering.builder;
  builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", wrapper));
  frame = builder.CreateAlloca(frameType, nullptr, "frame");
  llvm::cast<llvm::AllocaInst>(frame)->setAlignment(
      llvm::Align(frameAlignment));
  clearFlags();
  if (source.variadicCursor >= 0) {
    auto *cursor = field(localFields[source.variadicCursor]);
    builder.CreateStore(llvm::Constant::getNullValue(lowering.layoutType(
                            source.locals[source.variadicCursor].type)),
                        cursor);
    builder.CreateCall(
        llvm::Intrinsic::getOrInsertDeclaration(
            &lowering.module, llvm::Intrinsic::vacopy, {builder.getPtrTy()}),
        {cursor, wrapper->getArg(source.parameters)});
    // The incoming cursor belongs to the physical entry that va_start it, which
    // also ends it once this call returns; the frame owns only the copy.
    if (locals[source.variadicCursor] != std::numeric_limits<unsigned>::max())
      set(roots[locals[source.variadicCursor]].node, true);
  }
  for (unsigned i = 0; i < source.parameters; ++i) {
    if (source.locals[i].mode == ParameterMode::Read ||
        source.locals[i].mode == ParameterMode::Mut)
      builder.CreateStore(wrapper->getArg(i), field(localFields[i]));
    else
      lowering.store(source.locals[i].type, wrapper->getArg(i),
                     field(localFields[i]),
                     llvm::Align(lowering.alignment(source.locals[i].type)));
    if (locals[i] != std::numeric_limits<unsigned>::max())
      set(roots[locals[i]].node, true);
  }
  bindStatics();
  auto *outerFrame = frame;
  if (lowering.freestanding ||
      (nodes.empty() && source.abi != "C" && source.abi != "system"))
    builder.CreateCall(bodyFunction, {frame});
  else
    builder.CreateCall(
        lowering.runtime(
            source.abi == "C" || source.abi == "system" ? "mettle_rt_run_c"
                                                        : "mettle_rt_run",
            builder.getVoidTy(),
            {builder.getPtrTy(), builder.getPtrTy(), builder.getPtrTy()}),
        {frame, bodyFunction, cleanupFunction});
  finishWrapper(outerFrame);
  frame = bodyFunction->getArg(0);
  return outerFrame;
}
void CleanupFrame::clearFlags() {
  auto &builder = lowering.builder;
  for (const auto &node : nodes) {
    builder.CreateStore(builder.getFalse(), field(node.flag));
    if (node.relocation >= 0)
      builder.CreateStore(builder.getFalse(), field(node.relocatedFlag));
  }
}
void CleanupFrame::bindStatics() {
  for (std::size_t i = 0; i < source.locals.size(); ++i)
    if (source.locals[i].storage == StorageDuration::Static) {
      lowering.builder.CreateStore(
          lowering.statics.at(source.locals[i].staticIndex),
          field(localFields[i]));
      if (locals[i] != std::numeric_limits<unsigned>::max())
        set(roots[locals[i]].node, true);
    }
}
// The unstarted state owns only the environment; it may be moved until it
// is first resumed, after which it is pinned.
void CleanupFrame::startCoroutine(llvm::Value *state,
                                  llvm::Value *environment) {
  auto *saved = frame;
  frame = state;
  clearFlags();
  lowering.builder.CreateStore(lowering.builder.getInt32(0), field(stateField));
  if (source.parameters == 1) {
    lowering.store(source.locals[0].type, environment, field(localFields[0]),
                   llvm::Align(lowering.alignment(source.locals[0].type)));
    if (locals[0] != std::numeric_limits<unsigned>::max())
      set(roots[locals[0]].node, true);
  }
  bindStatics();
  frame = saved;
}
llvm::Value *CleanupFrame::resumeCoroutine(llvm::Value *state,
                                           llvm::Value *context,
                                           Type optional) {
  auto &builder = lowering.builder;
  auto *saved = frame;
  frame = state;
  builder.CreateStore(context, field(contextField));
  if (lowering.freestanding || nodes.empty())
    builder.CreateCall(bodyFunction, {frame});
  else
    builder.CreateCall(lowering.runtime("mettle_rt_run", builder.getVoidTy(),
                                        {builder.getPtrTy(), builder.getPtrTy(),
                                         builder.getPtrTy()}),
                       {frame, bodyFunction, cleanupFunction});
  auto *function = builder.GetInsertBlock()->getParent();
  auto *ready = llvm::BasicBlock::Create(lowering.context, "ready", function);
  auto *pending =
      llvm::BasicBlock::Create(lowering.context, "pending", function);
  auto *join = llvm::BasicBlock::Create(lowering.context, "resumed", function);
  builder.CreateCondBr(
      builder.CreateICmpEQ(
          builder.CreateLoad(builder.getInt32Ty(), field(stateField)),
          builder.getInt32(complete)),
      ready, pending);
  builder.SetInsertPoint(ready);
  auto *value = lowering.variant(
      optional, 1,
      {lowering.load(source.result, field(resultField),
                     llvm::Align(lowering.alignment(source.result)))});
  auto *readyEnd = builder.GetInsertBlock();
  builder.CreateBr(join);
  builder.SetInsertPoint(pending);
  auto *none = lowering.variant(optional, 0, {});
  auto *pendingEnd = builder.GetInsertBlock();
  builder.CreateBr(join);
  builder.SetInsertPoint(join);
  auto *result = builder.CreatePHI(value->getType(), 2);
  result->addIncoming(value, readyEnd);
  result->addIncoming(none, pendingEnd);
  frame = saved;
  return result;
}
llvm::Value *CleanupFrame::variadicContext() {
  return field(localFields[source.variadicCursor]);
}

void CleanupFrame::finishWrapper(llvm::Value *outerFrame) {
  frame = outerFrame;
  if (source.result == Type::Never)
    lowering.builder.CreateUnreachable();
  else if (source.result == Type::Unit)
    lowering.builder.CreateRetVoid();
  else if (lowering.indirect(source.result)) {
    lowering.builder.CreateMemCpy(
        wrapper->getArg(wrapper->arg_size() - 1),
        llvm::Align(lowering.alignment(source.result)), field(resultField),
        llvm::Align(lowering.alignment(source.result)),
        lowering.layout(source.result).size);
    lowering.builder.CreateRetVoid();
  } else
    lowering.builder.CreateRet(
        lowering.load(source.result, field(resultField),
                      llvm::Align(lowering.alignment(source.result))));
}

void CleanupFrame::store(const ir::Instruction &instruction,
                         llvm::Value *value) {
  auto &builder = lowering.builder;
  if (auto found = replacementIndices.find(&instruction);
      found != replacementIndices.end()) {
    auto &replacement = replacements[found->second];
    builder.CreateStore(address(instruction.place), field(replacement.pointer));
    const auto &root = roots[nodes[replacement.destination].root];
    if (root.indirect && root.local < 0) {
      builder.CreateStore(address(root.place), field(root.field));
      set(root.node, true);
    }
    if (lowering.freestanding) {
      builder.CreateCall(replacement.destroy, {frame, builder.getInt32(0)});
      builder.CreateCall(replacement.install, {frame});
    } else
      builder.CreateCall(
          lowering.runtime(
              "mettle_rt_replace", builder.getVoidTy(),
              {builder.getPtrTy(), builder.getPtrTy(), builder.getPtrTy()}),
          {frame, replacement.destroy, replacement.install});
  } else {
    lowering.store(instruction.operands[0].type, value,
                   address(instruction.place), alignment(instruction.place));
    auto node = placeNode(instruction.place);
    if (node != std::numeric_limits<unsigned>::max()) {
      set(node, true);
      updateParents(node);
    }
  }
}

void CleanupFrame::scopeExit(int scope) {
  for (int node : plan.scopes.at(scope)) {
    llvm::Value *unwinding = lowering.builder.getInt32(0);
    if (!lowering.freestanding)
      unwinding = lowering.builder.CreateCall(lowering.runtime(
          "mettle_rt_panicking", lowering.builder.getInt32Ty(), {}));
    callDrop(planNodes[node], unwinding);
  }
}
void CleanupFrame::dropPlace(const Place &place) {
  auto node = placeNode(place);
  if (node == std::numeric_limits<unsigned>::max())
    return;
  const auto &root = roots[nodes[node].root];
  if (root.indirect && root.local < 0)
    lowering.builder.CreateStore(address(place), field(root.field));
  set(node, true);
  llvm::Value *unwinding = lowering.builder.getInt32(0);
  if (!lowering.freestanding)
    unwinding = lowering.builder.CreateCall(lowering.runtime(
        "mettle_rt_panicking", lowering.builder.getInt32Ty(), {}));
  callDrop(node, unwinding);
}

void CleanupFrame::returnValue(ir::Value value, llvm::Value *result) {
  if (source.result != Type::Unit && source.result != Type::Never) {
    lowering.store(source.result, result, field(resultField),
                   llvm::Align(lowering.alignment(source.result)));
    consume(value);
  }
  lowering.builder.CreateRetVoid();
}
} // namespace mettle::backend
