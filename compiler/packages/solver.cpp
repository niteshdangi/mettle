#include "packages/solver.h"
#include <algorithm>
#include <deque>
#include <set>

namespace mettle::packages {
namespace {
struct Edge {
  std::shared_ptr<const Manifest> from;
  const DependencySpec *spec = nullptr;
  std::vector<std::string> features;
  bool defaults = true;
  // Adds features to an already requested dependency without a requirement.
  bool featureOnly = false;
};

struct Chosen {
  Candidate candidate;
  std::set<std::string> features, dependencies;
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

class Solver {
public:
  Solver(const Problem &request, const Universe &universe,
         Diagnostics &diagnostics)
      : request(request), universe(universe), diagnostics(diagnostics) {}

  std::optional<Resolution> run() {
    State state;
    const auto &root = request.root;
    auto &chosen = state.chosen[root.manifest->name];
    chosen.candidate = root;
    Edge start{root.manifest, nullptr, request.features,
               request.defaultFeatures, false};
    enable(state, root.manifest->name, start);
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

  void activate(State &state, Chosen &chosen, const std::string &name) {
    if (!chosen.dependencies.insert(name).second)
      return;
    const auto *spec = chosen.candidate.manifest->dependency(name);
    state.queue.push_back({chosen.candidate.manifest, spec, spec->features,
                           spec->defaultFeatures, false});
  }

  // Applies `edge`'s feature request to the package it selected.
  void enable(State &state, const std::string &name, const Edge &edge) {
    auto &chosen = state.chosen.at(name);
    const auto &manifest = *chosen.candidate.manifest;
    Span where = edge.spec ? edge.spec->span : manifest.nameSpan;
    if (!chosen.expanded) {
      chosen.expanded = true;
      for (const auto &dependency : manifest.dependencies)
        if (!dependency.optional)
          activate(state, chosen, dependency.name);
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
            activate(state, chosen, item.substr(4));
          else if (auto slash = item.find('/'); slash != std::string::npos) {
            auto dependency = item.substr(0, slash);
            activate(state, chosen, dependency);
            state.queue.push_back({chosen.candidate.manifest,
                                   manifest.dependency(dependency),
                                   {item.substr(slash + 1)},
                                   false,
                                   true});
          } else
            pending.push_back(item);
        }
      } else if (implicitFeature(manifest, feature)) {
        activate(state, chosen, feature);
      } else {
        failFatal(where, "package '" + manifest.name + "' has no feature '" +
                             feature + "'");
        return;
      }
    }
  }

  static std::string constraintsText(const State &state,
                                     const std::string &name) {
    std::string text;
    for (const auto &constraint : state.constraints.at(name))
      text += (text.empty() ? "" : ", ") + std::string("'") +
              constraint.requirement.text + "' (required by '" +
              constraint.requirer + "')";
    return text;
  }

  // Candidates for the first edge naming a package, best first.
  std::vector<Candidate> candidates(const Edge &edge) {
    const auto &spec = *edge.spec;
    if (spec.path) {
      auto found = universe.path(*edge.from, spec);
      if (!found) {
        fatal = true;
        return {};
      }
      if (spec.requirement &&
          !spec.requirement->matches(found->manifest->version)) {
        failFatal(spec.span, "path dependency '" + spec.name + "' is version " +
                                 toString(found->manifest->version) +
                                 ", which does not satisfy '" +
                                 spec.requirement->text + "'");
        return {};
      }
      return {std::move(*found)};
    }
    auto all = universe.registry(spec.name);
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
          compare(preferred->second, candidate.manifest->version) == 0;
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
                  spec.requirement->text + "' by '" + describe(*edge.from) +
                  "') was not found: " + universe.absence(spec.name);
      else {
        message = "no available version of '" + spec.name + "' satisfies '" +
                  spec.requirement->text + "' (required by '" +
                  describe(*edge.from) + "'); available:";
        for (const auto &version : versions)
          message += ' ' + version;
      }
      note(spec.span, std::move(message));
    }
    return usable;
  }

