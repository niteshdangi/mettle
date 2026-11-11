#include "resolution/resolve.h"
#include <algorithm>
#include <limits>
#include <unordered_set>

namespace mettle::resolution {
namespace {
constexpr ModuleId publicBoundary = std::numeric_limits<ModuleId>::max();

std::string key(Namespace space, std::string_view name) {
  char prefix = space == Namespace::Value   ? 'v'
                : space == Namespace::Macro ? 'm'
                                            : 't';
  return std::string(1, prefix) + ":" + std::string(name);
}
std::vector<std::string> components(std::string_view spelling) {
  std::vector<std::string> result;
  for (;;) {
    auto separator = spelling.find("::");
    result.emplace_back(spelling.substr(0, separator));
    if (separator == std::string_view::npos)
      return result;
    spelling.remove_prefix(separator + 2);
  }
}
std::string join(const std::vector<std::string> &path) {
  std::string result;
  for (const auto &part : path) {
    if (!result.empty())
      result += "::";
    result += part;
  }
  return result;
}
} // namespace

bool Resolution::inside(ModuleId module, ModuleId boundary) const {
  if (boundary == publicBoundary)
    return true;
  if (module == publicBoundary)
    return false;
  for (;;) {
    if (module == boundary)
      return true;
    if (module == 0)
      return false;
    module = moduleInfos[module].parent;
  }
}

std::optional<std::uint32_t> Resolution::packageOf(Span span) const {
  if (span.begin >= span.end)
    return std::nullopt;
  if (auto found = sourcePackages.find(span.source);
      found != sourcePackages.end())
    return found->second;
  if (rawPackageInput && intervals.contains(span.source))
    return 0;
  return std::nullopt;
}

std::optional<std::uint32_t>
Resolution::nativePackage(std::string_view name) const {
  if (name != "core" && name != "alloc" && name != "std")
    return std::nullopt;
  auto found = packageInstances.find("native:standard-library");
  return found == packageInstances.end()
             ? std::nullopt
             : std::optional<std::uint32_t>(found->second);
}

std::optional<std::uint32_t>
Resolution::packageIndex(std::string_view identity) const {
  auto found = packageInstances.find(std::string(identity));
  if (found != packageInstances.end())
    return found->second;
  if (rawPackageInput && identity == "raw-root")
    return 0;
  return std::nullopt;
}

std::optional<std::string>
Resolution::packageIdentity(std::uint32_t index) const {
  for (const auto &[identity, candidate] : packageInstances)
    if (candidate == index)
      return identity;
  if (rawPackageInput && index == 0)
    return "raw-root";
  return std::nullopt;
}

void Resolution::index() {
  intervals.clear();
  for (std::size_t i = 0; i < items.size(); ++i)
    intervals[items[i].span.source].push_back(
        {items[i].span.begin, items[i].span.end, i, -1});
  for (auto &[source, list] : intervals) {
    std::stable_sort(
        list.begin(), list.end(), [](const Interval &a, const Interval &b) {
          return a.begin != b.begin ? a.begin < b.begin : a.end > b.end;
        });
    std::vector<int> open;
    for (std::size_t i = 0; i < list.size(); ++i) {
      while (!open.empty() && list[open.back()].end < list[i].end &&
             list[open.back()].end <= list[i].begin)
        open.pop_back();
      while (!open.empty() && list[open.back()].end < list[i].end)
        open.pop_back();
      list[i].parent = open.empty() ? -1 : open.back();
      open.push_back(static_cast<int>(i));
    }
  }
}

const Resolution::Item *Resolution::exact(Span span) const {
  auto found = intervals.find(span.source);
  if (found == intervals.end())
    return nullptr;
  const auto &list = found->second;
  auto first = std::lower_bound(list.begin(), list.end(), span.begin,
                                [](const Interval &entry, std::size_t begin) {
                                  return entry.begin < begin;
                                });
  for (; first != list.end() && first->begin == span.begin; ++first)
    if (first->end == span.end)
      return &items[first->item];
  return nullptr;
}

ModuleId Resolution::moduleOf(Span span) const {
  auto found = intervals.find(span.source);
  if (found == intervals.end())
    return 0;
  const auto &list = found->second;
  auto after = std::upper_bound(list.begin(), list.end(), span.begin,
                                [](std::size_t begin, const Interval &entry) {
                                  return begin < entry.begin;
                                });
  // Items nest or are disjoint, so the innermost enclosing item is the nearest
  // ancestor, starting at the last item that begins at or before the span.
  for (int i = static_cast<int>(after - list.begin()) - 1; i >= 0;
       i = list[i].parent)
    if (list[i].end >= span.end) {
      // Equal-length duplicates resolve to the earliest declared item.
      auto best = i;
      while (best > 0 && list[best - 1].begin == list[i].begin &&
             list[best - 1].end == list[i].end)
        --best;
      return items[list[best].item].module;
    }
  return 0;
}

std::string Resolution::canonical(Span span) const {
  if (const auto *item = exact(span))
    return item->canonical;
  return {};
}
bool Resolution::accessible(Span declaration, ModuleId from) const {
  if (const auto *item = exact(declaration))
    return inside(from, item->boundary);
  return false;
}

std::vector<std::size_t> Resolution::find(ModuleId module,
                                          std::string_view name,
                                          Namespace space,
                                          ModuleId from) const {
  std::vector<std::size_t> result;
  auto found = scopes[module].bindings.find(key(space, name));
  if (found == scopes[module].bindings.end())
    return result;
  bool explicitPresent = std::any_of(
      found->second.begin(), found->second.end(),
      [](const Binding &binding) { return binding.explicitBinding; });
  if (!explicitPresent &&
      scopes[module].pendingExplicit.contains(std::string(name)))
    return result;
  for (const auto &binding : found->second) {
    const auto &definition = definitions[binding.definition];
    if ((explicitPresent && !binding.explicitBinding) ||
        !inside(from, binding.boundary) ||
        (space == Namespace::Module && !definition.target) ||
        (space == Namespace::Type && definition.target))
      continue;
    if (binding.import && !binding.prelude)
      usedImports.emplace(*binding.import, std::string(name));
    if (std::find(result.begin(), result.end(), binding.definition) ==
        result.end())
      result.push_back(binding.definition);
  }
  return result;
}

bool Resolution::importUsed(std::size_t index, std::string_view name) const {
  if (!name.empty())
    return usedImports.contains({index, std::string(name)});
  auto first = usedImports.lower_bound({index, std::string()});
  return first != usedImports.end() && first->first == index;
}

std::optional<std::string>
Resolution::associatedType(std::string canonical) const {
  std::unordered_set<std::string> visited;
  for (;;) {
    auto alias = aliasTargets.find(canonical);
    if (alias == aliasTargets.end())
      return canonical;
    if (!visited.insert(canonical).second)
      return std::nullopt;
    auto target = lookup(alias->second.first, alias->second.second,
                         Namespace::Type, {}, nullptr);
    if (!target)
      return std::nullopt;
    canonical = *target;
  }
}

std::vector<std::size_t> Resolution::associated(std::string canonical,
                                                std::string_view name,
                                                ModuleId from) const {
  auto type = associatedType(std::move(canonical));
  if (!type)
    return {};
  auto found = associatedItems.find(*type);
  if (found == associatedItems.end())
    return {};
  std::vector<std::size_t> matches;
  for (auto index : found->second)
    if (definitions[index].name == name &&
        inside(from, definitions[index].boundary))
      matches.push_back(index);
  return matches;
}

std::optional<std::string> Resolution::lookup(ModuleId from,
                                              std::string_view spelling,
                                              Namespace space, Span use,
                                              Diagnostics *diagnostics) const {
  if (from >= moduleInfos.size())
    return std::nullopt;
  auto path = components(spelling);
  ModuleId scope = from;
  std::size_t position = 0;
  if (path[0] == "package") {
    while (scope != 0 && moduleInfos[scope].parent != 0)
      scope = moduleInfos[scope].parent;
    if (scope == 0 || !moduleInfos[scope].name.starts_with("mettle_pkg_"))
      scope = 0;
    ++position;
  } else if (path[0].starts_with("mettle_pkg_")) {
    scope = 0;
  } else if (path[0] == "self") {
    ++position;
  } else if (path.size() > 1 &&
             (path[0] == "core" || path[0] == "alloc" || path[0] == "std") &&
             find(scope, path[0], Namespace::Module, from).empty()) {
    // A mounted library root is reachable from every module unless shadowed.
    scope = 0;
  }
  if (position == 0 && path[0] != "super" &&
      find(scope, path[0], path.size() > 1 ? Namespace::Module : space, from)
          .empty()) {
    auto root = scope;
    while (root != 0 && moduleInfos[root].parent != 0)
      root = moduleInfos[root].parent;
    if (root == 0 || !moduleInfos[root].name.starts_with("mettle_pkg_"))
      root = 0;
    auto aliases = find(root, path[0], Namespace::Module, from);
    if (!aliases.empty() &&
        std::all_of(aliases.begin(), aliases.end(), [&](auto index) {
          const auto &definition = definitions[index];
          return definition.target &&
                 moduleInfos[*definition.target].parent == 0 &&
                 definition.canonical.starts_with("mettle_pkg_");
        }))
      scope = root;
  }
  while (position < path.size() && path[position] == "super") {
    if (scope == 0) {
      if (diagnostics)
        diagnostics->error("name", use, "'super' escapes the package root");
      return std::nullopt;
    }
    scope = moduleInfos[scope].parent;
    ++position;
  }
  for (; position < path.size(); ++position) {
    bool last = position + 1 == path.size();
    auto matches =
        find(scope, path[position], last ? space : Namespace::Module, from);
    if (!last && matches.empty() && position + 2 == path.size() &&
        space == Namespace::Value) {
      auto types = find(scope, path[position], Namespace::Type, from);
      if (types.size() == 1) {
        matches =
            associated(definitions[types.front()].canonical, path.back(), from);
        if (matches.size() == 1)
          return definitions[matches.front()].canonical;
      }
    }
    if (matches.size() != 1) {
      if (diagnostics)
        diagnostics->error("name", use,
                           matches.empty()
                               ? "unresolved or inaccessible name '" +
                                     std::string(spelling) + "'"
                               : "ambiguous import for '" +
                                     std::string(spelling) + "'");
      return std::nullopt;
    }
    const auto &definition = definitions[matches.front()];
    if (last)
      return definition.canonical;
    scope = *definition.target;
  }
  if (space == Namespace::Module)
    return moduleInfos[scope].canonical;
  if (diagnostics)
    diagnostics->error("name", use,
                       "module path does not name a type or value");
  return std::nullopt;
}

class Resolver {
public:
  Resolver(const Module &tree, Diagnostics &diagnostics,
           const SourcePackages &packages)
      : tree(tree), diagnostics(diagnostics) {
    result.rawPackageInput = packages.empty();
    for (const auto &[source, identity] : packages) {
      if (identity.empty())
        continue;
      auto [instance, inserted] = result.packageInstances.try_emplace(
          identity, static_cast<std::uint32_t>(result.packageInstances.size()));
      (void)inserted;
      result.sourcePackages.emplace(source, instance->second);
    }
    result.moduleInfos.push_back({0, "", ""});
    result.scopes.emplace_back();
    result.definitions.push_back(
        {Namespace::Module, 0, publicBoundary, "package", "", {}, 0});
    moduleNames.emplace("", 0);
  }

