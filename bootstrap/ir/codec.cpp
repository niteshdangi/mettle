#include "ir/codec.h"
#include "support/limits.h"
#include <algorithm>
#include <bit>
#include <limits>
#include <map>
#include <set>
#include <type_traits>

namespace mettle::ir {
namespace {
using metadata::SymbolKind;
struct InvalidArchive {
  std::string message;
};
[[noreturn]] void reject(std::string message) {
  throw InvalidArchive{std::move(message)};
}
template <class E> constexpr unsigned lastTag() {
  if constexpr (std::is_same_v<E, Access>)
    return static_cast<unsigned>(Access::Mut);
  else if constexpr (std::is_same_v<E, InlineHint>)
    return static_cast<unsigned>(InlineHint::Never);
  else if constexpr (std::is_same_v<E, Op>)
    return static_cast<unsigned>(Op::TextLiteral);
  else if constexpr (std::is_same_v<E, Exit>)
    return static_cast<unsigned>(Exit::Suspend);
  else if constexpr (std::is_same_v<E, ParameterMode>)
    return static_cast<unsigned>(ParameterMode::Mut);
  else if constexpr (std::is_same_v<E, StorageDuration>)
    return static_cast<unsigned>(StorageDuration::Static);
  else if constexpr (std::is_same_v<E, Projection::Kind>)
    return static_cast<unsigned>(Projection::Kind::Opaque);
  else if constexpr (std::is_same_v<E, StaticConstant::Kind>)
    return static_cast<unsigned>(StaticConstant::Kind::Repeat);
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
    a(r.kind, r.value, r.first, r.second, r.span);
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
  } else if constexpr (std::is_same_v<R, Function>) {
    a(r.name, r.result, r.parameters);
    a.sequence(r.locals, limits::locals);
    a.sequence(r.blocks, limits::cfgBlocks);
    a(r.values);
    a.sequence(r.scopes, limits::tokens);
    a(r.resultSources, r.resultContents, r.withinFlows, r.externalName,
      r.twoPhaseReceiver, r.constructorSelfSlot, r.indirectContract,
      r.callLocalParameters, r.genericParameters, r.declarationOnly,
      r.genericResultSources, r.interfaceBounds, r.unpinBounds,
      r.regionSignature, r.interfaceResult, r.genericEqualities,
      r.unsafeFunction, r.abi, r.foreignDeclaration, r.exportedDefinition,
      r.variadic, r.floatingPolicy, r.variadicCursor, r.targetFeatures,
      r.nakedAssembly, r.arrayLoops, r.coroutine, r.span, r.inlineHint);
  } else if constexpr (std::is_same_v<R, StaticConstant>) {
    if (++a.constantDepth > limits::typeDepth)
      reject("static constant nesting exceeds compiler limit");
    a(r.kind, r.type, r.scalar);
    a.sequence(r.fields, limits::cleanupPlaces);
    a.symbol(r.symbol, r.kind == StaticConstant::Kind::Function
                           ? SymbolKind::Function
                           : SymbolKind::Static);
    a(r.projections, r.selection, r.text);
    if (((r.kind == StaticConstant::Kind::Address ||
          r.kind == StaticConstant::Kind::Function) &&
         r.symbol < 0) ||
        (r.kind == StaticConstant::Kind::Repeat && r.fields.size() != 1) ||
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
template <class T> struct IsSet : std::false_type {};
template <class T> struct IsSet<std::set<T>> : std::true_type {};
template <class T> struct IsPair : std::false_type {};
template <class T, class U> struct IsPair<std::pair<T, U>> : std::true_type {};

struct Symbols {
  std::map<std::pair<SymbolKind, std::uint32_t>, std::string> identities;
  std::map<std::pair<SymbolKind, std::string>, std::uint32_t> indices;
  void bind(SymbolKind kind, std::uint32_t index, const std::string &name) {
    auto [identity, newIdentity] =
        identities.emplace(std::pair{kind, index}, name);
    auto [slot, newSlot] = indices.emplace(std::pair{kind, name}, index);
    if ((!newIdentity && identity->second != name) ||
        (!newSlot && slot->second != index))
      reject("inconsistent or aliased IR logical symbol mapping");
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
  explicit Writer(const metadata::EncodeReferences &references)
      : references(references) {}
  void unsignedInteger(std::uint64_t number, unsigned width) {
    if (bytes.size() > limits::sourceBytes - width)
      reject("IR archive exceeds compiler file size limit");
    for (unsigned i = 0; i < width; ++i)
      bytes.push_back(static_cast<std::uint8_t>(number >> (i * 8)));
  }
  void boolean(bool v) { unsignedInteger(v, 1); }
  void text(const std::string &v) {
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
  Reader(std::span<const std::uint8_t> bytes,
         const metadata::DecodeReferences &references)
      : references(references), bytes(bytes) {
    if (bytes.size() > limits::sourceBytes)
      reject("IR archive exceeds compiler file size limit");
  }
  std::uint64_t unsignedInteger(unsigned width) {
    if (width > bytes.size() - position)
      reject("truncated IR archive");
    std::uint64_t result = 0;
    for (unsigned i = 0; i < width; ++i)
      result |= std::uint64_t{bytes[position++]} << (i * 8);
    return result;
  }
  void boolean(bool &v) {
    auto bit = unsignedInteger(1);
    if (bit > 1)
      reject("invalid IR boolean");
    v = bit != 0;
  }
  void text(std::string &v) {
    auto count = unsignedInteger(4);
    if (count > bytes.size() - position)
      reject("truncated IR string");
    v.assign(reinterpret_cast<const char *>(bytes.data() + position), count);
    position += count;
  }
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
    metadata::SourceReference source;
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
  std::pair<std::string, std::uint32_t> identity(SymbolKind kind) {
    std::string name;
    text(name);
    auto ref = references.symbol ? references.symbol(kind, name) : std::nullopt;
    if (name.empty() || !ref ||
        *ref > static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
      reject("unmapped or invalid IR logical symbol");
    symbols.bind(kind, *ref, name);
    return {std::move(name), *ref};
  }
  void symbol(int &id, SymbolKind kind) {
    bool present;
    boolean(present);
    id = present ? static_cast<int>(identity(kind).second) : -1;
  }
};

bool validIndex(int index, std::size_t size, bool optional = false) {
  return (optional && index == -1) ||
         (index >= 0 && static_cast<std::size_t>(index) < size);
}
void checkNumber(const NumericLiteral &literal, Type type,
                 unsigned pointerBits) {
  if ((isFloating(type) && !validFloatingConstant(literal, type)) ||
      ((isInteger(type) || type == Type::Bool || type == Type::Char) &&
       !integerLiteralFits(literal, type, pointerBits)))
    reject("invalid typed IR numeric literal");
}
void checkNumbers(const Program &program) {
  auto pointerBits =
      program.target.pointerBits ? program.target.pointerBits : 64;
  for (const auto &function : program.functions)
    for (const auto &block : function.blocks)
      for (const auto &instruction : block.instructions)
        if (instruction.numeric)
          checkNumber(*instruction.numeric, instruction.result.type,
                      pointerBits);
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
  std::size_t instructions = 0;
  for (const auto &block : f.blocks) {
    if (block.instructions.size() > limits::tokens - instructions)
      reject("IR function exceeds compiler instruction limit");
    instructions += block.instructions.size();
  }
  if (f.values < 0 || static_cast<std::size_t>(f.values) > limits::tokens ||
      static_cast<std::size_t>(f.values) != instructions ||
      f.parameters > f.locals.size() || f.scopes.empty() ||
      f.scopes.front().parent != -1)
    reject("invalid IR function shape");
  std::vector<bool> definitions(instructions);
  for (const auto &block : f.blocks)
    for (const auto &instruction : block.instructions) {
      auto id = instruction.result.id;
      if (!validIndex(id, definitions.size()) || definitions[id])
        reject("invalid or duplicate function-local IR value definition");
      definitions[id] = true;
    }
  for (std::size_t i = 1; i < f.scopes.size(); ++i)
    if (!validIndex(f.scopes[i].parent, i))
      reject("invalid IR lexical scope parent");
  auto value = [&](Value v) {
    if (!validIndex(v.id, f.values, true))
      reject("invalid function-local IR value reference");
  };
  auto place = [&](const Place &p) {
    if (!validIndex(p.root, f.locals.size(), true) ||
        (p.root == -1 && !p.fields.empty()))
      reject("invalid function-local IR place reference");
  };
  auto parameters = [&](const auto &entries) {
    for (auto p : entries)
      if (p >= f.parameters)
        reject("invalid IR parameter reference");
  };
  parameters(f.resultSources);
  parameters(f.resultContents);
  parameters(f.callLocalParameters);
  for (auto [source, target] : f.withinFlows)
    if (source >= f.parameters || target >= f.parameters)
      reject("invalid IR within-flow parameter reference");
  parameters(f.genericResultSources);
  if (!validIndex(f.constructorSelfSlot, f.locals.size(), true) ||
      !validIndex(f.variadicCursor, f.locals.size(), true))
    reject("invalid IR special local reference");
  for (const auto &local : f.locals)
    if (local.scope < -2 ||
        (local.scope >= 0 && !validIndex(local.scope, f.scopes.size())))
      reject("invalid IR local scope reference");
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
    if (block.exit.kind == Exit::None ||
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

EncodeResult encodeProgram(const Program &program,
                           const metadata::EncodeReferences &references) {
  std::string context;
  try {
    Writer writer(references);
    writer.unsignedInteger(0x5249544d, 4);
    writer.unsignedInteger(1, 4);
    if ((!program.functionPackages.empty() &&
         program.functionPackages.size() != program.functions.size()) ||
        (!program.staticPackages.empty() &&
         program.staticPackages.size() != program.statics.size()))
      reject("misaligned IR package ownership");
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
        writer.value(items[i]);
        context.clear();
      }
    };
    for (const auto &function : program.functions)
      checkFunction(function);
    records(program.functions, program.functionPackages, SymbolKind::Function);
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

DecodeResult decodeProgram(std::span<const std::uint8_t> bytes,
                           const metadata::DecodeReferences &references) {
  try {
    Reader reader(bytes, references);
    if (reader.unsignedInteger(4) != 0x5249544d ||
        reader.unsignedInteger(4) != 1)
      reject("unsupported IR archive format or version");
    DecodeResult result;
    auto records = [&](auto &items, auto &packages, auto &names,
                       auto &destinations, SymbolKind kind) {
      auto count = reader.count(limits::functions);
      std::set<std::string> identities;
      std::set<std::uint32_t> slots;
      for (std::uint32_t i = 0; i < count; ++i) {
        auto [name, destination] = reader.identity(kind);
        if (!identities.insert(name).second ||
            !slots.insert(destination).second)
          reject("duplicate or aliased IR definition identity");
        names.push_back(std::move(name));
        destinations.push_back(destination);
        reader.text(packages.emplace_back());
        reader.value(items.emplace_back());
      }
    };
    auto &program = result.program;
    records(program.functions, program.functionPackages,
            result.functionIdentities, result.functionDestinations,
            SymbolKind::Function);
    records(program.statics, program.staticPackages, result.staticIdentities,
            result.staticDestinations, SymbolKind::Static);
    auto count = reader.count(limits::functions);
    std::set<std::string> identities;
    std::set<std::uint32_t> slots;
    for (std::uint32_t i = 0; i < count; ++i) {
      auto [name, slot] = reader.identity(SymbolKind::Closure);
      if (!identities.insert(name).second || !slots.insert(slot).second)
        reject("duplicate or aliased IR closure identity");
      int function;
      reader.symbol(function, SymbolKind::Function);
      if (function < 0)
        reject("missing IR closure function");
      result.closureFunctions.emplace_back(slot, function);
    }
    tail(reader, program);
    if (reader.position != bytes.size())
      reject("trailing data in IR archive");
    for (const auto &function : program.functions)
      checkFunction(function);
    checkNumbers(program);
    return result;
  } catch (const InvalidArchive &error) {
    DecodeResult result;
    result.error = error.message;
    return result;
  }
}
} // namespace mettle::ir
