#include "expansion/detail.h"
#include <algorithm>

namespace mettle::expansion {
namespace {
enum class Site { Item, Declaration, Field, Variant, VariantField, Import };

class Expander {
public:
  Expander(Module &module, Diagnostics &diagnostics,
           const Configuration &configuration, const SourceAllocator &allocate)
      : module(module), diagnostics(diagnostics), configuration(configuration),
        allocate(allocate) {}

  void run() {
    for (auto &declaration : module.modules) {
      auto scope = declaration.item.scope;
      scope.push_back(declaration.name);
      auto span = extent(declaration.span, declaration.item.attributes);
      if (!process(declaration.item.attributes, Site::Item)) {
        inactive.push_back(std::move(scope));
        module.inactiveSyntax.push_back(span);
      }
    }
    retain(module.modules, [&](Module::ModuleDeclaration &item) {
      auto scope = item.item.scope;
      scope.push_back(item.name);
      return !inside(scope);
    });
    retain(module.functions, [&](Function &item) {
      auto attributes = configuration.collectTests ? item.item.attributes
                                                   : std::vector<Attribute>{};
      auto span = extent(functionSpan(item), item.item.attributes);
      if (!keep(item.item, Site::Item, functionSpan(item)))
        return false;
      if (configuration.collectTests)
        collect(item, attributes);
      bool drop = configuration.dropEntry && item.item.scope.empty() &&
                  item.name == "main";
      if (drop)
        module.inactiveSyntax.push_back(span);
      return !drop;
    });
    retain(module.statics, [&](Module::Static &item) {
      return keep(item.item, Site::Item, item.span);
    });
    retain(module.aliases, [&](Module::Alias &item) {
      return keep(item.item, Site::Import, item.span);
    });
    retain(module.imports, [&](Module::Import &item) {
      return keep(item.item, Site::Import, item.span);
    });
    retain(module.interfaces, [&](Module::Interface &item) {
      methods(item.methods);
      return keep(item.item, Site::Item, item.span);
    });
    retain(module.implementations, [&](Module::Implementation &item) {
      methods(item.methods);
      return keep(item.item, Site::Item, item.span);
    });
    retain(module.products,
           [&](Module::Product &item) { return product(item); });
    for (std::size_t i = 0; i < module.products.size(); ++i)
      derive(i);
  }

private:
  Module &module;
  Diagnostics &diagnostics;
  const Configuration &configuration;
  const SourceAllocator &allocate;
  // Scopes of the inline modules whose own `@cfg` predicate is false.
  std::vector<std::vector<std::string>> inactive;

  template <typename T, typename Keep>
  static void retain(std::vector<T> &items, Keep keep) {
    std::erase_if(items, [&](T &item) { return !keep(item); });
  }

  static Span extent(Span span, const std::vector<Attribute> &attributes) {
    for (const auto &attribute : attributes)
      if (attribute.span.source == span.source)
        span.begin = std::min(span.begin, attribute.span.begin);
    return span;
  }

  static Span functionSpan(const Function &function) {
    auto span = function.span;
    if (function.body.get())
      span.end = std::max(span.end, function.body->span.end);
    return span;
  }

  bool inside(const std::vector<std::string> &scope) const {
    return std::any_of(
        inactive.begin(), inactive.end(), [&](const auto &prefix) {
          return scope.size() >= prefix.size() &&
                 std::equal(prefix.begin(), prefix.end(), scope.begin());
        });
  }

  // Validates and consumes an item's attributes; an item inside an inactive
  // inline module is dropped together with the module.
  bool keep(ItemSyntax &item, Site site, Span span) {
    span = extent(span, item.attributes);
    auto own = process(item.attributes, site);
    bool active = own && !inside(item.scope);
    if (!active)
      module.inactiveSyntax.push_back(span);
    return active;
  }

  void methods(std::vector<Function> &members) {
    retain(members, [&](Function &method) {
      auto span = extent(functionSpan(method), method.item.attributes);
      bool active = process(method.item.attributes, Site::Item);
      if (!active)
        module.inactiveSyntax.push_back(span);
      return active;
    });
  }

  bool product(Module::Product &item) {
    auto span = extent(item.span, item.item.attributes);
    auto own = process(item.item.attributes, Site::Declaration);
    retain(item.fields, [&](Parameter &field) {
      auto fieldSpan =
          extent(field.syntaxSpan.value_or(field.span), field.attributes);
      bool active = process(field.attributes, Site::Field);
      if (!active)
        module.inactiveSyntax.push_back(fieldSpan);
      return active;
    });
    methods(item.methods);
    retain(item.variants, [&](Module::Product::Variant &variant) {
      auto variantSpan = extent(variant.span, variant.attributes);
      auto variantActive = process(variant.attributes, Site::Variant);
      retain(variant.fields, [&](Parameter &field) {
        auto fieldSpan =
            extent(field.syntaxSpan.value_or(field.span), field.attributes);
        bool active = process(field.attributes, Site::VariantField);
        if (!active)
          module.inactiveSyntax.push_back(fieldSpan);
        return active;
      });
      if (!variantActive)
        module.inactiveSyntax.push_back(variantSpan);
      return variantActive;
    });
    item.hasDestructor =
        std::any_of(item.methods.begin(), item.methods.end(),
                    [](const Function &method) { return method.destructor; });
    bool active = own && !inside(item.item.scope);
    if (!active)
      module.inactiveSyntax.push_back(span);
    return active;
  }

