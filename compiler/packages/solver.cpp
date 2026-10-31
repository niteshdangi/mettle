#include "packages/solver.h"
#include <algorithm>
#include <deque>
#include <set>

namespace mettle::packages {
namespace {
struct Edge {
  std::string from;
  std::shared_ptr<const Manifest> manifest;
  const DependencySpec *spec = nullptr;
  std::vector<std::string> features;
  bool defaults = true, featureOnly = false, host = false;
};

struct Chosen {
  Candidate candidate;
  std::map<std::pair<std::string, bool>, std::string> dependencies;
  std::set<std::string> features;
  bool defaults = false, expanded = false;
};

struct Constraint {
  std::string requirer;
  Requirement requirement;
};

struct State {
  std::map<std::string, Chosen> chosen;
  std::map<std::string, std::vector<Constraint>> constraints;
  std::deque<Edge> queue;
};

std::string describe(const Manifest &manifest) {
  return manifest.name + ' ' + toString(manifest.version);
}

bool matches(const Candidate &candidate, const DependencySpec &spec) {
  if (candidate.manifest->name != spec.name ||
      (spec.requirement &&
       !spec.requirement->matches(candidate.manifest->version)))
    return false;
  return true;
}

class Solver {
public:
  Solver(const Problem &request, const Universe &universe,
         Diagnostics &diagnostics)
      : request(request), universe(universe), diagnostics(diagnostics) {}

  std::optional<Resolution> run() {
    State state;
    const auto &root = request.root;
    auto rootId = identity(root);
    state.chosen.emplace(rootId, Chosen{root});
    Edge start{rootId, root.manifest, nullptr, request.features,
               request.defaultFeatures, false, false};
    enable(state, rootId, start);
    if (!fatal && search(std::move(state)))
      return build();
    if (!fatal) {
      if (conflict)
        diagnostics.error("package", conflict->first, conflict->second);
      else
        diagnostics.error("package", {}, "dependency resolution failed");
    }
    return std::nullopt;
  }

private:
  const Problem &request;
  const Universe &universe;
  Diagnostics &diagnostics;
  bool fatal = false;
  std::optional<std::pair<Span, std::string>> conflict;
  std::map<std::string, Chosen> solution;

  void failFatal(Span span, std::string message) {
    fatal = true;
    diagnostics.error("package", span, std::move(message));
  }
  void note(Span span, std::string message) {
    if (!conflict)
      conflict.emplace(span, std::move(message));
  }

  static bool implicitFeature(const Manifest &manifest,
                              const std::string &name) {
    const auto *dependency = manifest.dependency(name);
    if (!dependency || !dependency->optional)
      return false;
    for (const auto &feature : manifest.features)
      for (const auto &item : feature.items)
        if (item == "dep:" + name)
          return false;
    return true;
  }

  void activate(State &state, const std::string &from,
                const std::shared_ptr<const Manifest> &manifest,
                const DependencySpec &spec, bool host) {
    state.queue.push_back({from, manifest, &spec, spec.features,
                           spec.defaultFeatures, false, host});
  }

