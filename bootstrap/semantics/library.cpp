#include "semantics/library.h"
#include "support/limits.h"
#include "types/layout.h"
#include <algorithm>
#include <limits>
#include <type_traits>

namespace mettle {
namespace {
struct Hygiene {
  std::map<std::uint64_t, std::uint64_t> binders;
  std::map<std::uint64_t, SyntaxContextPtr> contexts;
};
class Archive {
public:
  explicit Archive(
      const metadata::EncodeReferences &references, TypeStore &types,
      std::shared_ptr<Hygiene> hygiene = std::make_shared<Hygiene>())
      : types(&types), encode(&references), hygiene(std::move(hygiene)) {}
  Archive(std::span<const std::uint8_t> input,
          const metadata::DecodeReferences &references, TypeStore *types)
      : types(types), input(input), decode(&references) {}
  bool reading() const { return decode != nullptr; }
  std::shared_ptr<Hygiene> hygieneState() const { return hygiene; }
  bool good() const { return error.empty(); }
  void fail(std::string message) {
    if (error.empty())
      error = std::move(message);
  }
  template <typename... T> void operator()(T &...values) {
    (value(values), ...);
  }
  template <typename T> void value(const T &item) {
    value(const_cast<T &>(item));
  }
  template <typename T> void value(T &item) {
    if (!good())
      return;
    if constexpr (std::is_integral_v<T>) {
      std::uint64_t bits = static_cast<std::uint64_t>(item);
      if (reading()) {
        bits = 0;
        if (input.size() - offset < 8) {
          fail("truncated declaration integer");
          return;
        }
        for (unsigned i = 0; i != 8; ++i)
          bits |= std::uint64_t(input[offset++]) << (8 * i);
        if constexpr (std::is_same_v<T, bool>) {
          if (bits > 1)
            fail("invalid declaration boolean");
        } else if constexpr (std::is_unsigned_v<T>) {
          if (bits > std::numeric_limits<T>::max())
            fail("declaration integer exceeds its representation");
        } else if (static_cast<std::int64_t>(bits) <
                       std::numeric_limits<T>::min() ||
                   static_cast<std::int64_t>(bits) >
                       std::numeric_limits<T>::max())
          fail("declaration integer exceeds its representation");
        item = static_cast<T>(bits);
      } else {
        for (unsigned i = 0; i != 8; ++i)
          output.push_back(static_cast<std::uint8_t>(bits >> (8 * i)));
      }
    } else if constexpr (std::is_enum_v<T>) {
      auto bits = static_cast<unsigned>(item);
      value(bits);
      if (reading()) {
        if (bits > maximum(static_cast<T *>(nullptr)))
          fail("invalid declaration enumeration");
        item = static_cast<T>(bits);
      }
    } else
      record(item);
  }
  void value(std::string &text) {
    std::uint64_t size = text.size();
    value(size);
    if (!good())
      return;
    if (reading()) {
      if (size > input.size() - offset) {
        fail("truncated declaration string");
        return;
      }
      text.assign(reinterpret_cast<const char *>(input.data() + offset),
                  static_cast<std::size_t>(size));
      offset += static_cast<std::size_t>(size);
    } else
      output.insert(output.end(), text.begin(), text.end());
  }
  template <typename T> void value(std::vector<T> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > (input.size() - offset) / 8) {
        fail("declaration collection exceeds its payload");
        return;
      }
      items.resize(static_cast<std::size_t>(count));
    }
    for (auto &item : items)
      value(item);
  }
  void value(std::vector<bool> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > (input.size() - offset) / 8) {
        fail("declaration collection exceeds its payload");
        return;
      }
      items.resize(static_cast<std::size_t>(count));
    }
    for (std::size_t i = 0; i < items.size(); ++i) {
      bool item = items[i];
      value(item);
      if (reading())
        items[i] = item;
    }
  }
  template <typename T, std::size_t N> void value(std::array<T, N> &items) {
    for (auto &item : items)
      value(item);
  }
  template <typename T, typename U> void value(std::pair<T, U> &item) {
    value(item.first);
    value(item.second);
  }
  template <typename T> void value(std::optional<T> &item) {
    bool present = item.has_value();
    value(present);
    if (!good())
      return;
    if (reading() && present)
      item.emplace();
    if (present)
      value(*item);
  }
  template <typename T> void value(std::shared_ptr<const T> &item) {
    bool present = bool(item);
    value(present);
    if (!good())
      return;
    if (reading() && present) {
      auto result = std::make_shared<T>();
      value(*result);
      item = std::move(result);
    } else if (present)
      value(*item);
  }
  template <typename K, typename V> void value(std::map<K, V> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > (input.size() - offset) / 16) {
        fail("declaration map exceeds its payload");
        return;
      }
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        K key{};
        V item{};
        value(key);
        value(item);
        if (!items.emplace(std::move(key), std::move(item)).second)
          fail("duplicate declaration map key");
      }
    } else
      for (auto &[key, item] : items) {
        value(key);
        value(item);
      }
  }
  template <typename T>
  void value(std::map<std::pair<std::string, std::uint64_t>, T> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > input.size() / 16) {
        fail("hygienic declaration map exceeds its payload");
        return;
      }
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        std::string spelling;
        SyntaxContextPtr context;
        T item{};
        (*this)(spelling, context, item);
        auto key =
            std::pair{std::move(spelling), context ? context->identity : 0};
        if (!items.emplace(std::move(key), std::move(item)).second)
          fail("duplicate hygienic declaration name");
      }
    } else
      for (auto &[key, item] : items) {
        SyntaxContextPtr context;
        if (key.second) {
          auto known = hygiene->contexts.find(key.second);
          if (known == hygiene->contexts.end()) {
            fail("unresolved declaration hygiene binder");
            return;
          }
          context = known->second;
        }
        (*this)(key.first, context, item);
      }
  }
  template <typename K, typename V>
  void value(std::unordered_map<K, V> &items) {
    std::map<K, V> ordered;
    if (!reading())
      ordered.insert(items.begin(), items.end());
    value(ordered);
    if (reading())
      items.insert(ordered.begin(), ordered.end());
  }
  template <typename T> void value(std::set<T> &items) {
    std::vector<T> ordered(items.begin(), items.end());
    value(ordered);
    if (reading())
      for (auto &item : ordered)
        if (!items.insert(std::move(item)).second)
          fail("duplicate declaration set item");
  }
  void symbol(metadata::SymbolKind kind, std::uint32_t &index) {
    std::string identity;
    if (!reading()) {
      auto resolved =
          encode->symbol ? encode->symbol(kind, index) : std::nullopt;
      if (!resolved || resolved->empty()) {
        fail("unresolved logical declaration symbol");
        return;
      }
      identity = std::move(*resolved);
    }
    value(identity);
    if (reading() && good()) {
      auto resolved =
          decode->symbol ? decode->symbol(kind, identity) : std::nullopt;
      if (!resolved)
        fail("unknown logical declaration symbol");
      else
        index = *resolved;
    }
  }
  void symbol(metadata::SymbolKind kind, int &index) {
    bool present = index >= 0;
    value(present);
    if (!good() || !present)
      return;
    auto encoded = static_cast<std::uint32_t>(index);
    symbol(kind, encoded);
    if (reading()) {
      if (encoded > std::uint32_t(std::numeric_limits<int>::max()))
        fail("declaration symbol exceeds its representation");
      else
        index = static_cast<int>(encoded);
    }
  }
  void package(std::uint32_t &index) {
    bool present = index != unknownPackage;
    value(present);
    if (present && good())
      symbol(metadata::SymbolKind::Package, index);
    else if (reading())
      index = unknownPackage;
  }
  void value(Type &type) {
    std::uint32_t index = 0;
    if (!reading()) {
      auto resolved = encode->type ? encode->type(type) : std::nullopt;
      if (!resolved) {
        fail("unresolved declaration type");
        return;
      }
      index = *resolved;
    }
    value(index);
    if (reading() && good()) {
      auto resolved = decode->type ? decode->type(index) : std::nullopt;
      if (!resolved ||
          (types && *resolved != Type::Unknown && !types->contains(*resolved)))
        fail("unknown declaration type reference");
      else
        type = *resolved;
    }
  }
  void value(Span &span) {
    metadata::SourceReference reference;
    if (!reading()) {
      auto resolved = encode->source ? encode->source(span) : std::nullopt;
      if (!resolved) {
        fail("unresolved declaration source revision");
        return;
      }
      reference = std::move(*resolved);
    }
    (*this)(reference.revision, reference.begin, reference.end);
    if (reference.begin > reference.end)
      fail("invalid declaration source extent");
    if (reading() && good()) {
      auto resolved = decode->source ? decode->source(reference) : std::nullopt;
      if (!resolved)
        fail("unknown declaration source revision");
      else
        span = *resolved;
    }
  }
  void value(RegionId &region) {
    Type carrier = Type::Unknown;
    if (!reading())
      carrier = types->viewType(Type::Unit, ParameterMode::Read, region);
    value(carrier);
    if (reading() && good()) {
      if (!types || !types->isView(carrier) ||
          types->view(carrier).payload != Type::Unit)
        fail("invalid declaration region reference");
      else
        region = types->view(carrier).region;
    }
  }
  void value(CallableType &signature) {
    Type carrier = Type::Unknown;
    if (!reading())
      carrier = types->callableType(signature);
    value(carrier);
    if (reading() && good()) {
      if (!types || !types->isCallable(carrier))
        fail("invalid declaration callable reference");
      else
        signature = types->callable(carrier);
    }
  }
  void value(SyntaxContextPtr &context) {
    bool present = bool(context);
    value(present);
    if (!present || !good())
      return;
    SyntaxContext result = reading() ? SyntaxContext{} : *context;
    if (!reading() && result.identity) {
      hygiene->contexts.emplace(result.identity, context);
      auto [position, inserted] = hygiene->binders.emplace(
          result.identity, hygiene->binders.size() + 1);
      result.identity = position->second;
    }
    (*this)(result.scope, result.definition, result.identity);
    if (reading() && good()) {
      if (result.identity > UINT32_MAX)
        fail("declaration hygiene reference exceeds its representation");
      else if (result.identity)
        result.identity |= std::uint64_t(result.definition.source + 1) << 32;
      context = std::make_shared<const SyntaxContext>(std::move(result));
    }
  }
  void value(NodeOwner &node) {
    bool present = node.get() != nullptr;
    value(present);
    if (!present || !good())
      return;
    if (reading()) {
      auto result = std::make_unique<Node>();
      value(*result);
      node = std::move(result);
    } else
      value(*node);
  }
  void tag(std::string expected) {
    auto actual = expected;
    value(actual);
    if (actual != expected)
      fail("unsupported checked declaration schema");
  }
  void finish() {
    if (reading() && good() && offset != input.size())
      fail("trailing checked declaration bytes");
  }
  template <typename T> void record(T &item);
  std::vector<std::uint8_t> output;
  std::string error;
  TypeStore *types;

