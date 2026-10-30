#include "resolution/load.h"
#include "expansion/macros.h"
#include "support/limits.h"
#include "syntax/parser.h"
#include <filesystem>
#include <iterator>
#include <set>
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
  Loader(const SourceProvider &provider, Diagnostics &diagnostics,
         const Library &library)
      : provider(provider), diagnostics(diagnostics), library(library) {}

  std::optional<Module> run(Source root) {
    auto directory = fs::path(root.path).parent_path();
    read(std::move(root), {}, std::move(directory), 0);
    for (const auto &package : library.packages) {
      if (!diagnostics.empty())
        break;
      mountPackage(package);
    }
    if (diagnostics.empty() && !library.directory.empty())
      mountLibraries();
    if (!diagnostics.empty())
      return std::nullopt;
    return std::move(result);
  }

private:
  const SourceProvider &provider;
  Diagnostics &diagnostics;
  const Library &library;
  Module result;
  std::unordered_set<std::string> loaded;
  SourceId nextSource = 0;
  // Library root that owns each loaded source; user sources are absent.
  std::unordered_map<SourceId, std::string> owner;
  std::string currentRoot;
  std::set<std::string> mounted, shadowed;
  // Package being mounted, if any; its sources are user code.
  const Library::Package *currentPackage = nullptr;
  // Expansion facts per dependency package; the empty key is the libraries'.
  std::unordered_map<std::string, expansion::Configuration> configurations;
  struct Names {
    bool any = false;
    std::set<std::string> names;
  };
  std::unordered_map<std::string, Names> declared;
  std::unordered_map<std::string, bool> availability;
  std::unordered_map<std::string, std::string> methods;
  bool builtinMethodsLoaded = false;
  std::size_t scanned = 0, scannedLiterals = 0;

  struct Reference {
    std::string root, member, from;
    Span span;
    bool text = false;
  };

  static bool libraryRoot(const std::string &name) {
    return name == "core" || name == "alloc" || name == "std";
  }
  // Names visible in every user module without an import; the first path
  // component is the library root that supplies each one.
  static const std::vector<std::vector<std::string>> &preludeNames() {
    static const std::vector<std::vector<std::string>> names{
        {"core", "text", "Text"},
        {"core", "iter", "Iterator"},
        {"core", "iter", "IntoIterator"},
        {"core", "iter", "DoubleEndedIterator"},
        {"core", "iter", "Iterable"},
        {"core", "iter", "IterableMut"},
        {"core", "cmp", "PartialEq"},
        {"core", "cmp", "Eq"},
        {"core", "cmp", "PartialOrd"},
        {"core", "cmp", "Ord"},
        {"core", "cmp", "Ordering"},
        {"core", "panic", "panic"},
        {"core", "panic", "assert"},
        {"alloc", "string", "String"}};
    return names;
  }
  static int layer(const std::string &name) {
    return name == "core" ? 0 : name == "alloc" ? 1 : name == "std" ? 2 : 3;
  }

  // A library root exports the names it declares or re-exports; `core` is
  // mounted only for those, so `core::ptr` and the other compiler built-ins
  // never pull the library in.
  const Names &exported(const std::string &root) {
    auto found = declared.find(root);
    if (found != declared.end())
      return found->second;
    Names names;
    auto path = (fs::path(library.directory) / root / "module.mt")
                    .lexically_normal()
                    .generic_string();
    auto source = provider(path);
    Diagnostics scratch;
    if (!source)
      names.any = true;
    else {
      auto tree = parse(*source, scratch);
      names.any = !scratch.empty();
      for (const auto &item : tree.modules)
        names.names.insert(item.name);
      for (const auto &item : tree.products)
        names.names.insert(item.name);
      for (const auto &item : tree.interfaces)
        names.names.insert(item.name);
      for (const auto &item : tree.aliases)
        names.names.insert(item.name);
      for (const auto &item : tree.statics)
        names.names.insert(item.name);
      for (const auto &item : tree.functions)
        if (item.implementation < 0 && item.interfaceOwner.empty())
          names.names.insert(item.name);
      for (const auto &item : tree.imports) {
        names.any |= item.glob;
        if (!item.alias.empty())
          names.names.insert(item.alias);
        else if (item.names.empty() && !item.path.empty())
          names.names.insert(item.path.back());
        for (const auto &name : item.names)
          names.names.insert(name.alias.empty() ? name.name : name.alias);
      }
    }
    return declared.emplace(root, std::move(names)).first->second;
  }

  // Inherent methods that `core` defines on built-in types (optionals,
  // outcomes, slices), mapped to their defining module. Calling one needs the
  // library mounted even when the program names nothing from `core`.
  const std::unordered_map<std::string, std::string> &builtinMethods() {
    if (builtinMethodsLoaded)
      return methods;
    builtinMethodsLoaded = true;
    for (const char *module : {"option", "outcome", "slice"}) {
      auto source = provider(
          (fs::path(library.directory) / "core" / (std::string(module) + ".mt"))
              .lexically_normal()
              .generic_string());
      if (!source)
        continue;
      Diagnostics scratch;
      auto tree = parse(*source, scratch);
      if (!scratch.empty())
        continue;
      for (const auto &function : tree.functions)
        if (function.implementation >= 0 && function.interfaceOwner.empty())
          methods.emplace(function.name.substr(function.name.rfind('.') + 1),
                          module);
    }
    return methods;
  }

  bool available(const std::string &root) {
    auto [entry, inserted] = availability.try_emplace(root, false);
    if (inserted)
      entry->second =
          provider((fs::path(library.directory) / root / "module.mt")
                       .lexically_normal()
                       .generic_string())
              .has_value();
    return entry->second;
  }

  std::vector<Reference> references() {
    std::vector<const Token *> significant;
    for (auto i = scanned; i < result.tokens.size(); ++i) {
      auto kind = result.tokens[i].kind;
      if (kind != TokenKind::Space && kind != TokenKind::Comment &&
          kind != TokenKind::Newline)
        significant.push_back(&result.tokens[i]);
    }
    scanned = result.tokens.size();
    std::vector<Reference> found;
    auto from = [&](const Token &token) {
      auto entry = owner.find(token.span.source);
      return entry == owner.end() ? std::string() : entry->second;
    };
    for (auto i = scannedLiterals; i < result.textLiterals.size(); ++i) {
      auto span = result.textLiterals[i];
      auto entry = owner.find(span.source);
      found.push_back({"core", "text",
                       entry == owner.end() ? std::string() : entry->second,
                       span, true});
    }
    scannedLiterals = result.textLiterals.size();
    for (std::size_t i = 0; i < significant.size(); ++i) {
      const auto &token = *significant[i];
      if (token.kind == TokenKind::Word && from(token).empty() && i > 0 &&
          significant[i - 1]->text == "." && i + 1 < significant.size() &&
          significant[i + 1]->text == "(" && available("core")) {
        const auto &known = builtinMethods();
        if (auto method = known.find(token.text); method != known.end())
          found.push_back({"core", method->second, "", token.span, false});
      }
      if (token.kind == TokenKind::Word && from(token).empty() &&
          (i == 0 || (significant[i - 1]->text != "::" &&
                      significant[i - 1]->text != ".")))
        for (const auto &name : preludeNames())
          if (name.back() == token.text) {
            if (available(name[0]))
              found.push_back({name[0], name[1], "", token.span, false});
            break;
          }
      if (token.kind != TokenKind::Word || !libraryRoot(token.text) ||
          i + 1 >= significant.size() || significant[i + 1]->text != "::")
        continue;
      // `package::core::...` names the mounted root like a bare `core::...`.
      bool packageRooted = i > 1 && significant[i - 1]->text == "::" &&
                           significant[i - 2]->text == "package";
      if (i > 0 && !packageRooted &&
          (significant[i - 1]->text == "::" || significant[i - 1]->text == "."))
        continue;
      std::string member;
      if (i + 2 < significant.size() &&
          significant[i + 2]->kind == TokenKind::Word)
        member = significant[i + 2]->text;
      found.push_back({token.text, member, from(token), token.span, false});
    }
    return found;
  }

  void mountPackage(const Library::Package &package) {
    auto source = provider(package.source);
    if (!source) {
      if (diagnostics.empty())
        diagnostics.error("io", {},
                          "package '" + package.name + "' requires '" +
                              package.source + "'");
      return;
    }
    for (const auto &declaration : result.modules)
      if (declaration.item.scope.empty() && declaration.name == package.name) {
        diagnostics.error("name", declaration.span,
                          "module '" + package.name +
                              "' collides with the dependency package of the "
                              "same name");
        return;
      }
    Module::ModuleDeclaration declaration;
    declaration.name = package.name;
    declaration.item.visibility.publicItem = true;
    result.modules.push_back(std::move(declaration));
    auto directory = fs::path(source->path).parent_path();
    currentPackage = &package;
    read(std::move(*source), {package.name}, std::move(directory), 1);
    currentPackage = nullptr;
  }

  void mountLibraries() {
    for (const auto &declaration : result.modules)
      if (declaration.item.scope.empty())
        shadowed.insert(declaration.name);
    while ((scanned < result.tokens.size() ||
            scannedLiterals < result.textLiterals.size()) &&
           diagnostics.empty()) {
      for (const auto &reference : references()) {
        if (!reference.text && layer(reference.from) < 3 &&
            layer(reference.root) > layer(reference.from)) {
          diagnostics.error("name", reference.span,
                            "library module '" + reference.from +
                                "' may not depend on '" + reference.root +
                                "' (core <- alloc <- std)");
          return;
        }
        if (shadowed.contains(reference.root) ||
            mounted.contains(reference.root))
          continue;
        if (reference.root == "core" && !reference.text) {
          const auto &names = exported("core");
          if (!names.any && !names.names.contains(reference.member))
            continue;
        }
        if (reference.root == "std" && library.freestanding) {
          diagnostics.error("name", reference.span,
                            "library module 'std' is not available in a "
                            "freestanding build");
          return;
        }
        mount(reference.root, reference.span);
        if (!diagnostics.empty())
          return;
      }
    }
    // Without a user module shadowing `core` there is no prelude to offer.
    if (mounted.contains("core") && !shadowed.contains("core")) {
      for (const auto &name : preludeNames())
        if (mounted.contains(name[0]) && !shadowed.contains(name[0]))
          result.prelude.names.push_back(name);
      result.prelude.libraryRoots.assign(mounted.begin(), mounted.end());
    }
  }

  void mount(const std::string &root, Span span) {
    auto path =
        (fs::path(library.directory) / root / "module.mt").lexically_normal();
    auto source = provider(path.generic_string());
    if (!source) {
      if (diagnostics.empty())
        diagnostics.error("name", span,
                          "library module '" + root + "' requires '" +
                              path.generic_string() + "'");
      return;
    }
    mounted.insert(root);
    Module::ModuleDeclaration declaration;
    declaration.name = root;
    declaration.item.visibility.publicItem = true;
    result.modules.push_back(std::move(declaration));
    auto saved = currentRoot;
    currentRoot = root;
    read(std::move(*source), {root}, path.parent_path(), 1);
    currentRoot = saved;
  }

  // The root source tests the requested features, a dependency package its
  // resolved features and a standard library root none.
  const expansion::Configuration &configuration() {
    if (!currentPackage && currentRoot.empty())
      return library.configuration;
    auto key = currentPackage ? currentPackage->name : std::string{};
    auto found = configurations.find(key);
    if (found != configurations.end())
      return found->second;
    auto selected = library.configuration;
    selected.features =
        currentPackage ? currentPackage->features : std::set<std::string>{};
    return configurations.emplace(key, std::move(selected)).first->second;
  }

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
    if (!currentRoot.empty())
      owner[source.id] = currentRoot;
    // Declarative macros expand on the token level, before parsing.
    if (auto generated = expansion::expandMacros(source, diagnostics, [&] {
          auto id = nextSource++;
          if (!currentRoot.empty())
            owner[id] = currentRoot;
          return id;
        }))
      source = std::move(*generated);
    if (!diagnostics.empty())
      return;
    auto tree = parseDeclarations(source, diagnostics);
    if (!diagnostics.empty())
      return;
    // Expansion precedes member flattening and the external-module scan, so
    // inactive modules are never read and generated impls are flattened too.
    expansion::expand(tree, diagnostics, configuration(), [&] {
      auto id = nextSource++;
      if (!currentRoot.empty())
        owner[id] = currentRoot;
      return id;
    });
    if (!diagnostics.empty())
      return;
    completeDeclarations(tree);
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
    result.textLiterals.insert(result.textLiterals.end(),
                               tree.textLiterals.begin(),
                               tree.textLiterals.end());
    result.tokens.insert(result.tokens.end(),
                         std::make_move_iterator(tree.tokens.begin()),
                         std::make_move_iterator(tree.tokens.end()));
  }
};
} // namespace

std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics, const Library &library) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Loader(provider, diagnostics, library).run(std::move(root));
}

std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics, const Library &library) {
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
  return load(sources.front(), provider, diagnostics, library);
}
} // namespace mettle::resolution
