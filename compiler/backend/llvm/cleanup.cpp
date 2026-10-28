#include "backend/llvm/cleanup.h"

#include <algorithm>
#include <limits>

namespace mettle::backend {
llvm::Type *LoweringContext::type(Type typeId) {
  if (typeId == Type::I32)
    return builder.getInt32Ty();
  if (typeId == Type::Bool)
    return builder.getInt1Ty();
  if (typeId == Type::Unit || typeId == Type::Never)
    return llvm::StructType::get(context);
  if (program.types->isView(typeId))
    return builder.getPtrTy();
  if (auto found = products.find(typeId.index()); found != products.end())
    return found->second;
  const auto &product = program.types->product(typeId);
  auto *result =
      llvm::StructType::create(context, "mettle.type." + product.name);
  products[typeId.index()] = result;
  std::vector<llvm::Type *> members;
  for (const auto &member : product.fields)
    members.push_back(type(member.type));
  result->setBody(members);
  return result;
}

llvm::Type *LoweringContext::resultType(Type typeId) {
  return typeId == Type::Unit || typeId == Type::Never ? builder.getVoidTy()
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
  return function;
}

unsigned CleanupFrame::addField(llvm::Type *type) {
  unsigned index = fields.size();
  fields.push_back(type);
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
                                              : lowering.type(type));
  roots.push_back({type, field, 0, local, indirect, planned.place});
  auto node = addNode(sourcePlan, place, root, -1, {});
  roots[root].node = node;
  return root;
}

