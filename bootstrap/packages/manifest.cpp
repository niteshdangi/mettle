#include "packages/manifest.h"
#include <algorithm>
#include <filesystem>
#include <set>

namespace mettle::packages {
std::string gitSelector(const DependencySpec &dependency) {
  if (dependency.rev)
    return "rev=" + *dependency.rev;
  if (dependency.tag)
    return "tag=" + *dependency.tag;
  if (dependency.branch)
    return "branch=" + *dependency.branch;
  return "HEAD";
}

namespace {
using Kind = data::Value::Kind;

bool validMacroName(const std::string &name) {
  return !name.empty() && name[0] >= 'a' && name[0] <= 'z' &&
         std::all_of(name.begin(), name.end(), [](char c) {
           return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
         });
}

class Reader {
public:
  Reader(Diagnostics &diagnostics, const Source &source)
      : diagnostics(diagnostics), source(source) {}
  bool failed = false;

  void error(Span span, std::string message, const char *phase = "package") {
    span.source = source.id;
    diagnostics.error(phase, span, std::move(message));
    failed = true;
  }

  const std::string *string(const data::Value &value, const char *what) {
    if (value.kind != Kind::String) {
      error(value.span, std::string(what) + " must be a string");
      return nullptr;
    }
    return &value.string;
  }

  bool known(const data::Value &table, const char *where,
             std::initializer_list<const char *> allowed) {
    bool ok = true;
    for (const auto &entry : table.object)
      if (std::none_of(allowed.begin(), allowed.end(),
                       [&](const char *name) { return entry.first == name; })) {
        error(entry.second.key,
              "unknown key '" + entry.first + "' in " + where);
        ok = false;
      }
    return ok;
  }

  std::optional<Requirement> requirement(const data::Value &value) {
    std::vector<Requirement> parts;
    auto one = [&](const data::Value &item) {
      auto *text = string(item, "a version requirement");
      if (!text)
        return false;
      std::string why;
      auto parsed = parseRequirement(*text, why);
      if (!parsed) {
        error(item.span, "invalid version requirement '" + *text + "': " + why);
        return false;
      }
      parts.push_back(std::move(*parsed));
      return true;
    };
    if (value.kind == Kind::Array) {
      if (value.array.empty()) {
        error(value.span, "a version requirement list must not be empty");
        return std::nullopt;
      }
      for (const auto &item : value.array)
        if (!one(item))
          return std::nullopt;
    } else if (!one(value))
      return std::nullopt;
    return unite(std::move(parts));
  }

