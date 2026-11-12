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
  std::set<std::string> gitSelectors;
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
  bool valid = true;
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
    Chosen chosen;
    chosen.candidate = root;
    state.chosen.emplace(rootId, std::move(chosen));
    Edge start{rootId,
               root.manifest,
               nullptr,
               request.features,
               request.defaultFeatures,
               false,
               false};
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
    if (edge.spec && edge.spec->git)
      chosen.gitSelectors.insert(gitSelector(*edge.spec));
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
      if (request.includeDev && chosen.candidate.kind == SourceKind::Root)
        for (const auto &dependency : manifest.devDependencies)
          activate(state, id, chosen.candidate.manifest, dependency, false);
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
            if (const auto *dependency = manifest.dependency(item.substr(4))) {
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
            state.queue.push_back({id,
                                   chosen.candidate.manifest,
                                   spec,
                                   {item.substr(slash + 1)},
                                   false,
                                   true,
                                   chosen.candidate.host});
            if (!manifest.macros.empty() && !chosen.candidate.host) {
              activate(state, id, chosen.candidate.manifest, *spec, true);
              state.queue.push_back({id,
                                     chosen.candidate.manifest,
                                     spec,
                                     {item.substr(slash + 1)},
                                     false,
                                     true,
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
        note(where, "package '" + manifest.name + "' has no feature '" +
                        feature + "'");
        state.valid = false;
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
        failFatal(spec.span, "path dependency '" + spec.name + "' is version " +
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
        failFatal(spec.span, "git dependency '" + spec.name + "' is version " +
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
                  spec.requirement->text + "' by '" + describe(*edge.manifest) +
                  "') was not found: " + universe.absence(spec.name);
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
          note(edge.spec->span, "no version of '" + edge.spec->name +
                                    "' satisfies all requirements: " +
                                    constraintsText(state, target));
          return false;
        }
      }
      state.chosen.at(edge.from).dependencies[{edge.spec->name, edge.host}] =
          target;
    }
    enable(state, target, edge);
    return !fatal && state.valid;
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

  // SemVer-compatible registry versions of one package in one build context
  // unify; only incompatible versions coexist.
  static bool compatible(const Candidate &a, const Candidate &b) {
    if (a.kind != SourceKind::Registry || b.kind != SourceKind::Registry ||
        a.host != b.host || a.registry != b.registry ||
        a.manifest->name != b.manifest->name)
      return false;
    const auto &x = a.manifest->version;
    const auto &y = b.manifest->version;
    if (x.major != y.major)
      return false;
    if (x.major != 0)
      return true;
    return x.minor == y.minor && (x.minor != 0 || x.patch == y.patch);
  }

  bool search(State state) {
    while (!state.queue.empty() && !fatal && state.valid) {
      auto edge = std::move(state.queue.front());
      state.queue.pop_front();
      if (edge.featureOnly) {
        const auto &owner = state.chosen.at(edge.from);
        auto dependency = owner.dependencies.find({edge.spec->name, edge.host});
        if (dependency == owner.dependencies.end()) {
          failFatal(edge.spec->span, "feature dependency '" + edge.spec->name +
                                         "' was not resolved");
          return false;
        }
        if (!apply(state, dependency->second, edge))
          return false;
        continue;
      }

      auto options = candidates(edge);
      const auto &owner = state.chosen.at(edge.from);
      if (auto selected = owner.dependencies.find({edge.spec->name, edge.host});
          selected != owner.dependencies.end()) {
        std::erase_if(options, [&](const Candidate &candidate) {
          return identity(candidate) != selected->second;
        });
        if (options.empty())
          note(edge.spec->span,
               "conflicting requirements for dependency alias '" +
                   edge.spec->name + "'");
      }
      if (options.empty())
        return false;
      std::vector<Candidate> fresh;
      std::string conflict;
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
        } else {
          auto unified = std::find_if(
              state.chosen.begin(), state.chosen.end(), [&](const auto &entry) {
                return compatible(entry.second.candidate, option);
              });
          if (unified == state.chosen.end())
            fresh.push_back(std::move(option));
          else
            conflict = unified->first;
        }
      }
      if (reused)
        continue;
      options = std::move(fresh);
      if (options.empty()) {
        if (!conflict.empty()) {
          state.constraints[conflict].push_back(
              {describe(*edge.manifest), *edge.spec->requirement});
          note(edge.spec->span, "no version of '" + edge.spec->name +
                                    "' satisfies all requirements: " +
                                    constraintsText(state, conflict));
        }
        return false;
      }
      if (options.size() == 1) {
        choose(state, edge, std::move(options.front()));
        continue;
      }
      for (auto &option : options) {
        auto branch = state;
        choose(branch, edge, std::move(option));
        if (fatal)
          return false;
        if (!branch.valid)
          continue;
        if (search(std::move(branch)))
          return true;
        if (fatal)
          return false;
      }
      return false;
    }
    if (fatal || !state.valid)
      return false;
    if (!acyclic(state.chosen))
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
      package.gitSelectors.assign(chosen.gitSelectors.begin(),
                                  chosen.gitSelectors.end());
      for (const auto &[key, dependency] : chosen.dependencies)
        package.dependencies.emplace_back(key.first, dependency);
      return package;
    };
    auto rootId = identity(request.root);
    resolution.packages.push_back(convert(rootId, solution.at(rootId)));
    for (const auto &[id, chosen] : solution)
      if (id != rootId)
        resolution.packages.push_back(convert(id, chosen));
    return resolution;
  }

  bool acyclic(const std::map<std::string, Chosen> &chosen) {
    std::set<std::string> done;
    std::vector<std::string> path;
    bool ok = true;
    std::function<void(const std::string &)> visit =
        [&](const std::string &id) {
          const auto &package = chosen.at(id);
          path.push_back(id);
          for (const auto &[key, dependency] : package.dependencies) {
            auto onPath = std::find(path.begin(), path.end(), dependency);
            if (onPath != path.end()) {
              std::string text;
              for (auto at = onPath; at != path.end(); ++at)
                text += describe(*chosen.at(*at).candidate.manifest) + " -> ";
              const auto *spec =
                  package.candidate.manifest->dependency(key.first);
              if (!spec)
                for (const auto &candidate :
                     package.candidate.manifest->buildDependencies)
                  if (candidate.name == key.first) {
                    spec = &candidate;
                    break;
                  }
              conflict.emplace(
                  spec ? spec->span : package.candidate.manifest->nameSpan,
                  "dependency cycle: " + text +
                      describe(*chosen.at(dependency).candidate.manifest) +
                      "; cyclic package compilation is not "
                      "supported");
              ok = false;
              return;
            }
            if (done.insert(dependency).second) {
              visit(dependency);
              if (!ok)
                return;
            }
          }
          path.pop_back();
        };
    auto root = identity(request.root);
    done.insert(root);
    visit(root);
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
    source = candidate.sourceIdentity.empty() ? "path:" + candidate.location
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
