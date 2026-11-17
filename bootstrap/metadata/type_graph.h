#pragma once

#include "types/type.h"
#include <functional>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace mettle::metadata {
enum class ValidationMode { Eager, OnDemand };
class InvalidMetadata final : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};
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
TypeGraphExport
exportTypeGraph(const TypeStore &types, std::span<const Type> roots,
                const TypeGraphSymbols &symbols,
                ValidationMode validation = ValidationMode::Eager);
// Demand-loaded records retain their immutable resolver and validate before
// use.
TypeGraphImport
importTypeGraph(TypeStore &types, std::span<const std::uint8_t> bytes,
                const TypeGraphSymbols &symbols,
                ValidationMode validation = ValidationMode::Eager,
                std::shared_ptr<const TypeGraphSymbols> retainedSymbols = {},
                std::shared_ptr<const void> backing = {});
} // namespace mettle::metadata