private:
  const metadata::EncodeReferences *encode = nullptr;
  std::span<const std::uint8_t> input;
  const metadata::DecodeReferences *decode = nullptr;
  std::size_t offset = 0;
  unsigned depth = 0;
  std::shared_ptr<Hygiene> hygiene = std::make_shared<Hygiene>();
  static unsigned maximum(Kind *) { return unsigned(Kind::ConditionChain); }
  static unsigned maximum(TypeForm *) { return unsigned(TypeForm::Owner); }
  static unsigned maximum(OwnerKind *) {
    return unsigned(OwnerKind::LocalWeak);
  }
  static unsigned maximum(GenericParameterKind *) {
    return unsigned(GenericParameterKind::Region);
  }
  static unsigned maximum(PatternKind *) { return unsigned(PatternKind::Rest); }
  static unsigned maximum(TokenKind *) {
    return unsigned(TokenKind::FormatClose);
  }
  static unsigned maximum(ParameterMode *) {
    return unsigned(ParameterMode::Mut);
  }
  static unsigned maximum(StorageDuration *) {
    return unsigned(StorageDuration::Static);
  }
  static unsigned maximum(StaticConstant::Kind *) {
    return unsigned(StaticConstant::Kind::Pointer);
  }
  static unsigned maximum(ReceiverStep::Kind *) {
    return unsigned(ReceiverStep::Kind::Erase);
  }
  static unsigned maximum(interfaces::Property *) {
    return unsigned(interfaces::Property::Static);
  }
  static unsigned maximum(metadata::SymbolKind *) {
    return unsigned(metadata::SymbolKind::Static);
  }
};