  std::shared_ptr<const Resolution> run() {
    collectModules();
    collectItems();
    collectAssociatedConstants();
    imports();
    if (!diagnostics.empty())
      return {};
    prelude();
    collectAssociatedFunctions();
    collectAssociatedConstants();
    if (!diagnostics.empty())
      return {};
    result.index();
    return std::make_shared<const Resolution>(std::move(result));
  }

private:
  const Module &tree;
  Diagnostics &diagnostics;
  Resolution result;
  std::unordered_map<std::string, ModuleId> moduleNames;
  std::unordered_set<std::string> diagnosed;
  std::unordered_set<const Module::Associated *> collectedAssociatedConstants;
  std::unordered_set<std::size_t> associatedConstantDefinitions;
  struct AssociatedFunction {
    const Function *function;
    std::size_t definition, item;
    std::string owner;
  };
  std::vector<AssociatedFunction> associatedFunctions;

  ModuleId scope(const std::vector<std::string> &path) {
    std::vector<std::string> prefix;
    ModuleId parent = 0;
    for (const auto &part : path) {
      prefix.push_back(part);
      auto canonical = join(prefix);
      auto found = moduleNames.find(canonical);
      if (found != moduleNames.end()) {
        parent = found->second;
        continue;
      }
      auto id = static_cast<ModuleId>(result.moduleInfos.size());
      result.moduleInfos.push_back({parent, part, canonical});
      result.scopes.emplace_back();
      moduleNames.emplace(canonical, id);
      parent = id;
    }
    return parent;
  }