  void enable(State &state, const std::string &id, const Edge &edge) {
    auto &chosen = state.chosen.at(id);
    const auto &manifest = *chosen.candidate.manifest;
    Span where = edge.spec ? edge.spec->span : manifest.nameSpan;
    if (!chosen.expanded) {
      chosen.expanded = true;
      for (const auto &dependency : manifest.dependencies)
        if (!dependency.optional)
          activate(state, id, chosen.candidate.manifest, dependency,
                   chosen.candidate.host);
      for (const auto &dependency : manifest.buildDependencies)
        if (!dependency.optional)
          activate(state, id, chosen.candidate.manifest, dependency, true);
      if (!manifest.macros.empty())
        for (const auto &dependency : manifest.dependencies)
          if (!dependency.optional)
            activate(state, id, chosen.candidate.manifest, dependency, true);
    }
    std::vector<std::string> pending = edge.features;
    if (edge.defaults && !chosen.defaults) {
      chosen.defaults = true;
      if (manifest.feature("default"))
        pending.push_back("default");
    }
    for (std::size_t i = 0; i < pending.size(); ++i) {
      auto feature = pending[i];
      if (!chosen.features.insert(feature).second)
        continue;
      if (const auto *declared = manifest.feature(feature)) {
        for (const auto &item : declared->items) {
          if (item.rfind("dep:", 0) == 0)
            if (const auto *dependency =
                    manifest.dependency(item.substr(4))) {
              activate(state, id, chosen.candidate.manifest, *dependency,
                       chosen.candidate.host);
              if (!manifest.macros.empty() && !chosen.candidate.host)
                activate(state, id, chosen.candidate.manifest, *dependency,
                         true);
            } else
              failFatal(where, "feature '" + feature +
                                   "' refers to a missing dependency");
          else if (auto slash = item.find('/'); slash != std::string::npos) {
            auto dependency = item.substr(0, slash);
            const auto *spec = manifest.dependency(dependency);
            if (!spec) {
              failFatal(where, "feature '" + feature +
                                   "' refers to a missing dependency");
              return;
            }
            activate(state, id, chosen.candidate.manifest, *spec,
                     chosen.candidate.host);
            state.queue.push_back(
                {id, chosen.candidate.manifest, spec,
                 {item.substr(slash + 1)}, false, true,
                 chosen.candidate.host});
            if (!manifest.macros.empty() && !chosen.candidate.host) {
              activate(state, id, chosen.candidate.manifest, *spec, true);
              state.queue.push_back({id, chosen.candidate.manifest, spec,
                                     {item.substr(slash + 1)}, false, true,
                                     true});
            }
          } else
            pending.push_back(item);
        }
      } else if (implicitFeature(manifest, feature)) {
        if (const auto *dependency = manifest.dependency(feature)) {
          activate(state, id, chosen.candidate.manifest, *dependency,
                   chosen.candidate.host);
          if (!manifest.macros.empty() && !chosen.candidate.host)
            activate(state, id, chosen.candidate.manifest, *dependency, true);
        } else
          failFatal(where, "implicit feature '" + feature +
                               "' refers to a missing dependency");
      } else {
        failFatal(where, "package '" + manifest.name + "' has no feature '" +
                             feature + "'");
        return;
      }
    }
  }

  static std::string constraintsText(const State &state,
                                     const std::string &id) {
    std::string text;
    auto found = state.constraints.find(id);
    if (found == state.constraints.end())
      return text;
    for (const auto &constraint : found->second)
      text += (text.empty() ? "" : ", ") + std::string("'") +
              constraint.requirement.text + "' (required by '" +
              constraint.requirer + "')";
    return text;
  }

