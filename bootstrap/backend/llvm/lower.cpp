#include "backend/llvm/lower.h"
#include "backend/llvm/abi.h"
#include "backend/llvm/cleanup.h"
#include "backend/llvm/object.h"
#include "backend/llvm/target.h"
#include "support/path.h"
#include "types/layout.h"
#include "llvm/IR/InlineAsm.h"

#include "llvm/ADT/APFloat.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/TargetParser/Triple.h"
#include <algorithm>
#include <map>
#include <optional>
#include <set>
#include <tuple>

namespace mettle::backend {
namespace {
std::optional<Type> pinnedViewPayload(const TypeStore &types, Type type) {
  if (!types.isProduct(type) ||
      types.product(type).kind != AggregateKind::Pin ||
      types.product(type).components.empty())
    return std::nullopt;
  auto view = types.product(type).components.front();
  if (!types.isView(view) || types.view(view).mode != ParameterMode::Mut)
    return std::nullopt;
  return types.view(view).payload;
}

bool pinnedErasedReceiver(const TypeStore &types, Type type) {
  auto payload = pinnedViewPayload(types, type);
  return payload && types.isErased(*payload);
}

void applyInlineHint(llvm::Function &function, ir::InlineHint hint) {
  switch (hint) {
  case ir::InlineHint::Default:
    break;
  case ir::InlineHint::Hint:
    function.addFnAttr(llvm::Attribute::InlineHint);
    break;
  case ir::InlineHint::Always:
    function.addFnAttr(llvm::Attribute::AlwaysInline);
    break;
  case ir::InlineHint::Never:
    function.addFnAttr(llvm::Attribute::NoInline);
    break;
  }
}

class Lowerer {
public:
  Lowerer(const ir::Program &program, llvm::LLVMContext &context,
          llvm::StringRef target, bool freestanding,
          const DebugInfoRequest *debug, bool sanitizeAddress,
          bool sanitizeThread, CodegenPartition partition)
      : program(program), context(context), partition(std::move(partition)),
        module(std::make_unique<llvm::Module>("mettle", context)),
        builder(context),
        lowering{program, context, *module, builder, functions, {}},
        abi(lowering, program.target.arch != TargetArch::Unknown
                          ? program.target.arch == TargetArch::Aarch64
                          : llvm::Triple(target.empty() ? defaultTargetTriple()
                                                        : target.str())
                                .isAArch64()) {
    this->sanitizeAddress = sanitizeAddress;
    this->sanitizeThread = sanitizeThread;
    const auto triple = target.empty() ? defaultTargetTriple() : target.str();
    auto layout = targetDataLayout(triple);
    if (!layout)
      llvm::report_fatal_error(llvm::Twine("target data layout unavailable: ") +
                               llvm::toString(layout.takeError()));
    if (auto error = checkTargetLayout(*program.types, triple))
      llvm::report_fatal_error(llvm::Twine(llvm::toString(std::move(error))));
    module->setDataLayout(*layout);
    module->setTargetTriple(llvm::Triple(triple));
    module->addModuleFlag(llvm::Module::Error, "mettle.pointer.width", 64);
    if (!program.target.triple.empty())
      module->addModuleFlag(
          llvm::Module::Error, "mettle.target.triple",
          llvm::MDString::get(context, program.target.triple));
    lowering.freestanding = freestanding;
    if (debug)
      debugInfo = std::make_unique<DebugInfo>(*module, program, *debug);
    for (auto [state, body] : program.coroutines)
      coroutineStates.emplace(state, body);
    lowering.coroutine = [this](Type state) -> CleanupFrame & {
      return coroutineFrame(coroutineStates.at(state));
    };
    program.types->resolveCoroutineLayouts(
        [this](Type state)
            -> std::optional<std::pair<std::uint64_t, std::uint64_t>> {
          auto found = coroutineStates.find(state);
          if (found == coroutineStates.end())
            return std::nullopt;
          auto &frame = coroutineFrame(found->second);
          return std::pair{frame.size(), frame.align()};
        });
  }
  ~Lowerer() { program.types->resolveCoroutineLayouts({}); }
  Lowerer(const Lowerer &) = delete;
  Lowerer &operator=(const Lowerer &) = delete;
  std::unique_ptr<llvm::Module> run() {
    auto result = build();
    for (auto &function : *result) {
      if (function.isDeclaration())
        continue;
      if (sanitizeAddress)
        function.addFnAttr(llvm::Attribute::SanitizeAddress);
      if (sanitizeThread)
        function.addFnAttr(llvm::Attribute::SanitizeThread);
    }
    if (debugInfo)
      debugInfo->finalize();
    return result;
  }
  std::unique_ptr<llvm::Module> build() {
    for (std::size_t i = 0; i < program.statics.size(); ++i) {
      const auto &storage = program.statics[i];
      auto name = storage.externalName.empty() ? "mettle.static." + storage.name
                                               : storage.externalName;
      auto *global = module->getNamedGlobal(name);
      const bool owns = ownsStatic(i);
      const StaticConstant *initializer =
          owns && storage.initializer ? &*storage.initializer : nullptr;
      if (!initializer && !storage.externalName.empty())
        for (std::size_t other = 0; other < program.statics.size(); ++other)
          if (program.statics[other].externalName == storage.externalName &&
              program.statics[other].initializer &&
              (!partition.split || ownsStatic(other)))
            initializer = &*program.statics[other].initializer;
      if (!global)
        global = new llvm::GlobalVariable(
            *module, staticType(storage.type, initializer),
            !storage.mutableBinding && !interiorMutable(storage.type),
            storage.externalName.empty() && !partition.split
                ? llvm::GlobalValue::InternalLinkage
                : llvm::GlobalValue::ExternalLinkage,
            nullptr, name);
      if (partition.split && storage.externalName.empty()) {
        global->setVisibility(llvm::GlobalValue::HiddenVisibility);
        global->setDSOLocal(true);
      }
      global->setAlignment(llvm::Align(lowering.alignment(storage.type)));
      lowering.statics.push_back(global);
    }
    externals.resize(program.functions.size());
    signatures.resize(program.functions.size());
    for (std::size_t index = 0; index < program.functions.size(); ++index) {
      const auto &f = program.functions[index];
      std::vector<llvm::Type *> parameters;
      for (std::size_t i = 0; i < f.parameters; ++i)
        parameters.push_back(f.locals[i].mode == ParameterMode::Read ||
                                     f.locals[i].mode == ParameterMode::Mut
                                 ? builder.getPtrTy()
                                 : type(f.locals[i].type));
      if (f.variadicCursor >= 0)
        parameters.push_back(builder.getPtrTy());
      if (lowering.indirect(f.result))
        parameters.push_back(builder.getPtrTy());
      auto *signature =
          llvm::FunctionType::get(resultType(f.result), parameters, false);
      llvm::Function *function;
      if (!f.abi.empty()) {
        signatures[index] = abi.signature(f);
        if (!f.indirectContract) {
          externals[index] = llvm::cast<llvm::Function>(
              module
                  ->getOrInsertFunction(f.externalName, signatures[index]->type)
                  .getCallee());
          externals[index]->setUWTableKind(llvm::UWTableKind::Default);
          if (lowering.freestanding)
            externals[index]->addFnAttr(llvm::Attribute::NoUnwind);
          if (f.result == Type::Never)
            externals[index]->addFnAttr(llvm::Attribute::NoReturn);
          abi.attributes(*externals[index], *signatures[index]);
          targetAttributes(*externals[index], program.target, f.targetFeatures);
        }
        if (f.nakedAssembly) {
          externals[index]->addFnAttr(llvm::Attribute::Naked);
          externals[index]->addFnAttr(llvm::Attribute::NoInline);
          externals[index]->addFnAttr(llvm::Attribute::NoUnwind);
          functions.push_back(externals[index]);
          continue;
        }
        function = llvm::Function::Create(
            signature,
            f.blocks.empty() || (partition.split && !ownsFunction(index))
                ? llvm::GlobalValue::ExternalLinkage
                : llvm::GlobalValue::InternalLinkage,
            "mettle.abi." + f.name, *module);
      } else
        function =
            f.externalName.empty()
                ? llvm::Function::Create(
                      signature,
                      partition.split ? llvm::GlobalValue::ExternalLinkage
                                      : llvm::GlobalValue::InternalLinkage,
                      "mettle." + displayPath(f.name), *module)
                : llvm::cast<llvm::Function>(
                      module->getOrInsertFunction(f.externalName, signature)
                          .getCallee());
      function->setUWTableKind(llvm::UWTableKind::Default);
      if (partition.split && f.externalName.empty()) {
        function->setVisibility(llvm::GlobalValue::HiddenVisibility);
        function->setDSOLocal(true);
      }
      targetAttributes(*function, program.target, f.targetFeatures);
      if (!f.blocks.empty())
        applyInlineHint(*function, f.inlineHint);
      if (lowering.freestanding)
        function->addFnAttr(llvm::Attribute::NoUnwind);
      if (!f.abi.empty() && !signatures[index]) {
        for (std::size_t p = 0; p < f.parameters; ++p)
          if (parameters[p]->isIntegerTy() &&
              integerWidth(f.locals[p].type) < 32)
            function->addParamAttr(p, isSignedInteger(f.locals[p].type)
                                          ? llvm::Attribute::SExt
                                          : llvm::Attribute::ZExt);
        if (resultType(f.result)->isIntegerTy() && integerWidth(f.result) < 32)
          function->addRetAttr(isSignedInteger(f.result)
                                   ? llvm::Attribute::SExt
                                   : llvm::Attribute::ZExt);
      }
      if (f.result == Type::Never)
        function->addFnAttr(llvm::Attribute::NoReturn);
      functions.push_back(function);
    }
    for (std::size_t i = 0; i < program.statics.size(); ++i)
      if (ownsStatic(i) && program.statics[i].initializer)
        lowering.statics[i]->setInitializer(
            staticConstant(*program.statics[i].initializer));
    std::vector<llvm::Function *> symbols;
    for (std::size_t i = 0; i < functions.size(); ++i)
      symbols.push_back(externals[i] ? externals[i] : functions[i]);
    AssemblySymbolResolver resolveSymbol = [&](AssemblyOperand::SymbolKind kind,
                                               int id) -> llvm::GlobalValue * {
      return kind == AssemblyOperand::SymbolKind::Function
                 ? static_cast<llvm::GlobalValue *>(symbols[id])
                 : lowering.statics[id];
    };
    for (const auto &assembly : program.globalAssembly)
      module->appendModuleInlineAsm(
          globalAssembly(lowering, assembly, resolveSymbol));
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (ownsFunction(i) && program.functions[i].nakedAssembly) {
        const auto &assembly = *program.functions[i].nakedAssembly;
        auto text = globalAssembly(lowering, assembly, resolveSymbol);
        for (std::size_t dollar = 0;
             (dollar = text.find('$', dollar)) != std::string::npos;
             dollar += 2)
          text.insert(dollar, "$");
        builder.SetInsertPoint(
            llvm::BasicBlock::Create(context, "naked", functions[i]));
        auto *code = llvm::InlineAsm::get(
            llvm::FunctionType::get(builder.getVoidTy(), false), text, "", true,
            false, llvm::InlineAsm::AD_ATT, false);
        auto *call = builder.CreateCall(code);
        call->addFnAttr(llvm::Attribute::NoUnwind);
        builder.CreateUnreachable();
      }
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (ownsFunction(i) && !program.functions[i].blocks.empty())
        function(program.functions[i], functions[i]);
    if (debugInfo)
      debugInfo->clear(builder);
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (externals[i] && ownsFunction(i) &&
          !program.functions[i].blocks.empty() &&
          !program.functions[i].nakedAssembly)
        abi.exportBody(*externals[i], *functions[i], *signatures[i]);
    if (lowering.freestanding || !partition.emitEntry)
      return std::move(module);
    for (std::size_t i = 0; i < functions.size(); ++i)
      if ((!partition.split || partition.packageIdentity.empty()) &&
          program.functions[i].name == "main" &&
          program.functions[i].externalName == "main")
        return std::move(module);
    if (partition.split && !partition.packageIdentity.empty())
      return std::move(module);
    auto *entry = llvm::Function::Create(
        llvm::FunctionType::get(builder.getInt32Ty(), false),
        llvm::GlobalValue::ExternalLinkage, "main", *module);
    entry->setUWTableKind(llvm::UWTableKind::Default);
    builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", entry));
    for (std::size_t i = 0; i < functions.size(); ++i)
      if (program.functions[i].name == "main") {
        auto *callback = lowering.callback("mettle.main");
        auto saved = builder.saveIP();
        builder.SetInsertPoint(
            llvm::BasicBlock::Create(context, "entry", callback));
        auto *result = builder.CreateCall(functions[i]);
        builder.CreateStore(result, callback->getArg(0));
        builder.CreateRetVoid();
        builder.restoreIP(saved);
        auto *resultSlot = builder.CreateAlloca(builder.getInt32Ty());
        builder.CreateStore(builder.getInt32(0), resultSlot);
        // A nonzero runtime status (uncaught source panic) replaces the result.
        auto *status = builder.CreateCall(
            lowering.runtime("mettle_rt_main", builder.getInt32Ty(),
                             {builder.getPtrTy(), builder.getPtrTy()}),
            {resultSlot, callback});
        builder.CreateRet(builder.CreateSelect(
            builder.CreateICmpNE(status, builder.getInt32(0)), status,
            builder.CreateLoad(builder.getInt32Ty(), resultSlot)));
        break;
      }
    return std::move(module);
  }
  bool checked = true;

private:
  const ir::Program &program;
  llvm::LLVMContext &context;
  bool sanitizeAddress = false, sanitizeThread = false;
  CodegenPartition partition;
  std::unique_ptr<llvm::Module> module;
  llvm::IRBuilder<> builder;
  std::vector<llvm::Function *> functions;
  LoweringContext lowering;
  CAbi abi;
  std::vector<llvm::Function *> externals;
  std::vector<std::optional<CAbiSignature>> signatures;
  using WitnessKey =
      std::tuple<Type, Type, Type, std::vector<llvm::Constant *>>;
  std::map<WitnessKey, llvm::GlobalVariable *> witnesses;
  std::map<std::tuple<int, Type, Type>, llvm::Function *> pinnedWitnessThunks;
  std::map<std::string, llvm::GlobalVariable *> textLiterals;
  std::unique_ptr<DebugInfo> debugInfo;
  std::map<Type, int> coroutineStates;
  std::map<int, std::unique_ptr<CleanupFrame>> coroutineFrames;
  std::set<int> buildingFrames;

  bool ownsFunction(std::size_t index) const {
    if (!partition.split)
      return true;
    return index < program.functionPackages.size() &&
           program.functionPackages[index] == partition.packageIdentity;
  }

  bool ownsStatic(std::size_t index) const {
    if (!partition.split)
      return true;
    return index < program.staticPackages.size() &&
           program.staticPackages[index] == partition.packageIdentity;
  }

  // Frames are built on first use, so a state embedding another state's
  // future lays out the inner frame first.
  CleanupFrame &coroutineFrame(int body) {
    if (auto found = coroutineFrames.find(body); found != coroutineFrames.end())
      return *found->second;
    if (!buildingFrames.insert(body).second)
      llvm::report_fatal_error("async body contains its own state");
    auto frame = std::make_unique<CleanupFrame>(
        lowering, program.functions[body],
        "mettle.coroutine." + program.functions[body].name);
    if (partition.split)
      for (auto *callback : {frame->body(), frame->unwind()}) {
        callback->setLinkage(llvm::GlobalValue::ExternalLinkage);
        callback->setVisibility(llvm::GlobalValue::HiddenVisibility);
        callback->setDSOLocal(true);
      }
    if (debugInfo)
      for (const auto &[state, coroutineBody] : program.coroutines)
        if (coroutineBody == body)
          debugInfo->describeCoroutine(
              state, program.functions[body], frame->structure(),
              frame->stateFieldIndex(), frame->outputFieldIndex(),
              frame->localFieldIndices());
    buildingFrames.erase(body);
    return *coroutineFrames.emplace(body, std::move(frame)).first->second;
  }

  bool interiorMutable(Type value) {
    if (!program.types->isProduct(value))
      return false;
    const auto &record = program.types->product(value);
    switch (record.kind) {
    case AggregateKind::Product:
    case AggregateKind::Enumeration:
    case AggregateKind::Optional:
    case AggregateKind::Outcome:
    case AggregateKind::Tuple:
    case AggregateKind::Array:
    case AggregateKind::Range:
    case AggregateKind::Opaque:
    case AggregateKind::Uninit:
    case AggregateKind::ManualDrop:
    case AggregateKind::Pin:
    case AggregateKind::Ordering:
    case AggregateKind::PhantomPinned:
      break;
    default:
      return true;
    }
    for (const auto &field : record.fields)
      if (interiorMutable(field.type))
        return true;
    return false;
  }
  llvm::Type *staticType(Type value,
                         const StaticConstant *initializer = nullptr) {
    if (!program.types->isProduct(value))
      return lowering.storageType(value);
    StaticConstant shape;
    shape.type = value;
    if (program.types->isSum(value) ||
        program.types->product(value).layout.unionType)
      shape.selection = 0;
    if (initializer && initializer->kind == StaticConstant::Kind::Repeat)
      return llvm::ArrayType::get(
          staticType(program.types->product(value).components[0],
                     &initializer->fields[0]),
          *program.types->arrayLength(value));
    auto members =
        staticConstantFields(*program.types, initializer ? *initializer : shape)
            .value();
    const auto &layout = lowering.layout(value);
    auto offsetOf = [&](unsigned field) {
      return program.types->compactArray(value)
                 ? field *
                       lowering
                           .layout(program.types->product(value).components[0])
                           .size
                 : layout.fields[field];
    };
    std::vector<llvm::Type *> fields;
    std::uint64_t offset = 0;
    for (std::size_t i = 0; i < members.size(); ++i) {
      auto [field, type] = members[i];
      if (offsetOf(field) > offset)
        fields.push_back(llvm::ArrayType::get(builder.getInt8Ty(),
                                              offsetOf(field) - offset));
      fields.push_back(
          staticType(type, initializer ? &initializer->fields[i] : nullptr));
      offset = offsetOf(field) + lowering.layout(type).size;
    }
    if (layout.size > offset)
      fields.push_back(
          llvm::ArrayType::get(builder.getInt8Ty(), layout.size - offset));
    auto *result = llvm::StructType::get(context, fields, true);
    return result;
  }
  llvm::GlobalVariable *textGlobal(const std::string &text) {
    auto &global = textLiterals[text];
    if (!global) {
      global = new llvm::GlobalVariable(
          *module, llvm::ArrayType::get(builder.getInt8Ty(), text.size()), true,
          llvm::GlobalValue::PrivateLinkage,
          llvm::ConstantDataArray::getString(context, text, false),
          "mettle.text");
      global->setUnnamedAddr(llvm::GlobalValue::UnnamedAddr::Global);
      global->setAlignment(llvm::Align(1));
    }
    return global;
  }
  llvm::Constant *staticConstant(const StaticConstant &value) {
    if (value.kind == StaticConstant::Kind::Pointer) {
      auto *integer =
          llvm::ConstantInt::get(module->getDataLayout().getIntPtrType(context),
                                 value.scalar.magnitude[0]);
      auto *pointer = llvm::ConstantExpr::getIntToPtr(
          integer, llvm::PointerType::getUnqual(context));
      if (value.fields.empty())
        return pointer;
      return llvm::ConstantStruct::get(
          llvm::cast<llvm::StructType>(staticType(value.type)),
          {pointer, staticConstant(value.fields.front())});
    }
    if (value.kind == StaticConstant::Kind::Text) {
      auto *global = textGlobal(value.text);
      auto *integerType = module->getDataLayout().getIntPtrType(context);
      auto *address = llvm::ConstantExpr::getGetElementPtr(
          builder.getInt8Ty(), global,
          llvm::ConstantInt::get(integerType, value.byteOffset));
      if (auto *fat = llvm::dyn_cast<llvm::StructType>(staticType(value.type)))
        return llvm::ConstantStruct::get(
            fat, {address,
                  llvm::ConstantInt::get(
                      integerType, *textConstantCount(*program.types, value))});
      return address;
    }
    if (value.kind == StaticConstant::Kind::Function)
      return externals.at(value.symbol) ? externals[value.symbol]
                                        : functions.at(value.symbol);
    if (value.kind == StaticConstant::Kind::Address) {
      auto type = program.statics.at(value.symbol).type;
      std::uint64_t offset = value.byteOffset;
      for (auto field : value.projections) {
        offset += lowering.layout(type).fields.at(field);
        type = program.types->product(type).fields.at(field).type;
      }
      auto *address = llvm::ConstantExpr::getGetElementPtr(
          builder.getInt8Ty(), lowering.statics.at(value.symbol),
          builder.getInt64(offset));
      if (program.types->pointerMetadata(
              program.types->view(value.type).payload) ==
          PointerMetadata::ElementCount)
        return llvm::ConstantStruct::get(
            llvm::cast<llvm::StructType>(staticType(value.type)),
            {address, builder.getInt64(value.scalar.magnitude[0])});
      return address;
    }
    if (value.kind == StaticConstant::Kind::Repeat) {
      auto *array = llvm::cast<llvm::ArrayType>(staticType(value.type, &value));
      auto *element = staticConstant(value.fields[0]);
      if (element->isNullValue())
        return llvm::ConstantAggregateZero::get(array);
      return llvm::ConstantArray::get(
          array,
          std::vector<llvm::Constant *>(array->getNumElements(), element));
    }
    if (value.kind == StaticConstant::Kind::Aggregate) {
      auto members = staticConstantFields(*program.types, value).value();
      const auto &layout = lowering.layout(value.type);
      auto offsetOf = [&](unsigned field) {
        return program.types->compactArray(value.type)
                   ? field * lowering
                                 .layout(program.types->product(value.type)
                                             .components[0])
                                 .size
                   : layout.fields[field];
      };
      auto *representation =
          llvm::cast<llvm::StructType>(staticType(value.type, &value));
      std::vector<llvm::Constant *> fields;
      std::uint64_t offset = 0;
      for (std::size_t i = 0; i < members.size(); ++i) {
        auto [field, type] = members[i];
        if (offsetOf(field) > offset)
          fields.push_back(llvm::Constant::getNullValue(
              representation->getElementType(fields.size())));
        fields.push_back(staticConstant(value.fields.at(i)));
        offset = offsetOf(field) + lowering.layout(type).size;
      }
      if (layout.size > offset)
        fields.push_back(llvm::Constant::getNullValue(
            representation->getElementType(fields.size())));
      return llvm::ConstantStruct::get(representation, fields);
    }
    if (isFloating(value.type)) {
      if (value.scalar.floatingBits) {
        llvm::APFloat number(value.type == Type::F32
                                 ? llvm::APFloat::IEEEsingle()
                                 : llvm::APFloat::IEEEdouble(),
                             llvm::APInt(value.type == Type::F32 ? 32 : 64,
                                         *value.scalar.floatingBits));
        return llvm::ConstantFP::get(context, number);
      }
      llvm::APFloat number(value.type == Type::F32
                               ? llvm::APFloat::IEEEsingle()
                               : llvm::APFloat::IEEEdouble());
      llvm::cantFail(number.convertFromString(
          value.scalar.floating, llvm::APFloat::rmNearestTiesToEven));
      return llvm::ConstantFP::get(context, number);
    }
    if (value.type == Type::Unit)
      return llvm::Constant::getNullValue(staticType(value.type));
    unsigned width = value.type == Type::Bool   ? 8
                     : value.type == Type::Char ? 32
                                                : integerWidth(value.type);
    llvm::APInt bits(
        width,
        llvm::ArrayRef(value.scalar.magnitude).take_front(width > 64 ? 2 : 1));
    return llvm::ConstantInt::get(context,
                                  value.scalar.negative ? -bits : bits);
  }