  void dependencies(const data::Value &table, const char *section,
                    std::vector<DependencySpec> &out) {
    if (table.kind != Kind::Object) {
      error(table.span, std::string("[") + section + "] must be a table");
      return;
    }
    for (const auto &[name, value] : table.object) {
      DependencySpec spec;
      spec.name = name;
      spec.span = value.key;
      if (!validPackageName(name)) {
        error(value.key, "invalid package name '" + name +
                             "' (expected [a-z][a-z0-9_-]*)");
        continue;
      }
      if (value.kind == Kind::String &&
          (value.string.starts_with("./") || value.string.starts_with("../") ||
           std::filesystem::path(value.string).is_absolute())) {
        spec.path = value.string;
      } else if (value.kind == Kind::String || value.kind == Kind::Array) {
        spec.requirement = requirement(value);
        if (!spec.requirement)
          continue;
      } else if (value.kind == Kind::Object) {
        if (!known(value, "a dependency",
                   {"path", "git", "rev", "tag", "branch", "version",
                    "features", "default_features", "optional"}))
          continue;
        if (const auto *path = value.find("path")) {
          if (const auto *text = string(*path, "'path'"))
            spec.path = *text;
          else
            continue;
        }
        if (const auto *git = value.find("git")) {
          if (const auto *text = string(*git, "'git'"))
            spec.git = *text;
          else
            continue;
        }
        for (auto [key, target] :
             {std::pair<const char *, std::optional<std::string> *>{"rev",
                                                                    &spec.rev},
              {"tag", &spec.tag},
              {"branch", &spec.branch}}) {
          if (const auto *selector = value.find(key))
            if (const auto *text = string(*selector, key))
              *target = *text;
        }
        auto selectors = static_cast<unsigned>(spec.rev.has_value()) +
                         static_cast<unsigned>(spec.tag.has_value()) +
                         static_cast<unsigned>(spec.branch.has_value());
        if (spec.path && spec.git) {
          error(value.key, "a dependency cannot specify both 'path' and 'git'");
          continue;
        }
        if (spec.git && selectors > 1) {
          error(value.key,
                "a git dependency may specify only one of 'rev', 'tag' or "
                "'branch'");
          continue;
        }
        if (!spec.git && selectors != 0) {
          error(value.key, "'rev', 'tag' and 'branch' require 'git'");
          continue;
        }
        if (spec.git && spec.git->empty()) {
          error(value.key, "'git' must not be empty");
          continue;
        }
        if (const auto *version = value.find("version")) {
          spec.requirement = requirement(*version);
          if (!spec.requirement)
            continue;
        }
        if (!spec.path && !spec.git && !spec.requirement) {
          error(value.key, "dependency '" + name +
                               "' needs a 'path' or a 'version' requirement");
          continue;
        }
        if (const auto *features = value.find("features")) {
          if (features->kind != Kind::Array) {
            error(features->span, "'features' must be an array of strings");
            continue;
          }
          bool ok = true;
          for (const auto &item : features->array) {
            if (const auto *text = string(item, "a feature name"))
              spec.features.push_back(*text);
            else
              ok = false;
          }
          if (!ok)
            continue;
        }
        for (auto [key, target] :
             {std::pair<const char *, bool *>{"default_features",
                                              &spec.defaultFeatures},
              {"optional", &spec.optional}}) {
          if (const auto *flag = value.find(key)) {
            if (flag->kind != Kind::Boolean)
              error(flag->span, std::string("'") + key + "' must be a boolean");
            else
              *target = flag->boolean;
          }
        }
      } else {
        error(value.span, "a dependency must be a version string or a table");
        continue;
      }
      out.push_back(std::move(spec));
    }
  }

private:
  Diagnostics &diagnostics;
  const Source &source;
};
} // namespace

bool validPackageName(const std::string &name) {
  if (name.empty() || name[0] < 'a' || name[0] > 'z')
    return false;
  return std::all_of(name.begin(), name.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' ||
           c == '-';
  });
}

std::string moduleName(const std::string &package) {
  auto name = package;
  std::replace(name.begin(), name.end(), '-', '_');
  return name;
}

const DependencySpec *Manifest::dependency(const std::string &name) const {
  for (const auto &item : dependencies)
    if (item.name == name)
      return &item;
  return nullptr;
}

const Feature *Manifest::feature(const std::string &name) const {
  for (const auto &item : features)
    if (item.name == name)
      return &item;
  return nullptr;
}

const Target *Manifest::library() const {
  for (const auto &target : targets)
    if (target.kind == "library")
      return &target;
  return nullptr;
}