  std::vector<Candidate> candidates(const Edge &edge) {
    const auto &spec = *edge.spec;
    if (spec.path) {
      auto found = universe.path(*edge.manifest, spec);
      if (!found) {
        fatal = true;
        return {};
      }
      if (!matches(*found, spec)) {
        failFatal(spec.span, "path dependency '" + spec.name +
                                 "' is version " +
                                 toString(found->manifest->version) +
                                 ", which does not satisfy '" +
                                 spec.requirement->text + "'");
        return {};
      }
      found->host = edge.host;
      return {std::move(*found)};
    }
    if (spec.git) {
      auto found = universe.git(*edge.manifest, spec);
      if (!found) {
        fatal = true;
        return {};
      }
      if (!matches(*found, spec)) {
        failFatal(spec.span, "git dependency '" + spec.name +
                                 "' is version " +
                                 toString(found->manifest->version) +
                                 ", which does not satisfy '" +
                                 spec.requirement->text + "'");
        return {};
      }
      found->host = edge.host;
      return {std::move(*found)};
    }
    auto all = universe.registry(spec.name);
    for (auto &candidate : all)
      candidate.host = edge.host;
    std::sort(all.begin(), all.end(),
              [](const Candidate &a, const Candidate &b) {
                return compare(a.manifest->version, b.manifest->version) > 0;
              });
    std::vector<Candidate> usable;
    std::vector<std::string> versions;
    auto preferred = request.preferred.find(spec.name);
    for (const auto &candidate : all) {
      versions.push_back(toString(candidate.manifest->version));
      bool pinned =
          preferred != request.preferred.end() &&
          std::any_of(preferred->second.begin(), preferred->second.end(),
                      [&](const Version &version) {
                        return compare(version, candidate.manifest->version) ==
                               0;
                      });
      if (!spec.requirement->matches(candidate.manifest->version) ||
          (candidate.yanked && !pinned))
        continue;
      if (pinned)
        usable.insert(usable.begin(), candidate);
      else
        usable.push_back(candidate);
    }
    if (usable.empty()) {
      std::string message;
      if (all.empty())
        message = "package '" + spec.name + "' (required '" +
                  spec.requirement->text + "' by '" +
                  describe(*edge.manifest) + "') was not found: " +
                  universe.absence(spec.name);
      else {
        message = "no available version of '" + spec.name + "' satisfies '" +
                  spec.requirement->text + "' (required by '" +
                  describe(*edge.manifest) + "'); available:";
        for (const auto &version : versions)
          message += ' ' + version;
      }
      note(spec.span, std::move(message));
    }
    return usable;
  }

  bool apply(State &state, const std::string &target, const Edge &edge) {
    auto &chosen = state.chosen.at(target);
    if (!edge.featureOnly) {
      if (edge.spec->requirement) {
        state.constraints[target].push_back(
            {describe(*edge.manifest), *edge.spec->requirement});
        if (!edge.spec->requirement->matches(
                chosen.candidate.manifest->version)) {
          note(edge.spec->span,
               "no version of '" + edge.spec->name +
                   "' satisfies all requirements: " +
                   constraintsText(state, target));
          return false;
        }
      }
      state.chosen.at(edge.from).dependencies[{edge.spec->name, edge.host}] =
          target;
    }
    enable(state, target, edge);
    return !fatal;
  }

  void choose(State &state, const Edge &edge, Candidate candidate) {
    auto id = identity(candidate);
    Chosen chosen;
    chosen.candidate = std::move(candidate);
    state.chosen.emplace(id, std::move(chosen));
    if (edge.spec->requirement)
      state.constraints[id].push_back(
          {describe(*edge.manifest), *edge.spec->requirement});
    state.chosen.at(edge.from).dependencies[{edge.spec->name, edge.host}] = id;
    enable(state, id, edge);
  }

  bool search(State state) {
    while (!state.queue.empty() && !fatal) {
      auto edge = std::move(state.queue.front());
      state.queue.pop_front();
      if (edge.featureOnly) {
        const auto &owner = state.chosen.at(edge.from);
        auto dependency =
            owner.dependencies.find({edge.spec->name, edge.host});
        if (dependency == owner.dependencies.end()) {
          failFatal(edge.spec->span,
                    "feature dependency '" + edge.spec->name +
                        "' was not resolved");
          return false;
        }
        if (!apply(state, dependency->second, edge))
          return false;
        continue;
      }

      auto options = candidates(edge);
      if (options.empty())
        return false;
      std::vector<Candidate> fresh;
      bool reused = false;
      for (auto &option : options) {
        auto found = state.chosen.find(identity(option));
        if (found != state.chosen.end()) {
          if (!edge.spec->requirement ||
              edge.spec->requirement->matches(
                  found->second.candidate.manifest->version)) {
            if (!apply(state, found->first, edge))
              return false;
            reused = true;
            break;
          }
        } else
          fresh.push_back(std::move(option));
      }
      if (reused)
        continue;
      options = std::move(fresh);
      if (options.empty())
        return false;
      if (options.size() == 1) {
        choose(state, edge, std::move(options.front()));
        continue;
      }
      for (auto &option : options) {
        auto branch = state;
        choose(branch, edge, std::move(option));
        if (fatal)
          return false;
        if (search(std::move(branch)))
          return true;
        if (fatal)
          return false;
      }
      return false;
    }
    if (fatal)
      return false;
    solution = std::move(state.chosen);
    return true;
  }

