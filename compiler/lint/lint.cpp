#include "lint/lint.h"
#include "types/type.h"
#include <algorithm>
#include <cctype>
#include <memory>
#include <optional>
#include <tuple>

namespace mettle::lint {
namespace {
using Overrides = std::map<std::string, Level>;

std::optional<Level> attributeLevel(const std::string &name) {
  if (name == "allow")
    return Level::Allow;
  if (name == "warn")
    return Level::Warn;
  if (name == "deny" || name == "forbid")
    return Level::Deny;
  return std::nullopt;
}

// Rule names in an attribute: `@deny(unused-binding, unused_import)`; the
// name `warnings` selects every rule. Identifiers that are not lint rules are
// left to other diagnostics and ignored here.
Overrides overrides(const std::vector<Attribute> &attributes) {
  Overrides result;
  for (const auto &attribute : attributes) {
    auto level = attributeLevel(attribute.name);
    if (!level || !attribute.parenthesized)
      continue;
    std::string name;
    auto apply = [&] {
      std::replace(name.begin(), name.end(), '_', '-');
      if (name == "warnings")
        for (auto rule : rules())
          result[std::string(rule)] = *level;
      else if (known(name))
        result[name] = *level;
      name.clear();
    };
    for (const auto &token : attribute.arguments) {
      if (token.text == ",")
        apply();
      else
        name += token.text;
    }
    apply();
  }
  return result;
}

std::string join(const std::vector<std::string> &path) {
  std::string result;
  for (const auto &part : path)
    result += (result.empty() ? "" : "::") + part;
  return result;
}

class Linter {
public:
  Linter(const CheckedModule &module, const Configuration &configuration)
      : module(module), configuration(configuration),
        types(module.typeStore()) {}

  std::vector<Finding> run() {
    imports();
    functions();
    std::stable_sort(findings.begin(), findings.end(),
                     [](const Finding &left, const Finding &right) {
                       return std::tie(left.span.source, left.span.begin) <
                              std::tie(right.span.source, right.span.begin);
                     });
    return std::move(findings);
  }

private:
  // The locals of one function body or closure body. Closure bodies have a
  // slot space of their own; captured outer bindings reach the enclosing unit
  // through the closure's capture list.
  struct Unit {
    explicit Unit(const FunctionFacts &function)
        : function(&function), used(function.locals.size()),
          mutated(function.locals.size()), declared(function.locals.size()) {}
    struct Candidate {
      int slot;
      bool variable;
      std::string name;
      Span span;
    };
    const FunctionFacts *function;
    std::vector<char> used, mutated, declared;
    std::vector<Candidate> candidates;
    // Part of the body was not checked, so a missing use proves nothing.
    bool opaque = false;
  };

  const CheckedModule &module;
  const Configuration &configuration;
  std::shared_ptr<const TypeStore> types;
  Overrides current;
  std::vector<Finding> findings;

  Level effective(std::string_view rule) const {
    auto name = std::string(rule);
    if (auto found = current.find(name); found != current.end())
      return found->second;
    if (auto found = configuration.levels.find(name);
        found != configuration.levels.end())
      return found->second;
    return configuration.defaultLevel;
  }
  void report(std::string_view rule, Span span, std::string message) {
    if (configuration.include && !configuration.include(span))
      return;
    auto level = effective(rule);
    if (level != Level::Allow)
      findings.push_back({std::string(rule), span, std::move(message), level});
  }

  void imports() {
    const auto &resolution = module.namespaces();
    const auto &declarations = module.syntax().imports;
    for (std::size_t i = 0; i < declarations.size(); ++i) {
      const auto &declaration = declarations[i];
      // A public or restricted import re-exports; its use is elsewhere.
      if (declaration.item.visibility.publicItem ||
          !declaration.item.visibility.restriction.empty() ||
          declaration.path.empty())
        continue;
      auto path = join(declaration.path);
      if (declaration.glob) {
        if (!resolution.importUsed(i))
          report(unusedImport, declaration.span,
                 "glob import of '" + path + "::*' is never used");
      } else if (!declaration.names.empty()) {
        for (const auto &entry : declaration.names)
          if (!resolution.importUsed(i, entry.alias.empty() ? entry.name
                                                            : entry.alias))
            report(unusedImport, entry.span,
                   "import '" + path + "::" + entry.name + "' is never used");
      } else if (!resolution.importUsed(i, declaration.alias.empty()
                                               ? declaration.path.back()
                                               : declaration.alias)) {
        report(unusedImport, declaration.span,
               "import '" + path + "' is never used");
      }
    }
  }

