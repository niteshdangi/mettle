#include "driver/document.h"
#include "documentation/html.h"
#include "expansion/macros.h"
#include "packages/plan.h"
#include "resolution/load.h"
#include "resolution/resolve.h"
#include "support/path.h"
#include "syntax/parser.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <set>
#include <string_view>
#include <utility>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

struct Input {
  fs::path file;
  std::string name;
};

// A page is named by its path below the given directory: `net/http.mt` is
// `net.http` and a directory's `module.mt` names the directory itself.
std::string pageName(const fs::path &relative) {
  auto stem = relative;
  stem.replace_extension();
  if (stem.filename() == "module" && stem.has_parent_path())
    stem = stem.parent_path();
  std::string name;
  for (const auto &part : stem)
    name += (name.empty() ? "" : "::") + part.generic_string();
  return displayPath(name);
}

bool gather(const std::string &argument, std::vector<Input> &inputs) {
  std::error_code error;
  fs::path path(argument);
  if (fs::is_directory(path, error)) {
    std::vector<Input> found;
    for (fs::recursive_directory_iterator walk(path, error), end;
         !error && walk != end; walk.increment(error)) {
      auto name = walk->path().filename().string();
      if (walk->is_directory(error) &&
          (name == "target" || name.starts_with("."))) {
        walk.disable_recursion_pending();
        continue;
      }
      if (walk->is_regular_file(error) && walk->path().extension() == ".mt")
        found.push_back(
            {walk->path(), pageName(fs::relative(walk->path(), path))});
    }
    if (error) {
      std::cerr << "mettle: error[io]: cannot read " << argument << ": "
                << error.message() << '\n';
      return false;
    }
    inputs.insert(inputs.end(), found.begin(), found.end());
    return true;
  }
  if (!fs::is_regular_file(path, error)) {
    std::cerr << "mettle: error[io]: cannot read " << argument << '\n';
    return false;
  }
  inputs.push_back({path, pageName(path.filename())});
  return true;
}

bool write(const fs::path &path, const std::string &content) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  out << content;
  out.flush();
  return static_cast<bool>(out);
}

bool packageInput(const std::string &argument) {
  std::error_code error;
  auto path = fs::path(argument);
  if (fs::is_regular_file(path, error))
    return path.filename() == "Mettle.toml";
  error.clear();
  return fs::is_directory(path, error) &&
         fs::is_regular_file(path / "Mettle.toml", error);
}

std::string joined(const std::vector<std::string> &path, std::string_view sep) {
  std::string result;
  for (const auto &part : path)
    result += (result.empty() ? "" : std::string(sep)) + part;
  return result;
}

resolution::Namespace itemNamespace(documentation::Kind kind) {
  using Kind = documentation::Kind;
  switch (kind) {
  case Kind::Function:
  case Kind::Constant:
  case Kind::Variant:
  case Kind::Field:
    return resolution::Namespace::Value;
  case Kind::Type:
  case Kind::Union:
  case Kind::Enum:
  case Kind::Interface:
  case Kind::Alias:
    return resolution::Namespace::Type;
  case Kind::Module:
    return resolution::Namespace::Module;
  case Kind::Macro:
    return resolution::Namespace::Macro;
  case Kind::Implementation:
    return resolution::Namespace::Value;
  }
  return resolution::Namespace::Value;
}

void resolveItems(std::vector<documentation::Item> &items,
                  const resolution::Resolution &names,
                  std::set<std::string> &documented, std::uint32_t pageScope,
                  std::string_view owner = {}) {
  for (auto &item : items) {
    // Extracted item spans may extend past the resolver's item interval; the
    // page's own module is then the enclosing scope.
    auto inner = names.moduleOf(item.span);
    item.scope = inner != 0 ? inner : pageScope;
    bool associated =
        item.kind == documentation::Kind::Variant ||
        (!owner.empty() && item.kind == documentation::Kind::Function);
    bool resolvable = item.kind != documentation::Kind::Field &&
                      item.kind != documentation::Kind::Implementation &&
                      item.kind != documentation::Kind::Macro;
    if (resolvable) {
      auto spelling =
          associated ? std::string(owner) + "::" + item.name : item.name;
      auto canonical = names.lookup(
          item.scope, spelling, itemNamespace(item.kind), item.span, nullptr);
      if (canonical) {
        item.canonical = *canonical;
        documented.insert(*canonical);
        if (item.kind == documentation::Kind::Module)
          for (std::size_t module = 0; module < names.modules().size();
               ++module)
            if (names.modules()[module].canonical == *canonical) {
              item.scope = static_cast<std::uint32_t>(module);
              break;
            }
      }
    }
    auto memberOwner = item.kind == documentation::Kind::Type ||
                               item.kind == documentation::Kind::Union ||
                               item.kind == documentation::Kind::Enum ||
                               item.kind == documentation::Kind::Interface
                           ? std::string_view(item.name)
                           : std::string_view{};
    resolveItems(item.members, names, documented, pageScope, memberOwner);
  }
}