#define WIRE(T, ...)                                                           \
  void wire(Archive &a, T &v) { a(__VA_ARGS__); }
WIRE(LexicalNameSyntax, v.spelling, v.span, v.context)
WIRE(GenericArgument, v.type, v.value, v.region, v.span, v.binding)
WIRE(TypeSyntax, v.name, v.view, v.sources, v.regions, v.nested, v.form,
     v.ownerKind, v.elements, v.count, v.countExpression, v.arguments,
     v.callable, v.binders, v.context)
WIRE(CallableParameterSyntax, v.annotation, v.mode, v.name)
WIRE(CallableTypeSyntax, v.parameters, v.result, v.error, v.mode, v.regions,
     v.unsafeCall, v.abi, v.variadic)
WIRE(GenericParameter, v.kind, v.name, v.span, v.bounds, v.annotation,
     v.defaultType, v.defaultValue, v.context, v.nameSpan)
WIRE(GenericConstraint, v.subject, v.bounds, v.equality, v.span, v.region)
WIRE(Pattern, v.kind, v.span, v.text, v.field, v.children, v.inclusive, v.rest,
     v.literalKind, v.context, v.fieldContext)
WIRE(ClosureParameter, v.name, v.annotation, v.span, v.mode, v.pattern,
     v.context)
WIRE(AssemblySyntax::Operand, v.mode, v.name, v.reg, v.explicitRegister,
     v.discard, v.input, v.output, v.span)
WIRE(AssemblySyntax, v.variant, v.templates, v.options, v.clobberAbis,
     v.operands)
WIRE(Node, v.kind, v.span, v.text, v.name, v.label, v.annotation, v.children,
     v.flag, v.semicolon, v.depth, v.patterns, v.parameters, v.error,
     v.genericArguments, v.ownerGenericArguments, v.assembly, v.context,
     v.fieldContext, v.fieldSpan)
WIRE(VisibilitySyntax, v.publicItem, v.restriction, v.span)
WIRE(Token, v.kind, v.span, v.text, v.context)
WIRE(Attribute, v.name, v.arguments, v.span, v.parenthesized)
WIRE(ItemSyntax, v.scope, v.visibility, v.attributes)
WIRE(Function, v.name, v.annotation, v.span, v.parameters, v.owner, v.receiver,
     v.destructor, v.regions, v.item, v.constructor, v.error,
     v.genericParameters, v.constraints, v.implicitGenericParameters,
     v.interfaceOwner, v.implementation, v.unsafeFunction, v.constFunction,
     v.asynchronous, v.asyncDefaultFutureInferred, v.asyncDefaultBodyResult,
     v.asyncOutput, v.asyncError, v.asyncFuture, v.futureStorage, v.abi,
     v.foreignDeclaration, v.variadic, v.explicitReceiver, v.variadicCursor,
     v.variadicSpan, v.lexicalContext)
WIRE(Module::Static, v.name, v.annotation, v.span, v.item, v.mutableBinding,
     v.foreignDeclaration, v.constant)
WIRE(Module::Associated, v.name, v.span, v.visibility, v.constant,
     v.asyncFuture, v.asyncFutureDefaultInferred, v.annotation, v.value,
     v.genericParameters, v.bounds, v.constraints)
WIRE(Module::Product::Variant, v.name, v.fields, v.span, v.attributes)
WIRE(Module::Product, v.name, v.span, v.copyRequested, v.fields, v.regions,
     v.hasDestructor, v.enumeration, v.unionType, v.variants, v.item,
     v.genericParameters, v.constraints, v.interfaces, v.associated,
     v.nameContext)
WIRE(Module::Alias, v.name, v.target, v.span, v.item, v.genericParameters,
     v.constraints)
WIRE(Module::Interface, v.name, v.span, v.item, v.genericParameters,
     v.constraints, v.superinterfaces, v.associated, v.unsafeInterface,
     v.nameContext)
WIRE(Module::Implementation, v.target, v.interface, v.span, v.item,
     v.genericParameters, v.constraints, v.associated, v.methodFunctions,
     v.shorthand, v.negative, v.unsafeImplementation)
WIRE(Module::ModuleDeclaration, v.name, v.span, v.item)
WIRE(Module::MacroDeclaration, v.name, v.span, v.item)
WIRE(Module::Import::Name, v.name, v.alias, v.span)
WIRE(Module::Import, v.path, v.names, v.alias, v.glob, v.synthesized, v.span,
     v.item)
WIRE(Module::Prelude, v.names, v.libraryRoots)
WIRE(Module, v.functions, v.statics, v.products, v.aliases, v.interfaces,
     v.implementations, v.modules, v.macros, v.imports, v.prelude)
WIRE(NumericLiteral, v.magnitude, v.floating, v.negative, v.floatingBits)
WIRE(FloatingPolicy, v.reassociate, v.contract, v.noNaNs, v.noInfinities,
     v.noSignedZeros, v.reciprocal, v.approximateFunctions)
WIRE(TypeBinding, v.parameter, v.argument)
WIRE(RegionRequirement, v.longer, v.shorter)
WIRE(Local, v.name, v.type, v.mutableBinding, v.span, v.mode, v.patternView,
     v.storage, v.readMatchPattern, v.context)
