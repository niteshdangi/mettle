#include "packages/plan.h"
#include "packages/lock.h"
#include "packages/manifest.h"
#include "packages/sha256.h"
#include "packages/solver.h"
#include "packages/toml.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>

namespace mettle::packages {
namespace {
namespace fs = std::filesystem;

std::optional<std::string> readFile(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream)
    return std::nullopt;
  std::ostringstream text;
  text << stream.rdbuf();
  return text.str();
}

// Content identity of a package: its manifest and every Mettle source, by
// relative path. Hidden directories, `target` and `build` are not inputs.
std::string checksum(const fs::path &directory) {
  std::vector<std::pair<std::string, fs::path>> files;
  for (fs::recursive_directory_iterator it(directory), end; it != end; ++it) {
    const auto name = it->path().filename().string();
    if (it->is_directory()) {
      if (name.rfind('.', 0) == 0 || name == "target" || name == "build")
        it.disable_recursion_pending();
      continue;
    }
    if (it->is_regular_file() &&
        (it->path().extension() == ".mt" || name == "Mettle.toml"))
      files.emplace_back(
          it->path().lexically_relative(directory).generic_string(),
          it->path());
  }
  std::sort(files.begin(), files.end());
  Sha256 hash;
  for (const auto &[relative, path] : files) {
    auto text = readFile(path).value_or("");
    hash.update(relative);
    hash.update(std::string_view("\0", 1));
    hash.update(std::to_string(text.size()));
    hash.update(std::string_view("\0", 1));
    hash.update(text);
  }
  return "sha256:" + hash.finish();
}

class Planner {
public:
  Planner(const Request &request, Diagnostics &diagnostics)
      : request(request), diagnostics(diagnostics) {}

  Outcome run() {
    Outcome outcome;
    std::error_code error;
    fs::path input(request.input);
    if (fs::is_directory(input, error))
      rootDirectory = fs::canonical(input, error);
    else if (input.filename() == "Mettle.toml")
      rootDirectory = fs::canonical(
          input.parent_path().empty() ? fs::path(".") : input.parent_path(),
          error);
    else {
      outcome.fallback = {request.input, "", 0};
      diagnostics.error(
          "io", {},
          "'" + request.input +
              "' is neither a package directory nor a Mettle.toml");
      return outcome;
    }
    outcome.fallback = {(rootDirectory / "Mettle.toml").generic_string(), "",
                        0};
    if (error) {
      diagnostics.error("io", {}, "cannot open package: " + error.message());
      return outcome;
    }
    auto root = loadManifest(rootDirectory, {});
    if (!sources.empty())
      outcome.fallback.text = sources.front().text;
    if (root)
      outcome.plan = build(root);
    return outcome;
  }

private:
  const Request &request;
  Diagnostics &diagnostics;
  fs::path rootDirectory;
  SourceId nextId = 0;
  std::vector<Source> sources;
  std::map<std::string, std::shared_ptr<const Manifest>> loaded;
  std::vector<fs::path> registries;

  bool failed() const { return !diagnostics.empty(); }

  std::string display(const fs::path &path) const {
    auto relative = path.lexically_relative(rootDirectory).generic_string();
    return relative.empty() ? "." : relative;
  }

  std::shared_ptr<const Manifest> loadManifest(const fs::path &directory,
                                               std::optional<Span> at) {
    auto key = directory.generic_string();
    if (auto found = loaded.find(key); found != loaded.end())
      return found->second;
    auto &slot = loaded[key];
    auto path = directory / "Mettle.toml";
    auto text = readFile(path);
    if (!text) {
      diagnostics.error("io", at.value_or(Span{}),
                        "cannot read " + path.generic_string());
      return slot;
    }
    sources.push_back({path.generic_string(), std::move(*text), nextId++});
    const auto &source = sources.back();
    auto tree = toml::parse(source, diagnostics, "manifest");
    if (!tree)
      return slot;
    auto manifest =
        parseManifest(*tree, source, directory.generic_string(), diagnostics);
    if (manifest)
      slot = std::make_shared<const Manifest>(std::move(*manifest));
    return slot;
  }

  std::optional<Candidate> loadPath(const Manifest &from,
                                    const DependencySpec &spec) {
    std::error_code error;
    auto directory =
        fs::weakly_canonical(fs::path(from.directory) / *spec.path, error);
    if (error || !fs::is_directory(directory)) {
      diagnostics.error("package", spec.span,
                        "path dependency '" + spec.name + "' does not exist: " +
                            (fs::path(from.directory) / *spec.path)
                                .lexically_normal()
                                .generic_string());
      return std::nullopt;
    }
    auto manifest = loadManifest(directory, spec.span);
    if (!manifest)
      return std::nullopt;
    if (manifest->name != spec.name) {
      diagnostics.error("package", spec.span,
                        "dependency '" + spec.name + "' at '" + *spec.path +
                            "' is the package '" + manifest->name + "'");
      return std::nullopt;
    }
    return Candidate{
        manifest, SourceKind::Path, directory.generic_string(), {}, false};
  }