  static bool harnessAttribute(const std::string &name) {
    return name == "test" || name == "bench" || name == "ignore" ||
           name == "should_panic";
  }

  // The optional constant text argument of `@ignore("...")` and
  // `@should_panic("...")`.
  std::string textArgument(const Attribute &attribute) {
    if (!attribute.parenthesized || attribute.arguments.empty())
      return {};
    if (attribute.arguments.size() != 1 ||
        attribute.arguments[0].kind != TokenKind::Text ||
        attribute.arguments[0].text.size() < 2) {
      diagnostics.error("attribute", attribute.span,
                        "attribute '@" + attribute.name +
                            "' takes at most one constant text argument");
      return {};
    }
    const auto &text = attribute.arguments[0].text;
    return text.substr(1, text.size() - 2);
  }

  // Records a function annotated for the harness (the attributes as written,
  // before `@cfg` consumption).
  void collect(Function &function, const std::vector<Attribute> &attributes) {
    Module::TestFunction found;
    bool marked = false, modifiers = false;
    for (const auto &attribute : attributes) {
      if (attribute.name == "test" || attribute.name == "bench") {
        if (marked)
          diagnostics.error("attribute", attribute.span,
                            "a function is either '@test' or '@bench', once");
        marked = true;
        found.bench = attribute.name == "bench";
      } else if (attribute.name == "ignore") {
        modifiers = found.ignored = true;
        found.ignoreReason = textArgument(attribute);
      } else if (attribute.name == "should_panic") {
        modifiers = found.shouldPanic = true;
        found.panicMessage = textArgument(attribute);
      }
    }
    if (!marked) {
      if (modifiers)
        diagnostics.error("attribute", function.span,
                          "'@ignore' and '@should_panic' need '@test' or "
                          "'@bench' on the same function");
      return;
    }
    const auto &result = function.annotation;
    bool unit = result.empty() ||
                (result.form == TypeForm::Named && result.name == "Unit" &&
                 result.arguments.empty()) ||
                (result.form == TypeForm::Tuple && result.elements.empty());
    if (!function.parameters.empty() || !function.genericParameters.empty() ||
        !function.owner.empty() || (!unit && !found.bench) ||
        function.foreignDeclaration)
      diagnostics.error("attribute", function.span,
                        "'@test' and '@bench' functions are plain functions "
                        "without parameters or generics; a '@test' function "
                        "has no result other than Unit");
    if (found.bench && found.shouldPanic)
      diagnostics.error("attribute", function.span,
                        "'@should_panic' applies to '@test' functions");
    found.path = function.item.scope;
    found.path.push_back(function.name);
    found.span = function.span;
    found.fallible = !function.error.empty();
    // The generated harness is in the package root, so collected entries in
    // descendant modules must be package-visible to that caller.
    function.item.visibility.publicItem = true;
    function.item.visibility.restriction = {"package"};
    module.tests.push_back(std::move(found));
  }

  // Returns false when a `@cfg` predicate excludes the attributed syntax.
  bool process(std::vector<Attribute> &attributes, Site site) {
    bool active = true, sawCfg = false;
    std::erase_if(attributes, [&](const Attribute &attribute) {
      if (!knownAttribute(attribute.name)) {
        diagnostics.error("attribute", attribute.span,
                          "unknown attribute '@" + attribute.name + "'");
        return false;
      }
      if (attribute.name == "cfg") {
        if (sawCfg)
          diagnostics.error("attribute", attribute.span,
                            "duplicate attribute 'cfg'; combine predicates "
                            "with all(...)");
        sawCfg = true;
        active &= evaluateCfg(attribute, configuration, diagnostics);
        return true;
      }
      if (harnessAttribute(attribute.name)) {
        // Consumed: ordinary builds ignore test metadata.
        if (site != Site::Item)
          diagnostics.error("attribute", attribute.span,
                            "attribute '@" + attribute.name +
                                "' applies to functions");
        return true;
      }
      if (attribute.name == "derive") {
        if (site != Site::Declaration) {
          diagnostics.error("attribute", attribute.span,
                            "derive applies to type and enum declarations");
          return true;
        }
        return false;
      }
      if (site == Site::Variant || site == Site::VariantField)
        diagnostics.error("attribute", attribute.span,
                          "attribute '@" + attribute.name +
                              "' is not supported on enum variants");
      else if (site == Site::Import)
        diagnostics.error("feature", attribute.span,
                          "attributes on this declaration require their "
                          "compile-time implementation");
      return false;
    });
    return active;
  }

  void derive(std::size_t index) {
    auto &item = module.products[index];
    std::vector<DeriveRequest> requests;
    std::set<std::string> requested;
    for (const auto &attribute : item.item.attributes)
      if (attribute.name == "derive") {
        auto parsed = deriveRequests(attribute, requested, diagnostics);
        requests.insert(requests.end(), parsed.begin(), parsed.end());
      }
    std::erase_if(item.item.attributes,
                  [](const Attribute &a) { return a.name == "derive"; });
    for (const auto &request : requests)
      item.deriveRequests.emplace_back(request.name, request.span);
    if (!requests.empty())
      generateDerives(module, index, requests, diagnostics, allocate);
  }
};
} // namespace

void expand(Module &module, Diagnostics &diagnostics,
            const Configuration &configuration,
            const SourceAllocator &allocate) {
  Expander(module, diagnostics, configuration, allocate).run();
}
} // namespace mettle::expansion
