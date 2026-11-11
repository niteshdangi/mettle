#include "expansion/macro_library.h"
#include "support/limits.h"
#include <algorithm>
#include <set>
#include <type_traits>
#include <utility>

namespace mettle::expansion {
namespace {
constexpr std::string_view magic{"MTMACRO\1", 8};

std::uint32_t checksum(std::string_view bytes) {
  std::uint32_t result = UINT32_MAX;
  for (unsigned char byte : bytes) {
    result ^= byte;
    for (unsigned bit = 0; bit < 8; ++bit)
      result = (result >> 1) ^ (0xedb88320u & (0u - (result & 1u)));
  }
  return ~result;
}

template <class Wire, class T> void fields(Wire &wire, T &value) {
  using V = std::remove_const_t<T>;
  if constexpr (std::is_same_v<V, MacroSource>)
    wire(value.identity, value.path, value.bytes);
  else if constexpr (std::is_same_v<V, MacroLocation>)
    wire(value.source, value.begin, value.end);
  else if constexpr (std::is_same_v<V, MacroContext>)
    wire(value.scope, value.definition, value.hygienic);
  else if constexpr (std::is_same_v<V, MacroToken>)
    wire(value.kind, value.text, value.origin, value.space, value.authored,
         value.glued, value.context);
  else if constexpr (std::is_same_v<V, MacroNode>)
    wire(value.kind, value.token, value.name, value.fragment, value.body,
         value.separator, value.repetition);
  else if constexpr (std::is_same_v<V, MacroRule>)
    wire(value.matcher, value.expansion);
  else if constexpr (std::is_same_v<V, MacroDefinition>)
    wire(value.name, value.location, value.scope, value.visibilityBoundary,
         value.publicItem, value.rules);
  else if constexpr (std::is_same_v<V, MacroImport>)
    wire(value.scope, value.path, value.alias, value.name, value.publicItem,
         value.restriction, value.location);
  else if constexpr (std::is_same_v<V, MacroLibrary>)
    wire(value.sources, value.contexts, value.definitions, value.imports,
         value.indexedModules, value.declaredModules);
  else
    static_assert(!sizeof(V), "unsupported macro wire record");
}

class Writer {
public:
  std::string bytes{magic};
  bool good = true;
  template <class... T> void operator()(const T &...values) {
    (value(values), ...);
  }
  void word(std::uint32_t number) {
    for (unsigned shift = 0; shift < 32; shift += 8)
      byte(static_cast<unsigned char>(number >> shift));
  }

private:
  void byte(unsigned char number) {
    if (bytes.size() == limits::sourceBytes)
      good = false;
    if (good)
      bytes += static_cast<char>(number);
  }
  void value(bool flag) { byte(flag ? 1 : 0); }
  void value(char letter) { byte(static_cast<unsigned char>(letter)); }
  void value(std::uint32_t number) { word(number); }
  void value(const std::string &text) {
    word(static_cast<std::uint32_t>(text.size()));
    if (text.size() > limits::sourceBytes - bytes.size())
      good = false;
    if (good)
      bytes += text;
  }
  template <class T> void value(const std::vector<T> &values) {
    word(static_cast<std::uint32_t>(values.size()));
    for (const auto &entry : values) {
      if (!good)
        break;
      value(entry);
    }
  }
  template <class T> void value(const std::optional<T> &entry) {
    value(entry.has_value());
    if (entry)
      value(*entry);
  }
  template <class T> void value(const T &entry) {
    if constexpr (std::is_enum_v<T>)
      byte(static_cast<unsigned char>(entry));
    else
      fields(*this, entry);
  }
};

class Reader {
public:
  explicit Reader(std::string_view input) : bytes(input) {}
  bool good = true;
  template <class... T> void operator()(T &...values) { (value(values), ...); }
  bool done() const { return good && position == bytes.size(); }
  std::uint32_t word() {
    std::uint32_t result = 0;
    for (unsigned shift = 0; shift < 32; shift += 8)
      result |= std::uint32_t{byte()} << shift;
    return result;
  }

private:
  std::string_view bytes;
  std::size_t position = 0, nodes = 0;
  unsigned depth = 0;
  unsigned char byte() {
    if (!good || position == bytes.size()) {
      good = false;
      return 0;
    }
    return static_cast<unsigned char>(bytes[position++]);
  }
  void value(bool &flag) {
    auto encoded = byte();
    good &= encoded <= 1;
    flag = encoded != 0;
  }
  void value(char &letter) { letter = static_cast<char>(byte()); }
  void value(std::uint32_t &number) { number = word(); }
  void value(std::string &text) {
    auto size = word();
    if (!good || size > bytes.size() - position) {
      good = false;
      return;
    }
    text.assign(bytes.substr(position, size));
    position += size;
  }
  template <class T> void value(std::vector<T> &values) {
    auto count = word();
    if (!good || count > limits::tokens || count > bytes.size() - position) {
      good = false;
      return;
    }
    for (std::uint32_t i = 0; i < count && good; ++i) {
      values.emplace_back();
      value(values.back());
    }
  }
  template <class T> void value(std::optional<T> &entry) {
    bool present = false;
    value(present);
    if (good && present) {
      entry.emplace();
      value(*entry);
    }
  }
  template <class T> void value(T &entry) {
    if (!good)
      return;
    if constexpr (std::is_enum_v<T>) {
      entry = static_cast<T>(byte());
    } else if constexpr (std::is_same_v<T, MacroNode>) {
      if (++nodes > limits::tokens || depth >= limits::syntaxDepth) {
        good = false;
        return;
      }
      ++depth;
      fields(*this, entry);
      --depth;
    } else {
      fields(*this, entry);
    }
  }
};

class Validator {
public:
  explicit Validator(const MacroLibrary &library) : library(library) {}
  bool run() {
    if (!count(library.sources) || !count(library.contexts) ||
        !count(library.definitions) || !count(library.imports) ||
        !count(library.indexedModules) || !count(library.declaredModules))
      return false;
    std::set<std::string> identities;
    for (const auto &source : library.sources)
      if (source.identity.empty() || !text(source.identity) ||
          !text(source.path) || !identities.insert(source.identity).second)
        return false;
    for (const auto &context : library.contexts)
      if (!path(context.scope) || context.definition.source == UINT32_MAX ||
          !location(context.definition))
        return false;
    std::set<std::pair<std::vector<std::string>, std::string>> definitions;
    for (const auto &definition : library.definitions) {
      if (definition.name.empty() || !text(definition.name) ||
          isReservedWord(definition.name) ||
          definition.location.source == UINT32_MAX ||
          !location(definition.location) || !path(definition.scope) ||
          !path(definition.visibilityBoundary) || definition.rules.empty() ||
          !count(definition.rules) ||
          definition.visibilityBoundary.size() > definition.scope.size() ||
          !std::equal(definition.visibilityBoundary.begin(),
                      definition.visibilityBoundary.end(),
                      definition.scope.begin()) ||
          !definitions.emplace(definition.scope, definition.name).second)
        return false;
      for (const auto &rule : definition.rules)
        if (!nodes(rule.matcher, true, 0) || !nodes(rule.expansion, false, 0))
          return false;
    }
    for (const auto &import : library.imports)
      if (!path(import.scope) || !path(import.path) || import.path.empty() ||
          import.alias.empty() || import.name.empty() || !text(import.alias) ||
          !text(import.name) || !path(import.restriction) ||
          !location(import.location))
        return false;
    std::set<std::string> indexed;
    for (const auto &module : library.indexedModules)
      if (!text(module) || !indexed.insert(module).second)
        return false;
    for (const auto &module : library.declaredModules)
      if (!path(module))
        return false;
    return true;
  }

private:
  const MacroLibrary &library;
  std::size_t nodeCount = 0;
  template <class T> bool count(const std::vector<T> &values) const {
    return values.size() <= limits::tokens;
  }
  bool text(const std::string &value) const {
    return value.size() <= limits::sourceBytes && !invalidUtf8(value);
  }
  bool path(const std::vector<std::string> &value) const {
    if (!count(value))
      return false;
    for (const auto &part : value)
      if (part.empty() || !text(part))
        return false;
    return true;
  }
  bool location(const MacroLocation &value) const {
    if (value.source == UINT32_MAX)
      return value.begin == 0 && value.end == 0;
    return value.source < library.sources.size() && value.begin <= value.end &&
           value.end <= library.sources[value.source].bytes;
  }
  bool token(const MacroToken &value) const {
    auto kind = static_cast<unsigned>(value.kind);
    return kind <= static_cast<unsigned>(TokenKind::FormatClose) &&
           value.kind != TokenKind::Space && value.kind != TokenKind::Comment &&
           value.kind != TokenKind::End && !value.text.empty() &&
           text(value.text) && value.origin.source != UINT32_MAX &&
           location(value.origin) &&
           (!value.context || *value.context < library.contexts.size());
  }
  bool nodes(const std::vector<MacroNode> &values, bool matcher,
             unsigned depth) {
    if (!count(values) || depth > limits::syntaxDepth)
      return false;
    for (const auto &node : values) {
      if (++nodeCount > limits::tokens || !token(node.token) ||
          !text(node.name) || !text(node.fragment) ||
          (node.separator && !token(*node.separator)))
        return false;
      if (node.kind != MacroNodeKind::Literal &&
          (node.token.kind != TokenKind::Symbol || node.token.text != "$"))
        return false;
      switch (node.kind) {
      case MacroNodeKind::Literal:
        if (!node.name.empty() || !node.fragment.empty() ||
            !node.body.empty() || node.separator)
          return false;
        break;
      case MacroNodeKind::Variable:
        if (node.name.empty() || (matcher && node.fragment.empty()) ||
            (!matcher && !node.fragment.empty()) || !node.body.empty() ||
            node.separator)
          return false;
        break;
      case MacroNodeKind::Repetition:
        if (!node.name.empty() || !node.fragment.empty() ||
            (node.repetition != '*' && node.repetition != '+' &&
             node.repetition != '?') ||
            (node.repetition == '?' && node.separator) ||
            !nodes(node.body, matcher, depth + 1))
          return false;
        if (node.separator &&
            (node.separator->kind == TokenKind::Newline ||
             (node.separator->kind == TokenKind::Symbol &&
              (node.separator->text == "(" || node.separator->text == "[" ||
               node.separator->text == "{" || node.separator->text == ")" ||
               node.separator->text == "]" || node.separator->text == "}"))))
          return false;
        break;
      case MacroNodeKind::Capture:
        if (matcher || !node.separator || !node.name.empty() ||
            !node.fragment.empty() || !node.body.empty() ||
            node.separator->kind != TokenKind::Word)
          return false;
        break;
      default:
        return false;
      }
    }
    return true;
  }
};

void invalid(Diagnostics &diagnostics) {
  diagnostics.error("macro", {}, "invalid compiled macro library");
}
} // namespace

bool validateMacros(const MacroLibrary &library, Diagnostics &diagnostics) {
  if (Validator(library).run())
    return true;
  invalid(diagnostics);
  return false;
}

std::optional<std::string> encodeMacros(const MacroLibrary &library,
                                        Diagnostics &diagnostics) {
  if (!validateMacros(library, diagnostics))
    return std::nullopt;
  Writer writer;
  writer(library);
  writer.word(checksum(writer.bytes));
  if (!writer.good) {
    diagnostics.error("limit", {},
                      "compiled macro library exceeds source limit");
    return std::nullopt;
  }
  return std::move(writer.bytes);
}

std::optional<MacroLibrary> decodeMacros(std::string_view bytes,
                                         Diagnostics &diagnostics) {
  if (bytes.size() < magic.size() + 4 || bytes.size() > limits::sourceBytes ||
      !bytes.starts_with(magic)) {
    invalid(diagnostics);
    return std::nullopt;
  }
  auto payload = bytes.substr(0, bytes.size() - 4);
  Reader footer(bytes.substr(bytes.size() - 4));
  if (footer.word() != checksum(payload)) {
    invalid(diagnostics);
    return std::nullopt;
  }
  Reader reader(payload.substr(magic.size()));
  MacroLibrary library;
  reader(library);
  if (!reader.done()) {
    invalid(diagnostics);
    return std::nullopt;
  }
  if (!validateMacros(library, diagnostics))
    return std::nullopt;
  return library;
}
} // namespace mettle::expansion