WIRE(FunctionFacts, v.result, v.asyncDefaultBodyResult, v.diverges, v.locals,
     v.resultSources, v.resultContents, v.withinFlows, v.error, v.abiResult,
     v.defaultAbiResults, v.defaultValueTypes, v.defaultBorrowed,
     v.defaultBorrowOperand, v.parameterBindings, v.parameterViewTypes,
     v.constructorSelfSlot, v.canonicalName, v.opaqueResult, v.regionSignature,
     v.genericParameters, v.genericResultSources, v.interfaceBounds,
     v.unpinBounds, v.genericEqualities, v.externalName, v.floatingPolicy,
     v.library, v.variadicCursor, v.targetFeatures, v.naked)
WIRE(StaticFacts, v.name, v.externalName, v.library, v.type, v.initializer)
WIRE(DeclarationEnvironment, v.names, v.bounds, v.parameters, v.defaults,
     v.equalities, v.declarationSpan)
WIRE(DeclarationRegions, v.names, v.parameters, v.assumptions)
WIRE(ImportedTypeDeclaration, v.span, v.name, v.type, v.generics)
void wire(Archive &a, ImportedInherentConstant &v) {
  a(v.implementation, v.declaration, v.name, v.target, v.declaredType, v.value,
    v.materialized);
  if ((!v.materialized && v.value == Type::Unknown) ||
      (v.materialized &&
       (v.value != Type::Unknown || v.materialized->type != v.declaredType ||
        (v.materialized->kind != StaticConstant::Kind::Aggregate &&
         v.materialized->kind != StaticConstant::Kind::Repeat))))
    a.fail("inconsistent checked associated constant value");
}
WIRE(interfaces::Obligation, v.subject, v.interfaceType, v.property)
WIRE(interfaces::Associated, v.name, v.parameter, v.parameters, v.defaultValue,
     v.bounds, v.requirements, v.constant, v.regions, v.regionRequirements,
     v.asyncFuture, v.asyncFutureDefaultInferred, v.equalities, v.defaults)
WIRE(interfaces::AssociatedValue, v.parameters, v.value, v.regions,
     v.regionRequirements, v.requirements, v.fromDefault)
WIRE(interfaces::ConcurrencyDeclaration, v.negative, v.implementation)
WIRE(interfaces::Projection, v.parameter, v.subject, v.interfaceType,
     v.associated, v.arguments, v.regionArguments)
WIRE(DeclarationSymbolIdentity, v.kind, v.index, v.span, v.definition)
WIRE(LibraryHeaderImport::TypeIdentity, v.reference, v.span, v.definition,
     v.parameterOrdinal)
#undef WIRE

void wire(Archive &a, ImportedClosure &v) {
  a(v.span, v.definition, v.facts, v.type);
  for (auto &local : v.facts.locals)
    if (local.storage == StorageDuration::Static)
      a.symbol(metadata::SymbolKind::Static, local.staticIndex);
}

void wire(Archive &a, Parameter &v) {
  a(v.name, v.annotation, v.span, v.mode, v.visibility, v.pattern, v.attributes,
    v.format, v.syntaxSpan, v.context);
  bool hasDefault = v.defaultValue.get() || v.compiledDefault;
  a(hasDefault);
  if (a.reading())
    v.compiledDefault = hasDefault;
}

void wire(Archive &a, StaticConstant &v) {
  a(v.kind, v.type, v.scalar, v.fields);
  if (v.kind == StaticConstant::Kind::Function)
    a.symbol(metadata::SymbolKind::Function, v.symbol);
  else if (v.kind == StaticConstant::Kind::Address)
    a.symbol(metadata::SymbolKind::Static, v.symbol);
  a(v.projections, v.selection, v.text, v.byteOffset);
  if ((v.kind == StaticConstant::Kind::Repeat && v.fields.size() != 1) ||
      v.selection < -1)
    a.fail("invalid checked static constant inventory");
  if (v.kind == StaticConstant::Kind::Text && !textConstantCount(*a.types, v))
    a.fail("invalid checked literal-backed static constant");
}
void wire(Archive &a, interfaces::Method &v) {
  a(v.name);
  a.symbol(metadata::SymbolKind::Function, v.function);
  a(v.signature, v.implicitParameters, v.dispatchable);
}
void wire(Archive &a, interfaces::Definition &v) {
  a(v.name, v.span);
  a.package(v.package);
  a(v.self, v.parameters, v.superinterfaces, v.associated, v.methods, v.regions,
    v.regionRequirements, v.requirements, v.equalities, v.unsafeInterface);
}
void wire(Archive &a, interfaces::MethodBinding &v) {
  a.symbol(metadata::SymbolKind::Function, v.function);
  a(v.arguments, v.defaultMethod);
}
void wire(Archive &a, interfaces::Implementation &v) {
  a(v.target, v.interfaceType, v.span);
  a.package(v.package);
  a(v.parameters, v.requirements, v.methods, v.associated, v.inherent,
    v.regions, v.regionRequirements, v.equalities);
}
void wire(Archive &a, interfaces::Database &v) {
  std::uint64_t count = v.definitions.size();
  a(count);
  if (count > limits::interfaces)
    a.fail("interface inventory exceeds the compiler representation");
  for (std::uint64_t i = 0; i < count && a.good(); ++i) {
    auto index = static_cast<std::uint32_t>(i);
    a.symbol(metadata::SymbolKind::Interface, index);
    if (!a.reading()) {
      a(v.definitions[i]);
      continue;
    }
    interfaces::Definition item;
    a(item);
    if (index >= limits::interfaces) {
      a.fail("interface identity exceeds the compiler representation");
      break;
    }
    if (v.definitions.size() <= index)
      v.definitions.resize(std::size_t(index) + 1);
    if (!v.definitions[index].name.empty())
      a.fail("duplicate checked interface identity");
    v.definitions[index] = std::move(item);
  }
  a(v.implementations, v.projections, v.unpinImplementations,
    v.concurrencyDeclarations, v.argumentsReady);
}
void wire(Archive &a, ReceiverStep &v) {
  a(v.kind, v.source, v.target, v.resultView, v.count, v.mode);
  a.symbol(metadata::SymbolKind::Function, v.callee);
  a(v.typeArguments, v.interfaceSelf, v.interfaceType, v.interfaceMethod);
}
void wire(Archive &a, ReceiverPlan &v) { a(v.source, v.target, v.steps); }
void wire(Archive &a, NodeFacts &v) {
  a(v.type);
  a.symbol(metadata::SymbolKind::Function, v.callee);
  a(v.slot, v.field, v.variant, v.number, v.numeric, v.machineOperation,
    v.machineType, v.constantParameter, v.constantValue, v.constantCount,
    v.callResult, v.typeArguments, v.lexicallyBound, v.unsafeContext,
    v.receiverPlan);
  a(v.interfaceSelf, v.interfaceType, v.interfaceMethod, v.outcomePropagation);
}
template <typename T> void Archive::record(T &item) {
  constexpr bool recursive =
      std::is_same_v<T, TypeSyntax> || std::is_same_v<T, Node> ||
      std::is_same_v<T, Pattern> || std::is_same_v<T, StaticConstant>;
  if constexpr (recursive) {
    if (depth >= limits::syntaxDepth) {
      fail("checked declaration nesting limit exceeded");
      return;
    }
    ++depth;
  }
  wire(*this, item);
  if constexpr (recursive)
    --depth;
  if constexpr (std::is_same_v<T, Node>) {
    if (!good())
      return;
    for (const auto &child : item.children)
      if (!child.get()) {
        fail("checked expression contains an empty child");
        return;
      }
    auto count = item.children.size();
    bool valid = true;
    switch (item.kind) {
    case Kind::Group:
    case Kind::Unary:
    case Kind::Cast:
    case Kind::Unsafe:
    case Kind::Field:
    case Kind::Condition:
      valid = count == 1;
      break;
    case Kind::Binary:
    case Kind::Assign:
    case Kind::Index:
    case Kind::While:
    case Kind::For:
    case Kind::Range:
      valid = count == 2;
      break;
    case Kind::Call:
    case Kind::Match:
      valid = count >= 1;
      break;
    case Kind::If:
      valid = count == 2 || count == 3;
      break;
    case Kind::Loop:
      valid = count == 1;
      break;
    case Kind::Array:
      valid = !item.flag || count == 2;
      break;
    default:
      break;
    }
    if ((item.kind == Kind::Binding && item.text == "<pattern>") ||
        item.kind == Kind::Arm || item.kind == Kind::For)
      valid &= item.patterns.size() == 1;
    if (!valid)
      fail("checked expression has an invalid operand inventory");
  }
  if constexpr (std::is_same_v<T, Pattern>)
    if ((item.kind == PatternKind::At || item.kind == PatternKind::Range) &&
        item.children.size() != 1)
      fail("checked pattern has an invalid operand inventory");
}