  void functions() {
    const auto &declarations = module.syntax().functions;
    for (std::size_t i = 0; i < declarations.size(); ++i) {
      if (!declarations[i].body.get())
        continue;
      current = overrides(declarations[i].item.attributes);
      Unit unit(module.function(i));
      walk(*declarations[i].body, unit);
      finish(unit);
    }
    current.clear();
  }

  static void mark(Unit &unit, int slot, bool mutation) {
    if (slot < 0 || static_cast<std::size_t>(slot) >= unit.used.size())
      return;
    unit.used[slot] = 1;
    if (mutation)
      unit.mutated[slot] = 1;
  }
  static void declare(Unit &unit, int slot, bool variable,
                      const std::string &name, Span span) {
    if (slot < 0 || static_cast<std::size_t>(slot) >= unit.used.size() ||
        unit.declared[slot] || name.empty() || name[0] == '_' ||
        !(std::isalpha(static_cast<unsigned char>(name[0]))))
      return;
    unit.declared[slot] = 1;
    unit.candidates.push_back({slot, variable, name, span});
  }
  void collect(const Pattern &pattern, Unit &unit) {
    if (pattern.kind == PatternKind::Binding || pattern.kind == PatternKind::At)
      if (const auto *facts = module.find(pattern))
        declare(unit, facts->slot, false, pattern.text, pattern.span);
    for (const auto &child : pattern.children)
      collect(child, unit);
  }

  void walk(const Node &node, Unit &unit) {
    if (node.kind == Kind::Closure) {
      closure(node, unit);
      return;
    }
    if (const auto *facts = module.find(node)) {
      if (node.kind == Kind::Name)
        mark(unit, facts->slot, facts->exclusivePlace);
      else if (node.kind == Kind::Binding)
        declare(unit, facts->slot, node.flag, node.text, node.span);
    }
    for (const auto &pattern : node.patterns)
      collect(pattern, unit);
    if (node.kind == Kind::Block) {
      block(node, unit);
      return;
    }
    for (const auto &child : node.children)
      walk(*child, unit);
  }

  void closure(const Node &node, Unit &parent) {
    const auto *facts = module.find(node);
    if (!facts || facts->closure < 0 ||
        static_cast<std::size_t>(facts->closure) >= module.closures().size()) {
      parent.opaque = true;
      return;
    }
    const auto &body = *module.closures()[facts->closure];
    Unit unit(body.function);
    for (const auto &child : node.children)
      walk(*child, unit);
    finish(unit);
    for (const auto &capture : body.captures)
      mark(parent, capture.source.root, capture.mode == ParameterMode::Mut);
  }

  void block(const Node &node, Unit &unit) {
    bool diverged = false, reported = false;
    for (std::size_t i = 0; i < node.children.size(); ++i) {
      const auto &child = *node.children[i];
      if (diverged && !reported) {
        report(unreachableCode, child.span,
               "unreachable code: the previous statement never completes");
        reported = true;
      }
      walk(child, unit);
      if (!isStatement(child.kind) &&
          (i + 1 < node.children.size() || child.semicolon))
        discarded(child);
      if (const auto *facts = module.find(child); facts && !facts->flow.normal)
        diverged = true;
    }
  }

  // The value of an expression statement is dropped; a typed failure carried
  // in an Outcome must be handled or discarded explicitly.
  void discarded(const Node &node) {
    const auto *facts = module.find(node);
    if (!facts || facts->type == Type::Unknown ||
        !types->isProduct(facts->type) ||
        types->product(facts->type).kind != AggregateKind::Outcome)
      return;
    report(unusedOutcome, node.span,
           "the Outcome of this expression is ignored; handle it, propagate "
           "it with 'try' or discard it with 'let _ ='");
  }

  void finish(const Unit &unit) {
    if (unit.opaque)
      return;
    for (const auto &candidate : unit.candidates) {
      auto slot = static_cast<std::size_t>(candidate.slot);
      if (!unit.used[slot])
        report(unusedBinding, candidate.span,
               "binding '" + candidate.name +
                   "' is never used; prefix it with '_' or discard the value "
                   "with 'let _ ='");
      else if (candidate.variable && !unit.mutated[slot])
        report(unusedMutability, candidate.span,
               "'var " + candidate.name +
                   "' is never reassigned or mutably borrowed; declare it "
                   "with 'let'");
    }
  }
};
} // namespace

const std::vector<std::string_view> &rules() {
  static const std::vector<std::string_view> names{
      unusedBinding, unusedMutability, unusedImport, unreachableCode,
      unusedOutcome};
  return names;
}

bool known(std::string_view rule) {
  const auto &names = rules();
  return std::find(names.begin(), names.end(), rule) != names.end();
}

std::vector<Finding> run(const CheckedModule &module,
                         const Configuration &configuration) {
  return Linter(module, configuration).run();
}
} // namespace mettle::lint