  ModuleId boundary(const ItemSyntax &item, ModuleId module, Span span) {
    const auto &visibility = item.visibility;
    if (!visibility.publicItem)
      return module;
    if (visibility.restriction.empty())
      return publicBoundary;
    auto path = visibility.restriction;
    ModuleId current = module;
    ModuleId package = module;
    while (package != 0 && result.moduleInfos[package].parent != 0)
      package = result.moduleInfos[package].parent;
    if (package == 0 ||
        !result.moduleInfos[package].name.starts_with("mettle_pkg_"))
      package = 0;
    std::size_t position = 0;
    if (path[0] == "package") {
      current = package;
      ++position;
    } else if (path[0] == "self") {
      ++position;
    } else if (path[0] != "super") {
      current = package;
    }
    while (position < path.size() && path[position] == "super") {
      if (current == package) {
        diagnostics.error("name", span,
                          "visibility restriction escapes the package root");
        return module;
      }
      current = result.moduleInfos[current].parent;
      ++position;
    }
    auto canonical = result.moduleInfos[current].canonical;
    for (; position < path.size(); ++position) {
      if (!canonical.empty())
        canonical += "::";
      canonical += path[position];
    }
    auto found = moduleNames.find(canonical);
    if (found == moduleNames.end() || !result.inside(module, found->second)) {
      diagnostics.error("name", visibility.span,
                        "restricted visibility must name an enclosing module");
      return module;
    }
    return found->second;
  }

