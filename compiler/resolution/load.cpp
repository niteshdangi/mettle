#include "resolution/load.h"
#include "support/limits.h"
#include "syntax/parser.h"
#include <filesystem>
#include <iterator>
#include <unordered_map>
#include <unordered_set>

namespace mettle::resolution {
namespace {
namespace fs = std::filesystem;

template <typename Item>
void prepend(Item &item, const std::vector<std::string> &prefix) {
  item.item.scope.insert(item.item.scope.begin(), prefix.begin(), prefix.end());
}

template <typename Item>
void merge(std::vector<Item> &destination, std::vector<Item> source,
           const std::vector<std::string> &prefix) {
  for (auto &item : source) {
    prepend(item, prefix);
    destination.push_back(std::move(item));
  }
}

class Loader {
public:
  Loader(const SourceProvider &provider, Diagnostics &diagnostics)
      : provider(provider), diagnostics(diagnostics) {}

  std::optional<Module> run(Source root) {
    auto directory = fs::path(root.path).parent_path();
    read(std::move(root), {}, std::move(directory), 0);
    if (!diagnostics.empty())
      return std::nullopt;
    return std::move(result);
  }

private:
  const SourceProvider &provider;
  Diagnostics &diagnostics;
  Module result;
  std::unordered_set<std::string> loaded;
  SourceId nextSource = 0;

  void read(Source source, std::vector<std::string> prefix, fs::path directory,
            unsigned depth) {
    auto identity = fs::path(source.path).lexically_normal().generic_string();
    if (!loaded.insert(identity).second) {
      diagnostics.error("name", {},
                        "source file '" + source.path +
                            "' has more than one module identity");
      return;
    }
    if (depth > limits::parserNesting || loaded.size() > limits::products) {
      diagnostics.error("limit", {}, "module loading limit exceeded");
      return;
    }
    source.id = nextSource++;
    auto tree = parse(source, diagnostics);
    if (!diagnostics.empty())
      return;
    for (const auto &declaration : tree.modules) {
      if (!declaration.external)
        continue;
      auto childDirectory = directory;
      for (const auto &part : declaration.item.scope)
        childDirectory /= part;
      auto firstPath = childDirectory / (declaration.name + ".mt");
      auto secondPath = childDirectory / declaration.name / "module.mt";
      auto first = provider(firstPath.lexically_normal().generic_string());
      auto second = provider(secondPath.lexically_normal().generic_string());
      if (first.has_value() == second.has_value()) {
        diagnostics.error("name", declaration.span,
                          first ? "external module '" + declaration.name +
                                      "' matches both '" +
                                      firstPath.generic_string() + "' and '" +
                                      secondPath.generic_string() + "'"
                                : "external module '" + declaration.name +
                                      "' requires exactly one of '" +
                                      firstPath.generic_string() + "' or '" +
                                      secondPath.generic_string() + "'");
        continue;
      }
      auto childPrefix = prefix;
      childPrefix.insert(childPrefix.end(), declaration.item.scope.begin(),
                         declaration.item.scope.end());
      childPrefix.push_back(declaration.name);
      auto child = first ? std::move(*first) : std::move(*second);
      auto childIdentity =
          fs::path(child.path).lexically_normal().generic_string();
      if (loaded.contains(childIdentity)) {
        diagnostics.error(
            "name", declaration.span,
            "source file '" + child.path +
                "' has more than one module identity (or a module cycle)");
        continue;
      }
      read(std::move(child), std::move(childPrefix),
           childDirectory / declaration.name, depth + 1);
    }
    auto implementationOffset = static_cast<int>(result.implementations.size());
    for (auto &implementation : tree.implementations)
      for (auto &function : implementation.methodFunctions)
        function += result.functions.size();
    for (auto &function : tree.functions)
      if (function.implementation >= 0)
        function.implementation += implementationOffset;
    merge(result.interfaces, std::move(tree.interfaces), prefix);
    merge(result.implementations, std::move(tree.implementations), prefix);
    merge(result.functions, std::move(tree.functions), prefix);
    merge(result.statics, std::move(tree.statics), prefix);
    merge(result.products, std::move(tree.products), prefix);
    merge(result.aliases, std::move(tree.aliases), prefix);
    merge(result.modules, std::move(tree.modules), prefix);
    merge(result.imports, std::move(tree.imports), prefix);
    for (auto &assembly : tree.globalAssembly)
      result.globalAssembly.push_back(std::move(assembly));
    result.tokens.insert(result.tokens.end(),
                         std::make_move_iterator(tree.tokens.begin()),
                         std::make_move_iterator(tree.tokens.end()));
  }
};
} // namespace

std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Loader(provider, diagnostics).run(std::move(root));
}

std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics) {
  if (sources.empty()) {
    diagnostics.error("io", {}, "a compilation requires a root source");
    return std::nullopt;
  }
  std::unordered_map<std::string, const Source *> catalog;
  for (const auto &source : sources) {
    auto identity = fs::path(source.path).lexically_normal().generic_string();
    if (!catalog.emplace(identity, &source).second) {
      diagnostics.error("io", {},
                        "duplicate source identity in source catalog: " +
                            source.path);
      return std::nullopt;
    }
  }
  SourceProvider provider =
      [&](const std::string &path) -> std::optional<Source> {
    auto found =
        catalog.find(fs::path(path).lexically_normal().generic_string());
    return found == catalog.end() ? std::nullopt
                                  : std::optional<Source>(*found->second);
  };
  return load(sources.front(), provider, diagnostics);
}
} // namespace mettle::resolution
