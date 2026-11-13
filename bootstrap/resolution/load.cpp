#include "resolution/load.h"
#include "expansion/harness.h"
#include "expansion/macros.h"
#include "support/limits.h"
#include "syntax/parser.h"
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <iterator>
#include <limits>
#include <map>
#include <set>
#include <string_view>
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

struct DefinitionReference {
  SyntaxContextPtr context;
  Span span;
};

class DefinitionReferences {
public:
  explicit DefinitionReferences(Diagnostics &diagnostics)
      : diagnostics(diagnostics) {}

  std::vector<DefinitionReference> collect(const Module &tree) {
    for (const auto &function : tree.functions) {
      Bindings bindings;
      if (function.implementation < 0 && !function.owner.empty())
        for (const auto &product : tree.products)
          if (product.name == function.owner &&
              product.item.scope == function.item.scope)
            generics(product.genericParameters, product.constraints, bindings,
                     product.span);
      generics(function.genericParameters, function.constraints, bindings,
               function.span);
      if (!function.owner.empty())
        self(bindings, function.lexicalContext);
      for (const auto &parameter : function.parameters)
        parameterBinding(parameter, bindings);
      type(function.annotation, bindings, function.span);
      type(function.error, bindings, function.span);
      type(function.asyncOutput, bindings, function.span);
      type(function.asyncError, bindings, function.span);
      type(function.asyncDefaultBodyResult, bindings, function.span);
      if (function.body.get())
        node(*function.body, bindings);
    }
    for (const auto &product : tree.products) {
      Bindings bindings;
      self(bindings, diagnostics.syntaxContext(product.span));
      generics(product.genericParameters, product.constraints, bindings,
               product.span);
      for (const auto &interface : product.interfaces)
        type(interface, bindings, product.span);
      for (const auto &field : product.fields)
        parameterType(field, bindings);
      for (const auto &variant : product.variants) {
        for (const auto &field : variant.fields)
          parameterType(field, bindings);
        if (variant.discriminant)
          node(*variant.discriminant, bindings);
      }
      associated(product.associated, bindings);
    }
    for (const auto &interface : tree.interfaces) {
      Bindings bindings;
      self(bindings, diagnostics.syntaxContext(interface.span));
      generics(interface.genericParameters, interface.constraints, bindings,
               interface.span);
      for (const auto &parent : interface.superinterfaces)
        type(parent, bindings, interface.span);
      associated(interface.associated, bindings);
    }
    for (const auto &implementation : tree.implementations) {
      Bindings bindings;
      self(bindings, diagnostics.syntaxContext(implementation.span));
      generics(implementation.genericParameters, implementation.constraints,
               bindings, implementation.span);
      type(implementation.target, bindings, implementation.span);
      type(implementation.interface, bindings, implementation.span);
      associated(implementation.associated, bindings);
    }
    for (const auto &alias : tree.aliases) {
      Bindings bindings;
      generics(alias.genericParameters, alias.constraints, bindings,
               alias.span);
      type(alias.target, bindings, alias.span);
    }
    for (const auto &storage : tree.statics) {
      Bindings bindings;
      type(storage.annotation, bindings, storage.span);
      if (storage.initializer.get())
        node(*storage.initializer, bindings);
    }
    for (const auto &assembly : tree.globalAssembly) {
      Bindings bindings;
      node(*assembly, bindings);
    }
    return std::move(references);
  }

private:
  using Key = std::pair<std::string, std::uint64_t>;
  struct Bindings {
    std::set<Key> values, types;
  };
  Diagnostics &diagnostics;
  std::vector<DefinitionReference> references;