  void duplicate(Span span, std::string_view name) {
    diagnostics.error("name", span,
                      "duplicate explicit binding '" + std::string(name) + "'");
  }

  void define(Namespace space, ModuleId module, ModuleId visible,
              std::string name, std::string canonical, Span span,
              std::optional<ModuleId> target = {}) {
    auto &bindings = result.scopes[module].bindings[key(space, name)];
    if (!bindings.empty()) {
      auto kind = space == Namespace::Type     ? "type"
                  : space == Namespace::Macro  ? "macro"
                  : space == Namespace::Module ? "module"
                                               : "function or value binding";
      diagnostics.error("name", span,
                        "duplicate " + std::string(kind) + " '" + name + "'");
      return;
    }
    auto id = result.definitions.size();
    result.definitions.push_back({space, module, visible, std::move(name),
                                  std::move(canonical), span, target});
    bindings.push_back({id, visible, true, {}});
  }

  void collectModules() {
    for (const auto &declaration : tree.modules) {
      auto path = declaration.item.scope;
      path.push_back(declaration.name);
      scope(path);
    }
    for (const auto &declaration : tree.modules) {
      auto parent = scope(declaration.item.scope);
      auto path = declaration.item.scope;
      path.push_back(declaration.name);
      auto child = scope(path);
      auto visible = boundary(declaration.item, parent, declaration.span);
      define(Namespace::Module, parent, visible, declaration.name,
             result.moduleInfos[child].canonical, declaration.span, child);
      result.items.push_back({declaration.span, parent,
                              result.moduleInfos[child].canonical, visible});
    }
  }

  std::string itemName(ModuleId module, std::string_view name) const {
    auto prefix = result.moduleInfos[module].canonical;
    return prefix.empty() ? std::string(name)
                          : prefix + "::" + std::string(name);
  }

