#include "expansion/detail.h"
#include <set>

namespace mettle::expansion {
bool knownAttribute(const std::string &name) {
  static const std::set<std::string> names{
      "cfg",           "derive",      "layout",       "align",
      "packed",        "export_name", "link_name",    "link",
      "link_section",  "used",        "target_feature", "naked",
      "fast_math",     "pinned",      "nonexhaustive", "inline",
      "cold",          "deprecated",  "must_use",     "track_caller",
      "test",          "ignore",      "should_panic", "global_allocator",
      "panic_handler", "no_std",      "no_main",      "doc",
      "allow",         "warn",        "deny",         "forbid",
      "expect"};
  return names.contains(name);
}

namespace {
class Evaluator {
public:
  Evaluator(const Attribute &attribute, const Configuration &configuration,
            Diagnostics &diagnostics)
      : attribute(attribute), configuration(configuration),
        diagnostics(diagnostics) {}

  bool run() {
    if (!attribute.parenthesized || attribute.arguments.empty())
      return fail(attribute.span, "cfg requires one predicate");
    auto value = predicate();
    if (position < attribute.arguments.size() && !failed)
      fail(attribute.arguments[position].span,
           "unexpected tokens after the cfg predicate; combine predicates "
           "with all(...) or any(...)");
    return !failed && value;
  }

private:
  const Attribute &attribute;
  const Configuration &configuration;
  Diagnostics &diagnostics;
  std::size_t position = 0;
  bool failed = false;

  bool fail(Span span, std::string message) {
    if (!failed)
      diagnostics.error("attribute", span, std::move(message));
    failed = true;
    return false;
  }
  const Token *peek(std::size_t look = 0) const {
    return position + look < attribute.arguments.size()
               ? &attribute.arguments[position + look]
               : nullptr;
  }
  bool symbol(const char *text, std::size_t look = 0) const {
    auto token = peek(look);
    return token && token->kind == TokenKind::Symbol && token->text == text;
  }
  Span here() const {
    return peek() ? peek()->span : attribute.span;
  }

  // `all`, `any` and `not` evaluate every operand, so an unknown predicate is
  // diagnosed even where the combinator's result is already decided.
  bool predicate() {
    auto token = peek();
    if (!token || token->kind != TokenKind::Word)
      return fail(here(), "expected a cfg predicate");
    auto name = token->text;
    auto span = token->span;
    if (name == "true" || name == "false") {
      ++position;
      return name == "true";
    }
    if (symbol("(", 1)) {
      if (name != "all" && name != "any" && name != "not")
        return fail(span, "unknown cfg predicate '" + name + "'");
      position += 2;
      std::vector<bool> operands;
      while (!symbol(")")) {
        if (failed || !peek())
          return fail(here(), "unterminated cfg predicate");
        operands.push_back(predicate());
        if (failed)
          return false;
        if (symbol(","))
          ++position;
        else if (!symbol(")"))
          return fail(here(), "expected ',' or ')' in the cfg predicate");
      }
      ++position;
      if (name == "not") {
        if (operands.size() != 1)
          return fail(span, "not(...) takes exactly one predicate");
        return !operands.front();
      }
      bool all = true, any = false;
      for (bool value : operands) {
        all &= value;
        any |= value;
      }
      return name == "all" ? all : any;
    }
    static const std::set<std::string> keys{
        "target_os",     "target_arch",   "target_family",
        "target_endian", "target_pointer_width", "target_feature",
        "feature"};
    if (!keys.contains(name))
      return fail(span, "unknown cfg predicate '" + name + "'");
    ++position;
    if (!symbol("="))
      return fail(span, "cfg predicate '" + name + "' requires = \"value\"");
    ++position;
    auto value = peek();
    if (!value || value->kind != TokenKind::Text)
      return fail(here(), "cfg predicate '" + name +
                              "' requires a constant text value");
    ++position;
    auto text = value->text.substr(1, value->text.size() - 2);
    if (name == "target_os")
      return !configuration.os.empty() && text == configuration.os;
    if (name == "target_arch")
      return !configuration.arch.empty() && text == configuration.arch;
    if (name == "target_family")
      return !configuration.family.empty() && text == configuration.family;
    if (name == "target_endian")
      return !configuration.endian.empty() && text == configuration.endian;
    if (name == "target_pointer_width")
      return configuration.pointerWidth != 0 &&
             text == std::to_string(configuration.pointerWidth);
    if (name == "target_feature")
      return configuration.targetFeatures.contains(text);
    return configuration.features.contains(text);
  }
};
} // namespace

bool evaluateCfg(const Attribute &attribute,
                 const Configuration &configuration,
                 Diagnostics &diagnostics) {
  return Evaluator(attribute, configuration, diagnostics).run();
}
} // namespace mettle::expansion
