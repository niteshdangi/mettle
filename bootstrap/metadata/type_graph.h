#pragma once

#include "types/type.h"
#include <functional>
#include <optional>
#include <span>
#include <string>
#include <vector>

namespace mettle::metadata {
struct DefinitionIdentity {
  std::string package;
  std::string definition;
  std::optional<std::uint32_t> parameterOrdinal;
  auto operator<=>(const DefinitionIdentity &) const = default;
};
enum class SymbolKind { Function, Interface, Package, Closure, Static };
struct TypeGraphSymbols {
  std::function<std::optional<DefinitionIdentity>(Type)> definition;
  std::function<std::optional<Type>(const DefinitionIdentity &)>
      lookupDefinition;
  std::function<std::optional<std::string>(SymbolKind, std::uint32_t)> symbol;
  std::function<std::optional<std::uint32_t>(SymbolKind, std::string_view)>
      resolve;
};
struct TypeGraphExport {
  std::vector<std::uint8_t> bytes;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};
struct ImportedDefinition {
  DefinitionIdentity identity;
  Type type;
};
struct TypeGraphImport {
  std::vector<Type> roots;
  std::vector<ImportedDefinition> definitions;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};
// Archive references are local to this payload, never cross-build identities.
TypeGraphExport exportTypeGraph(const TypeStore &types,
                                std::span<const Type> roots,
                                const TypeGraphSymbols &symbols);
// Only a fully validated candidate replaces types; callbacks do not mutate it.
TypeGraphImport importTypeGraph(TypeStore &types,
                                std::span<const std::uint8_t> bytes,
                                const TypeGraphSymbols &symbols);
} // namespace mettle::metadata