void expression(Archive &archive, std::shared_ptr<CheckedExpression> &value) {
  bool present = bool(value);
  archive(present);
  if (!present || !archive.good())
    return;
  if (archive.reading())
    value = std::make_shared<CheckedExpression>();
  archive(value->syntax);
  if (archive.good() && !value->syntax.get())
    archive.fail("checked expression has no executable root");
  auto visit = [&](auto &&self, const Node &node) -> void {
    NodeFacts facts;
    if (!archive.reading()) {
      auto found = value->facts.find(&node);
      if (found != value->facts.end())
        facts = found->second;
    }
    archive(facts);
    std::optional<StaticConstant> constant;
    if (!archive.reading())
      if (auto found = value->constants.find(&node);
          found != value->constants.end())
        constant = found->second;
    archive(constant);
    if (archive.reading())
      value->facts.emplace(&node, std::move(facts));
    if (archive.reading() && constant)
      value->constants.emplace(&node, std::move(*constant));
    for (const auto &child : node.children)
      self(self, *child);
  };
  if (archive.good())
    visit(visit, *value->syntax);
}

void function(Archive &archive, ImportedFunction &value) {
  archive(value.span, value.facts, value.generics, value.regions,
          value.unsafeFunction, value.hasBody);
  expression(archive, value.body);
  std::uint64_t count = value.defaults.size();
  archive(count);
  if (!archive.good())
    return;
  if (archive.reading()) {
    if (count > value.facts.locals.size()) {
      archive.fail("default contract exceeds the parameter inventory");
      return;
    }
    value.defaults.resize(static_cast<std::size_t>(count));
  }
  for (auto &item : value.defaults)
    expression(archive, item);
  const auto parameters = value.defaults.size();
  const auto &facts = value.facts;
  if (facts.defaultAbiResults.size() != parameters ||
      facts.defaultValueTypes.size() != parameters ||
      facts.defaultBorrowed.size() != parameters ||
      facts.defaultBorrowOperand.size() != parameters ||
      !archive.types->isCallable(facts.regionSignature))
    archive.fail("invalid checked function signature inventory");
  for (auto source : facts.resultSources)
    if (source >= parameters)
      archive.fail("invalid checked result source");
  for (auto source : facts.resultContents)
    if (source >= parameters)
      archive.fail("invalid checked result contents source");
  for (auto [source, target] : facts.withinFlows)
    if (source >= parameters || target >= parameters)
      archive.fail("invalid checked within flow");
  for (auto [slot, parameter] : facts.parameterBindings)
    if (slot < 0 || std::size_t(slot) >= facts.locals.size() ||
        parameter >= parameters)
      archive.fail("invalid checked parameter binding");
}

