#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include "types/machine.h"
#include <algorithm>
#include <functional>
#include <map>
#include <stdexcept>

namespace mettle {
void Checker::error(std::string phase, Span span, std::string message) {
  if (phase == "type" && std::any_of(staticStates.begin(), staticStates.end(),
                                     [](auto state) { return state == 1; }))
    phase = "constant";
  ++reportedErrors;
  diagnostics.error(std::move(phase), span, std::move(message));
}

std::optional<CheckedModule> Checker::run() {
  interfaceHeaders();
  if (!diagnostics.empty())
    return std::nullopt;
  declarations();
  if (!diagnostics.empty())
    return std::nullopt;
  products();
  if (!diagnostics.empty())
    return std::nullopt;
  interfaceSignatures();
  checked.functions.resize(module.functions.size());
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &f = module.functions[i];
    current = &f;
    facts(f).genericParameters = genericBindings(f);
    auto name = definitionName(f.span, f.name);
    facts(f).canonicalName =
        f.constructor ? name + "$init" + std::to_string(i) : name;
    auto [existing, inserted] = names.emplace(name, i);
    if (!inserted &&
        !(f.constructor && module.functions[existing->second].constructor))
      error("name", f.span, "duplicate function '" + displayPath(f.name) + "'");
    if (auto type = typeNames.find(name);
        type != typeNames.end() && checked.types->isProduct(type->second) &&
        !checked.types->isSum(type->second))
      error("name", f.span,
            "function conflicts with type constructor '" + displayPath(f.name) +
                "'");
    functionVariables[&f] =
        inference.fresh(annotation(f.annotation, f.span, f.owner));
    facts(f).diverges = inference.value(functionVariables[&f]) == Type::Never;
    if (f.explicitReceiver) {
      if (f.owner.empty() && f.implementation < 0)
        error("signature", f.span,
              "explicit receiver requires an owning type or interface");
      else {
        auto self =
            annotation(f.parameters.front().annotation, f.span, f.owner);
        while (checked.types->isView(self))
          self = checked.types->view(self).payload;
        if (checked.types->isProduct(self) &&
            checked.types->product(self).kind == AggregateKind::Pin)
          self = checked.types->view(checked.types->product(self).components[0])
                     .payload;
        TypeSyntax expected;
        expected.name = "Self";
        if (checked.types->eraseRegions(self) !=
            checked.types->eraseRegions(annotation(expected, f.span, f.owner)))
          error("signature", f.span, "explicit receiver must wrap Self");
      }
    }
    if (!f.error.empty())
      facts(f).error = annotation(f.error, f.span, f.owner);
    if (f.destructor)
      checked.types->setDestructor(typeNames.at(typeName(f.owner, f.span)),
                                   static_cast<int>(i));
    if (f.body.get())
      if (f.body.get())
        controlFlow(f);
  }
  targetDeclarations();
  staticNamesAndTypes();
  for (const auto *product : deferredLayouts)
    checked.types->setProductLayout(
        typeNames.at(definitionName(product->span, product->name)),
        productLayout(*product));
  interfaceImplementations();
  if (diagnostics.empty())
    registerConstructors();
  proveDeferredObligations();
  staticDeclarations();
  if (diagnostics.empty())
    resolveRegionProjections();
  if (!diagnostics.empty())
    return std::nullopt;
  bool changed;
  do {
    changed = false;
    for (auto &f : module.functions) {
      if (!f.body.get())
        continue;
      genericBindings(f);
      if (!f.body.get())
        continue;
      auto value = flow(*f.body, f.owner);
      if (f.annotation.empty() && !facts(f).diverges && !value.normal &&
          !value.returns) {
        facts(f).diverges = true;
        inference.set(functionVariables[&f], Type::Never);
        changed = true;
      }
    }
  } while (changed);
  for (auto &f : module.functions)
    if (f.body.get())
      flow(*f.body, f.owner);