  llvm::GlobalVariable *witness(Type concrete, Type root, Type target,
                                const std::vector<llvm::Constant *> &methods) {
    WitnessKey key{concrete, root, target, methods};
    if (auto found = witnesses.find(key); found != witnesses.end())
      return found->second;
    const auto &source = program.types->erased(root);
    const auto &destination = program.types->erased(target);
    std::vector<llvm::Constant *> entries;
    auto metadata = program.types->pointerMetadata(concrete);
    entries.push_back(metadata == PointerMetadata::ElementCount
                          ? llvm::ConstantExpr::getIntToPtr(builder.getInt64(1),
                                                            builder.getPtrTy())
                          : llvm::ConstantPointerNull::get(builder.getPtrTy()));
    auto layoutType = concrete;
    std::uint64_t prefixSize = 0;
    if (metadata == PointerMetadata::ElementCount) {
      while (program.types->isProduct(layoutType) &&
             !program.types->product(layoutType).fields.empty()) {
        prefixSize += lowering.layout(layoutType).fields.back();
        layoutType = program.types->product(layoutType).fields.back().type;
      }
      if (program.types->isSlice(layoutType))
        layoutType = program.types->slice(layoutType).element;
    }
    entries.push_back(llvm::ConstantExpr::getIntToPtr(
        builder.getInt64(lowering.layout(layoutType).size),
        builder.getPtrTy()));
    entries.push_back(llvm::ConstantExpr::getIntToPtr(
        builder.getInt64(lowering.alignment(concrete)), builder.getPtrTy()));
    auto drop = std::find_if(
        program.dynamicDropFunctions.begin(),
        program.dynamicDropFunctions.end(),
        [&](const auto &entry) { return entry.first == concrete; });
    bool hasDrop = drop != program.dynamicDropFunctions.end() &&
                   drop->second >= 0 &&
                   static_cast<std::size_t>(drop->second) < functions.size();
    entries.push_back(hasDrop
                          ? static_cast<llvm::Constant *>(functions.at(
                                static_cast<std::size_t>(drop->second)))
                          : llvm::ConstantPointerNull::get(builder.getPtrTy()));
    entries.push_back(llvm::ConstantExpr::getIntToPtr(
        builder.getInt64(prefixSize), builder.getPtrTy()));
    for (std::size_t method = 0; method < destination.methodSlots.size();
         ++method) {
      std::size_t index = source.methodSlots.size();
      for (std::size_t candidate = 0; candidate < source.methodSlots.size();
           ++candidate)
        if (source.methodOwners[candidate] ==
                destination.methodOwners[method] &&
            source.methodSlots[candidate] == destination.methodSlots[method]) {
          index = candidate;
          break;
        }
      if (index == source.methodSlots.size())
        llvm::report_fatal_error("parent witness has no verified method");
      entries.push_back(methods[index]);
    }
    for (auto parent : destination.parentInterfaces)
      entries.push_back(witness(concrete, root, parent, methods));
    auto *initializer = llvm::ConstantArray::get(
        llvm::ArrayType::get(builder.getPtrTy(), entries.size()), entries);
    auto *table = new llvm::GlobalVariable(
        *module, initializer->getType(), true,
        llvm::GlobalValue::PrivateLinkage, initializer, "mettle.witness");
    witnesses.emplace(std::move(key), table);
    return table;
  }

