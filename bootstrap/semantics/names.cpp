#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include <algorithm>

namespace mettle {

std::vector<DiagnosticMessage>
Checker::vocabularyHelp(std::string_view spelling) const {
  if (spelling == "Vec")
    return {{"help", {}, "use `List` for the growable sequence type"}};
  if (spelling == "HashMap")
    return {{"help", {}, "use `Map` for the hash-based key/value collection"}};
  return {};
}

Checker::Binding Checker::lookup(const std::string &name, Span span,
                                 std::optional<SyntaxContextPtr> context) {
  auto lexical = context ? *context : diagnostics.syntaxContext(span);
  auto key = nameKey(name, lexical);
  for (auto it = scopes.rbegin(); it != scopes.rend(); ++it) {
    auto found = it->find(key);
    if (found != it->end()) {
      auto binding = found->second;
      auto sourceScope = static_cast<std::size_t>(
          std::distance(scopes.begin(), it.base()) - 1);
      for (auto [closure, boundary] : closureScopes) {
        if (boundary <= sourceScope || binding.owner == closure)
          continue;
        auto &captures = captureBindings[closure];
        auto capture = std::find_if(
            captures.begin(), captures.end(), [&](const auto &capture) {
              return capture.source.owner == binding.owner &&
                     capture.source.slot == binding.slot;
            });
        int slot;
        if (capture != captures.end())
          slot = capture->proxy;
        else {
          auto &locals = facts(*closure).locals;
          if (locals.size() >= limits::locals) {
            error("limit", span, "closure capture limit exceeded");
            return {inference.fresh(), -1, closure};
          }
          slot = static_cast<int>(locals.size());
          locals.push_back({name, Type::Unknown, true, span});
          locals.back().context = lexical;
          localVariables[closure].push_back(binding.variable);
          captures.push_back({binding, slot, span});
        }
        binding = {binding.variable, slot, closure};
        scopes[boundary][key] = binding;
      }
      return binding;
    }
  }
  if (auto storage = staticName(name, span, context)) {
    for (std::size_t i = 0; i < facts(*current).locals.size(); ++i) {
      const auto &local = facts(*current).locals[i];
      if (local.storage != StorageDuration::Static ||
          local.staticIndex !=
              static_cast<int>(checked.staticStorage[*storage].identity))
        continue;
      if (local.mutableBinding)
        requireUnsafe(span);
      if (checked.staticStorage[*storage].type == Type::Unknown)
        inference.equal(localVariables[current][i],
                        inference.fresh(staticType(*storage)), span);
      return {localVariables[current][i], static_cast<int>(i), current};
    }
  }
  error("name", span, "unresolved value '" + displayPath(name) + "'",
        vocabularyHelp(name));
  return {inference.fresh(), -1};
}
// A path container qualifies a following segment: a module, a type (including
// builtin, `Self` and generic parameters) or an interface.
bool Checker::pathContainer(std::string_view spelling, const Function *function,
                            Span span) const {
  std::string_view owner;
  if (function)
    owner = function->owner;
  if (function && spelling.find("::") == std::string_view::npos) {
    // Outside a type, `Self.x` still reaches the `Self::x` diagnostic.
    if (spelling == "Self")
      return true;
    for (const auto &parameter : function->genericParameters)
      if (parameter.kind == GenericParameterKind::Type &&
          nameKey(parameter.name, parameter.context) == nameKey(spelling, span))
        return true;
  }
  if (!typeName(spelling, span, owner).empty())
    return true;
  return checked.symbols
      ->lookup(nameModule(span), spelling, resolution::Namespace::Module, span)
      .has_value();
}

// Target-syntax dotted paths (`Opt.Some`, `core.pin.Pin.new`, `Slot.empty`)
// parse as syntax-only `Field` chains. Unless a binding in `lexical` names the
// root, the longest prefix whose leading segments are path containers is the
// same path as its `::` spelling; the node of its last segment becomes that
// qualified `Name` (carrying per-segment generic arguments) and any remaining
// links stay ordinary field or method accesses. A value binding therefore
// shadows a type or module of the same name.
void Checker::qualifyDottedPath(Node &node, const std::set<NameKey> &lexical,
                                const Function *function) {
  if (node.kind != Kind::Field || node.flag || node.children.size() != 1)
    return;
  std::vector<Node *> chain;
  Node *root = &node;
  while (root->kind == Kind::Field && !root->flag &&
         root->children.size() == 1) {
    chain.push_back(root);
    root = root->children[0].get();
  }
  if (root->kind != Kind::Name || root->annotation.form != TypeForm::Named ||
      !root->ownerGenericArguments.empty() ||
      root->text.find("::") != std::string::npos ||
      (root->text == "self" && function && !function->owner.empty()) ||
      lexical.contains(nameKey(root->text, root->context)))
    return;
  std::reverse(chain.begin(), chain.end());
  // Segment 0 is the root; segment i is chain[i - 1].
  const std::size_t total = chain.size() + 1;
  std::string spelling = root->text;
  std::size_t containers = 0;
  // Library roots may name compiler intrinsics (`core.mem.forget`) whose
  // modules are never mounted, so an unshadowed `core`/`alloc`/`std` chain is
  // a path through its last link, exactly like its `::` spelling.
  const bool library =
      root->text == "core" || root->text == "alloc" || root->text == "std";
  while (containers < chain.size() &&
         (library || pathContainer(spelling, function, root->span))) {
    ++containers;
    spelling += "::" + chain[containers - 1]->text;
  }
  if (containers == 0)
    return;
  const std::size_t length = std::min(containers + 1, total);
  auto generics = [&](std::size_t segment) -> std::vector<GenericArgument> & {
    return segment == 0 ? root->genericArguments
                        : chain[segment - 1]->genericArguments;
  };
  for (std::size_t segment = 0; segment + 2 < length; ++segment)
    if (!generics(segment).empty())
      return;
  spelling = root->text;
  for (std::size_t segment = 1; segment < length; ++segment)
    spelling += "::" + chain[segment - 1]->text;
  auto last = std::move(generics(length - 1));
  auto owner = std::move(generics(length - 2));
  auto &target = *chain[length - 2];
  target.kind = Kind::Name;
  target.text = std::move(spelling);
  target.genericArguments = std::move(last);
  target.ownerGenericArguments = std::move(owner);
  target.context = root->context;
  target.children.clear();
}
// Constant initializers have no function context: only module-level names and
// the dotted paths among them need qualifying.
void Checker::qualifyDottedPaths(Node &node) {
  qualifyDottedPath(node, {}, nullptr);
  for (auto &child : node.children)
    qualifyDottedPaths(*child);
}
int Checker::local(std::string name, int variable, bool mutableBinding,
                   Span span, std::optional<SyntaxContextPtr> context) {
  if (facts(*current).locals.size() >= limits::locals) {
    error("limit", span, "local binding limit exceeded");
    return -1;
  }
  int slot = static_cast<int>(facts(*current).locals.size());
  facts(*current).locals.push_back({name, Type::Unknown, mutableBinding, span});
  facts(*current).locals.back().context =
      context ? *context : diagnostics.syntaxContext(span);
  localVariables[current].push_back(variable);
  scopes.back()[nameKey(name, context ? *context
                                      : diagnostics.syntaxContext(span))] = {
      variable, slot, current};
  return slot;
}
} // namespace mettle
