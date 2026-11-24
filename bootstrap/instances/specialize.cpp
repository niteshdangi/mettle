#include "instances/specialize.h"
#include "instances/arrays.h"
#include "instances/callables.h"
#include "metadata/references.h"
#include "support/limits.h"
#include "support/path.h"
#include "types/layout.h"
#include <algorithm>
#include <functional>
#include <map>
#include <set>
#include <stdexcept>
#include <unordered_map>

namespace mettle::instances {
namespace {
// A generic body instantiated with the empty type (`Outcome<T, Never>`) keeps
// code that handles a value which cannot exist. Nothing reaches it, so it is
// reduced to inert constants that keep their value ids.
void neutralizeEmptyValues(ir::Function &function) {
  std::set<int> empty;
  auto neutralize = [&](ir::Instruction &instruction) {
    ir::Instruction inert;
    inert.op = ir::Op::Constant;
    inert.result = instruction.result;
    inert.result.type = Type::Bool;
    inert.result.access = ir::Access::Owned;
    inert.span = instruction.span;
    inert.scope = instruction.scope;
    auto inserted = empty.insert(instruction.result.id).second;
    instruction = std::move(inert);
    return inserted;
  };
  auto diverges = [](const ir::Instruction &instruction) {
    return instruction.op == ir::Op::Call ||
           instruction.op == ir::Op::CatchCall ||
           instruction.op == ir::Op::IndirectCall ||
           instruction.op == ir::Op::Panic || instruction.op == ir::Op::Machine;
  };
  bool changed = false;
  for (auto &block : function.blocks) {
    bool cut = false;
    for (auto &instruction : block.instructions) {
      if (!cut && !diverges(instruction) &&
          (instruction.result.type == Type::Never ||
           std::any_of(instruction.operands.begin(), instruction.operands.end(),
                       [](const auto &operand) {
                         return operand.type == Type::Never;
                       })))
        cut = true;
      if (cut && instruction.op != ir::Op::Constant)
        neutralize(instruction);
    }
    if (cut) {
      block.exit = {};
      block.exit.kind = ir::Exit::Unreachable;
      changed = true;
    }
  }
  // A join keeps only the inputs that still reach it.
  auto reaches = [&](int from, std::size_t to) {
    const auto &exit = function.blocks.at(static_cast<std::size_t>(from)).exit;
    return (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Suspend)
               ? exit.first == static_cast<int>(to)
               : exit.kind == ir::Exit::Branch &&
                     (exit.first == static_cast<int>(to) ||
                      exit.second == static_cast<int>(to));
  };
  if (!changed)
    return;
  struct Phi {
    ir::Instruction *instruction;
    std::vector<std::uint8_t> live;
    std::size_t remaining = 0;
  };
  using PhiUse = std::pair<std::size_t, std::size_t>;
  std::vector<Phi> phis;
  std::unordered_map<int, std::vector<ir::Instruction *>> readers;
  std::unordered_map<int, std::vector<PhiUse>> phiReaders;
  std::unordered_map<int, std::vector<std::size_t>> exitReaders;
  std::unordered_map<std::size_t, std::vector<PhiUse>> outgoingPhis;
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    auto &block = function.blocks[b];
    for (auto &instruction : block.instructions) {
      if (instruction.op == ir::Op::Phi) {
        auto index = phis.size();
        Phi phi{&instruction,
                std::vector<std::uint8_t>(instruction.operands.size())};
        for (std::size_t i = 0; i < instruction.operands.size(); ++i)
          if (i < instruction.predecessors.size() &&
              reaches(instruction.predecessors[i], b) &&
              !empty.contains(instruction.operands[i].id)) {
            phi.live[i] = 1;
            ++phi.remaining;
            phiReaders[instruction.operands[i].id].push_back({index, i});
            outgoingPhis[static_cast<std::size_t>(instruction.predecessors[i])]
                .push_back({index, i});
          }
        if (!phi.remaining && !instruction.operands.empty())
          neutralize(instruction);
        phis.push_back(std::move(phi));
      } else if (instruction.op != ir::Op::Constant ||
                 !instruction.operands.empty()) {
        for (const auto &operand : instruction.operands)
          readers[operand.id].push_back(&instruction);
        readers[instruction.target.id].push_back(&instruction);
      }
    }
    if (block.exit.kind != ir::Exit::None &&
        block.exit.kind != ir::Exit::Unreachable)
      exitReaders[block.exit.value.id].push_back(b);
  }
  std::vector<int> pending(empty.begin(), empty.end());
  std::vector<std::size_t> cutBlocks;
  auto removeOperand = [&](PhiUse use) {
    auto &phi = phis[use.first];
    if (!phi.live[use.second])
      return;
    phi.live[use.second] = 0;
    if (!--phi.remaining && neutralize(*phi.instruction))
      pending.push_back(phi.instruction->result.id);
  };
  while (!pending.empty() || !cutBlocks.empty()) {
    if (!cutBlocks.empty()) {
      auto block = cutBlocks.back();
      cutBlocks.pop_back();
      if (auto found = outgoingPhis.find(block); found != outgoingPhis.end())
        for (auto use : found->second)
          removeOperand(use);
      continue;
    }
    auto value = pending.back();
    pending.pop_back();
    if (auto found = readers.find(value); found != readers.end())
      for (auto *instruction : found->second)
        if ((instruction->op != ir::Op::Constant ||
             !instruction->operands.empty()) &&
            neutralize(*instruction))
          pending.push_back(instruction->result.id);
    if (auto found = phiReaders.find(value); found != phiReaders.end())
      for (auto use : found->second)
        removeOperand(use);
    if (auto found = exitReaders.find(value); found != exitReaders.end())
      for (auto b : found->second) {
        auto &exit = function.blocks[b].exit;
        if (exit.kind != ir::Exit::None && exit.kind != ir::Exit::Unreachable) {
          exit = {};
          exit.kind = ir::Exit::Unreachable;
          cutBlocks.push_back(b);
        }
      }
  }
  for (auto &phi : phis) {
    auto &instruction = *phi.instruction;
    if (!phi.remaining || phi.remaining == instruction.operands.size())
      continue;
    std::size_t kept = 0;
    for (std::size_t i = 0; i < phi.live.size(); ++i)
      if (phi.live[i]) {
        instruction.operands[kept] = instruction.operands[i];
        instruction.predecessors[kept++] = instruction.predecessors[i];
      }
    instruction.operands.resize(kept);
    instruction.predecessors.resize(kept);
  }
}
struct LocatedLimit : std::length_error {
  LocatedLimit(const std::string &message, Span span)
      : std::length_error(message), span(span) {}
  Span span;
};
} // namespace

void Queries::invalidate(std::span<const std::uint8_t> changed) {
  std::erase_if(entries, [&](const auto &entry) {
    return entry.first.first < changed.size() && changed[entry.first.first];
  });
}