std::optional<evaluation::Shape> shape(const TypeStore &types, Type type,
                                       unsigned depth = 0) {
  if (depth > limits::typeDepth)
    return std::nullopt;
  evaluation::Shape result;
  result.type = type;
  if (type == Type::Unit) {
    result.kind = evaluation::Shape::Kind::Unit;
    return result;
  }
  if (!types.isProduct(type))
    return isNumeric(type) || type == Type::Bool || type == Type::Char
               ? std::optional(result)
               : std::nullopt;
  const auto &product = types.product(type);
  if (types.isSum(type) &&
      std::all_of(product.variants.begin(), product.variants.end(),
                  [](const auto &variant) { return variant.fields.empty(); }))
    return result;
  if (product.kind == AggregateKind::Array) {
    auto count = types.arrayLength(type);
    if (!count || product.components.empty())
      return std::nullopt;
    auto element = shape(types, product.components.front(), depth + 1);
    if (!element)
      return std::nullopt;
    result.kind = evaluation::Shape::Kind::Array;
    result.count = *count;
    result.elements.push_back(std::move(*element));
    return result;
  }
  if (product.kind != AggregateKind::Tuple)
    return std::nullopt;
  result.kind = evaluation::Shape::Kind::Tuple;
  for (const auto &field : product.fields) {
    auto element = shape(types, field.type, depth + 1);
    if (!element)
      return std::nullopt;
    result.elements.push_back(std::move(*element));
  }
  return result;
}
} // namespace

DeclarationInventory declarationInventory(const CheckedModule &module) {
  DeclarationInventory result;
  std::set<Type> known;
  auto types = [&](const DeclarationEnvironment &environment,
                   const std::string &owner, Span span) {
    for (std::size_t p = 0; p < environment.parameters.size(); ++p)
      if (known.insert(environment.parameters[p]).second)
        result.types.push_back(
            {environment.parameters[p], span, owner, std::uint32_t(p)});
  };
  const auto &contracts = *module.declarationContracts;
  for (const auto &product : contracts.products) {
    if (known.insert(product.type).second)
      result.types.push_back(
          {product.type, product.span, product.name, std::nullopt});
    types(product.generics, product.name, product.span);
  }
  for (const auto &alias : contracts.aliases)
    types(alias.generics, alias.name, alias.span);
  for (std::size_t i = 0; i < module.interfaceData->definitions.size(); ++i) {
    const auto &definition = module.interfaceData->definitions[i];
    result.symbols.push_back({metadata::SymbolKind::Interface, std::uint32_t(i),
                              definition.span, definition.name});
    if (known.insert(definition.self).second)
      result.types.push_back(
          {definition.self, definition.span, definition.name + "::<Self>", 0});
    if (i < contracts.interfaces.size())
      types(contracts.interfaces[i].generics, definition.name, definition.span);
    for (const auto &associated : definition.associated) {
      if (known.insert(associated.parameter).second)
        result.types.push_back(
            {associated.parameter, definition.span,
             definition.name + "::" + associated.name + "::<family>", 0});
      DeclarationEnvironment family;
      family.parameters = associated.parameters;
      types(family, definition.name + "::" + associated.name, definition.span);
    }
  }
  std::map<std::string, unsigned> implementationOrdinals;
  std::map<std::tuple<SourceId, std::size_t, std::size_t>, std::string>
      implementationNames;
  for (const auto &implementation : contracts.implementations) {
    std::string owner;
    for (const auto &syntax : module.tree.implementations)
      if (syntax.span.source == implementation.span.source &&
          syntax.span.begin == implementation.span.begin &&
          syntax.span.end == implementation.span.end) {
        for (const auto &scope : syntax.item.scope)
          owner += scope + "::";
        owner +=
            "<extend:" + syntax.target.name + ":" + syntax.interface.name + ">";
        break;
      }
    auto identity = owner + "::<implementation." +
                    std::to_string(implementationOrdinals[owner]++) + ">";
    implementationNames.emplace(std::tuple{implementation.span.source,
                                           implementation.span.begin,
                                           implementation.span.end},
                                identity);
    types(implementation.generics, identity, implementation.span);
  }
  for (const auto &associated : contracts.associated) {
    std::string owner;
    auto matches = [&](const Module::Associated &item) {
      return item.span.source == associated.span.source &&
             item.span.begin == associated.span.begin &&
             item.span.end == associated.span.end;
    };
    for (std::size_t i = 0; i < module.tree.interfaces.size(); ++i)
      for (const auto &item : module.tree.interfaces[i].associated)
        if (matches(item))
          owner = module.interfaceData->definitions[i].name;
    for (const auto &implementation : module.tree.implementations)
      for (const auto &item : implementation.associated)
        if (matches(item))
          owner = implementationNames.at({implementation.span.source,
                                          implementation.span.begin,
                                          implementation.span.end});
    types(associated.generics, owner + "::" + associated.name, associated.span);
  }
  for (const auto &implementation : contracts.database.implementations) {
    if (implementation.associated.empty())
      continue;
    const auto &syntax =
        module.tree.implementations[implementation.declaration];
    const auto &owner = implementationNames.at(
        {syntax.span.source, syntax.span.begin, syntax.span.end});
    const auto &definition =
        contracts.database.definitions
            [module.types->erased(implementation.interfaceType).declaration];
    for (const auto &[ordinal, associated] : implementation.associated) {
      const auto &name = definition.associated[ordinal].name;
      for (std::size_t p = 0; p < associated.parameters.size(); ++p)
        if (known.insert(associated.parameters[p]).second)
          result.types.push_back({associated.parameters[p], syntax.span,
                                  owner + "::<family." + name + ">",
                                  std::uint32_t(p)});
    }
  }
  std::map<const Function *, std::string> functionNames;
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    const auto &function = module.tree.functions[i];
    const auto &facts = module.functions[i];
    functionNames.emplace(&function, facts.canonicalName);
    result.symbols.push_back({metadata::SymbolKind::Function, std::uint32_t(i),
                              function.span, facts.canonicalName});
    if (auto contract = contracts.functions.find(std::uint32_t(i));
        contract != contracts.functions.end())
      types(contract->second.generics, facts.canonicalName, function.span);
    if (facts.opaqueResult != Type::Unknown &&
        known.insert(facts.opaqueResult).second)
      result.types.push_back({facts.opaqueResult, function.span,
                              facts.canonicalName + "::<opaque>",
                              std::nullopt});
  }
  for (const auto &[i, closure] : contracts.closures) {
    if (known.insert(closure.type).second)
      result.types.push_back(
          {closure.type, closure.span, closure.definition, std::nullopt});
    result.symbols.push_back(
        {metadata::SymbolKind::Closure, i, closure.span, closure.definition});
  }
  for (std::size_t i = 0; i < module.staticStorage.size(); ++i)
    result.symbols.push_back({metadata::SymbolKind::Static, std::uint32_t(i),
                              module.tree.statics[i].span,
                              module.staticStorage[i].name});
  std::set<std::uint32_t> packages;
  const auto symbolCount = result.symbols.size();
  for (std::size_t i = 0; i < symbolCount; ++i) {
    const auto symbol = result.symbols[i];
    if (auto package = module.namespaces().packageOf(symbol.span);
        package && packages.insert(*package).second)
      result.symbols.push_back(
          {metadata::SymbolKind::Package, *package, symbol.span, {}});
  }
  return result;
}

