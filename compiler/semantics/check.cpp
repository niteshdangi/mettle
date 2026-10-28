#include "semantics/checker.h"
#include "support/limits.h"
#include <functional>

namespace mettle {
void Checker::error(std::string phase, Span span, std::string message) {
  diagnostics.error(std::move(phase), span, std::move(message));
}

std::optional<CheckedModule> Checker::run() {
  products();
  if (!diagnostics.empty())
    return std::nullopt;
  checked.functions.resize(module.functions.size());
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &f = module.functions[i];
    if (!names.emplace(f.name, i).second)
      error("name", f.span, "duplicate function '" + f.name + "'");
    if (auto type = typeNames.find(f.name);
        type != typeNames.end() && checked.types->isProduct(type->second))
      error("name", f.span,
            "function conflicts with type constructor '" + f.name + "'");
    functionVariables[&f] =
        inference.fresh(annotation(f.annotation, f.span, f.owner));
    facts(f).diverges =
        f.annotation.name == "Never" && f.annotation.view.empty();
    if (f.destructor)
      checked.types->setDestructor(typeNames.at(f.owner), static_cast<int>(i));
  }
  if (!diagnostics.empty())
    return std::nullopt;
  bool changed;
  do {
    changed = false;
    for (auto &f : module.functions) {
      auto value = flow(*f.body);
      if (f.annotation.empty() && !facts(f).diverges && !value.normal &&
          !value.returns) {
        facts(f).diverges = true;
        inference.set(functionVariables[&f], Type::Never);
        changed = true;
      }
    }
  } while (changed);
  for (auto &f : module.functions)
    flow(*f.body);

  std::vector<std::vector<std::size_t>> edges(module.functions.size());
  std::function<void(Node &, std::vector<std::size_t> &)> calls =
      [&](Node &n, std::vector<std::size_t> &out) {
        if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name) {
          auto found = names.find(n.children[0]->text);
          if (found != names.end())
            out.push_back(found->second);
        } else if (n.kind == Kind::Call && n.children[0]->kind == Kind::Field) {
          for (std::size_t i = 0; i < module.functions.size(); ++i)
            if (module.functions[i].name.ends_with("." + n.children[0]->text))
              out.push_back(i);
        }
        for (auto &child : n.children)
          calls(*child, out);
      };
  for (std::size_t i = 0; i < edges.size(); ++i)
    calls(*module.functions[i].body, edges[i]);
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
    fields();
    for (auto w : component) {
      auto &f = module.functions[w];
      facts(f).result = inference.value(functionVariables[&f]);
      if (facts(f).result == Type::Unknown)
        error("type", f.span, "cannot infer recursive result; add ': Type'");
    }
  };
  for (std::size_t i = 0; i < edges.size(); ++i)
    if (index[i] == -1)
      visit(i);

  for (auto [variable, span] : integerOrBoolean) {
    auto t = inference.value(variable);
    if (t != Type::Bool && t != Type::I32 && t != Type::Never)
      error("type", span, "operation requires a resolved bool or i32 type");
  }
  for (auto [variable, span] : comparisons)
    if (checked.types->isProduct(inference.value(variable)))
      error("type", span,
            "product comparisons require a declared comparison interface");
  for (auto &f : module.functions) {
    facts(f).result = inference.value(functionVariables[&f]);
    std::function<void(Node &)> resolve = [&](Node &n) {
      for (auto &child : n.children)
        resolve(*child);
      if (nodeVariables.contains(&n))
        facts(n).type = inference.value(nodeVariables[&n]);
      if (n.kind == Kind::Name && facts(n).slot >= 0)
        facts(n).place = Place{facts(n).slot, {}};
      else if (n.kind == Kind::Group)
        facts(n).place = facts(*n.children[0]).place;
      else if (n.kind == Kind::Unary && n.text == "*" &&
               facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        facts(n).place->fields.push_back(Projection::dereference());
      } else if (n.kind == Kind::Field && facts(n).field >= 0 &&
                 facts(*n.children[0]).place) {
        facts(n).place = facts(*n.children[0]).place;
        for (unsigned i = 0; i < facts(n).dereferences; ++i)
          facts(n).place->fields.push_back(Projection::dereference());
        facts(n).place->fields.push_back(
            Projection::field(static_cast<std::uint32_t>(facts(n).field)));
      }
    };
    resolve(*f.body);
    for (std::size_t i = 0; i < facts(f).locals.size(); ++i) {
      facts(f).locals[i].type = inference.value(localVariables[&f][i]);
      if (facts(f).locals[i].type == Type::Unknown)
        error("type", facts(f).locals[i].span,
              "cannot infer local type; add ': Type'");
    }
    if (checked.types->containsViews(facts(f).result)) {
      std::vector<std::size_t> eligible;
      for (std::size_t p = 0; p < f.parameters.size(); ++p) {
        const auto &local = facts(f).locals[p];
        if (local.mode == ParameterMode::Read ||
            local.mode == ParameterMode::Mut ||
            checked.types->containsViews(local.type))
          eligible.push_back(p);
      }
      if (!f.annotation.sources.empty()) {
        for (const auto &source : f.annotation.sources) {
          auto found = std::find_if(
              f.parameters.begin(), f.parameters.end(),
              [&](const auto &parameter) { return parameter.name == source; });
          if (found == f.parameters.end())
            error("name", f.span,
                  "unknown borrowed result source '" + source + "'");
          else {
            auto index = static_cast<std::size_t>(found - f.parameters.begin());
            if (std::find(eligible.begin(), eligible.end(), index) ==
                eligible.end())
              error("ownership", f.span,
                    "borrowed result source is not borrowed input storage");
            else
              facts(f).resultSources.push_back(index);
          }
        }
      } else if (eligible.size() == 1)
        facts(f).resultSources = eligible;
      else if (eligible.size() > 1)
        error(
            "type", f.span,
            "ambiguous borrowed result requires an explicit from relationship");
      else
        error("ownership", f.span,
              "borrowed result has no eligible input source");
    }
  }
  auto main = names.find("main");
  if (main == names.end())
    error("name", {}, "missing entry function 'main'");
  else {
    auto &f = module.functions[main->second];
    if (!f.parameters.empty() || facts(f).result != Type::I32)
      error("type", f.span,
            "entry function must have no parameters and return i32");
  }
  if (!diagnostics.empty())
    return std::nullopt;
  return std::move(checked);
}
std::optional<CheckedModule> check(Module module, Diagnostics &diagnostics) {
  if (!diagnostics.empty())
    return std::nullopt;
  return Checker(std::move(module), diagnostics).run();
}

} // namespace mettle