std::optional<Manifest> parseManifest(const data::Value &root,
                                      const Source &source,
                                      const std::string &directory,
                                      Diagnostics &diagnostics) {
  Reader reader(diagnostics, source);
  Manifest manifest;
  manifest.directory = directory;
  manifest.source = source.id;
  if (root.kind != Kind::Object) {
    reader.error(root.span, "package.mettle must contain an object");
    return std::nullopt;
  }
  reader.known(root, "package.mettle",
               {"name", "version", "mettle-version", "description", "kind",
                "emit", "entry", "dependencies", "dev-dependencies",
                "build-dependencies", "features", "registry", "build",
                "macros"});
  const auto *package = &root;
  auto require = [&](const char *key) -> const data::Value * {
    const auto *value = package->find(key);
    if (!value)
      reader.error(package->span,
                   std::string("package.mettle needs '") + key + "'");
    return value;
  };
  if (const auto *name = require("name")) {
    if (const auto *text = reader.string(*name, "'name'")) {
      manifest.name = *text;
      manifest.nameSpan = name->span;
      if (!validPackageName(*text))
        reader.error(name->span, "invalid package name '" + *text +
                                     "' (expected [a-z][a-z0-9_-]*)");
      else if (*text == "core" || *text == "alloc" || *text == "std" ||
               moduleName(*text) == "package" || moduleName(*text) == "self" ||
               moduleName(*text) == "super")
        reader.error(name->span, "package name '" + *text +
                                     "' collides with a reserved module root");
    }
  }
  if (const auto *version = require("version")) {
    if (const auto *text = reader.string(*version, "'version'")) {
      if (auto parsed = parseVersion(*text))
        manifest.version = std::move(*parsed);
      else
        reader.error(version->span, "invalid SemVer version '" + *text + "'");
    }
  }
  if (const auto *required = root.find("mettle-version")) {
    manifest.mettleVersionSpan = required->span;
    if (const auto *text = reader.string(*required, "'mettle-version'")) {
      manifest.mettleVersion = parseVersion(*text);
      if (!manifest.mettleVersion)
        reader.error(required->span,
                     "'mettle-version' must be a minimum compiler version in "
                     "MAJOR.MINOR.PATCH form");
    }
  }
  auto addEntry = [&](const std::string &name, const data::Value *value,
                      bool primary) {
    if (!validPackageName(name)) {
      reader.error(value ? value->key : root.span,
                   "invalid entry name '" + name + "'");
      return;
    }
    const auto *fields = value && value->kind == Kind::Object ? value : &root;
    if (fields != &root)
      reader.known(*fields, "an entry", {"kind", "path", "emit"});
    if (fields != &root && !primary && !fields->find("path"))
      reader.error(fields->span, "a named entry requires 'path'");
    Span span = value ? value->span : root.span;
    std::string kind = "executable", path = "src/main.mt";
    if (const auto *item = fields->find("kind"))
      if (const auto *text = reader.string(*item, "'kind'"))
        kind = *text;
    if (kind != "library" && kind != "executable") {
      reader.error(span, "entry kind must be 'library' or 'executable'");
      return;
    }
    const auto *file = fields != &root ? fields->find("path") : value;
    if (file)
      if (const auto *text = reader.string(*file, "an entry path"))
        path = *text;
    if (path.empty() || path.find('\0') != std::string::npos) {
      reader.error(span, "an entry must be a nonempty path without NUL bytes");
      return;
    }
    std::vector<std::string> emits;
    if (const auto *requested = fields->find("emit")) {
      auto one = [&](const data::Value &item) {
        if (const auto *text = reader.string(item, "an emit format")) {
          bool valid = kind == "library"
                           ? (*text == "static" || *text == "shared" ||
                              *text == "package" || *text == "object" ||
                              *text == "llvm" || *text == "ir")
                           : (*text == "executable" || *text == "object" ||
                              *text == "llvm" || *text == "ir");
          if (!valid)
            reader.error(item.span, "emit format '" + *text +
                                        "' is incompatible with '" + kind +
                                        "'");
          else if (std::find(emits.begin(), emits.end(), *text) != emits.end())
            reader.error(item.span, "duplicate emit format '" + *text + "'");
          else
            emits.push_back(*text);
        }
      };
      if (requested->kind == Kind::Array) {
        for (const auto &item : requested->array)
          one(item);
        if (requested->array.empty())
          reader.error(requested->span, "'emit' must not be empty");
      } else
        one(*requested);
    } else
      emits.push_back(kind == "library" ? "static" : "executable");
    manifest.targets.push_back({name, kind, path, span, std::move(emits)});
  };
  const auto *entry = root.find("entry");
  if (entry && entry->kind == Kind::Object) {
    if (root.find("kind") || root.find("emit"))
      reader.error(entry->span,
                   "an entry map declares 'kind' and 'emit' per entry");
    if (!entry->find("main"))
      reader.error(entry->span, "an entry map must define 'main'");
    for (const auto &[name, value] : entry->object)
      addEntry(name, &value, name == "main");
  } else if (entry) {
    addEntry("main", entry, true);
  } else if (root.find("kind") || root.find("emit") ||
             std::filesystem::exists(std::filesystem::path(directory) /
                                     "src/main.mt"))
    addEntry("main", nullptr, true);
  if (std::count_if(
          manifest.targets.begin(), manifest.targets.end(),
          [](const Target &target) { return target.kind == "library"; }) > 1)
    reader.error(root.span, "a package has at most one library entry");
  if (const auto *table = root.find("dependencies"))
    reader.dependencies(*table, "dependencies", manifest.dependencies);
  if (const auto *table = root.find("build-dependencies"))
    reader.dependencies(*table, "build-dependencies",
                        manifest.buildDependencies);
  for (const auto &dependency : manifest.buildDependencies)
    if (dependency.optional)
      reader.error(dependency.span,
                   "optional build-dependencies are not supported");
  if (const auto *table = root.find("dev-dependencies"))
    reader.dependencies(*table, "dev-dependencies", manifest.devDependencies);
  for (const auto &dependency : manifest.devDependencies)
    if (dependency.optional)
      reader.error(dependency.span,
                   "development dependencies cannot be optional");
  for (const auto *list : {&manifest.dependencies, &manifest.buildDependencies,
                           &manifest.devDependencies})
    for (const auto &dependency : *list)
      if (moduleName(dependency.name) == moduleName(manifest.name))
        reader.error(dependency.span,
                     "dependency '" + dependency.name +
                         "' has the name of its own package; a package name "
                         "and its dependency names share one namespace");
  if (const auto *registry = root.find("registry")) {
    if (registry->kind != Kind::Object ||
        !reader.known(*registry, "[registry]", {"path"}))
      reader.error(registry->span, "[registry] must be a table with 'path'");
    else if (const auto *path = registry->find("path")) {
      if (const auto *text = reader.string(*path, "'path'"))
        manifest.registry = *text;
    }
  }
  if (const auto *build = root.find("build")) {
    if (build->kind != Kind::Object ||
        !reader.known(*build, "[build]", {"script"}))
      reader.error(build->span, "[build] must be a table with 'script'");
    else if (const auto *script = build->find("script")) {
      if (const auto *text = reader.string(*script, "'script'")) {
        manifest.buildScript = *text;
        manifest.buildScriptSpan = script->span;
      }
    }
  }
  if (const auto *macros = root.find("macros")) {
    if (macros->kind != Kind::Object)
      reader.error(macros->span, "[macros] must be a table of macros");
    else
      for (const auto &[name, value] : macros->object) {
        if (value.kind != Kind::Object) {
          reader.error(value.span,
                       "a macro must be a table with 'source' and 'api'");
          continue;
        }
        reader.known(value, "a macro", {"source", "api"});
        MacroDecl macro;
        macro.name = name;
        macro.span = value.key;
        if (!validMacroName(name))
          reader.error(value.key, "invalid macro name '" + name +
                                      "' (expected [a-z][a-z0-9_]*)");
        const auto *file = value.find("source");
        const auto *api = value.find("api");
        if (!file || !api) {
          reader.error(value.key,
                       "macro '" + name + "' needs 'source' and 'api'");
          continue;
        }
        if (const auto *text = reader.string(*file, "'source'"))
          macro.source = *text;
        if (api->kind != Kind::Integer)
          reader.error(api->span, "'api' must be an integer major version");
        else if (api->integer != 1)
          reader.error(api->span,
                       "unsupported macro API major version " +
                           std::to_string(api->integer) + " (supported: 1)",
                       "feature");
        else
          macro.api = api->integer;
        if (!macro.source.empty() && macro.api == 1)
          manifest.macros.push_back(std::move(macro));
      }
  }
  if (const auto *features = root.find("features")) {
    if (features->kind != Kind::Object)
      reader.error(features->span, "[features] must be a table");
    else
      for (const auto &[name, value] : features->object) {
        Feature feature;
        feature.name = name;
        feature.span = value.key;
        if (value.kind != Kind::Array) {
          reader.error(value.span,
                       "feature '" + name + "' must list its enabled items");
          continue;
        }
        for (const auto &item : value.array)
          if (const auto *text = reader.string(item, "a feature item"))
            feature.items.push_back(*text);
        manifest.features.push_back(std::move(feature));
      }
  }
  // A feature item names a feature, `dep:optional-dependency` or
  // `dependency/feature`; `dep:` suppresses the implicit feature.
  std::set<std::string> suppressed;
  for (const auto &feature : manifest.features)
    for (const auto &item : feature.items)
      if (item.rfind("dep:", 0) == 0)
        suppressed.insert(item.substr(4));
  for (const auto &feature : manifest.features)
    for (const auto &item : feature.items) {
      auto bad = [&](const std::string &message) {
        reader.error(feature.span,
                     "feature '" + feature.name + "': " + message);
      };
      if (item.rfind("dep:", 0) == 0) {
        const auto *dep = manifest.dependency(item.substr(4));
        if (!dep || !dep->optional)
          bad("'" + item + "' must name an optional dependency");
      } else if (auto slash = item.find('/'); slash != std::string::npos) {
        if (!manifest.dependency(item.substr(0, slash)))
          bad("'" + item + "' names no dependency");
      } else {
        const auto *dep = manifest.dependency(item);
        bool implicit = dep && dep->optional && !suppressed.contains(item);
        if (!manifest.feature(item) && !implicit)
          bad("'" + item + "' is not a feature of this package");
        else if (item == feature.name)
          bad("a feature cannot enable itself");
      }
    }
  if (reader.failed)
    return std::nullopt;
  return manifest;
}
} // namespace mettle::packages