  void collectItems() {
    for (const auto &macro : tree.macros) {
      auto module = scope(macro.item.scope);
      auto visible = boundary(macro.item, module, macro.span);
      auto name = itemName(module, macro.name);
      result.items.push_back({macro.span, module, name, visible});
      define(Namespace::Macro, module, visible, macro.name, name, macro.span);
    }
    for (const auto &storage : tree.statics) {
      auto module = scope(storage.item.scope);
      auto visible = boundary(storage.item, module, storage.span);
      auto name = itemName(module, storage.name);
      result.items.push_back({storage.span, module, name, visible});
      define(Namespace::Value, module, visible, storage.name, name,
             storage.span);
    }
    for (const auto &interface : tree.interfaces) {
      auto module = scope(interface.item.scope);
      auto visible = boundary(interface.item, module, interface.span);
      auto name = itemName(module, interface.name);
      result.items.push_back({interface.span, module, name, visible});
      define(Namespace::Type, module, visible, interface.name, name,
             interface.span);
      result.associatedItems.try_emplace(name);
    }
    for (std::size_t i = 0; i < tree.implementations.size(); ++i) {
      const auto &implementation = tree.implementations[i];
      if (implementation.shorthand)
        continue;
      auto module = scope(implementation.item.scope);
      result.items.push_back(
          {implementation.span, module,
           itemName(module, "<impl." + std::to_string(i) + ">"),
           boundary(implementation.item, module, implementation.span)});
    }
    for (const auto &product : tree.products) {
      auto module = scope(product.item.scope);
      auto visible = boundary(product.item, module, product.span);
      auto name = itemName(module, product.name);
      result.associatedItems.try_emplace(name);
      result.items.push_back({product.span, module, name, visible});
      define(Namespace::Type, module, visible, product.name, name,
             product.span);
      if (!product.enumeration)
        define(Namespace::Value, module, visible, product.name, name,
               product.span);
      for (const auto &variant : product.variants) {
        auto index = result.definitions.size();
        result.definitions.push_back({Namespace::Value,
                                      module,
                                      visible,
                                      variant.name,
                                      name + "::" + variant.name,
                                      variant.span,
                                      {}});
        result.associatedItems[name].push_back(index);
        result.items.push_back(
            {variant.span, module, name + "::" + variant.name, visible});
      }
      for (const auto &field : product.fields) {
        ItemSyntax item{product.item.scope, field.visibility};
        result.items.push_back(
            {field.span, module, {}, boundary(item, module, field.span)});
      }
    }
    for (const auto &alias : tree.aliases) {
      auto module = scope(alias.item.scope);
      auto name = itemName(module, alias.name);
      auto visible = boundary(alias.item, module, alias.span);
      result.items.push_back({alias.span, module, name, visible});
      define(Namespace::Type, module, visible, alias.name, name, alias.span);
      if (!alias.target.name.empty() && !alias.target.nested &&
          alias.target.view.empty() && alias.target.form == TypeForm::Named)
        result.aliasTargets.emplace(name, std::pair{module, alias.target.name});
    }
    for (const auto &function : tree.functions) {
      auto module = scope(function.item.scope);
      auto name = itemName(module, function.name);
      auto visible = boundary(function.item, module, function.span);
      auto item = result.items.size();
      result.items.push_back({function.span, module, name, visible});
      if (function.owner.empty())
        define(Namespace::Value, module, visible, function.name, name,
               function.span);
      else if (!function.destructor && !function.constructor &&
               (function.implementation < 0 ||
                (function.receiver == "static" &&
                 tree.implementations[static_cast<std::size_t>(
                                          function.implementation)]
                     .interface.name.empty()))) {
        auto delimiter = function.name.rfind('.');
        auto member = function.name.substr(delimiter + 1);
        auto index = result.definitions.size();
        result.definitions.push_back({Namespace::Value,
                                      module,
                                      visible,
                                      member,
                                      name,
                                      function.span,
                                      {}});
        auto owner = itemName(module, function.owner);
        result.associatedItems[owner].push_back(index);
        associatedFunctions.push_back({&function, index, item, owner});
      }
    }
  }

  bool collectAssociatedFunctions() {
    bool changed = false;
    for (auto &entry : associatedFunctions) {
      auto module = scope(entry.function->item.scope);
      auto owner = result.lookup(module, entry.function->owner, Namespace::Type,
                                 entry.function->span, nullptr);
      if (!owner)
        continue;
      auto canonical = result.associatedType(*owner);
      if (!canonical || *canonical == entry.owner)
        continue;
      auto &old = result.associatedItems[entry.owner];
      std::erase(old, entry.definition);
      for (auto index : result.associatedItems[*canonical])
        if (associatedConstantDefinitions.contains(index) &&
            result.definitions[index].name ==
                result.definitions[entry.definition].name)
          diagnostics.error("name", result.definitions[index].span,
                            "duplicate associated item '" +
                                result.definitions[index].name + "'");
      result.associatedItems[*canonical].push_back(entry.definition);
      auto &definition = result.definitions[entry.definition];
      definition.canonical = *canonical + "::" + definition.name;
      result.items[entry.item].canonical = definition.canonical;
      entry.owner = *canonical;
      changed = true;
    }
    return changed;
  }