class Planner {
public:
  Planner(const ir::Program &source, Diagnostics &diagnostics,
          const Hooks &hooks, Scope scope, Queries *queries,
          std::span<const std::size_t> roots)
      : source(source), diagnostics(diagnostics),
        types(std::make_shared<TypeStore>(*source.types)), hooks(hooks),
        queries(queries),
        library(scope == Scope::Library || scope == Scope::DemandedLibrary),
        demandedLibrary(scope == Scope::DemandedLibrary), roots(roots),
        externalLibraryBodies(scope == Scope::ProgramWithLibraryObjects ||
                              scope ==
                                  Scope::OptimizedProgramWithLibraryObjects),
        optimizeLibraryBodies(scope ==
                              Scope::OptimizedProgramWithLibraryObjects) {
    result.types = types;
    result.requireEntry = source.requireEntry && !library;
    result.statics = source.statics;
    result.staticPackages = source.staticPackages;
    if (library) {
      auto owned = result.statics.size();
      while (owned > 0 && !packageOwned(source.staticPackages, owned - 1))
        --owned;
      result.statics.resize(owned);
      result.staticPackages.resize(
          std::min(owned, source.staticPackages.size()));
    }
    result.libraries = source.libraries;
    result.target = source.target;
  }
  std::optional<SpecializedProgram> run() {
    try {
      if (demandedLibrary)
        for (auto root : roots)
          instance(root, {}, {});
      for (std::size_t i = 0; i < source.functions.size(); ++i) {
        if (auto index = source.deferredFunctionIndex(i)) {
          if ((demandedLibrary && !index->exportedDefinition) ||
              index->generic || index->declarationOnly ||
              (library ? !packageOwned(source.functionPackages, i)
                       : source.requireEntry && index->name != "main" &&
                             !index->exportedDefinition &&
                             i < source.libraryBodies.size() &&
                             source.libraryBodies[i]))
            continue;
        }
        if (demandedLibrary && !source.functions[i].exportedDefinition)
          continue;
        // An executable keeps its own functions and instantiates the library
        // bodies its entry, its exports and its statics reach.
        if (source.functions[i].genericParameters.empty() &&
            !source.functions[i].declarationOnly && !externalLibraryBody(i) &&
            (library
                 ? packageOwned(source.functionPackages, i)
                 : !source.requireEntry || source.functions[i].name == "main" ||
                       source.functions[i].exportedDefinition ||
                       i >= source.libraryBodies.size() ||
                       !source.libraryBodies[i]))
          instance(i, {}, {});
      }
      prepareDynamicDrops();
      std::function<void(StaticConstant &)> constant =
          [&](StaticConstant &value) {
            if (value.kind == StaticConstant::Kind::Function)
              value.symbol = instance(value.symbol, {}, {});
            for (auto &field : value.fields)
              constant(field);
          };
      for (std::size_t i = 0; i < result.statics.size(); ++i)
        if (auto &storage = result.statics[i];
            storage.initializer &&
            (!library || packageOwned(source.staticPackages, i))) {
          destructor(storage.type, storage.span);
          constant(*storage.initializer);
        }
      result.globalAssembly = source.globalAssembly;
      for (auto &assembly : result.globalAssembly)
        specializeAssembly(assembly, {});
    } catch (const metadata::InvalidMetadata &failure) {
      diagnostics.error("metadata", {}, failure.what());
    } catch (const std::invalid_argument &failure) {
      diagnostics.error("type", {}, failure.what());
    } catch (const LocatedLimit &failure) {
      diagnostics.error("limit", failure.span, failure.what());
    } catch (const std::length_error &failure) {
      diagnostics.error("limit", {}, failure.what());
    }
    if (!diagnostics.empty())
      return std::nullopt;
    if (queries) {
      queries->entries = std::move(nextQueries);
      queries->reused += queryHits;
    }
    return SpecializedProgram{std::move(result), std::move(types)};
  }

private:
  const ir::Program &source;
  Diagnostics &diagnostics;
  std::shared_ptr<TypeStore> types;
  const Hooks &hooks;
  Queries *queries;
  std::map<Queries::Key, std::shared_ptr<const Queries::Entry>> nextQueries;
  std::size_t queryHits = 0;
  std::map<Type, Queries::Recipe> typeRecipes;
  std::map<Queries::Recipe, Type, std::owner_less<Queries::Recipe>>
      restoredTypes;
  std::map<std::string, Type, std::less<>> nominalTypes;
  std::size_t nominalTypesIndexed = 0;
  std::map<std::string, Type, std::less<>> callableTypes;
  std::size_t callableTypesIndexed = 0;
  std::string callableIdentity(Type type) const {
    std::map<Type, std::optional<std::set<RegionId>>> regions;
    std::function<bool(Type)> collect = [&](Type value) {
      if (value.index() < builtinTypeCount)
        return true;
      auto [known, inserted] = regions.try_emplace(value);
      if (!inserted)
        return known->second.has_value();
      std::set<RegionId> free;
      auto addRegion = [&](RegionId region) {
        if (region != RegionId::Unspecified && region != RegionId::Static)
          free.insert(region);
      };
      auto child = [&](Type child) {
        if (!collect(child))
          return false;
        if (auto found = regions.find(child); found != regions.end())
          free.insert(found->second->begin(), found->second->end());
        return true;
      };
      if (types->isFunctionPointer(value)) {
        const auto &signature = types->callable(value);
        if (!child(signature.result) || !child(signature.error) ||
            !child(signature.abiResult))
          return false;
        for (const auto &requirement : signature.regionRequirements) {
          addRegion(requirement.longer);
          addRegion(requirement.shorter);
        }
        for (std::size_t i = 0; i < signature.parameters.size(); ++i) {
          const auto &parameter = signature.parameters[i];
          if (!child(parameter.type))
            return false;
          if (i < signature.parameterRegions.size() &&
              (parameter.mode == ParameterMode::Read ||
               parameter.mode == ParameterMode::Mut ||
               types->containsViews(parameter.type)))
            addRegion(signature.parameterRegions[i]);
        }
        for (auto bound : signature.regionParameters)
          free.erase(bound);
      } else if (types->isView(value) || types->isPointer(value)) {
        addRegion(types->view(value).region);
        if (!child(types->view(value).payload))
          return false;
      } else if (types->isSlice(value)) {
        if (!child(types->slice(value).element))
          return false;
      } else if (types->isProduct(value)) {
        const auto &product = types->product(value);
        if (product.callable >= 0 ||
            !std::all_of(product.genericArguments.begin(),
                         product.genericArguments.end(), child) ||
            !std::all_of(product.components.begin(), product.components.end(),
                         child) ||
            !std::all_of(product.fields.begin(), product.fields.end(),
                         [&](const auto &field) { return child(field.type); }))
          return false;
        for (auto region : product.regionArguments)
          addRegion(region);
      } else
        return false;
      known->second = std::move(free);
      return true;
    };
    if (!collect(type) || !regions.at(type)->empty())
      return {};
    const auto &signature = types->callable(type);
    return "F" + typeIdentity(*types, type) + ":" +
           std::to_string(static_cast<unsigned>(signature.environmentMode)) +
           ":" + typeIdentity(*types, signature.abiResult);
  }
  Type callableType(std::string_view identity) {
    if (auto found = callableTypes.find(identity); found != callableTypes.end())
      return found->second;
    if (!callableTypesIndexed)
      callableTypesIndexed =
          builtinTypeCount +
          (queries->types ? queries->types->storedTypeCount() : 0);
    while (callableTypesIndexed < builtinTypeCount + types->storedTypeCount()) {
      auto type = types->typeAt(callableTypesIndexed++);
      if (types->isFunctionPointer(type))
        if (auto key = callableIdentity(type); !key.empty())
          callableTypes.try_emplace(std::move(key), type);
    }
    auto found = callableTypes.find(identity);
    return found == callableTypes.end() ? Type::Unknown : found->second;
  }
  bool restorable(const Queries::Recipe &value) {
    return (value->kind != Queries::TypeRecipe::Kind::Callable ||
            callableType(value->identity) != Type::Unknown) &&
           std::all_of(
               value->arguments.begin(), value->arguments.end(),
               [&](const auto &argument) { return restorable(argument); });
  }
  Type nominalType(std::string_view name) {
    if (!nominalTypesIndexed)
      nominalTypesIndexed =
          builtinTypeCount +
          (queries->types ? queries->types->storedTypeCount() : 0);
    while (nominalTypesIndexed < builtinTypeCount + types->storedTypeCount()) {
      auto type = types->typeAt(nominalTypesIndexed++);
      if (!types->isProduct(type))
        continue;
      const auto &product = types->product(type);
      if ((product.kind != AggregateKind::Product &&
           product.kind != AggregateKind::Enumeration) ||
          product.genericOrigin != Type::Unknown || product.callable >= 0 ||
          product.normalizedFields || product.regionOrigin != Type::Unknown ||
          !product.regionArguments.empty())
        continue;
      auto [found, inserted] = nominalTypes.emplace(product.name, type);
      if (!inserted && found->second != type)
        found->second = Type::Unknown;
    }
    auto found = nominalTypes.find(name);
    return found == nominalTypes.end() ? Type::Unknown : found->second;
  }
  Queries::Recipe recipe(Type type) {
    if (auto found = typeRecipes.find(type); found != typeRecipes.end())
      return found->second;
    typeRecipes.emplace(type, nullptr);
    auto result = std::make_shared<Queries::TypeRecipe>();
    using Kind = Queries::TypeRecipe::Kind;
    std::vector<Type> arguments;
    if (queries->stable(type)) {
      result->origin = type;
      result->identity = "S" + std::to_string(type.index()) + ";";
    } else if (types->isPointer(type) || types->isView(type)) {
      const auto &view = types->view(type);
      if (view.region != RegionId::Unspecified &&
          view.region != RegionId::Static)
        return {};
      result->kind = types->isPointer(type) ? Kind::Pointer : Kind::View;
      result->mode = view.mode;
      result->region = view.region;
      arguments.push_back(view.payload);
    } else if (types->isSlice(type)) {
      result->kind = Kind::Slice;
      arguments.push_back(types->slice(type).element);
    } else if (types->isConstant(type) &&
               types->parameter(type).kind == TypeParameterKind::Value) {
      result->kind = Kind::Constant;
      result->value = types->parameter(type).numeric;
      arguments.push_back(types->parameter(type).valueType);
      result->identity = typeIdentity(*types, type);
    } else if (types->isFunctionPointer(type)) {
      result->identity = callableIdentity(type);
      if (result->identity.empty())
        return {};
      result->kind = Kind::Callable;
      callableTypes.insert_or_assign(result->identity, type);
    } else if (types->isProduct(type)) {
      const auto &product = types->product(type);
      if (product.callable >= 0 || !product.regionArguments.empty())
        return {};
      if (product.regionOrigin != Type::Unknown) {
        const auto &origin = types->product(product.regionOrigin);
        if (!origin.regionArguments.empty() ||
            product.genericOrigin != origin.genericOrigin ||
            product.genericArguments != origin.genericArguments ||
            product.regionPattern != origin.regionPattern ||
            product.fields.size() != origin.fields.size() ||
            !std::equal(product.fields.begin(), product.fields.end(),
                        origin.fields.begin(),
                        [](const auto &left, const auto &right) {
                          return left.name == right.name;
                        }))
          return {};
        result->kind = Kind::Regional;
        result->normalizedFields = product.normalizedFields;
        arguments.push_back(product.regionOrigin);
        for (const auto &field : product.fields)
          arguments.push_back(field.type);
      } else if (product.normalizedFields)
        return {};
      else if (product.genericOrigin != Type::Unknown) {
        result->kind = Kind::Instance;
        arguments.push_back(product.genericOrigin);
        arguments.insert(arguments.end(), product.genericArguments.begin(),
                         product.genericArguments.end());
      } else if ((product.kind == AggregateKind::Product ||
                  product.kind == AggregateKind::Enumeration) &&
                 nominalType(product.name) == type) {
        result->kind = Kind::Nominal;
        result->identity = "N" + product.name;
      } else {
        if (product.regionPattern != Type::Unknown)
          return {};
        switch (product.kind) {
        case AggregateKind::Optional:
        case AggregateKind::Outcome:
        case AggregateKind::Tuple:
        case AggregateKind::Array:
        case AggregateKind::Range:
        case AggregateKind::Uninit:
        case AggregateKind::ManualDrop:
        case AggregateKind::UnsafeCell:
        case AggregateKind::Cell:
        case AggregateKind::RefCell:
        case AggregateKind::Ref:
        case AggregateKind::RefMut:
        case AggregateKind::BorrowError:
        case AggregateKind::BorrowMutError:
        case AggregateKind::Pin:
        case AggregateKind::Atomic:
        case AggregateKind::Ordering:
        case AggregateKind::PhantomPinned:
          break;
        default:
          return {};
        }
        result->kind = Kind::Structural;
        result->aggregate = product.kind;
        result->count = static_cast<std::uint32_t>(product.fields.size());
        arguments = product.components;
        if (product.kind == AggregateKind::Array &&
            product.arrayCount != Type::Unknown) {
          result->kind = Kind::Array;
          arguments.push_back(product.arrayCount);
        }
      }
    } else
      return {};
    for (auto argument : arguments) {
      auto child = recipe(argument);
      if (!child)
        return {};
      result->arguments.push_back(std::move(child));
    }
    if (result->identity.empty()) {
      result->identity =
          std::to_string(static_cast<unsigned>(result->kind)) + ":" +
          std::to_string(result->origin.index()) + ":" +
          std::to_string(static_cast<unsigned>(result->mode)) + ":" +
          std::to_string(result->region.index()) + ":" +
          std::to_string(static_cast<unsigned>(result->aggregate)) + ":" +
          std::to_string(result->count) + ":" +
          std::to_string(result->normalizedFields) + "[";
      for (const auto &child : result->arguments)
        result->identity +=
            std::to_string(child->identity.size()) + ":" + child->identity;
      result->identity += "]";
    }
    typeRecipes[type] = result;
    restoredTypes.emplace(result, type);
    return result;
  }
  Type restore(const Queries::Recipe &recipe) {
    if (auto found = restoredTypes.find(recipe); found != restoredTypes.end())
      return found->second;
    std::vector<Type> arguments;
    for (const auto &argument : recipe->arguments)
      arguments.push_back(restore(argument));
    Type result;
    using Kind = Queries::TypeRecipe::Kind;
    switch (recipe->kind) {
    case Kind::Stable:
      result = recipe->origin;
      break;
    case Kind::View:
      result = types->viewType(arguments.at(0), recipe->mode, recipe->region);
      break;
    case Kind::Pointer:
      result = types->pointerType(arguments.at(0), recipe->mode);
      break;
    case Kind::Slice:
      result = types->sliceType(arguments.at(0));
      break;
    case Kind::Constant:
      result = types->constant(arguments.at(0), recipe->value);
      break;
    case Kind::Instance:
      result = types->instantiateProduct(
          arguments.at(0), {arguments.begin() + 1, arguments.end()});
      break;
    case Kind::Structural:
      result = types->structural(recipe->aggregate, std::move(arguments),
                                 recipe->count);
      break;
    case Kind::Array:
      result = types->arrayType(arguments.at(0), arguments.at(1));
      break;
    case Kind::Nominal:
      result = nominalType(std::string_view(recipe->identity).substr(1));
      if (result == Type::Unknown)
        throw std::logic_error(
            "specialization query lost its source declaration identity");
      break;
    case Kind::Regional: {
      auto origin = arguments.at(0);
      auto fields = types->product(origin).fields;
      if (arguments.size() != fields.size() + 1)
        throw std::logic_error(
            "specialization query changed its normalized field inventory");
      for (std::size_t i = 0; i < fields.size(); ++i)
        fields[i].type = arguments[i + 1];
      result = types->regionalProduct(origin, std::move(fields), {},
                                      recipe->normalizedFields);
      break;
    }
    case Kind::Callable:
      result = callableType(recipe->identity);
      if (result == Type::Unknown)
        throw std::logic_error(
            "specialization query lost its current callable contract");
      break;
    }
    restoredTypes.emplace(recipe, result);
    return result;
  }
  const bool library;
  const bool demandedLibrary;
  const std::span<const std::size_t> roots;
  const bool externalLibraryBodies;
  const bool optimizeLibraryBodies;
  ir::Program result;
  static bool packageOwned(const std::vector<std::string> &packages,
                           std::size_t index) {
    return index < packages.size() && !packages[index].empty();
  }
  bool externalLibraryBody(std::size_t index) const {
    if (!externalLibraryBodies || index >= source.libraryBodies.size() ||
        !source.libraryBodies[index] ||
        index >= source.functionPackages.size() ||
        !source.functionPackages[index].starts_with("native:") ||
        index >= source.functions.size())
      return false;
    const auto &function = source.functions[index];
    return !function.declarationOnly && function.genericParameters.empty() &&
           function.variadicCursor < 0 &&
           (function.abi.empty() || !function.externalName.empty());
  }
  bool canInlineAcrossObjects(const ir::Function &function) const {
    if (function.trackCaller || !function.targetFeatures.empty())
      return false;
    std::map<Type, bool> safeTypes;
    auto safeType = [&](Type type) {
      if (type == Type::Unknown)
        return true;
      auto [entry, inserted] = safeTypes.try_emplace(type);
      if (inserted)
        entry->second =
            !source.types->isSymbolic(type) && !source.types->needsDrop(type);
      return entry->second;
    };
    if (!safeType(function.result))
      return false;
    for (const auto &local : function.locals) {
      if (!safeType(local.type))
        return false;
      if (local.storage == StorageDuration::Static &&
          (local.staticIndex < 0 ||
           static_cast<std::size_t>(local.staticIndex) >=
               source.staticPackages.size() ||
           !source.staticPackages[local.staticIndex].starts_with("native:")))
        return false;
    }
    for (const auto &block : function.blocks) {
      if (!safeType(block.exit.value.type))
        return false;
      for (const auto &instruction : block.instructions) {
        if (!safeType(instruction.result.type) ||
            !safeType(instruction.target.type) ||
            instruction.constantParameter != Type::Unknown ||
            instruction.interfaceMethod >= 0 ||
            !instruction.unpinProofs.empty() ||
            !instruction.witnessEntries.empty() || instruction.assembly ||
            instruction.dropFunction >= 0 ||
            std::any_of(
                instruction.operands.begin(), instruction.operands.end(),
                [&](const auto &value) { return !safeType(value.type); }))
          return false;
        switch (instruction.op) {
        case ir::Op::Constant:
        case ir::Op::Declare:
        case ir::Op::Load:
        case ir::Op::Store:
        case ir::Op::Unary:
        case ir::Op::Binary:
        case ir::Op::Phi:
        case ir::Op::Construct:
        case ir::Op::Project:
        case ir::Op::Move:
        case ir::Op::BorrowRead:
        case ir::Op::BorrowMut:
        case ir::Op::ReserveMut:
        case ir::Op::Activate:
        case ir::Op::ViewRead:
        case ir::Op::ViewMut:
        case ir::Op::ScopeExit:
        case ir::Op::VariantConstruct:
        case ir::Op::VariantTest:
        case ir::Op::ArrayBorrowRead:
        case ir::Op::ArrayBorrowMut:
        case ir::Op::ArrayRepeat:
        case ir::Op::ArrayTake:
        case ir::Op::UnsizeView:
        case ir::Op::SliceLength:
        case ir::Op::SliceBorrowRead:
        case ir::Op::SliceBorrowMut:
        case ir::Op::Cast:
        case ir::Op::StorageWrite:
        case ir::Op::RawAddress:
          break;
        case ir::Op::Call:
          if (instruction.callee < 0 || !instruction.typeArguments.empty() ||
              !externalLibraryBody(
                  static_cast<std::size_t>(instruction.callee)) ||
              source.functions[instruction.callee].trackCaller)
            return false;
          break;
        case ir::Op::Machine:
          if (!instruction.text.starts_with("numeric.") &&
              instruction.text != "ptr.cast" && instruction.text != "ptr.add")
            return false;
          break;
        default:
          return false;
        }
      }
    }
    return true;
  }
  using Key = std::pair<std::size_t, std::vector<Type>>;
  std::map<Key, int> instances;
  std::map<std::pair<Type, Type>, int> callableAdapters;
  std::map<Type, int> callableContracts;
  std::map<Type, int> coroutineBodies;
  std::set<Type> visitedTypes;
  unsigned instanceDepth = 0;
  Type dropElement(Type payload) const {
    if (types->isSlice(payload))
      return types->slice(payload).element;
    return types->isSized(payload) ? payload : Type::Unknown;
  }
  Type tailDropElement(Type payload) const {
    std::set<Type> visited;
    while (visited.insert(payload).second) {
      if (types->isSlice(payload))
        return types->slice(payload).element;
      if (types->isSized(payload))
        return payload;
      if (!types->isProduct(payload) || types->product(payload).fields.empty())
        return Type::Unknown;
      payload = types->product(payload).fields.back().type;
    }
    return Type::Unknown;
  }
  void prepareDynamicDrops() {
    int helper = -1;
    for (std::size_t i = 0; i < source.functions.size(); ++i) {
      auto index = source.deferredFunctionIndex(i);
      if (displayPath(index ? index->name : source.functions[i].name) ==
          "core.slice.drop_values") {
        helper = static_cast<int>(i);
        break;
      }
    }

    std::map<Type, Span> requested;
    auto request = [&](Type payload, Span span) {
      auto element = dropElement(payload);
      if (element != Type::Unknown && types->needsDrop(element))
        requested.try_emplace(element, span);
    };
    auto requestTail = [&](Type payload, Span span) {
      auto element = tailDropElement(payload);
      if (element != Type::Unknown && types->needsDrop(element))
        requested.try_emplace(element, span);
    };
    for (const auto &function : result.functions)
      for (const auto &block : function.blocks)
        for (const auto &instruction : block.instructions) {
          if (instruction.op == ir::Op::OwnerUnsize) {
            auto sourcePayload =
                types->product(instruction.operands.front().type)
                    .genericArguments.front();
            auto targetPayload = types->product(instruction.result.type)
                                     .genericArguments.front();
            if (types->isSlice(targetPayload))
              request(targetPayload, instruction.span);
            else if (instruction.interfaceType != Type::Unknown)
              request(sourcePayload, instruction.span);
            else if (types->needsDrop(targetPayload)) {
              if (tailDropElement(targetPayload) == Type::Unknown)
                diagnostics.error("feature", instruction.span,
                                  "dynamic drop for this unsized owner payload "
                                  "is unsupported");
              else
                requestTail(targetPayload, instruction.span);
            }
          } else if (instruction.op == ir::Op::EraseView) {
            if (dropElement(instruction.interfaceSelf) == Type::Unknown &&
                types->needsDrop(instruction.interfaceSelf))
              diagnostics.error("feature", instruction.span,
                                "dynamic drop for this erased unsized payload "
                                "is unsupported");
            else
              request(instruction.interfaceSelf, instruction.span);
          } else if (instruction.op == ir::Op::DropPlace) {
            auto payload = projectedType(
                *types, function.locals[instruction.place.root].type,
                instruction.place.fields);
            if (payload &&
                (types->isSlice(*payload) || types->isErased(*payload))) {
              if (!types->isErased(*payload))
                request(*payload, instruction.span);
            } else if (payload &&
                       types->pointerMetadata(*payload) ==
                           PointerMetadata::ElementCount &&
                       types->needsDrop(*payload)) {
              if (tailDropElement(*payload) == Type::Unknown)
                diagnostics.error(
                    "feature", instruction.span,
                    "dynamic drop for this unsized payload is unsupported");
              else
                requestTail(*payload, instruction.span);
            }
          }
        }

    std::map<Type, int> specialized;
    for (const auto &[element, span] : requested) {
      if (helper < 0) {
        diagnostics.error("feature", span,
                          "dynamic drop requires core.slice.drop_values");
        continue;
      }
      specialized.emplace(
          element, instance(static_cast<std::size_t>(helper), {element}, span));
    }

    auto functionFor = [&](Type payload) {
      auto element = dropElement(payload);
      auto found = specialized.find(element);
      return found == specialized.end() ? -1 : found->second;
    };
    std::map<Type, int> dynamicDrops;
    for (const auto &[element, function] : specialized)
      dynamicDrops.emplace(element, function);
    for (std::size_t f = 0; f < result.functions.size(); ++f) {
      auto &function = result.functions.edit(f);
      for (auto &block : function.blocks)
        for (auto &instruction : block.instructions) {
          if (instruction.op == ir::Op::OwnerUnsize) {
            auto sourcePayload =
                types->product(instruction.operands.front().type)
                    .genericArguments.front();
            auto targetPayload = types->product(instruction.result.type)
                                     .genericArguments.front();
            instruction.dropFunction =
                instruction.interfaceType != Type::Unknown
                    ? functionFor(sourcePayload)
                : types->isSlice(targetPayload) ? functionFor(targetPayload)
                                                : -1;
            if (instruction.interfaceType != Type::Unknown &&
                instruction.dropFunction >= 0)
              dynamicDrops.emplace(sourcePayload, instruction.dropFunction);
          } else if (instruction.op == ir::Op::EraseView) {
            instruction.dropFunction = functionFor(instruction.interfaceSelf);
            if (instruction.dropFunction >= 0)
              dynamicDrops.emplace(instruction.interfaceSelf,
                                   instruction.dropFunction);
          } else if (instruction.op == ir::Op::DropPlace) {
            auto payload = projectedType(
                *types, function.locals[instruction.place.root].type,
                instruction.place.fields);
            if (payload && types->isSlice(*payload))
              instruction.dropFunction = functionFor(*payload);
          }
        }
    }
    result.dynamicDropFunctions.assign(dynamicDrops.begin(),
                                       dynamicDrops.end());
  }
  void specializeAssembly(Assembly &assembly,
                          std::span<const TypeBinding> bindings) {
    for (auto &operand : assembly.operands) {
      if (operand.mode == AssemblyMode::Const) {
        operand.constantIdentity =
            types->substitute(operand.constantIdentity, bindings);
        auto value = types->scalarConstantValue(operand.constantIdentity);
        if (!value)
          throw std::invalid_argument(
              "assembly const requires a resolved integer constant");
        operand.constant = *value;
        operand.type = types->parameter(operand.constantIdentity).valueType;
      } else if (operand.mode == AssemblyMode::Sym &&
                 operand.symbolKind == AssemblyOperand::SymbolKind::Function) {
        auto arguments = operand.symbolArguments;
        for (auto &argument : arguments)
          argument = types->substitute(argument, bindings);
        operand.symbol = instance(operand.symbol, arguments, {});
        operand.symbolArguments.clear();
      } else if (operand.mode != AssemblyMode::Const)
        operand.type =
            types->eraseRegions(types->substitute(operand.type, bindings));
      operand.inputType =
          types->eraseRegions(types->substitute(operand.inputType, bindings));
    }
  }
  int closureBody(Type receiver, Span span) {
    const auto &signature = types->callable(receiver);
    if (signature.function < 0 ||
        static_cast<std::size_t>(signature.function) >=
            source.closureFunctions.size())
      throw std::invalid_argument("callable environment has no generated body");
    auto body = source.closureFunctions[signature.function];
    auto arguments = types->product(receiver).genericOrigin == Type::Unknown
                         ? source.functions[body].genericParameters
                         : types->product(receiver).genericArguments;
    return instance(static_cast<std::size_t>(body), arguments, span);
  }
  // The body of a coroutine state is its closure's instance, marked so the
  // backend lays out its frame inside the state.
  int coroutineBody(Type state, Span span) {
    if (auto found = coroutineBodies.find(state);
        found != coroutineBodies.end())
      return found->second;
    auto closure = types->product(state).components[1];
    if (!types->isCallable(closure) || types->isFunctionPointer(closure))
      throw std::invalid_argument("coroutine body is not a closure");
    auto function = types->callable(closure).function;
    if (function < 0 ||
        static_cast<std::size_t>(function) >= source.closureFunctions.size() ||
        !source.functions[source.closureFunctions[function]].coroutine)
      throw std::invalid_argument("coroutine body is not an async closure");
    auto body = closureBody(closure, span);
    coroutineBodies.emplace(state, body);
    result.coroutines.emplace_back(state, body);
    return body;
  }
  int adaptCallable(Type receiver, Type contract, Span span) {
    if (!types->satisfiesCallable(receiver, contract))
      throw std::invalid_argument(
          "concrete callable does not satisfy its declared capability");
    auto key = std::pair{receiver, contract};
    if (auto found = callableAdapters.find(key);
        found != callableAdapters.end())
      return found->second;
    if (result.functions.size() + 2 >= limits::functions)
      throw std::length_error("callable specialization limit exceeded");
    auto id = static_cast<int>(result.functions.size());
    callableAdapters.emplace(key, id);
    result.functions.emplace_back();
    result.functionPackages.emplace_back();
    int callee;
    if (types->isFunctionPointer(receiver)) {
      auto [entry, inserted] = callableContracts.emplace(receiver, -1);
      if (inserted) {
        entry->second = static_cast<int>(result.functions.size());
        result.functions.push_back(callableContract(receiver, *types));
        result.functionPackages.emplace_back();
      }
      callee = entry->second;
    } else
      callee = closureBody(receiver, span);
    result.functions.edit(id) =
        callableAdapter(receiver, contract, callee, *types,
                        "<callable-adapter-" + std::to_string(id) + ">");
    return id;
  }
  void concrete(Type type, Span span) {
    if (type == Type::Unknown || types->isSymbolic(type))
      diagnostics.error("type", span,
                        "generic instance contains an unresolved parameter");
    else if (types->isProduct(type) && types->isSized(type)) {
      auto layout = objectLayout(*types, type);
      if (!layout && !coroutineDependent(*types, type))
        diagnostics.error(
            "attribute", span,
            "object layout cannot be established for this representation");
      else if (layout && layout->size > limits::objectBytes)
        diagnostics.error("limit", span,
                          "array size exceeds target address space");
    }
  }
  void destructor(Type type, Span span) {
    if (!visitedTypes.insert(type).second)
      return;
    if (types->isView(type)) {
      destructor(types->view(type).payload, span);
      return;
    }
    if (!types->isProduct(type))
      return;
    auto product = types->product(type);
    if (product.hasDestructor && product.destructor >= 0) {
      auto index = static_cast<std::size_t>(product.destructor);
      if (index >= source.functions.size())
        throw std::invalid_argument(
            "generic destructor refers to an invalid function");
      auto arguments = source.functions[index].genericParameters.empty()
                           ? std::vector<Type>{}
                           : product.genericArguments;
      auto selected = instance(index, std::move(arguments), span);
      types->setDestructor(type, selected);
    }
    for (const auto &field : product.fields)
      destructor(field.type, span);
  }
  int instance(std::size_t index, std::vector<Type> arguments, Span span) {
    if (index >= source.functions.size())
      throw std::invalid_argument(
          "generic call refers to an invalid declaration");
    const auto &header = source.functions[index];
    Key key{index, arguments};
    if (auto found = instances.find(key); found != instances.end())
      return found->second;
    const bool external = arguments.empty() && externalLibraryBody(index);
    bool available = false;
    if (external && optimizeLibraryBodies && header.abi.empty() &&
        header.externalName.empty() && !header.coroutine &&
        !header.nakedAssembly && header.inlineHint != ir::InlineHint::Never &&
        index < source.lazyFunctionRecords.size() &&
        source.lazyFunctionRecords[index]) {
      auto record = *source.lazyFunctionRecords[index];
      if (record >= hooks.libraryBodySizes.size()) {
        diagnostics.error("metadata", span,
                          "deferred checked-library body size is unavailable");
        return -1;
      }
      constexpr std::size_t automaticInlineBodyBytes = 8192;
      available = header.inlineHint != ir::InlineHint::Default ||
                  hooks.libraryBodySizes[record] <= automaticInlineBodyBytes;
    }
    std::optional<ir::Function> loaded;
    auto loadBody = [&]() {
      if (!hooks.loadLibraryBody) {
        diagnostics.error("metadata", span,
                          "deferred checked-library body has no loader");
        return false;
      }
      loaded = hooks.loadLibraryBody(*source.lazyFunctionRecords[index], header,
                                     diagnostics);
      return loaded.has_value();
    };
    if (available) {
      if (!loadBody())
        return -1;
      available = canInlineAcrossObjects(*loaded);
    }
    if (external && !available) {
      auto id = static_cast<int>(result.functions.size());
      instances.emplace(std::move(key), id);
      auto symbol = header.externalName.empty()
                        ? "mettle." + displayPath(header.name)
                        : header.externalName;
      result.functions.push_back(header.externalDeclaration(std::move(symbol)));
      result.functionPackages.push_back(source.functionPackages[index]);
      result.declarationSources.resize(id);
      result.declarationSources.push_back(index);
      return id;
    }
    if (header.declarationOnly)
      throw std::invalid_argument(
          "interface call has no uniquely selected concrete implementation");
    if (header.genericParameters.size() != arguments.size())
      throw std::invalid_argument(
          "generic instance argument count does not match");
    if (instanceDepth >= limits::typeDepth)
      throw LocatedLimit("generic specialization nesting limit exceeded "
                         "while instantiating '" +
                             displayPath(header.name) + "'",
                         span);
    for (auto argument : arguments)
      if (types->name(argument).size() > limits::typeNameBytes)
        throw LocatedLimit("generic specialization type grows beyond the "
                           "compiler size limit while instantiating '" +
                               displayPath(header.name) + "'",
                           span);
    struct Scope {
      unsigned &depth;
      explicit Scope(unsigned &depth) : depth(depth) { ++depth; }
      ~Scope() { --depth; }
    } scope(instanceDepth);
    if (instances.size() >= limits::functions)
      throw std::length_error("generic specialization limit exceeded");
    std::vector<TypeBinding> bindings;
    for (std::size_t i = 0; i < arguments.size(); ++i) {
      concrete(arguments[i], span);
      bindings.push_back({header.genericParameters[i], arguments[i]});
    }
    bool queryable = queries && index < queries->functions &&
                     !header.indirectContract && !header.nakedAssembly;
    Queries::Key queryKey{index, {}};
    if (queryable) {
      for (auto argument : arguments)
        if (auto value = recipe(argument))
          queryKey.second.push_back(value->identity);
        else {
          queryable = false;
          break;
        }
    }
    std::shared_ptr<const Queries::Entry> cached;
    if (queryable)
      if (auto found = queries->entries.find(queryKey);
          found != queries->entries.end())
        cached = found->second;
    if (cached &&
        !std::all_of(cached->types.begin(), cached->types.end(),
                     [&](const auto &item) { return restorable(item.second); }))
      cached.reset();
    if (cached)
      for (auto [block, position] : cached->indirectCallees) {
        const auto &current = loaded ? *loaded : header;
        if (block >= current.blocks.size() ||
            position >= current.blocks[block].instructions.size()) {
          cached.reset();
          break;
        }
        const auto &instruction = current.blocks[block].instructions[position];
        if (instruction.op != ir::Op::IndirectCall || instruction.callee < 0 ||
            static_cast<std::size_t>(instruction.callee) >=
                source.functions.size() ||
            !source.functions[instruction.callee].indirectContract) {
          cached.reset();
          break;
        }
      }
    if (!loaded && !cached && index < source.lazyFunctionRecords.size() &&
        source.lazyFunctionRecords[index])
      if (!loadBody())
        return -1;
    const auto &declaration = loaded ? *loaded : header;
    auto id = static_cast<int>(result.functions.size());
    const bool genericInstance = !arguments.empty();
    instances.emplace(key, id);
    result.functions.emplace_back();
    if (available) {
      result.availableExternally.resize(id + 1);
      result.availableExternally[id] = true;
    }
    if (genericInstance) {
      result.genericInstances.resize(id + 1);
      result.genericInstances[id] = true;
    }
    result.functionPackages.push_back(
        genericInstance || index >= source.functionPackages.size()
            ? std::string{}
            : source.functionPackages[index]);
    auto function = cached ? cached->function : declaration;
    if (!cached)
      function.genericParameters.clear();
    if (!cached && !arguments.empty()) {
      function.name += ".<";
      for (std::size_t i = 0; i < arguments.size(); ++i) {
        if (i)
          function.name += ",";
        function.name += types->name(arguments[i]);
      }
      function.name += ">";
      // Display names omit callable binders, result sources and region
      // relations, so distinct function-pointer arguments can print alike.
      // Their instances carry a hash of the structural identity, which is a
      // pure function of the arguments and so agrees across packages.
      if (std::any_of(arguments.begin(), arguments.end(), [&](Type argument) {
            return containsFunctionPointer(*types, argument);
          })) {
        std::uint64_t identity = 0xcbf29ce484222325ull;
        for (auto argument : arguments)
          for (unsigned char byte : typeIdentity(*types, argument) + "|")
            identity = (identity ^ byte) * 0x100000001b3ull;
        static constexpr char digits[] = "0123456789abcdef";
        function.name += "#";
        for (int shift = 60; shift >= 0; shift -= 4)
          function.name += digits[(identity >> shift) & 0xf];
      }
      // A generic indirect contract is declared by external name; each
      // instance has its own signature, so it needs its own symbol.
      if (function.indirectContract)
        function.externalName += "." + std::to_string(id);
    }
    auto regionSignature =
        types->substitute(declaration.regionSignature, bindings);
    if (hooks.normalizeRegionSignature)
      regionSignature = hooks.normalizeRegionSignature(
          regionSignature, bindings, *types, diagnostics);
    std::vector<std::pair<Type, std::optional<Span>>> destructors;
    if (cached) {
      std::map<Type, Type> remapped;
      for (const auto &[type, value] : cached->types)
        remapped.emplace(type, restore(value));
      auto remap = [&](Type type) {
        return queries->stable(type) ? type : remapped.at(type);
      };
      ir::remapTypes(function, remap);
      for (auto [block, position] : cached->indirectCallees)
        function.blocks.at(block).instructions.at(position).callee =
            declaration.blocks.at(block).instructions.at(position).callee;
      function.interfaceResult = declaration.interfaceResult;
      for (auto [type, location] : cached->destructors)
        destructor(remap(type), location.value_or(span));
      nextQueries.emplace(std::move(queryKey), cached);
      ++queryHits;
    } else {
      // Instructions repeat a handful of types; a result is cached only after
      // it was fully validated without diagnostics.
      std::map<std::pair<Type, bool>, Type> resolved;
      auto substitute = [&](Type &type, bool runtime = true) {
        if (auto known = resolved.find({type, runtime});
            known != resolved.end()) {
          type = known->second;
          return;
        }
        const auto original = type;
        type = types->substitute(type, bindings);
        if (hooks.normalizeType)
          type = hooks.normalizeType(type, bindings, *types, diagnostics);
        if (runtime)
          type = types->eraseRegions(type);
        if (type != Type::Unknown) {
          concrete(type, span);
          if (queryable)
            destructors.emplace_back(type, std::nullopt);
          destructor(type, span);
        }
        if (diagnostics.empty())
          resolved.emplace(std::pair{original, runtime}, type);
      };
      substitute(function.result);
      for (auto &local : function.locals)
        substitute(local.type);
      function.interfaceBounds.clear();
      function.unpinBounds.clear();
      function.sizedBounds.clear();
      function.regionSignature = regionSignature;
      function.genericEqualities.clear();
      if (types->containsViews(function.result, true))
        for (auto source : function.genericResultSources) {
          if (source >= function.parameters)
            throw std::invalid_argument(
                "generic result source is not a parameter");
          // Only views carried by the instantiated argument can flow into the
          // result; the borrow of a `read`/`mut` parameter itself does not.
          const auto &parameter = function.locals[source];
          if (!types->containsViews(parameter.type, true) ||
              std::find(function.resultSources.begin(),
                        function.resultSources.end(),
                        source) != function.resultSources.end())
            continue;
          function.resultSources.push_back(source);
          if (parameter.mode == ParameterMode::Read ||
              parameter.mode == ParameterMode::Mut)
            function.resultContents.push_back(source);
        }
      function.genericResultSources.clear();
      if (function.nakedAssembly)
        specializeAssembly(*function.nakedAssembly, bindings);
      for (auto &block : function.blocks) {
        if (block.exit.kind != ir::Exit::None)
          substitute(block.exit.value.type);
        for (auto &instruction : block.instructions) {
          for (auto &[subject, runtime] : instruction.unpinProofs) {
            if (!hooks.validateUnpin)
              throw std::invalid_argument(
                  "Unpin instance proof is unavailable");
            subject =
                hooks.validateUnpin(subject, bindings, function,
                                    instruction.span, *types, diagnostics);
            substitute(runtime);
          }
          if (instruction.assembly)
            specializeAssembly(*instruction.assembly, bindings);
          substitute(instruction.result.type);
          substitute(instruction.indirectType);
          substitute(instruction.opaqueType);
          substitute(instruction.interfaceType, false);
          substitute(instruction.interfaceSelf, false);
          substitute(instruction.target.type);
          for (auto &projection : instruction.place.fields)
            substitute(projection.type);
          for (auto &operand : instruction.operands)
            substitute(operand.type);
          for (auto &argument : instruction.typeArguments)
            substitute(argument, false);
          for (auto &entry : instruction.witnessEntries)
            substitute(entry.owner, false);
          if (instruction.op == ir::Op::DropPlace) {
            auto payload = projectedType(
                *types, function.locals.at(instruction.place.root).type,
                instruction.place.fields);
            if (!payload)
              throw std::invalid_argument("explicit drop has an invalid place");
            if (queryable)
              destructors.emplace_back(*payload, instruction.span);
            destructor(*payload, instruction.span);
          }
          if (instruction.constantParameter != Type::Unknown) {
            auto identity =
                types->substitute(instruction.constantParameter, bindings);
            if (hooks.normalizeType)
              identity =
                  hooks.normalizeType(identity, bindings, *types, diagnostics);
            auto value = types->scalarConstantValue(identity);
            if (!value && hooks.aggregateConstant &&
                hooks.aggregateConstant(
                    instruction,
                    types->substitute(instruction.constantParameter, bindings),
                    *types, diagnostics)) {
              // Replaced by a call of the implementation's initializer.
            } else if (!value)
              diagnostics.error(
                  "type", instruction.span,
                  "const parameter did not evaluate in generic instance");
            else {
              instruction.numeric = *value;
              if (instruction.result.type == Type::I32 ||
                  instruction.result.type == Type::Bool ||
                  instruction.result.type == Type::Char ||
                  instruction.result.type == Type::U8)
                instruction.number =
                    static_cast<std::int32_t>(*types->constantValue(identity));
            }
            instruction.constantParameter = Type::Unknown;
          }
          if (hooks.selectCall &&
              !hooks.selectCall(instruction, bindings, *types, diagnostics))
            continue;
        }
      }
      for (auto &loop : function.arrayLoops) {
        substitute(loop.index.type);
        for (auto &projection : loop.source.fields)
          substitute(projection.type);
      }
      if (queryable && diagnostics.empty()) {
        bool stable = true;
        std::vector<std::pair<std::size_t, std::size_t>> indirectCallees;
        for (const auto &local : function.locals)
          if (local.storage == StorageDuration::Static)
            stable &=
                local.staticIndex >= 0 &&
                static_cast<std::size_t>(local.staticIndex) < queries->statics;
        for (std::size_t b = 0; b < function.blocks.size(); ++b)
          for (std::size_t i = 0; i < function.blocks[b].instructions.size();
               ++i) {
            const auto &instruction = function.blocks[b].instructions[i];
            stable &= !instruction.assembly;
            stable &= instruction.dropFunction < 0 ||
                      static_cast<std::size_t>(instruction.dropFunction) <
                          queries->functions;
            if (instruction.callee >= 0 &&
                static_cast<std::size_t>(instruction.callee) >=
                    queries->functions) {
              if (instruction.op == ir::Op::IndirectCall &&
                  static_cast<std::size_t>(instruction.callee) <
                      source.functions.size() &&
                  source.functions[instruction.callee].indirectContract)
                indirectCallees.emplace_back(b, i);
              else
                stable = false;
            }
          }
        if (stable) {
          auto retained = std::make_shared<Queries::Entry>(
              Queries::Entry{function,
                             std::move(destructors),
                             {},
                             std::move(indirectCallees)});
          for (auto [block, position] : retained->indirectCallees)
            retained->function.blocks[block].instructions[position].callee = -1;
          retained->function.regionSignature = Type::Unknown;
          retained->function.interfaceResult = Type::Unknown;
          auto remember = [&](Type type) {
            if (!queries->stable(type)) {
              if (auto value = recipe(type))
                retained->types.emplace(type, std::move(value));
              else
                stable = false;
            }
            return type;
          };
          ir::remapTypes(retained->function, remember);
          for (auto [type, location] : retained->destructors) {
            (void)location;
            remember(type);
          }
          if (stable)
            nextQueries.emplace(std::move(queryKey), std::move(retained));
        }
      }
    }
    function.regionSignature = regionSignature;
    for (auto &block : function.blocks)
      for (auto &instruction : block.instructions) {
        if (instruction.op == ir::Op::IndirectCall &&
            instruction.target.type != instruction.indirectType) {
          instruction.callee =
              adaptCallable(instruction.target.type, instruction.indirectType,
                            instruction.span);
          instruction.op = ir::Op::Call;
          instruction.operands.insert(instruction.operands.begin(),
                                      instruction.target);
          instruction.target = {};
          instruction.indirectType = Type::Unknown;
          instruction.typeArguments.clear();
          continue;
        }
        if (instruction.op == ir::Op::Machine &&
            (instruction.text == "coroutine.start" ||
             instruction.text == "coroutine.resume")) {
          instruction.callee =
              coroutineBody(instruction.typeArguments.at(0), instruction.span);
          continue;
        }
        if (instruction.callee >= 0) {
          instruction.callee =
              instance(static_cast<std::size_t>(instruction.callee),
                       instruction.typeArguments, instruction.span);
          instruction.typeArguments.clear();
        }
      }
    neutralizeEmptyValues(function);
    expandArrays(function, *types);
    result.functions.edit(id) = std::move(function);
    return id;
  }
};
std::optional<SpecializedProgram>
specialize(const ir::Program &declarations, Diagnostics &diagnostics,
           const Hooks &hooks, Scope scope, Queries *queries,
           std::span<const std::size_t> roots) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Planner(declarations, diagnostics, hooks, scope, queries, roots).run();
}
} // namespace mettle::instances
