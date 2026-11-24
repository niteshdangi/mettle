#include "pipeline/compile.h"
#include "analysis/initialization.h"
#include "analysis/loans.h"
#include "cleanup/plan.h"
#include "instances/specialize.h"
#include "ir/verify.h"
#include "lowering/scalar.h"
#include "resolution/load.h"
#include "resolution/resolve.h"
#include "semantics/check.h"
#include "semantics/interfaces.h"
#include "syntax/parser.h"
#include "types/project.h"
#include <map>
#include <set>
#include <tuple>

mettle::ir::VerifiedProgram::VerifiedProgram(
    Program program, std::unique_ptr<const std::vector<cleanup::Plan>> plans)
    : value(std::move(program)), plans(std::move(plans)) {}
mettle::ir::VerifiedProgram::VerifiedProgram(VerifiedProgram &&) noexcept =
    default;
mettle::ir::VerifiedProgram &
mettle::ir::VerifiedProgram::operator=(VerifiedProgram &&) noexcept = default;
mettle::ir::VerifiedProgram::~VerifiedProgram() = default;

namespace mettle::pipeline {
static std::function<std::optional<ir::Function>(std::size_t)>
bodyLoader(const ir::Program &program, const lowering::ImportedBodies *bodies,
           Diagnostics &diagnostics) {
  if (!bodies || !bodies->loadFunction)
    return {};
  return [&program, bodies,
          &diagnostics](std::size_t f) -> std::optional<ir::Function> {
    std::string error;
    const auto &header = program.functions[f];
    auto body =
        bodies->loadFunction(*program.lazyFunctionRecords[f], header, error);
    if (!body)
      diagnostics.error("metadata", header.span,
                        error.empty() ? "compiled library body failed to load"
                                      : error);
    return body;
  };
}
analysis::EffectSummaries::Loader
effectsLoader(const ir::Program &program,
              const lowering::ImportedBodies *bodies,
              Diagnostics &diagnostics) {
  if (!bodies || !bodies->loadSummary)
    return {};
  return [&program, bodies, &diagnostics](
             std::size_t f) -> std::optional<analysis::FunctionEffects> {
    if (f >= program.lazyFunctionRecords.size() ||
        !program.lazyFunctionRecords[f])
      return std::nullopt;
    std::string error;
    auto bytes = bodies->loadSummary(*program.lazyFunctionRecords[f], error);
    if (bytes.empty()) {
      if (!error.empty())
        diagnostics.error("metadata", program.functions[f].span, error);
      return std::nullopt;
    }
    auto effects = analysis::decodeEffects(bytes, bodies->summaryReferences);
    if (!effects)
      diagnostics.error("metadata", program.functions[f].span,
                        "compiled library effect summary is invalid");
    return effects;
  };
}
class Compiler {
public:
  static bool mergeImportedMetadata(ir::Program &program,
                                    const ir::Program &metadata,
                                    Diagnostics &diagnostics) {
    auto fail = [&](const char *message) {
      diagnostics.error("metadata", {}, message);
      return false;
    };
    if (!metadata.functions.empty() || !metadata.statics.empty() ||
        !metadata.closureFunctions.empty())
      return fail("imported metadata contains unplaced definitions");
    const auto &target = program.target;
    const auto &other = metadata.target;
    if (target.arch != other.arch || target.system != other.system ||
        target.pointerBits != other.pointerBits ||
        target.littleEndian != other.littleEndian ||
        target.triple != other.triple || target.baseline != other.baseline)
      return fail("imported library target facts do not match the consumer");
    std::map<std::tuple<Type, Type, int, std::vector<Type>>, int> adapters;
    for (const auto &adapter : program.opaqueAdapters)
      adapters.emplace(std::tuple{adapter.self, adapter.interfaceType,
                                  adapter.method, adapter.methodArguments},
                       adapter.function);
    for (const auto &adapter : metadata.opaqueAdapters) {
      auto [found, inserted] =
          adapters.emplace(std::tuple{adapter.self, adapter.interfaceType,
                                      adapter.method, adapter.methodArguments},
                           adapter.function);
      if (!inserted && found->second != adapter.function)
        return fail("conflicting imported interface adapter definitions");
      if (inserted)
        program.opaqueAdapters.push_back(adapter);
    }
    auto mergeFunctions = [&](auto &destination, const auto &source) {
      std::map<Type, int> functions(destination.begin(), destination.end());
      for (auto [type, function] : source) {
        auto [found, inserted] = functions.emplace(type, function);
        if (!inserted && found->second != function)
          return false;
        if (inserted)
          destination.emplace_back(type, function);
      }
      return true;
    };
    if (!mergeFunctions(program.coroutines, metadata.coroutines) ||
        !mergeFunctions(program.dynamicDropFunctions,
                        metadata.dynamicDropFunctions))
      return fail("conflicting imported coroutine or dynamic-drop definitions");
    program.globalAssembly.insert(program.globalAssembly.begin(),
                                  metadata.globalAssembly.begin(),
                                  metadata.globalAssembly.end());
    program.libraries.insert(program.libraries.begin(),
                             metadata.libraries.begin(),
                             metadata.libraries.end());
    return true;
  }
  static bool proveUnpin(TypeStore &store, const interfaces::Database &database,
                         Diagnostics &diagnostics, Type subject, Type runtime,
                         const ir::Function &function, Span span) {
    std::vector<interfaces::Obligation> assumptions;
    for (auto [type, bound] : function.interfaceBounds)
      assumptions.push_back({type, bound});
    for (auto type : function.unpinBounds)
      assumptions.push_back({type, Type::Unknown, interfaces::Property::Unpin});
    for (auto type : function.sizedBounds)
      assumptions.push_back({type, Type::Unknown, interfaces::Property::Sized});
    RegionEnvironment regions;
    if (store.isFunctionPointer(function.regionSignature)) {
      const auto &signature = store.callable(function.regionSignature);
      regions.universe = signature.regionUniverse;
      regions.assumptions = signature.regionRequirements;
    }
    interfaces::Solver solver(store, database, diagnostics, assumptions,
                              regions);
    interfaces::Solver runtimeTypes(store, database, diagnostics,
                                    std::move(assumptions), std::move(regions),
                                    true);
    solver.setEqualities(function.genericEqualities);
    runtimeTypes.setEqualities(function.genericEqualities);
    subject = solver.normalize(subject, function.genericEqualities, span);
    return solver.prove({subject, Type::Unknown, interfaces::Property::Unpin},
                        span, false) &&
           store.eraseRegions(runtimeTypes.normalize(
               subject, function.genericEqualities, span)) == runtime;
  }
  static std::optional<ir::VerifiedProgram>
  admit(ir::Program program, Diagnostics &diagnostics,
        const ir::UnpinProof &proof = {}, const ir::Program *prepared = nullptr,
        const analysis::LoanResults *previousLoans = nullptr) {
    if (!diagnostics.empty())
      return std::nullopt;
    if (!program.types) {
      ir::verify(program, diagnostics);
      return std::nullopt;
    }
    for (const auto &function : program.functions) {
      bool concrete = function.genericParameters.empty() &&
                      !function.declarationOnly &&
                      !program.types->isSymbolic(function.result);
      for (const auto &local : function.locals)
        concrete &= !program.types->isSymbolic(local.type);
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions) {
          concrete &= !program.types->isSymbolic(instruction.result.type);
          if (instruction.op == ir::Op::ArrayRepeat)
            concrete &= program.types->compactArray(instruction.result.type);
          if (instruction.op == ir::Op::ArrayTake &&
              program.types->needsDrop(instruction.result.type))
            diagnostics.error("feature", instruction.span,
                              "by-value iteration over a large array of "
                              "droppable elements is not implemented");
        }
      if (!concrete)
        diagnostics.error(
            "internal", {},
            "uninstantiated declaration reached executable admission");
    }
    if (!diagnostics.empty() || !ir::verify(program, diagnostics, {}, proof))
      return std::nullopt;
    auto plans =
        std::make_unique<std::vector<cleanup::Plan>>(program.functions.size());
    for (std::size_t i = 0; i < program.functions.size(); ++i) {
      const auto &function = program.functions[i];
      if (function.blocks.empty())
        continue;
      try {
        (*plans)[i] = cleanup::plan(function, *program.types);
      } catch (const std::length_error &error) {
        auto local = function.parameters < function.locals.size()
                         ? function.parameters
                         : std::size_t{0};
        diagnostics.error("limit",
                          function.locals.empty() ? Span{}
                                                  : function.locals[local].span,
                          error.what());
      }
    }
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::initialization(program, diagnostics, prepared);
    if (!diagnostics.empty())
      return std::nullopt;
    analysis::loans(program, diagnostics, prepared, previousLoans);
    if (!diagnostics.empty())
      return std::nullopt;
    return ir::VerifiedProgram(std::move(program), std::move(plans));
  }
  static std::optional<PreparedProgram>
  prepare(Module tree, Diagnostics &diagnostics, bool requireEntry = true,
          TargetFacts target = {}, const CheckedObserver &observe = {},
          const PackageOwners &packageOwners = {},
          NumericEvaluator numericEvaluator = nullptr,
          const resolution::SourcePackages &sourcePackages = {},
          const LibraryImporter &importLibrary = {},
          FunctionQueries *queries = nullptr) {
    if (!diagnostics.empty())
      return std::nullopt;
    auto resolved = resolution::resolve(tree, diagnostics, sourcePackages);
    if (!resolved)
      return std::nullopt;
    std::optional<ImportedProgram> library;
    std::shared_ptr<const ImportedDeclarations> imported;
    if (importLibrary) {
      library = importLibrary(tree, *resolved, diagnostics);
      if (!library || !diagnostics.empty()) {
        if (diagnostics.empty())
          diagnostics.error("metadata", {}, "compiled library import failed");
        return std::nullopt;
      }
      imported = library->declarations;
    }
    std::optional<FunctionQueries::State> nextQueries;
    bool retainedInstanceQueries = false;
    const std::map<std::size_t, ir::Function> *reusedBodies = nullptr;
    const auto native = imported;
    bool queryable = queries && !observe && tree.globalAssembly.empty();
    if (queryable) {
      nextQueries.emplace();
      nextQueries->inputs = declarationQueryInputs(tree, native.get());
      if (!nextQueries->inputs.error.empty()) {
        diagnostics.error("internal", {},
                          "cannot identify declaration queries: " +
                              nextQueries->inputs.error);
        return std::nullopt;
      }
      nextQueries->native = native;
      nextQueries->target = target;
      nextQueries->numericEvaluator = numericEvaluator;
      nextQueries->requireEntry = requireEntry;
      nextQueries->packages = sourcePackages;
      nextQueries->instances = std::make_shared<instances::Queries>(
          native ? native->types : nullptr, tree.functions.size(),
          tree.statics.size());
      const auto &previous = queries->state;
      auto targetIdentity = [](const TargetFacts &value) {
        return std::tie(value.arch, value.system, value.pointerBits,
                        value.littleEndian, value.triple, value.baseline);
      };
      if (previous && previous->native == native &&
          previous->numericEvaluator == numericEvaluator &&
          previous->inputs.context == nextQueries->inputs.context &&
          previous->packages == sourcePackages &&
          previous->requireEntry == requireEntry &&
          targetIdentity(previous->target) == targetIdentity(target)) {
        nextQueries->typeVerification = previous->typeVerification;
        std::vector<std::uint8_t> invalid(tree.functions.size());
        std::vector<std::vector<std::size_t>> callers(tree.functions.size());
        std::vector<std::size_t> changed;
        for (const auto &[index, body] : nextQueries->inputs.bodies) {
          auto old = previous->inputs.bodies.find(index);
          if (old == previous->inputs.bodies.end() || old->second != body ||
              !previous->functions.contains(index)) {
            invalid[index] = true;
            changed.push_back(index);
          }
        }
        for (const auto &[caller, dependencies] : previous->dependencies)
          for (auto dependency : dependencies)
            if (dependency < callers.size())
              callers[dependency].push_back(caller);
        auto fixedCallContract = [&](std::size_t index) {
          const auto &function = tree.functions[index];
          const auto &result = function.annotation;
          return function.parameters.empty() &&
                 function.genericParameters.empty() &&
                 function.regions.empty() && function.error.empty() &&
                 !function.asynchronous && result.form == TypeForm::Named &&
                 result.view.empty() && !result.nested &&
                 result.arguments.empty() && result.binders.empty() &&
                 builtinType(result.name) != Type::Unknown;
        };
        for (std::size_t i = 0; i < changed.size(); ++i) {
          // These bodies cannot change any type or flow exposed to callers.
          if (previous->functions.contains(changed[i]) &&
              fixedCallContract(changed[i]))
            continue;
          for (auto caller : callers[changed[i]])
            if (!invalid[caller]) {
              invalid[caller] = true;
              changed.push_back(caller);
            }
        }
        if (previous->instances) {
          nextQueries->instances =
              std::make_shared<instances::Queries>(*previous->instances);
          nextQueries->instances->invalidate(invalid);
          retainedInstanceQueries = true;
        }
        auto reused = std::count_if(
            previous->functions.begin(), previous->functions.end(),
            [&](const auto &entry) { return !invalid[entry.first]; });
        if (reused) {
          auto declarations =
              std::make_shared<ImportedDeclarations>(*previous->declarations);
          for (const auto &[index, function] : previous->functions) {
            (void)function;
            if (invalid[index]) {
              declarations->functions.erase(static_cast<std::uint32_t>(index));
              continue;
            }
            tree.functions.edit(index).body = {};
            nextQueries->dependencies.emplace(index,
                                              previous->dependencies.at(index));
          }
          imported = std::move(declarations);
          reusedBodies = &previous->functions;
          queries->reused += reused;
        }
      }
    }
    auto checked =
        check(std::move(tree), diagnostics, std::move(resolved), requireEntry,
              std::move(target), numericEvaluator, std::move(imported));
    if (!checked)
      return std::nullopt;
    if (observe)
      observe(*checked);
    auto program =
        lowering::lower(*checked, diagnostics,
                        library ? library->bodies : nullptr, reusedBodies);
    if (!diagnostics.empty())
      return std::nullopt;
    if (nextQueries) {
      {
        TypeProjection projection(*program.types,
                                  native ? native->types.get() : nullptr);
        std::map<Type, bool> reusableTypes;
        std::function<bool(Type)> reusableType = [&](Type type) {
          const auto &types = *program.types;
          std::vector<Type> pending{type};
          std::set<Type> visited;
          for (std::size_t i = 0; i < pending.size(); ++i) {
            auto current = pending[i];
            if (current.index() < builtinTypeCount ||
                (native && native->types && native->types->contains(current)) ||
                !visited.insert(current).second)
              continue;
            if (auto known = reusableTypes.find(current);
                known != reusableTypes.end()) {
              if (!known->second)
                return reusableTypes[type] = false;
              continue;
            }
            if (types.isErased(current) || types.isProjection(current) ||
                (types.isProduct(current) &&
                 types.product(current).callable >= 0))
              return reusableTypes[type] = false;
            auto children = types.referencedTypes(current);
            pending.insert(pending.end(), children.begin(), children.end());
          }
          for (auto current : visited)
            reusableTypes[current] = true;
          return true;
        };
        auto stableSymbol = [&](int symbol, bool function) {
          return symbol < 0 ||
                 static_cast<std::size_t>(symbol) <
                     (function ? checked->syntax().functions.size()
                               : checked->syntax().statics.size());
        };
        std::vector<std::size_t> retained;
        for (const auto &[index, body] : nextQueries->inputs.bodies) {
          (void)body;
          auto function = program.functions.at(index);
          const auto &syntax = checked->syntax().functions[index];
          bool cacheable =
              syntax.interfaceOwner.empty() && syntax.implementation < 0;
          for (const auto &local : function.locals)
            if (local.storage == StorageDuration::Static)
              cacheable &= stableSymbol(local.staticIndex, false);
          auto assembly = [&](const Assembly &value) {
            for (const auto &operand : value.operands)
              if (operand.mode == AssemblyMode::Sym)
                cacheable &= stableSymbol(
                    operand.symbol, operand.symbolKind ==
                                        AssemblyOperand::SymbolKind::Function);
          };
          if (function.nakedAssembly)
            assembly(*function.nakedAssembly);
          for (auto &block : function.blocks)
            for (auto &instruction : block.instructions) {
              if (instruction.op == ir::Op::IndirectCall) {
                instruction.callee = -1;
                instruction.typeArguments.clear();
              }
              cacheable &= stableSymbol(instruction.callee, true) &&
                           stableSymbol(instruction.dropFunction, true);
              if (instruction.assembly)
                assembly(*instruction.assembly);
            }
          ir::remapTypes(function, [&](Type type) {
            cacheable &= reusableType(type);
            return type;
          });
          if (!cacheable)
            continue;
          retained.push_back(index);
          ir::remapTypes(function,
                         [&](Type type) { return projection.type(type); });
          nextQueries->functions.emplace(index, std::move(function));
        }
        auto dependencies = [&](std::size_t caller,
                                const ir::Function &function) {
          auto &result = nextQueries->dependencies[caller];
          const auto &semantic = checked->dependencies(caller);
          result.insert(result.end(), semantic.begin(), semantic.end());
          auto assembly = [&](const Assembly &value) {
            for (const auto &operand : value.operands)
              if (operand.mode == AssemblyMode::Sym &&
                  operand.symbolKind == AssemblyOperand::SymbolKind::Function &&
                  operand.symbol >= 0)
                result.push_back(static_cast<std::size_t>(operand.symbol));
          };
          if (function.nakedAssembly)
            assembly(*function.nakedAssembly);
          for (const auto &block : function.blocks)
            for (const auto &instruction : block.instructions) {
              for (auto callee : {instruction.callee, instruction.dropFunction})
                if (callee >= 0)
                  result.push_back(static_cast<std::size_t>(callee));
              if (instruction.assembly)
                assembly(*instruction.assembly);
            }
          std::sort(result.begin(), result.end());
          result.erase(std::unique(result.begin(), result.end()), result.end());
        };
        const auto count = checked->syntax().functions.size();
        for (std::size_t i = 0; i < count; ++i)
          if (!native || !native->functions.contains(i))
            dependencies(i, program.functions.at(i));
        std::size_t helper = count + checked->nativeDefaultCount();
        for (std::size_t i = checked->syntax().functions.nativeSize();
             i < count; ++i)
          for (std::size_t p = 0;
               p < checked->syntax().functions.header(i).parameters.size(); ++p)
            if (checked->hasDefault(i, p)) {
              if (!native || !native->functions.contains(i))
                dependencies(i, program.functions.at(helper));
              ++helper;
            }
        std::vector<std::vector<std::size_t>> callers(count);
        std::vector<std::size_t> unsupported;
        for (const auto &[caller, dependencies] : nextQueries->dependencies) {
          if (!nextQueries->functions.contains(caller))
            continue;
          for (auto dependency : dependencies)
            if (dependency < count &&
                (!native || !native->functions.contains(dependency))) {
              callers[dependency].push_back(caller);
              if (!nextQueries->functions.contains(dependency))
                unsupported.push_back(caller);
            }
        }
        for (std::size_t i = 0; i < unsupported.size(); ++i)
          if (nextQueries->functions.erase(unsupported[i]))
            unsupported.insert(unsupported.end(),
                               callers[unsupported[i]].begin(),
                               callers[unsupported[i]].end());
        retained.clear();
        for (const auto &[index, function] : nextQueries->functions) {
          (void)function;
          retained.push_back(index);
        }
        nextQueries->declarations = retainQueryDeclarations(
            *checked, native.get(), retained, projection, reusableType);
      }
    }
    program.requireEntry = requireEntry;
    if (library && library->metadata &&
        !mergeImportedMetadata(program, *library->metadata, diagnostics))
      return std::nullopt;
    auto types = std::make_shared<TypeStore>(*program.types);
    program.types = types;
    auto database = checked->interfaceStore();
    auto declarationProof = [&](Type subject, Type runtime,
                                const ir::Function &function, Span span) {
      return proveUnpin(*types, *database, diagnostics, subject, runtime,
                        function, span);
    };
    program.functionPackages.resize(program.functions.size());
    if (!packageOwners.empty())
      for (std::size_t i = 0; i < checked->syntax().functions.size() &&
                              i < program.functionPackages.size();
           ++i) {
        auto source =
            native && native->catalog && checked->syntax().functions.native(i)
                ? native->catalog->symbolSpan(metadata::SymbolKind::Function, i)
                      .value()
                      .source
                : checked->syntax().functions.header(i).span.source;
        if (auto owner = packageOwners.find(source);
            owner != packageOwners.end())
          program.functionPackages[i] = owner->second;
      }
    program.staticPackages.resize(program.statics.size());
    for (std::size_t i = 0; i < checked->syntax().statics.size() &&
                            i < program.staticPackages.size();
         ++i) {
      auto source = program.statics[i].span.source;
      if (auto owner = packageOwners.find(source); owner != packageOwners.end())
        program.staticPackages[i] = owner->second;
    }
    lowering::opaqueAdapters(program, *types, checked->interfaceDatabase(),
                             diagnostics);
    lowering::erasedAdapters(program, *types, checked->interfaceDatabase());
    program.functionPackages.resize(program.functions.size());
    // Declaration-only normalization of a type is fixed per function.
    std::map<std::pair<const ir::Function *, Type>, Type> declared;
    auto normalize = [&](Type type, std::span<const TypeBinding> bindings,
                         const ir::Function &function) {
      if (bindings.empty())
        if (auto known = declared.find({&function, type});
            known != declared.end())
          return known->second;
      std::vector<interfaces::Obligation> assumptions;
      for (auto [subject, interface] : function.interfaceBounds)
        assumptions.push_back({subject, interface});
      interfaces::Solver declarations(*types, checked->interfaceDatabase(),
                                      diagnostics, std::move(assumptions), {},
                                      true);
      std::vector<TypeBinding> substitutions(bindings.begin(), bindings.end());
      substitutions.insert(substitutions.end(),
                           function.genericEqualities.begin(),
                           function.genericEqualities.end());
      auto normalized =
          types->eraseRegions(declarations.normalize(type, substitutions, {}));
      if (bindings.empty())
        declared.emplace(std::pair{&function, type}, normalized);
      return normalized;
    };
    // Bodies imported unchanged from the checked library were verified and
    // analysed when the library was built.
    program.libraryBodies.resize(program.functions.size());
    const auto trusted = program.libraryBodies;
    for (std::size_t i = 0; i < program.functions.size(); ++i) {
      if (trusted[i])
        continue;
      auto &function = program.functions.edit(i);
      auto valueType = [&](ir::Value &value) {
        value.type = normalize(value.type, {}, function);
      };
      function.result = normalize(function.result, {}, function);
      for (auto &local : function.locals)
        local.type = normalize(local.type, {}, function);
      for (auto &block : function.blocks) {
        for (auto &instruction : block.instructions) {
          valueType(instruction.result);
          for (auto &operand : instruction.operands)
            valueType(operand);
          valueType(instruction.target);
          instruction.indirectType =
              normalize(instruction.indirectType, {}, function);
          instruction.interfaceSelf =
              normalize(instruction.interfaceSelf, {}, function);
          instruction.interfaceType =
              normalize(instruction.interfaceType, {}, function);
          instruction.opaqueType =
              normalize(instruction.opaqueType, {}, function);
          // An aggregate constant keeps its projection: instantiation calls
          // the implementation's initializer.
          if (auto constant =
                  normalize(instruction.constantParameter, {}, function);
              !types->isConstant(constant) ||
              !types->isProduct(types->parameter(constant).valueType))
            instruction.constantParameter = constant;
          for (auto &argument : instruction.typeArguments)
            argument = normalize(argument, {}, function);
          for (auto &[subject, runtime] : instruction.unpinProofs)
            runtime = normalize(subject, {}, function);
          for (auto &entry : instruction.witnessEntries)
            entry.owner = normalize(entry.owner, {}, function);
          lowering::witnessSlots(instruction, *types, diagnostics);
          for (auto &projection : instruction.place.fields)
            projection.type = normalize(projection.type, {}, function);
        }
        valueType(block.exit.value);
      }
    }
    if (!diagnostics.empty() ||
        !ir::verify(program, diagnostics, normalize, declarationProof, &trusted,
                    nextQueries ? &nextQueries->typeVerification : nullptr))
      return std::nullopt;
    auto analyzed = trusted;
    // Published queries have passed body analysis under these same
    // dependencies.
    if (reusedBodies)
      for (const auto &[index, function] : *reusedBodies) {
        (void)function;
        if (checked->imported(index))
          analyzed[index] = true;
      }
    analysis::initialization(program, diagnostics, nullptr, &analyzed);
    if (!diagnostics.empty())
      return std::nullopt;
    auto loans = analysis::loans(
        program, diagnostics, nullptr, nullptr, &analyzed,
        bodyLoader(program, library ? library->bodies.get() : nullptr,
                   diagnostics),
        nullptr,
        effectsLoader(program, library ? library->bodies.get() : nullptr,
                      diagnostics));
    if (!diagnostics.empty())
      return std::nullopt;
    auto instanceQueries = nextQueries ? nextQueries->instances : nullptr;
    if (nextQueries) {
      if (!retainedInstanceQueries && queries->state &&
          queries->state->instances)
        queries->specialized += queries->state->instances->hits();
      queries->state = std::move(nextQueries);
    }
    return PreparedProgram(std::move(program), std::move(database),
                           std::move(loans),
                           library ? std::move(library->bodies) : nullptr,
                           std::move(instanceQueries));
  }