LibraryDeclarationExport
exportLibraryDeclarations(const CheckedModule &module,
                          const metadata::EncodeReferences &references,
                          std::span<const SourceId> omitImportSources) {
  LibraryDeclarationExport result;
  if (!module.declarationContracts) {
    result.error = "checked declaration contracts were not retained";
    return result;
  }
  Archive header(references, *module.types);
  header.tag("mettle.checked-header.1");
  const auto &tree = module.tree;
  header(tree.functions, tree.statics, tree.products, tree.aliases,
         tree.interfaces, tree.implementations, tree.modules, tree.macros);
  std::vector<Module::Import> imports;
  for (const auto &item : tree.imports)
    if (std::find(omitImportSources.begin(), omitImportSources.end(),
                  item.span.source) == omitImportSources.end())
      imports.push_back(item);
  header(imports, tree.prelude);
  auto inventory = declarationInventory(module);
  for (auto &symbol : inventory.symbols) {
    auto logical = references.symbol
                       ? references.symbol(symbol.kind, symbol.index)
                       : std::nullopt;
    if (!logical || logical->empty()) {
      header.fail("unresolved header symbol identity");
      break;
    }
    symbol.definition = std::move(*logical);
  }
  header(inventory.symbols);
  std::vector<LibraryHeaderImport::TypeIdentity> typeIdentities;
  for (const auto &identity : inventory.types) {
    auto reference =
        references.type ? references.type(identity.type) : std::nullopt;
    if (!reference) {
      header.fail("unresolved header type identity");
      break;
    }
    typeIdentities.push_back({*reference, identity.span, identity.definition,
                              identity.parameterOrdinal});
  }
  header(typeIdentities);
  if (!header.good()) {
    result.error = std::move(header.error);
    return result;
  }
  result.header = std::move(header.output);
  Archive contracts(references, *module.types, header.hygieneState());
  contracts.tag("mettle.checked-contracts.6");
  auto &value = *module.declarationContracts;
  std::uint64_t count = value.functions.size();
  contracts(count);
  for (auto &[index, item] : value.functions) {
    auto symbol = index;
    contracts.symbol(metadata::SymbolKind::Function, symbol);
    function(contracts, item);
    for (const auto &local : item.facts.locals)
      if (local.storage == StorageDuration::Static) {
        auto index = local.staticIndex;
        contracts.symbol(metadata::SymbolKind::Static, index);
      }
  }
  count = value.statics.size();
  contracts(count);
  for (auto &[index, item] : value.statics) {
    auto symbol = index;
    contracts.symbol(metadata::SymbolKind::Static, symbol);
    contracts(item);
  }
  contracts(value.products, value.aliases, value.interfaces,
            value.implementations, value.associated, value.inherentConstants);
  count = value.closures.size();
  contracts(count);
  for (auto &[index, closure] : value.closures) {
    auto symbol = index;
    contracts.symbol(metadata::SymbolKind::Closure, symbol);
    contracts(closure);
  }
  contracts(value.checkingDatabase, value.database);
  result.contracts = std::move(contracts.output);
  result.error = std::move(contracts.error);
  return result;
}

LibraryHeaderImport
decodeLibraryHeader(std::span<const std::uint8_t> bytes,
                    const metadata::DecodeReferences &references) {
  LibraryHeaderImport result;
  Archive archive(bytes, references, nullptr);
  archive.tag("mettle.checked-header.1");
  Module module;
  archive(module);
  archive(result.symbols);
  archive(result.types);
  archive.finish();
  if (!archive.good())
    result.error = std::move(archive.error);
  else {
    for (const auto &function : module.functions)
      if (function.implementation >= 0 &&
          std::size_t(function.implementation) >=
              module.implementations.size()) {
        result.error = "invalid declaration implementation reference";
        return result;
      }
    result.module = std::move(module);
  }
  return result;
}

