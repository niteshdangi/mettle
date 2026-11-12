#include "packages/plan.h"
#include "packages/data.h"
#include "packages/lock.h"
#include "packages/manifest.h"
#include "packages/sha256.h"
#include "packages/solver.h"
#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <unistd.h>

namespace mettle::packages {
namespace {
namespace fs = std::filesystem;

std::optional<std::string> readFile(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream)
    return std::nullopt;
  std::ostringstream text;
  text << stream.rdbuf();
  if (stream.bad() || text.bad())
    return std::nullopt;
  return text.str();
}

// Package inputs exclude generated locks and build output.
std::optional<std::string> checksum(const fs::path &directory,
                                    std::string &problem, bool legacy = false) {
  try {
    std::vector<std::pair<std::string, fs::path>> files;
    std::vector<std::pair<std::string, std::string>> links;
    auto root = fs::canonical(directory);
    std::set<fs::path> visited{root};
    for (fs::recursive_directory_iterator
             it(directory,
                legacy ? fs::directory_options::none
                       : fs::directory_options::follow_directory_symlink),
         end;
         it != end; ++it) {
      const auto name = it->path().filename().string();
      if (!legacy && it->is_symlink()) {
        auto target = fs::canonical(it->path()).lexically_relative(root);
        if (target.empty() || *target.begin() == "..") {
          problem = "source link outside its directory: " +
                    it->path().generic_string();
          return std::nullopt;
        }
        links.emplace_back(
            it->path().lexically_relative(directory).generic_string(),
            target.generic_string());
      }
      if (it->is_directory()) {
        if ((legacy && name.starts_with('.')) || name == ".git" ||
            (legacy && (name == "target" || name == "build")) ||
            (!legacy && name == "target" && it.depth() == 0) ||
            (!legacy && !visited.insert(fs::canonical(it->path())).second))
          it.disable_recursion_pending();
        continue;
      }
      if (it->is_regular_file() && name != "lock.mettle" &&
          (legacy ? it->path().extension() == ".mt" ||
                        it->path().extension() == ".mettle"
                  : name != "YANKED" || it.depth() != 0)) {
        files.emplace_back(
            it->path().lexically_relative(directory).generic_string(),
            it->path());
      }
    }
    std::sort(files.begin(), files.end());
    std::sort(links.begin(), links.end());
    Sha256 hash;
    for (const auto &[relative, path] : files) {
      auto content = readFile(path);
      if (!content && !legacy) {
        problem = "cannot read package input " + path.generic_string();
        return std::nullopt;
      }
      const auto &text = content.value_or("");
      hash.update(relative);
      hash.update(std::string_view("\0", 1));
      hash.update(std::to_string(text.size()));
      hash.update(std::string_view("\0", 1));
      hash.update(text);
    }
    for (const auto &[relative, target] : links) {
      hash.update("link:");
      hash.update(relative);
      hash.update(std::string_view("\0", 1));
      hash.update(target);
    }
    return std::string(legacy ? "sha256:" : "sha256-tree-2:") + hash.finish();
  } catch (const fs::filesystem_error &error) {
    problem = "cannot inspect package inputs: " + std::string(error.what());
    return std::nullopt;
  }
}

std::string moduleRoot(const ResolvedPackage &package) {
  Sha256 hash;
  hash.update(package.identity);
  auto version = toString(package.candidate.manifest->version);
  std::replace_if(
      version.begin(), version.end(),
      [](char c) {
        return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9') || c == '_');
      },
      '_');
  return "mettle_pkg_" + moduleName(package.candidate.manifest->name) + "_" +
         version + "_" + hash.finish();
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
    else if (input.filename() == "package.mettle")
      rootDirectory = fs::canonical(
          input.parent_path().empty() ? fs::path(".") : input.parent_path(),
          error);
    else {
      outcome.fallback = {request.input, "", 0};
      diagnostics.error(
          "io", {},
          "'" + request.input +
              "' is neither a package directory nor a package.mettle");
      return outcome;
    }
    outcome.fallback = {(rootDirectory / "package.mettle").generic_string(), "",
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
  std::map<std::string, std::pair<std::string, std::string>> gitOrigins;

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
    auto path = directory / "package.mettle";
    auto text = readFile(path);
    if (!text) {
      diagnostics.error("io", at.value_or(Span{}),
                        "cannot read " + path.generic_string());
      return slot;
    }
    sources.push_back({path.generic_string(), std::move(*text), nextId++});
    const auto &source = sources.back();
    auto tree = data::parse(source, diagnostics, "manifest");
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
    Candidate candidate;
    candidate.manifest = std::move(manifest);
    candidate.kind = SourceKind::Path;
    candidate.location = directory.generic_string();
    candidate.sourceIdentity =
        "path+" + directory.lexically_relative(rootDirectory).generic_string();
    std::size_t originLength = 0;
    for (const auto &[root, git] : gitOrigins) {
      auto relative = directory.lexically_relative(root);
      if (!relative.empty() && *relative.begin() != ".." &&
          root.size() > originLength) {
        candidate.sourceIdentity =
            "path+" + git.second + "/" + relative.generic_string();
        originLength = root.size();
      }
    }
    return candidate;
  }

  std::optional<Candidate> loadGit(const Manifest &from,
                                   const DependencySpec &spec,
                                   const Lock *recorded) {
    (void)from;
    if (!request.gitCheckout) {
      diagnostics.error("feature", spec.span,
                        "git dependencies require the system git provider");
      return std::nullopt;
    }
    auto selector = gitSelector(spec);
    std::string lockedCommit;
    if (recorded)
      for (const auto &entry : recorded->packages)
        if (entry.name == spec.name &&
            entry.source.rfind("git+" + *spec.git + "#", 0) == 0 &&
            std::find(entry.gitSelectors.begin(), entry.gitSelectors.end(),
                      selector) != entry.gitSelectors.end()) {
          lockedCommit =
              entry.source.substr(std::string("git+" + *spec.git + "#").size());
          break;
        }
    std::string problem;
    auto checkout = request.gitCheckout(*spec.git, selector, lockedCommit,
                                        request.offline, problem);
    if (!checkout) {
      diagnostics.error("package", spec.span,
                        "cannot resolve git dependency '" + spec.name +
                            "' from '" + *spec.git + "': " + problem);
      return std::nullopt;
    }
    auto directory = fs::canonical(checkout->directory);
    auto manifest = loadManifest(directory, spec.span);
    if (!manifest)
      return std::nullopt;
    if (manifest->name != spec.name) {
      diagnostics.error("package", spec.span,
                        "git dependency '" + spec.name + "' at '" + *spec.git +
                            "' is the package '" + manifest->name + "'");
      return std::nullopt;
    }
    Candidate candidate;
    candidate.manifest = std::move(manifest);
    candidate.kind = SourceKind::Git;
    candidate.location = directory.generic_string();
    candidate.git = *spec.git;
    candidate.commit = checkout->commit;
    candidate.sourceIdentity = "git+" + candidate.git + "#" + candidate.commit;
    gitOrigins[directory.generic_string()] = {candidate.commit,
                                              candidate.sourceIdentity};
    return candidate;
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
        Candidate candidate;
        candidate.manifest = std::move(manifest);
        candidate.kind = SourceKind::Registry;
        candidate.location = directory.generic_string();
        candidate.registry = display(registry);
        candidate.sourceIdentity = "registry+" + candidate.registry;
        candidate.yanked = fs::exists(directory / "YANKED");
        found.push_back(std::move(candidate));
      }
    }
    return found;
  }

  std::string absence() const {
    std::string text;
    if (registries.empty())
      text = "no registry is configured (use registry { path: ... } in "
             "package.mettle "
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

  static std::string sourceOf(const Candidate &candidate) {
    switch (candidate.kind) {
    case SourceKind::Root:
      return "root";
    case SourceKind::Path:
      return candidate.sourceIdentity;
    case SourceKind::Registry:
      return "registry+" + candidate.registry;
    case SourceKind::Git:
      return "git+" + candidate.git + "#" + candidate.commit;
    }
    return {};
  }

  std::optional<Lock> lockOf(const Resolution &resolution) {
    Lock lock;
    for (const auto &package : resolution.packages) {
      LockedPackage entry;
      entry.name = package.name();
      entry.version = toString(package.candidate.manifest->version);
      entry.id = package.identity;
      entry.source = sourceOf(package.candidate);
      if (package.candidate.kind != SourceKind::Root) {
        std::string problem;
        auto value = checksum(package.candidate.location, problem);
        if (!value) {
          diagnostics.error("package", {},
                            "package '" + package.name() + "': " + problem);
          return std::nullopt;
        }
        entry.checksum = *value;
      }
      entry.features = package.features;
      entry.gitSelectors = package.gitSelectors;
      for (const auto &[name, id] : package.dependencies) {
        (void)name;
        entry.dependencies.push_back(id);
      }
      lock.packages.push_back(std::move(entry));
    }
    return lock;
  }

  bool validate(const Resolution &resolution) {
    const auto compilerVersion = parseVersion(METTLE_VERSION);
    if (!compilerVersion) {
      diagnostics.error("internal", {},
                        "compiler build has an invalid version");
      return false;
    }
    for (const auto &package : resolution.packages) {
      const auto &manifest = *package.candidate.manifest;
      if (manifest.mettleVersion &&
          compare(*compilerVersion, *manifest.mettleVersion) < 0)
        diagnostics.error("feature", manifest.mettleVersionSpan,
                          "package '" + manifest.name + "' requires Mettle " +
                              toString(*manifest.mettleVersion) +
                              " or newer; running compiler is " METTLE_VERSION);
      if (package.candidate.kind == SourceKind::Root)
        continue;
      const auto *library = manifest.library();
      if (!library && !manifest.macros.empty())
        continue;
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
    bool primary = std::any_of(
        root->targets.begin(), root->targets.end(),
        [&](const Target &target) { return target.name == "main"; });
    for (const auto &target : root->targets)
      if (request.target.empty() ? (!primary || target.name == "main")
                                 : target.name == request.target) {
        if (executable) {
          diagnostics.error("package", target.span,
                            "several executable targets; select one with "
                            "--entry NAME");
          return std::nullopt;
        }
        executable = &target;
      }
    if (!executable) {
      diagnostics.error("package", root->nameSpan,
                        request.target.empty()
                            ? "package '" + root->name + "' has no source entry"
                            : "package '" + root->name + "' has no entry '" +
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

    auto lockPath = rootDirectory / "lock.mettle";
    std::optional<Lock> recorded;
    SourceId lockSource = 0;
    if (auto text = readFile(lockPath)) {
      lockSource = nextId;
      sources.push_back(
          {lockPath.generic_string(), std::move(*text), nextId++});
      auto tree = data::parse(sources.back(), diagnostics, "lock");
      if (!tree)
        return std::nullopt;
      recorded = parseLock(*tree, sources.back(), diagnostics);
      if (!recorded)
        return std::nullopt;
    } else if (request.locked) {
      diagnostics.error("lock", {},
                        "lock.mettle is missing and --locked forbids "
                        "creating it");
      return std::nullopt;
    }

    Universe universe;
    universe.path = [&](const Manifest &from, const DependencySpec &spec) {
      return loadPath(from, spec);
    };
    universe.git = [&](const Manifest &from, const DependencySpec &spec) {
      return loadGit(from, spec, recorded ? &*recorded : nullptr);
    };
    universe.registry = [&](const std::string &name) {
      return registryCandidates(name);
    };
    universe.absence = [&](const std::string &) { return absence(); };
    Problem solving;
    solving.root.manifest = root;
    solving.root.kind = SourceKind::Root;
    solving.root.location = root->directory;
    solving.features = request.features;
    solving.defaultFeatures = request.defaultFeatures;
    solving.includeDev = request.includeDev;
    if (recorded)
      for (const auto &package : recorded->packages)
        if (auto version = parseVersion(package.version))
          solving.preferred[package.name].push_back(*version);
    auto resolution = resolve(solving, universe, diagnostics);
    if (!resolution || failed() || !validate(*resolution))
      return std::nullopt;

    auto freshLock = lockOf(*resolution);
    if (!freshLock)
      return std::nullopt;
    auto &fresh = *freshLock;
    // Where the lock records `id`, else the start of the lock.
    auto at = [&](const std::string &id) {
      Span span{0, 0, lockSource};
      if (recorded)
        if (const auto *entry = recorded->find(id))
          span = entry->span;
      return span;
    };
    if (recorded)
      for (const auto &now : fresh.packages) {
        const auto *then = recorded->find(now.id);
        if (then &&
            (now.source.rfind("registry+", 0) == 0 ||
             now.source.rfind("git+", 0) == 0) &&
            then->source == now.source && then->version == now.version &&
            then->checksum != now.checksum) {
          bool oldFormat = then->checksum.starts_with("sha256:");
          bool validMigration = false;
          if (oldFormat) {
            auto package = std::find_if(
                resolution->packages.begin(), resolution->packages.end(),
                [&](const auto &item) { return item.identity == now.id; });
            std::string problem;
            auto previous =
                checksum(package->candidate.location, problem, true);
            validMigration = previous && *previous == then->checksum;
          }
          if (validMigration)
            continue;
          diagnostics.error(
              "lock", at(now.id),
              "checksum mismatch for immutable package '" + now.name + "' " +
                  now.version + ": the lock records " + then->checksum +
                  " but its sources hash to " + now.checksum +
                  "; either the package or lock.mettle was altered");
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
          const auto *then = recorded->find(package.id);
          if (!then || !equivalent(*then, package)) {
            span = at(package.id);
            break;
          }
        }
        diagnostics.error("lock", span,
                          "lock.mettle needs updating but --locked forbids "
                          "changing it" +
                              why);
        return std::nullopt;
      }
      if (!write(lockPath, text))
        return std::nullopt;
    }

    Plan plan;
    plan.package = root->name;
    plan.kind = executable->kind;
    plan.emits = executable->emits;
    plan.version = toString(root->version);
    std::error_code error;
    plan.root = fs::canonical(rootSource, error).generic_string();
    for (const auto &package : resolution->packages) {
      Plan::PackageOrigin origin;
      origin.identity = package.identity;
      origin.directory = package.candidate.manifest->directory;
      origin.host = package.candidate.host;
      for (const auto &[directory, git] : gitOrigins) {
        auto relative =
            fs::path(origin.directory).lexically_relative(directory);
        if (!relative.empty() && *relative.begin() != ".." &&
            directory.size() > origin.gitRoot.size()) {
          origin.gitRoot = directory;
          origin.gitCommit = git.first;
          origin.gitSourceIdentity = git.second;
        }
      }
      plan.origins.push_back(std::move(origin));
    }
    std::map<std::string, std::string> modules;
    for (const auto &package : resolution->packages)
      if (package.candidate.kind != SourceKind::Root &&
          package.candidate.manifest->library())
        modules.emplace(package.identity, moduleRoot(package));
    std::map<std::string, const ResolvedPackage *> byIdentity;
    for (const auto &package : resolution->packages)
      byIdentity.emplace(package.identity, &package);
    std::set<std::string> visited;
    std::vector<const ResolvedPackage *> ordered;
    auto visit = [&](auto &self, const ResolvedPackage &package) -> void {
      if (!visited.insert(package.identity).second)
        return;
      for (const auto &[name, dependency] : package.dependencies)
        self(self, *byIdentity.at(dependency));
      ordered.push_back(&package);
    };
    for (const auto &package : resolution->packages)
      visit(visit, package);
    for (const auto *resolved : ordered) {
      const auto &package = *resolved;
      const auto &manifest = *package.candidate.manifest;
      if (manifest.buildScript) {
        auto script = fs::path(manifest.directory) / *manifest.buildScript;
        if (!fs::is_regular_file(script)) {
          diagnostics.error("package", manifest.buildScriptSpan,
                            "build script '" + *manifest.buildScript +
                                "' does not exist");
          return std::nullopt;
        }
        BuildScript buildScript;
        buildScript.package = manifest.name;
        buildScript.version = toString(manifest.version);
        buildScript.identity = package.identity;
        buildScript.directory = manifest.directory;
        buildScript.source = fs::canonical(script, error).generic_string();
        buildScript.features = package.features;
        buildScript.root = package.candidate.kind == SourceKind::Root;
        buildScript.host = package.candidate.host;
        for (const auto &[name, dependency] : package.dependencies)
          if (modules.contains(dependency) &&
              std::find_if(resolution->packages.begin(),
                           resolution->packages.end(),
                           [&](const ResolvedPackage &candidate) {
                             return candidate.identity == dependency &&
                                    candidate.candidate.host;
                           }) != resolution->packages.end())
            buildScript.dependencies.emplace_back(moduleName(name),
                                                  modules.at(dependency));
        plan.scripts.push_back(std::move(buildScript));
      }
      if (!package.candidate.host) {
        for (const auto &macro : manifest.macros) {
          auto program = fs::path(manifest.directory) / macro.source;
          if (!fs::is_regular_file(program)) {
            diagnostics.error("package", macro.span,
                              "macro source '" + macro.source +
                                  "' does not exist");
            return std::nullopt;
          }
          for (const auto &known : plan.macros)
            if (known.name == macro.name) {
              diagnostics.error("package", macro.span,
                                "macro '" + macro.name +
                                    "' is declared by both '" + known.package +
                                    "' and '" + manifest.name + "'");
              return std::nullopt;
            }
          Macro plannedMacro;
          plannedMacro.name = macro.name;
          plannedMacro.identity = package.identity;
          plannedMacro.package = manifest.name;
          plannedMacro.version = toString(manifest.version);
          plannedMacro.directory = manifest.directory;
          plannedMacro.source = fs::canonical(program, error).generic_string();
          plannedMacro.features = package.features;
          for (const auto &[name, dependency] : package.dependencies)
            if (modules.contains(dependency) &&
                std::find_if(resolution->packages.begin(),
                             resolution->packages.end(),
                             [&](const ResolvedPackage &candidate) {
                               return candidate.identity == dependency &&
                                      candidate.candidate.host;
                             }) != resolution->packages.end())
              plannedMacro.dependencies.emplace_back(moduleName(name),
                                                     modules.at(dependency));
          plan.macros.push_back(std::move(plannedMacro));
        }
      }
      if (package.candidate.kind == SourceKind::Root) {
        plan.features = package.features;
        plan.rootIdentity = package.identity;
        for (const auto &[name, dependency] : package.dependencies) {
          auto child = std::find_if(resolution->packages.begin(),
                                    resolution->packages.end(),
                                    [&](const ResolvedPackage &candidate) {
                                      return candidate.identity == dependency;
                                    });
          if (child != resolution->packages.end() &&
              modules.contains(dependency)) {
            if (child->candidate.host)
              plan.hostDependencies.emplace_back(moduleName(name),
                                                 modules.at(dependency));
            else
              plan.dependencies.emplace_back(moduleName(name),
                                             modules.at(dependency));
          }
        }
        continue;
      }
      if (!manifest.library())
        continue;
      Mount mount;
      mount.name = moduleName(manifest.name);
      mount.source =
          fs::canonical(
              fs::path(manifest.directory) / manifest.library()->source, error)
              .generic_string();
      mount.module = modules.at(package.identity);
      mount.package = manifest.name;
      mount.version = toString(manifest.version);
      mount.identity = package.identity;
      mount.features = package.features;
      for (const auto &[name, dependency] : package.dependencies) {
        auto child = std::find_if(resolution->packages.begin(),
                                  resolution->packages.end(),
                                  [&](const ResolvedPackage &candidate) {
                                    return candidate.identity == dependency;
                                  });
        if (child != resolution->packages.end() &&
            child->candidate.host == package.candidate.host &&
            modules.contains(dependency))
          mount.dependencies.emplace_back(moduleName(name),
                                          modules.at(dependency));
      }
      if (package.candidate.host)
        plan.hostMounts.push_back(std::move(mount));
      else
        plan.mounts.push_back(std::move(mount));
    }
    Sha256 hash;
    hash.update(text);
    hash.update("\ntarget=" + executable->name);
    plan.fingerprint = "sha256:" + hash.finish();
    return plan;
  }

  bool write(const fs::path &path, const std::string &text) {
    struct Temporary {
      std::string path;
      int descriptor = -1;
      ~Temporary() {
        if (descriptor >= 0)
          close(descriptor);
        if (!path.empty()) {
          std::error_code ignored;
          fs::remove(path, ignored);
        }
      }
    } temporary{path.string() + ".tmp.XXXXXX"};
    temporary.descriptor = mkstemp(temporary.path.data());
    auto fail = [&](const std::string &action, std::error_code error) {
      diagnostics.error("io", {},
                        action + " " + path.generic_string() + ": " +
                            error.message());
      return false;
    };
    if (temporary.descriptor < 0) {
      auto error = std::error_code(errno, std::generic_category());
      temporary.path.clear();
      return fail("cannot stage", error);
    }
    std::size_t offset = 0;
    while (offset < text.size()) {
      auto count = ::write(temporary.descriptor, text.data() + offset,
                           text.size() - offset);
      if (count < 0 && errno == EINTR)
        continue;
      if (count <= 0)
        return fail("cannot write", std::error_code(count < 0 ? errno : EIO,
                                                    std::generic_category()));
      offset += static_cast<std::size_t>(count);
    }
    int status = close(temporary.descriptor);
    temporary.descriptor = -1;
    if (status != 0)
      return fail("cannot close",
                  std::error_code(errno, std::generic_category()));
    std::error_code error;
    fs::rename(temporary.path, path, error);
    if (error)
      return fail("cannot update", error);
    temporary.path.clear();
    return true;
  }
};
} // namespace

Outcome plan(const Request &request, Diagnostics &diagnostics) {
  return Planner(request, diagnostics).run();
}
} // namespace mettle::packages
