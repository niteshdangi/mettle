#include "resolution/load.h"
#include "expansion/harness.h"
#include "expansion/macros.h"
#include "support/limits.h"
#include "syntax/parser.h"
#include <algorithm>
#include <filesystem>
#include <iterator>
#include <map>
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
         const Library &library, std::vector<SourceModule> *sourceModules,
         std::vector<SourceModule> *allSources)
      : provider(provider), diagnostics(diagnostics), library(library),
        sourceModules(sourceModules), allSources(allSources) {}

  std::optional<Module> run(Source root) {
    auto directory = fs::path(root.path).parent_path();
    auto harnessPath =
        (directory / "mettle-test-harness.mt").lexically_normal();
    for (const auto &package : library.packages) {
      auto source = provider(package.source);
      if (!source)
        continue;
      auto name = package.module.empty() ? package.name : package.module;
      sourceId(*source);
      macroModules[{name}] = {fs::path(source->path).parent_path(),
                              source->path, source->id, std::nullopt};
    }
    // Library macros (`std.macros.dbg`) resolve before the libraries mount.
    if (!library.directory.empty())
      for (std::string libraryName : {"core", "alloc", "std"}) {
        auto path = (fs::path(library.directory) / libraryName / "module.mt")
                        .lexically_normal()
                        .generic_string();
        auto source = provider(path);
        if (!source)
          continue;
        sourceId(*source);
        macroModules.try_emplace({libraryName},
                                 MacroModuleLocation{
                                     fs::path(path).parent_path(), path,
                                     source->id, std::nullopt});
      }
    read(std::move(root), {}, directory, 0, true);
    if (library.harness != Library::Harness::None && diagnostics.empty()) {
      bool bench = library.harness == Library::Harness::Bench;
      read({harnessPath.generic_string(),
            expansion::harnessSource(result.tests, bench)},
           {}, std::move(directory), 1);
    }
    for (const auto &package : library.packages) {
      if (!diagnostics.empty())
        break;
      mountPackage(package);
    }
    if (diagnostics.empty()) {
      for (const auto &package : library.packages)
        for (const auto &[name, module] : package.dependencies)
          packageImport(package.module, name, module);
      std::map<std::string, std::vector<std::string>> roots;
      for (const auto &[name, module] : library.packageDependencies)
        roots[name].push_back(module);
      // Every resolved package is a root module named after it; a direct
      // alias wins, and an ambiguous transitive name (coexisting versions)
      // stays reachable only through its dependents.
      std::map<std::string, std::set<std::string>> transitive;
      for (const auto &package : library.packages) {
        auto name = package.name;
        std::replace(name.begin(), name.end(), '-', '_');
        bool local = std::any_of(result.modules.begin(), result.modules.end(),
                                 [&](const auto &declaration) {
                                   return declaration.item.scope.empty() &&
                                          declaration.name == name;
                                 });
        if (!roots.contains(name) && !local)
          transitive[name].insert(package.module);
      }
      for (const auto &[name, modules] : transitive)
        if (modules.size() == 1)
          roots[name].push_back(*modules.begin());
      for (const auto &[name, modules] : roots)
        for (const auto &module : modules)
          packageImport({}, name, module);
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
  std::vector<SourceModule> *sourceModules;
  std::vector<SourceModule> *allSources;
  Module result;
  std::unordered_set<std::string> loaded;
  std::set<std::vector<std::string>> knownModules;
  SourceId nextSource = 0;
  std::map<std::string, SourceId> sourceIds;
  struct MacroModuleLocation {
    fs::path directory;
    std::string sourcePath;
    SourceId sourceId = 0;
    std::optional<Source> rootSource;
  };
  std::map<std::vector<std::string>, MacroModuleLocation> macroModules;
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
  // Iterator methods; a call chained on `)` (as in `(0..n).fold(...)`) needs
  // `core` because the built-in range value is then a library range.
  std::unordered_set<std::string> iteratorMethods;
  bool builtinMethodsLoaded = false;
  std::size_t scanned = 0, scannedLiterals = 0;

  SourceId sourceId(Source &source) {
    auto identity = fs::path(source.path).lexically_normal().generic_string();
    auto [found, inserted] = sourceIds.emplace(identity, nextSource);
    if (inserted)
      ++nextSource;
    source.id = found->second;
    return source.id;
  }

  std::optional<expansion::MacroModuleSource>
  macroModule(const std::vector<std::string> &requested,
              const std::vector<std::string> &from) {
    auto path = requested;
    bool rooted = path.size() >= 2 && path.front() == "package";
    if (!path.empty()) {
      auto alias = path[rooted ? 1 : 0];
      std::replace(alias.begin(), alias.end(), '-', '_');
      std::string module;
      const Library::Package *ownerPackage = nullptr;
      if (!from.empty())
        for (const auto &package : library.packages)
          if (package.module == from.front()) {
            ownerPackage = &package;
            break;
          }
      const auto &dependencies = ownerPackage ? ownerPackage->dependencies
                                              : library.packageDependencies;
      for (const auto &[name, target] : dependencies)
        if (name == alias || name == path[rooted ? 1 : 0]) {
          module = target;
          break;
        }
      if (module.empty() && rooted)
        return std::nullopt;
      if (!module.empty()) {
        path.erase(path.begin(), path.begin() + (rooted ? 2 : 1));
        path.insert(path.begin(), module);
      }
    }

    auto base = macroModules.end();
    for (auto candidate = macroModules.begin(); candidate != macroModules.end();
         ++candidate)
      if (candidate->first.size() <= path.size() &&
          std::equal(candidate->first.begin(), candidate->first.end(),
                     path.begin()) &&
          (base == macroModules.end() ||
           candidate->first.size() > base->first.size()))
        base = candidate;
    if (base == macroModules.end())
      return std::nullopt;
    if (base->first.size() == path.size()) {
      auto source = base->second.rootSource ? base->second.rootSource
                                            : provider(base->second.sourcePath);
      if (!source)
        return std::nullopt;
      source->id = base->second.sourceId;
      return expansion::MacroModuleSource{std::move(*source), path,
                                          base->first};
    }

    for (auto length = path.size(); length > base->first.size(); --length) {
      auto directory = base->second.directory;
      for (auto i = base->first.size(); i + 1 < length; ++i)
        directory /= path[i];
      auto name = path[length - 1];
      auto firstPath =
          (directory / (name + ".mt")).lexically_normal().generic_string();
      auto secondPath =
          (directory / name / "module.mt").lexically_normal().generic_string();
      auto first = provider(firstPath);
      auto second = provider(secondPath);
      if (first && second)
        return std::nullopt;
      if (!first && !second)
        continue;
      auto source = first ? std::move(*first) : std::move(*second);
      sourceId(source);
      std::vector<std::string> sourcePath(path.begin(), path.begin() + length);
      return expansion::MacroModuleSource{std::move(source), std::move(path),
                                          std::move(sourcePath)};
    }

    auto source = base->second.rootSource ? base->second.rootSource
                                          : provider(base->second.sourcePath);
    if (!source)
      return std::nullopt;
    source->id = base->second.sourceId;
    return expansion::MacroModuleSource{std::move(*source), std::move(path),
                                        base->first};
  }

  struct Reference {
    std::string root, member, from;
    Span span;
    bool text = false;
    bool ownerSyntax = false;
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
        {"core", "iter", "BidirectionalIterator"},
        {"core", "iter", "OwnedIterable"},
        {"core", "iter", "Iterable"},
        {"core", "iter", "MutableIterable"},
        {"core", "cmp", "PartialEq"},
        {"core", "cmp", "Eq"},
        {"core", "cmp", "PartialOrd"},
        {"core", "cmp", "Ord"},
        {"core", "cmp", "Ordering"},
        {"core", "panic", "panic"},
        {"core", "panic", "assert"},
        {"alloc", "string", "String"},
        {"alloc", "collections", "List"},
        {"alloc", "collections", "Map"},
        {"alloc", "collections", "Set"}};
    return names;
  }
  static int layer(const std::string &name) {
    return name == "core" ? 0 : name == "alloc" ? 1 : name == "std" ? 2 : 3;
  }

  // A library root exports the names it declares or re-exports. Compiler
  // pointer operations do not mount `core`; `NonNull` is loaded by its
  // explicit source path.
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
    if (auto source =
            provider((fs::path(library.directory) / "core" / "iter.mt")
                         .lexically_normal()
                         .generic_string())) {
      Diagnostics scratch;
      auto tree = parse(*source, scratch);
      if (scratch.empty())
        for (const auto &function : tree.functions)
          if (function.implementation < 0 &&
              function.interfaceOwner == "Iterator")
            iteratorMethods.insert(
                function.name.substr(function.name.rfind('.') + 1));
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
    // A program type named like a prelude entry shadows it, so the prelude's
    // library is not mounted for that name.
    std::set<std::string> declaredTypes;
    for (std::size_t i = 0; i + 1 < significant.size(); ++i)
      if (from(*significant[i]).empty() &&
          (significant[i]->text == "type" || significant[i]->text == "enum" ||
           significant[i]->text == "interface"))
        declaredTypes.insert(significant[i + 1]->text);
    for (std::size_t i = 0; i < significant.size(); ++i) {
      const auto &token = *significant[i];
      if (token.kind == TokenKind::Word && from(token).empty() &&
          (token.text == "heap" || token.text == "shared" ||
           token.text == "weak" || token.text == "local"))
        found.push_back({"alloc", "", "", token.span, false, true});
      // Async functions and closures are typed by `core.future.Future`.
      if (token.text == "async" && from(token) != "core" && available("core"))
        found.push_back({"core", "future", from(token), token.span, false});
      if (token.kind == TokenKind::Word && from(token).empty() && i > 0 &&
          significant[i - 1]->text == "." && i + 1 < significant.size() &&
          significant[i + 1]->text == "(" && available("core")) {
        const auto &known = builtinMethods();
        if (auto method = known.find(token.text); method != known.end())
          found.push_back({"core", method->second, "", token.span, false});
        else if (i > 1 && significant[i - 2]->text == ")" &&
                 iteratorMethods.contains(token.text))
          found.push_back({"core", "iter", "", token.span, false});
      }
      if (token.kind == TokenKind::Word && from(token).empty() &&
          (i == 0 || (significant[i - 1]->text != "::" &&
                      significant[i - 1]->text != ".")))
        for (const auto &name : preludeNames())
          if (name.back() == token.text) {
            if (!declaredTypes.contains(token.text) && available(name[0]))
              found.push_back({name[0], name[1], "", token.span, false});
            break;
          }
      // Both `core::x` and the target spelling `core.x` name a library
      // module; a value named like a root only mounts an unused library.
      if (token.kind != TokenKind::Word || !libraryRoot(token.text) ||
          i + 1 >= significant.size() ||
          (significant[i + 1]->text != "::" && significant[i + 1]->text != "."))
        continue;
      // `package.core...` names the mounted root like a bare `core...`.
      bool packageRooted = i > 1 &&
                           (significant[i - 1]->text == "::" ||
                            significant[i - 1]->text == ".") &&
                           significant[i - 2]->text == "package";
      if (i > 0 && !packageRooted &&
          (significant[i - 1]->text == "::" || significant[i - 1]->text == "."))
        continue;
      std::string member;
      if (i + 2 < significant.size() &&
          significant[i + 2]->kind == TokenKind::Word)
        member = significant[i + 2]->text;
      // Do not load library sources for compiler-owned `core.ptr` intrinsics.
      if (token.text == "core" && member == "ptr") {
        bool namesNonNull = i + 4 < significant.size() &&
                            (significant[i + 3]->text == "." ||
                             significant[i + 3]->text == "::") &&
                            significant[i + 4]->text == "NonNull";
        bool importsPointerModule = false;
        auto first = i > 3 ? i - 3 : 0;
        for (auto previous = first; previous < i; ++previous)
          importsPointerModule |= significant[previous]->text == "import";
        if (!namesNonNull && !importsPointerModule)
          continue;
      }
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
    auto root = package.module.empty() ? package.name : package.module;
    for (const auto &declaration : result.modules)
      if (declaration.item.scope.empty() && declaration.name == root) {
        diagnostics.error("name", declaration.span,
                          "module '" + root +
                              "' collides with a dependency package instance");
        return;
      }
    Module::ModuleDeclaration declaration;
    declaration.name = root;
    declaration.item.visibility.publicItem = true;
    result.modules.push_back(std::move(declaration));
    auto directory = fs::path(source->path).parent_path();
    currentPackage = &package;
    read(std::move(*source), {root}, std::move(directory), 1);
    currentPackage = nullptr;
  }

  void packageImport(const std::string &scope, const std::string &name,
                     const std::string &module) {
    for (const auto &declaration : result.modules)
      if (declaration.item.scope == (scope.empty()
                                         ? std::vector<std::string>{}
                                         : std::vector<std::string>{scope}) &&
          declaration.name == name) {
        diagnostics.error("name", declaration.span,
                          "module '" + name +
                              "' collides with a dependency package alias");
        return;
      }
    Module::Import imported;
    imported.path = {module};
    imported.alias = name;
    imported.synthesized = true;
    imported.item.scope = scope.empty() ? std::vector<std::string>{}
                                        : std::vector<std::string>{scope};
    result.imports.push_back(std::move(imported));
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
        if (reference.ownerSyntax &&
            (shadowed.contains(reference.root) || !available(reference.root))) {
          diagnostics.error("feature", reference.span,
                            "native owner syntax requires the alloc library");
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
    auto key = currentPackage
                   ? (currentPackage->module.empty() ? currentPackage->name
                                                     : currentPackage->module)
                   : std::string{};
    auto found = configurations.find(key);
    if (found != configurations.end())
      return found->second;
    auto selected = library.configuration;
    selected.features =
        currentPackage ? currentPackage->features : std::set<std::string>{};
    return configurations.emplace(key, std::move(selected)).first->second;
  }

  void discoverImports(const Module &tree,
                       const std::vector<std::string> &prefix, unsigned depth,
                       bool rootPackageSource) {
    for (const auto &imported : tree.imports) {
      if (imported.path.empty())
        continue;
      auto scope = prefix;
      scope.insert(scope.end(), imported.item.scope.begin(),
                   imported.item.scope.end());
      const auto &path = imported.path;
      std::size_t start = 0;
      auto packageRoot =
          currentPackage
              ? std::vector<std::string>{currentPackage->module.empty()
                                             ? currentPackage->name
                                             : currentPackage->module}
              : std::vector<std::string>{};
      if (path[0] == "package") {
        scope = packageRoot;
        ++start;
      } else if (path[0] == "self")
        ++start;
      else if (path[0] != "super") {
        const auto &dependencies = currentPackage ? currentPackage->dependencies
                                                  : library.packageDependencies;
        if (libraryRoot(path[0]) ||
            std::any_of(dependencies.begin(), dependencies.end(),
                        [&](const auto &dependency) {
                          return dependency.first == path[0];
                        }))
          continue;
      }
      while (start < path.size() && path[start] == "super") {
        if (scope.size() <= packageRoot.size())
          break;
        scope.pop_back();
        ++start;
      }
      auto location = macroModules.end();
      for (auto candidate = macroModules.begin();
           candidate != macroModules.end(); ++candidate)
        if (candidate->first.size() <= scope.size() &&
            std::equal(candidate->first.begin(), candidate->first.end(),
                       scope.begin()) &&
            (location == macroModules.end() ||
             candidate->first.size() > location->first.size()))
          location = candidate;
      if (location == macroModules.end())
        continue;
      auto directory = location->second.directory;
      for (auto i = location->first.size(); i < scope.size(); ++i)
        directory /= scope[i];
      auto parent = scope;
      for (auto i = start; i < path.size(); ++i) {
        auto candidate = parent;
        candidate.push_back(path[i]);
        auto childDirectory = directory / path[i];
        if (!knownModules.contains(candidate)) {
          auto first = provider((directory / (path[i] + ".mt"))
                                    .lexically_normal()
                                    .generic_string());
          auto second = provider(
              (childDirectory / "main.mt").lexically_normal().generic_string());
          if (first && second) {
            diagnostics.error("name", imported.span,
                              "imported module '" + path[i] +
                                  "' has multiple source files");
            break;
          }
          if (first || second) {
            auto child = first ? std::move(*first) : std::move(*second);
            for (auto j = scope.size(); j < candidate.size(); ++j) {
              std::vector<std::string> module(candidate.begin(),
                                              candidate.begin() + j + 1);
              if (!knownModules.insert(module).second)
                continue;
              Module::ModuleDeclaration declaration;
              declaration.name = module.back();
              module.pop_back();
              declaration.item.scope = std::move(module);
              declaration.span = imported.span;
              result.modules.push_back(std::move(declaration));
            }
            read(std::move(child), candidate, childDirectory, depth + 1,
                 rootPackageSource);
          }
        }
        directory = std::move(childDirectory);
        parent = std::move(candidate);
      }
    }
  }

  void read(Source source, std::vector<std::string> prefix, fs::path directory,
            unsigned depth, bool rootPackageSource = false) {
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
    sourceId(source);
    MacroModuleLocation location{directory, source.path, source.id,
                                 std::nullopt};
    if (prefix.empty())
      location.rootSource = source;
    macroModules[prefix] = std::move(location);
    if (rootPackageSource && sourceModules)
      sourceModules->push_back({source, prefix, {}});
    if (allSources && (rootPackageSource || currentPackage))
      allSources->push_back({source, prefix,
                             currentPackage ? (currentPackage->module.empty()
                                                   ? currentPackage->name
                                                   : currentPackage->module)
                                            : std::string{}});
    if (!currentRoot.empty())
      owner[source.id] = currentRoot;
    // Declarative macros expand on the token level, before parsing.
    expansion::MacroModuleProvider macroProvider =
        [this](const std::vector<std::string> &path,
               const std::vector<std::string> &from) {
          return macroModule(path, from);
        };
    std::vector<Module::MacroDeclaration> macros;
    if (auto generated = expansion::expandMacros(
            source, diagnostics,
            [&] {
              auto id = nextSource++;
              if (!currentRoot.empty())
                owner[id] = currentRoot;
              return id;
            },
            library.procedures, prefix, macroProvider, &macros))
      source = std::move(*generated);
    if (!diagnostics.empty())
      return;
    auto tree = parseDeclarations(source, diagnostics);
    if (!diagnostics.empty())
      return;
    // Expansion precedes member flattening and the external-module scan, so
    // inactive modules are never read and generated impls are flattened too.
    const expansion::Configuration *facts = &configuration();
    std::optional<expansion::Configuration> harnessFacts;
    if (rootPackageSource && library.harness != Library::Harness::None) {
      harnessFacts = *facts;
      harnessFacts->collectTests = true;
      harnessFacts->dropEntry = depth == 0;
      facts = &*harnessFacts;
    }
    expansion::expand(tree, diagnostics, *facts, [&] {
      auto id = nextSource++;
      if (!currentRoot.empty())
        owner[id] = currentRoot;
      return id;
    });
    if (!diagnostics.empty())
      return;
    for (auto &test : tree.tests) {
      test.path.insert(test.path.begin(), prefix.begin(), prefix.end());
      result.tests.push_back(std::move(test));
    }
    completeDeclarations(tree);
    for (const auto &declaration : tree.modules) {
      auto path = prefix;
      path.insert(path.end(), declaration.item.scope.begin(),
                  declaration.item.scope.end());
      path.push_back(declaration.name);
      knownModules.insert(std::move(path));
    }
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
           childDirectory / declaration.name, depth + 1, rootPackageSource);
    }
    if (currentRoot.empty() || currentPackage)
      discoverImports(tree, prefix, depth, rootPackageSource);
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
    merge(result.macros, std::move(macros), prefix);
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
                           Diagnostics &diagnostics, const Library &library,
                           std::vector<SourceModule> *sourceModules,
                           std::vector<SourceModule> *allSources) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Loader(provider, diagnostics, library, sourceModules, allSources)
      .run(std::move(root));
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