  // Set while lowering a large result that the next store would only copy.
  llvm::Value *resultDestination = nullptr;
  llvm::Type *type(Type t) { return lowering.type(t); }
  llvm::Type *resultType(Type t) { return lowering.resultType(t); }
  llvm::Value *unit() { return llvm::Constant::getNullValue(type(Type::Unit)); }
  llvm::Value *call(const ir::Instruction &instruction, llvm::Value *target,
                    llvm::ArrayRef<llvm::Value *> arguments,
                    const std::set<std::string> &callerFeatures) {
    if (instruction.op == ir::Op::IndirectCall && instruction.erasedDispatch) {
      const auto &signature = program.types->callable(instruction.indirectType);
      std::vector<llvm::Type *> parameters;
      for (const auto &parameter : signature.parameters)
        parameters.push_back(parameter.mode == ParameterMode::Read ||
                                     parameter.mode == ParameterMode::Mut
                                 ? builder.getPtrTy()
                                 : type(parameter.type));
      if (lowering.indirect(signature.abiResult))
        parameters.push_back(builder.getPtrTy());
      auto *callType = llvm::FunctionType::get(resultType(signature.abiResult),
                                               parameters, signature.variadic);
      std::vector<llvm::Value *> actual(arguments.begin(), arguments.end());
      llvm::Value *returned = nullptr;
      if (lowering.indirect(signature.abiResult)) {
        returned = resultDestination ? resultDestination
                                     : lowering.temporary(signature.abiResult);
        actual.push_back(returned);
      }
      auto *value = builder.CreateCall(callType, target, actual);
      return returned ? returned
             : signature.abiResult == Type::Unit ||
                     signature.abiResult == Type::Never
                 ? unit()
                 : value;
    }
    auto index = instruction.callee;
    const auto &callee = program.functions[index];
    if (!target)
      target = signatures[index] ? externals[index] : functions[index];
    auto invoke =
        [&](llvm::Value *called,
            llvm::ArrayRef<llvm::Value *> parameters) -> llvm::Value * {
      if (signatures[index]) {
        std::vector<Type> argumentTypes;
        for (auto operand : instruction.operands)
          argumentTypes.push_back(operand.type);
        return abi.call(called, *signatures[index], parameters, argumentTypes);
      }
      std::vector<llvm::Value *> actual(parameters.begin(), parameters.end());
      llvm::Value *returned = nullptr;
      if (lowering.indirect(instruction.result.type)) {
        returned = resultDestination
                       ? resultDestination
                       : lowering.temporary(instruction.result.type);
        actual.push_back(returned);
      }
      auto *result = builder.CreateCall(functions[index]->getFunctionType(),
                                        called, actual);
      return returned ? returned
             : instruction.result.type == Type::Unit ||
                     instruction.result.type == Type::Never
                 ? unit()
                 : result;
    };
    std::function<unsigned(llvm::Type *)> vectorWidth =
        [&](llvm::Type *type) -> unsigned {
      if (auto *vector = llvm::dyn_cast<llvm::FixedVectorType>(type))
        return vector->getPrimitiveSizeInBits().getFixedValue();
      unsigned width = 0;
      if (auto *record = llvm::dyn_cast<llvm::StructType>(type))
        for (auto *element : record->elements())
          width = std::max(width, vectorWidth(element));
      if (auto *array = llvm::dyn_cast<llvm::ArrayType>(type))
        width = vectorWidth(array->getElementType());
      return width;
    };
    unsigned width = vectorWidth(functions[index]->getReturnType());
    for (auto *argument : arguments)
      width = std::max(width, vectorWidth(argument->getType()));
    if (signatures[index]) {
      auto *physical = signatures[index]->type;
      width = std::max(width, vectorWidth(physical->getReturnType()));
      for (auto *parameter : physical->params())
        width = std::max(width, vectorWidth(parameter));
    }
    auto differs = [&](const std::string &feature) {
      return featuresAvailable(program.target, callerFeatures, {feature}) !=
             featuresAvailable(program.target, callee.targetFeatures,
                               {feature});
    };
    if (program.target.arch != TargetArch::X86_64 ||
        !((width > 128 && differs("avx")) ||
          (width > 256 && differs("avx512f"))))
      return invoke(target, arguments);

    // Feature guards permit a call, but do not change the caller's vector ABI.
    std::vector<llvm::Type *> parameters(arguments.size() + 2,
                                         builder.getPtrTy());
    auto *bridge = llvm::Function::Create(
        llvm::FunctionType::get(builder.getVoidTy(), parameters, false),
        llvm::GlobalValue::InternalLinkage, "mettle.feature.call", *module);
    targetAttributes(*bridge, program.target, callee.targetFeatures);
    bridge->addFnAttr(llvm::Attribute::NoInline);
    bridge->setUWTableKind(llvm::UWTableKind::Default);
    auto saved = builder.saveIP();
    builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", bridge));
    std::vector<llvm::Value *> loaded;
    for (std::size_t i = 0; i < arguments.size(); ++i)
      loaded.push_back(builder.CreateAlignedLoad(
          arguments[i]->getType(), bridge->getArg(i + 2), llvm::Align(1)));
    auto *returned = invoke(bridge->getArg(1), loaded);
    bool hasResult = instruction.result.type != Type::Unit &&
                     instruction.result.type != Type::Never;
    if (hasResult)
      builder.CreateAlignedStore(returned, bridge->getArg(0), llvm::Align(1));
    if (instruction.result.type == Type::Never)
      builder.CreateUnreachable();
    else
      builder.CreateRetVoid();
    builder.restoreIP(saved);
    llvm::IRBuilder<> entry(
        &builder.GetInsertBlock()->getParent()->getEntryBlock(),
        builder.GetInsertBlock()->getParent()->getEntryBlock().begin());
    auto *result = entry.CreateAlloca(hasResult ? type(instruction.result.type)
                                                : builder.getInt8Ty());
    std::vector<llvm::Value *> storage{result, target};
    for (auto *argument : arguments) {
      auto *slot = entry.CreateAlloca(argument->getType());
      builder.CreateStore(argument, slot);
      storage.push_back(slot);
    }
    builder.CreateCall(bridge, storage);
    return hasResult ? builder.CreateLoad(type(instruction.result.type), result)
                     : unit();
  }
  llvm::Function *pinnedWitnessThunk(const ir::Instruction &instruction) {
    auto key = std::tuple{instruction.callee, instruction.interfaceSelf,
                          instruction.result.type};
    if (auto found = pinnedWitnessThunks.find(key);
        found != pinnedWitnessThunks.end())
      return found->second;
    const auto &contract = program.types->callable(instruction.result.type);
    const auto &implementation = program.functions[instruction.callee];
    std::vector<llvm::Type *> parameters;
    for (const auto &parameter : contract.parameters)
      parameters.push_back(parameter.mode == ParameterMode::Read ||
                                   parameter.mode == ParameterMode::Mut
                               ? builder.getPtrTy()
                               : type(parameter.type));
    bool indirectResult = lowering.indirect(contract.abiResult);
    if (indirectResult)
      parameters.push_back(builder.getPtrTy());
    auto *signature = llvm::FunctionType::get(resultType(contract.abiResult),
                                              parameters, contract.variadic);
    auto *thunk = llvm::Function::Create(
        signature, llvm::GlobalValue::InternalLinkage,
        "mettle.pinned-witness." + std::to_string(pinnedWitnessThunks.size()),
        *module);
    thunk->setUWTableKind(llvm::UWTableKind::Default);
    targetAttributes(*thunk, program.target, implementation.targetFeatures);
    pinnedWitnessThunks.emplace(key, thunk);

    auto saved = builder.saveIP();
    builder.SetInsertPoint(llvm::BasicBlock::Create(context, "entry", thunk));
    auto receiverType = contract.parameters.front().type;
    auto *view = lowering.extract(thunk->getArg(0), receiverType, 0);
    auto *data = builder.CreateExtractValue(view, 0);
    auto concreteReceiver = implementation.locals[0].type;
    auto *pinned = lowering.construct(concreteReceiver, {data});
    std::vector<llvm::Value *> arguments{pinned};
    for (std::size_t p = 1; p < contract.parameters.size(); ++p)
      arguments.push_back(thunk->getArg(static_cast<unsigned>(p)));
    if (indirectResult)
      arguments.push_back(
          thunk->getArg(static_cast<unsigned>(contract.parameters.size())));
    auto *result =
        builder.CreateCall(functions[instruction.callee]->getFunctionType(),
                           functions[instruction.callee], arguments);
    if (contract.abiResult == Type::Never)
      builder.CreateUnreachable();
    else if (contract.abiResult == Type::Unit || indirectResult)
      builder.CreateRetVoid();
    else
      builder.CreateRet(result);
    builder.restoreIP(saved);
    return thunk;
  }
  llvm::Value *repack(llvm::Value *value, Type source, Type target) {
    if (source == target ||
        (!lowering.indirect(source) && !lowering.indirect(target) &&
         type(source) == type(target)))
      return value;
    if (program.types->isOpaque(source))
      return repack(value, program.types->product(source).fields[0].type,
                    target);
    if (program.types->isOpaque(target))
      return repack(value, source,
                    program.types->product(target).fields[0].type);
    if (program.types->isProduct(source) && program.types->isProduct(target)) {
      std::vector<llvm::Value *> fields;
      const auto &from = program.types->product(source).fields;
      const auto &to = program.types->product(target).fields;
      for (std::size_t field = 0; field < from.size(); ++field)
        fields.push_back(repack(lowering.extract(value, source, field),
                                from[field].type, to[field].type));
      return lowering.construct(target, fields);
    }
    llvm::report_fatal_error("invalid checked opaque representation adapter");
  }
  llvm::Value *repeatArray(Type array, llvm::Value *value,
                           llvm::Value *destination) {
    auto element = program.types->product(array).components[0];
    auto count = *program.types->arrayLength(array);
    auto stride = lowering.layout(element).size;
    auto *storage = destination ? destination : lowering.temporary(array);
    auto alignment = llvm::Align(lowering.alignment(array));
    auto *base = storage;
    std::optional<std::uint8_t> pattern;
    if (auto *constant = llvm::dyn_cast<llvm::Constant>(value)) {
      if (constant->isNullValue())
        pattern = 0;
      else if (auto *integer = llvm::dyn_cast<llvm::ConstantInt>(constant);
               integer && integer->getBitWidth() % 8 == 0 &&
               integer->getBitWidth() / 8 == stride) {
        auto bits = integer->getValue();
        auto byte = bits.trunc(8).getZExtValue();
        bool uniform = true;
        for (unsigned at = 8; at < bits.getBitWidth(); at += 8)
          uniform &= bits.extractBitsAsZExtValue(8, at) == byte;
        if (uniform)
          pattern = static_cast<std::uint8_t>(byte);
      }
    }
    if (pattern || !count || !stride) {
      builder.CreateMemSet(base, builder.getInt8(pattern.value_or(0)),
                           count * stride, alignment);
    } else {
      auto *function = builder.GetInsertBlock()->getParent();
      auto *before = builder.GetInsertBlock();
      auto *loop = llvm::BasicBlock::Create(context, "repeat.loop", function);
      auto *body = llvm::BasicBlock::Create(context, "repeat.body", function);
      auto *done = llvm::BasicBlock::Create(context, "repeat.done", function);
      builder.CreateMemSet(base, builder.getInt8(0), count * stride, alignment);
      builder.CreateBr(loop);
      builder.SetInsertPoint(loop);
      auto *index = builder.CreatePHI(builder.getInt64Ty(), 2);
      index->addIncoming(builder.getInt64(0), before);
      builder.CreateCondBr(
          builder.CreateICmpULT(index, builder.getInt64(count)), body, done);
      builder.SetInsertPoint(body);
      auto *slot =
          builder.CreateGEP(builder.getInt8Ty(), base,
                            builder.CreateMul(index, builder.getInt64(stride)));
      lowering.store(element, value, slot,
                     llvm::Align(lowering.alignment(element)));
      auto *next = builder.CreateAdd(index, builder.getInt64(1));
      builder.CreateBr(loop);
      index->addIncoming(next, body);
      builder.SetInsertPoint(done);
    }
    return lowering.indirect(array)
               ? storage
               : builder.CreateLoad(lowering.layoutType(array), storage);
  }
  void emitPanic(std::int32_t code = 1) {
    if (lowering.freestanding) {
      builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), llvm::Intrinsic::trap));
      return;
    }
    auto function = lowering.runtime("mettle_rt_panic", builder.getVoidTy(),
                                     {builder.getInt32Ty()});
    llvm::cast<llvm::Function>(function.getCallee())
        ->addFnAttr(llvm::Attribute::NoReturn);
    builder.CreateCall(function, {builder.getInt32(code)});
  }
  void panicIf(llvm::Value *condition, std::int32_t code = 1) {
    auto *function = builder.GetInsertBlock()->getParent();
    auto *panic = llvm::BasicBlock::Create(context, "panic", function);
    auto *next = llvm::BasicBlock::Create(context, "checked", function);
    builder.CreateCondBr(condition, panic, next);
    builder.SetInsertPoint(panic);
    emitPanic(code);
    builder.CreateUnreachable();
    builder.SetInsertPoint(next);
  }
  llvm::Value *binary(const std::string &op, llvm::Value *a, llvm::Value *b,
                      Type operand) {
    if (program.types->isPointer(operand) && a->getType()->isStructTy()) {
      llvm::Value *equal = builder.getTrue(), *less = builder.getFalse();
      auto *representation = llvm::cast<llvm::StructType>(a->getType());
      for (unsigned field = 0; field < representation->getNumElements();
           ++field) {
        auto *left = builder.CreateExtractValue(a, field);
        auto *right = builder.CreateExtractValue(b, field);
        less = builder.CreateOr(
            less, builder.CreateAnd(equal, builder.CreateICmpULT(left, right)));
        equal = builder.CreateAnd(equal, builder.CreateICmpEQ(left, right));
      }
      if (op == "==")
        return equal;
      if (op == "!=")
        return builder.CreateNot(equal);
      if (op == "<")
        return less;
      if (op == "<=")
        return builder.CreateOr(less, equal);
      if (op == ">")
        return builder.CreateNot(builder.CreateOr(less, equal));
      return builder.CreateNot(less);
    }
    if (isFloating(operand)) {
      if (op == "+")
        return builder.CreateFAdd(a, b);
      if (op == "-")
        return builder.CreateFSub(a, b);
      if (op == "*")
        return builder.CreateFMul(a, b);
      if (op == "/")
        return builder.CreateFDiv(a, b);
      if (op == "%")
        return builder.CreateFRem(a, b);
      if (op == "==")
        return builder.CreateFCmpOEQ(a, b);
      if (op == "!=")
        return builder.CreateFCmpUNE(a, b);
      if (op == "<")
        return builder.CreateFCmpOLT(a, b);
      if (op == "<=")
        return builder.CreateFCmpOLE(a, b);
      if (op == ">")
        return builder.CreateFCmpOGT(a, b);
      if (op == ">=")
        return builder.CreateFCmpOGE(a, b);
    }
    bool sign = isSignedInteger(operand);
    auto integer = [&](std::uint64_t value) {
      return llvm::ConstantInt::get(a->getType(), value);
    };
    if (op == "+" || op == "-" || op == "*") {
      if (checked) {
        auto intrinsic =
            op == "+"   ? (sign ? llvm::Intrinsic::sadd_with_overflow
                                : llvm::Intrinsic::uadd_with_overflow)
            : op == "-" ? (sign ? llvm::Intrinsic::ssub_with_overflow
                                : llvm::Intrinsic::usub_with_overflow)
                        : (sign ? llvm::Intrinsic::smul_with_overflow
                                : llvm::Intrinsic::umul_with_overflow);
        auto *fn = llvm::Intrinsic::getOrInsertDeclaration(
            module.get(), intrinsic, {a->getType()});
        auto *result = builder.CreateCall(fn, {a, b});
        auto *value = builder.CreateExtractValue(result, 0);
        panicIf(builder.CreateExtractValue(result, 1));
        return value;
      }
      if (op == "+")
        return builder.CreateAdd(a, b);
      if (op == "-")
        return builder.CreateSub(a, b);
      return builder.CreateMul(a, b);
    }
    if (op == "/" || op == "%") {
      auto *invalid = builder.CreateICmpEQ(b, integer(0));
      if (sign) {
        auto width = integerWidth(operand);
        auto *minimum = llvm::ConstantInt::get(
            context, llvm::APInt::getSignedMinValue(width));
        auto *minusOne =
            llvm::ConstantInt::get(context, llvm::APInt::getAllOnes(width));
        invalid = builder.CreateOr(
            invalid, builder.CreateAnd(builder.CreateICmpEQ(a, minimum),
                                       builder.CreateICmpEQ(b, minusOne)));
      }
      panicIf(invalid);
      return op == "/"
                 ? (sign ? builder.CreateSDiv(a, b) : builder.CreateUDiv(a, b))
                 : (sign ? builder.CreateSRem(a, b) : builder.CreateURem(a, b));
    }
    if (op == "<<" || op == ">>") {
      if (checked)
        panicIf(builder.CreateICmpUGE(
            b, llvm::ConstantInt::get(b->getType(), integerWidth(operand))));
      b = builder.CreateAnd(
          b, llvm::ConstantInt::get(b->getType(), integerWidth(operand) - 1));
      b = builder.CreateZExtOrTrunc(b, a->getType());
      return op == "<<" ? builder.CreateShl(a, b)
             : sign     ? builder.CreateAShr(a, b)
                        : builder.CreateLShr(a, b);
    }
    if (op == "&")
      return builder.CreateAnd(a, b);
    if (op == "|")
      return builder.CreateOr(a, b);
    if (op == "^")
      return builder.CreateXor(a, b);
    if (operand == Type::Unit)
      return builder.getInt1(op == "==" || op == "<=" || op == ">=");
    if (op == "==")
      return builder.CreateICmpEQ(a, b);
    if (op == "!=")
      return builder.CreateICmpNE(a, b);
    if (op == "<")
      return sign ? builder.CreateICmpSLT(a, b) : builder.CreateICmpULT(a, b);
    if (op == "<=")
      return sign ? builder.CreateICmpSLE(a, b) : builder.CreateICmpULE(a, b);
    if (op == ">")
      return sign ? builder.CreateICmpSGT(a, b) : builder.CreateICmpUGT(a, b);
    if (op == ">=")
      return sign ? builder.CreateICmpSGE(a, b) : builder.CreateICmpUGE(a, b);
    llvm_unreachable("unknown checked binary operation");
  }
  llvm::Value *cast(llvm::Value *value, Type source, Type target) {
    auto *destination = type(target);
    if (source == target)
      return value;
    if (fieldlessEnumeration(*program.types, source)) {
      auto *storage = lowering.temporary(source);
      builder.CreateStore(value, storage);
      auto *tag = lowering.enumTag(source, storage, false);
      return builder.CreateIntCast(
          tag, destination,
          isSignedInteger(program.types->product(source).layout.tag));
    }
    if (program.types->isPointer(target)) {
      if (value->getType()->isStructTy() && destination->isPointerTy())
        return builder.CreateExtractValue(value, 0);
      return value;
    }
    if (isFloating(source) && isFloating(target))
      return source == Type::F32 ? builder.CreateFPExt(value, destination)
                                 : builder.CreateFPTrunc(value, destination);
    if (isFloating(source)) {
      auto intrinsic = isSignedInteger(target) ? llvm::Intrinsic::fptosi_sat
                                               : llvm::Intrinsic::fptoui_sat;
      auto *function = llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), intrinsic, {destination, value->getType()});
      return builder.CreateCall(function, {value});
    }
    if (isFloating(target))
      return isSignedInteger(source) ? builder.CreateSIToFP(value, destination)
                                     : builder.CreateUIToFP(value, destination);
    return builder.CreateIntCast(value, destination, isSignedInteger(source));
  }
  llvm::Value *checkedCast(const ir::Instruction &instruction,
                           llvm::Value *value, Type target) {
    llvm::IRBuilderBase::FastMathFlagGuard guard(builder);
    builder.clearFastMathFlags();
    auto source = instruction.operands[0].type;
    auto width = integerWidth(target);
    bool sign = isSignedInteger(target);
    llvm::Value *valid = nullptr;
    if (isFloating(source)) {
      auto *trunc = llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), llvm::Intrinsic::trunc, {value->getType()});
      auto *integral = builder.CreateCall(trunc, {value});
      const auto &semantics = source == Type::F32 ? llvm::APFloat::IEEEsingle()
                                                  : llvm::APFloat::IEEEdouble();
      auto power = [&](unsigned exponent, bool negative) {
        llvm::APFloat bound(semantics);
        bound.convertFromAPInt(
            llvm::APInt::getOneBitSet(exponent + 1, exponent), false,
            llvm::APFloat::rmNearestTiesToEven);
        if (negative)
          bound.changeSign();
        return llvm::ConstantFP::get(context, bound);
      };
      auto *lower = sign ? power(width - 1, true)
                         : llvm::ConstantFP::getZero(value->getType());
      auto *upper = power(width - (sign ? 1 : 0), false);
      valid = builder.CreateAnd(builder.CreateFCmpOGE(integral, lower),
                                builder.CreateFCmpOLT(integral, upper));
    } else {
      auto extendedWidth = std::max(integerWidth(source), width) + 1;
      auto *extended = builder.CreateIntCast(
          value, builder.getIntNTy(extendedWidth), isSignedInteger(source));
      auto minimum =
          sign ? llvm::APInt::getSignedMinValue(width).sext(extendedWidth)
               : llvm::APInt::getZero(extendedWidth);
      auto maximum = (sign ? llvm::APInt::getSignedMaxValue(width)
                           : llvm::APInt::getAllOnes(width))
                         .zext(extendedWidth);
      valid = builder.CreateAnd(
          builder.CreateICmpSGE(extended,
                                llvm::ConstantInt::get(context, minimum)),
          builder.CreateICmpSLE(extended,
                                llvm::ConstantInt::get(context, maximum)));
    }
    auto *converted = cast(value, source, target);
    llvm::Value *aggregate =
        llvm::Constant::getNullValue(type(instruction.result.type));
    aggregate = builder.CreateInsertValue(
        aggregate, builder.CreateZExt(valid, builder.getInt32Ty()), 0);
    return builder.CreateInsertValue(aggregate, converted, 1);
  }
  llvm::Value *atomic(const ir::Instruction &instruction,
                      llvm::ArrayRef<llvm::Value *> arguments) {
    auto method = std::string_view(instruction.text).substr(7);
    bool fence = method == "fence" || method == "compiler_fence";
    bool raw = method.starts_with("raw_");
    if (raw)
      method.remove_prefix(4);
    Type wrapper = Type::Unknown, payload = Type::Unknown;
    if (!fence) {
      if (raw)
        payload = program.types->pointer(instruction.operands[0].type).payload;
      else {
        wrapper =
            program.types->isView(instruction.operands[0].type)
                ? program.types->view(instruction.operands[0].type).payload
                : instruction.operands[0].type;
        payload = program.types->product(wrapper).components[0];
      }
    }
    if (method == "into_inner")
      return lowering.extract(arguments[0], wrapper, 0);
    if (method == "as_ptr")
      return arguments[0];
    bool compare =
        method == "compare_exchange" || method == "compare_exchange_weak";
    bool unary = method == "load" || method == "fetch_not";
    auto orderIndex = fence ? 0u : unary ? 1u : compare ? 3u : 2u;
    auto *order = lowering.extract(arguments[orderIndex],
                                   instruction.operands[orderIndex].type, 0);
    if (compare) {
      auto *failure =
          lowering.extract(arguments[4], instruction.operands[4].type, 0);
      order = builder.CreateAdd(builder.CreateMul(order, builder.getInt32(5)),
                                failure);
    }
    auto ordering = [](unsigned value) {
      switch (value) {
      case 0:
        return llvm::AtomicOrdering::Monotonic;
      case 1:
        return llvm::AtomicOrdering::Release;
      case 2:
        return llvm::AtomicOrdering::Acquire;
      case 3:
        return llvm::AtomicOrdering::AcquireRelease;
      default:
        return llvm::AtomicOrdering::SequentiallyConsistent;
      }
    };
    auto readOrdering = [](llvm::AtomicOrdering order) {
      return order == llvm::AtomicOrdering::Release
                 ? llvm::AtomicOrdering::Monotonic
             : order == llvm::AtomicOrdering::AcquireRelease
                 ? llvm::AtomicOrdering::Acquire
                 : order;
    };
    auto emit = [&](unsigned success, unsigned failure) -> llvm::Value * {
      auto memoryOrder = ordering(success);
      if (fence) {
        builder.CreateFence(memoryOrder, method == "compiler_fence"
                                             ? llvm::SyncScope::SingleThread
                                             : llvm::SyncScope::System);
        return unit();
      }
      auto logical = [&](llvm::Value *value) -> llvm::Value * {
        return payload == Type::Bool
                   ? builder.CreateTrunc(value, builder.getInt1Ty())
                   : value;
      };
      auto physical = [&](llvm::Value *value) -> llvm::Value * {
        return payload == Type::Bool
                   ? builder.CreateZExt(value, builder.getInt8Ty())
                   : value;
      };
      auto *pointer = arguments[0];
      auto alignment = llvm::Align(lowering.alignment(payload));
      if (method == "load") {
        auto *load = builder.CreateAlignedLoad(lowering.storageType(payload),
                                               pointer, alignment);
        load->setAtomic(memoryOrder);
        return logical(load);
      }
      if (method == "store") {
        auto *store = builder.CreateAlignedStore(physical(arguments[1]),
                                                 pointer, alignment);
        store->setAtomic(memoryOrder);
        return unit();
      }
      if (compare) {
        auto failed = ordering(failure);
        if (failed == llvm::AtomicOrdering::SequentiallyConsistent)
          memoryOrder = llvm::AtomicOrdering::SequentiallyConsistent;
        else if (failed == llvm::AtomicOrdering::Acquire) {
          if (memoryOrder == llvm::AtomicOrdering::Monotonic)
            memoryOrder = llvm::AtomicOrdering::Acquire;
          if (memoryOrder == llvm::AtomicOrdering::Release)
            memoryOrder = llvm::AtomicOrdering::AcquireRelease;
        }
        auto *exchange = builder.CreateAtomicCmpXchg(
            pointer, physical(arguments[1]), physical(arguments[2]),
            llvm::MaybeAlign(alignment), memoryOrder, failed);
        exchange->setWeak(method == "compare_exchange_weak");
        auto *old = logical(builder.CreateExtractValue(exchange, 0));
        auto *matched = builder.CreateExtractValue(exchange, 1);
        return lowering.construct(
            instruction.result.type,
            {builder.CreateSelect(matched, builder.getInt32(0),
                                  builder.getInt32(1)),
             old, old});
      }
      bool pointerArithmetic =
          method.starts_with("fetch_ptr_") || method.starts_with("fetch_byte_");
      bool pointerMask = program.types->isPointer(payload) &&
                         (method == "fetch_and" || method == "fetch_or" ||
                          method == "fetch_xor");
      if (pointerArithmetic || pointerMask ||
          (payload == Type::Bool && method == "fetch_nand")) {
        auto *function = builder.GetInsertBlock()->getParent();
        auto *entry = builder.GetInsertBlock();
        auto *load = builder.CreateAlignedLoad(lowering.storageType(payload),
                                               pointer, alignment);
        load->setAtomic(readOrdering(memoryOrder));
        auto *retry =
            llvm::BasicBlock::Create(context, "atomic.retry", function);
        auto *done = llvm::BasicBlock::Create(context, "atomic.done", function);
        builder.CreateBr(retry);
        builder.SetInsertPoint(retry);
        auto *old = builder.CreatePHI(load->getType(), 2);
        old->addIncoming(load, entry);
        llvm::Value *desired;
        if (pointerArithmetic) {
          auto *count = arguments[1];
          if (method.ends_with("sub"))
            count = builder.CreateNeg(count);
          auto *element = method.starts_with("fetch_byte")
                              ? builder.getInt8Ty()
                              : lowering.storageType(
                                    program.types->pointer(payload).payload);
          desired = builder.CreateGEP(element, old, count);
        } else if (pointerMask) {
          auto *address = builder.CreatePtrToInt(old, builder.getInt64Ty());
          auto *mask = arguments[1];
          auto *masked =
              method == "fetch_and"  ? builder.CreateAnd(address, mask)
              : method == "fetch_or" ? builder.CreateOr(address, mask)
                                     : builder.CreateXor(address, mask);
          // Rebase the address on the observed pointer, as ptr.with_addr does.
          desired = builder.CreateGEP(builder.getInt8Ty(), old,
                                      builder.CreateSub(masked, address));
        } else
          desired =
              builder.CreateXor(builder.CreateAnd(old, physical(arguments[1])),
                                builder.getInt8(1));
        auto *exchange = builder.CreateAtomicCmpXchg(
            pointer, old, desired, llvm::MaybeAlign(alignment), memoryOrder,
            readOrdering(memoryOrder));
        auto *observed = builder.CreateExtractValue(exchange, 0);
        auto *matched = builder.CreateExtractValue(exchange, 1);
        old->addIncoming(observed, builder.GetInsertBlock());
        builder.CreateCondBr(matched, done, retry);
        builder.SetInsertPoint(done);
        return logical(observed);
      }
      auto operation = llvm::AtomicRMWInst::Xchg;
      if (method == "fetch_add")
        operation = llvm::AtomicRMWInst::Add;
      else if (method == "fetch_sub")
        operation = llvm::AtomicRMWInst::Sub;
      else if (method == "fetch_and")
        operation = llvm::AtomicRMWInst::And;
      else if (method == "fetch_or")
        operation = llvm::AtomicRMWInst::Or;
      else if (method == "fetch_xor" || method == "fetch_not")
        operation = llvm::AtomicRMWInst::Xor;
      else if (method == "fetch_nand")
        operation = llvm::AtomicRMWInst::Nand;
      else if (method == "fetch_min")
        operation = isSignedInteger(payload) ? llvm::AtomicRMWInst::Min
                                             : llvm::AtomicRMWInst::UMin;
      else if (method == "fetch_max")
        operation = isSignedInteger(payload) ? llvm::AtomicRMWInst::Max
                                             : llvm::AtomicRMWInst::UMax;
      return logical(builder.CreateAtomicRMW(
          operation, pointer,
          method == "fetch_not" ? builder.getInt8(1) : physical(arguments[1]),
          llvm::MaybeAlign(alignment), memoryOrder));
    };
    auto *function = builder.GetInsertBlock()->getParent();
    auto *done =
        llvm::BasicBlock::Create(context, "atomic.dispatch.done", function);
    auto *invalid =
        llvm::BasicBlock::Create(context, "atomic.invalid.order", function);
    auto *dispatch = builder.CreateSwitch(order, invalid, compare ? 15 : 5);
    std::vector<std::pair<llvm::Value *, llvm::BasicBlock *>> outputs;
    for (unsigned success = 0; success < 5; ++success) {
      if ((method == "load" && (success == 1 || success == 3)) ||
          (method == "store" && (success == 2 || success == 3)) ||
          (fence && success == 0))
        continue;
      for (unsigned failure : {0u, 2u, 4u}) {
        if (!compare && failure)
          continue;
        auto *block =
            llvm::BasicBlock::Create(context, "atomic.order", function);
        dispatch->addCase(
            builder.getInt32(compare ? success * 5 + failure : success), block);
        builder.SetInsertPoint(block);
        auto *value = emit(success, failure);
        outputs.emplace_back(value, builder.GetInsertBlock());
        builder.CreateBr(done);
      }
    }
    builder.SetInsertPoint(invalid);
    emitPanic();
    builder.CreateUnreachable();
    builder.SetInsertPoint(done);
    if (instruction.result.type == Type::Unit)
      return unit();
    auto *result =
        builder.CreatePHI(type(instruction.result.type), outputs.size());
    for (auto [value, block] : outputs)
      result->addIncoming(value, block);
    return result;
  }
  llvm::Value *cell(const ir::Instruction &instruction,
                    const std::vector<llvm::Value *> &arguments) {
    auto wrapper = instruction.typeArguments[0];
    auto kind = program.types->product(wrapper).kind;
    auto method = std::string_view(instruction.text).substr(5);
    if (method == "into_inner")
      return lowering.extract(arguments[0], wrapper, cellPayloadField(kind));
    bool guard = kind == AggregateKind::Ref || kind == AggregateKind::RefMut;
    auto owner =
        guard
            ? program.types->view(program.types->product(wrapper).components[0])
                  .payload
            : wrapper;
    auto payload = program.types->product(owner).components[0];
    auto *address = arguments[0];
    if (guard)
      address =
          lowering.load(program.types->product(wrapper).components[0], address,
                        llvm::Align(lowering.alignment(wrapper)));
    auto *storage = lowering.projectField(
        address, owner, cellPayloadField(program.types->product(owner).kind));
    if (method == "as_ptr" || method == "get_ref" || method == "get_mut")
      return storage;
    if (method == "get")
      return lowering.load(payload, storage,
                           llvm::Align(lowering.alignment(payload)));
    auto *function = builder.GetInsertBlock()->getParent();
    auto require = [&](llvm::Value *condition) {
      auto *valid = llvm::BasicBlock::Create(context, "cell.valid", function);
      auto *invalid =
          llvm::BasicBlock::Create(context, "cell.conflict", function);
      builder.CreateCondBr(condition, valid, invalid);
      builder.SetInsertPoint(invalid);
      emitPanic();
      builder.CreateUnreachable();
      builder.SetInsertPoint(valid);
    };
    bool dynamic = program.types->product(owner).kind == AggregateKind::RefCell;
    auto *counter =
        dynamic ? lowering.projectField(address, owner, 0) : nullptr;
    if (method == "replace" || method == "swap") {
      if (dynamic)
        require(builder.CreateICmpEQ(
            builder.CreateLoad(builder.getInt64Ty(), counter),
            builder.getInt64(0)));
      auto *old = lowering.load(payload, storage,
                                llvm::Align(lowering.alignment(payload)));
      if (method == "replace") {
        lowering.store(payload, arguments[1], storage,
                       llvm::Align(lowering.alignment(payload)));
        return old;
      }
      if (dynamic) {
        auto *otherCounter = lowering.projectField(arguments[1], owner, 0);
        require(builder.CreateAnd(
            builder.CreateICmpNE(address, arguments[1]),
            builder.CreateICmpEQ(
                builder.CreateLoad(builder.getInt64Ty(), otherCounter),
                builder.getInt64(0))));
      }
      auto *other = lowering.projectField(
          arguments[1], owner,
          cellPayloadField(program.types->product(owner).kind));
      auto *value = lowering.load(payload, other,
                                  llvm::Align(lowering.alignment(payload)));
      lowering.store(payload, value, storage,
                     llvm::Align(lowering.alignment(payload)));
      lowering.store(payload, old, other,
                     llvm::Align(lowering.alignment(payload)));
      return unit();
    }
    bool exclusive = method.ends_with("_mut");
    bool fallible = method.starts_with("try_");
    auto *count = builder.CreateLoad(builder.getInt64Ty(), counter);
    auto *available =
        exclusive ? builder.CreateICmpEQ(count, builder.getInt64(0))
                  : builder.CreateAnd(
                        builder.CreateICmpSGE(count, builder.getInt64(0)),
                        builder.CreateICmpNE(
                            count, builder.getInt64(0x7fffffffffffffffULL)));
    llvm::BasicBlock *failed = nullptr, *done = nullptr;
    if (fallible) {
      auto *valid = llvm::BasicBlock::Create(context, "cell.borrow", function);
      failed =
          llvm::BasicBlock::Create(context, "cell.borrow.failed", function);
      done = llvm::BasicBlock::Create(context, "cell.borrow.done", function);
      builder.CreateCondBr(available, valid, failed);
      builder.SetInsertPoint(valid);
    } else
      require(available);
    builder.CreateStore(exclusive
                            ? builder.getInt64(-1)
                            : builder.CreateAdd(count, builder.getInt64(1)),
                        counter);
    auto result = instruction.result.type;
    auto guardType =
        fallible ? program.types->product(result).components[0] : result;
    auto *borrow = lowering.construct(guardType, {address});
    if (!fallible)
      return borrow;
    auto *success = lowering.variant(result, 0, {borrow});
    auto *successBlock = builder.GetInsertBlock();
    builder.CreateBr(done);
    builder.SetInsertPoint(failed);
    auto error = program.types->product(result).components[1];
    auto *failure =
        lowering.variant(result, 1, {lowering.construct(error, {})});
    builder.CreateBr(done);
    builder.SetInsertPoint(done);
    auto *value = builder.CreatePHI(type(result), 2);
    value->addIncoming(success, successBlock);
    value->addIncoming(failure, failed);
    return value;
  }
  llvm::Value *machine(const ir::Instruction &instruction,
                       const std::vector<llvm::Value *> &arguments) {
    auto operation = std::string_view(instruction.text);
    if (operation.starts_with("atomic."))
      return atomic(instruction, arguments);
    if (operation.starts_with("cell."))
      return cell(instruction, arguments);
    auto argument = instruction.typeArguments.empty()
                        ? Type::Unknown
                        : instruction.typeArguments[0];
    auto invoke = [&](llvm::Intrinsic::ID intrinsic,
                      llvm::ArrayRef<llvm::Value *> values) {
      auto *function = llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), intrinsic, {values[0]->getType()});
      return builder.CreateCall(function, values);
    };
    if (operation == "storage.uninit")
      return lowering.indirect(instruction.result.type)
                 ? lowering.zero(instruction.result.type)
                 : llvm::UndefValue::get(type(instruction.result.type));
    if (operation == "storage.zeroed")
      return lowering.zero(instruction.result.type);
    if (operation == "storage.assume_init" ||
        operation == "storage.into_inner" || operation == "pin.into_inner" ||
        operation == "pin.into_inner_unchecked")
      return lowering.extract(arguments[0], argument, 0);
    if (operation == "storage.as_ptr" || operation == "storage.as_mut_ptr" ||
        operation == "storage.get")
      return arguments[0];
    if (operation == "storage.take" || operation == "storage.assume_init_read")
      return lowering.load(
          instruction.result.type, arguments[0],
          llvm::Align(lowering.alignment(instruction.result.type)));
    if (operation == "size_of")
      return builder.getInt64(lowering.layout(argument).size);
    if (operation == "align_of")
      return builder.getInt64(lowering.alignment(argument));
    if (operation == "needs_drop")
      return builder.getInt1(program.types->needsDrop(argument));
    if (operation == "type_id") {
      // Exact identity: one link-once byte per structural identity (not the
      // display name, which omits regions), named by that identity. Equal
      // types in every package and partition resolve to one definition;
      // distinct identities are distinct symbols and are never merged (no
      // unnamed_addr), so identities cannot collide.
      const auto symbol =
          "mettle.type_id." + typeIdentity(*program.types, argument);
      auto *global = module->getNamedGlobal(symbol);
      if (!global) {
        global = new llvm::GlobalVariable(*module, builder.getInt8Ty(), true,
                                          llvm::GlobalValue::LinkOnceODRLinkage,
                                          builder.getInt8(0), symbol);
        global->setVisibility(llvm::GlobalValue::HiddenVisibility);
        if (!module->getTargetTriple().isOSBinFormatMachO())
          global->setComdat(module->getOrInsertComdat(symbol));
      }
      return builder.CreatePtrToInt(global, builder.getInt64Ty());
    }
    if (operation == "mem.forget")
      return unit();
    if (operation == "hint.black_box") {
      // The value round-trips through memory that an empty assembly block may
      // read and write, so the optimizer can neither fold nor drop it.
      auto alignment = llvm::Align(lowering.alignment(argument));
      auto *storage = lowering.temporary(argument);
      lowering.store(argument, arguments[0], storage, alignment);
      auto *barrier = llvm::InlineAsm::get(
          llvm::FunctionType::get(builder.getVoidTy(), {builder.getPtrTy()},
                                  false),
          "", "r,~{memory}", true);
      builder.CreateCall(barrier, {storage})
          ->addFnAttr(llvm::Attribute::NoUnwind);
      return lowering.load(argument, storage, alignment);
    }
    if (operation == "intrinsics.abort") {
      builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), llvm::Intrinsic::trap));
      return unit();
    }
    if (operation == "intrinsics.panic_message") {
      // The single runtime hook: hosted programs report the message and
      // unwind; freestanding programs have no sink and trap.
      if (lowering.freestanding) {
        builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
            module.get(), llvm::Intrinsic::trap));
        return unit();
      }
      auto function =
          lowering.runtime("mettle_rt_panic_message", builder.getVoidTy(),
                           {builder.getPtrTy(), builder.getInt64Ty()});
      llvm::cast<llvm::Function>(function.getCallee())
          ->addFnAttr(llvm::Attribute::NoReturn);
      builder.CreateCall(function,
                         {builder.CreateExtractValue(arguments[0], 0),
                          builder.CreateExtractValue(arguments[0], 1)});
      return unit();
    }
    if (operation == "mem.replace" || operation == "mem.swap") {
      auto alignment = llvm::Align(lowering.alignment(argument));
      auto *data = arguments[0];
      if (operation == "mem.replace") {
        auto *old = lowering.load(argument, data, alignment);
        lowering.store(argument, arguments[1], data, alignment);
        return old;
      }
      auto *temporary = lowering.temporary(argument);
      auto size = lowering.layout(argument).size;
      builder.CreateMemCpy(temporary, alignment, data, alignment, size);
      builder.CreateMemMove(data, alignment, arguments[1], alignment, size);
      builder.CreateMemCpy(arguments[1], alignment, temporary, alignment, size);
      return unit();
    }
    if (operation == "mem.size_of_val" || operation == "mem.align_of_val") {
      if (program.types->isErased(argument)) {
        auto *table = builder.CreateExtractValue(arguments[0], 2);
        auto slotIndex = operation == "mem.size_of_val" ? std::uint32_t{1}
                                                        : std::uint32_t{2};
        auto *slot = builder.CreateGEP(builder.getPtrTy(), table,
                                       builder.getInt32(slotIndex));
        auto *value = builder.CreatePtrToInt(
            builder.CreateLoad(builder.getPtrTy(), slot), builder.getInt64Ty());
        if (operation == "mem.align_of_val")
          return value;
        auto *kind = builder.CreateLoad(
            builder.getPtrTy(),
            builder.CreateGEP(builder.getPtrTy(), table, builder.getInt32(0)));
        auto *count = builder.CreateExtractValue(arguments[0], 1);
        auto *prefixSlot =
            builder.CreateGEP(builder.getPtrTy(), table, builder.getInt32(4));
        auto *prefix = builder.CreatePtrToInt(
            builder.CreateLoad(builder.getPtrTy(), prefixSlot),
            builder.getInt64Ty());
        auto *alignSlot =
            builder.CreateGEP(builder.getPtrTy(), table, builder.getInt32(2));
        auto *alignment = builder.CreatePtrToInt(
            builder.CreateLoad(builder.getPtrTy(), alignSlot),
            builder.getInt64Ty());
        auto *dynamicSize =
            builder.CreateAdd(prefix, builder.CreateMul(count, value));
        auto *mask = builder.CreateSub(alignment, builder.getInt64(1));
        dynamicSize = builder.CreateAnd(builder.CreateAdd(dynamicSize, mask),
                                        builder.CreateNot(mask));
        return builder.CreateSelect(
            builder.CreateICmpNE(
                kind, llvm::ConstantPointerNull::get(builder.getPtrTy())),
            dynamicSize, value);
      }
      auto element = program.types->isSlice(argument)
                         ? program.types->slice(argument).element
                         : argument;
      if (operation == "mem.align_of_val")
        return builder.getInt64(lowering.alignment(element));
      auto *size = builder.getInt64(lowering.layout(element).size);
      if (program.types->isSlice(argument))
        return builder.CreateMul(builder.CreateExtractValue(arguments[0], 1),
                                 size);
      if (program.types->pointerMetadata(argument) ==
          PointerMetadata::ElementCount) {
        Type tail = argument;
        std::uint64_t offset = 0;
        while (program.types->isProduct(tail) &&
               !program.types->product(tail).fields.empty()) {
          const auto &record = program.types->product(tail);
          offset += lowering.layout(tail).fields.back();
          tail = record.fields.back().type;
        }
        if (!program.types->isSlice(tail))
          llvm::report_fatal_error(
              "element-count metadata has no unsized slice tail");
        auto *count = builder.CreateExtractValue(arguments[0], 1);
        auto *dynamic = builder.CreateAdd(
            builder.getInt64(offset),
            builder.CreateMul(
                count,
                builder.getInt64(
                    lowering.layout(program.types->slice(tail).element).size)));
        auto alignment = builder.getInt64(lowering.alignment(argument));
        auto mask = builder.CreateSub(alignment, builder.getInt64(1));
        return builder.CreateAnd(builder.CreateAdd(dynamic, mask),
                                 builder.CreateNot(mask));
      }
      return size;
    }
    if (operation == "mem.zeroed")
      return lowering.zero(instruction.result.type);
    if (operation == "mem.transmute") {
      auto source = instruction.operands[0].type;
      auto *storage = lowering.temporary(source);
      lowering.store(source, arguments[0], storage,
                     llvm::Align(lowering.alignment(source)));
      return lowering.load(instruction.result.type, storage, llvm::Align(1));
    }
    if (operation.starts_with("numeric.")) {
      auto method = operation.substr(8);
      auto receiverType = instruction.operands[0].type;
      bool mutatingAscii =
          method == "make_ascii_lowercase" || method == "make_ascii_uppercase";
      auto self = program.types->isView(receiverType)
                      ? program.types->view(receiverType).payload
                      : receiverType;
      auto *a = arguments[0];
      if (mutatingAscii)
        a = builder.CreateLoad(type(self), a);
      auto *b = arguments.size() > 1 ? arguments[1] : nullptr;
      if (method == "checked_cast")
        return checkedCast(instruction, a, argument);
      if (method == "to_int_unchecked")
        return isSignedInteger(argument)
                   ? builder.CreateFPToSI(a, type(argument))
                   : builder.CreateFPToUI(a, type(argument));
      if (method == "to_bits" || method == "from_bits")
        return builder.CreateBitCast(a, type(instruction.result.type));
      if (method == "cast_signed" || method == "cast_unsigned")
        return a;
      if (method == "to_be" || method == "to_le" || method == "from_be" ||
          method == "from_le") {
        bool bigEndian = method == "to_be" || method == "from_be";
        bool swap = module->getDataLayout().isLittleEndian() == bigEndian;
        return swap && integerWidth(self) > 8
                   ? invoke(llvm::Intrinsic::bswap, {a})
                   : a;
      }
      if (method == "to_be_bytes" || method == "to_le_bytes" ||
          method == "to_ne_bytes" || method == "from_be_bytes" ||
          method == "from_le_bytes" || method == "from_ne_bytes") {
        bool fromBytes = method.starts_with("from_");
        bool bigEndian = method.ends_with("be_bytes");
        bool littleEndian = method.ends_with("le_bytes");
        unsigned width = isInteger(fromBytes ? argument : self)
                             ? integerWidth(fromBytes ? argument : self)
                         : (fromBytes ? argument : self) == Type::F32 ? 32
                                                                      : 64;
        auto rawType = builder.getIntNTy(width);
        auto *storage =
            lowering.temporary(fromBytes ? instruction.operands[0].type : self);
        if (fromBytes) {
          // The temporary has the byte array's alignment, which is below the
          // integer's ABI alignment for 16-byte integers.
          llvm::Align bytesAlign(
              lowering.alignment(instruction.operands[0].type));
          builder.CreateAlignedStore(arguments[0], storage, bytesAlign);
          llvm::Value *bits =
              builder.CreateAlignedLoad(rawType, storage, bytesAlign);
          bool swap = littleEndian ? !module->getDataLayout().isLittleEndian()
                      : bigEndian  ? module->getDataLayout().isLittleEndian()
                                   : false;
          if (swap && width > 8)
            bits = invoke(llvm::Intrinsic::bswap, {bits});
          return isFloating(argument)
                     ? builder.CreateBitCast(bits, type(argument))
                     : bits;
        }
        auto *bits = isFloating(self) ? builder.CreateBitCast(a, rawType) : a;
        bool swap = littleEndian ? !module->getDataLayout().isLittleEndian()
                    : bigEndian  ? module->getDataLayout().isLittleEndian()
                                 : false;
        if (swap && width > 8)
          bits = invoke(llvm::Intrinsic::bswap, {bits});
        builder.CreateStore(bits, storage);
        return builder.CreateLoad(type(instruction.result.type), storage);
      }
      if (isFloating(self)) {
        if (method == "sin_cos") {
          auto *sine = invoke(llvm::Intrinsic::sin, {a});
          auto *cosine = invoke(llvm::Intrinsic::cos, {a});
          return lowering.construct(instruction.result.type, {sine, cosine});
        }
        if (method == "mul_add")
          return invoke(llvm::Intrinsic::fma, arguments);
        if (method == "copysign")
          return invoke(llvm::Intrinsic::copysign, arguments);
        if (method == "abs")
          return invoke(llvm::Intrinsic::fabs, arguments);
        if (method == "sqrt")
          return invoke(llvm::Intrinsic::sqrt, arguments);
        if (method == "floor")
          return invoke(llvm::Intrinsic::floor, arguments);
        if (method == "ceil")
          return invoke(llvm::Intrinsic::ceil, arguments);
        if (method == "trunc")
          return invoke(llvm::Intrinsic::trunc, arguments);
        if (method == "round")
          return invoke(llvm::Intrinsic::round, arguments);
        if (method == "round_ties_even")
          return invoke(llvm::Intrinsic::roundeven, arguments);
        auto external = [&](std::string name,
                            llvm::ArrayRef<llvm::Value *> values) {
          if (self == Type::F32)
            name += "f";
          std::vector<llvm::Type *> parameters;
          for (auto *value : values)
            parameters.push_back(value->getType());
          auto *signature =
              llvm::FunctionType::get(type(self), parameters, false);
          auto function = module->getOrInsertFunction(name, signature);
          return builder.CreateCall(function, values);
        };
        if (method == "sin")
          return invoke(llvm::Intrinsic::sin, arguments);
        if (method == "cos")
          return invoke(llvm::Intrinsic::cos, arguments);
        if (method == "exp")
          return invoke(llvm::Intrinsic::exp, arguments);
        if (method == "exp2")
          return invoke(llvm::Intrinsic::exp2, arguments);
        if (method == "ln")
          return invoke(llvm::Intrinsic::log, arguments);
        if (method == "log2")
          return invoke(llvm::Intrinsic::log2, arguments);
        if (method == "log10")
          return invoke(llvm::Intrinsic::log10, arguments);
        if (method == "powf")
          return invoke(llvm::Intrinsic::pow, arguments);
        if (method == "powi")
          return builder.CreateCall(
              llvm::Intrinsic::getOrInsertDeclaration(
                  module.get(), llvm::Intrinsic::powi,
                  {arguments[0]->getType(), arguments[1]->getType()}),
              arguments);
        if (method == "log") {
          auto *numerator = invoke(llvm::Intrinsic::log, {a});
          auto *denominator = invoke(llvm::Intrinsic::log, {b});
          return builder.CreateFDiv(numerator, denominator);
        }
        if (method == "tan")
          return external("tan", arguments);
        if (method == "asin")
          return external("asin", arguments);
        if (method == "acos")
          return external("acos", arguments);
        if (method == "atan")
          return external("atan", arguments);
        if (method == "atan2")
          return external("atan2", arguments);
        if (method == "sinh")
          return external("sinh", arguments);
        if (method == "cosh")
          return external("cosh", arguments);
        if (method == "tanh")
          return external("tanh", arguments);
        if (method == "asinh")
          return external("asinh", arguments);
        if (method == "acosh")
          return external("acosh", arguments);
        if (method == "atanh")
          return external("atanh", arguments);
        if (method == "exp_m1")
          return external("expm1", arguments);
        if (method == "ln_1p")
          return external("log1p", arguments);
        if (method == "cbrt")
          return external("cbrt", arguments);
        if (method == "hypot")
          return external("hypot", arguments);
        // self - self.trunc(): an integral input yields +0.0, also when
        // negative.
        if (method == "fract")
          return builder.CreateFSub(a, invoke(llvm::Intrinsic::trunc, {a}));
        if (method == "recip")
          return builder.CreateFDiv(llvm::ConstantFP::get(type(self), 1.0), a);
        if (method == "signum") {
          auto *nan = builder.CreateFCmpUNO(a, a);
          auto *one = llvm::ConstantFP::get(type(self), 1.0);
          auto *signedOne = invoke(llvm::Intrinsic::copysign, {one, a});
          return builder.CreateSelect(nan, a, signedOne);
        }
        if (method == "to_degrees" || method == "to_radians") {
          constexpr double pi = 3.14159265358979323846264338327950288;
          auto factor = method == "to_degrees" ? 180.0 / pi : pi / 180.0;
          return builder.CreateFMul(a,
                                    llvm::ConstantFP::get(type(self), factor));
        }
        if (method == "div_euclid" || method == "rem_euclid") {
          auto *remainder = builder.CreateFRem(a, b);
          auto *zero = llvm::ConstantFP::get(type(self), 0.0);
          auto *negative = builder.CreateFCmpOLT(remainder, zero);
          if (method == "div_euclid") {
            auto *quotient =
                invoke(llvm::Intrinsic::trunc, {builder.CreateFDiv(a, b)});
            auto *one = llvm::ConstantFP::get(type(self), 1.0);
            auto *adjusted =
                builder.CreateSelect(builder.CreateFCmpOGT(b, zero),
                                     builder.CreateFSub(quotient, one),
                                     builder.CreateFAdd(quotient, one));
            return builder.CreateSelect(negative, adjusted, quotient);
          }
          auto *magnitude = invoke(llvm::Intrinsic::fabs, {b});
          auto *adjusted = builder.CreateFAdd(remainder, magnitude);
          remainder = builder.CreateSelect(negative, adjusted, remainder);
          remainder = builder.CreateSelect(
              builder.CreateFCmpOGE(remainder, magnitude), zero, remainder);
          remainder = builder.CreateSelect(
              builder.CreateFCmpOEQ(remainder, zero), zero, remainder);
          return remainder;
        }
        if (method == "midpoint") {
          auto two = [](llvm::Type *t) {
            return llvm::ConstantFP::get(t, 2.0);
          };
          if (self == Type::F32) {
            // binary32: the exact sum fits binary64, so one final rounding.
            auto *wide = builder.getDoubleTy();
            auto *sum = builder.CreateFAdd(builder.CreateFPExt(a, wide),
                                           builder.CreateFPExt(b, wide));
            return builder.CreateFPTrunc(builder.CreateFDiv(sum, two(wide)),
                                         type(self));
          }
          // binary64: halve before adding only where the sum could overflow,
          // and never halve an operand that would underflow.
          auto *low = llvm::ConstantFP::get(type(self), 2.0 * 0x1p-1022);
          auto *high =
              llvm::ConstantFP::get(type(self), 0x1.fffffffffffffp+1023 / 2.0);
          auto *absA = invoke(llvm::Intrinsic::fabs, {a});
          auto *absB = invoke(llvm::Intrinsic::fabs, {b});
          auto *halfA = builder.CreateFDiv(a, two(type(self)));
          auto *halfB = builder.CreateFDiv(b, two(type(self)));
          auto *small = builder.CreateAnd(builder.CreateFCmpOLE(absA, high),
                                          builder.CreateFCmpOLE(absB, high));
          auto *result = builder.CreateFAdd(halfA, halfB);
          result = builder.CreateSelect(builder.CreateFCmpOLT(absB, low),
                                        builder.CreateFAdd(halfA, b), result);
          result = builder.CreateSelect(builder.CreateFCmpOLT(absA, low),
                                        builder.CreateFAdd(a, halfB), result);
          return builder.CreateSelect(
              small,
              builder.CreateFDiv(builder.CreateFAdd(a, b), two(type(self))),
              result);
        }
        if (method == "min" || method == "max")
          return invoke(method == "min" ? llvm::Intrinsic::minnum
                                        : llvm::Intrinsic::maxnum,
                        arguments);
        if (method == "clamp") {
          auto *invalid = builder.CreateOr(
              builder.CreateFCmpUNO(b, b),
              builder.CreateOr(
                  builder.CreateFCmpUNO(arguments[2], arguments[2]),
                  builder.CreateFCmpOGT(b, arguments[2])));
          panicIf(invalid);
          // Comparison-based like the constant evaluator: NaN and signed
          // zeros inside the range pass through unchanged.
          auto *lower = builder.CreateSelect(builder.CreateFCmpOLT(a, b), b, a);
          return builder.CreateSelect(
              builder.CreateFCmpOGT(lower, arguments[2]), arguments[2], lower);
        }
        if (method == "next_up" || method == "next_down") {
          unsigned bitWidth = self == Type::F32 ? 32 : 64;
          auto *bits = builder.CreateBitCast(a, builder.getIntNTy(bitWidth));
          auto constant = [&](std::uint64_t value) {
            return llvm::ConstantInt::get(bits->getType(), value);
          };
          auto signMask = std::uint64_t{1} << (bitWidth - 1);
          auto exponentMask = self == Type::F32
                                  ? std::uint64_t{0x7f800000}
                                  : std::uint64_t{0x7ff0000000000000};
          auto *negative = builder.CreateICmpNE(
              builder.CreateAnd(bits, constant(signMask)), constant(0));
          auto *zero =
              builder.CreateFCmpOEQ(a, llvm::ConstantFP::get(type(self), 0.0));
          auto *special = builder.CreateICmpEQ(
              builder.CreateAnd(bits, constant(exponentMask)),
              constant(exponentMask));
          auto *nan = builder.CreateFCmpUNO(a, a);
          bool up = method == "next_up";
          auto *unchanged = builder.CreateOr(
              nan, builder.CreateAnd(special, up ? builder.CreateNot(negative)
                                                 : negative));
          auto *increment = up ? negative : builder.CreateNot(negative);
          auto *nextBits = builder.CreateSelect(
              increment, builder.CreateSub(bits, constant(1)),
              builder.CreateAdd(bits, constant(1)));
          auto *zeroBits = constant(up ? 1 : (signMask | 1));
          nextBits = builder.CreateSelect(zero, zeroBits, nextBits);
          nextBits = builder.CreateSelect(unchanged, bits, nextBits);
          return builder.CreateBitCast(nextBits, type(self));
        }
        unsigned width = self == Type::F32 ? 32 : 64;
        unsigned fractionBits = self == Type::F32 ? 23 : 52;
        auto *bits = builder.CreateBitCast(a, builder.getIntNTy(width));
        auto constant = [&](std::uint64_t value) {
          return llvm::ConstantInt::get(bits->getType(), value);
        };
        auto fractionMask = (std::uint64_t{1} << fractionBits) - 1;
        auto exponentMask = self == Type::F32
                                ? std::uint64_t{0x7f800000}
                                : std::uint64_t{0x7ff0000000000000};
        auto *exponent = builder.CreateAnd(bits, constant(exponentMask));
        auto *fraction = builder.CreateAnd(bits, constant(fractionMask));
        auto *special = builder.CreateICmpEQ(exponent, constant(exponentMask));
        auto *zeroExponent = builder.CreateICmpEQ(exponent, constant(0));
        auto *zeroFraction = builder.CreateICmpEQ(fraction, constant(0));
        if (method == "is_nan")
          return builder.CreateAnd(special, builder.CreateNot(zeroFraction));
        if (method == "is_infinite")
          return builder.CreateAnd(special, zeroFraction);
        if (method == "is_finite")
          return builder.CreateNot(special);
        if (method == "is_subnormal")
          return builder.CreateAnd(zeroExponent,
                                   builder.CreateNot(zeroFraction));
        if (method == "is_normal")
          return builder.CreateAnd(builder.CreateNot(zeroExponent),
                                   builder.CreateNot(special));
        auto *negative = builder.CreateICmpNE(
            builder.CreateAnd(bits, constant(std::uint64_t{1} << (width - 1))),
            constant(0));
        return method == "is_sign_negative" ? negative
                                            : builder.CreateNot(negative);
      }
      auto width = integerWidth(self);
      auto integer = [&](std::uint64_t value) {
        return llvm::ConstantInt::get(a->getType(), value);
      };
      if (method == "swap_bytes")
        return width == 8 ? a : invoke(llvm::Intrinsic::bswap, arguments);
      if (method == "reverse_bits")
        return invoke(llvm::Intrinsic::bitreverse, arguments);
      if (method == "count_ones" || method == "count_zeros")
        return builder.CreateZExtOrTrunc(
            invoke(llvm::Intrinsic::ctpop,
                   {method == "count_zeros" ? builder.CreateNot(a) : a}),
            builder.getInt32Ty());
      if (method == "leading_zeros" || method == "leading_ones" ||
          method == "trailing_zeros" || method == "trailing_ones") {
        auto *value = method.ends_with("ones") ? builder.CreateNot(a) : a;
        return builder.CreateZExtOrTrunc(invoke(method.starts_with("leading")
                                                    ? llvm::Intrinsic::ctlz
                                                    : llvm::Intrinsic::cttz,
                                                {value, builder.getFalse()}),
                                         builder.getInt32Ty());
      }
      if (method == "rotate_left" || method == "rotate_right") {
        auto *count = builder.CreateZExtOrTrunc(b, a->getType());
        return invoke(method == "rotate_left" ? llvm::Intrinsic::fshl
                                              : llvm::Intrinsic::fshr,
                      {a, a, count});
      }
      if (self == Type::U8 &&
          (method.starts_with("is_ascii") || method.starts_with("to_ascii") ||
           method.starts_with("make_ascii") ||
           method == "eq_ignore_ascii_case")) {
        auto lower = [&](llvm::Value *value) {
          auto *upper =
              builder.CreateAnd(builder.CreateICmpUGE(value, integer(0x41)),
                                builder.CreateICmpULE(value, integer(0x5a)));
          return builder.CreateSelect(
              upper, builder.CreateAdd(value, integer(0x20)), value);
        };
        auto upper = [&](llvm::Value *value) {
          auto *lowercase =
              builder.CreateAnd(builder.CreateICmpUGE(value, integer(0x61)),
                                builder.CreateICmpULE(value, integer(0x7a)));
          return builder.CreateSelect(
              lowercase, builder.CreateSub(value, integer(0x20)), value);
        };
        if (method == "to_ascii_lowercase")
          return lower(a);
        if (method == "to_ascii_uppercase")
          return upper(a);
        if (method == "make_ascii_lowercase" ||
            method == "make_ascii_uppercase") {
          builder.CreateStore(method == "make_ascii_lowercase" ? lower(a)
                                                               : upper(a),
                              arguments[0]);
          return unit();
        }
        if (method == "eq_ignore_ascii_case")
          return builder.CreateICmpEQ(lower(a), lower(b));
        if (method == "is_ascii")
          return builder.CreateICmpULT(a, integer(0x80));
        auto *alpha = builder.CreateOr(
            builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x41)),
                              builder.CreateICmpULE(a, integer(0x5a))),
            builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x61)),
                              builder.CreateICmpULE(a, integer(0x7a))));
        auto *digit =
            builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x30)),
                              builder.CreateICmpULE(a, integer(0x39)));
        if (method == "is_ascii_alphabetic")
          return alpha;
        if (method == "is_ascii_alphanumeric")
          return builder.CreateOr(alpha, digit);
        if (method == "is_ascii_control")
          return builder.CreateOr(builder.CreateICmpULT(a, integer(0x20)),
                                  builder.CreateICmpEQ(a, integer(0x7f)));
        if (method == "is_ascii_digit")
          return digit;
        if (method == "is_ascii_graphic")
          return builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x21)),
                                   builder.CreateICmpULE(a, integer(0x7e)));
        if (method == "is_ascii_hexdigit")
          return builder.CreateOr(
              digit,
              builder.CreateOr(
                  builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x41)),
                                    builder.CreateICmpULE(a, integer(0x46))),
                  builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x61)),
                                    builder.CreateICmpULE(a, integer(0x66)))));
        if (method == "is_ascii_lowercase")
          return builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x61)),
                                   builder.CreateICmpULE(a, integer(0x7a)));
        if (method == "is_ascii_punctuation")
          return builder.CreateAnd(
              builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x21)),
                                builder.CreateICmpULE(a, integer(0x7e))),
              builder.CreateNot(builder.CreateOr(alpha, digit)));
        if (method == "is_ascii_uppercase")
          return builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x41)),
                                   builder.CreateICmpULE(a, integer(0x5a)));
        // Tab, line feed, form feed, carriage return and space; vertical tab
        // (0x0b) is not ASCII whitespace.
        return builder.CreateOr(
            builder.CreateAnd(
                builder.CreateAnd(builder.CreateICmpUGE(a, integer(0x09)),
                                  builder.CreateICmpULE(a, integer(0x0d))),
                builder.CreateICmpNE(a, integer(0x0b))),
            builder.CreateICmpEQ(a, integer(0x20)));
      }
      bool sign = isSignedInteger(self);
      if (method == "ilog" || method == "checked_ilog" || method == "ilog2" ||
          method == "checked_ilog2" || method == "ilog10" ||
          method == "checked_ilog10") {
        bool optional = method.starts_with("checked_");
        bool baseArgument =
            method.ends_with("ilog") || method.ends_with("checked_ilog");
        bool baseTwo = method.ends_with("ilog2");
        bool baseTen = method.ends_with("ilog10");
        auto *valid = sign ? builder.CreateICmpSGT(a, integer(0))
                           : builder.CreateICmpNE(a, integer(0));
        llvm::Value *base = baseTwo ? integer(2) : baseTen ? integer(10) : b;
        if (baseArgument) {
          auto *validBase = sign ? builder.CreateICmpSGT(base, integer(1))
                                 : builder.CreateICmpUGT(base, integer(1));
          valid = builder.CreateAnd(valid, validBase);
        }
        if (!optional)
          panicIf(builder.CreateNot(valid));
        llvm::Value *result = nullptr;
        if (baseTwo) {
          auto *safe = builder.CreateSelect(valid, a, integer(1));
          auto *leading = builder.CreateZExtOrTrunc(
              invoke(llvm::Intrinsic::ctlz, {safe, builder.getFalse()}),
              builder.getInt32Ty());
          result = builder.CreateSub(builder.getInt32(width - 1), leading);
        } else {
          auto *safeValue = builder.CreateSelect(valid, a, integer(1));
          auto *safeBase = baseArgument
                               ? builder.CreateSelect(valid, base, integer(2))
                               : integer(10);
          auto *function = builder.GetInsertBlock()->getParent();
          auto *preheader = builder.GetInsertBlock();
          auto *loop = llvm::BasicBlock::Create(context, "ilog.loop", function);
          auto *body = llvm::BasicBlock::Create(context, "ilog.body", function);
          auto *done = llvm::BasicBlock::Create(context, "ilog.done", function);
          builder.CreateBr(loop);
          builder.SetInsertPoint(loop);
          auto *value = builder.CreatePHI(a->getType(), 2);
          auto *count = builder.CreatePHI(builder.getInt32Ty(), 2);
          value->addIncoming(safeValue, preheader);
          count->addIncoming(builder.getInt32(0), preheader);
          auto *atLeastBase = sign ? builder.CreateICmpSGE(value, safeBase)
                                   : builder.CreateICmpUGE(value, safeBase);
          builder.CreateCondBr(atLeastBase, body, done);
          builder.SetInsertPoint(body);
          auto *nextValue = sign ? builder.CreateSDiv(value, safeBase)
                                 : builder.CreateUDiv(value, safeBase);
          auto *nextCount = builder.CreateAdd(count, builder.getInt32(1));
          auto *backedge = builder.GetInsertBlock();
          builder.CreateBr(loop);
          value->addIncoming(nextValue, backedge);
          count->addIncoming(nextCount, backedge);
          builder.SetInsertPoint(done);
          result = count;
        }
        if (!optional)
          return result;
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        aggregate = builder.CreateInsertValue(
            aggregate, builder.CreateZExt(valid, builder.getInt32Ty()), 0);
        return builder.CreateInsertValue(aggregate, result, 1);
      }
      if (method == "isqrt" || method == "checked_isqrt") {
        bool optional = method == "checked_isqrt";
        auto *valid =
            sign ? builder.CreateICmpSGE(a, integer(0)) : builder.getTrue();
        if (!optional)
          panicIf(builder.CreateNot(valid));
        auto *nonzero = builder.CreateICmpNE(a, integer(0));
        auto *safeValue = builder.CreateSelect(
            builder.CreateAnd(valid, nonzero), a, integer(1));
        auto *one = integer(1);
        auto *function = builder.GetInsertBlock()->getParent();
        auto *preheader = builder.GetInsertBlock();
        auto *loop = llvm::BasicBlock::Create(context, "isqrt.loop", function);
        auto *body = llvm::BasicBlock::Create(context, "isqrt.body", function);
        auto *done = llvm::BasicBlock::Create(context, "isqrt.done", function);
        builder.CreateBr(loop);
        builder.SetInsertPoint(loop);
        auto *estimate = builder.CreatePHI(a->getType(), 2);
        estimate->addIncoming(safeValue, preheader);
        auto *quotient = sign ? builder.CreateSDiv(safeValue, estimate)
                              : builder.CreateUDiv(safeValue, estimate);
        auto *halves = builder.CreateAdd(builder.CreateLShr(estimate, one),
                                         builder.CreateLShr(quotient, one));
        auto *oddBits = builder.CreateAdd(builder.CreateAnd(estimate, one),
                                          builder.CreateAnd(quotient, one));
        auto *next =
            builder.CreateAdd(halves, builder.CreateLShr(oddBits, one));
        builder.CreateCondBr(sign ? builder.CreateICmpSLT(next, estimate)
                                  : builder.CreateICmpULT(next, estimate),
                             body, done);
        builder.SetInsertPoint(body);
        auto *backedge = builder.GetInsertBlock();
        builder.CreateBr(loop);
        estimate->addIncoming(next, backedge);
        builder.SetInsertPoint(done);
        auto *result = builder.CreateSelect(nonzero, estimate, integer(0));
        if (!optional)
          return result;
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        aggregate = builder.CreateInsertValue(
            aggregate, builder.CreateZExt(valid, builder.getInt32Ty()), 0);
        return builder.CreateInsertValue(aggregate, result, 1);
      }
      auto present = [&](llvm::Value *valid, llvm::Value *result) {
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        aggregate = builder.CreateInsertValue(
            aggregate, builder.CreateZExt(valid, builder.getInt32Ty()), 0);
        return builder.CreateInsertValue(aggregate, result, 1);
      };
      if (method == "bit_width" || method == "highest_one" ||
          method == "lowest_one" || method == "isolate_highest_one") {
        auto *nonzero = builder.CreateICmpNE(a, integer(0));
        bool lowest = method == "lowest_one";
        // Zero yields the defined count `width` and is masked below.
        auto *count =
            invoke(lowest ? llvm::Intrinsic::cttz : llvm::Intrinsic::ctlz,
                   {a, builder.getFalse()});
        if (method == "isolate_highest_one") {
          auto *top = llvm::ConstantInt::get(
              context, llvm::APInt::getSignedMinValue(width));
          auto *shift = builder.CreateSelect(nonzero, count, integer(0));
          return builder.CreateSelect(nonzero, builder.CreateLShr(top, shift),
                                      integer(0));
        }
        auto *count32 = builder.CreateZExtOrTrunc(count, builder.getInt32Ty());
        if (method == "bit_width")
          return builder.CreateSub(builder.getInt32(width), count32);
        return present(
            nonzero,
            lowest ? count32
                   : builder.CreateSub(builder.getInt32(width - 1), count32));
      }
      if (method == "isolate_lowest_one")
        return builder.CreateAnd(a, builder.CreateNeg(a));
      if (method == "carrying_add" || method == "borrowing_sub") {
        auto intrinsic = method == "carrying_add"
                             ? llvm::Intrinsic::uadd_with_overflow
                             : llvm::Intrinsic::usub_with_overflow;
        auto *first = invoke(intrinsic, {a, b});
        auto *second =
            invoke(intrinsic, {builder.CreateExtractValue(first, 0),
                               builder.CreateZExt(arguments[2], a->getType())});
        return lowering.construct(
            instruction.result.type,
            {builder.CreateExtractValue(second, 0),
             builder.CreateOr(builder.CreateExtractValue(first, 1),
                              builder.CreateExtractValue(second, 1))});
      }
      if (method == "carrying_mul" || method == "carrying_mul_add") {
        // self * rhs + carry (+ add) never exceeds the double-width range.
        auto *wide = builder.getIntNTy(width * 2);
        auto *full = builder.CreateMul(builder.CreateZExt(a, wide),
                                       builder.CreateZExt(b, wide));
        for (std::size_t i = 2; i < arguments.size(); ++i)
          full =
              builder.CreateAdd(full, builder.CreateZExt(arguments[i], wide));
        return lowering.construct(
            instruction.result.type,
            {builder.CreateTrunc(full, a->getType()),
             builder.CreateTrunc(builder.CreateLShr(full, width),
                                 a->getType())});
      }
      if (method == "checked_signed_diff") {
        // The exact difference fits in width + 1 signed bits.
        auto *wide = builder.getIntNTy(width + 1);
        auto *difference = builder.CreateSub(builder.CreateZExt(a, wide),
                                             builder.CreateZExt(b, wide));
        auto *low = llvm::ConstantInt::get(
            wide, llvm::APInt::getSignedMinValue(width).sext(width + 1));
        auto *high = llvm::ConstantInt::get(
            wide, llvm::APInt::getSignedMaxValue(width).sext(width + 1));
        auto *valid =
            builder.CreateAnd(builder.CreateICmpSGE(difference, low),
                              builder.CreateICmpSLE(difference, high));
        return present(valid, builder.CreateTrunc(difference, a->getType()));
      }
      bool mixedStrict = method.starts_with("strict_");
      bool mixedOptional = method.starts_with("checked_");
      bool mixedOverflowing = method.starts_with("overflowing_");
      bool mixedSaturating = method.starts_with("saturating_");
      bool mixedWrapping = method.starts_with("wrapping_");
      auto mixedMethod = method;
      mixedMethod.remove_prefix(mixedStrict        ? 7
                                : mixedOptional    ? 8
                                : mixedOverflowing ? 12
                                : mixedSaturating  ? 11
                                : mixedWrapping    ? 9
                                                   : 0);
      bool mixedSigned = mixedMethod.ends_with("_signed");
      bool mixedUnsigned = mixedMethod.ends_with("_unsigned");
      if (mixedSigned || mixedUnsigned) {
        bool subtract = mixedMethod.starts_with("sub_");
        auto extendedType = llvm::IntegerType::get(context, width + 2);
        auto *left = sign ? builder.CreateSExt(a, extendedType)
                          : builder.CreateZExt(a, extendedType);
        auto *right = mixedSigned ? builder.CreateSExt(b, extendedType)
                                  : builder.CreateZExt(b, extendedType);
        auto *wide = subtract ? builder.CreateSub(left, right)
                              : builder.CreateAdd(left, right);
        llvm::Value *overflow = nullptr;
        llvm::Value *bounded = wide;
        if (sign) {
          auto *minimum = llvm::ConstantInt::get(
              context, llvm::APInt::getSignedMinValue(width).sext(width + 2));
          auto *maximum = llvm::ConstantInt::get(
              context, llvm::APInt::getSignedMaxValue(width).sext(width + 2));
          auto *below = builder.CreateICmpSLT(wide, minimum);
          auto *above = builder.CreateICmpSGT(wide, maximum);
          overflow = builder.CreateOr(below, above);
          if (mixedSaturating)
            bounded = builder.CreateSelect(
                below, minimum, builder.CreateSelect(above, maximum, wide));
        } else {
          auto *minimum = llvm::ConstantInt::get(
              context, llvm::APInt::getZero(width).zext(width + 2));
          auto *maximum = llvm::ConstantInt::get(
              context, llvm::APInt::getAllOnes(width).zext(width + 2));
          auto *below = builder.CreateICmpSLT(wide, minimum);
          auto *above = builder.CreateICmpSGT(wide, maximum);
          overflow = builder.CreateOr(below, above);
          if (mixedSaturating)
            bounded = builder.CreateSelect(
                below, minimum, builder.CreateSelect(above, maximum, wide));
        }
        auto *value = builder.CreateTrunc(bounded, a->getType());
        if (mixedStrict || (!mixedOptional && !mixedOverflowing &&
                            !mixedSaturating && !mixedWrapping && checked))
          panicIf(overflow);
        if (mixedOptional || mixedOverflowing) {
          llvm::Value *aggregate =
              llvm::Constant::getNullValue(type(instruction.result.type));
          if (mixedOptional) {
            aggregate = builder.CreateInsertValue(
                aggregate,
                builder.CreateZExt(builder.CreateNot(overflow),
                                   builder.getInt32Ty()),
                0);
            return builder.CreateInsertValue(aggregate, value, 1);
          }
          return lowering.construct(instruction.result.type, {value, overflow});
        }
        return value;
      }
      if (method.starts_with("unchecked_")) {
        auto unchecked = method.substr(10);
        if (unchecked == "neg")
          return builder.CreateNeg(a);
        if (unchecked == "shl" || unchecked == "shr") {
          auto *count = builder.CreateZExtOrTrunc(b, a->getType());
          return unchecked == "shl" ? builder.CreateShl(a, count)
                 : sign             ? builder.CreateAShr(a, count)
                                    : builder.CreateLShr(a, count);
        }
        return unchecked == "add"   ? builder.CreateAdd(a, b)
               : unchecked == "sub" ? builder.CreateSub(a, b)
                                    : builder.CreateMul(a, b);
      }
      if (method == "unbounded_shl" || method == "unbounded_shr") {
        auto *tooWide = builder.CreateICmpUGE(b, builder.getInt32(width));
        auto *count = builder.CreateAnd(b, builder.getInt32(width - 1));
        count = builder.CreateZExtOrTrunc(count, a->getType());
        auto *shifted = method == "unbounded_shl" ? builder.CreateShl(a, count)
                        : sign ? builder.CreateAShr(a, count)
                               : builder.CreateLShr(a, count);
        auto *wideResult = method == "unbounded_shr" && sign
                               ? builder.CreateAShr(a, integer(width - 1))
                               : integer(0);
        return builder.CreateSelect(tooWide, wideResult, shifted);
      }
      if (method == "next_power_of_two" ||
          method == "checked_next_power_of_two") {
        bool optional = method == "checked_next_power_of_two";
        auto *zero = builder.CreateICmpEQ(a, integer(0));
        auto *decremented = builder.CreateSub(a, integer(1));
        auto *leading = builder.CreateZExtOrTrunc(
            invoke(llvm::Intrinsic::ctlz, {decremented, builder.getFalse()}),
            builder.getInt32Ty());
        auto *shift = builder.CreateSub(builder.getInt32(width), leading);
        auto *overflow = builder.CreateAnd(
            builder.CreateICmpUGE(shift, builder.getInt32(width)),
            builder.CreateNot(zero));
        if (!optional && checked)
          panicIf(overflow);
        auto *safeShift =
            builder.CreateSelect(overflow, builder.getInt32(width - 1), shift);
        auto *count = builder.CreateZExtOrTrunc(safeShift, a->getType());
        auto *power = builder.CreateShl(integer(1), count);
        power = builder.CreateSelect(zero, integer(1), power);
        power = builder.CreateSelect(overflow, integer(0), power);
        if (!optional)
          return power;
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        aggregate = builder.CreateInsertValue(
            aggregate,
            builder.CreateZExt(builder.CreateNot(overflow),
                               builder.getInt32Ty()),
            0);
        return builder.CreateInsertValue(aggregate, power, 1);
      }
      if (method == "div_ceil" || method == "next_multiple_of" ||
          method == "checked_next_multiple_of" || method == "is_multiple_of") {
        auto *zero = builder.CreateICmpEQ(b, integer(0));
        auto *safeDivisor = builder.CreateSelect(zero, integer(1), b);
        auto *quotient = builder.CreateUDiv(a, safeDivisor);
        auto *remainder = builder.CreateURem(a, safeDivisor);
        if (method == "div_ceil") {
          panicIf(zero);
          auto *hasRemainder = builder.CreateICmpNE(remainder, integer(0));
          return builder.CreateAdd(
              quotient, builder.CreateZExt(hasRemainder, a->getType()));
        }
        if (method == "is_multiple_of")
          return builder.CreateOr(
              builder.CreateAnd(zero, builder.CreateICmpEQ(a, integer(0))),
              builder.CreateAnd(builder.CreateNot(zero),
                                builder.CreateICmpEQ(remainder, integer(0))));
        bool optional = method == "checked_next_multiple_of";
        auto *hasRemainder = builder.CreateICmpNE(remainder, integer(0));
        auto *increment = builder.CreateSelect(
            hasRemainder, builder.CreateSub(b, remainder), integer(0));
        auto *sum = invoke(llvm::Intrinsic::uadd_with_overflow, {a, increment});
        auto *rounded = builder.CreateExtractValue(sum, 0);
        auto *overflow =
            builder.CreateOr(zero, builder.CreateExtractValue(sum, 1));
        if (!optional) {
          panicIf(checked ? overflow : zero);
          return rounded;
        }
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        aggregate = builder.CreateInsertValue(
            aggregate,
            builder.CreateZExt(builder.CreateNot(overflow),
                               builder.getInt32Ty()),
            0);
        return builder.CreateInsertValue(aggregate, rounded, 1);
      }
      if (method == "midpoint") {
        auto *wideA = sign
                          ? builder.CreateSExt(a, builder.getIntNTy(width + 1))
                          : builder.CreateZExt(a, builder.getIntNTy(width + 1));
        auto *wideB = sign
                          ? builder.CreateSExt(b, builder.getIntNTy(width + 1))
                          : builder.CreateZExt(b, builder.getIntNTy(width + 1));
        auto *sum = builder.CreateAdd(wideA, wideB);
        auto *two = llvm::ConstantInt::get(context, llvm::APInt(width + 1, 2));
        auto *half =
            sign ? builder.CreateSDiv(sum, two) : builder.CreateUDiv(sum, two);
        return builder.CreateTrunc(half, a->getType());
      }
      if (method == "is_positive" || method == "is_negative") {
        if (!sign)
          return method == "is_positive" ? builder.CreateICmpNE(a, integer(0))
                                         : builder.getFalse();
        return method == "is_positive" ? builder.CreateICmpSGT(a, integer(0))
                                       : builder.CreateICmpSLT(a, integer(0));
      }
      if (method == "signum") {
        auto *nonzero = builder.CreateICmpNE(a, integer(0));
        if (!sign)
          return builder.CreateZExt(nonzero, a->getType());
        auto *negative = builder.CreateICmpSLT(a, integer(0));
        auto *minusOne =
            llvm::ConstantInt::get(context, llvm::APInt::getAllOnes(width));
        return builder.CreateSelect(negative, minusOne,
                                    builder.CreateZExt(nonzero, a->getType()));
      }
      if (method == "is_power_of_two") {
        auto *nonzero = builder.CreateICmpNE(a, integer(0));
        auto *positive = sign ? builder.CreateICmpSGT(a, integer(0)) : nonzero;
        auto *previous = builder.CreateSub(a, integer(1));
        return builder.CreateAnd(
            positive,
            builder.CreateICmpEQ(builder.CreateAnd(a, previous), integer(0)));
      }
      if (method == "unsigned_abs") {
        auto *negative = builder.CreateICmpSLT(a, integer(0));
        return builder.CreateSelect(negative, builder.CreateNeg(a), a);
      }
      if (method == "abs_diff") {
        auto *less =
            sign ? builder.CreateICmpSLT(a, b) : builder.CreateICmpULT(a, b);
        return builder.CreateSelect(less, builder.CreateSub(b, a),
                                    builder.CreateSub(a, b));
      }
      if (method == "pow" || method == "checked_pow" ||
          method == "wrapping_pow" || method == "overflowing_pow" ||
          method == "saturating_pow" || method == "strict_pow") {
        bool optional = method == "checked_pow";
        bool overflowing = method == "overflowing_pow";
        bool saturating = method == "saturating_pow";
        bool wrapping = method == "wrapping_pow";
        bool strict = method == "strict_pow";
        auto *one = integer(1);
        auto *minimum = llvm::ConstantInt::get(
            context, sign ? llvm::APInt::getSignedMinValue(width)
                          : llvm::APInt::getZero(width));
        auto *maximum = llvm::ConstantInt::get(
            context, sign ? llvm::APInt::getSignedMaxValue(width)
                          : llvm::APInt::getAllOnes(width));
        auto multiply = [&](llvm::Value *left, llvm::Value *right) {
          auto intrinsic = sign ? llvm::Intrinsic::smul_with_overflow
                                : llvm::Intrinsic::umul_with_overflow;
          auto *function = llvm::Intrinsic::getOrInsertDeclaration(
              module.get(), intrinsic, {left->getType()});
          auto *pair = builder.CreateCall(function, {left, right});
          return std::pair{builder.CreateExtractValue(pair, 0),
                           builder.CreateExtractValue(pair, 1)};
        };
        auto *function = builder.GetInsertBlock()->getParent();
        auto *preheader = builder.GetInsertBlock();
        auto *loop = llvm::BasicBlock::Create(context, "pow.loop", function);
        auto *body = llvm::BasicBlock::Create(context, "pow.body", function);
        auto *done = llvm::BasicBlock::Create(context, "pow.done", function);
        builder.CreateBr(loop);
        builder.SetInsertPoint(loop);
        auto *exponent = builder.CreatePHI(b->getType(), 2);
        auto *result = builder.CreatePHI(a->getType(), 2);
        auto *factor = builder.CreatePHI(a->getType(), 2);
        auto *overflow = builder.CreatePHI(builder.getInt1Ty(), 2);
        exponent->addIncoming(b, preheader);
        result->addIncoming(one, preheader);
        factor->addIncoming(a, preheader);
        overflow->addIncoming(builder.getFalse(), preheader);
        builder.CreateCondBr(
            builder.CreateICmpNE(exponent, builder.getInt32(0)), body, done);
        builder.SetInsertPoint(body);
        auto *used = builder.CreateICmpNE(
            builder.CreateAnd(exponent, builder.getInt32(1)),
            builder.getInt32(0));
        auto [product, productOverflow] = multiply(result, factor);
        llvm::Value *selectedProduct = product;
        if (saturating) {
          auto *negative =
              sign
                  ? builder.CreateXor(builder.CreateICmpSLT(result, integer(0)),
                                      builder.CreateICmpSLT(factor, integer(0)))
                  : builder.getFalse();
          auto *limit =
              sign ? builder.CreateSelect(negative, minimum, maximum) : maximum;
          selectedProduct =
              builder.CreateSelect(productOverflow, limit, product);
        }
        auto *nextResult = builder.CreateSelect(used, selectedProduct, result);
        auto *remaining = builder.CreateLShr(exponent, builder.getInt32(1));
        auto *hasRemaining =
            builder.CreateICmpNE(remaining, builder.getInt32(0));
        auto [square, squareOverflow] = multiply(factor, factor);
        auto *nextFactor =
            saturating ? builder.CreateSelect(squareOverflow, maximum, square)
                       : square;
        auto *nextOverflow = builder.CreateOr(
            overflow,
            builder.CreateOr(builder.CreateAnd(used, productOverflow),
                             builder.CreateAnd(hasRemaining, squareOverflow)));
        auto *backedge = builder.GetInsertBlock();
        builder.CreateBr(loop);
        exponent->addIncoming(remaining, backedge);
        result->addIncoming(nextResult, backedge);
        factor->addIncoming(nextFactor, backedge);
        overflow->addIncoming(nextOverflow, backedge);
        builder.SetInsertPoint(done);
        auto *resultValue = static_cast<llvm::Value *>(result);
        auto *overflowValue = static_cast<llvm::Value *>(overflow);
        if (strict ||
            (!optional && !overflowing && !saturating && !wrapping && checked))
          panicIf(overflowValue);
        if (optional || overflowing) {
          llvm::Value *aggregate =
              llvm::Constant::getNullValue(type(instruction.result.type));
          if (optional) {
            aggregate = builder.CreateInsertValue(
                aggregate,
                builder.CreateZExt(builder.CreateNot(overflowValue),
                                   builder.getInt32Ty()),
                0);
            return builder.CreateInsertValue(aggregate, resultValue, 1);
          }
          return lowering.construct(instruction.result.type,
                                    {resultValue, overflowValue});
        }
        return resultValue;
      }
      bool strict = method.starts_with("strict_");
      bool optional = method.starts_with("checked_");
      bool overflowing = method.starts_with("overflowing_");
      bool saturating = method.starts_with("saturating_");
      bool wrapping = method.starts_with("wrapping_");
      method.remove_prefix(strict        ? 7
                           : optional    ? 8
                           : overflowing ? 12
                           : saturating  ? 11
                           : wrapping    ? 9
                                         : 0);
      llvm::Value *value = nullptr, *overflow = nullptr;
      auto *minimum = llvm::ConstantInt::get(
          context, sign ? llvm::APInt::getSignedMinValue(width)
                        : llvm::APInt::getZero(width));
      auto *maximum = llvm::ConstantInt::get(
          context, sign ? llvm::APInt::getSignedMaxValue(width)
                        : llvm::APInt::getAllOnes(width));
      if (method == "shl" || method == "shr") {
        overflow = builder.CreateICmpUGE(b, builder.getInt32(width));
        auto *count = builder.CreateAnd(b, builder.getInt32(width - 1));
        count = builder.CreateZExtOrTrunc(count, a->getType());
        value = method == "shl" ? builder.CreateShl(a, count)
                : sign          ? builder.CreateAShr(a, count)
                                : builder.CreateLShr(a, count);
        if (strict)
          panicIf(overflow);
      } else if (method == "div" || method == "rem" || method == "div_euclid" ||
                 method == "rem_euclid") {
        bool euclidean = method == "div_euclid" || method == "rem_euclid";
        bool remainder = method == "rem" || method == "rem_euclid";
        auto *zero = builder.CreateICmpEQ(b, integer(0));
        auto *negativeOne =
            llvm::ConstantInt::get(context, llvm::APInt::getAllOnes(width));
        overflow = sign
                       ? builder.CreateAnd(builder.CreateICmpEQ(a, minimum),
                                           builder.CreateICmpEQ(b, negativeOne))
                       : builder.getFalse();
        if (!optional)
          panicIf(zero);
        auto *invalid = builder.CreateOr(zero, overflow);
        auto *divisor = builder.CreateSelect(invalid, integer(1), b);
        auto *quotient = sign ? builder.CreateSDiv(a, divisor)
                              : builder.CreateUDiv(a, divisor);
        auto *remainderValue = sign ? builder.CreateSRem(a, divisor)
                                    : builder.CreateURem(a, divisor);
        if (euclidean && sign) {
          auto *negativeRemainder =
              builder.CreateICmpSLT(remainderValue, integer(0));
          auto *positiveDivisor = builder.CreateICmpSGT(divisor, integer(0));
          auto *adjustedQuotient = builder.CreateSelect(
              positiveDivisor, builder.CreateSub(quotient, integer(1)),
              builder.CreateAdd(quotient, integer(1)));
          quotient = builder.CreateSelect(negativeRemainder, adjustedQuotient,
                                          quotient);
          auto *divisorMagnitude = builder.CreateSelect(
              positiveDivisor, divisor, builder.CreateNeg(divisor));
          auto *adjustedRemainder =
              builder.CreateAdd(remainderValue, divisorMagnitude);
          remainderValue = builder.CreateSelect(
              negativeRemainder, adjustedRemainder, remainderValue);
        }
        value = remainder ? remainderValue : quotient;
        value = builder.CreateSelect(
            overflow, remainder ? integer(0) : (saturating ? maximum : minimum),
            value);
        overflow = builder.CreateOr(zero, overflow);
        if (strict ||
            (!optional && !overflowing && !saturating && !wrapping && checked))
          panicIf(overflow);
      } else if (method == "neg" || method == "abs") {
        auto *negated = builder.CreateNeg(a);
        overflow = sign ? builder.CreateICmpEQ(a, minimum)
                        : builder.CreateICmpNE(a, integer(0));
        value = method == "abs"
                    ? builder.CreateSelect(builder.CreateICmpSLT(a, integer(0)),
                                           negated, a)
                    : negated;
        if (saturating)
          value = builder.CreateSelect(overflow, sign ? maximum : integer(0),
                                       value);
        if (strict ||
            (!optional && !overflowing && !saturating && !wrapping && checked))
          panicIf(overflow);
      } else {
        auto intrinsic =
            method == "add"   ? (sign ? llvm::Intrinsic::sadd_with_overflow
                                      : llvm::Intrinsic::uadd_with_overflow)
            : method == "sub" ? (sign ? llvm::Intrinsic::ssub_with_overflow
                                      : llvm::Intrinsic::usub_with_overflow)
                              : (sign ? llvm::Intrinsic::smul_with_overflow
                                      : llvm::Intrinsic::umul_with_overflow);
        auto *pair = invoke(intrinsic, {a, b});
        value = builder.CreateExtractValue(pair, 0);
        overflow = builder.CreateExtractValue(pair, 1);
        if (saturating) {
          llvm::Value *limit = method == "sub" ? integer(0) : maximum;
          if (sign) {
            auto *negative = builder.CreateICmpSLT(a, integer(0));
            if (method == "mul")
              negative = builder.CreateXor(
                  negative, builder.CreateICmpSLT(b, integer(0)));
            limit = builder.CreateSelect(negative, minimum, maximum);
          }
          value = builder.CreateSelect(overflow, limit, value);
        }
        if (strict ||
            (!optional && !overflowing && !saturating && !wrapping && checked))
          panicIf(overflow);
      }
      if (optional || overflowing) {
        llvm::Value *aggregate =
            llvm::Constant::getNullValue(type(instruction.result.type));
        if (optional) {
          aggregate = builder.CreateInsertValue(
              aggregate,
              builder.CreateZExt(builder.CreateNot(overflow),
                                 builder.getInt32Ty()),
              0);
          return builder.CreateInsertValue(aggregate, value, 1);
        }
        return lowering.construct(instruction.result.type, {value, overflow});
      }
      return value;
    }
    if (operation == "ptr.null" || operation == "ptr.null_mut")
      return llvm::ConstantPointerNull::get(builder.getPtrTy());
    if (operation == "ptr.without_provenance" ||
        operation == "ptr.with_exposed_provenance")
      return builder.CreateIntToPtr(arguments[0], builder.getPtrTy());
    if (operation == "ptr.from_ref" || operation == "ptr.from_mut")
      return arguments[0];
    auto *handle = arguments[0];
    auto *data = handle->getType()->isStructTy()
                     ? builder.CreateExtractValue(handle, 0)
                     : handle;
    auto method = operation.substr(4);
    if (method == "addr" || method == "expose_provenance")
      return builder.CreatePtrToInt(data, builder.getInt64Ty());
    if (method == "is_null")
      return builder.CreateIsNull(data);
    if (method == "cast" || method == "cast_mut" || method == "cast_const")
      return type(instruction.result.type)->isPointerTy() ? data : handle;
    auto payload = program.types->pointer(instruction.operands[0].type).payload;
    if (method == "copy" || method == "copy_nonoverlapping") {
      auto *size = builder.CreateMul(
          arguments[2], builder.getInt64(lowering.layout(payload).size));
      auto alignment = llvm::Align(lowering.alignment(payload));
      if (method == "copy")
        builder.CreateMemMove(arguments[1], alignment, data, alignment, size);
      else
        builder.CreateMemCpy(arguments[1], alignment, data, alignment, size);
      return unit();
    }
    if (method == "write_bytes") {
      auto *size = builder.CreateMul(
          arguments[2], builder.getInt64(lowering.layout(payload).size));
      builder.CreateMemSet(data, arguments[1], size,
                           llvm::Align(lowering.alignment(payload)));
      return unit();
    }
    if (method == "replace") {
      auto alignment = llvm::Align(lowering.alignment(payload));
      auto *old = lowering.load(payload, data, alignment);
      lowering.store(payload, arguments[1], data, alignment);
      return old;
    }
    if (method == "swap" || method == "swap_nonoverlapping") {
      auto alignment = llvm::Align(lowering.alignment(payload));
      auto *temporary = lowering.temporary(payload);
      auto size = lowering.layout(payload).size;
      auto swap = [&](llvm::Value *first, llvm::Value *second) {
        builder.CreateMemCpy(temporary, alignment, first, alignment, size);
        builder.CreateMemMove(first, alignment, second, alignment, size);
        builder.CreateMemCpy(second, alignment, temporary, alignment, size);
      };
      if (method == "swap") {
        swap(data, arguments[1]);
      } else {
        auto *function = builder.GetInsertBlock()->getParent();
        auto *before = builder.GetInsertBlock();
        auto *loop = llvm::BasicBlock::Create(context, "swap.loop", function);
        auto *body = llvm::BasicBlock::Create(context, "swap.body", function);
        auto *done = llvm::BasicBlock::Create(context, "swap.done", function);
        builder.CreateBr(loop);
        builder.SetInsertPoint(loop);
        auto *index = builder.CreatePHI(builder.getInt64Ty(), 2);
        index->addIncoming(builder.getInt64(0), before);
        builder.CreateCondBr(builder.CreateICmpULT(index, arguments[2]), body,
                             done);
        builder.SetInsertPoint(body);
        auto *first =
            builder.CreateGEP(lowering.storageType(payload), data, index);
        auto *second = builder.CreateGEP(lowering.storageType(payload),
                                         arguments[1], index);
        swap(first, second);
        auto *next = builder.CreateAdd(index, builder.getInt64(1));
        builder.CreateBr(loop);
        index->addIncoming(next, body);
        builder.SetInsertPoint(done);
      }
      return unit();
    }
    if (method == "offset_from" || method == "offset_from_unsigned" ||
        method == "byte_offset_from" || method == "byte_offset_from_unsigned") {
      auto *other = arguments[1]->getType()->isStructTy()
                        ? builder.CreateExtractValue(arguments[1], 0)
                        : arguments[1];
      auto *distance = builder.CreateSub(
          builder.CreatePtrToInt(data, builder.getInt64Ty()),
          builder.CreatePtrToInt(other, builder.getInt64Ty()));
      auto size =
          method.starts_with("byte_") ? 1 : lowering.layout(payload).size;
      if (!size) {
        emitPanic();
        return builder.getInt64(0);
      }
      if (method.ends_with("_unsigned"))
        panicIf(builder.CreateICmpSLT(distance, builder.getInt64(0)));
      return builder.CreateSDiv(distance, builder.getInt64(size));
    }
    if (method.starts_with("read") &&
        lowering.indirect(instruction.result.type))
      return lowering.load(
          instruction.result.type, data,
          method == "read_unaligned"
              ? llvm::Align(1)
              : llvm::Align(lowering.alignment(instruction.result.type)),
          method == "read_volatile");
    if (method.starts_with("write") &&
        lowering.indirect(instruction.operands[1].type)) {
      lowering.store(
          instruction.operands[1].type, arguments[1], data,
          method == "write_unaligned"
              ? llvm::Align(1)
              : llvm::Align(lowering.alignment(instruction.operands[1].type)),
          method == "write_volatile");
      return unit();
    }
    if (method.starts_with("read")) {
      auto *load = builder.CreateLoad(
          lowering.storageType(instruction.result.type), data);
      load->setVolatile(method == "read_volatile");
      if (method == "read_unaligned")
        load->setAlignment(llvm::Align(1));
      return load->getType() == type(instruction.result.type)
                 ? load
                 : builder.CreateTrunc(load, type(instruction.result.type));
    }
    if (method.starts_with("write")) {
      auto *value = arguments[1];
      auto *physical = lowering.storageType(instruction.operands[1].type);
      if (value->getType() != physical)
        value = builder.CreateZExt(value, physical);
      auto *store = builder.CreateStore(value, data);
      store->setVolatile(method == "write_volatile");
      if (method == "write_unaligned")
        store->setAlignment(llvm::Align(1));
      return unit();
    }
    llvm::Value *offset = arguments[1];
    llvm::Type *element = builder.getInt8Ty();
    bool wrapping = method.starts_with("wrapping_");
    if (wrapping)
      method.remove_prefix(9);
    bool bytes = method.starts_with("byte_");
    if (bytes)
      method.remove_prefix(5);
    if (method == "with_addr")
      offset = builder.CreateSub(
          offset, builder.CreatePtrToInt(data, builder.getInt64Ty()));
    else {
      if (method == "sub")
        offset = builder.CreateNeg(offset);
      if (!bytes)
        element = lowering.storageType(
            program.types->pointer(instruction.operands[0].type).payload);
    }
    auto *result = wrapping || method == "with_addr"
                       ? builder.CreateGEP(element, data, offset)
                       : builder.CreateInBoundsGEP(element, data, offset);
    return handle->getType()->isStructTy()
               ? builder.CreateInsertValue(handle, result, 0)
               : result;
  }
  void function(const ir::Function &source, llvm::Function *target) {
    llvm::FastMathFlags flags;
    const auto &policy = source.floatingPolicy;
    flags.setAllowReassoc(policy.reassociate);
    flags.setAllowContract(policy.contract);
    flags.setNoNaNs(policy.noNaNs);
    flags.setNoInfs(policy.noInfinities);
    flags.setNoSignedZeros(policy.noSignedZeros);
    flags.setAllowReciprocal(policy.reciprocal);
    flags.setApproxFunc(policy.approximateFunctions);
    builder.setFastMathFlags(flags);
    if (debugInfo)
      debugInfo->clear(builder);
    std::unique_ptr<CleanupFrame> ownFrame;
    if (!source.coroutine)
      ownFrame = std::make_unique<CleanupFrame>(lowering, source, target);
    auto &frame = source.coroutine ? coroutineFrame(static_cast<int>(
                                         &source - program.functions.data()))
                                   : *ownFrame;
    if (debugInfo)
      debugInfo->begin(builder, debugInfo->attach(*target, source, true),
                       nullptr, false);
    if (source.coroutine) {
      // A coroutine body runs only through its state's resumption.
      frame.finishCallbacks();
      builder.SetInsertPoint(
          llvm::BasicBlock::Create(context, "entry", target));
      builder.CreateUnreachable();
    } else
      frame.createWrapper();
    target = frame.body();
    applyInlineHint(*target, source.inlineHint);
    if (debugInfo)
      debugInfo->begin(builder, debugInfo->attach(*target, source, false),
                       &source, true);
    targetAttributes(*target, program.target, source.targetFeatures);
    std::vector<llvm::BasicBlock *> blocks, ends;
    llvm::BasicBlock *dispatch =
        source.coroutine ? llvm::BasicBlock::Create(context, "dispatch", target)
                         : nullptr;
    // Coroutine values crossing blocks are reloaded from their frame slots at
    // the start of each using block (phi operands in the predecessor).
    std::vector<std::vector<ir::Value>> reloads(source.blocks.size());
    std::vector<int> resumes;
    std::map<std::pair<int, int>, llvm::Value *> incoming;
    if (source.coroutine) {
      std::vector<int> defined(source.values, -1);
      for (std::size_t b = 0; b < source.blocks.size(); ++b)
        for (const auto &n : source.blocks[b].instructions)
          if (n.result.id >= 0)
            defined[n.result.id] = static_cast<int>(b);
      std::set<std::pair<int, int>> seen;
      auto reload = [&](const ir::Value &value, int block) {
        if (value.id >= 0 && defined[value.id] != block &&
            frame.spilled(value.id) && seen.insert({block, value.id}).second)
          reloads[block].push_back(value);
      };
      for (std::size_t b = 0; b < source.blocks.size(); ++b) {
        int block = static_cast<int>(b);
        for (const auto &n : source.blocks[b].instructions) {
          if (n.op == ir::Op::Phi) {
            for (std::size_t i = 0; i < n.operands.size(); ++i)
              reload(n.operands[i], n.predecessors[i]);
            continue;
          }
          for (const auto &operand : n.operands)
            reload(operand, block);
          reload(n.target, block);
        }
        reload(source.blocks[b].exit.value, block);
      }
    }
    for (std::size_t i = 0; i < source.blocks.size(); ++i)
      blocks.push_back(
          llvm::BasicBlock::Create(context, "b" + std::to_string(i), target));
    ends.resize(blocks.size());
    builder.SetInsertPoint(blocks[0]);
    auto address = [&](const Place &place) -> llvm::Value * {
      return frame.address(place);
    };
    std::vector<llvm::Value *> values(source.values, nullptr);
    std::vector<unsigned> uses(source.values, 0);
    for (const auto &block : source.blocks) {
      for (const auto &instruction : block.instructions) {
        for (const auto &operand : instruction.operands)
          if (operand.id >= 0)
            ++uses[operand.id];
        if (instruction.target.id >= 0)
          ++uses[instruction.target.id];
      }
      if (block.exit.value.id >= 0)
        ++uses[block.exit.value.id];
    }
    // A large value consumed only by the next instruction can alias its
    // source: that instruction reads it before anything else can write.
    auto aliasable = [&](const ir::Block &block, std::size_t position) {
      const auto &n = block.instructions[position];
      if (!lowering.indirect(n.result.type) || uses[n.result.id] != 1 ||
          position + 1 >= block.instructions.size() ||
          frame.alignment(n.place).value() < lowering.alignment(n.result.type))
        return false;
      const auto &next = block.instructions[position + 1];
      return next.op != ir::Op::Phi && next.op != ir::Op::ArrayRepeat &&
             std::any_of(next.operands.begin(), next.operands.end(),
                         [&](const ir::Value &operand) {
                           return operand.id == n.result.id;
                         });
    };
    auto directDestination = [&](const ir::Block &block,
                                 std::size_t position) -> llvm::Value * {
      const auto &n = block.instructions[position];
      if (!lowering.indirect(n.result.type) ||
          program.types->needsDrop(n.result.type) || uses[n.result.id] != 1 ||
          position + 1 >= block.instructions.size())
        return nullptr;
      const auto &next = block.instructions[position + 1];
      if (next.op != ir::Op::Store || next.operands.size() != 1 ||
          next.operands[0].id != n.result.id ||
          *projectedType(*program.types, source.locals[next.place.root].type,
                         next.place.fields) != n.result.type ||
          frame.alignment(next.place).value() <
              lowering.alignment(n.result.type))
        return nullptr;
      return address(next.place);
    };
    struct Pending {
      llvm::PHINode *phi;
      const ir::Instruction *instruction;
      int block;
    };
    std::vector<Pending> pending;
    if (debugInfo && !source.name.starts_with('<')) {
      builder.SetInsertPoint(blocks[0]);
      for (std::size_t i = 0; i < source.locals.size(); ++i) {
        const auto &local = source.locals[i];
        if (local.name.empty() || local.name.starts_with('<'))
          continue;
        if (i >= source.parameters && local.storage != StorageDuration::Static)
          continue;
        bool borrowed =
            local.storage == StorageDuration::Static ||
            (i < source.parameters && (local.mode == ParameterMode::Read ||
                                       local.mode == ParameterMode::Mut));
        debugInfo->declare(builder, i, local,
                           i < source.parameters ? static_cast<unsigned>(i + 1)
                                                 : 0,
                           borrowed, frame.localStorage(i));
      }
    }
    for (std::size_t b = 0; b < blocks.size(); ++b) {
      builder.SetInsertPoint(blocks[b]);
      for (const auto &n : source.blocks[b].instructions)
        if (n.op == ir::Op::Phi) {
          auto *phi = builder.CreatePHI(type(n.result.type), n.operands.size());
          pending.push_back({phi, &n, static_cast<int>(b)});
          values[n.result.id] = phi;
        }
      for (const auto &value : reloads[b])
        values[value.id] =
            lowering.load(value.type, frame.spillAddress(value.id),
                          llvm::Align(lowering.alignment(value.type)));
      std::size_t position = static_cast<std::size_t>(-1);
      for (const auto &n : source.blocks[b].instructions) {
        ++position;
        if (debugInfo)
          debugInfo->locate(builder, n.span, n.scope);
        llvm::Value *result = unit();
        auto get = [&](std::size_t i) { return values[n.operands[i].id]; };
        switch (n.op) {
        case ir::Op::FeatureTest:
          result = detectFeature(lowering, n.text);
          break;
        case ir::Op::TextLiteral: {
          auto *global = textGlobal(n.text);
          // Byte text of a known length is a thin pointer to the array.
          if (auto *fat = llvm::dyn_cast<llvm::StructType>(type(n.result.type)))
            result = llvm::ConstantStruct::get(
                fat, {global, builder.getInt64(n.text.size())});
          else
            result = global;
          break;
        }
        case ir::Op::Assembly: {
          std::vector<llvm::Value *> inputs;
          std::vector<llvm::Function *> symbols;
          for (std::size_t i = 0; i < n.operands.size(); ++i)
            inputs.push_back(get(i));
          for (std::size_t i = 0; i < functions.size(); ++i)
            symbols.push_back(externals[i] ? externals[i] : functions[i]);
          AssemblySymbolResolver resolveSymbol =
              [&](AssemblyOperand::SymbolKind kind,
                  int id) -> llvm::GlobalValue * {
            return kind == AssemblyOperand::SymbolKind::Function
                       ? static_cast<llvm::GlobalValue *>(symbols[id])
                       : lowering.statics[id];
          };
          result = emitAssembly(lowering, *n.assembly, n.result.type, inputs,
                                resolveSymbol);
          break;
        }
        case ir::Op::SliceLength: {
          auto slice = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          auto *handle =
              builder.CreateLoad(lowering.viewType(slice), address(n.place));
          auto *length = builder.CreateExtractValue(handle, 1);
          result = length;
          break;
        }
        case ir::Op::UnsizeView:
          result = llvm::UndefValue::get(type(n.result.type));
          result = builder.CreateInsertValue(result, address(n.place), 0);
          result = builder.CreateInsertValue(
              result, builder.CreateZExtOrTrunc(get(0), builder.getInt64Ty()),
              1);
          break;
        case ir::Op::OwnerUnsize: {
          auto sourceOwner = n.operands[0].type;
          auto targetOwner = n.result.type;
          const auto &source = program.types->product(sourceOwner);
          const auto &target = program.types->product(targetOwner);
          auto sourcePayload = source.genericArguments.front();
          auto targetPayload = target.genericArguments.front();
          auto *owner = get(0);
          auto *data = lowering.extract(owner, sourceOwner, 0);
          auto pointerType = target.fields.front().type;
          llvm::Value *pointer = llvm::UndefValue::get(type(pointerType));
          pointer = builder.CreateInsertValue(pointer, data, 0);
          if (program.types->pointerMetadata(targetPayload) ==
              PointerMetadata::ElementCount) {
            pointer = builder.CreateInsertValue(
                pointer,
                builder.CreateZExtOrTrunc(get(1), builder.getInt64Ty()), 1);
          } else {
            std::vector<llvm::Constant *> methods;
            for (std::size_t method = 1; method < n.operands.size(); ++method)
              methods.push_back(
                  n.operands[method].type == Type::Unit
                      ? llvm::ConstantPointerNull::get(builder.getPtrTy())
                      : llvm::cast<llvm::Constant>(get(method)));
            auto *table =
                witness(sourcePayload, targetPayload, targetPayload, methods);
            pointer =
                builder.CreateInsertValue(pointer, builder.getInt64(0), 1);
            pointer = builder.CreateInsertValue(pointer, table, 2);
          }
          std::vector<llvm::Value *> fields{pointer};
          for (std::size_t field = 1; field < source.fields.size(); ++field)
            fields.push_back(lowering.extract(owner, sourceOwner, field));
          frame.consume(n.operands[0]);
          result = lowering.construct(targetOwner, fields);
          break;
        }
        case ir::Op::SliceBorrowRead:
        case ir::Op::SliceBorrowMut: {
          auto slice = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          auto *handle =
              builder.CreateLoad(lowering.viewType(slice), address(n.place));
          auto *data = builder.CreateExtractValue(handle, 0);
          auto *length = builder.CreateExtractValue(handle, 1);
          if (n.operands.size() == 2) {
            auto *start =
                builder.CreateZExtOrTrunc(get(0), builder.getInt64Ty());
            auto *end = builder.CreateZExtOrTrunc(get(1), builder.getInt64Ty());
            panicIf(builder.CreateOr(builder.CreateICmpUGT(start, end),
                                     builder.CreateICmpUGT(end, length)));
            result = llvm::UndefValue::get(type(n.result.type));
            result = builder.CreateInsertValue(
                result,
                builder.CreateGEP(
                    lowering.storageType(program.types->slice(slice).element),
                    data, start),
                0);
            result = builder.CreateInsertValue(
                result, builder.CreateSub(end, start), 1);
            break;
          }
          auto *index = builder.CreateZExtOrTrunc(get(0), builder.getInt64Ty());
          auto *negative =
              n.operands[0].type == Type::I32
                  ? builder.CreateICmpSLT(get(0), builder.getInt32(0))
                  : builder.getFalse();
          panicIf(
              builder.CreateOr(negative, builder.CreateICmpUGE(index, length)));
          result = builder.CreateGEP(
              lowering.storageType(program.types->slice(slice).element), data,
              index);
          break;
        }
        case ir::Op::OpaqueRepack:
          result = n.result.access == ir::Access::Owned
                       ? repack(get(0), n.operands[0].type, n.result.type)
                       : get(0);
          frame.consume(n.operands[0]);
          break;
        case ir::Op::EraseView: {
          std::vector<llvm::Constant *> methods;
          for (std::size_t i = 0; i < n.operands.size(); ++i)
            methods.push_back(
                n.operands[i].type == Type::Unit
                    ? llvm::ConstantPointerNull::get(builder.getPtrTy())
                    : llvm::cast<llvm::Constant>(get(i)));
          auto *table = witness(n.interfaceSelf, n.interfaceType,
                                n.interfaceType, methods);
          auto sourceTypeId = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          llvm::Value *data = address(n.place), *count = builder.getInt64(0);
          if (program.types->pointerMetadata(sourceTypeId) ==
              PointerMetadata::ElementCount) {
            auto *handle =
                builder.CreateLoad(lowering.viewType(sourceTypeId), data);
            data = builder.CreateExtractValue(handle, 0);
            count = builder.CreateExtractValue(handle, 1);
          }
          result = llvm::UndefValue::get(type(n.result.type));
          result = builder.CreateInsertValue(result, data, 0);
          result = builder.CreateInsertValue(result, count, 1);
          result = builder.CreateInsertValue(result, table, 2);
          break;
        }
        case ir::Op::ErasedUpcast: {
          auto sourceTypeId = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          auto *handle = builder.CreateLoad(lowering.viewType(sourceTypeId),
                                            address(n.place));
          auto *table = builder.CreateExtractValue(handle, 2);
          auto offset =
              5 + program.types->erased(n.interfaceSelf).methodTypes.size() +
              n.number;
          auto *slot = builder.CreateGEP(
              builder.getPtrTy(), table,
              builder.getInt32(static_cast<std::uint32_t>(offset)));
          auto *parent = builder.CreateLoad(builder.getPtrTy(), slot);
          result = builder.CreateInsertValue(handle, parent, 2);
          break;
        }
        case ir::Op::WitnessMethod: {
          auto handleType = n.operands[0].type;
          auto *handle = pinnedErasedReceiver(*program.types, handleType)
                             ? lowering.extract(get(0), handleType, 0)
                             : builder.CreateLoad(type(handleType), get(0));
          auto *table = builder.CreateExtractValue(handle, 2);
          auto *slot = builder.CreateGEP(builder.getPtrTy(), table,
                                         builder.getInt32(n.number + 5));
          result = builder.CreateLoad(builder.getPtrTy(), slot);
          break;
        }
        case ir::Op::FunctionAddress:
          if (n.erasedDispatch &&
              !program.types->callable(n.result.type).parameters.empty() &&
              pinnedErasedReceiver(
                  *program.types,
                  program.types->callable(n.result.type).parameters[0].type))
            result = pinnedWitnessThunk(n);
          else
            result =
                externals[n.callee] ? externals[n.callee] : functions[n.callee];
          break;
        case ir::Op::CallableCoerce:
          result = get(0);
          break;
        case ir::Op::Constant:
          if (n.result.type == Type::Bool)
            result =
                builder.getInt1(n.numeric ? n.numeric->magnitude[0] != 0 ||
                                                n.numeric->magnitude[1] != 0
                                          : n.number != 0);
          else if (n.numeric) {
            if (isFloating(n.result.type)) {
              llvm::APFloat number(n.result.type == Type::F32
                                       ? llvm::APFloat::IEEEsingle()
                                       : llvm::APFloat::IEEEdouble());
              if (n.numeric->floatingBits)
                number = llvm::APFloat(
                    number.getSemantics(),
                    llvm::APInt(n.result.type == Type::F32 ? 32 : 64,
                                *n.numeric->floatingBits));
              else {
                auto status = number.convertFromString(
                    n.numeric->floating, llvm::APFloat::rmNearestTiesToEven);
                if (!status)
                  llvm::report_fatal_error(
                      llvm::Twine(llvm::toString(status.takeError())));
              }
              result = llvm::ConstantFP::get(context, number);
            } else {
              auto width = integerWidth(n.result.type);
              llvm::APInt number(
                  width, llvm::ArrayRef<std::uint64_t>(n.numeric->magnitude)
                             .take_front(width > 64 ? 2 : 1));
              if (n.numeric->negative)
                number = -number;
              result = llvm::ConstantInt::get(context, number);
            }
          } else if (isInteger(n.result.type) || n.result.type == Type::Char)
            result =
                llvm::ConstantInt::get(type(n.result.type), n.number, true);
          break;
        case ir::Op::Cast:
          result = cast(get(0), n.operands[0].type, n.result.type);
          break;
        case ir::Op::Machine: {
          std::vector<llvm::Value *> arguments;
          for (std::size_t operand = 0; operand < n.operands.size(); ++operand)
            arguments.push_back(get(operand));
          if (n.text == "coroutine.start") {
            auto *state = lowering.temporary(n.result.type);
            coroutineFrame(n.callee).startCoroutine(state, arguments[0]);
            result = lowering.indirect(n.result.type)
                         ? static_cast<llvm::Value *>(state)
                         : builder.CreateLoad(type(n.result.type), state);
          } else if (n.text == "coroutine.resume")
            result = coroutineFrame(n.callee).resumeCoroutine(
                arguments[0], arguments[1], n.result.type);
          else if (n.text == "coroutine.context")
            result =
                builder.CreateLoad(type(n.result.type), frame.contextAddress());
          else if (n.text == "va.start") {
            result = builder.CreateLoad(type(n.result.type),
                                        frame.variadicContext());
            frame.move({source.variadicCursor, {}});
          } else if (n.text == "va.copy") {
            auto *storage = lowering.temporary(n.result.type);
            builder.CreateStore(
                llvm::Constant::getNullValue(type(n.result.type)), storage);
            builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
                                   module.get(), llvm::Intrinsic::vacopy,
                                   {builder.getPtrTy()}),
                               {storage, arguments[0]});
            result = builder.CreateLoad(type(n.result.type), storage);
          } else if (n.text == "va.arg")
            result = abi.variadicArgument(arguments[0], n.result.type);
          else if (n.text == "va.end") {
            auto *storage = lowering.temporary(n.operands[0].type);
            builder.CreateStore(arguments[0], storage);
            builder.CreateCall(
                llvm::Intrinsic::getOrInsertDeclaration(
                    module.get(), llvm::Intrinsic::vaend, {builder.getPtrTy()}),
                {storage});
          } else
            result = mettle::targetOperation(n.text)
                         ? backend::targetOperation(lowering, n, arguments)
                         : machine(n, arguments);
          for (auto operand : n.operands)
            if (operand.access == ir::Access::Owned)
              frame.consume(operand);
          break;
        }
        case ir::Op::Declare:
          frame.declare(n.place);
          if (debugInfo &&
              n.place.root >= static_cast<int>(source.parameters) &&
              n.place.root >= 0 &&
              static_cast<std::size_t>(n.place.root) < source.locals.size()) {
            auto index = static_cast<std::size_t>(n.place.root);
            const auto &local = source.locals[index];
            if (!local.name.empty() && !local.name.starts_with('<') &&
                local.storage != StorageDuration::Static)
              debugInfo->declare(builder, index, local, 0, false,
                                 frame.localStorage(index));
          }
          break;
        case ir::Op::Load:
        case ir::Op::Move:
          result = aliasable(source.blocks[b], position)
                       ? address(n.place)
                       : lowering.load(n.result.type, address(n.place),
                                       frame.alignment(n.place));
          if (n.op == ir::Op::Move)
            frame.move(n.place);
          if (n.op == ir::Op::Move && debugInfo && n.place.root >= 0 &&
              static_cast<std::size_t>(n.place.root) < source.locals.size())
            debugInfo->invalidate(builder,
                                  static_cast<std::size_t>(n.place.root),
                                  n.span, n.scope);
          break;
        case ir::Op::BorrowRead:
        case ir::Op::BorrowMut:
        case ir::Op::ReserveMut:
        case ir::Op::ViewRead:
        case ir::Op::ViewMut:
          result = address(n.place);
          // A borrowed view value still denotes its slot, not its payload.
          if (n.result.access == ir::Access::Owned &&
              program.types->isView(n.result.type) &&
              program.types->pointerMetadata(
                  program.types->view(n.result.type).payload) !=
                  PointerMetadata::None)
            result = builder.CreateLoad(type(n.result.type), result);
          break;
        case ir::Op::Activate:
          break;
        case ir::Op::ArrayBorrowRead:
        case ir::Op::ArrayBorrowMut: {
          auto array = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          const auto &record = program.types->product(array);
          auto length = *program.types->arrayLength(array);
          auto *elements = llvm::ArrayType::get(
              lowering.storageType(record.components.at(0)), length);
          // A signed index is sign-extended so negatives fail the unsigned
          // bounds comparison.
          auto *index =
              n.operands[0].type == Type::I32
                  ? builder.CreateSExt(get(0), builder.getInt64Ty())
                  : builder.CreateZExtOrTrunc(get(0), builder.getInt64Ty());
          panicIf(builder.CreateICmpUGE(index, builder.getInt64(length)), 2);
          result = builder.CreateGEP(elements, address(n.place),
                                     {builder.getInt64(0), index});
          break;
        }
        case ir::Op::ArrayRepeat:
          result = repeatArray(n.result.type, get(0),
                               directDestination(source.blocks[b], position));
          break;
        case ir::Op::ArrayTake: {
          auto array = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          auto stride = lowering.layout(n.result.type).size;
          auto *index = builder.CreateZExtOrTrunc(get(0), builder.getInt64Ty());
          auto *element = builder.CreateGEP(
              builder.getInt8Ty(), address(n.place),
              builder.CreateMul(index, builder.getInt64(stride)));
          auto alignment = std::min<std::uint64_t>(
              lowering.alignment(array), lowering.alignment(n.result.type));
          result =
              lowering.load(n.result.type, element, llvm::Align(alignment));
          if (debugInfo && n.place.root >= 0 &&
              static_cast<std::size_t>(n.place.root) < source.locals.size())
            debugInfo->invalidate(builder,
                                  static_cast<std::size_t>(n.place.root),
                                  n.span, n.scope);
          break;
        }
        case ir::Op::Store:
        case ir::Op::StorageWrite:
          frame.store(n, get(0));
          if (n.op == ir::Op::Store && debugInfo && n.place.root >= 0 &&
              n.place.fields.empty() &&
              static_cast<std::size_t>(n.place.root) < source.locals.size())
            debugInfo->restore(builder, static_cast<std::size_t>(n.place.root),
                               n.span, n.scope,
                               frame.localStorage(n.place.root));
          if (n.op == ir::Op::StorageWrite)
            frame.consume(n.operands[0]);
          break;
        case ir::Op::DropPlace: {
          auto payload = projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          if (payload && !n.place.fields.empty() &&
              n.place.fields.back().kind == Projection::Kind::Dereference &&
              (program.types->isSlice(*payload) ||
               program.types->isErased(*payload))) {
            auto pointerPlace = n.place;
            pointerPlace.fields.pop_back();
            auto pointerType = projectedType(
                *program.types, source.locals[pointerPlace.root].type,
                pointerPlace.fields);
            if (pointerType && program.types->isPointer(*pointerType)) {
              auto *handle =
                  builder.CreateLoad(type(*pointerType), address(pointerPlace));
              auto *data = handle->getType()->isStructTy()
                               ? builder.CreateExtractValue(handle, 0)
                               : handle;
              if (program.types->isSlice(*payload)) {
                if (program.types->needsDrop(
                        program.types->slice(*payload).element)) {
                  auto *count = builder.CreateExtractValue(handle, 1);
                  if (n.dropFunction >= 0)
                    builder.CreateCall(
                        functions.at(static_cast<std::size_t>(n.dropFunction)),
                        {data, count});
                }
              } else {
                auto *table = builder.CreateExtractValue(handle, 2);
                auto *dropSlot = builder.CreateGEP(builder.getPtrTy(), table,
                                                   builder.getInt32(3));
                auto *drop = builder.CreateLoad(builder.getPtrTy(), dropSlot);
                auto *kind = builder.CreateLoad(
                    builder.getPtrTy(),
                    builder.CreateGEP(builder.getPtrTy(), table,
                                      builder.getInt32(0)));
                auto *count = builder.CreateSelect(
                    builder.CreateICmpNE(kind, llvm::ConstantPointerNull::get(
                                                   builder.getPtrTy())),
                    builder.CreateExtractValue(handle, 1), builder.getInt64(1));
                auto *signature = llvm::FunctionType::get(
                    builder.getVoidTy(),
                    {builder.getPtrTy(), builder.getInt64Ty()}, false);
                auto *function = builder.GetInsertBlock()->getParent();
                auto *callDrop =
                    llvm::BasicBlock::Create(context, "drop.erased", function);
                auto *done = llvm::BasicBlock::Create(
                    context, "drop.erased.done", function);
                builder.CreateCondBr(
                    builder.CreateICmpNE(drop, llvm::ConstantPointerNull::get(
                                                   builder.getPtrTy())),
                    callDrop, done);
                builder.SetInsertPoint(callDrop);
                builder.CreateCall(signature, drop, {data, count});
                builder.CreateBr(done);
                builder.SetInsertPoint(done);
              }
            } else
              frame.dropPlace(n.place);
          } else
            frame.dropPlace(n.place);
          if (debugInfo && n.place.root >= 0 &&
              static_cast<std::size_t>(n.place.root) < source.locals.size())
            debugInfo->invalidate(builder,
                                  static_cast<std::size_t>(n.place.root),
                                  n.span, n.scope);
          break;
        }
        case ir::Op::ScopeExit:
          frame.scopeExit(n.number);
          if (debugInfo)
            debugInfo->endScope(builder, source, n.number, n.span);
          break;
        case ir::Op::Unary:
          result =
              n.text == "!" ? builder.CreateNot(get(0))
              : isFloating(n.result.type)
                  ? builder.CreateFNeg(get(0))
                  : binary("-", llvm::Constant::getNullValue(get(0)->getType()),
                           get(0), n.result.type);
          break;
        case ir::Op::Binary:
          result = binary(n.text, get(0), get(1), n.operands[0].type);
          break;
        case ir::Op::Call:
        case ir::Op::IndirectCall:
        case ir::Op::CatchCall: {
          std::vector<llvm::Value *> arguments;
          for (auto value : n.operands) {
            arguments.push_back(values[value.id]);
            frame.consume(value);
          }
          if (n.erasedDispatch &&
              !pinnedErasedReceiver(*program.types, n.operands[0].type)) {
            auto *handle =
                builder.CreateLoad(type(n.operands[0].type), arguments[0]);
            auto *data = builder.CreateExtractValue(handle, 0);
            auto *count = builder.CreateExtractValue(handle, 1);
            auto *table = builder.CreateExtractValue(handle, 2);
            auto *kind = builder.CreateLoad(builder.getPtrTy(), table);
            auto *fatType = llvm::StructType::get(
                context, {builder.getPtrTy(), builder.getInt64Ty()});
            llvm::Value *fat = llvm::UndefValue::get(fatType);
            fat = builder.CreateInsertValue(fat, data, 0);
            fat = builder.CreateInsertValue(fat, count, 1);
            auto *stored = lowering.temporary(fatType);
            builder.CreateStore(fat, stored);
            arguments[0] = builder.CreateSelect(
                builder.CreateICmpNE(
                    kind, llvm::ConstantPointerNull::get(builder.getPtrTy())),
                stored, data);
          }
          if (n.op == ir::Op::CatchCall) {
            std::vector<llvm::Type *> members;
            for (auto *argument : arguments)
              members.push_back(argument->getType());
            auto *contextType = llvm::StructType::get(context, members);
            auto *callback = lowering.callback("mettle.catch");
            targetAttributes(*callback, program.target,
                             program.functions[n.callee].targetFeatures);
            auto saved = builder.saveIP();
            builder.SetInsertPoint(
                llvm::BasicBlock::Create(context, "entry", callback));
            std::vector<llvm::Value *> loaded;
            for (unsigned i = 0; i < members.size(); ++i)
              loaded.push_back(builder.CreateLoad(
                  members[i], builder.CreateStructGEP(contextType,
                                                      callback->getArg(0), i)));
            if (lowering.indirect(program.functions[n.callee].result))
              loaded.push_back(
                  lowering.temporary(program.functions[n.callee].result));
            builder.CreateCall(functions[n.callee], loaded);
            builder.CreateRetVoid();
            builder.restoreIP(saved);
            // Catch returns before this callback stack is unwound, so this
            // context need not escape into the function's outer cleanup frame.
            llvm::IRBuilder<> entryBuilder(&target->getEntryBlock(),
                                           target->getEntryBlock().begin());
            auto *callContext = entryBuilder.CreateAlloca(contextType);
            for (unsigned i = 0; i < arguments.size(); ++i)
              builder.CreateStore(
                  arguments[i],
                  builder.CreateStructGEP(contextType, callContext, i));
            result = builder.CreateCall(
                lowering.runtime("mettle_rt_catch", builder.getInt32Ty(),
                                 {builder.getPtrTy(), builder.getPtrTy()}),
                {callContext, callback});
          } else {
            auto *target =
                n.op == ir::Op::IndirectCall ? values[n.target.id] : nullptr;
            if (n.op == ir::Op::IndirectCall &&
                n.target.access != ir::Access::Owned)
              target = builder.CreateLoad(type(n.target.type), target);
            resultDestination = directDestination(source.blocks[b], position);
            result = call(n, target, arguments, source.targetFeatures);
            resultDestination = nullptr;
          }
          break;
        }
        case ir::Op::Phi: {
          result = values[n.result.id];
          break;
        }
        case ir::Op::Construct:
          if (program.types->isOpaque(n.result.type)) {
            result = get(0);
            frame.consume(n.operands[0]);
            break;
          }
          {
            std::vector<llvm::Value *> fields;
            for (std::size_t i = 0; i < n.operands.size(); ++i) {
              fields.push_back(get(i));
              frame.consume(n.operands[i]);
            }
            result = lowering.construct(n.result.type, fields, n.number);
          }
          break;
        case ir::Op::VariantConstruct: {
          std::vector<llvm::Value *> fields;
          for (std::size_t i = 0; i < n.operands.size(); ++i) {
            fields.push_back(get(i));
            frame.consume(n.operands[i]);
          }
          result = lowering.variant(n.result.type, n.number, fields);
          break;
        }
        case ir::Op::VariantTest: {
          auto sumType = *projectedType(
              *program.types, source.locals[n.place.root].type, n.place.fields);
          auto *tag = lowering.enumTag(sumType, address(n.place));
          result = builder.CreateICmpEQ(tag, builder.getInt32(n.number));
          break;
        }
        case ir::Op::Panic:
          emitPanic(n.number);
          break;
        case ir::Op::Project:
          result = lowering.extract(get(0), n.operands[0].type, n.number);
          break;
        }
        frame.remember(n.result, result);
        values[n.result.id] = result;
        if (source.coroutine && n.result.id >= 0 && frame.spilled(n.result.id))
          lowering.store(n.result.type, result, frame.spillAddress(n.result.id),
                         llvm::Align(lowering.alignment(n.result.type)));
      }
      const auto &exit = source.blocks[b].exit;
      if (source.coroutine)
        for (int successor : {exit.first, exit.second})
          if (successor >= 0)
            for (const auto &n : source.blocks[successor].instructions)
              if (n.op == ir::Op::Phi)
                for (std::size_t i = 0; i < n.operands.size(); ++i)
                  if (n.predecessors[i] == static_cast<int>(b))
                    incoming[{static_cast<int>(b), n.operands[i].id}] =
                        values[n.operands[i].id];
      if (debugInfo)
        debugInfo->locate(builder, exit.span, 0);
      switch (exit.kind) {
      case ir::Exit::Jump:
        builder.CreateBr(blocks[exit.first]);
        break;
      case ir::Exit::Branch:
        builder.CreateCondBr(values[exit.value.id], blocks[exit.first],
                             blocks[exit.second]);
        break;
      case ir::Exit::Suspend:
        resumes.push_back(exit.first);
        builder.CreateStore(builder.getInt32(static_cast<int>(resumes.size())),
                            frame.stateAddress());
        builder.CreateRetVoid();
        break;
      case ir::Exit::Return:
        if (source.coroutine)
          builder.CreateStore(builder.getInt32(CleanupFrame::complete),
                              frame.stateAddress());
        frame.returnValue(exit.value, source.result == Type::Unit ||
                                              source.result == Type::Never
                                          ? nullptr
                                          : values[exit.value.id]);
        break;
      case ir::Exit::Unreachable:
        builder.CreateUnreachable();
        break;
      case ir::Exit::None:
        llvm_unreachable("unterminated compiler CFG");
      }
      ends[b] = builder.GetInsertBlock();
    }
    std::map<std::pair<int, int>, llvm::BasicBlock *> transfers;
    for (std::size_t b = 0; b < source.blocks.size(); ++b)
      for (const auto &n : source.blocks[b].instructions)
        if (n.op == ir::Op::Phi && program.types->needsDrop(n.result.type))
          for (std::size_t i = 0; i < n.predecessors.size(); ++i) {
            int predecessor = n.predecessors[i];
            auto key = std::pair(predecessor, static_cast<int>(b));
            auto [entry, inserted] = transfers.try_emplace(key, nullptr);
            if (inserted) {
              auto *edge =
                  llvm::BasicBlock::Create(context, "transfer", target);
              entry->second = edge;
              auto *terminator = ends[predecessor]->getTerminator();
              for (unsigned s = 0; s < terminator->getNumSuccessors(); ++s)
                if (terminator->getSuccessor(s) == blocks[b])
                  terminator->setSuccessor(s, edge);
              builder.SetInsertPoint(edge);
              builder.CreateBr(blocks[b]);
            }
            builder.SetInsertPoint(entry->second->getTerminator());
            frame.consume(n.operands[i]);
          }
    for (auto &p : pending)
      for (std::size_t i = 0; i < p.instruction->operands.size(); ++i) {
        int predecessor = p.instruction->predecessors[i];
        auto transfer = transfers.find({predecessor, p.block});
        auto id = p.instruction->operands[i].id;
        auto value = incoming.find({predecessor, id});
        p.phi->addIncoming(value == incoming.end() ? values[id] : value->second,
                           transfer == transfers.end() ? ends[predecessor]
                                                       : transfer->second);
      }
    if (dispatch)
      coroutineDispatch(frame, dispatch, blocks, resumes);
  }
  // Entry of a coroutine body: continue at the recorded suspension point and
  // mark the state running, so a panic or a poll after completion is caught.
  void coroutineDispatch(CleanupFrame &frame, llvm::BasicBlock *dispatch,
                         const std::vector<llvm::BasicBlock *> &blocks,
                         const std::vector<int> &resumes) {
    auto *invalid = llvm::BasicBlock::Create(context, "resumed.invalid",
                                             dispatch->getParent());
    builder.SetInsertPoint(dispatch);
    auto *state =
        builder.CreateLoad(builder.getInt32Ty(), frame.stateAddress());
    builder.CreateStore(builder.getInt32(CleanupFrame::running),
                        frame.stateAddress());
    auto *select = builder.CreateSwitch(state, invalid, resumes.size() + 1);
    select->addCase(builder.getInt32(0), blocks[0]);
    for (std::size_t i = 0; i < resumes.size(); ++i)
      select->addCase(builder.getInt32(static_cast<int>(i + 1)),
                      blocks[resumes[i]]);
    builder.SetInsertPoint(invalid);
    if (lowering.freestanding)
      builder.CreateCall(llvm::Intrinsic::getOrInsertDeclaration(
          module.get(), llvm::Intrinsic::trap));
    else {
      static const std::string message =
          "async future polled after completion or panic";
      auto function =
          lowering.runtime("mettle_rt_panic_message", builder.getVoidTy(),
                           {builder.getPtrTy(), builder.getInt64Ty()});
      llvm::cast<llvm::Function>(function.getCallee())
          ->addFnAttr(llvm::Attribute::NoReturn);
      builder.CreateCall(
          function, {textGlobal(message), builder.getInt64(message.size())});
    }
    builder.CreateUnreachable();
  }
};
} // namespace

std::unique_ptr<llvm::Module> lower(const ir::VerifiedProgram &program,
                                    llvm::LLVMContext &context, bool checked,
                                    llvm::StringRef target, bool freestanding,
                                    const DebugInfoRequest *debug,
                                    bool sanitizeAddress, bool sanitizeThread,
                                    CodegenPartition partition) {
  auto selected = program.program().target.triple.empty()
                      ? target
                      : llvm::StringRef(program.program().target.triple);
  Lowerer lowerer(program.program(), context, selected, freestanding, debug,
                  sanitizeAddress, sanitizeThread, std::move(partition));
  lowerer.checked = checked;
  return lowerer.run();
}
} // namespace mettle::backend