  bool collectAssociatedConstants() {
    bool changed = false;
    for (const auto &implementation : tree.implementations) {
      if (!implementation.interface.empty() || implementation.negative)
        continue;
      auto module = scope(implementation.item.scope);
      auto owner = result.lookup(module, implementation.target.name,
                                 Namespace::Type, implementation.span, nullptr);
      if (!owner)
        continue;
      auto canonicalOwner = result.associatedType(*owner);
      if (!canonicalOwner)
        continue;
      auto &members = result.associatedItems[*canonicalOwner];
      for (const auto &associated : implementation.associated) {
        if (!associated.constant ||
            !collectedAssociatedConstants.insert(&associated).second)
          continue;
        if (std::any_of(members.begin(), members.end(), [&](auto index) {
              return result.definitions[index].name == associated.name;
            })) {
          diagnostics.error("name", associated.span,
                            "duplicate associated item '" + associated.name +
                                "'");
          continue;
        }
        ItemSyntax item{implementation.item.scope, associated.visibility, {}};
        auto visible = boundary(item, module, associated.span);
        auto canonical = *canonicalOwner + "::" + associated.name;
        auto index = result.definitions.size();
        result.definitions.push_back({Namespace::Value,
                                      module,
                                      visible,
                                      associated.name,
                                      canonical,
                                      associated.span,
                                      {}});
        associatedConstantDefinitions.insert(index);
        members.push_back(index);
        result.items.push_back(
            {associated.span, module, std::move(canonical), visible});
        changed = true;
      }
    }
    return changed;
  }

  struct Target {
    std::size_t definition;
    ModuleId boundary;
  };
  std::vector<Target> targets(ModuleId from,
                              const std::vector<std::string> &path,
                              bool moduleOnly = false) {
    std::vector<Target> resultTargets;
    auto spelling = join(path);
    for (auto space : {Namespace::Type, Namespace::Value, Namespace::Module,
                       Namespace::Macro}) {
      if (moduleOnly && space != Namespace::Module)
        continue;
      auto canonical = result.lookup(from, spelling, space, {}, nullptr);
      if (!canonical)
        continue;
      for (std::size_t i = 0; i < result.definitions.size(); ++i) {
        const auto &definition = result.definitions[i];
        if (definition.space == space && definition.canonical == *canonical) {
          resultTargets.push_back({i, definition.boundary});
          break;
        }
      }
    }
    return resultTargets;
  }

  bool bind(ModuleId module, std::string_view name, Target target,
            ModuleId visible, bool explicitBinding, Span span,
            std::size_t importIndex, bool prelude = false) {
    const auto &definition = result.definitions[target.definition];
    auto &bindings =
        result.scopes[module].bindings[key(definition.space, name)];
    for (const auto &binding : bindings)
      if (binding.definition == target.definition &&
          binding.explicitBinding == explicitBinding &&
          binding.boundary == visible &&
          (!explicitBinding || binding.import == importIndex ||
           (binding.import && tree.imports[*binding.import].synthesized) ||
           tree.imports[importIndex].synthesized))
        return false;
    if (explicitBinding &&
        std::any_of(bindings.begin(), bindings.end(),
                    [](const auto &entry) { return entry.explicitBinding; })) {
      auto identity =
          std::to_string(importIndex) + ":" + key(definition.space, name);
      if (diagnosed.insert(identity).second)
        duplicate(span, name);
      return false;
    }
    if (!result.inside(visible, target.boundary)) {
      auto identity = "visibility:" + std::to_string(importIndex) + ":" +
                      key(definition.space, name);
      if (diagnosed.insert(identity).second)
        diagnostics.error("name", span,
                          "cannot reexport private or restricted item '" +
                              std::string(name) + "'");
      return false;
    }
    bindings.push_back(
        {target.definition, visible, explicitBinding, importIndex, prelude});
    return true;
  }

