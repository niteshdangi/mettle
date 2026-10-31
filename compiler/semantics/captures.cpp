#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>
#include <set>
#include <tuple>

namespace mettle {
namespace {
ParameterMode stronger(ParameterMode a, ParameterMode b) {
  if (a == ParameterMode::Take || b == ParameterMode::Take)
    return ParameterMode::Take;
  if (a == ParameterMode::Mut || b == ParameterMode::Mut)
    return ParameterMode::Mut;
  return ParameterMode::Read;
}
} // namespace
int Checker::closure(Node &syntax, bool reachable) {
  (void)reachable;
  if (checked.closureBodies.size() + module.functions.size() >=
      limits::functions) {
    error("limit", syntax.span, "closure function limit exceeded");
    return inference.fresh();
  }
  auto owned = std::make_unique<ClosureFacts>();
  auto &closure = *owned;
  closure.syntax = &syntax;
  closure.parent = current;
  closure.declaration.name =
      "<closure-" + std::to_string(checked.closureBodies.size()) + ">";
  closure.declaration.span = syntax.span;
  closure.declaration.owner = current->owner;
  closure.declaration.annotation = syntax.annotation;
  closure.declaration.error = syntax.error;
  auto index = checked.closureBodies.size();
  checked.closureBodies.push_back(std::move(owned));
  closureFunctions[&closure.declaration] = index;
  facts(syntax).closure = static_cast<int>(index);
  auto *outer = current;
  closure.function.genericParameters = facts(*outer).genericParameters;
  closure.function.interfaceBounds = facts(*outer).interfaceBounds;
  closure.function.unpinBounds = facts(*outer).unpinBounds;
  closure.function.genericEqualities = facts(*outer).genericEqualities;
  auto savedScopes = scopes;
  auto savedLoops = std::move(loopResults);
  auto savedEffectContext = effectContext;
  current = &closure.declaration;
  closureScopes.emplace_back(current, scopes.size());
  scopes.emplace_back();
  effectContext = 0;
  local("<environment>", inference.fresh(), false, syntax.span);
  Type expected = Type::Unknown;
  if (auto found = closureContexts.find(&syntax);
      found != closureContexts.end())
    expected = found->second;
  const CallableType *context = checked.types->isCallable(expected)
                                    ? &checked.types->callable(expected)
                                    : nullptr;
  // Interning annotations may grow callable storage.
  std::optional<CallableType> contextCopy;
  if (context) {
    contextCopy = *context;
    context = &*contextCopy;
    if (context->parameters.size() != syntax.parameters.size())
      error("type", syntax.span,
            "closure parameter count does not match context");
  }
  auto resultType =
      syntax.annotation.empty()
          ? (context ? context->result : Type::Unknown)
          : annotation(syntax.annotation, syntax.span, current->owner);
  functionVariables[current] = inference.fresh(resultType);
  if (!syntax.error.empty())
    closure.function.error =
        annotation(syntax.error, syntax.span, current->owner);
  else if (context && context->error != Type::Unknown)
    error("effects", syntax.span,
          "closure typed failure requires an explicit throws annotation");
  for (std::size_t p = 0; p < syntax.parameters.size(); ++p) {
    const auto &parameter = syntax.parameters[p];
    auto type =
        parameter.annotation.empty()
            ? (context && p < context->parameters.size()
                   ? context->parameters[p].type
                   : Type::Unknown)
            : annotation(parameter.annotation, parameter.span, current->owner);
    auto mode = parameter.mode == "take"   ? ParameterMode::Take
                : parameter.mode == "read" ? ParameterMode::Read
                : parameter.mode == "mut"  ? ParameterMode::Mut
                : context && p < context->parameters.size()
                    ? context->parameters[p].mode
                : checked.types->isCopy(type) ? ParameterMode::Value
                                              : ParameterMode::Read;
    if (scopes.back().contains(parameter.name))
      error("name", parameter.span, "duplicate closure parameter");
    auto slot =
        local(parameter.name, inference.fresh(type), false, parameter.span);
    if (slot >= 0)
      closure.function.locals[slot].mode = mode;
    Parameter declaration{parameter.name, parameter.annotation, parameter.span,
                          parameter.mode};
    closure.declaration.parameters.push_back(std::move(declaration));
  }
  for (std::size_t p = 0; p < closure.declaration.parameters.size(); ++p) {
    auto &parameter = syntax.parameters[p];
    if (!parameter.pattern)
      continue;
    auto first = closure.function.locals.size();
    pattern(*parameter.pattern, localVariables[current][p + 1],
            closure.function.locals[p + 1].mode);
    for (auto slot = first; slot < closure.function.locals.size(); ++slot)
      closure.function.parameterBindings[static_cast<int>(slot)] = p + 1;
    irrefutable.emplace_back(&*parameter.pattern,
                             localVariables[current][p + 1]);
  }
  staticLocals();
  flow(*syntax.children[0], current->owner);
  contextualize(*syntax.children[0], resultType);
  auto body = node(*syntax.children[0], true);
  if (facts(*syntax.children[0]).flow.normal)
    coerce(*syntax.children[0], body, functionVariables[current], syntax.span);
  fields(false);
  completeClosure(closure);
  current = outer;
  scopes = std::move(savedScopes);
  loopResults = std::move(savedLoops);
  effectContext = savedEffectContext;
  closureScopes.pop_back();
  if (context && compatibleCallable(closure.type, expected)) {
    facts(syntax).callableCoercion = expected;
    facts(syntax).callableSource = closure.type;
    facts(syntax).rebuiltType = expected;
    return inference.fresh(expected);
  }
  return inference.fresh(closure.type);
}
void Checker::completeClosure(ClosureFacts &closure, bool final) {
  const auto &syntax = *closure.syntax;
  closure.function.result =
      inference.value(functionVariables.at(&closure.declaration));
  closure.function.abiResult =
      closure.function.error == Type::Unknown
          ? closure.function.result
          : checked.types->structural(
                AggregateKind::Outcome,
                {closure.function.result, closure.function.error});
  resolveClosure(closure, final);
  bool unresolved = closure.function.result == Type::Unknown;
  for (std::size_t i = 1; i < closure.function.locals.size(); ++i)
    unresolved |= closure.function.locals[i].type == Type::Unknown;
  if (final && closure.function.result == Type::Unknown)
    error("type", syntax.span, "cannot infer closure result; add ': Type'");
  closure.deferred = unresolved;
  closure.captures.clear();
  closure.function.resultSources.clear();
  if (!unresolved)
    inferCaptures(closure);
  CallableType descriptor;
  descriptor.function =
      static_cast<int>(closureFunctions.at(&closure.declaration));
  descriptor.result = closure.function.result;
  descriptor.error = closure.function.error;
  descriptor.abiResult = closure.function.abiResult;
  for (std::size_t p = 0; p < syntax.parameters.size(); ++p) {
    auto &local = closure.function.locals[p + 1];
    if (syntax.parameters[p].mode.empty() && !closureContexts.contains(&syntax))
      local.mode = checked.types->isCopy(local.type) ? ParameterMode::Value
                                                     : ParameterMode::Read;
    descriptor.parameters.push_back(
        {local.type, local.mode, syntax.parameters[p].name});
  }
  std::vector<TypeField> fields;
  for (std::size_t c = 0; c < closure.captures.size(); ++c) {
    auto &capture = closure.captures[c];
    descriptor.mode = stronger(descriptor.mode, capture.mode);
    if (final && !syntax.flag && capture.mode == ParameterMode::Take)
      error("ownership", capture.span,
            "moving a captured place requires a take closure");
    auto rootMode = facts(*closure.parent).locals[capture.source.root].mode;
    capture.viaView =
        syntax.flag && capture.mode != ParameterMode::Take &&
        (rootMode == ParameterMode::Read || rootMode == ParameterMode::Mut) &&
        (!checked.types->isCopy(capture.type) ||
         !checked.types->isSized(capture.type));
    capture.storedType =
        syntax.flag && !capture.viaView
            ? capture.type
            : checked.types->viewType(capture.type,
                                      capture.mode == ParameterMode::Mut
                                          ? ParameterMode::Mut
                                          : ParameterMode::Read);
    const auto &local = closure.function.locals[capture.proxy.root];
    std::string name = local.name;
    auto current = local.type;
    for (const auto &projection : capture.proxy.fields) {
      if (projection.kind == Projection::Kind::Field &&
          checked.types->isProduct(current) &&
          projection.index < checked.types->product(current).fields.size())
        name +=
            "." + checked.types->product(current).fields[projection.index].name;
      auto next =
          projectedType(*checked.types, current, std::span(&projection, 1));
      if (!next)
        break;
      current = *next;
    }
    if (name.empty())
      name = "<capture-" + std::to_string(c) + ">";
    fields.push_back({std::move(name), capture.storedType});
  }
  if (checked.types->containsViews(closure.function.abiResult)) {
    std::vector<std::size_t> eligible;
    bool capturedViews = false;
    for (const auto &field : fields)
      capturedViews |= checked.types->containsViews(field.type);
    if (!closure.captures.empty() &&
        (descriptor.mode != ParameterMode::Take || capturedViews))
      eligible.push_back(0);
    for (std::size_t p = 0; p < syntax.parameters.size(); ++p) {
      const auto &parameter = closure.function.locals[p + 1];
      if (parameter.mode == ParameterMode::Read ||
          parameter.mode == ParameterMode::Mut ||
          checked.types->containsViews(parameter.type))
        eligible.push_back(p + 1);
    }
    if (!syntax.annotation.sources.empty()) {
      for (const auto &source : syntax.annotation.sources) {
        bool found = source == "static";
        for (auto p : eligible) {
          if (p && syntax.parameters[p - 1].name == source) {
            closure.function.resultSources.push_back(p);
            found = true;
          } else if (!p)
            for (const auto &capture : closure.captures)
              if (facts(*closure.parent).locals[capture.source.root].name ==
                  source) {
                closure.function.resultSources.push_back(0);
                found = true;
              }
        }
        if (final && !found)
          error("ownership", syntax.span, "invalid closure result source");
      }
    } else if (eligible.size() == 1)
      closure.function.resultSources = eligible;
    else if (final && !unresolved)
      error("ownership", syntax.span,
            "borrowed closure result requires an unambiguous from contract");
  }
  for (auto source : closure.function.resultSources)
    if (source)
      descriptor.resultSources.push_back(source - 1);
    else
      descriptor.resultFromEnvironment = true;
  // A coroutine body outlives its start call, so its state owns the captures.
  descriptor.environmentMode =
      syntax.text == "coroutine" ? ParameterMode::Take
      : !syntax.flag && descriptor.mode == ParameterMode::Read
          ? ParameterMode::Value
          : descriptor.mode;
  if (closure.type == Type::Unknown)
    closure.type = checked.types->closureType(closure.declaration.name,
                                              std::move(fields), descriptor);
  else
    checked.types->defineClosure(closure.type, std::move(fields), descriptor);
  checked.types->setGenericParameters(closure.type,
                                      closure.function.genericParameters);
  closure.function.canonicalName = closure.declaration.name;
  closure.function.locals[0].type = closure.type;
  closure.function.locals[0].mode = descriptor.environmentMode;
  if (syntax.text == "coroutine" && !unresolved)
    coroutineInterior(closure, syntax);
}
// Like Rust generators, the interior is scope-based rather than
// liveness-based: the lexical bindings in scope at each suspension and the
// operands already evaluated around it. It may over-approximate.
void Checker::coroutineInterior(const ClosureFacts &closure,
                                const Node &syntax) {
  std::set<std::string> names;
  std::vector<Type> held;
  std::function<void(const Pattern &, std::vector<std::string> &)> bindings =
      [&](const Pattern &pattern, std::vector<std::string> &scope) {
        if (pattern.kind == PatternKind::Binding)
          scope.push_back(pattern.text);
        for (const auto &child : pattern.children)
          bindings(child, scope);
      };
  auto callee = [](const Node &n, std::string_view name) {
    return n.kind == Kind::Call && !n.children.empty() &&
           n.children[0]->kind == Kind::Name && n.children[0]->text == name;
  };
  std::function<void(const Node &, std::vector<std::string>, std::vector<Type>)>
      walk = [&](const Node &n, std::vector<std::string> scope,
                 std::vector<Type> evaluated) {
        if (&n != &syntax && n.kind == Kind::Closure)
          return;
        if (callee(n, "core::intrinsics::coroutine_suspend")) {
          names.insert(scope.begin(), scope.end());
          held.insert(held.end(), evaluated.begin(), evaluated.end());
          return;
        }
        if (n.kind == Kind::Block) {
          for (const auto &child : n.children) {
            walk(*child, scope, evaluated);
            if (child->kind != Kind::Binding)
              continue;
            if (child->text != "_")
              scope.push_back(child->text);
            for (const auto &pattern : child->patterns)
              bindings(pattern, scope);
          }
          return;
        }
        if (n.kind != Kind::Binding)
          for (const auto &pattern : n.patterns)
            bindings(pattern, scope);
        // The desugared await's poll result is consumed before suspending.
        bool poll = n.kind == Kind::Match && !n.children.empty() &&
                    callee(*n.children[0], "core::future::poll_await");
        for (const auto &child : n.children) {
          walk(*child, scope, evaluated);
          if (auto found = checked.nodes.find(child.get());
              !poll && found != checked.nodes.end() &&
              found->second.type != Type::Unknown)
            evaluated.push_back(found->second.type);
        }
      };
  walk(syntax, {}, {});
  for (std::size_t i = 1; i < closure.function.locals.size(); ++i)
    if (names.contains(closure.function.locals[i].name) &&
        closure.function.locals[i].type != Type::Unknown)
      held.push_back(closure.function.locals[i].type);
  std::sort(held.begin(), held.end());
  held.erase(std::unique(held.begin(), held.end()), held.end());
  checked.types->setCoroutineInterior(closure.type, std::move(held));
}
void Checker::finishClosures() {
  bool changed = true;
  unsigned rounds = 0;
  while (changed) {
    if (++rounds > limits::typeDepth) {
      error("limit", {}, "closure capture capability inference limit exceeded");
      return;
    }
    changed = false;
    for (auto &closure : checked.closureBodies) {
      const auto before = checked.types->callable(closure->type);
      std::vector<std::tuple<Place, ParameterMode, Type>> captures;
      for (const auto &capture : closure->captures)
        captures.emplace_back(capture.proxy, capture.mode, capture.storedType);
      completeClosure(*closure);
      const auto &after = checked.types->callable(closure->type);
      changed |= before.mode != after.mode || before.result != after.result ||
                 before.parameters != after.parameters ||
                 before.resultFromEnvironment != after.resultFromEnvironment ||
                 before.resultSources != after.resultSources ||
                 captures.size() != closure->captures.size();
      for (std::size_t i = 0;
           i < captures.size() && i < closure->captures.size(); ++i)
        changed |=
            captures[i] != std::make_tuple(closure->captures[i].proxy,
                                           closure->captures[i].mode,
                                           closure->captures[i].storedType);
    }
  }
  for (auto &closure : checked.closureBodies)
    completeClosure(*closure, true);
  checked.types->refreshProductInstances();
  for (const auto &[syntax, node] : checked.nodes)
    if (node.callableCoercion != Type::Unknown &&
        !compatibleCallable(node.callableSource, node.callableCoercion))
      error("type", syntax->span,
            "closure or function is not compatible with the function pointer");
}
void Checker::resolveClosure(ClosureFacts &closure, bool final) {
  auto &function = closure.declaration;
  for (std::size_t i = 1; i < closure.function.locals.size(); ++i) {
    auto &local = closure.function.locals[i];
    auto patternMode = checked.types->isView(local.type)
                           ? checked.types->view(local.type).mode
                           : local.mode;
    local.type = inference.value(localVariables[&function][i]);
    if (final && local.type == Type::Unknown)
      error("type", local.span, "cannot infer closure parameter or local type");
    if (local.patternView) {
      local.type = checked.types->viewType(local.type, patternMode);
      local.mode = ParameterMode::Value;
    }
  }
  std::function<void(const Node &)> resolve = [&](const Node &node) {
    if (node.kind != Kind::Closure) {
      if (auto plan = checked.iterations.find(&node);
          plan != checked.iterations.end())
        resolve(*plan->second.elaboration);
      for (auto &child : node.children)
        resolve(*child);
    }
    auto &checkedNode = facts(node);
    if (nodeVariables.contains(&node))
      checkedNode.type = inference.value(nodeVariables.at(&node));
    if (checkedNode.rebuiltType != Type::Unknown)
      checkedNode.type = checkedNode.rebuiltType;
    if (node.kind == Kind::Name && checkedNode.slot >= 0) {
      checkedNode.place = Place{checkedNode.slot, {}};
      if (closure.function.locals[checkedNode.slot].patternView)
        checkedNode.place->fields.push_back(Projection::dereference());
    } else if (node.kind == Kind::Group) {
      const auto &child = facts(*node.children[0]);
      if (checkedNode.rebuiltType != Type::Unknown || child.viewConversion ||
          child.rebuiltType != Type::Unknown || !child.injections.empty())
        checkedNode.place.reset();
      else
        checkedNode.place = child.place;
    } else if (node.kind == Kind::Unary && node.text == "*" &&
               facts(*node.children[0]).place) {
      checkedNode.place = facts(*node.children[0]).place;
      checkedNode.place->fields.push_back(Projection::dereference());
    } else if ((node.kind == Kind::Field || node.kind == Kind::Index) &&
               checkedNode.field >= 0 && facts(*node.children[0]).place) {
      checkedNode.place = facts(*node.children[0]).place;
      for (unsigned i = 0; i < checkedNode.dereferences; ++i)
        checkedNode.place->fields.push_back(Projection::dereference());
      checkedNode.place->fields.push_back(
          Projection::field(static_cast<std::uint32_t>(checkedNode.field)));
    }
  };
  resolve(*closure.syntax->children[0]);
}
void Checker::inferCaptures(ClosureFacts &closure) {
  const auto &bindings = captureBindings[&closure.declaration];
  auto record = [&](Place place, ParameterMode mode, Span span) {
    auto binding = std::find_if(
        bindings.begin(), bindings.end(),
        [&](const auto &binding) { return binding.proxy == place.root; });
    if (binding == bindings.end())
      return;
    // Precise capture paths stop at a raw-pointer dereference (capture the
    // pointer, not a copy of its target) and, in a take closure, at a field
    // of a value with a destructor (own the whole value).
    auto base = closure.function.locals[place.root].type;
    for (std::size_t i = 0; i < place.fields.size(); ++i) {
      if (place.fields[i].kind == Projection::Kind::Dereference &&
          checked.types->isPointer(base)) {
        place.fields.resize(i);
        mode = ParameterMode::Value;
        break;
      }
      if (closure.syntax->flag &&
          place.fields[i].kind == Projection::Kind::Field &&
          checked.types->isProduct(base) &&
          checked.types->product(base).hasDestructor) {
        place.fields.resize(i);
        break;
      }
      auto next = projectedType(*checked.types, base,
                                std::span(place.fields).subspan(i, 1));
      if (!next)
        break;
      base = *next;
    }
    ClosureCapture capture;
    capture.proxy = place;
    capture.source = place;
    capture.source.root = binding->source.slot;
    capture.mode = mode;
    capture.span = span;
    for (auto it = closure.captures.begin(); it != closure.captures.end();) {
      if (!overlaps(it->proxy, capture.proxy)) {
        ++it;
        continue;
      }
      auto common = std::mismatch(
          it->proxy.fields.begin(), it->proxy.fields.end(),
          capture.proxy.fields.begin(), capture.proxy.fields.end());
      capture.proxy.fields.resize(
          static_cast<std::size_t>(common.first - it->proxy.fields.begin()));
      capture.source.fields = capture.proxy.fields;
      capture.mode = stronger(capture.mode, it->mode);
      if (it->span.begin < capture.span.begin)
        capture.span = it->span;
      it = closure.captures.erase(it);
    }
    capture.type = *projectedType(
        *checked.types, closure.function.locals[capture.proxy.root].type,
        capture.proxy.fields);
    closure.captures.push_back(std::move(capture));
  };
  auto recordReceiver = [&](const Node &source, const ReceiverPlan &plan,
                            ParameterMode mode) {
    if (!facts(source).place)
      return false;
    auto place = *facts(source).place;
    if (!closure.syntax->flag)
      for (const auto &step : plan.steps) {
        if (step.kind != ReceiverStep::Kind::Native)
          break;
        place.fields.push_back(Projection::dereference());
      }
    record(std::move(place), mode, source.span);
    return true;
  };
  std::function<void(const Node &, ParameterMode)> visit =
      [&](const Node &node, ParameterMode use) {
        const auto &conversion = facts(node);
        if (conversion.viewConversion) {
          use = checked.types->view(conversion.conversionView).mode;
          if (recordReceiver(node, *conversion.viewConversion, use))
            return;
        }
        if (conversion.borrowConversion &&
            recordReceiver(node, *conversion.borrowConversion, use))
          return;
        auto nativeSource = conversion.unsizedSource != Type::Unknown
                                ? conversion.unsizedSource
                            : conversion.erasedSource != Type::Unknown
                                ? conversion.erasedSource
                                : conversion.reborrowSource;
        if (nativeSource != Type::Unknown &&
            checked.types->isView(nativeSource)) {
          ReceiverPlan native{nativeSource, nativeSource, {}};
          bool firstClass = checked.types->isView(conversion.type);
          if (firstClass)
            use = checked.types->view(conversion.type).mode;
          do {
            ReceiverStep step;
            step.source = native.target;
            step.target = checked.types->view(native.target).payload;
            native.target = step.target;
            native.steps.push_back(step);
          } while (!firstClass && checked.types->isView(native.target));
          if (recordReceiver(node, native, use))
            return;
        }
        if (node.kind == Kind::Closure) {
          const auto &nested = *checked.closureBodies.at(facts(node).closure);
          for (const auto &capture : nested.captures)
            record(capture.source,
                   node.flag && !checked.types->isCopy(capture.type)
                       ? ParameterMode::Take
                       : capture.mode,
                   capture.span);
          return;
        }
        if (facts(node).operatorCall) {
          const auto signature = functionSignature(facts(node).callee);
          for (std::size_t i = 0; i < node.children.size(); ++i)
            visit(*node.children[i], signature.parameters[i].mode);
          return;
        }
        if (node.kind == Kind::Assign) {
          visit(*node.children[0], ParameterMode::Mut);
          visit(*node.children[1], ParameterMode::Value);
          return;
        }
        if (node.kind == Kind::Unary &&
            (node.text == "read" || node.text == "mut" ||
             node.text == "take")) {
          visit(*node.children[0], node.text == "read"  ? ParameterMode::Read
                                   : node.text == "mut" ? ParameterMode::Mut
                                                        : ParameterMode::Take);
          return;
        }
        if (node.kind == Kind::Call) {
          const auto &call = facts(node);
          if (!call.machineOperation.empty()) {
            std::size_t operand = 0;
            if (call.method)
              visit(*node.children[0]->children[0],
                    call.machineBorrowModes.at(operand++));
            for (std::size_t i = 1; i < node.children.size(); ++i)
              visit(*node.children[i], call.machineBorrowModes.at(operand++));
          } else if (call.indirect) {
            auto type = facts(*node.children[0]).type;
            while (checked.types->isView(type))
              type = checked.types->view(type).payload;
            const auto signature = checked.types->callable(type);
            if (call.optional)
              visit(*node.children[0]->children[0], ParameterMode::Read);
            else
              visit(*node.children[0], signature.mode);
            for (std::size_t i = 1; i < node.children.size(); ++i)
              visit(*node.children[i], i <= signature.parameters.size()
                                           ? signature.parameters[i - 1].mode
                                           : ParameterMode::Value);
          } else if (call.callee < 0) {
            // Unresolved callee: its diagnostic is already reported.
            for (std::size_t i = 1; i < node.children.size(); ++i)
              visit(*node.children[i], ParameterMode::Value);
          } else {
            if (call.method) {
              const auto &receiver = *node.children[0]->children[0];
              auto mode = functionSignature(call.callee).parameters[0].mode;
              if (!call.receiverPlan ||
                  !recordReceiver(receiver, *call.receiverPlan, mode))
                visit(receiver, mode);
            }
            for (std::size_t i = 1; i < node.children.size(); ++i) {
              auto mode = call.constructor
                              ? ParameterMode::Value
                              : functionSignature(call.callee)
                                    .parameters[call.argumentOrder[i - 1]]
                                    .mode;
              visit(*node.children[i], mode);
            }
          }
          return;
        }
        if ((node.kind == Kind::Index || node.kind == Kind::Field) &&
            !facts(node).place) {
          auto mode = use;
          if (mode == ParameterMode::Value)
            mode = checked.types->isCopy(facts(node).type)
                       ? ParameterMode::Read
                       : ParameterMode::Take;
          visit(*node.children[0], mode);
          if (node.kind == Kind::Index)
            visit(*node.children[1], ParameterMode::Read);
          return;
        }
        if (facts(node).place) {
          auto mode = use;
          if (mode == ParameterMode::Value)
            mode = checked.types->isCopy(facts(node).type)
                       ? ParameterMode::Read
                       : ParameterMode::Take;
          record(*facts(node).place, mode, node.span);
          if (node.kind == Kind::Index)
            visit(*node.children[1], ParameterMode::Read);
          return;
        }
        if (auto plan = checked.iterations.find(&node);
            plan != checked.iterations.end()) {
          visit(*plan->second.elaboration, ParameterMode::Value);
          return;
        }
        for (const auto &child : node.children)
          visit(*child, ParameterMode::Value);
      };
  visit(*closure.syntax->children[0], ParameterMode::Value);
  std::stable_sort(
      closure.captures.begin(), closure.captures.end(),
      [](const auto &a, const auto &b) { return a.span.begin < b.span.begin; });
}
} // namespace mettle
