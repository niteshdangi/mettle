#include "ir/codec.h"
#include "support/limits.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <limits>
#include <map>
#include <mutex>
#include <set>
#include <thread>
#include <type_traits>
#include <unordered_map>

namespace mettle::ir {
namespace {
using metadata::SymbolKind;
struct InvalidArchive {
  std::string message;
};
[[noreturn]] void reject(std::string message) {
  throw InvalidArchive{std::move(message)};
}
template <class A> void functionHeader(A &a) {
  a(&Function::name, &Function::result, &Function::parameters);
  a.parameters();
  a(&Function::resultSources, &Function::resultContents, &Function::withinFlows,
    &Function::externalName, &Function::twoPhaseReceiver,
    &Function::constructorSelfSlot, &Function::indirectContract,
    &Function::callLocalParameters, &Function::genericParameters,
    &Function::declarationOnly, &Function::genericResultSources,
    &Function::interfaceBounds, &Function::unpinBounds, &Function::sizedBounds,
    &Function::regionSignature, &Function::interfaceResult,
    &Function::genericEqualities, &Function::unsafeFunction, &Function::abi,
    &Function::foreignDeclaration, &Function::exportedDefinition,
    &Function::variadic, &Function::floatingPolicy, &Function::variadicCursor,
    &Function::targetFeatures, &Function::nakedAssembly, &Function::coroutine,
    &Function::span, &Function::inlineHint, &Function::trackCaller);
}
template <class A, class L> void functionParameter(A &a, L &local) {
  a(local.name, local.type, local.mutableBinding, local.span, local.mode);
}
template <class A, class F> struct HeaderFields {
  A &archive;
  F &function;
  template <class... T> void operator()(T Function::*...members) {
    archive((function.*members)...);
  }
  void parameters() {
    if (function.parameters > limits::locals)
      reject("invalid IR function shape");
    if constexpr (A::reading)
      function.locals.resize(function.parameters);
    if (function.parameters > function.locals.size())
      reject("invalid IR function shape");
    for (std::size_t i = 0; i < function.parameters; ++i)
      functionParameter(archive, function.locals[i]);
  }
};
template <class A, class F> void functionHeader(A &a, F &r) {
  HeaderFields<A, F> fields{a, r};
  functionHeader(fields);
}
template <class A, class F> void functionBody(A &a, F &r) {
  std::size_t locals;
  if constexpr (A::reading) {
    locals = a.count(limits::locals);
    if (locals < r.parameters)
      reject("invalid IR function shape");
    r.locals.resize(locals);
  } else {
    locals = a.count(r.locals.size(), limits::locals);
  }
  for (std::size_t i = 0; i < locals; ++i) {
    auto &local = r.locals[i];
    if (i < r.parameters) {
      a(local.scope, local.order, local.storage);
      a.symbol(local.staticIndex, SymbolKind::Static);
    } else {
      a.value(local);
    }
  }
  a(r.values);
  a.sequence(r.scopes, limits::tokens);
  a(r.arrayLoops);
  a.sequence(r.blocks, limits::cfgBlocks);
}
template <class E> constexpr unsigned lastTag() {
  if constexpr (std::is_same_v<E, Access>)
    return static_cast<unsigned>(Access::Mut);
  else if constexpr (std::is_same_v<E, InlineHint>)
    return static_cast<unsigned>(InlineHint::Never);
  else if constexpr (std::is_same_v<E, Op>)
    return static_cast<unsigned>(Op::RawAddress);
  else if constexpr (std::is_same_v<E, Exit>)
    return static_cast<unsigned>(Exit::Suspend);
  else if constexpr (std::is_same_v<E, ParameterMode>)
    return static_cast<unsigned>(ParameterMode::Mut);
  else if constexpr (std::is_same_v<E, StorageDuration>)
    return static_cast<unsigned>(StorageDuration::Static);
  else if constexpr (std::is_same_v<E, Projection::Kind>)
    return static_cast<unsigned>(Projection::Kind::Opaque);
  else if constexpr (std::is_same_v<E, StaticConstant::Kind>)
    return static_cast<unsigned>(StaticConstant::Kind::TypeIdentity);
  else if constexpr (std::is_same_v<E, AssemblyVariant>)
    return static_cast<unsigned>(AssemblyVariant::Naked);
  else if constexpr (std::is_same_v<E, AssemblyMode>)
    return static_cast<unsigned>(AssemblyMode::Sym);
  else if constexpr (std::is_same_v<E, AssemblyOperand::SymbolKind>)
    return static_cast<unsigned>(AssemblyOperand::SymbolKind::Static);
  else if constexpr (std::is_same_v<E, TargetArch>)
    return static_cast<unsigned>(TargetArch::Aarch64);
  else {
    static_assert(std::is_same_v<E, TargetSystem>);
    return static_cast<unsigned>(TargetSystem::Darwin);
  }
}
template <class A, class T> void record(A &a, T &r) {
  using R = std::remove_const_t<T>;
  if constexpr (std::is_same_v<R, NumericLiteral>) {
    a(r.magnitude[0], r.magnitude[1], r.floating, r.negative, r.floatingBits);
    if ((!r.floating.empty() || r.floatingBits) &&
        (r.magnitude[0] || r.magnitude[1] ||
         (!r.floating.empty() && r.floatingBits)))
      reject("conflicting numeric literal carriers");
    if (!r.floating.empty() && !validFloatingLiteral(r.floating))
      reject("invalid floating literal");
  } else if constexpr (std::is_same_v<R, Value>) {
    a(r.id, r.type, r.access);
  } else if constexpr (std::is_same_v<R, Projection>) {
    a(r.kind, r.index, r.count, r.type);
  } else if constexpr (std::is_same_v<R, Place>) {
    a(r.root);
    a.sequence(r.fields, limits::cleanupPlaces);
  } else if constexpr (std::is_same_v<R, Local>) {
    a(r.name, r.type, r.mutableBinding, r.span, r.mode, r.scope, r.order,
      r.storage);
    a.symbol(r.staticIndex, SymbolKind::Static);
  } else if constexpr (std::is_same_v<R, Instruction::WitnessEntry>) {
    a(r.owner, r.method);
  } else if constexpr (std::is_same_v<R, Instruction>) {
    a(r.op, r.result, r.operands, r.predecessors, r.text, r.place);
    a.symbol(r.callee, SymbolKind::Function);
    a(r.number, r.span, r.target, r.indirectType, r.callLocalParameters,
      r.typeArguments, r.constantParameter, r.interfaceType, r.interfaceSelf,
      r.interfaceMethod);
    a.symbol(r.dropFunction, SymbolKind::Function);
    a(r.erasedDispatch, r.opaqueType);
    a.sequence(r.witnessEntries, limits::witnessSlots);
    a(r.numeric, r.unsafeAllowed, r.unpinProofs, r.assembly, r.scope);
    if (r.numeric && isFloating(r.result.type) &&
        !validFloatingConstant(*r.numeric, r.result.type))
      reject("invalid floating constant");
  } else if constexpr (std::is_same_v<R, Terminator>) {
    a(r.kind, r.value, r.first, r.second, r.span, r.unpredictable);
  } else if constexpr (std::is_same_v<R, Block>) {
    a(r.instructions, r.exit);
  } else if constexpr (std::is_same_v<R, Function::Scope>) {
    a(r.parent);
  } else if constexpr (std::is_same_v<R, Function::ArrayLoop>) {
    a(r.header, r.body, r.step, r.done, r.blocks, r.source, r.index, r.element,
      r.mode);
  } else if constexpr (std::is_same_v<R, TypeBinding>) {
    a(r.parameter, r.argument);
  } else if constexpr (std::is_same_v<R, FloatingPolicy>) {
    a(r.reassociate, r.contract, r.noNaNs, r.noInfinities, r.noSignedZeros,
      r.reciprocal, r.approximateFunctions);
  } else if constexpr (std::is_same_v<R, FunctionIndex>) {
    a(r.name, r.result, r.parameters, r.generic, r.declarationOnly,
      r.exportedDefinition, r.indirectContract, r.naked, r.hasAbi,
      r.hasExternalName, r.hasVariadicCursor, r.targetFeatures);
    if (r.parameters > limits::locals)
      reject("invalid IR function shape");
    if constexpr (A::reading)
      r.valid = true;
  } else if constexpr (std::is_same_v<R, Function>) {
    functionHeader(a, r);
    functionBody(a, r);
  } else if constexpr (std::is_same_v<R, StaticConstant>) {
    if (++a.constantDepth > limits::typeDepth)
      reject("static constant nesting exceeds compiler limit");
    a(r.kind, r.type, r.scalar);
    a.sequence(r.fields, limits::cleanupPlaces);
    a.symbol(r.symbol, r.kind == StaticConstant::Kind::Function
                           ? SymbolKind::Function
                           : SymbolKind::Static);
    a(r.projections, r.selection, r.text, r.byteOffset);
    if (((r.kind == StaticConstant::Kind::Address ||
          r.kind == StaticConstant::Kind::Function) &&
         r.symbol < 0) ||
        (r.kind == StaticConstant::Kind::Repeat && r.fields.size() != 1) ||
        (r.kind == StaticConstant::Kind::TypeIdentity &&
         (r.type != Type::U64 || r.text.empty() || !r.fields.empty() ||
          r.symbol != -1 || !r.projections.empty() || r.selection != -1 ||
          r.byteOffset != 0)) ||
        r.selection < -1)
      reject("invalid IR static constant shape");
    if (r.kind == StaticConstant::Kind::Scalar && isFloating(r.type) &&
        !validFloatingConstant(r.scalar, r.type))
      reject("invalid static floating constant");
    --a.constantDepth;
  } else if constexpr (std::is_same_v<R, Program::Static>) {
    a(r.name, r.externalName, r.library, r.type, r.mutableBinding,
      r.foreignDeclaration, r.span, r.initializer);
  } else if constexpr (std::is_same_v<R, Program::OpaqueAdapter>) {
    a(r.self, r.interfaceType, r.method);
    a.symbol(r.function, SymbolKind::Function);
    a(r.methodArguments);
  } else if constexpr (std::is_same_v<R, AssemblyOperand>) {
    a(r.mode, r.name, r.reg, r.explicitRegister, r.discard, r.type, r.inputType,
      r.constant, r.constantIdentity, r.symbolKind);
    a.symbol(r.symbol, r.symbolKind == AssemblyOperand::SymbolKind::Function
                           ? SymbolKind::Function
                           : SymbolKind::Static);
    a(r.symbolArguments);
    if (r.mode == AssemblyMode::Sym && r.symbol < 0)
      reject("missing IR assembly symbol");
  } else if constexpr (std::is_same_v<R, Assembly>) {
    a(r.variant, r.templates, r.operands, r.options, r.clobberAbis);
  } else {
    static_assert(std::is_same_v<R, TargetFacts>);
    a(r.arch, r.system, r.pointerBits, r.littleEndian, r.triple, r.baseline);
    if (r.pointerBits != 0 && r.pointerBits != 16 && r.pointerBits != 32 &&
        r.pointerBits != 64)
      reject("invalid target pointer width");
  }
}
template <class T> struct IsVector : std::false_type {};
template <class T> struct IsVector<std::vector<T>> : std::true_type {};
template <class T> struct IsOptional : std::false_type {};
template <class T> struct IsOptional<std::optional<T>> : std::true_type {};
template <class T> struct IsShared : std::false_type {};
template <class T>
struct IsShared<std::shared_ptr<const T>> : std::true_type {};
template <class T> struct IsSet : std::false_type {};
template <class T> struct IsSet<std::set<T>> : std::true_type {};
template <class T> struct IsPair : std::false_type {};
template <class T, class U> struct IsPair<std::pair<T, U>> : std::true_type {};

struct SymbolDefinitions {
  struct Binding {
    SymbolKind kind;
    std::uint32_t index;
    std::string_view name;
  };
  std::vector<Binding> bindings;
  std::vector<std::size_t> names;
  void finish() {
    std::sort(bindings.begin(), bindings.end(),
              [](const auto &a, const auto &b) {
                return std::pair{a.kind, a.index} < std::pair{b.kind, b.index};
              });
    for (std::size_t i = 0; i < bindings.size(); ++i) {
      if (i && bindings[i - 1].kind == bindings[i].kind &&
          bindings[i - 1].index == bindings[i].index)
        reject("duplicate or aliased IR definition identity");
      names.push_back(i);
    }
    std::sort(names.begin(), names.end(), [&](auto a, auto b) {
      return std::pair{bindings[a].kind, bindings[a].name} <
             std::pair{bindings[b].kind, bindings[b].name};
    });
    for (std::size_t i = 1; i < names.size(); ++i) {
      const auto &a = bindings[names[i - 1]], &b = bindings[names[i]];
      if (a.kind == b.kind && a.name == b.name)
        reject("duplicate or aliased IR definition identity");
    }
  }
  bool contains(SymbolKind kind, std::uint32_t index,
                std::string_view name) const {
    auto key = std::pair{kind, index};
    auto byId = std::lower_bound(
        bindings.begin(), bindings.end(), key,
        [](const auto &a, auto b) { return std::pair{a.kind, a.index} < b; });
    if (byId != bindings.end() && byId->kind == kind && byId->index == index) {
      if (byId->name != name)
        reject("inconsistent or aliased IR logical symbol mapping");
      return true;
    }
    auto byName = std::lower_bound(
        names.begin(), names.end(), std::pair{kind, name},
        [&](auto a, const auto &b) {
          return std::pair{bindings[a].kind, bindings[a].name} < b;
        });
    if (byName != names.end() && bindings[*byName].kind == kind &&
        bindings[*byName].name == name)
      reject("inconsistent or aliased IR logical symbol mapping");
    return false;
  }
};
struct Symbols {
  std::shared_ptr<const SymbolDefinitions> definitions;
  std::map<std::pair<SymbolKind, std::string>, std::uint32_t> indices;
  std::map<std::pair<SymbolKind, std::uint32_t>, std::string_view> identities;
  Symbols() = default;
  Symbols(const Symbols &) = delete;
  Symbols &operator=(const Symbols &) = delete;
  Symbols(Symbols &&) = default;
  Symbols &operator=(Symbols &&) = default;
  void bind(SymbolKind kind, std::uint32_t index, std::string_view name) {
    if (definitions && definitions->contains(kind, index, name))
      return;
    auto known = identities.find({kind, index});
    if (known != identities.end()) {
      if (known->second != name)
        reject("inconsistent or aliased IR logical symbol mapping");
      return;
    }
    auto [binding, inserted] =
        indices.emplace(std::pair{kind, std::string(name)}, index);
    if (!inserted)
      reject("inconsistent or aliased IR logical symbol mapping");
    identities.emplace(std::pair{kind, index}, binding->first.second);
  }
  void merge(const Symbols &other) {
    for (const auto &[key, name] : other.identities)
      bind(key.first, key.second, name);
  }
};
template <class Derived> struct Fields {
  unsigned constantDepth = 0;
  Derived &self() { return static_cast<Derived &>(*this); }
  template <class... T> void operator()(T &...values) { (value(values), ...); }
  template <class T> void value(T &v) {
    using V = std::remove_const_t<T>;
    if constexpr (std::is_same_v<V, Type>)
      self().type(v);
    else if constexpr (std::is_same_v<V, Span>)
      self().source(v);
    else if constexpr (std::is_same_v<V, std::string>)
      self().text(v);
    else if constexpr (std::is_same_v<V, bool>)
      self().boolean(v);
    else if constexpr (std::is_enum_v<V>) {
      if constexpr (Derived::reading) {
        auto tag = self().unsignedInteger(1);
        if (tag > lastTag<V>())
          reject("invalid IR enumeration tag");
        v = static_cast<V>(tag);
      } else {
        auto tag = static_cast<unsigned>(v);
        if (tag > lastTag<V>())
          reject("invalid IR enumeration tag");
        self().unsignedInteger(tag, 1);
      }
    } else if constexpr (std::is_integral_v<V>) {
      if constexpr (std::is_signed_v<V>) {
        static_assert(sizeof(V) == 4);
        if constexpr (Derived::reading)
          v = std::bit_cast<std::int32_t>(
              static_cast<std::uint32_t>(self().unsignedInteger(4)));
        else
          self().unsignedInteger(std::bit_cast<std::uint32_t>(v), 4);
      } else if constexpr (Derived::reading) {
        auto number = self().unsignedInteger(8);
        if (number > std::numeric_limits<V>::max())
          reject("IR integer exceeds destination representation");
        v = static_cast<V>(number);
      } else {
        self().unsignedInteger(v, 8);
      }
    } else if constexpr (IsVector<V>::value) {
      self().sequence(v, limits::tokens);
    } else if constexpr (IsOptional<V>::value) {
      bool present = v.has_value();
      self().boolean(present);
      if constexpr (Derived::reading) {
        if (present)
          v.emplace();
        else
          v.reset();
      }
      if (present)
        value(*v);
    } else if constexpr (IsShared<V>::value) {
      using E = typename V::element_type;
      bool present = v != nullptr;
      self().boolean(present);
      if constexpr (Derived::reading) {
        if (present) {
          auto decoded = std::make_shared<std::remove_const_t<E>>();
          value(*decoded);
          v = std::move(decoded);
        } else {
          v.reset();
        }
      } else if (present) {
        value(const_cast<std::remove_const_t<E> &>(*v));
      }
    } else if constexpr (IsSet<V>::value) {
      self().strings(v);
    } else if constexpr (IsPair<V>::value) {
      (*this)(v.first, v.second);
    } else {
      record(self(), v);
    }
  }
};
struct Writer : Fields<Writer> {
  static constexpr bool reading = false;
  const metadata::EncodeReferences &references;
  Symbols symbols;
  std::vector<std::uint8_t> bytes;
  struct TextHash {
    using is_transparent = void;
    std::size_t operator()(std::string_view text) const {
      return std::hash<std::string_view>{}(text);
    }
  };
  bool interned;
  std::unordered_map<std::string, std::uint32_t, TextHash, std::equal_to<>>
      textIndices;
  std::vector<const std::string *> texts;
  explicit Writer(const metadata::EncodeReferences &references,
                  bool interned = false)
      : references(references), interned(interned) {}
  void unsignedInteger(std::uint64_t number, unsigned width) {
    if (bytes.size() > limits::sourceBytes - 10)
      reject("IR archive exceeds compiler file size limit");
    if (width == 1) {
      bytes.push_back(static_cast<std::uint8_t>(number));
      return;
    }
    // LEB128: identifiers, counts and offsets are almost always small.
    while (number >= 0x80) {
      bytes.push_back(static_cast<std::uint8_t>(number | 0x80));
      number >>= 7;
    }
    bytes.push_back(static_cast<std::uint8_t>(number));
  }
  void boolean(bool v) { unsignedInteger(v, 1); }
  void text(const std::string &v) {
    if (interned) {
      auto [found, added] =
          textIndices.try_emplace(v, static_cast<std::uint32_t>(texts.size()));
      if (added) {
        if (texts.size() >= limits::tokens)
          reject("IR string table exceeds compiler count limit");
        texts.push_back(&found->first);
      }
      unsignedInteger(found->second, 4);
      return;
    }
    if (v.size() > limits::sourceBytes ||
        bytes.size() > limits::sourceBytes - v.size() ||
        bytes.size() + v.size() > limits::sourceBytes - 4)
      reject("IR archive string exceeds compiler file size limit");
    unsignedInteger(v.size(), 4);
    bytes.insert(bytes.end(), v.begin(), v.end());
  }
  std::uint32_t count(std::size_t count, std::size_t limit) {
    if (count > limit || count > std::numeric_limits<std::uint32_t>::max())
      reject("IR collection exceeds compiler count limit");
    unsignedInteger(count, 4);
    return static_cast<std::uint32_t>(count);
  }
  template <class T> void sequence(const T &v, std::size_t limit) {
    count(v.size(), limit);
    for (const auto &item : v)
      value(item);
  }
  void strings(const std::set<std::string> &v) {
    count(v.size(), limits::tokens);
    for (const auto &item : v)
      text(item);
  }
  void type(Type v) {
    auto ref = references.type ? references.type(v) : std::nullopt;
    if (!ref)
      reject("unmapped IR type reference");
    unsignedInteger(*ref, 4);
  }
  void source(Span v) {
    auto ref = references.source ? references.source(v) : std::nullopt;
    if (!ref || ref->begin > ref->end)
      reject("unmapped or invalid IR source reference");
    text(ref->revision);
    unsignedInteger(ref->begin, 4);
    unsignedInteger(ref->end, 4);
  }
  std::string identity(SymbolKind kind, std::uint32_t id) {
    auto ref = references.symbol ? references.symbol(kind, id) : std::nullopt;
    if (!ref || ref->empty())
      reject("unmapped IR logical symbol");
    symbols.bind(kind, id, *ref);
    text(*ref);
    return *ref;
  }
  void symbol(int id, SymbolKind kind) {
    if (id < -1)
      reject("invalid negative IR symbol");
    boolean(id >= 0);
    if (id >= 0)
      identity(kind, static_cast<std::uint32_t>(id));
  }
};
struct Reader : Fields<Reader> {
  static constexpr bool reading = true;
  const metadata::DecodeReferences &references;
  Symbols symbols;
  std::span<const std::uint8_t> bytes;
  std::size_t position = 0;
  bool interned;
  std::vector<std::string_view> ownedTexts;
  std::span<const std::string_view> texts;
  metadata::SourceReference sourceReference;
  Reader(std::span<const std::uint8_t> bytes,
         const metadata::DecodeReferences &references, bool interned = false,
         const std::span<const std::string_view> *inheritedTexts = nullptr)
      : references(references), bytes(bytes), interned(interned) {
    if (bytes.size() > limits::sourceBytes)
      reject("IR archive exceeds compiler file size limit");
    if (interned) {
      if (inheritedTexts) {
        texts = *inheritedTexts;
      } else {
        auto size = count(limits::tokens);
        for (std::uint32_t i = 0; i < size; ++i)
          ownedTexts.push_back(rawText());
        texts = ownedTexts;
      }
    }
  }
  std::uint64_t unsignedInteger(unsigned width) {
    if (width == 1) {
      if (position >= bytes.size())
        reject("truncated IR archive");
      return bytes[position++];
    }
    std::uint64_t result = 0;
    for (unsigned shift = 0;; shift += 7) {
      if (position >= bytes.size() || shift > 63)
        reject("truncated IR archive");
      auto byte = bytes[position++];
      if (shift == 63 && byte > 1)
        reject("IR integer exceeds its width");
      result |= std::uint64_t{byte & 0x7fu} << shift;
      if (!(byte & 0x80))
        break;
    }
    if (width < 8 && result >> (width * 8))
      reject("IR integer exceeds its width");
    return result;
  }
  void boolean(bool &v) {
    auto bit = unsignedInteger(1);
    if (bit > 1)
      reject("invalid IR boolean");
    v = bit != 0;
  }
  std::string_view rawText() {
    auto count = unsignedInteger(4);
    if (count > bytes.size() - position)
      reject("truncated IR string");
    std::string_view result(
        reinterpret_cast<const char *>(bytes.data() + position), count);
    position += count;
    return result;
  }
  std::string_view text() {
    if (!interned)
      return rawText();
    auto index = unsignedInteger(4);
    if (index >= texts.size())
      reject("invalid IR string table reference");
    return texts[index];
  }
  void text(std::string &v) { v = text(); }
  std::uint32_t count(std::size_t limit) {
    auto count = unsignedInteger(4);
    if (count > limit || count > bytes.size() - position)
      reject("invalid or truncated IR collection");
    return static_cast<std::uint32_t>(count);
  }
  template <class T> void sequence(T &v, std::size_t limit) {
    auto size = count(limit);
    v.clear();
    for (std::uint32_t i = 0; i < size; ++i) {
      v.emplace_back();
      value(v.back());
    }
  }
  void strings(std::set<std::string> &v) {
    auto size = count(limits::tokens);
    v.clear();
    for (std::uint32_t i = 0; i < size; ++i) {
      std::string item;
      text(item);
      if (!v.insert(std::move(item)).second)
        reject("duplicate IR set entry");
    }
  }
  void type(Type &v) {
    auto id = static_cast<std::uint32_t>(unsignedInteger(4));
    auto ref = references.type ? references.type(id) : std::nullopt;
    if (!ref)
      reject("unmapped IR type reference");
    v = *ref;
  }
  void source(Span &v) {
    auto &source = sourceReference;
    text(source.revision);
    source.begin = static_cast<std::uint32_t>(unsignedInteger(4));
    source.end = static_cast<std::uint32_t>(unsignedInteger(4));
    if (source.begin > source.end)
      reject("invalid IR source range");
    auto ref = references.source ? references.source(source) : std::nullopt;
    if (!ref || ref->begin > ref->end || ref->end > limits::sourceBytes)
      reject("unmapped or invalid IR source reference");
    v = *ref;
  }
  std::pair<std::string_view, std::uint32_t>
  identity(SymbolKind kind, std::string_view name, bool bind = true) {
    auto ref = references.symbol ? references.symbol(kind, name) : std::nullopt;
    if (name.empty() || !ref ||
        *ref > static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
      reject("unmapped or invalid IR logical symbol");
    if (bind)
      symbols.bind(kind, *ref, name);
    return {name, *ref};
  }
  std::pair<std::string_view, std::uint32_t> identity(SymbolKind kind,
                                                      bool bind = true) {
    return identity(kind, text(), bind);
  }
  void symbol(int &id, SymbolKind kind) {
    bool present;
    boolean(present);
    id = present ? static_cast<int>(identity(kind).second) : -1;
  }
};

struct HeaderScanner {
  Reader &reader;
  template <class... T> void operator()(T &...values) { (value(values), ...); }
  template <class T> void value(T &v) {
    if constexpr (std::is_same_v<T, std::string>) {
      reader.text();
    } else if constexpr (IsVector<T>::value) {
      sequence(v, limits::tokens);
    } else if constexpr (IsOptional<T>::value) {
      bool present;
      reader.boolean(present);
      if (present) {
        v.emplace();
        value(*v);
      } else {
        v.reset();
      }
    } else if constexpr (IsSet<T>::value) {
      auto size = reader.count(limits::tokens);
      std::set<std::string_view> entries;
      for (std::uint32_t i = 0; i < size; ++i)
        if (!entries.insert(reader.text()).second)
          reject("duplicate IR set entry");
    } else if constexpr (IsPair<T>::value) {
      (*this)(v.first, v.second);
    } else if constexpr (std::is_same_v<T, Type> || std::is_same_v<T, Span> ||
                         std::is_arithmetic_v<T> || std::is_enum_v<T> ||
                         std::is_same_v<T, NumericLiteral>) {
      reader.value(v);
    } else {
      record(*this, v);
    }
  }
  template <class T> void sequence(T &, std::size_t limit) {
    auto size = reader.count(limit);
    typename T::value_type item{};
    for (std::uint32_t i = 0; i < size; ++i)
      value(item);
  }
  void symbol(int &id, SymbolKind kind) { reader.symbol(id, kind); }
};

bool validIndex(int index, std::size_t size, bool optional = false) {
  return (optional && index == -1) ||
         (index >= 0 && static_cast<std::size_t>(index) < size);
}
bool sameFunctionIndex(const FunctionIndex &left, const FunctionIndex &right) {
  return left.name == right.name && left.result == right.result &&
         left.parameters == right.parameters && left.generic == right.generic &&
         left.declarationOnly == right.declarationOnly &&
         left.exportedDefinition == right.exportedDefinition &&
         left.indirectContract == right.indirectContract &&
         left.naked == right.naked && left.hasAbi == right.hasAbi &&
         left.hasExternalName == right.hasExternalName &&
         left.hasVariadicCursor == right.hasVariadicCursor &&
         left.targetFeatures == right.targetFeatures;
}
void checkParameter(std::size_t parameter, std::size_t parameters) {
  if (parameter >= parameters)
    reject("invalid IR parameter reference");
}
void checkWithinFlow(std::size_t source, std::size_t target,
                     std::size_t parameters) {
  if (source >= parameters || target >= parameters)
    reject("invalid IR within-flow parameter reference");
}
struct HeaderIndexReader {
  HeaderScanner scanner;
  FunctionIndex &index;
  template <class... T> void operator()(T Function::*...members) {
    (field(members), ...);
  }
  template <class T> void field(T Function::*member) {
    auto &reader = scanner.reader;
    if constexpr (std::is_same_v<T, std::string>) {
      if (member == &Function::name) {
        reader.value(index.name);
        return;
      }
      if (member == &Function::abi) {
        index.hasAbi = !reader.text().empty();
        return;
      }
      if (member == &Function::externalName) {
        index.hasExternalName = !reader.text().empty();
        return;
      }
    } else if constexpr (std::is_same_v<T, int>) {
      if (member == &Function::variadicCursor) {
        int cursor;
        reader.value(cursor);
        index.hasVariadicCursor = cursor >= 0;
        return;
      }
    } else if constexpr (std::is_same_v<T, Type>) {
      if (member == &Function::result) {
        reader.value(index.result);
        return;
      }
    } else if constexpr (std::is_same_v<T, std::size_t>) {
      reader.value(index.parameters);
      return;
    } else if constexpr (std::is_same_v<T, bool>) {
      if (member == &Function::declarationOnly) {
        reader.value(index.declarationOnly);
        return;
      }
      if (member == &Function::exportedDefinition) {
        reader.value(index.exportedDefinition);
        return;
      }
      if (member == &Function::indirectContract) {
        reader.value(index.indirectContract);
        return;
      }
    } else if constexpr (std::is_same_v<T, std::vector<std::size_t>>) {
      auto size = reader.count(limits::tokens);
      for (std::uint32_t i = 0; i < size; ++i) {
        std::size_t parameter;
        reader.value(parameter);
        checkParameter(parameter, index.parameters);
      }
      return;
    } else if constexpr (std::is_same_v<T, std::vector<std::pair<
                                               std::size_t, std::size_t>>>) {
      auto size = reader.count(limits::tokens);
      for (std::uint32_t i = 0; i < size; ++i) {
        std::pair<std::size_t, std::size_t> flow;
        reader.value(flow);
        checkWithinFlow(flow.first, flow.second, index.parameters);
      }
      return;
    } else if constexpr (std::is_same_v<T, std::vector<Type>>) {
      auto size = reader.count(limits::tokens);
      if (member == &Function::genericParameters)
        index.generic = size != 0;
      Type type;
      for (std::uint32_t i = 0; i < size; ++i)
        reader.value(type);
      return;
    } else if constexpr (std::is_same_v<T, std::set<std::string>>) {
      reader.value(index.targetFeatures);
      return;
    }
    T value{};
    scanner.value(value);
    if constexpr (std::is_same_v<T, std::optional<Assembly>>)
      index.naked = value.has_value();
  }
  void parameters() {
    if (index.parameters > limits::locals)
      reject("invalid IR function shape");
    Local local;
    for (std::size_t i = 0; i < index.parameters; ++i)
      functionParameter(scanner, local);
  }
};

// Decodes the records on up to eight threads; each has its own reader, whose
// symbol bindings are checked against the shared table afterwards. The first
// failing record (by position) is the one reported.
template <class Items>
void decodeRecords(
    Items &items,
    const std::vector<std::pair<std::size_t, std::size_t>> &extents,
    std::span<const std::uint8_t> bytes,
    const metadata::DecodeReferences &references, Symbols &symbols) {
  const std::size_t count = extents.size();
  std::vector<std::string> failures(count);
  std::vector<Symbols> bound(count);
  auto decode = [&](std::size_t i) {
    try {
      Reader record(bytes.subspan(extents[i].first, extents[i].second),
                    references, true);
      record.value(items[i]);
      if (record.position != extents[i].second)
        reject("trailing data in IR record");
      bound[i] = std::move(record.symbols);
    } catch (const InvalidArchive &error) {
      failures[i] = error.message;
    }
  };
  const std::size_t workers =
      count < 64
          ? 1
          : std::max<std::size_t>(
                1,
                std::min<std::size_t>(
                    {8, std::thread::hardware_concurrency(), count / 64 + 1}));
  std::vector<std::thread> threads;
  for (std::size_t w = 1; w < workers; ++w)
    threads.emplace_back([&, w] {
      for (std::size_t i = w; i < count; i += workers)
        decode(i);
    });
  for (std::size_t i = 0; i < count; i += workers)
    decode(i);
  for (auto &thread : threads)
    thread.join();
  struct CachedBinding {
    std::uint64_t key = 0;
    // The corresponding record binding outlives this cache.
    std::string_view name;
    bool occupied = false;
  };
  std::array<CachedBinding, 4096> recent{};
  for (std::size_t i = 0; i < count; ++i) {
    if (!failures[i].empty())
      reject(failures[i]);
    for (const auto &[key, name] : bound[i].identities) {
      auto encoded = (std::uint64_t(key.first) << 32) | key.second;
      auto &cached = recent[(encoded ^ (encoded >> 32)) % recent.size()];
      if (cached.occupied && cached.key == encoded && cached.name == name)
        continue;
      symbols.bind(key.first, key.second, name);
      cached = {encoded, name, true};
    }
  }
}

struct FunctionRecordExtent {
  std::size_t recordOffset = 0;
  std::size_t recordLength = 0;
  std::size_t bodyLength = 0;
};

struct FunctionSegments {
  std::size_t headerOffset = 0, headerLength = 0;
  std::size_t bodyOffset = 0, bodyLength = 0;
};

std::pair<std::span<const std::uint8_t>, std::span<const std::uint8_t>>
summarySegments(std::span<const std::uint8_t> body) {
  const metadata::DecodeReferences references;
  Reader reader(body, references);
  const auto length = reader.unsignedInteger(4);
  if (length > body.size() - reader.position)
    reject("invalid IR function summary extent");
  return {body.subspan(reader.position, length),
          body.subspan(reader.position + length)};
}

FunctionSegments functionSegments(const FunctionRecordExtent &extent) {
  const auto headerLength = extent.recordLength - extent.bodyLength;
  return {0, headerLength, headerLength, extent.bodyLength};
}

void programVersion(Reader &reader) {
  if (reader.unsignedInteger(4) != 0x5249544d ||
      reader.unsignedInteger(4) != 17)
    reject("unsupported IR archive format or version");
}

template <class Visit> void readFunctionRecords(Reader &reader, Visit &&visit) {
  struct Entry {
    std::string_view name, package;
    std::span<const std::uint8_t> index;
    FunctionRecordExtent extent;
  };
  const auto count = reader.count(limits::functions);
  std::vector<Entry> entries;
  entries.reserve(count);
  std::size_t payload = 0;
  for (std::uint32_t i = 0; i < count; ++i) {
    auto &entry = entries.emplace_back();
    entry.name = reader.text();
    entry.package = reader.text();
    const auto indexLength = reader.unsignedInteger(4);
    if (!indexLength || indexLength > reader.bytes.size() - reader.position)
      reject("invalid IR function index extent");
    entry.index = reader.bytes.subspan(reader.position, indexLength);
    reader.position += indexLength;
    const auto headerLength = reader.unsignedInteger(4);
    const auto bodyLength = reader.unsignedInteger(4);
    if (headerLength > reader.bytes.size() ||
        bodyLength > reader.bytes.size() - headerLength ||
        headerLength + bodyLength > reader.bytes.size() - payload)
      reject("truncated IR record");
    entry.extent = {payload,
                    static_cast<std::size_t>(headerLength + bodyLength),
                    static_cast<std::size_t>(bodyLength)};
    payload += entry.extent.recordLength;
  }
  if (payload > reader.bytes.size() - reader.position)
    reject("truncated IR record");
  const auto base = reader.position;
  for (std::uint32_t i = 0; i < count; ++i) {
    auto &entry = entries[i];
    entry.extent.recordOffset += base;
    visit(i, entry.name, entry.package, entry.extent.recordOffset,
          entry.extent.recordLength, functionSegments(entry.extent),
          entry.index);
  }
  reader.position += payload;
}

void checkFunctionHeader(const Function &function);

void decodeFunctionHeaders(TypeRecords<Function, true> &functions,
                           const std::vector<FunctionRecordExtent> &extents,
                           std::span<const std::uint8_t> bytes,
                           const metadata::DecodeReferences &references,
                           Symbols &symbols,
                           std::vector<FunctionRecordExtent> &bodyRecords,
                           std::vector<FunctionIndex> *indices = nullptr) {
  const std::size_t count = extents.size();
  std::vector<std::string> failures(count);
  std::vector<Symbols> bound(count);
  bodyRecords.resize(count);
  if (indices)
    indices->resize(count);
  auto decode = [&](std::size_t i) {
    try {
      auto recordBytes =
          bytes.subspan(extents[i].recordOffset, extents[i].recordLength);
      const auto segments = functionSegments(extents[i]);
      auto headerBytes =
          recordBytes.subspan(segments.headerOffset, segments.headerLength);
      Reader header(headerBytes, references, true);
      if (indices) {
        auto &index = indices->at(i);
        HeaderIndexReader scanner{{header}, index};
        functionHeader(scanner);
        if (header.position != headerBytes.size())
          reject("trailing data in IR function header");
        index.valid = true;
      } else {
        auto &function = functions.edit(i);
        functionHeader(header, function);
        function.scopes.clear();
        if (header.position != headerBytes.size())
          reject("trailing data in IR function header");
        checkFunctionHeader(function);
      }
      bodyRecords[i] = extents[i];
      bound[i] = std::move(header.symbols);
    } catch (const InvalidArchive &error) {
      failures[i] = error.message;
    }
  };
  const std::size_t workers =
      count < 64
          ? 1
          : std::max<std::size_t>(
                1,
                std::min<std::size_t>(
                    {8, std::thread::hardware_concurrency(), count / 64 + 1}));
  std::vector<std::thread> threads;
  for (std::size_t w = 1; w < workers; ++w)
    threads.emplace_back([&, w] {
      for (std::size_t i = w; i < count; i += workers)
        decode(i);
    });
  for (std::size_t i = 0; i < count; i += workers)
    decode(i);
  for (auto &thread : threads)
    thread.join();
  for (std::size_t i = 0; i < count; ++i) {
    if (!failures[i].empty())
      reject(failures[i]);
    symbols.merge(bound[i]);
  }
}

void checkNumber(const NumericLiteral &literal, Type type,
                 unsigned pointerBits) {
  if ((isFloating(type) && !validFloatingConstant(literal, type)) ||
      ((isInteger(type) || type == Type::Bool || type == Type::Char) &&
       !integerLiteralFits(literal, type, pointerBits)))
    reject("invalid typed IR numeric literal");
}
void checkFunctionHeader(const Function &f) {
  if (f.parameters > limits::locals || f.parameters > f.locals.size())
    reject("invalid IR function shape");
  auto parameters = [&](const auto &entries) {
    for (auto parameter : entries)
      checkParameter(parameter, f.parameters);
  };
  parameters(f.resultSources);
  parameters(f.resultContents);
  parameters(f.callLocalParameters);
  parameters(f.genericResultSources);
  for (auto [source, target] : f.withinFlows)
    checkWithinFlow(source, target, f.parameters);
}
void checkFunctionNumbers(const Function &function, unsigned pointerBits) {
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions)
      if (instruction.numeric)
        checkNumber(*instruction.numeric, instruction.result.type, pointerBits);
}
void checkNumbers(const Program &program) {
  auto pointerBits =
      program.target.pointerBits ? program.target.pointerBits : 64;
  for (std::size_t i = 0; i < program.functions.size(); ++i)
    if (program.functions.isMaterialized(i))
      checkFunctionNumbers(program.functions[i], pointerBits);
  auto constant = [&](auto &self, const StaticConstant &value) -> void {
    if (value.kind == StaticConstant::Kind::Scalar)
      checkNumber(value.scalar, value.type, pointerBits);
    for (const auto &field : value.fields)
      self(self, field);
  };
  for (const auto &storage : program.statics)
    if (storage.initializer)
      constant(constant, *storage.initializer);
}
void checkFunction(const Function &f) {
  checkFunctionHeader(f);
  if (f.values < 0 || static_cast<std::size_t>(f.values) > limits::tokens ||
      f.scopes.empty() || f.scopes.front().parent != -1)
    reject("invalid IR function shape");
  if (!validIndex(f.constructorSelfSlot, f.locals.size(), true) ||
      !validIndex(f.variadicCursor, f.locals.size(), true))
    reject("invalid IR special local reference");
  for (std::size_t i = 1; i < f.scopes.size(); ++i)
    if (!validIndex(f.scopes[i].parent, i))
      reject("invalid IR lexical scope parent");
  for (const auto &local : f.locals)
    if (local.scope < -2 ||
        (local.scope >= 0 && !validIndex(local.scope, f.scopes.size())))
      reject("invalid IR local scope reference");
  std::size_t instructions = 0;
  for (const auto &block : f.blocks) {
    if (block.instructions.size() > limits::tokens - instructions)
      reject("IR function exceeds compiler instruction limit");
    instructions += block.instructions.size();
  }
  if (static_cast<std::size_t>(f.values) != instructions)
    reject("invalid IR function shape");
  std::vector<bool> definitions(instructions);
  for (const auto &block : f.blocks)
    for (const auto &instruction : block.instructions) {
      auto id = instruction.result.id;
      if (!validIndex(id, definitions.size()) || definitions[id])
        reject("invalid or duplicate function-local IR value definition");
      definitions[id] = true;
    }
  auto value = [&](Value v) {
    if (!validIndex(v.id, f.values, true))
      reject("invalid function-local IR value reference");
  };
  auto place = [&](const Place &p) {
    if (!validIndex(p.root, f.locals.size(), true) ||
        (p.root == -1 && !p.fields.empty()))
      reject("invalid function-local IR place reference");
  };
  for (const auto &block : f.blocks) {
    for (const auto &n : block.instructions) {
      value(n.result);
      value(n.target);
      for (auto operand : n.operands)
        if (!validIndex(operand.id, f.values))
          reject("invalid function-local IR operand reference");
      place(n.place);
      for (auto predecessor : n.predecessors)
        if (!validIndex(predecessor, f.blocks.size()))
          reject("invalid IR predecessor reference");
      if (!validIndex(n.scope, f.scopes.size()) ||
          (n.op == Op::ScopeExit && !validIndex(n.number, f.scopes.size())) ||
          n.interfaceMethod < -1 ||
          (n.interfaceMethod >= 0 &&
           static_cast<std::size_t>(n.interfaceMethod) >= limits::witnessSlots))
        reject("invalid IR instruction scope or method reference");
      for (auto p : n.callLocalParameters)
        if (p >= n.operands.size())
          reject("invalid IR call-local parameter reference");
      for (const auto &entry : n.witnessEntries)
        if (entry.method >= limits::witnessSlots)
          reject("invalid IR witness method ordinal");
    }
    value(block.exit.value);
    if ((block.exit.unpredictable && block.exit.kind != Exit::Branch) ||
        block.exit.kind == Exit::None ||
        ((block.exit.kind == Exit::Return || block.exit.kind == Exit::Branch) &&
         !validIndex(block.exit.value.id, f.values)) ||
        !validIndex(block.exit.first, f.blocks.size(), true) ||
        !validIndex(block.exit.second, f.blocks.size(), true) ||
        (continues(block.exit.kind) && block.exit.first < 0) ||
        (block.exit.kind == Exit::Branch &&
         (block.exit.first < 0 || block.exit.second < 0)))
      reject("invalid IR terminator block reference");
  }
  for (const auto &loop : f.arrayLoops) {
    for (auto b : {loop.header, loop.body, loop.step, loop.done})
      if (!validIndex(b, f.blocks.size()))
        reject("invalid IR array-loop block reference");
    for (auto b : loop.blocks)
      if (!validIndex(b, f.blocks.size()))
        reject("invalid IR array-loop member reference");
    if (!validIndex(loop.element, f.values))
      reject("invalid IR array-loop element reference");
    place(loop.source);
    value(loop.index);
  }
}
template <class A, class T> void tail(A &a, T &p) {
  a(p.opaqueAdapters, p.requireEntry, p.libraries, p.target, p.globalAssembly);
  auto functions = [&](auto &entries) {
    if constexpr (A::reading) {
      auto count = a.count(limits::functions);
      entries.clear();
      for (std::uint32_t i = 0; i < count; ++i) {
        auto &entry = entries.emplace_back();
        a(entry.first);
        a.symbol(entry.second, SymbolKind::Function);
      }
    } else {
      a.count(entries.size(), limits::functions);
      for (const auto &entry : entries) {
        a(entry.first);
        a.symbol(entry.second, SymbolKind::Function);
      }
    }
  };
  functions(p.coroutines);
  functions(p.dynamicDropFunctions);
  for (const auto &adapter : p.opaqueAdapters)
    if (adapter.method < 0 ||
        static_cast<std::size_t>(adapter.method) >= limits::witnessSlots ||
        adapter.function < 0)
      reject("invalid IR opaque adapter");
  for (const auto &entry : p.coroutines)
    if (entry.second < 0)
      reject("missing IR coroutine function");
  for (const auto &entry : p.dynamicDropFunctions)
    if (entry.second < 0)
      reject("missing IR dynamic drop function");
}
} // namespace

ProgramLayout programLayout(std::span<const std::uint8_t> bytes) {
  try {
    const metadata::DecodeReferences references;
    Reader reader(bytes, references);
    programVersion(reader);
    ProgramLayout result;
    readFunctionRecords(reader,
                        [&](std::size_t, std::string_view, std::string_view,
                            std::size_t offset, std::size_t,
                            const FunctionSegments &segments,
                            std::span<const std::uint8_t>) {
                          result.bodies.push_back({offset + segments.bodyOffset,
                                                   segments.bodyLength});
                        });
    return result;
  } catch (const InvalidArchive &error) {
    return {{}, error.message};
  }
}

struct LazyFunctionBodies::State {
  std::span<const std::uint8_t> bytes;
  std::shared_ptr<const void> backing;
  std::vector<FunctionRecordExtent> records;
  std::unique_ptr<std::atomic<bool>[]> verified;
  Symbols symbols;
  TargetFacts target;
  FunctionBodyVerifier verifyBody;
  mutable std::mutex mutex;

