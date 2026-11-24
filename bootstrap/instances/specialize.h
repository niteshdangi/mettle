#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include <functional>
#include <map>
#include <memory>
#include <optional>

namespace mettle::instances {
class Queries {
public:
  Queries(std::shared_ptr<const TypeStore> types, std::size_t functions,
          std::size_t statics = 0)
      : types(std::move(types)), functions(functions), statics(statics) {}
  void invalidate(std::span<const std::uint8_t> changed);
  std::size_t hits() const { return reused; }

private:
  friend class Planner;
  struct TypeRecipe {
    enum class Kind {
      Stable,
      View,
      Pointer,
      Slice,
      Constant,
      Instance,
      Structural,
      Array,
      Nominal,
      Regional,
      Callable
    };
    Kind kind = Kind::Stable;
    Type origin = Type::Unknown;
    ParameterMode mode = ParameterMode::Value;
    RegionId region = RegionId::Unspecified;
    AggregateKind aggregate = AggregateKind::Product;
    NumericLiteral value{};
    std::uint32_t count = 0;
    bool normalizedFields = false;
    std::vector<std::shared_ptr<const TypeRecipe>> arguments;
    std::string identity;
  };
  using Recipe = std::shared_ptr<const TypeRecipe>;
  using Key = std::pair<std::size_t, std::vector<std::string>>;
  struct Entry {
    ir::Function function;
    std::vector<std::pair<Type, std::optional<Span>>> destructors;
    std::map<Type, Recipe> types;
    std::vector<std::pair<std::size_t, std::size_t>> indirectCallees;
  };
  std::shared_ptr<const TypeStore> types;
  std::size_t functions;
  std::size_t statics;
  std::map<Key, std::shared_ptr<const Entry>> entries;
  std::size_t reused = 0;
  bool stable(Type type) const {
    return type.index() < builtinTypeCount || (types && types->contains(type));
  }
};
struct Hooks {
  std::function<Type(Type, std::span<const TypeBinding>, TypeStore &,
                     Diagnostics &)>
      normalizeType{};
  std::function<bool(ir::Instruction &, std::span<const TypeBinding>,
                     TypeStore &, Diagnostics &)>
      selectCall{};
  // Turns the constant of an aggregate-typed interface constant, named by its
  // projection, into a call of the implementation's initializer.
  std::function<bool(ir::Instruction &, Type, TypeStore &, Diagnostics &)>
      aggregateConstant{};
  std::function<Type(Type, std::span<const TypeBinding>, const ir::Function &,
                     Span, TypeStore &, Diagnostics &)>
      validateUnpin{};
  std::function<Type(Type, std::span<const TypeBinding>, TypeStore &,
                     Diagnostics &)>
      normalizeRegionSignature{};
  std::function<std::optional<ir::Function>(std::size_t, const ir::Function &,
                                            Diagnostics &)>
      loadLibraryBody{};
  std::span<const std::size_t> libraryBodySizes{};
};
// `Program` instantiates what the program reaches; `Library` instantiates
// every non-generic package-owned body and its statics, independent of any
// consumer, so each package's code can be compiled once and reused.
enum class Scope {
  Program,
  ProgramWithLibraryObjects,
  OptimizedProgramWithLibraryObjects,
  Library,
  DemandedLibrary
};
struct SpecializedProgram {
  ir::Program program;
  std::shared_ptr<TypeStore> types;
};

std::optional<SpecializedProgram>
specialize(const ir::Program &declarations, Diagnostics &diagnostics,
           const Hooks &hooks = {}, Scope scope = Scope::Program,
           Queries *queries = nullptr, std::span<const std::size_t> roots = {});
} // namespace mettle::instances
