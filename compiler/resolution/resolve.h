#pragma once

#include "diagnostics/diagnostics.h"
#include "syntax/ast.h"
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mettle::resolution {
using ModuleId = std::uint32_t;
enum class Namespace { Type, Value, Module };

struct ModuleInfo {
  ModuleId parent = 0;
  std::string name;
  std::string canonical;
};

class Resolution {
public:
  ModuleId moduleOf(Span span) const;
  std::string canonical(Span span) const;
  bool accessible(Span declaration, ModuleId from) const;
  std::optional<std::string> lookup(ModuleId from, std::string_view spelling,
                                    Namespace space, Span use,
                                    Diagnostics *diagnostics = nullptr) const;
  const std::vector<ModuleInfo> &modules() const { return moduleInfos; }

private:
  friend std::shared_ptr<const Resolution> resolve(const Module &,
                                                   Diagnostics &);
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
                                          Diagnostics &diagnostics);
} // namespace mettle::resolution