  bool import(const Module::Import &declaration, std::size_t index,
              bool &resolved) {
    auto module = scope(declaration.item.scope);
    auto visible = boundary(declaration.item, module, declaration.span);
    bool changed = false;
    if (declaration.glob) {
      auto target = targets(module, declaration.path, true);
      if (target.size() != 1) {
        auto type = result.lookup(module, join(declaration.path),
                                  Namespace::Type, declaration.span);
        auto canonical = type ? result.associatedType(*type) : std::nullopt;
        if (!canonical || !result.associatedItems.contains(*canonical))
          return false;
        resolved = true;
        for (auto definition : result.associatedItems.at(*canonical)) {
          const auto &entry = result.definitions[definition];
          if (result.inside(module, entry.boundary))
            changed |= bind(module, entry.name, {definition, entry.boundary},
                            visible, false, declaration.span, index);
        }
        return changed;
      }
      resolved = true;
      auto imported = *result.definitions[target[0].definition].target;
      // Copy before insertion: self/glob cycles may mutate this same scope.
      auto entries = result.scopes[imported].bindings;
      for (const auto &[bindingKey, bindings] : entries) {
        auto name = std::string_view(bindingKey).substr(2);
        bool explicitPresent = std::any_of(
            bindings.begin(), bindings.end(),
            [](const auto &entry) { return entry.explicitBinding; });
        if (!explicitPresent &&
            result.scopes[imported].pendingExplicit.contains(std::string(name)))
          continue;
        for (const auto &entry : bindings)
          if ((!explicitPresent || entry.explicitBinding) &&
              result.inside(module, entry.boundary))
            changed |= bind(module, name, {entry.definition, entry.boundary},
                            visible, false, declaration.span, index);
      }
    } else if (!declaration.names.empty()) {
      resolved = true;
      for (const auto &entry : declaration.names) {
        auto path = declaration.path;
        path.push_back(entry.name);
        auto found = targets(module, path);
        if (found.empty())
          resolved = false;
        auto name = entry.alias.empty() ? entry.name : entry.alias;
        for (auto target : found)
          changed |=
              bind(module, name, target, visible, true, entry.span, index);
      }
    } else {
      auto found =
          targets(declaration.synthesized ? 0 : module, declaration.path);
      if (found.empty())
        return false;
      resolved = true;
      auto name = declaration.alias.empty() ? declaration.path.back()
                                            : declaration.alias;
      for (auto target : found)
        changed |=
            bind(module, name, target, visible, true, declaration.span, index);
    }
    return changed;
  }

  // Bind the prelude last, only where a module declares or imports nothing of
  // that name, so every explicit and glob binding shadows it.
  void prelude() {
    const auto &roots = tree.prelude.libraryRoots;
    for (const auto &path : tree.prelude.names) {
      auto found = targets(0, path);
      for (ModuleId module = 0; module < result.scopes.size(); ++module) {
        const auto &canonical = result.moduleInfos[module].canonical;
        auto root = canonical.substr(0, canonical.find("::"));
        if (std::find(roots.begin(), roots.end(), root) != roots.end())
          continue;
        for (auto target : found) {
          const auto &definition = result.definitions[target.definition];
          if (!result.scopes[module].bindings.contains(
                  key(definition.space, path.back())))
            bind(module, path.back(), target, module, false, {}, 0, true);
        }
      }
    }
  }

  void imports() {
    std::vector<bool> resolved(tree.imports.size());
    auto reserve = [&](const Module::Import &declaration, bool add) {
      if (declaration.glob)
        return;
      auto module = scope(declaration.item.scope);
      auto &pending = result.scopes[module].pendingExplicit;
      auto update = [&](const std::string &name) {
        if (add)
          ++pending[name];
        else if (--pending.at(name) == 0)
          pending.erase(name);
      };
      if (declaration.names.empty())
        update(declaration.alias.empty() ? declaration.path.back()
                                         : declaration.alias);
      else
        for (const auto &entry : declaration.names)
          update(entry.alias.empty() ? entry.name : entry.alias);
    };
    for (const auto &declaration : tree.imports)
      reserve(declaration, true);
    bool changed;
    do {
      changed = collectAssociatedFunctions();
      changed |= collectAssociatedConstants();
      for (std::size_t i = 0; i < tree.imports.size(); ++i) {
        bool complete = false;
        changed |= import(tree.imports[i], i, complete);
        if (complete && !resolved[i]) {
          reserve(tree.imports[i], false);
          resolved[i] = true;
          changed = true;
        }
      }
    } while (changed);
    for (std::size_t i = 0; i < tree.imports.size(); ++i)
      if (!resolved[i])
        diagnostics.error(
            "name", tree.imports[i].span,
            "unresolved, inaccessible, ambiguous or cyclic import '" +
                join(tree.imports[i].path) + "'");
    for (const auto &declaration : tree.imports) {
      auto module = scope(declaration.item.scope);
      result.items.push_back(
          {declaration.span,
           module,
           {},
           boundary(declaration.item, module, declaration.span)});
    }
  }
};

std::shared_ptr<const Resolution> resolve(const Module &module,
                                          Diagnostics &diagnostics,
                                          const SourcePackages &packages) {
  if (!diagnostics.empty())
    return {};
  return Resolver(module, diagnostics, packages).run();
}
} // namespace mettle::resolution