  std::vector<Candidate> registryCandidates(const std::string &name) {
    std::vector<Candidate> found;
    for (const auto &registry : registries) {
      std::error_code error;
      std::vector<fs::path> versions;
      for (fs::directory_iterator it(registry / name, error), end;
           !error && it != end; it.increment(error))
        if (it->is_directory())
          versions.push_back(it->path());
      std::sort(versions.begin(), versions.end());
      for (const auto &directory : versions) {
        auto version = parseVersion(directory.filename().string());
        if (!version)
          continue;
        if (std::any_of(found.begin(), found.end(), [&](const Candidate &c) {
              return compare(c.manifest->version, *version) == 0;
            }))
          continue;
        auto manifest = loadManifest(directory, {});
        if (!manifest)
          continue;
        if (manifest->name != name ||
            compare(manifest->version, *version) != 0) {
          diagnostics.error("package", manifest->nameSpan,
                            "registry entry '" + display(directory) +
                                "' contains package '" + manifest->name + "' " +
                                toString(manifest->version));
          continue;
        }
        found.push_back({manifest, SourceKind::Registry,
                         directory.generic_string(), display(registry),
                         fs::exists(directory / "YANKED")});
      }
    }
    return found;
  }

  std::string absence() const {
    std::string text;
    if (registries.empty())
      text = "no registry is configured (use [registry] path in Mettle.toml "
             "or --registry DIR)";
    else {
      text = "not present in the local registries";
      for (const auto &registry : registries)
        text += " '" + display(registry) + "'";
    }
    return text +
           (request.offline
                ? "; offline mode never fetches packages"
                : "; fetching from remote registries is not implemented");
  }

  static std::string sourceOf(const Candidate &candidate,
                              const fs::path &root) {
    switch (candidate.kind) {
    case SourceKind::Root:
      return "root";
    case SourceKind::Path:
      return "path+" + fs::path(candidate.location)
                           .lexically_relative(root)
                           .generic_string();
    case SourceKind::Registry:
      return "registry+" + candidate.registry;
    }
    return {};
  }

  Lock lockOf(const Resolution &resolution) const {
    Lock lock;
    for (const auto &package : resolution.packages) {
      LockedPackage entry;
      entry.name = package.name();
      entry.version = toString(package.candidate.manifest->version);
      entry.source = sourceOf(package.candidate, rootDirectory);
      if (package.candidate.kind != SourceKind::Root)
        entry.checksum = checksum(package.candidate.location);
      entry.features = package.features;
      entry.dependencies = package.dependencies;
      lock.packages.push_back(std::move(entry));
    }
    return lock;
  }

  bool validate(const Resolution &resolution) {
    std::map<std::string, std::string> modules;
    for (const auto &package : resolution.packages) {
      const auto &manifest = *package.candidate.manifest;
      if (package.candidate.kind == SourceKind::Root)
        continue;
      auto [entry, fresh] =
          modules.emplace(moduleName(manifest.name), manifest.name);
      if (!fresh)
        diagnostics.error("package", manifest.nameSpan,
                          "packages '" + entry->second + "' and '" +
                              manifest.name + "' would both mount as module '" +
                              entry->first + "'");
      const auto *library = manifest.library();
      if (!library) {
        diagnostics.error("package", manifest.nameSpan,
                          "package '" + manifest.name +
                              "' is a dependency but has no library target");
        continue;
      }
      if (!fs::is_regular_file(fs::path(manifest.directory) / library->source))
        diagnostics.error("package", library->span,
                          "library source '" + library->source +
                              "' does not exist");
    }
    return !failed();
  }

