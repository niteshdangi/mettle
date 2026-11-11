#pragma once

#include "consteval/evaluate.h"
#include "metadata/references.h"
#include "semantics/checked.h"
#include <map>
#include <memory>
#include <span>

namespace mettle {
struct DeclarationEnvironment {
  std::map<std::pair<std::string, std::uint64_t>, Type> names;
  std::map<Type, std::vector<TypeSyntax>> bounds;
  std::vector<Type> parameters;
  std::map<Type, Type> defaults;
  std::vector<TypeBinding> equalities;
  Span declarationSpan{};
};
struct DeclarationRegions {
  std::map<std::pair<std::string, std::uint64_t>, RegionId> names;
  std::vector<RegionId> parameters;
  std::vector<RegionRequirement> assumptions;
};
struct CheckedExpression {
  NodeOwner syntax;
  std::unordered_map<const Node *, NodeFacts> facts;
  std::unordered_map<const Node *, StaticConstant> constants;
};
struct ImportedFunction {
  Span span;
  FunctionFacts facts;
  DeclarationEnvironment generics;
  DeclarationRegions regions;
  std::shared_ptr<CheckedExpression> body;
  std::vector<std::shared_ptr<CheckedExpression>> defaults;
  evaluation::CheckedFunction evaluation;
  bool unsafeFunction = false;
  bool hasBody = false;
};
struct ImportedTypeDeclaration {
  Span span;
  std::string name;
  Type type = Type::Unknown;
  DeclarationEnvironment generics;
};
struct ImportedInherentConstant {
  Span implementation, declaration;
  std::string name;
  Type target = Type::Unknown, declaredType = Type::Unknown,
       value = Type::Unknown;
  std::optional<StaticConstant> materialized{};
};
struct ImportedClosure {
  Span span;
  std::string definition;
  FunctionFacts facts;
  Type type = Type::Unknown;
};
struct ImportedDeclarations {
  std::map<std::uint32_t, ImportedFunction> functions;
  std::map<std::uint32_t, StaticFacts> statics;
  std::map<std::uint32_t, ImportedClosure> closures;
  std::vector<ImportedTypeDeclaration> products, aliases, interfaces,
      implementations, associated;
  std::vector<ImportedInherentConstant> inherentConstants;
  interfaces::Database checkingDatabase, database;
  std::shared_ptr<TypeStore> types;
};
struct DeclarationTypeIdentity {
  Type type = Type::Unknown;
  Span span;
  std::string definition;
  std::optional<std::uint32_t> parameterOrdinal;
};
struct DeclarationSymbolIdentity {
  metadata::SymbolKind kind = metadata::SymbolKind::Function;
  std::uint32_t index = 0;
  Span span;
  std::string definition;
};
struct DeclarationInventory {
  std::vector<DeclarationTypeIdentity> types;
  std::vector<DeclarationSymbolIdentity> symbols;
};
DeclarationInventory declarationInventory(const CheckedModule &module);
struct LibraryDeclarationExport {
  std::vector<std::uint8_t> header, contracts;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};
struct LibraryHeaderImport {
  std::optional<Module> module;
  std::vector<DeclarationSymbolIdentity> symbols;
  struct TypeIdentity {
    std::uint32_t reference = 0;
    Span span;
    std::string definition;
    std::optional<std::uint32_t> parameterOrdinal;
  };
  std::vector<TypeIdentity> types;
  std::string error;
  explicit operator bool() const { return module.has_value(); }
};
struct LibraryDeclarationImport {
  std::shared_ptr<const ImportedDeclarations> declarations;
  std::string error;
  explicit operator bool() const { return bool(declarations); }
};
LibraryDeclarationExport
exportLibraryDeclarations(const CheckedModule &module,
                          const metadata::EncodeReferences &references,
                          std::span<const SourceId> omitImportSources = {});
LibraryHeaderImport
decodeLibraryHeader(std::span<const std::uint8_t> bytes,
                    const metadata::DecodeReferences &references);
LibraryDeclarationImport
importLibraryDeclarations(std::span<const std::uint8_t> bytes,
                          std::shared_ptr<TypeStore> types,
                          const metadata::DecodeReferences &references);
} // namespace mettle
