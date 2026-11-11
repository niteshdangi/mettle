#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"
#include <cstdint>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mettle::resolution {
using ModuleId = std::uint32_t;
using SourcePackages = std::unordered_map<SourceId, std::string>;
enum class Namespace { Type, Value, Module, Macro };

struct ModuleInfo {
  ModuleId parent = 0;
  std::string name;
  std::string canonical;
};

class Resolution {
public:
  ModuleId moduleOf(Span span) const;
  std::optional<std::uint32_t> packageOf(Span span) const;
  std::optional<std::uint32_t> nativePackage(std::string_view name) const;
  std::optional<std::uint32_t> packageIndex(std::string_view identity) const;
  std::optional<std::string> packageIdentity(std::uint32_t index) const;
  std::string canonical(Span span) const;
  bool accessible(Span declaration, ModuleId from) const;
  std::optional<std::string> lookup(ModuleId from, std::string_view spelling,
                                    Namespace space, Span use,
                                    Diagnostics *diagnostics = nullptr) const;
  const std::vector<ModuleInfo> &modules() const { return moduleInfos; }
  // Whether a lookup resolved through the binding that import `index` (the
  // position in `Module::imports`) made under `name`; an empty `name` asks
  // about any of its bindings (glob imports).
  bool importUsed(std::size_t index, std::string_view name = {}) const;

private:
  friend std::shared_ptr<const Resolution>
  resolve(const Module &, Diagnostics &, const SourcePackages &);
  friend class Resolver;
  struct Definition {
    Namespace space;
    ModuleId module;
    ModuleId boundary;
    std::string name, canonical;
    Span span;
    std::optional<ModuleId> target;
  };
  struct Binding {
    std::size_t definition;
    ModuleId boundary;
    bool explicitBinding;
    std::optional<std::size_t> import;
    // Bound by the prelude, not by an import declaration.
    bool prelude = false;
  };
  struct Scope {
    std::unordered_map<std::string, std::vector<Binding>> bindings;
    std::unordered_map<std::string, std::size_t> pendingExplicit;
  };
  struct Item {
    Span span;
    ModuleId module;
    std::string canonical;
    ModuleId boundary;
  };
  std::vector<ModuleInfo> moduleInfos;
  std::vector<Definition> definitions;
  std::vector<Scope> scopes;
  std::vector<Item> items;
  bool rawPackageInput = true;
  std::unordered_map<SourceId, std::uint32_t> sourcePackages;
  std::unordered_map<std::string, std::uint32_t> packageInstances;
  // Bindings that lookups went through, as (import index, local name).
  mutable std::set<std::pair<std::size_t, std::string>> usedImports;
  // Lookup indexes over `items`, built once after resolution completes.
  struct Interval {
    std::size_t begin, end, item;
    int parent;
  };
  std::unordered_map<SourceId, std::vector<Interval>> intervals;
  void index();
  const Item *exact(Span span) const;
  std::unordered_map<std::string, std::vector<std::size_t>> associatedItems;
  std::unordered_map<std::string, std::pair<ModuleId, std::string>>
      aliasTargets;
  std::optional<std::string> associatedType(std::string canonical) const;
  std::vector<std::size_t>
  associated(std::string canonical, std::string_view name, ModuleId from) const;
  bool inside(ModuleId module, ModuleId boundary) const;
  std::vector<std::size_t> find(ModuleId module, std::string_view name,
                                Namespace space, ModuleId from) const;
};

// Trees and their declarations remain syntax-only; all canonical identities
// live in this compilation-owned result.
std::shared_ptr<const Resolution> resolve(const Module &module,
                                          Diagnostics &diagnostics,
                                          const SourcePackages &packages = {});
} // namespace mettle::resolution
