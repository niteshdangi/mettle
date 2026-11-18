#pragma once

#include "consteval/evaluate.h"
#include "metadata/references.h"
#include "semantics/checked.h"
#include <array>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <span>
#include <string_view>
#include <tuple>

namespace mettle {
class TypeProjection;
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
  struct Dispatch {
    Type self, interfaceType;
    int method;
  };
  Span span{};
  NodeOwner syntax;
  std::unordered_map<const Node *, NodeFacts> facts;
  std::unordered_map<const Node *, StaticConstant> constants;
  std::vector<Dispatch> dispatches;
  std::function<void(CheckedExpression &)> load;
  void materialize() {
    if (load)
      std::call_once(loaded, [&] { load(*this); });
  }

private:
  std::once_flag loaded;
};
struct ImportedFunction {
  Span span;
  std::string symbolName;
  struct Contract {
    FunctionFacts facts;
    DeclarationEnvironment generics;
    DeclarationRegions regions;
  };
  std::shared_ptr<CheckedExpression> body;
  std::vector<std::shared_ptr<CheckedExpression>> defaults;
  struct Evaluator {
    std::once_flag once;
    evaluation::CheckedFunction function;
  };
  std::shared_ptr<Evaluator> evaluator;
  void prepareEvaluation() {
    evaluator = body ? std::make_shared<Evaluator>() : nullptr;
  }
  const evaluation::CheckedFunction &
  checkedFunction(const TypeStore &types) const;
  bool unsafeFunction = false;
  bool hasBody = false;
  struct SignatureIndex {
    Type result = Type::Unknown, error = Type::Unknown;
    std::vector<Type> parameters;
    std::string externalName;
    bool operator==(const SignatureIndex &) const = default;
  } signature;
  struct Deferred {
    std::once_flag once;
    std::function<std::shared_ptr<const ImportedFunction>()> load;
    std::shared_ptr<const ImportedFunction> value;
    const ImportedFunction &materialize();
  };
  std::shared_ptr<Deferred> deferred;
  const ImportedFunction &materialize() const;
  const Contract &contract() const;
  Contract &contract();
  void defer(SignatureIndex index,
             std::function<std::shared_ptr<const ImportedFunction>()> load);
  Type resultType() const {
    return deferred ? signature.result : contract().facts.result;
  }
  Type errorType() const {
    return deferred ? signature.error : contract().facts.error;
  }
  std::size_t localCount() const {
    return deferred ? signature.parameters.size()
                    : contract().facts.locals.size();
  }
  Type parameterType(std::size_t index) const {
    return deferred ? signature.parameters.at(index)
                    : contract().facts.locals.at(index).type;
  }
  std::string_view externalSymbol() const {
    return deferred ? signature.externalName : contract().facts.externalName;
  }

private:
  std::shared_ptr<Contract> owned;
};
struct ImportedTypeDeclaration {
  struct Deferred {
    std::once_flag once;
    std::function<DeclarationEnvironment()> load;
    std::optional<DeclarationEnvironment> value;
  };
  Span span;
  std::string name;
  Type type = Type::Unknown;
  DeclarationEnvironment generics;
  std::shared_ptr<Deferred> deferred;
  const DeclarationEnvironment &environment() const;
};
struct ImportedInherentConstant {
  Span implementation, declaration;
  std::string name;
  Type target = Type::Unknown, declaredType = Type::Unknown,
       value = Type::Unknown;
  std::optional<StaticConstant> materialized{};
  std::shared_ptr<CheckedExpression> initializer{};
};
struct ImportedClosure {
  Span span;
  std::string definition;
  FunctionFacts facts;
  Type type = Type::Unknown;
};
struct ImportedFunctionRecords {
  struct Header {
    Span span;
    Type result = Type::Unknown, error = Type::Unknown;
    std::size_t parameters = 0, count = 0;
    bool hasBody = false;
    std::string externalName;
    std::string symbolName;
  };
  std::vector<Header> headers;
  std::vector<Type> parameters;
  std::vector<bool> defaults;
  TypeRecords<ImportedFunction, true> functions;
};
class ImportedFunctionReference {
public:
  ImportedFunctionReference() = default;
  ImportedFunctionReference(std::shared_ptr<const ImportedFunction> value)
      : value(std::move(value)) {}
  ImportedFunctionReference(std::shared_ptr<ImportedFunction> value)
      : value(std::move(value)) {}
  ImportedFunctionReference(
      std::shared_ptr<const ImportedFunctionRecords> records, std::size_t index)
      : records(std::move(records)), index(index) {}
  const ImportedFunction *get() const {
    return records ? &records->functions.at(index) : value.get();
  }
  const ImportedFunction *operator->() const { return get(); }
  const ImportedFunction &operator*() const { return *get(); }
  explicit operator bool() const { return bool(records) || bool(value); }
  operator std::shared_ptr<const ImportedFunction>() const {
    return records ? records->functions.retain(index) : value;
  }
  Span span() const {
    return records ? records->headers[index].span : value->span;
  }
  Type resultType() const {
    return records ? records->headers[index].result : value->resultType();
  }
  Type errorType() const {
    return records ? records->headers[index].error : value->errorType();
  }
  std::size_t parameterCount() const {
    return records ? records->headers[index].count : value->localCount();
  }
  Type parameterType(std::size_t parameter) const {
    if (parameter >= parameterCount())
      throw std::out_of_range("checked parameter index");
    return records ? records->parameters.at(records->headers[index].parameters +
                                            parameter)
                   : value->parameterType(parameter);
  }
  std::size_t defaultCount() const {
    return records ? records->headers[index].count : value->defaults.size();
  }
  bool hasDefault(std::size_t parameter) const {
    if (parameter >= defaultCount())
      throw std::out_of_range("checked default index");
    return records ? records->defaults.at(records->headers[index].parameters +
                                          parameter)
                   : bool(value->defaults.at(parameter));
  }
  bool hasBody() const {
    return records ? records->headers[index].hasBody : value->hasBody;
  }
  std::string_view externalSymbol() const {
    return records ? records->headers[index].externalName
                   : value->externalSymbol();
  }
  bool isMaterialized() const {
    return !records || records->functions.isMaterialized(index);
  }
  std::string_view symbolName() const {
    return records ? records->headers[index].symbolName : value->symbolName;
  }

private:
  std::shared_ptr<const ImportedFunction> value;
  std::shared_ptr<const ImportedFunctionRecords> records;
  std::size_t index = 0;
};
struct ImportedConstructors {
  struct Header {
    std::uint32_t function = 0;
    Type origin = Type::Unknown;
  };
  std::vector<Header> headers;
  interfaces::DatabaseRecords<interfaces::Implementation> applicability;
};
template <class T> class ImportedDeclarationTable {
  using Storage = std::map<std::uint32_t, T>;

public:
  using const_iterator = typename Storage::const_iterator;
  using Loader = std::function<T(std::uint32_t)>;
  void mountIndexed(std::size_t count, Loader load) {
    nativeCount = count;
    loader = std::move(load);
  }
  std::size_t nativeSize() const { return nativeCount; }
  bool contains(std::uint32_t index) const {
    return index < nativeCount || records.contains(index);
  }
  const_iterator find(std::uint32_t index) const {
    if (index < nativeCount && !records.contains(index))
      records.emplace(index, loader(index));
    return records.find(index);
  }
  const T &at(std::uint32_t index) const {
    auto found = find(index);
    if (found == end())
      throw std::out_of_range("imported declaration ID");
    return found->second;
  }
  template <class... Args> auto emplace(std::uint32_t index, Args &&...args) {
    return records.emplace(index, std::forward<Args>(args)...);
  }
  template <class Value>
  auto insert_or_assign(std::uint32_t index, Value &&value) {
    return records.insert_or_assign(index, std::forward<Value>(value));
  }
  void erase(std::uint32_t index) { records.erase(index); }
  const_iterator begin() const { return records.begin(); }
  const_iterator end() const { return records.end(); }
  std::size_t size() const {
    return nativeCount + static_cast<std::size_t>(std::distance(
                             records.lower_bound(nativeCount), records.end()));
  }
  bool empty() const { return size() == 0; }
  std::size_t admittedSize() const { return records.size(); }

private:
  std::size_t nativeCount = 0;
  Loader loader;
  mutable Storage records;
};
using ImportedFunctionTable =
    ImportedDeclarationTable<ImportedFunctionReference>;