  static std::optional<ir::VerifiedProgram>
  specialize(const PreparedProgram &prepared, Diagnostics &diagnostics,
             instances::Scope scope, const ir::Program *consumer = nullptr) {
    if (!diagnostics.empty())
      return std::nullopt;
    auto &program = prepared.declarations;
    const auto &database = *prepared.interfaceData;
    instances::Hooks hooks;
    hooks.validateUnpin = [&](Type subject,
                              std::span<const TypeBinding> bindings,
                              const ir::Function &function, Span span,
                              TypeStore &store, Diagnostics &errors) {
      RegionEnvironment regions;
      if (store.isFunctionPointer(function.regionSignature)) {
        const auto &signature = store.callable(function.regionSignature);
        regions.universe = signature.regionUniverse;
        regions.assumptions = signature.regionRequirements;
      }
      interfaces::Solver solver(store, database, errors, {},
                                std::move(regions));
      auto actual = solver.normalize(subject, bindings, span);
      if (!solver.prove({actual, Type::Unknown, interfaces::Property::Unpin},
                        span, false))
        errors.error("type", span, "generic instance does not satisfy Unpin");
      return actual;
    };
    hooks.normalizeType = [&](Type type, std::span<const TypeBinding> bindings,
                              TypeStore &store, Diagnostics &errors) {
      interfaces::Solver solver(store, database, errors, {}, {}, true);
      return store.eraseRegions(solver.normalize(type, bindings, {}));
    };
    hooks.normalizeRegionSignature =
        [&](Type type, std::span<const TypeBinding> bindings, TypeStore &store,
            Diagnostics &errors) {
          interfaces::Solver solver(store, database, errors);
          return store.declaredRegions(solver.normalize(type, bindings, {}));
        };
    if (prepared.importedBodies && prepared.importedBodies->loadFunction) {
      auto importedBodies = prepared.importedBodies;
      hooks.libraryBodySizes = importedBodies->functionBodySizes;
      hooks.loadLibraryBody = [importedBodies](std::size_t record,
                                               const ir::Function &header,
                                               Diagnostics &errors) {
        std::string error;
        auto function = importedBodies->loadFunction(record, header, error);
        if (!function)
          errors.error("metadata", header.span,
                       error.empty() ? "compiled library body failed to load"
                                     : error);
        return function;
      };
    }
    hooks.aggregateConstant = [&](ir::Instruction &constant, Type projection,
                                  TypeStore &store, Diagnostics &errors) {
      if (!store.isProjection(projection))
        return false;
      const auto &projected = store.parameter(projection);
      interfaces::Solver solver(store, database, errors, {}, {}, true);
      auto selected = solver.constantInitializer(
          store.eraseRegions(
              solver.normalize(projected.operands[0], {}, constant.span)),
          solver.normalize(projected.operands[1], {}, constant.span),
          static_cast<std::size_t>(projected.value), constant.span);
      if (!selected)
        return false;
      constant.op = ir::Op::Call;
      constant.callee = selected->function;
      constant.typeArguments = std::move(selected->arguments);
      return true;
    };
    hooks.selectCall = [&](ir::Instruction &call,
                           std::span<const TypeBinding> bindings,
                           TypeStore &store, Diagnostics &errors) {
      if (call.op == ir::Op::WitnessMethod || call.op == ir::Op::EraseView ||
          call.op == ir::Op::ErasedUpcast) {
        interfaces::Solver solver(store, database, errors, {}, {}, true);
        call.interfaceType =
            solver.normalize(call.interfaceType, bindings, call.span);
        call.interfaceSelf =
            solver.normalize(call.interfaceSelf, bindings, call.span);
        for (auto &entry : call.witnessEntries)
          entry.owner = solver.normalize(entry.owner, bindings, call.span);
        return lowering::witnessSlots(call, store, errors);
      }
      if (call.interfaceMethod < 0)
        return true;
      interfaces::Solver solver(store, database, errors, {}, {}, true);
      // Semantic analysis checks region contracts; concrete implementation
      // selection is by type identity, not by the caller's region identities.
      std::vector<RegionId> checkedRegions;
      solver.collectStaticRegions(&checkedRegions);
      auto self = store.eraseRegions(
          solver.normalize(call.interfaceSelf, bindings, call.span));
      auto interface =
          solver.normalize(call.interfaceType, bindings, call.span);
      const auto &definition =
          database.definitions[store.erased(interface).declaration];
      auto prefix = definition.methods[call.interfaceMethod].implicitParameters;
      std::vector<Type> methodArguments;
      for (std::size_t i = prefix; i < call.typeArguments.size(); ++i)
        methodArguments.push_back(
            solver.normalize(call.typeArguments[i], bindings, call.span));
      if (store.isOpaque(self) || store.isErased(self)) {
        for (const auto &adapter : program.opaqueAdapters) {
          if (adapter.method != call.interfaceMethod ||
              store.erased(adapter.interfaceType).declaration !=
                  store.erased(interface).declaration ||
              adapter.methodArguments.size() != methodArguments.size())
            continue;
          auto substitutions = solver.match(adapter.self, self);
          if (!substitutions)
            continue;
          // Erased dispatch tables may hold one interface at several
          // arguments; associated bindings do not select the method.
          bool valid = !store.isErased(self) ||
                       store.erased(solver.normalize(adapter.interfaceType,
                                                     *substitutions, call.span))
                               .arguments == store.erased(interface).arguments;
          for (std::size_t i = 0; i < methodArguments.size(); ++i) {
            auto pattern = adapter.methodArguments[i];
            if (store.isParameter(pattern))
              substitutions->push_back({pattern, methodArguments[i]});
            else
              valid &= solver.normalize(pattern, *substitutions, call.span) ==
                       methodArguments[i];
          }
          if (!valid)
            continue;
          call.callee = adapter.function;
          call.typeArguments.clear();
          for (auto parameter :
               program.functions[adapter.function].genericParameters)
            call.typeArguments.push_back(
                solver.normalize(parameter, *substitutions, call.span));
          call.interfaceMethod = -1;
          call.interfaceSelf = call.erasedDispatch ? self : Type::Unknown;
          call.interfaceType = call.erasedDispatch ? interface : Type::Unknown;
          return true;
        }
        if (store.isOpaque(self)) {
          errors.error("internal", call.span,
                       "missing opaque interface adapter");
          return false;
        }
      }
      auto selected = solver.method(self, interface, call.interfaceMethod,
                                    methodArguments, call.span);
      if (!selected)
        return false;
      call.callee = selected->function;
      call.typeArguments = std::move(selected->arguments);
      call.interfaceMethod = -1;
      call.interfaceSelf = call.erasedDispatch ? self : Type::Unknown;
      call.interfaceType = call.erasedDispatch ? interface : Type::Unknown;
      return true;
    };
    std::vector<std::size_t> roots;
    if (consumer) {
      std::set<std::string> required;
      for (std::size_t i = 0; i < consumer->functions.size(); ++i)
        if (i < consumer->functionPackages.size() &&
            consumer->functionPackages[i].starts_with("native:"))
          required.insert(consumer->functions[i].name);
      for (std::size_t i = 0; i < program.functions.size() && !required.empty();
           ++i) {
        auto index = program.deferredFunctionIndex(i);
        const auto &name = index ? index->name : program.functions[i].name;
        if (required.erase(name)) {
          if (index ? !index->declarationOnly
                    : !program.functions[i].declarationOnly)
            roots.push_back(i);
        }
      }
      if (!required.empty()) {
        diagnostics.error("metadata", {},
                          "native object refers to an unknown declaration");
        return std::nullopt;
      }
    }
    std::optional<instances::Queries> instanceQueries;
    if (prepared.instances && scope != instances::Scope::Library &&
        scope != instances::Scope::DemandedLibrary)
      instanceQueries = *prepared.instances;
    auto concrete = instances::specialize(
        program, diagnostics, hooks, scope,
        instanceQueries ? &*instanceQueries : nullptr, roots);
    if (!concrete)
      return std::nullopt;
    auto concreteProof = [&](Type subject, Type runtime,
                             const ir::Function &function, Span span) {
      return proveUnpin(*concrete->types, database, diagnostics, subject,
                        runtime, function, span);
    };
    std::vector<std::size_t> unanalyzed;
    for (const auto &source : concrete->program.declarationSources)
      if (source && *source < prepared.loans.analyzed.size() &&
          !prepared.loans.analyzed[*source])
        unanalyzed.push_back(*source);
    std::optional<analysis::LoanResults> extended;
    if (!unanalyzed.empty()) {
      const std::vector<bool> trusted(program.functions.size(), true);
      extended = analysis::loans(
          program, diagnostics, nullptr, &prepared.loans, &trusted,
          bodyLoader(program, prepared.importedBodies.get(), diagnostics),
          &unanalyzed,
          effectsLoader(program, prepared.importedBodies.get(), diagnostics));
      if (!diagnostics.empty())
        return std::nullopt;
    }
    // Specialization extends type identities; remapped destructor IDs do not
    // change initialization or loan facts for otherwise identical functions.
    auto verified =
        admit(std::move(concrete->program), diagnostics, concreteProof,
              &program, extended ? &*extended : &prepared.loans);
    if (verified && instanceQueries)
      *prepared.instances = std::move(*instanceQueries);
    return verified;
  }
};
std::size_t FunctionQueries::specializationHits() const {
  return specialized +
         (state && state->instances ? state->instances->hits() : 0);
}
std::optional<PreparedProgram>
prepare(Module module, Diagnostics &diagnostics, bool requireEntry,
        TargetFacts target, const CheckedObserver &observe,
        const PackageOwners &packageOwners, NumericEvaluator numericEvaluator,
        const resolution::SourcePackages &sourcePackages,
        const LibraryImporter &importLibrary, FunctionQueries *queries) {
  try {
    return Compiler::prepare(std::move(module), diagnostics, requireEntry,
                             std::move(target), observe, packageOwners,
                             numericEvaluator, sourcePackages, importLibrary,
                             queries);
  } catch (const metadata::InvalidMetadata &failure) {
    diagnostics.error("metadata", {}, failure.what());
    return std::nullopt;
  }
}
std::optional<ir::VerifiedProgram> compile(const PreparedProgram &program,
                                           Diagnostics &diagnostics) {
  return Compiler::specialize(program, diagnostics, instances::Scope::Program);
}
std::optional<ir::VerifiedProgram>
compileWithLibraryObjects(const PreparedProgram &program,
                          Diagnostics &diagnostics, bool optimize) {
  return Compiler::specialize(
      program, diagnostics,
      optimize ? instances::Scope::OptimizedProgramWithLibraryObjects
               : instances::Scope::ProgramWithLibraryObjects);
}
std::optional<ir::VerifiedProgram>
compileLibrary(const PreparedProgram &program, Diagnostics &diagnostics) {
  return Compiler::specialize(program, diagnostics, instances::Scope::Library);
}
std::optional<ir::VerifiedProgram>
compileLibrary(const PreparedProgram &program, Diagnostics &diagnostics,
               const ir::Program &consumer) {
  return Compiler::specialize(program, diagnostics,
                              instances::Scope::DemandedLibrary, &consumer);
}
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics) {
  return Compiler::admit(std::move(program), diagnostics);
}
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics) {
  return compile(std::vector<Source>{source}, diagnostics);
}
std::optional<ir::VerifiedProgram> compile(const std::vector<Source> &sources,
                                           Diagnostics &diagnostics,
                                           const resolution::Library &library) {
  resolution::SourcePackages sourcePackages;
  auto tree = resolution::load(sources, diagnostics, library, &sourcePackages);
  if (!tree)
    return std::nullopt;
  return compile(std::move(*tree), diagnostics, true, {}, {}, {}, nullptr,
                 sourcePackages);
}
std::optional<ir::VerifiedProgram>
compile(Module module, Diagnostics &diagnostics, bool requireEntry,
        TargetFacts target, const CheckedObserver &observe,
        const PackageOwners &packageOwners, NumericEvaluator numericEvaluator,
        const resolution::SourcePackages &sourcePackages) {
  auto prepared =
      prepare(std::move(module), diagnostics, requireEntry, std::move(target),
              observe, packageOwners, numericEvaluator, sourcePackages);
  if (!prepared)
    return std::nullopt;
  return compile(std::move(*prepared), diagnostics);
}
} // namespace mettle::pipeline