  static Key key(std::string_view name, const SyntaxContextPtr &context) {
    return {std::string(name), context ? context->identity : 0};
  }
  static void self(Bindings &bindings, const SyntaxContextPtr &context) {
    auto identity = key("Self", context);
    bindings.types.insert(identity);
    bindings.values.insert(identity);
  }
  void reference(std::string_view name, const SyntaxContextPtr &context,
                 Span span, const std::set<Key> &bindings) {
    if (!name.empty() && name != "_" && context && context->identity &&
        !context->scope.empty() && !bindings.contains(key(name, context)) &&
        !bindings.contains(key(name.substr(0, name.find("::")), context)))
      references.push_back({context, span});
  }
  void arguments(const std::vector<GenericArgument> &arguments,
                 Bindings &bindings, Span span) {
    for (const auto &argument : arguments) {
      if (argument.type)
        type(*argument.type, bindings, span);
      if (argument.value)
        node(*argument.value, bindings);
    }
  }
  void type(const TypeSyntax &syntax, Bindings &bindings, Span span) {
    if (syntax.form == TypeForm::Named)
      reference(syntax.name, syntax.context, span, bindings.types);
    if (syntax.nested)
      type(*syntax.nested, bindings, span);
    for (const auto &element : syntax.elements)
      type(element, bindings, span);
    if (syntax.countExpression)
      node(*syntax.countExpression, bindings);
    arguments(syntax.arguments, bindings, span);
    if (syntax.callable) {
      for (const auto &parameter : syntax.callable->parameters)
        type(parameter.annotation, bindings, span);
      type(syntax.callable->result, bindings, span);
      type(syntax.callable->error, bindings, span);
    }
  }
  void generics(const std::vector<GenericParameter> &parameters,
                const std::vector<GenericConstraint> &constraints,
                Bindings &bindings, Span span) {
    for (const auto &parameter : parameters)
      if (parameter.kind != GenericParameterKind::Region) {
        auto identity = key(parameter.name, parameter.context);
        bindings.types.insert(identity);
        bindings.values.insert(identity);
      }
    for (const auto &parameter : parameters) {
      if (parameter.kind == GenericParameterKind::Region)
        continue;
      type(parameter.annotation, bindings, parameter.span);
      type(parameter.defaultType, bindings, parameter.span);
      for (const auto &bound : parameter.bounds)
        type(bound, bindings, parameter.span);
      if (parameter.defaultValue)
        node(*parameter.defaultValue, bindings);
    }
    for (const auto &constraint : constraints) {
      if (constraint.region)
        continue;
      type(constraint.subject, bindings, span);
      for (const auto &bound : constraint.bounds)
        type(bound, bindings, span);
      if (constraint.equality)
        type(*constraint.equality, bindings, span);
    }
  }
  void associated(const std::vector<Module::Associated> &items,
                  const Bindings &parent) {
    for (const auto &item : items) {
      auto bindings = parent;
      generics(item.genericParameters, item.constraints, bindings, item.span);
      type(item.annotation, bindings, item.span);
      type(item.value, bindings, item.span);
      for (const auto &bound : item.bounds)
        type(bound, bindings, item.span);
      if (item.constantValue)
        node(*item.constantValue, bindings);
    }
  }
  void pattern(const Pattern &syntax, Bindings &bindings) {
    if (syntax.kind == PatternKind::Product ||
        (syntax.kind == PatternKind::Variant && syntax.text != "none" &&
         syntax.text != "present" && syntax.text != "success" &&
         syntax.text != "failure"))
      reference(syntax.text, syntax.context, syntax.span, bindings.types);
    if ((syntax.kind == PatternKind::Binding ||
         syntax.kind == PatternKind::At || syntax.kind == PatternKind::Rest) &&
        !syntax.text.empty() && syntax.text != "_")
      bindings.values.insert(key(syntax.text, syntax.context));
    for (const auto &child : syntax.children)
      pattern(child, bindings);
  }
  void parameterType(const Parameter &parameter, Bindings &bindings) {
    type(parameter.annotation, bindings, parameter.span);
    if (parameter.defaultValue.get())
      node(*parameter.defaultValue, bindings);
  }
  void parameterBinding(const Parameter &parameter, Bindings &bindings) {
    parameterType(parameter, bindings);
    if (parameter.pattern)
      pattern(*parameter.pattern, bindings);
    else
      bindings.values.insert(key(parameter.name, parameter.context));
  }
  void node(const Node &syntax, Bindings &bindings) {
    type(syntax.annotation, bindings, syntax.span);
    type(syntax.error, bindings, syntax.span);
    arguments(syntax.genericArguments, bindings, syntax.span);
    arguments(syntax.ownerGenericArguments, bindings, syntax.span);
    if (syntax.kind == Kind::Name)
      reference(syntax.text, syntax.context, syntax.span, bindings.values);
    if (syntax.kind == Kind::Call && !syntax.children.empty() &&
        syntax.children[0]->kind == Kind::Field) {
      const auto &selector = *syntax.children[0];
      reference(selector.text, selector.context, selector.span, {});
    }
    if (syntax.kind == Kind::Binding) {
      for (const auto &child : syntax.children) {
        auto initializer = bindings;
        node(*child, initializer);
      }
      if (syntax.patterns.empty())
        bindings.values.insert(key(syntax.text, syntax.context));
      else
        for (const auto &binding : syntax.patterns)
          pattern(binding, bindings);
      return;
    }
    if (syntax.kind == Kind::If || syntax.kind == Kind::While ||
        syntax.kind == Kind::For) {
      auto branch = bindings;
      node(*syntax.children[0], branch);
      for (const auto &binding : syntax.patterns)
        pattern(binding, branch);
      node(*syntax.children[1], branch);
      if (syntax.children.size() > 2) {
        auto alternative = bindings;
        node(*syntax.children[2], alternative);
      }
      return;
    }
    if (syntax.kind == Kind::Block || syntax.kind == Kind::Closure ||
        syntax.kind == Kind::Arm) {
      auto local = bindings;
      for (const auto &binding : syntax.patterns)
        pattern(binding, local);
      for (const auto &parameter : syntax.parameters) {
        type(parameter.annotation, local, parameter.span);
        if (parameter.pattern)
          pattern(*parameter.pattern, local);
        else
          local.values.insert(key(parameter.name, parameter.context));
      }
      for (const auto &child : syntax.children)
        node(*child, local);
      return;
    }
    for (const auto &child : syntax.children)
      node(*child, bindings);
    if (syntax.kind == Kind::Condition)
      for (const auto &binding : syntax.patterns)
        pattern(binding, bindings);
  }
};

