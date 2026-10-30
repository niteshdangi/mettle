#include "syntax/migrate.h"
#include "syntax/parser.h"
#include <algorithm>
#include <iterator>

namespace mettle {
namespace {
void typeFingerprint(const TypeSyntax &type, std::string &out);
void nodeFingerprint(const Node &node, std::string &out);

void patternFingerprint(const Pattern &pattern, std::string &out) {
  out += "P(" + std::to_string(static_cast<int>(pattern.kind)) + ' ' +
         pattern.text + ' ' + pattern.field;
  for (const auto &child : pattern.children)
    patternFingerprint(child, out);
  out += ')';
}
void argumentsFingerprint(const std::vector<GenericArgument> &arguments,
                          std::string &out) {
  out += '<';
  for (const auto &argument : arguments) {
    out += argument.binding + '=' + argument.region;
    if (argument.type)
      typeFingerprint(*argument.type, out);
    if (argument.value)
      nodeFingerprint(*argument.value, out);
    out += ',';
  }
  out += '>';
}
void typeFingerprint(const TypeSyntax &type, std::string &out) {
  out += "T(" + std::to_string(static_cast<int>(type.form)) + ' ' + type.view +
         ' ' + type.name;
  for (const auto &source : type.sources)
    out += " from " + source;
  for (const auto &region : type.regions)
    out += " region " + region;
  for (const auto &binder : type.binders)
    out += " for " + binder;
  if (type.nested)
    typeFingerprint(*type.nested, out);
  for (const auto &element : type.elements)
    typeFingerprint(element, out);
  argumentsFingerprint(type.arguments, out);
  if (type.countExpression)
    nodeFingerprint(*type.countExpression, out);
  if (type.callable) {
    const auto &callable = *type.callable;
    out += " callable " + callable.mode + ' ' + callable.abi;
    for (const auto &parameter : callable.parameters) {
      out += parameter.mode + ' ';
      typeFingerprint(parameter.annotation, out);
    }
    typeFingerprint(callable.result, out);
    typeFingerprint(callable.error, out);
  }
  out += ')';
}
// A Name or Field chain is fingerprinted as one dotted-neutral path so that
// `a::b` and `a.b` compare equal; generic argument lists keep source order.
void nodeFingerprint(const Node &node, std::string &out) {
  const Node *root = &node;
  std::vector<const Node *> links;
  while (root->kind == Kind::Field && !root->flag &&
         root->children.size() == 1) {
    links.push_back(root);
    root = root->children[0].get();
  }
  if (root->kind == Kind::Name) {
    // Generic arguments are attached to the path segment they apply to:
    // a `::` Name carries owner arguments for its second-to-last segment
    // and its own arguments for the last, while a dotted chain carries them
    // per link. Empty lists are omitted so both spellings agree.
    std::vector<std::string> segments;
    for (std::size_t begin = 0;;) {
      auto end = root->text.find("::", begin);
      segments.push_back(root->text.substr(begin, end - begin));
      if (end == std::string::npos)
        break;
      begin = end + 2;
    }
    auto attach = [&](std::size_t index,
                      const std::vector<GenericArgument> &arguments) {
      if (!arguments.empty())
        argumentsFingerprint(arguments, segments[index]);
    };
    if (segments.size() >= 2)
      attach(segments.size() - 2, root->ownerGenericArguments);
    else if (!root->ownerGenericArguments.empty())
      argumentsFingerprint(root->ownerGenericArguments, segments.front());
    attach(segments.size() - 1, root->genericArguments);
    for (auto link = links.rbegin(); link != links.rend(); ++link) {
      segments.push_back((*link)->text);
      attach(segments.size() - 1, (*link)->genericArguments);
    }
    out += "N(";
    for (std::size_t index = 0; index < segments.size(); ++index)
      out += (index ? "::" : "") + segments[index];
    typeFingerprint(root->annotation, out);
    out += ' ' + node.name + (node.semicolon ? ";)" : ")");
    return;
  }
  out += "K(" + std::to_string(static_cast<int>(node.kind)) + ' ' + node.text +
         ' ' + node.name + ' ' + node.label + (node.flag ? " 1" : " 0") +
         (node.semicolon ? ";" : "");
  typeFingerprint(node.annotation, out);
  typeFingerprint(node.error, out);
  for (const auto &pattern : node.patterns)
    patternFingerprint(pattern, out);
  for (const auto &parameter : node.parameters) {
    out += parameter.name + ':' + parameter.mode;
    typeFingerprint(parameter.annotation, out);
    if (parameter.pattern)
      patternFingerprint(*parameter.pattern, out);
  }
  argumentsFingerprint(node.ownerGenericArguments, out);
  argumentsFingerprint(node.genericArguments, out);
  for (const auto &child : node.children)
    nodeFingerprint(*child, out);
  out += ')';
}
std::string fingerprint(const Module &module) {
  std::string out;
  for (const auto &function : module.functions) {
    out += "F(" + function.name + ' ' + function.receiver + ' ' +
           function.owner + ' ';
    for (const auto &parameter : function.parameters) {
      out += parameter.name + ':' + parameter.mode + ' ';
      typeFingerprint(parameter.annotation, out);
      if (parameter.pattern)
        patternFingerprint(*parameter.pattern, out);
      if (parameter.defaultValue.get())
        nodeFingerprint(*parameter.defaultValue, out);
    }
    typeFingerprint(function.annotation, out);
    typeFingerprint(function.error, out);
    for (const auto &generic : function.genericParameters) {
      out += generic.name;
      for (const auto &bound : generic.bounds)
        typeFingerprint(bound, out);
    }
    for (const auto &constraint : function.constraints) {
      typeFingerprint(constraint.subject, out);
      for (const auto &bound : constraint.bounds)
        typeFingerprint(bound, out);
      if (constraint.equality)
        typeFingerprint(*constraint.equality, out);
    }
    if (function.body.get())
      nodeFingerprint(*function.body, out);
    out += ")\n";
  }
  for (const auto &product : module.products) {
    out += "D(" + product.name;
    for (const auto &field : product.fields) {
      out += ' ' + field.name;
      typeFingerprint(field.annotation, out);
    }
    for (const auto &variant : product.variants) {
      out += " variant " + variant.name;
      for (const auto &field : variant.fields)
        typeFingerprint(field.annotation, out);
    }
    for (const auto &interface : product.interfaces)
      typeFingerprint(interface, out);
    out += ")\n";
  }
  for (const auto &implementation : module.implementations) {
    out += std::string("I(") + (implementation.negative ? "not " : "") +
           (implementation.unsafeImplementation ? "unsafe " : "") +
           (implementation.shorthand ? "shorthand " : "");
    typeFingerprint(implementation.target, out);
    typeFingerprint(implementation.interface, out);
    for (const auto &associated : implementation.associated) {
      out += associated.name;
      typeFingerprint(associated.value, out);
      typeFingerprint(associated.annotation, out);
    }
    out += ")\n";
  }
  for (const auto &interface : module.interfaces) {
    out += "J(" + interface.name;
    for (const auto &superinterface : interface.superinterfaces)
      typeFingerprint(superinterface, out);
    out += ")\n";
  }
  for (const auto &alias : module.aliases) {
    out += "A(" + alias.name;
    typeFingerprint(alias.target, out);
    out += ")\n";
  }
  for (const auto &item : module.imports) {
    out += "M(";
    for (const auto &component : item.path)
      out += component + '/';
    out += item.alias + (item.glob ? " *" : "");
    for (const auto &name : item.names)
      out += ' ' + name.name + '=' + name.alias;
    out += ")\n";
  }
  for (const auto &entry : module.statics) {
    out += "S(" + entry.name;
    typeFingerprint(entry.annotation, out);
    if (entry.initializer.get())
      nodeFingerprint(*entry.initializer, out);
    out += ")\n";
  }
  return out;
}

struct Edit {
  std::size_t begin, end;
  std::string text;
};

// Token view over the significant tokens (no space, comments or newlines).
class Scan {
public:
  explicit Scan(const std::vector<Token> &raw) : raw(raw) {
    std::vector<char> stack;
    for (std::size_t i = 0; i < raw.size(); ++i) {
      const auto &token = raw[i];
      if (token.kind == TokenKind::Space || token.kind == TokenKind::Comment ||
          token.kind == TokenKind::Newline)
        continue;
      indices.push_back(i);
      // Newlines are suppressed directly inside `(`, `[` and `${}` holes.
      suppressed.push_back(!stack.empty() && stack.back() == 'p');
      if (token.kind == TokenKind::FormatHoleOpen)
        stack.push_back('p');
      else if (token.kind == TokenKind::FormatHoleClose) {
        if (!stack.empty())
          stack.pop_back();
      } else if (token.kind == TokenKind::Symbol) {
        if (token.text == "(" || token.text == "[")
          stack.push_back('p');
        else if (token.text == "{")
          stack.push_back('b');
        else if ((token.text == ")" || token.text == "]" ||
                  token.text == "}") &&
                 !stack.empty())
          stack.pop_back();
      }
    }
  }
  std::size_t size() const { return indices.size(); }
  const Token &at(std::size_t k) const { return raw[indices[k]]; }
  const std::string &text(std::size_t k) const { return at(k).text; }
  bool name(std::size_t k) const {
    return k < size() && (at(k).kind == TokenKind::Word ||
                          at(k).kind == TokenKind::QuotedWord);
  }
  bool newlineBetween(std::size_t a, std::size_t b) const {
    for (auto i = indices[a] + 1; i < indices[b]; ++i)
      if (raw[i].kind == TokenKind::Newline ||
          (raw[i].kind == TokenKind::Comment &&
           raw[i].text.find_first_of("\r\n") != std::string::npos))
        return true;
    return false;
  }
  bool commentBetween(std::size_t a, std::size_t b) const {
    for (auto i = indices[a] + 1; i < indices[b]; ++i)
      if (raw[i].kind == TokenKind::Comment)
        return true;
    return false;
  }
  bool suppressedAt(std::size_t k) const { return suppressed[k]; }

private:
  const std::vector<Token> &raw;
  std::vector<std::size_t> indices;
  std::vector<char> suppressed;
};

// What may follow a generic application (language-grammar section 13.3).
bool genericFollower(const Scan &scan, std::size_t closer) {
  const auto next = closer + 1;
  if (next >= scan.size() || scan.at(next).kind == TokenKind::End ||
      scan.at(next).kind == TokenKind::FormatHoleClose)
    return true;
  if (scan.newlineBetween(closer, next) && !scan.suppressedAt(closer))
    return true;
  const auto &text = scan.text(next);
  return text == "(" || text == "." || text == "::" || text == ")" ||
         text == "]" || text == "}" || text == "," || text == ";";
}
constexpr auto none = static_cast<std::size_t>(-1);
} // namespace

std::optional<Migration> migrate(const Source &source,
                                 Diagnostics &diagnostics) {
  auto before = parse(source, diagnostics);
  if (!diagnostics.empty())
    return std::nullopt;
  Migration result;
  Scan scan(before.tokens);
  const auto count = scan.size();
  std::vector<Edit> edits;
  // `::` tokens that another rule consumed or that must stay as written.
  std::vector<char> settled(count, 0);
  auto skip = [&](std::size_t k, std::string reason) {
    result.skipped.push_back({scan.at(k).span.begin, std::move(reason)});
  };

  // Attribute arguments are opaque tokens interpreted by attribute handlers.
  for (std::size_t k = 0; k + 2 < count; ++k)
    if (scan.text(k) == "@" && scan.name(k + 1) && scan.text(k + 2) == "(") {
      int depth = 0;
      for (auto j = k + 2; j < count; ++j) {
        settled[j] = 1;
        depth += scan.text(j) == "(" ? 1 : scan.text(j) == ")" ? -1 : 0;
        if (!depth)
          break;
      }
    }

  for (const auto &implementation : before.implementations) {
    const auto begin = implementation.span.begin;
    if (!implementation.shorthand && begin < source.text.size() &&
        source.text.compare(begin, 4, "impl") == 0)
      edits.push_back({begin, begin + 4, "extend"});
  }

  // `<T implements I>::Item` becomes `T.(I).Item`.
  for (std::size_t k = 0; k < count; ++k) {
    if (scan.text(k) != "<" && scan.text(k) != "<<")
      continue;
    int depth = 1, nesting = 0;
    std::size_t implementsAt = none, closer = none;
    bool split = false;
    for (auto j = k + 1; j < count && closer == none; ++j) {
      const auto &word = scan.text(j);
      if (scan.at(j).kind == TokenKind::End || word == ";" || word == "{" ||
          word == "}")
        break;
      if (word == "(" || word == "[")
        ++nesting;
      else if (word == ")" || word == "]") {
        if (!nesting)
          break;
        --nesting;
      } else if (nesting)
        continue;
      else if (word == "<")
        ++depth;
      else if (word == "<<")
        depth += 2;
      else if (word == ">") {
        if (--depth == 0)
          closer = j;
      } else if (word == ">>") {
        if (depth < 2)
          break;
        depth -= 2;
        if (depth == 0) {
          closer = j;
          split = true;
        }
      } else if (word == ">=" || word == ">>=" || (word == "," && depth == 1))
        break;
      else if (word == "implements" && depth == 1 && implementsAt == none)
        implementsAt = j;
    }
    if (closer == none || implementsAt == none || closer + 2 >= count ||
        scan.text(closer + 1) != "::" || !scan.name(closer + 2))
      continue;
    const auto member = closer + 2;
    const auto subjectEnd = implementsAt - 1;
    const auto interfaceBegin = implementsAt + 1;
    const auto interfaceEnd = split ? closer : closer - 1;
    settled[closer + 1] = 1;
    bool nested = false;
    for (auto j = k + 1; j <= interfaceEnd; ++j)
      nested |= j != implementsAt && scan.text(j) == "implements";
    static const char *const atoms[] = {
        "[", "(",    "ptr",    "read",   "mut",   "any",    "some", "fn", "for",
        "_", "take", "unsafe", "extern", "async", "pinned", "<",    "<<"};
    const auto &first = scan.text(k + 1);
    const bool atom =
        std::any_of(std::begin(atoms), std::end(atoms),
                    [&](const char *text) { return first == text; });
    if (nested) {
      skip(k, "nested associated projection; run the migration again");
      continue;
    }
    if (atom || interfaceBegin > interfaceEnd || k + 1 > subjectEnd) {
      skip(k, "projection subject is not a path; write T.(I).Item by hand");
      continue;
    }
    if (scan.commentBetween(k, member)) {
      skip(k, "comment inside an associated projection");
      continue;
    }
    const auto open = scan.at(k).span.begin + (scan.text(k) == "<<" ? 1u : 0u);
    const auto &closing = scan.at(closer);
    edits.push_back({open, scan.at(k + 1).span.begin, ""});
    edits.push_back({scan.at(subjectEnd).span.end,
                     scan.at(interfaceBegin).span.begin, ".("});
    edits.push_back(
        {split ? closing.span.begin + 1 : scan.at(interfaceEnd).span.end,
         scan.at(member).span.begin, ")."});
  }

  // `::` becomes `.`; turbofish `::<` drops the separator.
  for (std::size_t k = 0; k < count; ++k) {
    if (scan.text(k) != "::" || settled[k])
      continue;
    auto last = k;
    while (last + 3 < count && scan.name(last + 1) &&
           scan.text(last + 2) == "::" && scan.name(last + 3))
      last += 2;
    if (last + 2 < count && scan.text(last + 2) == "!") {
      skip(k, "machine macro paths keep `::`");
      continue;
    }
    if (k + 1 < count &&
        (scan.text(k + 1) == "<" || scan.text(k + 1) == "<<")) {
      int depth = 0, braces = 0;
      std::size_t closer = none;
      bool mapped = true;
      for (auto j = k + 1; j < count && closer == none && mapped; ++j) {
        const auto &word = scan.text(j);
        if (word == "{")
          ++braces;
        else if (word == "}") {
          if (!braces)
            mapped = false;
          else
            --braces;
        } else if (braces)
          continue;
        else if (word == ";" || scan.at(j).kind == TokenKind::End)
          mapped = false;
        else if (word == ">=" || word == ">>=")
          mapped = false;
        else {
          depth += word == "<" ? 1 : word == "<<" ? 2 : 0;
          depth -= word == ">" ? 1 : word == ">>" ? 2 : 0;
          if (depth < 0)
            mapped = false;
          else if (depth == 0 && (word == ">" || word == ">>"))
            closer = j;
        }
      }
      if (closer == none || !mapped) {
        skip(k, "unbalanced turbofish");
        continue;
      }
      if (!genericFollower(scan, closer)) {
        skip(k, "specialized value before a non-follower: parenthesize it");
        continue;
      }
      edits.push_back({scan.at(k).span.begin, scan.at(k).span.end, ""});
    } else
      edits.push_back({scan.at(k).span.begin, scan.at(k).span.end, "."});
  }

  std::sort(edits.begin(), edits.end(),
            [](const Edit &a, const Edit &b) { return a.begin < b.begin; });
  std::string text;
  std::size_t cursor = 0;
  for (const auto &edit : edits) {
    if (edit.begin < cursor || edit.end < edit.begin ||
        edit.end > source.text.size())
      continue;
    text.append(source.text, cursor, edit.begin - cursor);
    text += edit.text;
    cursor = edit.end;
    ++result.rewrites;
  }
  text.append(source.text, cursor, std::string::npos);
  result.text = std::move(text);

  Diagnostics check;
  Source migrated{source.path, result.text, source.id};
  auto after = parse(migrated, check);
  if (!check.empty()) {
    diagnostics.error("migrate", {},
                      "the migrated source does not parse: " +
                          check.items.front().message);
    return std::nullopt;
  }
  if (fingerprint(before) != fingerprint(after)) {
    diagnostics.error("migrate", {},
                      "the migrated source parses to a different syntax tree; "
                      "no output produced");
    return std::nullopt;
  }
  return result;
}
} // namespace mettle