  std::optional<Resolution> build() {
    Resolution resolution;
    auto convert = [&](const std::string &id, const Chosen &chosen) {
      ResolvedPackage package;
      package.candidate = chosen.candidate;
      package.identity = id;
      package.features.assign(chosen.features.begin(), chosen.features.end());
      for (const auto &[key, dependency] : chosen.dependencies)
        package.dependencies.emplace_back(key.first, dependency);
      return package;
    };
    auto rootId = identity(request.root);
    resolution.packages.push_back(convert(rootId, solution.at(rootId)));
    for (const auto &[id, chosen] : solution)
      if (id != rootId)
        resolution.packages.push_back(convert(id, chosen));
    if (!acyclic(resolution))
      return std::nullopt;
    return resolution;
  }

  bool acyclic(const Resolution &resolution) {
    std::map<std::string, const ResolvedPackage *> byId;
    for (const auto &package : resolution.packages)
      byId[package.identity] = &package;
    std::set<std::string> done;
    std::vector<const ResolvedPackage *> path;
    bool ok = true;
    std::function<void(const ResolvedPackage &)> visit =
        [&](const ResolvedPackage &package) {
          path.push_back(&package);
          for (const auto &[name, dependency] : package.dependencies) {
            (void)name;
            auto onPath = std::find_if(
                path.begin(), path.end(), [&](const ResolvedPackage *entry) {
                  return entry->identity == dependency;
                });
            if (onPath != path.end()) {
              std::string text;
              for (auto at = onPath; at != path.end(); ++at)
                text += describe(*(*at)->candidate.manifest) + " -> ";
              auto dependencyName = byId.at(dependency)->name();
              const auto *spec =
                  package.candidate.manifest->dependency(dependencyName);
              if (!spec)
                for (const auto &candidate :
                     package.candidate.manifest->buildDependencies)
                  if (candidate.name == dependencyName) {
                    spec = &candidate;
                    break;
                  }
              diagnostics.error("package",
                                spec ? spec->span
                                     : package.candidate.manifest->nameSpan,
                                "dependency cycle: " +
                                    text +
                                    describe(*byId.at(dependency)
                                                  ->candidate.manifest) +
                                    "; cyclic package compilation is not "
                                    "supported");
              ok = false;
              return;
            }
            if (done.insert(dependency).second) {
              visit(*byId.at(dependency));
              if (!ok)
                return;
            }
          }
          path.pop_back();
        };
    auto root = resolution.packages.front().identity;
    done.insert(root);
    visit(resolution.packages.front());
    return ok;
  }
};
} // namespace

std::string identity(const Candidate &candidate) {
  const auto &manifest = *candidate.manifest;
  std::string source;
  switch (candidate.kind) {
  case SourceKind::Root:
    source = "root";
    break;
  case SourceKind::Path:
    source = candidate.sourceIdentity.empty()
                 ? "path:" + candidate.location
                 : candidate.sourceIdentity;
    break;
  case SourceKind::Registry:
    source = candidate.sourceIdentity.empty()
                 ? "registry:" + candidate.registry + ':' +
                       candidate.manifest->name + '@' +
                       toString(candidate.manifest->version)
                 : candidate.sourceIdentity;
    break;
  case SourceKind::Git:
    source = candidate.sourceIdentity.empty()
                 ? "git:" + candidate.git + '#' + candidate.commit
                 : candidate.sourceIdentity;
    break;
  }
  return manifest.name + '@' + toString(manifest.version) + '|' + source +
         (candidate.host ? "|host" : "|target");
}

std::optional<Resolution> resolve(const Problem &request,
                                  const Universe &universe,
                                  Diagnostics &diagnostics) {
  return Solver(request, universe, diagnostics).run();
}
} // namespace mettle::packages
