#include "semantics/checker.h"
#include <algorithm>
#include <limits>

namespace mettle {
void Checker::admitNative(std::string_view canonical) const {
  const auto &imports = checked.importedDeclarations;
  if (!imports || !imports->catalog)
    return;
  auto &self = *const_cast<Checker *>(this);
  if (auto function = imports->catalog->function(canonical))
    self.names.emplace(std::string(canonical), *function);
  if (auto type = imports->catalog->namedType(canonical)) {
    auto [kind, index] = *type;
    const ImportedDeclarations::TypeTable *table = nullptr;
    Span span;
    switch (kind) {
    case 0:
      table = &imports->products;
      if (index >= module.products.nativeSize())
        throw metadata::InvalidMetadata(
            "native product lookup exceeds its declaration directory");
      span = module.products.header(index).span;
      break;
    case 1:
      table = &imports->aliases;
      if (index >= module.aliases.nativeSize())
        throw metadata::InvalidMetadata(
            "native alias lookup exceeds its declaration directory");
      span = module.aliases.header(index).span;
      self.aliases.emplace(std::string(canonical), index);
      if (index < self.aliasStates.size())
        self.aliasStates[index] = 2;
      break;
    case 2:
      if (index >= module.interfaces.nativeSize())
        throw metadata::InvalidMetadata(
            "native interface lookup exceeds its declaration directory");
      self.interfaceNames.emplace(std::string(canonical), index);
      break;
    default:
      break;
    }
    if (table) {
      auto declaration = imports->findType(span, *table);
      if (!declaration)
        throw metadata::InvalidMetadata(
            "native type has no indexed declaration contract");
      if (declaration->name != canonical)
        throw metadata::InvalidMetadata(
            "native type lookup does not match its declaration");
      self.typeNames.emplace(std::string(canonical), declaration->type);
    }
  }
}
resolution::ModuleId
Checker::nameModule(Span span, std::optional<SyntaxContextPtr> context,
                    bool visibilityOnly) const {
  auto lexical = context ? *context : diagnostics.syntaxContext(span);
  if (!lexical)
    return checked.symbols->moduleOf(span);
  checked.symbols->moduleOf(lexical->definition);
  resolution::ModuleId moduleId = 0;
  const auto &modules = checked.symbols->modules();
  for (const auto &part : lexical->scope) {
    auto found = std::find_if(
        modules.begin(), modules.end(), [&](const auto &candidate) {
          return candidate.parent == moduleId && candidate.name == part;
        });
    if (found == modules.end()) {
      if (visibilityOnly)
        return std::numeric_limits<resolution::ModuleId>::max();
      diagnostics.error("name", span, "macro lexical module is unavailable");
      return 0;
    }
    moduleId = static_cast<resolution::ModuleId>(found - modules.begin());
  }
  return moduleId;
}

resolution::ModuleId Checker::accessModule(const Node &node) const {
  const auto &name = node.kind == Kind::Call && !node.children.empty()
                         ? *node.children[0]
                         : node;
  return nameModule(name.span, name.context);
}

std::string Checker::definitionName(Span span,
                                    std::string_view spelling) const {
  auto canonical = checked.symbols->canonical(span);
  return canonical.empty() ? std::string(spelling) : canonical;
}

const std::vector<const Module::Product *> &
Checker::productsNamed(const std::string &name) const {
  const auto &imports = checked.importedDeclarations;
  if (imports && imports->catalog)
    if (auto declaration = imports->catalog->namedType(name);
        declaration && declaration->first == 0) {
      auto &found = productIndex[name];
      if (found.empty())
        found.push_back(&module.products[declaration->second]);
      return found;
    }
  if (!localProductsIndexed) {
    for (const auto &product : module.products.localHeaders())
      productIndex[definitionName(product.span, product.name)].push_back(
          &product);
    localProductsIndexed = true;
  }
  static const std::vector<const Module::Product *> none;
  auto found = productIndex.find(name);
  if (found != productIndex.end())
    for (auto *&product : found->second)
      product = &module.products[module.products.indexOf(product)];
  return found == productIndex.end() ? none : found->second;
}

std::string Checker::typeName(std::string_view spelling, Span span,
                              std::string_view owner,
                              std::optional<SyntaxContextPtr> context) const {
  auto lexical = context ? *context : diagnostics.syntaxContext(span);
  if (spelling == "Self" && !owner.empty() &&
      (genericEnvironment
           ? nameKey("Self", lexical) ==
                 nameKey("Self", genericEnvironment->declarationSpan)
           : !lexical || !lexical->identity))
    spelling = owner;
  auto resolved = checked.symbols->lookup(nameModule(span, context), spelling,
                                          resolution::Namespace::Type, span);
  if (resolved) {
    admitNative(*resolved);
    return *resolved;
  }
  if (builtinType(spelling) != Type::Unknown)
    return std::string(spelling);
  return {};
}

std::string
Checker::callableName(std::string_view spelling, std::string_view owner,
                      Span span,
                      std::optional<SyntaxContextPtr> lexical) const {
  auto context = nameModule(span, lexical);
  if (auto resolved = checked.symbols->lookup(
          context, spelling, resolution::Namespace::Value, span)) {
    admitNative(*resolved);
    return *resolved;
  }
  if (auto type = typeName(spelling, span, owner, lexical); !type.empty())
    return type;
  auto separator = spelling.rfind("::");
  if (separator == std::string_view::npos)
    return {};
  auto prefix = typeName(spelling.substr(0, separator), span, owner, lexical);
  auto found = typeNames.find(prefix);
  if (found == typeNames.end() || !checked.types->isProduct(found->second))
    return {};
  return checked.symbols
      ->associatedItem(checked.types->product(found->second).name,
                       spelling.substr(separator + 2), context)
      .value_or("");
}

bool Checker::visibleField(Type type, std::size_t field, Span use,
                           std::optional<SyntaxContextPtr> context) {
  auto kind = checked.types->product(type).kind;
  if (kind == AggregateKind::Uninit || kind == AggregateKind::ManualDrop ||
      kind == AggregateKind::UnsafeCell || kind == AggregateKind::Pin ||
      kind == AggregateKind::Atomic || kind == AggregateKind::Cell ||
      kind == AggregateKind::RefCell || kind == AggregateKind::Ref ||
      kind == AggregateKind::RefMut || kind == AggregateKind::VarArgs) {
    error("name", use, "compiler-owned storage fields are private");
    return false;
  }
  if (checked.types->product(type).genericOrigin != Type::Unknown)
    type = checked.types->product(type).genericOrigin;
  const auto &name = checked.types->product(type).name;
  for (const auto *declared : productsNamed(name)) {
    const auto &product = *declared;
    if (product.enumeration || field >= product.fields.size())
      return true;
    if (checked.symbols->accessible(product.fields[field].span,
                                    nameModule(use, context, true)))
      return true;
    error("name", use,
          "private or restricted field '" + product.fields[field].name +
              "' is inaccessible");
    return false;
  }
  return true;
}
} // namespace mettle