class LibraryDeclarationIndex;
struct ImportedDeclarations {
  using TypeTable =
      TypeRecords<std::shared_ptr<const ImportedTypeDeclaration>, true>;
  using ConstantTable = TypeRecords<ImportedInherentConstant, true>;
  ImportedFunctionTable functions;
  std::shared_ptr<const LibraryDeclarationIndex> catalog;
  std::array<std::size_t, 5> nativeTypeCounts{};
  ImportedDeclarationTable<StaticFacts> statics;
  std::map<std::uint32_t, ImportedClosure> closures;
  TypeTable products, aliases, interfaces, implementations, associated;
  ConstantTable inherentConstants;
  std::size_t nativeConstantCount = 0;
  std::vector<std::shared_ptr<const ImportedConstructors>> constructorGroups;
  interfaces::Database checkingDatabase, database;
  std::shared_ptr<const TypeStore> types;
  struct Index {
    struct FunctionBinding {
      std::shared_ptr<const Function> declaration;
      ImportedFunctionReference contract;
    };
    struct Constant {
      std::size_t implementation = 0, declaration = 0;
      std::shared_ptr<const Module::Implementation> owner;
    };
    std::vector<FunctionBinding> functions;
    std::unordered_map<std::size_t, std::shared_ptr<const Function>>
        materializedFunctions;
    OverlayMap<std::string, std::size_t> functionNames;
    std::map<std::string, std::size_t> constructorOrdinals;
    std::vector<std::shared_ptr<const Module::Implementation>>
        implementationHeaders;
    std::vector<std::string> interfaceNames;
    std::vector<std::shared_ptr<const Module::Alias>> aliasHeaders;
    std::vector<std::optional<Type>> aliasTypes;
    std::vector<std::shared_ptr<const Module::Alias>> aliases;
    std::vector<Constant> constants;
    std::unordered_map<const CheckedExpression *,
                       std::shared_ptr<const CheckedExpression>>
        expressions;
    std::unordered_map<const Node *, const CheckedExpression *> nodes;
    std::unordered_map<const TypeSyntax *, Type> annotations;
    mutable std::mutex annotationMutex;
    std::vector<std::tuple<SourceId, std::size_t, std::size_t>> spans;
  };
  std::shared_ptr<const Index> index;
  std::string indexDeclarations(const Module *module);
  void indexTypes();
  std::shared_ptr<const ImportedTypeDeclaration>
  findType(Span span, const TypeTable &items) const;

private:
  std::array<const TypeTable *, 5> typeTables() const;
  std::array<std::vector<std::pair<
                 std::tuple<SourceId, std::size_t, std::size_t>, std::size_t>>,
             5>
      typeIndices;
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
class LibraryDeclarationIndex : public NativeDeclarationIndex {
public:
  virtual std::optional<DeclarationSymbolIdentity>
  symbol(metadata::SymbolKind kind, std::uint32_t index) const = 0;
  virtual std::optional<std::uint32_t>
  symbol(metadata::SymbolKind kind, std::string_view identity) const = 0;
  virtual std::size_t symbolCount(metadata::SymbolKind kind) const = 0;
  virtual std::size_t defaultCount() const = 0;
  virtual std::pair<std::uint32_t, std::uint32_t>
  defaultAt(std::size_t ordinal) const = 0;
  virtual std::optional<std::size_t>
  defaultOrdinal(std::uint32_t function, std::uint32_t parameter) const = 0;
  virtual std::optional<std::size_t> typeOrdinal(std::size_t kind,
                                                 Span span) const = 0;
  virtual std::optional<std::uint32_t>
  function(std::string_view canonical) const = 0;
  virtual std::optional<std::string>
  functionName(std::uint32_t index) const = 0;
  virtual std::optional<std::pair<std::size_t, std::size_t>>
  namedType(std::string_view canonical) const = 0;
  virtual std::vector<std::uint32_t> methods(std::string_view name) const = 0;
  virtual std::size_t constructorCount() const = 0;
  virtual bool constructor(std::uint32_t function) const = 0;
  virtual std::optional<std::uint32_t>
  namedStatic(std::string_view canonical) const = 0;
  virtual std::vector<std::uint32_t>
  externalStatics(std::string_view symbol) const = 0;
  virtual std::vector<std::uint32_t>
  externalFunctions(std::string_view symbol) const = 0;
  virtual std::optional<std::uint32_t>
  destructor(std::string_view owner) const = 0;
  virtual std::optional<std::uint32_t>
  namedConstant(std::string_view canonical) const = 0;
  virtual std::optional<std::pair<std::size_t, std::size_t>>
  constantOwner(std::uint32_t ordinal) const = 0;
  virtual bool constantMember(std::string_view name) const = 0;
  virtual std::size_t typeCount(std::size_t category) const = 0;
  virtual std::size_t constantCount() const = 0;
  virtual std::size_t associatedCount(std::size_t implementation) const = 0;
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
  std::shared_ptr<const LibraryDeclarationIndex> index;
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
struct DeclarationPayloadLayout {
  struct Payload {
    std::size_t offset, size;
  };
  std::vector<Payload> payloads;
  std::string error;
  explicit operator bool() const { return error.empty(); }
};
DeclarationPayloadLayout
declarationPayloadLayout(std::span<const std::uint8_t> bytes);
struct DeclarationQueryInputs {
  std::vector<std::uint8_t> context;
  std::map<std::size_t, std::vector<std::uint8_t>> bodies;
  std::string error;
};
DeclarationQueryInputs
declarationQueryInputs(const Module &module,
                       const ImportedDeclarations *native);
std::shared_ptr<const ImportedDeclarations> retainQueryDeclarations(
    const CheckedModule &module, const ImportedDeclarations *native,
    std::span<const std::size_t> functions, TypeProjection &projection,
    const std::function<bool(Type)> &reusableType = {});
LibraryDeclarationExport
exportLibraryDeclarations(const CheckedModule &module,
                          const metadata::EncodeReferences &references,
                          std::span<const SourceId> omitImportSources = {});
LibraryHeaderImport decodeLibraryHeader(
    std::span<const std::uint8_t> bytes,
    const metadata::DecodeReferences &references,
    std::shared_ptr<const void> backing = nullptr,
    metadata::ValidationMode validation = metadata::ValidationMode::Eager);
LibraryHeaderImport copyLibraryHeader(const LibraryHeaderImport &header);
LibraryDeclarationImport importLibraryDeclarations(
    std::span<const std::uint8_t> bytes, std::shared_ptr<TypeStore> types,
    const metadata::DecodeReferences &references,
    const Module *module = nullptr,
    std::shared_ptr<const void> backing = nullptr,
    std::shared_ptr<const metadata::DecodeReferences> retainedReferences =
        nullptr,
    metadata::ValidationMode validation = metadata::ValidationMode::Eager,
    std::span<const std::string_view> functionNames = {},
    std::function<bool(std::size_t, std::span<const std::uint8_t>)>
        verifyPayload = {},
    std::shared_ptr<const LibraryDeclarationIndex> catalog = nullptr);
} // namespace mettle
