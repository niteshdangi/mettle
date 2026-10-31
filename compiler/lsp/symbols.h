#pragma once

#include "syntax/token.h"
#include <cstddef>
#include <optional>
#include <string>
#include <vector>

namespace mettle::lsp {
enum class SymbolKind {
  Function,
  Type,
  Enumeration,
  Interface,
  Union,
  Alias,
  Static,
  Constant,
  Module,
  Implementation,
  Field,
  Variant,
  Local,
  Parameter
};

struct Declaration {
  std::string name, signature;
  SymbolKind kind = SymbolKind::Function;
  // Byte offsets: the name, and the whole declaration with its modifiers.
  std::size_t nameBegin = 0, nameEnd = 0, begin = 0, end = 0;
  // The enclosing item whose body declares this one, or -1.
  int parent = -1;
  // Locals and parameters: the region where the name is visible.
  std::size_t scopeBegin = 0, scopeEnd = 0;
  // A parameter's function.
  int owner = -1;
  bool scoped() const {
    return kind == SymbolKind::Local || kind == SymbolKind::Parameter;
  }
};

enum class Role {
  // The name token of a declaration.
  Declaration,
  // A plain use: resolved through locals, then items.
  Lexical,
  // After `.`, `?.` or `::`.
  Member,
  // `name:` in an argument list or field initializer; never a reference.
  Label
};

struct Occurrence {
  std::size_t token = 0, begin = 0, end = 0;
  std::string name;
  Role role = Role::Lexical;
  // Declaration: the declaration it names. Lexical: the visible local or
  // parameter it refers to, or -1 when it refers to an item.
  int declaration = -1;
};

struct CallContext {
  const Occurrence *callee = nullptr;
  std::size_t activeParameter = 0;
};

// A lexical view of one document built from its token stream alone, so it
// exists for incomplete or invalid source. It finds item, member, parameter and
// local declarations (with their scopes) and every identifier occurrence. It
// does not type-check: `x.name` is a member use of any declaration `name`, and
// pattern bindings of `match` arms and closures are not tracked.
class SymbolIndex {
public:
  explicit SymbolIndex(const std::string &text);
  const std::vector<Declaration> &declarations() const { return items; }
  const std::vector<Occurrence> &occurrences() const { return uses; }
  void setFunctionResult(Span functionSpan, const std::string &name,
                         const std::string &result);
  void addBinding(std::string name, Span span, std::size_t scopeBegin,
                  std::size_t scopeEnd, int parent = -1);
  void bindOccurrence(std::size_t offset, int declaration);
  // The occurrence whose identifier contains or ends at `offset`.
  const Occurrence *occurrenceAt(std::size_t offset) const;
  std::optional<CallContext> callAt(std::size_t offset) const;
  // The `name:` labels in the argument list directly after `callee`.
  std::vector<const Occurrence *> argumentLabels(const Occurrence &callee,
                                                 const std::string &name) const;

private:
  std::vector<Token> tokens;
  std::vector<std::size_t> match;
  std::vector<Declaration> items;
  std::vector<Occurrence> uses;
  std::vector<int> byToken;
  friend class Builder;
};
} // namespace mettle::lsp