void replaceDots(std::string &path) {
  for (std::size_t at = path.find('.'); at != std::string::npos;
       at = path.find('.', at + 2))
    path.replace(at, 1, "::");
}
} // namespace

int document(const Options &options) {
  std::vector<documentation::Page> pages;
  Diagnostics diagnostics;
  std::map<SourceId, Source> sources;
  std::set<SourceId> resolvedSources;
  std::shared_ptr<const resolution::Resolution> names;
  std::set<std::string> loadedPaths;
  int status = 0;
  bool package = packageInput(options.input);
  if (package) {
    auto outcome = packages::plan(packageRequest(options), diagnostics);
    if (!outcome.plan) {
      diagnostics.print(outcome.fallback, std::cerr);
      return 1;
    }
    auto read = [](const std::string &path) -> std::optional<Source> {
      std::ifstream in(path, std::ios::binary);
      if (!in)
        return std::nullopt;
      std::string text((std::istreambuf_iterator<char>(in)),
                       std::istreambuf_iterator<char>());
      if (!in && !in.eof())
        return std::nullopt;
      std::error_code error;
      auto canonical = fs::canonical(path, error);
      return Source{error ? fs::path(path).lexically_normal().generic_string()
                          : canonical.generic_string(),
                    std::move(text)};
    };
    auto root = read(outcome.plan->root);
    if (!root) {
      std::cerr << "mettle: error[io]: cannot read " << outcome.plan->root
                << '\n';
      return 1;
    }
    resolution::SourceProvider provider = [&](const std::string &path) {
      return read(path);
    };
    resolution::Library library;
    library.directory = options.libraryDirectory;
    library.freestanding = options.freestanding;
    library.configuration.features = std::set<std::string>(
        outcome.plan->features.begin(), outcome.plan->features.end());
    library.packageDependencies = outcome.plan->dependencies;
    for (const auto &mount : outcome.plan->mounts) {
      std::set<std::string> features(mount.features.begin(),
                                     mount.features.end());
      resolution::Library::Package dependency;
      dependency.name = mount.name;
      dependency.source = mount.source;
      dependency.module = mount.module;
      dependency.dependencies = mount.dependencies;
      dependency.features = std::move(features);
      library.packages.push_back(std::move(dependency));
    }
    std::vector<resolution::SourceModule> loadedSources;
    auto tree = resolution::load(*root, provider, diagnostics, library, nullptr,
                                 &loadedSources);
    if (tree)
      names = resolution::resolve(*tree, diagnostics);
    if (!tree || !names || !diagnostics.empty()) {
      diagnostics.print(*root, std::cerr);
      return 1;
    }
    std::map<std::string, std::string> packageNames;
    for (const auto &mount : outcome.plan->mounts) {
      auto name = mount.name;
      std::replace(name.begin(), name.end(), '-', '_');
      packageNames.emplace(mount.module, std::move(name));
    }
    for (const auto &loaded : loadedSources) {
      auto display = loaded.path;
      if (!display.empty())
        if (auto alias = packageNames.find(display.front());
            alias != packageNames.end())
          display.front() = alias->second;
      auto page = joined(display, ".");
      if (page.empty()) {
        std::error_code error;
        auto sourceRoot = fs::path(outcome.plan->root).parent_path();
        page = pageName(fs::relative(loaded.source.path, sourceRoot, error));
        if (error)
          page = pageName(fs::path(loaded.source.path).filename());
      }
      auto extracted = documentation::extract(loaded.source, std::move(page),
                                              options.documentPrivate);
      extracted.canonical = joined(loaded.path, "::");
      for (std::size_t module = 0; module < names->modules().size(); ++module)
        if (names->modules()[module].canonical == extracted.canonical) {
          extracted.scope = static_cast<std::uint32_t>(module);
          break;
        }
      sources.emplace(loaded.source.id, loaded.source);
      resolvedSources.insert(loaded.source.id);
      loadedPaths.insert(
          fs::path(loaded.source.path).lexically_normal().generic_string());
      pages.push_back(std::move(extracted));
    }
    SourceId nextSource =
        sources.empty() ? 0
                        : static_cast<SourceId>(sources.rbegin()->first + 1);
    std::vector<Input> extraInputs;
    for (const auto &argument : options.moreInputs)
      if (!gather(argument, extraInputs))
        status = 1;
    std::stable_sort(extraInputs.begin(), extraInputs.end(),
                     [](const Input &left, const Input &right) {
                       return left.file.generic_string() <
                              right.file.generic_string();
                     });
    for (const auto &input : extraInputs) {
      auto identity = input.file.lexically_normal().generic_string();
      if (!loadedPaths.insert(identity).second)
        continue;
      auto source = read(identity);
      if (!source) {
        std::cerr << "mettle: error[io]: cannot read " << identity << '\n';
        status = 1;
        continue;
      }
      source->id = nextSource++;
      auto expanded = expansion::expandMacros(*source, diagnostics,
                                              [&] { return nextSource++; });
      parse(expanded ? *expanded : *source, diagnostics);
      if (!diagnostics.empty()) {
        diagnostics.print(*source, std::cerr);
        diagnostics = {};
        status = 1;
        continue;
      }
      sources.emplace(source->id, *source);
      pages.push_back(
          documentation::extract(*source, input.name, options.documentPrivate));
    }
  } else {
    if (options.packageOptions) {
      std::cerr << "mettle: error[package]: package options need a package "
                   "directory or Mettle.toml\n";
      return 2;
    }
    std::vector<std::string> arguments{options.input};
    arguments.insert(arguments.end(), options.moreInputs.begin(),
                     options.moreInputs.end());
    std::vector<Input> inputs;
    for (const auto &argument : arguments)
      if (!gather(argument, inputs))
        status = 1;
    std::stable_sort(inputs.begin(), inputs.end(),
                     [](const Input &left, const Input &right) {
                       return left.file.generic_string() <
                              right.file.generic_string();
                     });
    std::set<std::string> seen;
    for (const auto &input : inputs) {
      auto display = input.file.lexically_normal().generic_string();
      if (!seen.insert(display).second)
        continue;
      std::ifstream in(input.file, std::ios::binary);
      std::string text((std::istreambuf_iterator<char>(in)),
                       std::istreambuf_iterator<char>());
      if (!in && !in.eof()) {
        std::cerr << "mettle: error[io]: cannot read " << display << '\n';
        status = 1;
        continue;
      }
      Source source{display, std::move(text)};
      SourceId next = source.id + 1;
      auto expanded =
          expansion::expandMacros(source, diagnostics, [&] { return next++; });
      parse(expanded ? *expanded : source, diagnostics);
      if (!diagnostics.empty()) {
        diagnostics.print(source, std::cerr);
        status = 1;
        diagnostics = {};
        continue;
      }
      source.id = static_cast<SourceId>(sources.size());
      sources.emplace(source.id, source);
      pages.push_back(
          documentation::extract(source, input.name, options.documentPrivate));
    }
  }
  std::set<std::string> documented;
  if (names)
    for (auto &page : pages)
      if (resolvedSources.contains(page.span.source))
        resolveItems(page.items, *names, documented, page.scope);
  for (const auto &page : pages)
    if (!page.canonical.empty())
      documented.insert(page.canonical);
  documentation::ReferenceResolver resolver;
  if (names) {
    resolver = [&](std::uint32_t scope, Span span,
                   std::string_view spelling) -> std::optional<std::string> {
      std::string canonicalPath(spelling);
      replaceDots(canonicalPath);
      std::set<std::string> matches;
      for (auto space :
           {resolution::Namespace::Type, resolution::Namespace::Value,
            resolution::Namespace::Module, resolution::Namespace::Macro})
        if (auto resolved =
                names->lookup(scope, canonicalPath, space, span, nullptr))
          matches.insert(*resolved);
      auto warn = [&](std::string message) {
        auto source = sources.find(span.source);
        if (source != sources.end()) {
          Diagnostics::SourceContext context(diagnostics, source->second);
          diagnostics.warning("doc-link", span, std::move(message));
        }
      };
      if (matches.size() != 1) {
        warn("unresolved documentation reference '" + std::string(spelling) +
             "'");
        return std::nullopt;
      }
      const auto &target = *matches.begin();
      if (!documented.contains(target)) {
        warn("documentation reference '" + std::string(spelling) +
             "' has no generated page");
        return std::nullopt;
      }
      return target;
    };
  } else {
    resolver = [&](std::uint32_t, Span span,
                   std::string_view spelling) -> std::optional<std::string> {
      auto source = sources.find(span.source);
      if (source != sources.end()) {
        Diagnostics::SourceContext context(diagnostics, source->second);
        diagnostics.warning("doc-link", span,
                            "cannot resolve documentation reference '" +
                                std::string(spelling) +
                                "' without a package name graph");
      }
      return std::nullopt;
    };
  }
  fs::path directory = options.output;
  if (directory.empty()) {
    std::error_code error;
    auto base =
        fs::is_directory(options.input, error) && options.moreInputs.empty()
            ? fs::path(options.input)
            : fs::path();
    directory = base / "target" / "mettle" / "doc";
  }
  std::error_code error;
  fs::create_directories(directory, error);
  if (error) {
    std::cerr << "mettle: error[io]: cannot create " << directory.string()
              << ": " << error.message() << '\n';
    return 1;
  }
  for (const auto &file : documentation::render(pages, resolver))
    if (!write(directory / file.name, file.content)) {
      std::cerr << "mettle: error[io]: cannot write "
                << (directory / file.name).string() << '\n';
      return 1;
    }
  if (!diagnostics.empty()) {
    auto source = sources.empty() ? Source{} : sources.begin()->second;
    diagnostics.print(source, std::cerr);
  }
  std::cout << "mettle: documented " << pages.size()
            << (pages.size() == 1 ? " module" : " modules") << " into "
            << (directory / "index.html").generic_string() << '\n';
  return status;
}
} // namespace mettle::driver
