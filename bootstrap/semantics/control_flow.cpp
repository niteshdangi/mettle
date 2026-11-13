#include "semantics/checker.h"
#include <functional>

namespace mettle {
void Checker::controlFlow(Function &function) {
  std::vector<Node *> targets;
  std::set<NameKey> lexical;
  std::function<void(const Pattern &)> bind = [&](const Pattern &pattern) {
    if (pattern.kind == PatternKind::Binding ||
        pattern.kind == PatternKind::At || pattern.kind == PatternKind::Rest)
      lexical.insert(nameKey(pattern.text, pattern.context));
    for (const auto &child : pattern.children)
      bind(child);
  };
  int next = 0;
  std::function<void(Node &)> visit = [&](Node &node) {
    qualifyDottedPath(node, lexical, &function);
    if (node.kind == Kind::Name)
      facts(node).lexicallyBound =
          lexical.contains(nameKey(node.text, node.context));
    if (node.kind == Kind::Block) {
      auto saved = lexical;
      for (auto &child : node.children)
        visit(*child);
      lexical = std::move(saved);
      return;
    }
    if (node.kind == Kind::Binding) {
      for (auto &child : node.children)
        visit(*child);
      if (node.patterns.empty())
        lexical.insert(nameKey(node.text, node.context));
      else
        bind(node.patterns[0]);
      return;
    }
    if (node.kind == Kind::Condition) {
      visit(*node.children[0]);
      if (!node.patterns.empty())
        bind(node.patterns[0]);
      return;
    }
    if (node.kind == Kind::Closure) {
      auto saved = std::move(targets);
      auto savedLexical = lexical;
      for (const auto &parameter : node.parameters) {
        lexical.insert(nameKey(parameter.name, parameter.context));
        if (parameter.pattern)
          bind(*parameter.pattern);
      }
      targets.clear();
      visit(*node.children[0]);
      targets = std::move(saved);
      lexical = std::move(savedLexical);
      return;
    }
    bool loop = node.kind == Kind::Loop || node.kind == Kind::While ||
                node.kind == Kind::For;
    if (loop) {
      facts(node).control = next++;
      targets.push_back(&node);
    } else if (node.kind == Kind::Break || node.kind == Kind::Continue) {
      auto target = targets.rbegin();
      while (target != targets.rend() && !node.label.empty() &&
             (*target)->label != node.label)
        ++target;
      if (target == targets.rend())
        error(node.label.empty() ? "type" : "name", node.span,
              node.label.empty() ? "loop control outside a loop"
                                 : "unknown loop label '" + node.label + "'");
      else
        facts(node).control = facts(**target).control;
    }
    if ((node.kind == Kind::If || node.kind == Kind::While) &&
        node.children[0]->kind == Kind::ConditionChain) {
      auto saved = lexical;
      visit(*node.children[0]);
      visit(*node.children[1]);
      lexical = std::move(saved);
      if (node.kind == Kind::If && node.children.size() > 2)
        visit(*node.children[2]);
    } else if (!node.patterns.empty() &&
               (node.kind == Kind::For || node.kind == Kind::If ||
                node.kind == Kind::While || node.kind == Kind::Arm)) {
      auto saved = lexical;
      std::size_t first = 0;
      if (node.kind != Kind::Arm) {
        visit(*node.children[0]);
        first = 1;
      }
      bind(node.patterns[0]);
      visit(*node.children[first]);
      if (node.kind == Kind::Arm && node.children.size() > 1)
        visit(*node.children[1]);
      lexical = std::move(saved);
      if (node.kind == Kind::If && node.children.size() > 2)
        visit(*node.children[2]);
    } else
      for (auto &child : node.children)
        visit(*child);
    if (loop)
      targets.pop_back();
  };
  for (auto &parameter : function.parameters) {
    if (parameter.defaultValue.get())
      visit(*parameter.defaultValue);
    lexical.insert(nameKey(parameter.name, parameter.context));
    if (parameter.pattern)
      bind(*parameter.pattern);
  }
  if (!function.variadicCursor.empty())
    lexical.insert(nameKey(function.variadicCursor, function.variadicSpan));
  visit(*function.body);
}

int Checker::loop(Node &n, bool reachable) {
  int result =
      inference.fresh(n.kind == Kind::While ? Type::Unit : Type::Unknown);
  loopResults[facts(n).control] = result;
  auto savedFeatures = guardedFeatures;
  scopes.emplace_back();
  if (n.kind == Kind::While) {
    auto condition = node(*n.children[0], reachable);
    if (n.patterns.empty())
      inference.equal(condition, inference.fresh(Type::Bool), n.span, true);
    else
      pattern(n.patterns[0], condition, ParameterMode::Read);
  }
  node(*n.children.back(),
       reachable &&
           (n.kind != Kind::While || facts(*n.children[0]).flow.normal) &&
           !(n.kind == Kind::While && booleanLiteral(*n.children[0]) == false));
  scopes.pop_back();
  guardedFeatures = std::move(savedFeatures);
  return facts(n).flow.normal ? result : inference.fresh(Type::Never);
}

int Checker::transfer(Node &n, bool reachable) {
  if (n.kind == Kind::Break) {
    int value = n.children.empty() ? inference.fresh(Type::Unit)
                                   : node(*n.children[0], reachable);
    inference.equal(value, loopResults.at(facts(n).control), n.span, true);
  }
  return inference.fresh(Type::Never);
}
bool Checker::implementsProtocol(Type type, std::string_view interface,
                                 Span span) {
  auto found = interfaceNames.find(std::string(interface));
  if (found == interfaceNames.end())
    return false;
  const auto &definition = checked.interfaceData->definitions[found->second];
  if (!definition.parameters.empty())
    return false;
  auto bound = checked.types->erasedType(
      ErasedType{definition.name, static_cast<std::uint32_t>(found->second)});
  auto assumptions = interfaceAssumptions();
  if (checked.types->isErased(type))
    assumptions.push_back({type, type});
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            std::move(assumptions), regionEnvironment());
  return solver.prove({type, bound}, span, false);
}
// Elaborates a `for` over a user iterator into the recorded plan
//   { var it = <iterator>; loop { match take it.next() {
//       present(pattern) => { body }; none => break } } }
// so that checking, regions, ownership and cleanup reuse the ordinary
// machinery. The parsed `for` is unchanged: the elaboration lives in the
// checked module's iteration table and shares the already-checked source and
// the body.
bool Checker::desugarIteration(Node &n, Type original) {
  static constexpr std::string_view iterator = "core::iter::Iterator",
                                    into = "core::iter::OwnedIterable",
                                    shared = "core::iter::Iterable",
                                    exclusive = "core::iter::MutableIterable";
  auto &source = *n.children[0];
  auto place = [](const Node &node) {
    auto *current = &node;
    while (current->kind == Kind::Group)
      current = current->children[0].get();
    return current->kind == Kind::Name || current->kind == Kind::Field ||
           current->kind == Kind::Index ||
           (current->kind == Kind::Unary &&
            (current->text == "*" || current->text == "mut" ||
             current->text == "read"));
  };
  auto self = original;
  while (checked.types->isView(self))
    self = checked.types->view(self).payload;
  auto mode = facts(n).iterationMode;
  if (mode == ParameterMode::Read && !place(source) &&
      !checked.types->isView(original))
    mode = ParameterMode::Take;
  // An iterator or owned-iterable held in a local is consumed by iterating it,
  // like a value, unless the type is iterable through a shared view.
  if (mode == ParameterMode::Read && place(source) &&
      !checked.types->isView(original) &&
      !implementsProtocol(self, shared, source.span) &&
      (implementsProtocol(self, iterator, source.span) ||
       implementsProtocol(self, into, source.span)))
    mode = ParameterMode::Take;
  std::string_view method, owner;
  if (mode == ParameterMode::Take) {
    if (!implementsProtocol(self, iterator, source.span)) {
      if (!implementsProtocol(self, into, source.span))
        return false;
      method = "into_iter";
      owner = into;
    }
  } else if (mode == ParameterMode::Mut) {
    if (implementsProtocol(self, exclusive, source.span)) {
      method = "iter_mut";
      owner = exclusive;
    } else if (!implementsProtocol(self, iterator, source.span))
      return false;
  } else if (implementsProtocol(self, shared, source.span)) {
    method = "iter";
    owner = shared;
  } else
    return false;
  auto make = [&](Kind kind, std::string text = {}) {
    auto result = std::make_unique<Node>();
    result->kind = kind;
    result->span = n.span;
    result->text = std::move(text);
    result->context = n.context;
    return result;
  };
  auto reference = [&] {
    auto result = make(Kind::Name, "<for iterator>");
    facts(*result).lexicallyBound = true;
    return result;
  };
  auto protocolCall = [&](NodeOwner receiver, std::string_view name,
                          std::string_view interface) {
    auto field = make(Kind::Field, std::string(name));
    field->children.push_back(std::move(receiver));
    auto call = make(Kind::Call, std::string(interface));
    call->children.push_back(std::move(field));
    return call;
  };
  reusedNodes.insert(&source);
  NodeOwner initializer = NodeOwner::borrow(source);
  if (!method.empty())
    initializer = protocolCall(std::move(initializer), method, owner);
  auto binding = make(Kind::Binding, "<for iterator>");
  binding->flag = true;
  binding->children.push_back(std::move(initializer));
  auto present = make(Kind::Arm);
  present->patterns.push_back(
      Pattern{PatternKind::Variant, n.patterns[0].span, "present"});
  present->patterns[0].children.push_back(n.patterns[0]);
  auto body = make(Kind::Block);
  body->children.push_back(NodeOwner::borrow(*n.children[1]));
  body->children.push_back(make(Kind::Unit));
  present->children.push_back(std::move(body));
  auto done = make(Kind::Arm);
  done->patterns.push_back(Pattern{PatternKind::Variant, n.span, "none"});
  auto exit = make(Kind::Break);
  facts(*exit).control = facts(n).control;
  done->children.push_back(std::move(exit));
  auto next = make(Kind::Match, "take");
  next->children.push_back(protocolCall(reference(), "next", iterator));
  next->children.push_back(std::move(present));
  next->children.push_back(std::move(done));
  auto loopBody = make(Kind::Block);
  loopBody->children.push_back(std::move(next));
  auto iteration = make(Kind::Loop);
  iteration->label = n.label;
  iteration->children.push_back(std::move(loopBody));
  facts(*iteration).control = facts(n).control;
  auto block = make(Kind::Block);
  block->children.push_back(std::move(binding));
  block->children.push_back(std::move(iteration));
  flow(*block);
  checked.iterations[&n] = IterationPlan{mode, std::string(owner),
                                         std::string(method), std::move(block)};
  return true;
}
} // namespace mettle