LibraryDeclarationImport
importLibraryDeclarations(std::span<const std::uint8_t> bytes,
                          std::shared_ptr<TypeStore> types,
                          const metadata::DecodeReferences &references) {
  LibraryDeclarationImport result;
  if (!types) {
    result.error = "checked declarations require an imported type store";
    return result;
  }
  Archive archive(bytes, references, types.get());
  archive.tag("mettle.checked-contracts.6");
  auto value = std::make_shared<ImportedDeclarations>();
  value->types = std::move(types);
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size() / 8)
    archive.fail("function inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Function, index);
    ImportedFunction item;
    function(archive, item);
    for (auto &local : item.facts.locals)
      if (local.storage == StorageDuration::Static)
        archive.symbol(metadata::SymbolKind::Static, local.staticIndex);
    if (!value->functions.emplace(index, std::move(item)).second)
      archive.fail("duplicate checked function identity");
  }
  archive(count);
  if (count > bytes.size() / 8)
    archive.fail("static inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Static, index);
    StaticFacts item;
    archive(item);
    item.identity = index;
    if (!value->statics.emplace(index, std::move(item)).second)
      archive.fail("duplicate checked static identity");
  }
  archive(value->products, value->aliases, value->interfaces,
          value->implementations, value->associated, value->inherentConstants);
  archive(count);
  if (count > bytes.size() / 8)
    archive.fail("closure inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Closure, index);
    ImportedClosure closure;
    archive(closure);
    if (index >= limits::functions ||
        !value->closures.emplace(index, std::move(closure)).second)
      archive.fail("invalid checked closure identity");
  }
  archive(value->checkingDatabase, value->database);
  auto sameSpan = [](Span left, Span right) {
    return left.source == right.source && left.begin == right.begin &&
           left.end == right.end;
  };
  const auto &checking = value->checkingDatabase;
  const auto &finalized = value->database;
  if (checking.definitions.size() != finalized.definitions.size() ||
      checking.implementations.size() != finalized.implementations.size() ||
      !std::equal(checking.definitions.begin(), checking.definitions.end(),
                  finalized.definitions.begin(),
                  [&](const auto &left, const auto &right) {
                    return left.name == right.name &&
                           sameSpan(left.span, right.span);
                  }) ||
      !std::equal(checking.implementations.begin(),
                  checking.implementations.end(),
                  finalized.implementations.begin(),
                  [&](const auto &left, const auto &right) {
                    return sameSpan(left.span, right.span);
                  }))
    archive.fail("checked interface phases have conflicting inventories");
  archive.finish();
  if (!archive.good()) {
    result.error = std::move(archive.error);
    return result;
  }
  auto parameter = [&](Type type) {
    return value->types->isParameter(type) ||
           (value->types->isConstant(type) &&
            (value->types->parameter(type).kind ==
                 TypeParameterKind::Constant ||
             value->types->parameter(type).kind ==
                 TypeParameterKind::Projection));
  };
  auto parameters = [&](const std::vector<Type> &items) {
    return std::all_of(items.begin(), items.end(), parameter);
  };
  for (const auto *database : {&value->checkingDatabase, &value->database}) {
    auto definition = [&](Type type) -> const interfaces::Definition * {
      if (!value->types->isErased(type))
        return nullptr;
      auto index = value->types->erased(type).declaration;
      return index < database->definitions.size() &&
                     !database->definitions[index].name.empty()
                 ? &database->definitions[index]
                 : nullptr;
    };
    auto functionExists = [&](int index) {
      return index >= 0 && value->functions.contains(std::uint32_t(index));
    };
    for (const auto &item : database->definitions) {
      if (item.name.empty())
        continue;
      if (!value->types->isParameter(item.self) || !parameters(item.parameters))
        archive.fail("invalid checked interface parameter inventory");
      for (const auto &associated : item.associated)
        if (!parameter(associated.parameter) ||
            !parameters(associated.parameters))
          archive.fail("invalid checked associated parameter inventory");
      for (const auto &method : item.methods)
        if (!functionExists(method.function))
          archive.fail("unknown checked interface method");
    }
    auto implementation = [&](const interfaces::Implementation &item) {
      if (!value->types->contains(item.target) || !parameters(item.parameters))
        archive.fail("invalid checked implementation parameter inventory");
      const auto *owner = definition(item.interfaceType);
      if (item.interfaceType != Type::Unknown && !owner)
        archive.fail("unknown checked implementation interface");
      for (const auto &[ordinal, method] : item.methods)
        if (!owner || ordinal >= owner->methods.size() ||
            !functionExists(method.function))
          archive.fail("invalid checked implementation method");
      for (const auto &[ordinal, associated] : item.associated)
        if (!owner || ordinal >= owner->associated.size() ||
            !parameters(associated.parameters))
          archive.fail("invalid checked implementation associated item");
      for (const auto &[name, method] : item.inherent) {
        (void)name;
        if (!functionExists(method.function))
          archive.fail("unknown checked inherent method");
      }
    };
    for (const auto &item : database->implementations)
      implementation(item);
    for (const auto &[type, item] : database->unpinImplementations) {
      (void)type;
      implementation(item);
    }
    for (const auto &[key, item] : database->concurrencyDeclarations) {
      (void)key;
      implementation(item.implementation);
    }
    for (const auto &projection : database->projections) {
      const auto *owner = definition(projection.interfaceType);
      if (!owner || projection.associated >= owner->associated.size() ||
          !parameter(projection.parameter) ||
          !value->types->contains(projection.subject))
        archive.fail("invalid checked associated projection");
    }
    auto expression = [&](const std::shared_ptr<CheckedExpression> &body) {
      if (!body)
        return;
      for (const auto &[node, facts] : body->facts) {
        (void)node;
        if (facts.interfaceMethod == -1)
          continue;
        const auto *owner = definition(facts.interfaceType);
        if (facts.interfaceMethod < 0 || !owner ||
            static_cast<std::size_t>(facts.interfaceMethod) >=
                owner->methods.size() ||
            facts.interfaceSelf == Type::Unknown ||
            !value->types->contains(facts.interfaceSelf))
          archive.fail("invalid checked expression interface dispatch");
      }
    };
    for (const auto &[index, function] : value->functions) {
      (void)index;
      expression(function.body);
      for (const auto &argument : function.defaults)
        expression(argument);
    }
  }
  if (!archive.good()) {
    result.error = std::move(archive.error);
    return result;
  }
  for (auto &[index, item] : value->functions) {
    (void)index;
    if (!item.body)
      continue;
    auto resultShape = shape(*value->types, item.facts.result);
    if (resultShape)
      item.evaluation.result = std::move(*resultShape);
    item.evaluation.unsafeFunction = item.unsafeFunction;
    bool supported = resultShape.has_value();
    for (std::size_t i = 0; i < item.defaults.size(); ++i) {
      auto parameter = shape(*value->types, item.facts.locals[i].type);
      if (!parameter) {
        supported = false;
        break;
      }
      const auto &local = item.facts.locals[i];
      item.evaluation.parameters.push_back(
          {local.name, std::move(*parameter), local.span,
           item.defaults[i] ? item.defaults[i]->syntax.get() : nullptr,
           local.context});
    }
    if (supported)
      item.evaluation.body = item.body->syntax.get();
  }
  result.declarations = std::move(value);
  return result;
}
} // namespace mettle