  // Returns false when this branch cannot satisfy the edge.
  bool apply(State &state, const Edge &edge) {
    const auto &spec = *edge.spec;
    auto &chosen = state.chosen.at(spec.name);
    auto who = describe(*edge.from);
    if (!edge.featureOnly) {
      if (spec.path && chosen.candidate.kind == SourceKind::Registry) {
        note(spec.span, "package '" + spec.name +
                            "' is required both from a path (by '" + who +
                            "') and from a registry");
        return false;
      }
      if (spec.path && chosen.candidate.kind == SourceKind::Path) {
        auto other = universe.path(*edge.from, spec);
        if (!other) {
          fatal = true;
          return false;
        }
        if (other->location != chosen.candidate.location) {
          note(spec.span, "package '" + spec.name +
                              "' is required from two different paths: '" +
                              chosen.candidate.location + "' and '" +
                              other->location + "' (by '" + who + "')");
          return false;
        }
      }
      if (spec.requirement) {
        state.constraints[spec.name].push_back({who, *spec.requirement});
        if (!spec.requirement->matches(chosen.candidate.manifest->version)) {
          note(spec.span, "no version of '" + spec.name +
                              "' satisfies all requirements: " +
                              constraintsText(state, spec.name));
          return false;
        }
      }
    }
    enable(state, spec.name, edge);
    return !fatal;
  }

  void choose(State &state, const Edge &edge, Candidate candidate) {
    const auto &spec = *edge.spec;
    if (spec.requirement)
      state.constraints[spec.name].push_back(
          {describe(*edge.from), *spec.requirement});
    auto &chosen = state.chosen[spec.name];
    chosen.candidate = std::move(candidate);
    enable(state, spec.name, edge);
  }

  bool search(State state) {
    while (!state.queue.empty() && !fatal) {
      auto edge = std::move(state.queue.front());
      state.queue.pop_front();
      if (state.chosen.contains(edge.spec->name)) {
        if (!apply(state, edge))
          return false;
        continue;
      }
      auto options = candidates(edge);
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
    auto convert = [&](const Chosen &chosen) {
      ResolvedPackage package;
      package.candidate = chosen.candidate;
      package.features.assign(chosen.features.begin(), chosen.features.end());
      package.dependencies.assign(chosen.dependencies.begin(),
                                  chosen.dependencies.end());
      return package;
    };
    const auto &rootName = request.root.manifest->name;
    resolution.packages.push_back(convert(solution.at(rootName)));
    for (const auto &[name, chosen] : solution)
      if (name != rootName)
        resolution.packages.push_back(convert(chosen));
    if (!acyclic(resolution))
      return std::nullopt;
    return resolution;
  }

  bool acyclic(const Resolution &resolution) {
    std::map<std::string, const ResolvedPackage *> byName;
    for (const auto &package : resolution.packages)
      byName[package.name()] = &package;
    std::set<std::string> done;
    std::vector<std::string> path;
    bool ok = true;
    std::function<void(const ResolvedPackage &)> visit =
        [&](const ResolvedPackage &package) {
          path.push_back(package.name());
          for (const auto &name : package.dependencies) {
            auto onPath = std::find(path.begin(), path.end(), name);
            if (onPath != path.end()) {
              std::string text;
              for (auto at = onPath; at != path.end(); ++at)
                text += *at + " -> ";
              const auto *spec = package.candidate.manifest->dependency(name);
              diagnostics.error("package", spec->span,
                                "dependency cycle: " + text + name +
                                    "; cyclic package compilation is not "
                                    "supported");
              ok = false;
              return;
            }
            if (done.insert(name).second) {
              visit(*byName.at(name));
              if (!ok)
                return;
            }
          }
          path.pop_back();
        };
    done.insert(resolution.packages.front().name());
    visit(resolution.packages.front());
    return ok;
  }
};
} // namespace

std::optional<Resolution> resolve(const Problem &request,
                                  const Universe &universe,
                                  Diagnostics &diagnostics) {
  return Solver(request, universe, diagnostics).run();
}
} // namespace mettle::packages