  std::vector<std::vector<std::size_t>> edges(module.functions.size());
  std::function<void(Node &, std::vector<std::size_t> &, std::string_view)>
      calls = [&](Node &n, std::vector<std::size_t> &out,
                  std::string_view owner) {
        if (n.kind == Kind::Name && !facts(n).lexicallyBound) {
          auto found = names.find(callableName(n.text, owner, n.span));
          if (found != names.end())
            out.push_back(found->second);
        } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name &&
                   !facts(*n.children[0]).lexicallyBound) {
          auto called = callableName(n.children[0]->text, owner, n.span);
          auto found = names.find(called);
          if (found != names.end())
            out.push_back(found->second);
          Type calledType = Type::Unknown;
          if (auto type = typeNames.find(called); type != typeNames.end())
            calledType = type->second;
          else if (auto alias = aliases.find(called); alias != aliases.end()) {
            const auto &syntax = module.aliases[alias->second];
            auto *saved = genericEnvironment;
            genericEnvironment = &aliasGenerics.at(&syntax);
            calledType = annotation(syntax.target, syntax.span);
            genericEnvironment = saved;
          }
          if (checked.types->isProduct(calledType)) {
            auto origin = checked.types->product(calledType).genericOrigin;
            if (origin == Type::Unknown)
              origin = calledType;
            if (auto candidates = constructors.find(origin);
                candidates != constructors.end())
              for (const auto &candidate : candidates->second)
                out.push_back(candidate.function);
          }
        } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Field) {
          for (std::size_t i = 0; i < module.functions.size(); ++i)
            if (module.functions[i].name.ends_with("." + n.children[0]->text))
              out.push_back(i);
        }
        if (auto plan = checked.iterations.find(&n);
            plan != checked.iterations.end())
          calls(*plan->second.elaboration, out, owner);
        for (auto &child : n.children)
          calls(*child, out, owner);
      };
  for (std::size_t i = 0; i < edges.size(); ++i) {
    if (module.functions[i].body.get())
      if (module.functions[i].body.get())
        calls(*module.functions[i].body, edges[i], module.functions[i].owner);
    for (auto &parameter : module.functions[i].parameters)
      if (parameter.defaultValue.get())
        calls(*parameter.defaultValue, edges[i], module.functions[i].owner);
  }
  std::vector<int> index(edges.size(), -1), low(edges.size());
  std::vector<std::size_t> stack;
  std::vector<bool> active(edges.size());
  int next = 0;
  std::function<void(std::size_t)> visit = [&](std::size_t v) {
    index[v] = low[v] = next++;
    stack.push_back(v);
    active[v] = true;
    for (auto w : edges[v]) {
      if (index[w] == -1) {
        visit(w);
        low[v] = std::min(low[v], low[w]);
      } else if (active[w])
        low[v] = std::min(low[v], index[w]);
    }
    if (low[v] != index[v])
      return;
    std::vector<std::size_t> component;
    while (true) {
      auto w = stack.back();
      stack.pop_back();
      active[w] = false;
      component.push_back(w);
      if (w == v)
        break;
    }
    for (auto w : component)
      function(module.functions[w]);
    resolveGenericCalls();
    fields();
    for (auto w : component) {
      auto &f = module.functions[w];
      facts(f).result = inference.value(functionVariables[&f]);
      facts(f).abiResult =
          facts(f).error == Type::Unknown
              ? facts(f).result
              : checked.types->structural(AggregateKind::Outcome,
                                          {facts(f).result, facts(f).error});
      if (facts(f).result == Type::Unknown && diagnostics.empty())
        error("type", f.span, "cannot infer recursive result; add ': Type'");
    }
  };
  for (std::size_t i = 0; i < edges.size(); ++i)
    if (index[i] == -1)
      visit(i);
  resolveGenericCalls();

  finishClosures();
  for (auto [variable, span] : integerOrBoolean) {
    auto t = inference.value(variable);
    if (t != Type::Bool && !isInteger(t) && t != Type::Never)
      error("type", span, "operation requires a resolved bool or integer type");
  }
  for (const auto &operation : numericOperations) {
    auto type = inference.value(operation.variable);
    bool valid = operation.operation == "arithmetic" ? isNumeric(type)
                 : operation.operation == "negate"
                     ? isSignedInteger(type) || isFloating(type)
                     : isInteger(type);
    if (!valid && type != Type::Never)
      error("type", operation.span,
            "operator is not available for this scalar type");
  }
  for (auto [variable, span] : comparisons)
    if (checked.types->isView(inference.value(variable)))
      error("type", span,
            "view comparisons require explicitly comparing the referenced "
            "values");
    else if (checked.types->isProduct(inference.value(variable)))
      error("type", span,
            "product comparisons require a declared comparison interface");
  for (auto &f : module.functions) {
    facts(f).result = inference.value(functionVariables[&f]);
    std::function<void(Node &)> resolve = [&](Node &n) {
      if (n.kind != Kind::Closure) {
        if (auto plan = checked.iterations.find(&n);
            plan != checked.iterations.end())
          resolve(*plan->second.elaboration);
        for (auto &child : n.children)
          resolve(*child);
      }
      if (nodeVariables.contains(&n))
        facts(n).type = inference.value(nodeVariables[&n]);
      if (facts(n).rebuiltType != Type::Unknown)
        facts(n).type = facts(n).rebuiltType;
      if (n.kind == Kind::Name && facts(n).slot >= 0) {
        facts(n).place = Place{facts(n).slot, {}};
        if (facts(f).locals[facts(n).slot].patternView)
          facts(n).place->fields.push_back(Projection::dereference());
      } else if (n.kind == Kind::Group) {
        const auto &child = facts(*n.children[0]);
        if (facts(n).rebuiltType != Type::Unknown || child.viewConversion ||
            child.rebuiltType != Type::Unknown || !child.injections.empty())
          facts(n).place.reset();
        else
          facts(n).place = child.place;
      } else if (n.kind == Kind::Unary && n.text == "*" &&
                 facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        facts(n).place->fields.push_back(Projection::dereference());
      } else if ((n.kind == Kind::Field || n.kind == Kind::Index) &&
                 !facts(n).optional && facts(n).field >= 0 &&
                 facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        for (unsigned i = 0; i < facts(n).dereferences; ++i)
          facts(n).place->fields.push_back(Projection::dereference());
        facts(n).place->fields.push_back(
            Projection::field(static_cast<std::uint32_t>(facts(n).field)));
      }
    };
    if (f.body.get())
      if (f.body.get())
        resolve(*f.body);
    for (auto &parameter : f.parameters)
      if (parameter.defaultValue.get())
        resolve(*parameter.defaultValue);
    std::optional<std::set<int>> poisonedRoots;
    auto poisoned = [&](std::size_t local) {
      if (!poisonedRoots) {
        poisonedRoots.emplace();
        for (auto variable : poisonedVariables)
          poisonedRoots->insert(inference.representative(variable));
      }
      return inference.depends(localVariables[&f][local], *poisonedRoots);
    };
    for (std::size_t i = 0; i < facts(f).locals.size(); ++i) {
      facts(f).locals[i].type = inference.value(localVariables[&f][i]);
      // A parameter's annotation is mandatory, so its failure is already
      // reported.
      if (facts(f).locals[i].type == Type::Unknown &&
          i >= f.parameters.size() && !poisoned(i))
        error("type", facts(f).locals[i].span,
              "cannot infer local type; add ': Type'");
      if (facts(f).locals[i].patternView) {
        facts(f).locals[i].type = checked.types->viewType(
            facts(f).locals[i].type, facts(f).locals[i].mode);
        facts(f).locals[i].mode = ParameterMode::Value;
      }
    }
    auto resultParameters = checked.types->typeParameters(facts(f).abiResult);
    for (std::size_t p = 0;
         p < f.parameters.size() && p < facts(f).locals.size(); ++p) {
      auto parameters = checked.types->typeParameters(facts(f).locals[p].type);
      bool transported = false;
      for (auto parameter : parameters)
        if (checked.types->isParameter(parameter) &&
            std::find(resultParameters.begin(), resultParameters.end(),
                      parameter) != resultParameters.end())
          transported = true;
      if (transported)
        facts(f).genericResultSources.push_back(p);
    }
  }
  resolvePatterns();
  if (diagnostics.empty())
    staticInitializers();
  std::map<Type, bool> varArgs;
  auto holdsVarArgs = [&](Type type) {
    auto [entry, inserted] = varArgs.try_emplace(type, false);
    if (inserted)
      entry->second = containsVarArgs(*checked.types, type);
    return entry->second;
  };
  for (const auto &[syntax, resolved] : checked.nodes) {
    if (holdsVarArgs(resolved.type) && !checked.types->isView(resolved.type) &&
        !(checked.types->isProduct(resolved.type) &&
          checked.types->product(resolved.type).kind == AggregateKind::VarArgs))
      error(
          "ownership", syntax->span,
          "a variadic cursor cannot escape into aggregate or closure storage");
    if (syntax->kind == Kind::Call && resolved.machineOperation.empty())
      for (std::size_t i = 1; i < syntax->children.size(); ++i)
        if (auto argument = checked.nodes.find(syntax->children[i].get());
            argument != checked.nodes.end() &&
            holdsVarArgs(argument->second.type))
          error("ownership", syntax->children[i]->span,
                "a variadic cursor cannot be passed outside its invocation");
    if (syntax->kind == Kind::Integer && resolved.numeric &&
        !integerLiteralFits(*resolved.numeric, resolved.type, pointerBits()))
      error("type", syntax->span,
            "integer literal is outside the " +
                displayPath(checked.types->name(resolved.type)) + " range");
    if (syntax->kind == Kind::Cast) {
      auto source = checked.nodes.at(syntax->children[0].get()).type;
      if (source != Type::Never && source != Type::Unknown &&
          !machineCastAllowed(*checked.types, source, resolved.type))
        error("type", syntax->span, "invalid scalar conversion");
    }
  }
  for (const auto &function : module.functions)
    if (holdsVarArgs(facts(function).result))
      error("ownership", function.span,
            "a variadic cursor cannot escape its invocation");
  if (diagnostics.empty())
    checkBorrowAlignment();
  if (diagnostics.empty())
    checkInterfaceContracts();
  if (diagnostics.empty())
    checkRegions();
  if (!diagnostics.empty())
    return std::nullopt;
  machineDeclarations();
  finishAssembly();
  if (!diagnostics.empty())
    return std::nullopt;
  finalizeInterfaces();
  exhaustiveness();
  if (!requireEntry)
    return diagnostics.empty()
               ? std::optional<CheckedModule>(std::move(checked))
               : std::nullopt;
  auto main = names.find("main");
  if (main == names.end())
    error("name", {}, "missing entry function 'main'");
  else {
    auto &f = module.functions[main->second];
    if (!facts(f).targetFeatures.empty() &&
        !featuresAvailable(checked.targetDescription, {},
                           facts(f).targetFeatures))
      error("feature", f.span,
            "hosted entry requires baseline target feature availability");
    if (!f.parameters.empty() || facts(f).result != Type::I32)
      error("type", f.span,
            "entry function must have no parameters and return i32");
    if (facts(f).error != Type::Unknown)
      error("effects", f.span,
            "entry function cannot expose an unhandled typed failure");
  }
  if (!diagnostics.empty())
    return std::nullopt;
  return std::move(checked);
}
std::optional<CheckedModule> check(Module module, Diagnostics &diagnostics,
                                   bool requireEntry, TargetFacts target) {
  if (!diagnostics.empty())
    return std::nullopt;
  auto symbols = resolution::resolve(module, diagnostics);
  return check(std::move(module), diagnostics, std::move(symbols), requireEntry,
               std::move(target));
}
std::optional<CheckedModule>
check(Module module, Diagnostics &diagnostics,
      std::shared_ptr<const resolution::Resolution> symbols, bool requireEntry,
      TargetFacts target) {
  if (!diagnostics.empty() || !symbols)
    return std::nullopt;
  try {
    return Checker(std::move(module), diagnostics, std::move(symbols),
                   requireEntry, std::move(target))
        .run();
  } catch (const std::length_error &failure) {
    diagnostics.error("limit", {}, failure.what());
    return std::nullopt;
  }
}

} // namespace mettle