class Loader {
public:
  Loader(const SourceProvider &provider, Diagnostics &diagnostics,
         const Library &library, std::vector<SourceModule> *sourceModules,
         std::vector<SourceModule> *allSources, SourcePackages *sourcePackages)
      : provider(provider), diagnostics(diagnostics), library(library),
        sourceModules(sourceModules), allSources(allSources),
        sourcePackagesOut(sourcePackages) {}

  std::optional<Module> run(Source root) {
    auto directory = fs::path(root.path).parent_path();
    sourceIds.emplace(fs::path(root.path).lexically_normal().generic_string(),
                      0);
    nextSource = 1;
    allocatedSources.insert(0);
    if (!reserveCompiledSources())
      return std::nullopt;
    for (const auto &compiled : library.compiled)
      if (!libraryRoot(compiled.root) && !mountCompiled(compiled))
        return std::nullopt;
    auto harnessPath =
        (directory / "mettle-test-harness.mt").lexically_normal();
    for (const auto &package : library.packages) {
      if (std::any_of(library.compiled.begin(), library.compiled.end(),
                      [&](const auto &compiled) {
                        return compiled.root == (package.module.empty()
                                                     ? package.name
                                                     : package.module);
                      }))
        continue;
      auto source = provider(package.source);
      if (!source)
        continue;
      auto name = package.module.empty() ? package.name : package.module;
      sourceId(*source);
      sourceInstances[source->id] = package.instanceIdentity;
      macroModules[{name}] = {fs::path(source->path).parent_path(),
                              source->path, source->id, std::nullopt};
      macroModules[{name}].package = &package;
    }
    read(std::move(root), {}, directory, 0, true);
    for (std::size_t i = 0;
         i < definitionReferences.size() && diagnostics.empty(); ++i) {
      auto origin =
          macroSources.find(definitionReferences[i].context->definition.source);
      if (origin != macroSources.end() && origin->second.rootPackageSource)
        materializeDefinition(definitionReferences[i]);
    }
    if (library.harness != Library::Harness::None && diagnostics.empty()) {
      for (auto &declaration : result.modules) {
        auto path = declaration.item.scope;
        path.push_back(declaration.name);
        if (std::any_of(result.tests.begin(), result.tests.end(),
                        [&](const auto &test) {
                          return path.size() < test.path.size() &&
                                 std::equal(path.begin(), path.end(),
                                            test.path.begin());
                        })) {
          declaration.item.visibility.publicItem = true;
          declaration.item.visibility.restriction = {"package"};
        }
      }
      bool bench = library.harness == Library::Harness::Bench;
      read({harnessPath.generic_string(),
            expansion::harnessSource(result.tests, bench)},
           {}, std::move(directory), 1);
    }
    for (const auto &package : library.packages) {
      if (!diagnostics.empty())
        break;
      if (std::any_of(library.compiled.begin(), library.compiled.end(),
                      [&](const auto &compiled) {
                        return compiled.root == (package.module.empty()
                                                     ? package.name
                                                     : package.module);
                      }))
        continue;
      mountPackage(package);
    }
    if (diagnostics.empty()) {
      for (const auto &package : library.packages) {
        for (const auto &[name, module] : package.dependencies)
          packageImport(package.module, name, module);
        if (!package.module.empty() && !package.instanceIdentity.empty())
          for (const auto &generated : library.packages)
            if (generated.module.empty() &&
                generated.instanceIdentity == package.instanceIdentity)
              packageImport(package.module, generated.name, generated.name);
      }
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
    if (diagnostics.empty())
      mountLibraries();
    if (!diagnostics.empty())
      return std::nullopt;
    assembleCompiledHeaders();
    if (sourcePackagesOut)
      *sourcePackagesOut = std::move(sourceInstances);
    return std::move(result);
  }

private:
  const SourceProvider &provider;
  Diagnostics &diagnostics;
  const Library &library;
  std::vector<SourceModule> *sourceModules;
  std::vector<SourceModule> *allSources;
  SourcePackages *sourcePackagesOut;
  SourcePackages sourceInstances;
  Module result;
  std::unordered_set<std::string> loaded;
  std::set<std::vector<std::string>> knownModules;
  SourceId nextSource = 0;
  std::set<SourceId> allocatedSources;
  std::set<SourceId> compiledSourceIds;
  std::map<std::string, Module> compiledHeaders;
  std::map<std::string, SourceId> sourceIds;
  struct MacroModuleLocation {
    fs::path directory;
    std::string sourcePath;
    SourceId sourceId = 0;
    std::optional<Source> rootSource;
    const Library::Package *package = nullptr;
    std::string nativeRoot{};
    bool rootPackageSource = false;
  };
  std::map<std::vector<std::string>, MacroModuleLocation> macroModules;
  struct MacroSource {
    Source source;
    std::vector<std::string> sourcePath;
    fs::path directory;
    const Library::Package *package;
    std::string nativeRoot;
    bool rootPackageSource;
    std::set<bool> importProviders{};
  };
  std::map<SourceId, MacroSource> macroSources;
  std::map<SourceId, std::vector<std::string>> nativeSources;
  std::vector<DefinitionReference> definitionReferences;
  std::size_t nextDefinitionReference = 0;
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
  std::size_t scanned = 0, scannedLiterals = 0, scannedImports = 0;

  const Library::CompiledModule *compiledModule(std::string_view root) const {
    auto found = std::find_if(
        library.compiled.begin(), library.compiled.end(),
        [&](const auto &compiled) { return compiled.root == root; });
    if (found == library.compiled.end() ||
        std::any_of(found->replaces.begin(), found->replaces.end(),
                    [&](const auto &name) { return shadowed.contains(name); }))
      return nullptr;
    return &*found;
  }

  bool reserveCompiledSources() {
    auto reserve = [&](SourceId id) {
      if (compiledSourceIds.contains(id))
        return true;
      if (!id || id == std::numeric_limits<SourceId>::max() ||
          allocatedSources.contains(id)) {
        diagnostics.error("metadata", {},
                          "compiled source identity collides with loaded code");
        return false;
      }
      compiledSourceIds.insert(id);
      allocatedSources.insert(id);
      nextSource = std::max(nextSource, SourceId(id + 1));
      return true;
    };
    for (const auto &[id, package] : library.compiledSourcePackages) {
      if (!reserve(id))
        return false;
      auto [found, inserted] = sourceInstances.emplace(id, package);
      if (!inserted && found->second != package) {
        diagnostics.error("metadata", {},
                          "compiled source has conflicting package identities");
        return false;
      }
    }
    for (const auto &[id, path] : library.compiledSourceModules) {
      if (!reserve(id))
        return false;
      auto [found, inserted] = nativeSources.emplace(id, path);
      if (!inserted && found->second != path) {
        diagnostics.error("metadata", {},
                          "compiled source has conflicting module identities");
        return false;
      }
      if (!path.empty() && libraryRoot(path.front()))
        owner[id] = path.front();
    }
    return true;
  }

  void indexCoreMethods(const Module &header) {
    for (const auto &function : header.functions) {
      auto module = function.item.scope.empty() ? std::string{}
                                                : function.item.scope.back();
      auto name = function.name.substr(function.name.rfind('.') + 1);
      if (function.implementation >= 0 && function.interfaceOwner.empty() &&
          (module == "option" || module == "outcome" || module == "slice"))
        methods.emplace(std::move(name), std::move(module));
      else if (function.interfaceOwner == "Iterator")
        iteratorMethods.insert(std::move(name));
    }
    builtinMethodsLoaded = true;
  }

  bool mountCompiled(const Library::CompiledModule &compiled) {
    if (compiledHeaders.contains(compiled.root))
      return true;
    if (!compiled.declarations) {
      diagnostics.error("metadata", {},
                        "compiled module has no declaration provider");
      return false;
    }
    const auto diagnosticsBefore = diagnostics.count();
    auto header = compiled.declarations();
    if (!header) {
      if (diagnostics.count() == diagnosticsBefore)
        diagnostics.error("metadata", {},
                          "compiled module declarations could not be decoded");
      return false;
    }
    if (!reserveCompiledSources())
      return false;
    for (auto &declaration : header->modules) {
      auto path = declaration.item.scope;
      path.push_back(declaration.name);
      knownModules.insert(std::move(path));
      declaration.item.checkedImport = true;
    }
    if (libraryRoot(compiled.root))
      mounted.insert(compiled.root);
    for (const auto &root : compiled.replaces)
      mounted.insert(root);
    if (compiled.root == "core" ||
        std::find(compiled.replaces.begin(), compiled.replaces.end(), "core") !=
            compiled.replaces.end())
      indexCoreMethods(*header);
    compiledHeaders.emplace(compiled.root, std::move(*header));
    return true;
  }

  void assembleCompiledHeaders() {
    Module prefix;
    std::set<std::string> replaced;
    for (const auto &compiled : library.compiled)
      if (compiledHeaders.contains(compiled.root))
        replaced.insert(compiled.replaces.begin(), compiled.replaces.end());
    for (const auto &compiled : library.compiled) {
      if (replaced.contains(compiled.root))
        continue;
      auto found = compiledHeaders.find(compiled.root);
      if (found == compiledHeaders.end())
        continue;
      auto &header = found->second;
      for (auto &implementation : header.implementations)
        for (auto &function : implementation.methodFunctions)
          function += prefix.functions.size();
      for (auto &function : header.functions)
        if (function.implementation >= 0)
          function.implementation += prefix.implementations.size();
      merge(prefix.interfaces, std::move(header.interfaces), {});
      merge(prefix.implementations, std::move(header.implementations), {});
      merge(prefix.functions, std::move(header.functions), {});
      merge(prefix.statics, std::move(header.statics), {});
      merge(prefix.products, std::move(header.products), {});
      merge(prefix.aliases, std::move(header.aliases), {});
      merge(prefix.modules, std::move(header.modules), {});
      merge(prefix.imports, std::move(header.imports), {});
      merge(prefix.macros, std::move(header.macros), {});
    }
    for (auto &implementation : result.implementations)
      for (auto &function : implementation.methodFunctions)
        function += prefix.functions.size();
    for (auto &function : result.functions)
      if (function.implementation >= 0)
        function.implementation += prefix.implementations.size();
    auto prepend = [](auto &target, auto &items) {
      target.insert(target.begin(), std::make_move_iterator(items.begin()),
                    std::make_move_iterator(items.end()));
    };
    prepend(result.interfaces, prefix.interfaces);
    prepend(result.implementations, prefix.implementations);
    prepend(result.functions, prefix.functions);
    prepend(result.statics, prefix.statics);
    prepend(result.products, prefix.products);
    prepend(result.aliases, prefix.aliases);
    prepend(result.modules, prefix.modules);
    prepend(result.imports, prefix.imports);
    prepend(result.macros, prefix.macros);
  }

  SourceId sourceId(Source &source) {
    auto identity = fs::path(source.path).lexically_normal().generic_string();
    auto found = sourceIds.find(identity);
    if (found == sourceIds.end())
      found = sourceIds.emplace(identity, allocateSource()).first;
    source.id = found->second;
    return source.id;
  }

  SourceId allocateSource() {
    auto id = library.allocateSource ? library.allocateSource() : nextSource++;
    if (!id || !allocatedSources.insert(id).second)
      diagnostics.error("metadata", {},
                        "source allocator returned an occupied identity");
    return id;
  }

  std::string sourceInstance() const {
    if (currentPackage)
      return currentPackage->instanceIdentity;
    if (!currentRoot.empty())
      return "native:standard-library";
    return library.rootIdentity.empty() ? "raw-root" : library.rootIdentity;
  }

  std::optional<expansion::MacroModuleSource>
  rememberMacroSource(expansion::MacroModuleSource source,
                      const MacroModuleLocation &location,
                      const fs::path &directory, bool imported) {
    source.configuration = library.configuration;
    if (location.package)
      source.configuration->features = location.package->features;
    else if (!location.nativeRoot.empty())
      source.configuration->features.clear();
    auto [entry, inserted] = macroSources.try_emplace(
        source.source.id,
        MacroSource{source.source, source.sourcePath, directory,
                    location.package, location.nativeRoot,
                    location.rootPackageSource});
    if (!inserted && entry->second.sourcePath != source.sourcePath) {
      diagnostics.error("name", {},
                        "macro source has more than one module identity");
      return std::nullopt;
    }
    entry->second.importProviders.insert(imported);
    return source;
  }

  std::optional<expansion::MacroModuleSource>
  macroModule(const std::vector<std::string> &requested,
              const std::vector<std::string> &from, bool imported = false) {
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
    if (library.compiledMacros &&
        (path.empty() || !libraryRoot(path.front()) || imported)) {
      if (!path.empty())
        if (const auto *compiled = compiledModule(path.front());
            compiled && !mountCompiled(*compiled))
          return std::nullopt;
      if (auto compiled = library.compiledMacros(path, from)) {
        if (!reserveCompiledSources())
          return std::nullopt;
        return compiled;
      }
    }
    if (imported && !path.empty() && libraryRoot(path.front())) {
      if (compiledModule(path.front()))
        return std::nullopt;
      if (!library.directory.empty() &&
          !macroModules.contains({path.front()})) {
        auto sourcePath =
            (fs::path(library.directory) / path.front() / "module.mt")
                .lexically_normal()
                .generic_string();
        if (auto source = provider(sourcePath)) {
          sourceId(*source);
          sourceInstances[source->id] = "native:standard-library";
          auto [location, inserted] = macroModules.try_emplace(
              std::vector<std::string>{path.front()},
              MacroModuleLocation{fs::path(sourcePath).parent_path(),
                                  sourcePath, source->id, std::nullopt});
          if (inserted)
            location->second.nativeRoot = path.front();
        }
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
      return rememberMacroSource({std::move(*source), path, base->first},
                                 base->second, base->second.directory,
                                 imported);
    }

    for (auto length = path.size(); length > base->first.size(); --length) {
      auto directory = base->second.directory;
      for (auto i = base->first.size(); i + 1 < length; ++i)
        directory /= path[i];
      auto name = path[length - 1];
      auto firstPath =
          (directory / (name + ".mt")).lexically_normal().generic_string();
      auto secondPath = (directory / name / "module.mt")
                            .lexically_normal()
                            .generic_string();
      auto first = provider(firstPath);
      auto second = provider(secondPath);
      if (first && second)
        return std::nullopt;
      if (!first && !second)
        continue;
      auto source = first ? std::move(*first) : std::move(*second);
      sourceId(source);
      sourceInstances[source.id] = sourceInstances.at(base->second.sourceId);
      std::vector<std::string> sourcePath(path.begin(), path.begin() + length);
      return rememberMacroSource(
          {std::move(source), std::move(path), std::move(sourcePath)},
          base->second, directory / name, imported);
    }

    auto source = base->second.rootSource ? base->second.rootSource
                                          : provider(base->second.sourcePath);
    if (!source)
      return std::nullopt;
    source->id = base->second.sourceId;
    return rememberMacroSource(
        {std::move(*source), std::move(path), base->first}, base->second,
        base->second.directory, imported);
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
    if (const auto *compiled = compiledModule("core");
        compiled && compiled->declarationIndex)
      if (auto header = compiled->declarationIndex()) {
        if (reserveCompiledSources())
          indexCoreMethods(*header);
        return methods;
      }
    builtinMethodsLoaded = true;
    if (library.directory.empty())
      return methods;
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
    if (shadowed.contains(root))
      return false;
    if (mounted.contains(root) || compiledModule(root))
      return true;
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
    auto inactive = result.inactiveSyntax;
    std::sort(inactive.begin(), inactive.end(), [](Span left, Span right) {
      return left.source < right.source ||
             (left.source == right.source && left.begin < right.begin);
    });
    // Preserve outer coverage when excluded intervals nest.
    for (std::size_t i = 1; i < inactive.size(); ++i)
      if (inactive[i].source == inactive[i - 1].source &&
          inactive[i].begin <= inactive[i - 1].end)
        inactive[i].end = std::max(inactive[i].end, inactive[i - 1].end);
    auto excluded = [&](Span span) {
      auto found = std::upper_bound(
          inactive.begin(), inactive.end(), span, [](Span left, Span right) {
            return left.source < right.source ||
                   (left.source == right.source && left.begin < right.begin);
          });
      if (found == inactive.begin())
        return false;
      --found;
      return found->source == span.source && span.begin < found->end;
    };
    const Token barrier{TokenKind::End, {}, ""};
    std::vector<const Token *> significant;
    for (auto i = scanned; i < result.tokens.size(); ++i) {
      const auto &token = result.tokens[i];
      auto kind = token.kind;
      if (excluded(token.span) || kind == TokenKind::End) {
        if (!significant.empty() && significant.back() != &barrier)
          significant.push_back(&barrier);
        continue;
      }
      if (kind != TokenKind::Space && kind != TokenKind::Comment &&
          kind != TokenKind::Newline) {
        if (!significant.empty() && significant.back() != &barrier &&
            significant.back()->span.source != token.span.source)
          significant.push_back(&barrier);
        significant.push_back(&token);
      }
    }
    scanned = result.tokens.size();
    std::vector<Reference> found;
    auto from = [&](const Token &token) {
      auto entry = owner.find(token.span.source);
      return entry == owner.end() ? std::string() : entry->second;
    };
    for (; scannedImports < result.imports.size(); ++scannedImports) {
      const auto &imported = result.imports[scannedImports];
      auto index = !imported.path.empty() && imported.path.front() == "package"
                       ? std::size_t{1}
                       : std::size_t{0};
      if (index >= imported.path.size() || !libraryRoot(imported.path[index]))
        continue;
      auto origin = owner.find(imported.span.source);
      found.push_back({imported.path[index],
                       index + 1 < imported.path.size()
                           ? imported.path[index + 1]
                           : std::string{},
                       origin == owner.end() ? std::string{} : origin->second,
                       imported.span, false});
    }
    for (auto i = scannedLiterals; i < result.textLiterals.size(); ++i) {
      auto span = result.textLiterals[i];
      if (excluded(span))
        continue;
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
      auto pathStart = i;
      while (pathStart >= 2 &&
             (significant[pathStart - 1]->text == "." ||
              significant[pathStart - 1]->text == "::") &&
             significant[pathStart - 2]->kind == TokenKind::Word)
        pathStart -= 2;
      auto nativePath = libraryRoot(significant[pathStart]->text) ||
                        (significant[pathStart]->text == "package" &&
                         pathStart + 2 < significant.size() &&
                         libraryRoot(significant[pathStart + 2]->text));
      if (!nativePath && token.kind == TokenKind::Word && from(token).empty() &&
          i > 0 && significant[i - 1]->text == "." &&
          i + 1 < significant.size() && significant[i + 1]->text == "(" &&
          available("core")) {
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
      if (declaration.item.scope.empty() && !declaration.item.checkedImport)
        shadowed.insert(declaration.name);
    auto native = !library.directory.empty() ||
                  std::any_of(library.compiled.begin(), library.compiled.end(),
                              [&](const auto &compiled) {
                                return libraryRoot(compiled.root);
                              });
    while (((native && (scanned < result.tokens.size() ||
                        scannedLiterals < result.textLiterals.size() ||
                        scannedImports < result.imports.size())) ||
            nextDefinitionReference < definitionReferences.size()) &&
           diagnostics.empty()) {
      auto pending = native ? references() : std::vector<Reference>{};
      for (const auto &reference : pending) {
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
        if (reference.root == "core" && !reference.text &&
            !reference.member.empty() && !compiledModule("core")) {
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
      while (nextDefinitionReference < definitionReferences.size() &&
             diagnostics.empty())
        materializeDefinition(definitionReferences[nextDefinitionReference++]);
    }
    // Without a user module shadowing `core` there is no prelude to offer.
    if (mounted.contains("core") && !shadowed.contains("core")) {
      for (const auto &name : preludeNames())
        if (mounted.contains(name[0]) && !shadowed.contains(name[0]))
          result.prelude.names.push_back(name);
      result.prelude.libraryRoots.assign(mounted.begin(), mounted.end());
    }
  }

  void materializeDefinition(DefinitionReference reference) {
    auto found = macroSources.find(reference.context->definition.source);
    auto parsed = nativeSources.find(reference.context->definition.source);
    if (found == macroSources.end() && parsed == nativeSources.end()) {
      diagnostics.error("name", reference.span,
                        "macro definition source is unavailable");
      return;
    }
    const auto &sourcePath = parsed != nativeSources.end()
                                 ? parsed->second
                                 : found->second.sourcePath;
    if (sourcePath.size() > reference.context->scope.size() ||
        !std::equal(sourcePath.begin(), sourcePath.end(),
                    reference.context->scope.begin())) {
      diagnostics.error("name", reference.span,
                        "macro lexical module does not match its provider");
      return;
    }
    auto definitionOwner = owner.find(reference.context->definition.source);
    auto nativeRoot = found != macroSources.end() ? found->second.nativeRoot
                      : definitionOwner == owner.end()
                          ? std::string{}
                          : definitionOwner->second;
    if (!nativeRoot.empty()) {
      auto caller = owner.find(reference.span.source);
      if (caller != owner.end() && layer(nativeRoot) > layer(caller->second)) {
        diagnostics.error("name", reference.span,
                          "library module '" + caller->second +
                              "' may not depend on '" + nativeRoot +
                              "' (core <- alloc <- std)");
        return;
      }
      if (nativeRoot == "std" && library.freestanding) {
        diagnostics.error("name", reference.span,
                          "library module 'std' is not available in a "
                          "freestanding build");
        return;
      }
      if (parsed == nativeSources.end() && !mounted.contains(nativeRoot)) {
        if (shadowed.contains(nativeRoot)) {
          diagnostics.error("name", reference.span,
                            "macro definition module is shadowed");
          return;
        }
        mount(nativeRoot, reference.span);
        if (!diagnostics.empty())
          return;
      }
    }
    if (parsed != nativeSources.end())
      return;
    auto origin = found->second;
    auto identity =
        fs::path(origin.source.path).lexically_normal().generic_string();
    if (loaded.contains(identity))
      return;
    if (auto existing = macroModules.find(origin.sourcePath);
        existing != macroModules.end() &&
        existing->second.sourceId != origin.source.id &&
        loaded.contains(fs::path(existing->second.sourcePath)
                            .lexically_normal()
                            .generic_string())) {
      diagnostics.error("name", reference.span,
                        "macro definition module has a different source");
      return;
    }
    for (std::size_t size = 1; size <= origin.sourcePath.size(); ++size) {
      std::vector<std::string> path(origin.sourcePath.begin(),
                                    origin.sourcePath.begin() + size);
      if (!knownModules.insert(path).second)
        continue;
      bool declared = std::any_of(
          result.modules.begin(), result.modules.end(), [&](const auto &item) {
            return item.name == path.back() &&
                   item.item.scope ==
                       std::vector<std::string>(path.begin(), path.end() - 1);
          });
      if (!declared) {
        Module::ModuleDeclaration declaration;
        declaration.name = path.back();
        path.pop_back();
        declaration.item.scope = std::move(path);
        // An implicit namespace must not enclose captured invocation tokens.
        declaration.span = {0, 0, origin.source.id};
        result.modules.push_back(std::move(declaration));
      }
    }
    auto savedRoot = currentRoot;
    auto savedPackage = currentPackage;
    currentRoot = origin.nativeRoot;
    currentPackage = origin.package;
    auto depth = static_cast<unsigned>(origin.sourcePath.size());
    read(std::move(origin.source), std::move(origin.sourcePath),
         std::move(origin.directory), depth, origin.rootPackageSource);
    currentPackage = savedPackage;
    currentRoot = std::move(savedRoot);
  }

  void mount(const std::string &root, Span span) {
    if (const auto *compiled = compiledModule(root)) {
      mountCompiled(*compiled);
      return;
    }
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
          auto second = provider((childDirectory / "module.mt")
                                     .lexically_normal()
                                     .generic_string());
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
    if (!diagnostics.empty())
      return;
    nativeSources[source.id] = prefix;
    sourceInstances[source.id] = sourceInstance();
    MacroModuleLocation location{directory, source.path, source.id,
                                 std::nullopt};
    location.package = currentPackage;
    location.nativeRoot = currentRoot;
    location.rootPackageSource = rootPackageSource;
    if (prefix.empty())
      location.rootSource = source;
    macroModules[prefix] = std::move(location);
    if (rootPackageSource && sourceModules)
      sourceModules->push_back({source, prefix, {}});
    if (allSources)
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
    expansion::MacroLibrary macroExports;
    if (auto generated = expansion::expandMacros(
            source, diagnostics,
            [&] {
              auto id = allocateSource();
              sourceInstances[id] = sourceInstance();
              if (!currentRoot.empty())
                owner[id] = currentRoot;
              return id;
            },
            library.procedures, prefix, macroProvider, &macros,
            [this](const std::vector<std::string> &path,
                   const std::vector<std::string> &from) {
              return macroModule(path, from, true);
            },
            &configuration(), library.macroExports ? &macroExports : nullptr,
            library.identifyMacroSource))
      source = std::move(*generated);
    if (!diagnostics.empty())
      return;
    if (library.macroExports && !library.macroExports(macroExports))
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
      auto id = allocateSource();
      sourceInstances[id] = sourceInstance();
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
    auto references = DefinitionReferences(diagnostics).collect(tree);
    definitionReferences.insert(definitionReferences.end(),
                                std::make_move_iterator(references.begin()),
                                std::make_move_iterator(references.end()));
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
    result.inactiveSyntax.insert(result.inactiveSyntax.end(),
                                 tree.inactiveSyntax.begin(),
                                 tree.inactiveSyntax.end());
    result.tokens.insert(result.tokens.end(),
                         std::make_move_iterator(tree.tokens.begin()),
                         std::make_move_iterator(tree.tokens.end()));
  }
};
} // namespace

std::optional<Module> load(Source root, const SourceProvider &provider,
                           Diagnostics &diagnostics, const Library &library,
                           std::vector<SourceModule> *sourceModules,
                           std::vector<SourceModule> *allSources,
                           SourcePackages *sourcePackages) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Loader(provider, diagnostics, library, sourceModules, allSources,
                sourcePackages)
      .run(std::move(root));
}

std::optional<Module> load(const std::vector<Source> &sources,
                           Diagnostics &diagnostics, const Library &library,
                           SourcePackages *sourcePackages) {
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
  return load(sources.front(), provider, diagnostics, library, nullptr, nullptr,
              sourcePackages);
}
} // namespace mettle::resolution