  std::span<const std::uint8_t> body(std::size_t recordIndex) const {
    if (recordIndex >= records.size())
      reject("IR function body index is out of range");
    const auto &extent = records[recordIndex];
    const auto segments = functionSegments(extent);
    auto bodyBytes = bytes.subspan(extent.recordOffset + segments.bodyOffset,
                                   segments.bodyLength);
    if (verifyBody && !verified[recordIndex].load(std::memory_order_acquire)) {
      if (!verifyBody(recordIndex, bodyBytes))
        reject("IR function body checksum mismatch");
      verified[recordIndex].store(true, std::memory_order_release);
    }
    return bodyBytes;
  }
};

FunctionDecodeResult
LazyFunctionBodies::load(std::size_t recordIndex, const Function &header,
                         const metadata::DecodeReferences &references) const {
  try {
    if (!state)
      reject("IR function body index is out of range");
    auto bodyBytes = summarySegments(state->body(recordIndex)).second;
    Reader body(bodyBytes, references, true);
    Function function = header;
    functionBody(body, function);
    if (body.position != bodyBytes.size())
      reject("trailing data in IR function body");
    checkFunction(function);
    checkFunctionNumbers(
        function, state->target.pointerBits ? state->target.pointerBits : 64);
    {
      std::lock_guard lock(state->mutex);
      state->symbols.merge(body.symbols);
    }
    return {std::move(function), {}};
  } catch (const InvalidArchive &error) {
    return {std::nullopt, error.message};
  }
}

std::span<const std::uint8_t>
LazyFunctionBodies::summary(std::size_t recordIndex, std::string &error) const {
  try {
    if (!state)
      reject("IR function body index is out of range");
    return summarySegments(state->body(recordIndex)).first;
  } catch (const InvalidArchive &failure) {
    error = failure.message;
    return {};
  }
}

EncodeResult
encodeProgram(const Program &program,
              const metadata::EncodeReferences &references,
              std::span<const std::vector<std::uint8_t>> summaries) {
  std::string context;
  try {
    Writer writer(references);
    writer.unsignedInteger(0x5249544d, 4);
    writer.unsignedInteger(17, 4);
    if ((!program.functionPackages.empty() &&
         program.functionPackages.size() != program.functions.size()) ||
        (!program.staticPackages.empty() &&
         program.staticPackages.size() != program.statics.size()))
      reject("misaligned IR package ownership");
    auto functionRecords = [&](const auto &items, const auto &packages) {
      writer.count(items.size(), limits::functions);
      std::set<std::string> identities;
      std::vector<std::uint8_t> payloads;
      for (std::size_t i = 0; i < items.size(); ++i) {
        auto name = writer.identity(SymbolKind::Function,
                                    static_cast<std::uint32_t>(i));
        if (!identities.insert(name).second)
          reject("duplicate IR definition identity");
        writer.text(packages.empty() ? std::string{} : packages[i]);
        context = items[i].name;
        Writer index(references);
        const auto callableIndex = indexFunction(items[i]);
        index.value(callableIndex);
        writer.unsignedInteger(index.bytes.size(), 4);
        if (index.bytes.size() > limits::sourceBytes - writer.bytes.size())
          reject("IR archive exceeds compiler file size limit");
        writer.bytes.insert(writer.bytes.end(), index.bytes.begin(),
                            index.bytes.end());
        auto section = [&](auto encode) {
          Writer record(references, true);
          encode(record, items[i]);
          Writer strings(references);
          strings.count(record.texts.size(), limits::tokens);
          for (const auto *text : record.texts)
            strings.text(*text);
          if (record.bytes.size() > limits::sourceBytes - strings.bytes.size())
            reject("IR record exceeds compiler file size limit");
          strings.bytes.insert(strings.bytes.end(), record.bytes.begin(),
                               record.bytes.end());
          writer.symbols.merge(record.symbols);
          return std::move(strings.bytes);
        };
        auto header = section([](auto &archive, const auto &function) {
          functionHeader(archive, function);
        });
        auto code = section([](auto &archive, const auto &function) {
          functionBody(archive, function);
        });
        Writer body(references);
        const auto *summary = i < summaries.size() ? &summaries[i] : nullptr;
        body.unsignedInteger(summary ? summary->size() : 0, 4);
        if (summary)
          body.bytes.insert(body.bytes.end(), summary->begin(), summary->end());
        if (code.size() > limits::sourceBytes - body.bytes.size())
          reject("IR record exceeds compiler file size limit");
        body.bytes.insert(body.bytes.end(), code.begin(), code.end());
        const auto headerSize = header.size();
        const auto bodySize = body.bytes.size();
        if (headerSize > limits::sourceBytes - payloads.size() ||
            bodySize > limits::sourceBytes - payloads.size() - headerSize)
          reject("IR archive exceeds compiler file size limit");
        writer.unsignedInteger(headerSize, 4);
        writer.unsignedInteger(bodySize, 4);
        payloads.insert(payloads.end(), header.begin(), header.end());
        payloads.insert(payloads.end(), body.bytes.begin(), body.bytes.end());
        context.clear();
      }
      if (payloads.size() > limits::sourceBytes - writer.bytes.size())
        reject("IR archive exceeds compiler file size limit");
      writer.bytes.insert(writer.bytes.end(), payloads.begin(), payloads.end());
    };
    auto records = [&](const auto &items, const auto &packages,
                       SymbolKind kind) {
      writer.count(items.size(), limits::functions);
      std::set<std::string> identities;
      for (std::size_t i = 0; i < items.size(); ++i) {
        auto name = writer.identity(kind, static_cast<std::uint32_t>(i));
        if (!identities.insert(name).second)
          reject("duplicate IR definition identity");
        writer.text(packages.empty() ? std::string{} : packages[i]);
        context = items[i].name;
        Writer record(references, true);
        record.value(items[i]);
        Writer strings(references);
        strings.count(record.texts.size(), limits::tokens);
        for (const auto *text : record.texts)
          strings.text(*text);
        if (record.bytes.size() > limits::sourceBytes - strings.bytes.size())
          reject("IR record exceeds compiler file size limit");
        writer.unsignedInteger(strings.bytes.size() + record.bytes.size(), 4);
        writer.bytes.insert(writer.bytes.end(), strings.bytes.begin(),
                            strings.bytes.end());
        writer.bytes.insert(writer.bytes.end(), record.bytes.begin(),
                            record.bytes.end());
        writer.symbols.merge(record.symbols);
        context.clear();
      }
    };
    for (const auto &function : program.functions)
      checkFunction(function);
    functionRecords(program.functions, program.functionPackages);
    records(program.statics, program.staticPackages, SymbolKind::Static);
    writer.count(program.closureFunctions.size(), limits::functions);
    for (std::size_t i = 0; i < program.closureFunctions.size(); ++i) {
      writer.identity(SymbolKind::Closure, static_cast<std::uint32_t>(i));
      if (program.closureFunctions[i] < 0)
        reject("missing IR closure function");
      writer.symbol(program.closureFunctions[i], SymbolKind::Function);
    }
    tail(writer, program);
    checkNumbers(program);
    return {std::move(writer.bytes), {}};
  } catch (const InvalidArchive &error) {
    return {{}, error.message + (context.empty() ? "" : " in " + context)};
  }
}

DecodeResult decodeProgramLazy(
    std::span<const std::uint8_t> bytes,
    const metadata::DecodeReferences &references, bool,
    std::shared_ptr<const metadata::DecodeReferences> retainedReferences,
    std::shared_ptr<const void> backing, FunctionBodyVerifier verifyBody,
    metadata::ValidationMode validation) {
  try {
    if (retainedReferences && retainedReferences.get() != &references)
      reject("retained IR references do not own the resolver");
    if (validation == metadata::ValidationMode::OnDemand &&
        (!retainedReferences || !verifyBody))
      reject("on-demand IR headers require retained references and "
             "authenticated bodies");
    if (retainedReferences && !backing) {
      auto owned = std::make_shared<const std::vector<std::uint8_t>>(
          bytes.begin(), bytes.end());
      bytes = *owned;
      backing = std::move(owned);
    }
    Reader reader(bytes, references);
    programVersion(reader);
    DecodeResult result;
    auto state = std::make_shared<LazyFunctionBodies::State>();
    auto definitions = validation == metadata::ValidationMode::OnDemand
                           ? std::make_shared<SymbolDefinitions>()
                           : nullptr;
    std::vector<FunctionRecordExtent> functionRecords;
    auto functions = [&](auto &items, auto &packages, auto &names,
                         auto &destinations) {
      std::vector<FunctionRecordExtent> extents;
      std::vector<std::span<const std::uint8_t>> indexRecords;
      std::vector<FunctionIndex> indices;
      readFunctionRecords(
          reader, [&](std::size_t, std::string_view name,
                      std::string_view package, std::size_t offset,
                      std::size_t length, const FunctionSegments &segments,
                      std::span<const std::uint8_t> indexBytes) {
            const auto destination =
                reader.identity(SymbolKind::Function, name, !definitions)
                    .second;
            if (definitions)
              definitions->bindings.push_back(
                  {SymbolKind::Function, destination, name});
            names.emplace_back(name);
            destinations.push_back(destination);
            packages.emplace_back(package);
            extents.push_back({offset, length, segments.bodyLength});
            indexRecords.push_back(indexBytes);
            Reader index(indexBytes, references);
            index.value(indices.emplace_back());
            if (index.position != indexBytes.size())
              reject("trailing data in IR function index");
            functionRecords.push_back({offset, length, segments.bodyLength});
            if (!retainedReferences)
              items.push_uninitialized();
          });
      if (!definitions) {
        auto slots = destinations;
        std::sort(slots.begin(), slots.end());
        if (std::adjacent_find(slots.begin(), slots.end()) != slots.end())
          reject("duplicate or aliased IR definition identity");
      }
      if (validation == metadata::ValidationMode::Eager) {
        std::vector<FunctionIndex> checkedIndices;
        decodeFunctionHeaders(items, extents, bytes, references, reader.symbols,
                              functionRecords,
                              retainedReferences ? &checkedIndices : nullptr);
        for (std::size_t i = 0; i < indices.size(); ++i)
          if (!sameFunctionIndex(indices[i], retainedReferences
                                                 ? checkedIndices[i]
                                                 : indexFunction(items[i])))
            reject("IR function index does not match its callable header");
      }
      if (retainedReferences) {
        result.program.functionIndex = std::move(indices);
        const auto count = extents.size();
        auto loader = std::make_shared<
            const TypeRecords<Function, true>::Loader>(
            [bytes, extents = std::move(extents), retainedReferences, backing,
             state, indexRecords = std::move(indexRecords)](std::size_t index) {
              try {
                TypeRecords<Function, true> decoded;
                decoded.push_uninitialized();
                Symbols symbols;
                std::vector<FunctionRecordExtent> records;
                decodeFunctionHeaders(decoded, {extents.at(index)}, bytes,
                                      *retainedReferences, symbols, records);
                Reader directory(indexRecords.at(index), *retainedReferences);
                FunctionIndex expected;
                directory.value(expected);
                if (!sameFunctionIndex(expected, indexFunction(decoded[0])))
                  reject(
                      "IR function index does not match its callable header");
                {
                  std::lock_guard lock(state->mutex);
                  state->symbols.merge(symbols);
                }
                return std::move(decoded.edit(0));
              } catch (const InvalidArchive &error) {
                throw metadata::InvalidMetadata(error.message);
              }
            });
        items.deferPrefix(count, std::move(loader));
      }
    };
    auto records = [&](auto &items, auto &packages, auto &names,
                       auto &destinations, SymbolKind kind) {
      auto count = reader.count(limits::functions);
      std::set<std::string> identities;
      std::set<std::uint32_t> slots;
      std::vector<std::pair<std::size_t, std::size_t>> extents;
      extents.reserve(count);
      for (std::uint32_t i = 0; i < count; ++i) {
        auto [name, destination] = reader.identity(kind, !definitions);
        if (definitions)
          definitions->bindings.push_back({kind, destination, name});
        if (!identities.emplace(name).second ||
            !slots.insert(destination).second)
          reject("duplicate or aliased IR definition identity");
        names.emplace_back(name);
        destinations.push_back(destination);
        reader.text(packages.emplace_back());
        auto length = reader.unsignedInteger(4);
        if (length > bytes.size() - reader.position)
          reject("truncated IR record");
        extents.emplace_back(reader.position, length);
        reader.position += length;
        items.emplace_back();
      }
      decodeRecords(items, extents, bytes, references, reader.symbols);
    };
    auto &program = result.program;
    functions(program.functions, program.functionPackages,
              result.functionIdentities, result.functionDestinations);
    records(program.statics, program.staticPackages, result.staticIdentities,
            result.staticDestinations, SymbolKind::Static);
    auto count = reader.count(limits::functions);
    std::set<std::string> identities;
    std::set<std::uint32_t> slots;
    for (std::uint32_t i = 0; i < count; ++i) {
      auto [name, slot] = reader.identity(SymbolKind::Closure, !definitions);
      if (definitions)
        definitions->bindings.push_back({SymbolKind::Closure, slot, name});
      if (!identities.emplace(name).second || !slots.insert(slot).second)
        reject("duplicate or aliased IR closure identity");
      int function;
      reader.symbol(function, SymbolKind::Function);
      if (function < 0)
        reject("missing IR closure function");
      result.closureFunctions.emplace_back(slot, function);
    }
    if (definitions) {
      definitions->finish();
      for (const auto &[key, name] : reader.symbols.identities)
        definitions->contains(key.first, key.second, name);
      reader.symbols.definitions = std::move(definitions);
    }
    tail(reader, program);
    if (reader.position != bytes.size())
      reject("trailing data in IR archive");
    checkNumbers(program);
    state->bytes = bytes;
    state->backing = std::move(backing);
    state->verifyBody = std::move(verifyBody);
    result.functionBodySizes.reserve(functionRecords.size());
    for (const auto &record : functionRecords)
      result.functionBodySizes.push_back(record.bodyLength);
    state->records = std::move(functionRecords);
    state->verified =
        std::make_unique<std::atomic<bool>[]>(state->records.size());
    state->symbols = std::move(reader.symbols);
    state->target = program.target;
    result.lazyFunctions = std::shared_ptr<LazyFunctionBodies>(
        new LazyFunctionBodies(std::move(state)));
    return result;
  } catch (const InvalidArchive &error) {
    DecodeResult result;
    result.error = error.message;
    return result;
  }
}

DecodeResult decodeProgram(std::span<const std::uint8_t> bytes,
                           const metadata::DecodeReferences &references) {
  auto result = decodeProgramLazy(bytes, references);
  if (!result)
    return result;
  for (std::size_t i = 0; i < result.program.functions.size(); ++i) {
    auto decoded =
        result.lazyFunctions->load(i, result.program.functions[i], references);
    if (!decoded) {
      DecodeResult failed;
      failed.error = std::move(decoded.error);
      return failed;
    }
    result.program.functions.edit(i) = std::move(*decoded.function);
  }
  result.lazyFunctions.reset();
  return result;
}
} // namespace mettle::ir