CleanupFrame::CleanupFrame(LoweringContext &lowering,
                           const ir::Function &source, llvm::Function *wrapper)
    : lowering(lowering), source(source), wrapper(wrapper),
      bodyFunction(lowering.callback(wrapper->getName() + ".body")),
      cleanupFunction(lowering.callback(wrapper->getName() + ".unwind", true)),
      frameType(llvm::StructType::create(
          lowering.context, (wrapper->getName() + ".frame").str())),
      plan(cleanup::plan(source, *lowering.program.types)) {
  locals.resize(source.locals.size(), std::numeric_limits<unsigned>::max());
  for (std::size_t i = 0; i < source.locals.size(); ++i) {
    const auto &local = source.locals[i];
    bool borrowed =
        i < source.parameters &&
        (local.mode == ParameterMode::Read || local.mode == ParameterMode::Mut);
    localFields.push_back(addField(borrowed ? lowering.builder.getPtrTy()
                                            : lowering.type(local.type)));
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
  resultField = addField(lowering.type(source.result));
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
  frameType->setBody(fields);
  emitCallbacks();
}

llvm::Value *CleanupFrame::field(unsigned index) {
  return lowering.builder.CreateStructGEP(frameType, frame, index);
}

llvm::Value *CleanupFrame::nodeAddress(unsigned node) {
  const auto &entry = nodes[node];
  const auto &root = roots[entry.root];
  auto *address = field(root.field);
  if (root.indirect)
    address = lowering.builder.CreateLoad(lowering.builder.getPtrTy(), address);
  auto type = root.type;
  for (auto index : entry.path) {
    address =
        lowering.builder.CreateStructGEP(lowering.type(type), address, index);
    type = lowering.program.types->product(type).fields[index].type;
  }
  return address;
}

unsigned CleanupFrame::placeNode(const Place &place) const {
  auto found = plan.indices.find(place);
  return found == plan.indices.end() ? std::numeric_limits<unsigned>::max()
                                     : planNodes[found->second];
}

llvm::Value *CleanupFrame::address(const Place &place) {
  auto *address = field(localFields[place.root]);
  const auto &local = source.locals[place.root];
  if (static_cast<std::size_t>(place.root) < source.parameters &&
      (local.mode == ParameterMode::Read || local.mode == ParameterMode::Mut))
    address = lowering.builder.CreateLoad(lowering.builder.getPtrTy(), address);
  auto type = source.locals[place.root].type;
  for (auto projection : place.fields) {
    if (projection.kind == Projection::Kind::Dereference) {
      address =
          lowering.builder.CreateLoad(lowering.builder.getPtrTy(), address);
      type = lowering.program.types->view(type).payload;
    } else {
      address = lowering.builder.CreateStructGEP(lowering.type(type), address,
                                                 projection.index);
      type =
          lowering.program.types->product(type).fields[projection.index].type;
    }
  }
  return address;
}

void CleanupFrame::set(unsigned node, bool initialized) {
  lowering.builder.CreateStore(lowering.builder.getInt1(initialized),
                               field(nodes[node].flag));
  for (auto child : nodes[node].children)
    set(child, initialized);
}

void CleanupFrame::updateParents(unsigned node) {
  for (int parent = nodes[node].parent; parent >= 0;
       parent = nodes[parent].parent) {
    llvm::Value *ready = lowering.builder.getTrue();
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
    lowering.builder.CreateStore(result, field(root.field));
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
  // Re-entry after a panic must never repeat an already-started destructor.
  builder.CreateStore(builder.getFalse(), field(entry.flag));
  if (entry.destructor >= 0)
    builder.CreateCall(lowering.functions[entry.destructor],
                       {nodeAddress(node)});
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
  auto *callback = lowering.callback(wrapper->getName() + ".drop", true);
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
  replacement.install = lowering.callback(wrapper->getName() + ".install");
  frame = replacement.install->getArg(0);
  builder.SetInsertPoint(
      llvm::BasicBlock::Create(lowering.context, "entry", replacement.install));
  const auto &pending = roots[replacement.pending];
  auto *destination =
      builder.CreateLoad(builder.getPtrTy(), field(replacement.pointer));
  auto *value =
      builder.CreateLoad(lowering.type(pending.type), field(pending.field));
  builder.CreateStore(value, destination);
  set(pending.node, false);
  set(replacement.destination, true);
  updateParents(replacement.destination);
  builder.CreateRetVoid();
  replacement.install->addFnAttr(llvm::Attribute::NoUnwind);
}

void CleanupFrame::emitCallbacks() {
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
  for (const auto &node : nodes)
    builder.CreateStore(builder.getFalse(), field(node.flag));
  for (unsigned i = 0; i < source.parameters; ++i) {
    builder.CreateStore(wrapper->getArg(i), field(localFields[i]));
    if (locals[i] != std::numeric_limits<unsigned>::max())
      set(roots[locals[i]].node, true);
  }
  for (const auto &root : roots)
    if (root.indirect)
      set(root.node, true);
  auto *outerFrame = frame;
  builder.CreateCall(lowering.runtime("mettle_rt_run", builder.getVoidTy(),
                                      {builder.getPtrTy(), builder.getPtrTy(),
                                       builder.getPtrTy()}),
                     {frame, bodyFunction, cleanupFunction});
  finishWrapper(outerFrame);
  frame = bodyFunction->getArg(0);
  return outerFrame;
}

void CleanupFrame::finishWrapper(llvm::Value *outerFrame) {
  frame = outerFrame;
  if (source.result == Type::Never)
    lowering.builder.CreateUnreachable();
  else if (source.result == Type::Unit)
    lowering.builder.CreateRetVoid();
  else
    lowering.builder.CreateRet(lowering.builder.CreateLoad(
        lowering.type(source.result), field(resultField)));
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
    builder.CreateCall(lowering.runtime("mettle_rt_replace",
                                        builder.getVoidTy(),
                                        {builder.getPtrTy(), builder.getPtrTy(),
                                         builder.getPtrTy()}),
                       {frame, replacement.destroy, replacement.install});
  } else {
    builder.CreateStore(value, address(instruction.place));
    auto node = placeNode(instruction.place);
    if (node != std::numeric_limits<unsigned>::max()) {
      set(node, true);
      updateParents(node);
    }
  }
}

void CleanupFrame::scopeExit(int scope) {
  for (int node : plan.scopes.at(scope))
    callDrop(planNodes[node],
             lowering.builder.CreateCall(lowering.runtime(
                 "mettle_rt_panicking", lowering.builder.getInt32Ty(), {})));
}

void CleanupFrame::returnValue(ir::Value value, llvm::Value *result) {
  if (source.result != Type::Unit && source.result != Type::Never) {
    lowering.builder.CreateStore(result, field(resultField));
    consume(value);
  }
  lowering.builder.CreateRetVoid();
}
} // namespace mettle::backend