  std::optional<Plan> build(const std::shared_ptr<const Manifest> &root) {
    const Target *executable = nullptr;
    for (const auto &target : root->targets)
      if (target.kind == "executable" &&
          (request.target.empty() || target.name == request.target)) {
        if (executable) {
          diagnostics.error("package", target.span,
                            "several executable targets; select one with "
                            "--bin NAME");
          return std::nullopt;
        }
        executable = &target;
      }
    if (!executable) {
      diagnostics.error(
          "package", root->nameSpan,
          request.target.empty()
              ? "package '" + root->name +
                    "' has no executable target; library-only packages cannot "
                    "be built on their own yet"
              : "package '" + root->name + "' has no executable target '" +
                    request.target + "'");
      return std::nullopt;
    }
    auto rootSource = fs::path(root->directory) / executable->source;
    if (!fs::is_regular_file(rootSource)) {
      diagnostics.error("package", executable->span,
                        "target source '" + executable->source +
                            "' does not exist");
      return std::nullopt;
    }

    for (const auto &path : request.registries)
      registries.push_back(fs::weakly_canonical(path));
    if (root->registry)
      registries.push_back(
          fs::weakly_canonical(rootDirectory / *root->registry));

    auto lockPath = rootDirectory / "Mettle.lock";
    std::optional<Lock> recorded;
    SourceId lockSource = 0;
    if (auto text = readFile(lockPath)) {
      lockSource = nextId;
      sources.push_back(
          {lockPath.generic_string(), std::move(*text), nextId++});
      auto tree = toml::parse(sources.back(), diagnostics, "lock");
      if (!tree)
        return std::nullopt;
      recorded = parseLock(*tree, sources.back(), diagnostics);
      if (!recorded)
        return std::nullopt;
    } else if (request.locked) {
      diagnostics.error("lock", {},
                        "Mettle.lock is missing and --locked forbids "
                        "creating it");
      return std::nullopt;
    }

    Universe universe;
    universe.path = [&](const Manifest &from, const DependencySpec &spec) {
      return loadPath(from, spec);
    };
    universe.registry = [&](const std::string &name) {
      return registryCandidates(name);
    };
    universe.absence = [&](const std::string &) { return absence(); };
    Problem solving;
    solving.root = {root, SourceKind::Root, root->directory, {}, false};
    solving.features = request.features;
    solving.defaultFeatures = request.defaultFeatures;
    if (recorded)
      for (const auto &package : recorded->packages)
        if (auto version = parseVersion(package.version))
          solving.preferred[package.name] = *version;
    auto resolution = resolve(solving, universe, diagnostics);
    if (!resolution || failed() || !validate(*resolution))
      return std::nullopt;

    auto fresh = lockOf(*resolution);
    // Where the lock records `name`, else the start of the lock.
    auto at = [&](const std::string &name) {
      Span span{0, 0, lockSource};
      if (recorded)
        if (const auto *entry = recorded->find(name))
          span = entry->span;
      return span;
    };
    if (recorded)
      for (const auto &now : fresh.packages) {
        const auto *then = recorded->find(now.name);
        if (then && now.source.rfind("registry+", 0) == 0 &&
            then->source == now.source && then->version == now.version &&
            then->checksum != now.checksum) {
          diagnostics.error(
              "lock", at(now.name),
              "checksum mismatch for registry package '" + now.name + "' " +
                  now.version + ": the lock records " + then->checksum +
                  " but its sources hash to " + now.checksum +
                  "; registry packages are immutable, so either the package "
                  "or Mettle.lock was altered");
          return std::nullopt;
        }
      }
    auto text = serialize(fresh);
    if (!recorded || serialize(*recorded) != text) {
      if (request.locked) {
        std::string why;
        Span span{0, 0, lockSource};
        for (const auto &note : differences(*recorded, fresh))
          why += "; " + note;
        for (const auto &package : fresh.packages) {
          const auto *then = recorded->find(package.name);
          if (!then || !equivalent(*then, package)) {
            span = at(package.name);
            break;
          }
        }
        diagnostics.error("lock", span,
                          "Mettle.lock needs updating but --locked forbids "
                          "changing it" +
                              why);
        return std::nullopt;
      }
      if (!write(lockPath, text))
        return std::nullopt;
    }

    Plan plan;
    plan.package = root->name;
    plan.version = toString(root->version);
    std::error_code error;
    plan.root = fs::canonical(rootSource, error).generic_string();
    for (const auto &package : resolution->packages) {
      const auto &manifest = *package.candidate.manifest;
      if (manifest.buildScript) {
        auto script = fs::path(manifest.directory) / *manifest.buildScript;
        if (!fs::is_regular_file(script)) {
          diagnostics.error("package", manifest.buildScriptSpan,
                            "build script '" + *manifest.buildScript +
                                "' does not exist");
          return std::nullopt;
        }
        plan.scripts.push_back(
            {manifest.name, toString(manifest.version), manifest.directory,
             fs::canonical(script, error).generic_string(),
             package.candidate.kind == SourceKind::Root});
      }
      if (package.candidate.kind == SourceKind::Root) {
        plan.features = package.features;
        continue;
      }
      plan.mounts.push_back(
          {moduleName(manifest.name),
           fs::canonical(
               fs::path(manifest.directory) / manifest.library()->source, error)
               .generic_string(),
           manifest.name, toString(manifest.version), package.features});
    }
    Sha256 hash;
    hash.update(text);
    hash.update("\ntarget=" + executable->name);
    plan.fingerprint = "sha256:" + hash.finish();
    return plan;
  }

  bool write(const fs::path &path, const std::string &text) {
    auto temporary = path;
    temporary += ".tmp";
    {
      std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
      out << text;
      if (!out) {
        diagnostics.error("io", {},
                          "cannot write " + temporary.generic_string());
        return false;
      }
    }
    std::error_code error;
    fs::rename(temporary, path, error);
    if (error)
      diagnostics.error("io", {},
                        "cannot update " + path.generic_string() + ": " +
                            error.message());
    return !error;
  }
};
} // namespace

Outcome plan(const Request &request, Diagnostics &diagnostics) {
  return Planner(request, diagnostics).run();
}
} // namespace mettle::packages
