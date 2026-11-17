#include "semantics/library.h"
#include "support/limits.h"
#include "types/layout.h"
#include "types/project.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <utility>

namespace mettle {
std::array<const ImportedDeclarations::TypeTable *, 5>
ImportedDeclarations::typeTables() const {
  return {&products, &aliases, &interfaces, &implementations, &associated};
}

void ImportedDeclarations::indexTypes() {
  auto tables = typeTables();
  for (std::size_t i = 0; i < tables.size(); ++i) {
    auto &index = typeIndices[i];
    index.clear();
    for (std::size_t j = 0; j < tables[i]->size(); ++j) {
      auto span = (*tables[i])[j]->span;
      index.emplace(std::tuple{span.source, span.begin, span.end}, j);
    }
  }
}

std::shared_ptr<const ImportedTypeDeclaration>
ImportedDeclarations::findType(Span span, const TypeTable &items) const {
  auto tables = typeTables();
  for (std::size_t i = 0; i < tables.size(); ++i) {
    if (tables[i] != &items || typeIndices[i].empty())
      continue;
    auto found = typeIndices[i].find({span.source, span.begin, span.end});
    return found == typeIndices[i].end() ? nullptr : items.at(found->second);
  }
  auto found = std::find_if(items.begin(), items.end(), [&](const auto &item) {
    return item->span.source == span.source && item->span.begin == span.begin &&
           item->span.end == span.end;
  });
  return found == items.end() ? nullptr : *found;
}

std::string ImportedDeclarations::indexDeclarations(const Module *module) {
  auto result = std::make_shared<Index>();
  auto remember = [&](Span span) {
    result->spans.emplace(span.source, span.begin, span.end);
  };
  auto expression = [&](const std::shared_ptr<CheckedExpression> &body) {
    if (!body || body->load || !body->syntax.get() ||
        result->expressions.contains(body.get()))
      return;
    result->expressions.emplace(body.get(), body);
    for (const auto &[node, facts] : body->facts) {
      result->nodes.emplace(node, body.get());
      if (node->kind == Kind::Cast)
        result->annotations.emplace(&node->annotation, facts.type);
    }
  };
  for (const auto &[position, function] : functions) {
    auto span = function.span();
    remember(span);
    if (function.isMaterialized()) {
      expression(function->body);
      for (const auto &argument : function->defaults)
        expression(argument);
    }
    if (!module)
      continue;
    if (position >= module->functions.size())
      return "checked function does not match its mounted declaration";
    const auto &syntax = module->functions[position];
    if (syntax.span.source != span.source || syntax.span.begin != span.begin ||
        syntax.span.end != span.end)
      return "checked function does not match its mounted declaration";
    if (syntax.body.get())
      return "imported runtime declaration unexpectedly has a source body";
    if (function.defaultCount() != syntax.parameters.size() ||
        function.parameterCount() < syntax.parameters.size())
      return "checked parameter contract is invalid";
    for (std::size_t p = 0; p < function.defaultCount(); ++p)
      if (function.hasDefault(p) != syntax.parameters[p].compiledDefault)
        return "checked default does not match its mounted declaration";
    if (!syntax.item.checkedImport)
      continue;
    auto declaration = module->functions.shared(position);
    result->annotations.emplace(&declaration->annotation,
                                function.resultType());
    result->annotations.emplace(&declaration->error, function.errorType());
    for (std::size_t p = 0;
         p < declaration->parameters.size() && p < function.parameterCount();
         ++p)
      result->annotations.emplace(&declaration->parameters[p].annotation,
                                  function.parameterType(p));
    result->functions.emplace(position, std::move(declaration));
  }
  for (const auto *items : typeTables())
    for (const auto &item : *items)
      remember(item->span);
  if (module)
    for (const auto &[position, facts] : statics) {
      (void)facts;
      if (position < module->statics.size())
        remember(module->statics[position].span);
    }
  std::multimap<std::tuple<SourceId, std::size_t, std::size_t>, std::size_t>
      implementationSpans;
  auto spanKey = [](Span span) {
    return std::tuple{span.source, span.begin, span.end};
  };
  if (module)
    for (std::size_t i = 0; i < module->implementations.size(); ++i)
      implementationSpans.emplace(spanKey(module->implementations[i].span), i);
  for (const auto &constant : inherentConstants) {
    expression(constant.initializer);
    if (!module)
      continue;
    auto [found, last] =
        implementationSpans.equal_range(spanKey(constant.implementation));
    if (found == last)
      return "checked associated constant has no mounted implementation";
    if (std::next(found) != last) {
      result->constants.emplace_back();
      continue;
    }
    const auto &owner = module->implementations[found->second];
    auto declaration = std::find_if(
        owner.associated.begin(), owner.associated.end(),
        [&](const auto &item) {
          return spanKey(item.span) == spanKey(constant.declaration);
        });
    if (declaration == owner.associated.end() || !declaration->constant ||
        (constant.initializer && declaration->constantValue &&
         spanKey(declaration->constantValue->span) !=
             spanKey(constant.initializer->span)))
      return "checked associated constant does not match its initializer";
    result->constants.push_back(
        {found->second,
         static_cast<std::size_t>(declaration - owner.associated.begin()),
         owner.item.checkedImport
             ? module->implementations.shared(found->second)
             : nullptr});
  }
  if (module)
    for (std::size_t i = 0; i < module->aliases.size(); ++i)
      if (module->aliases[i].item.checkedImport)
        if (auto contract = findType(module->aliases[i].span, aliases)) {
          auto declaration = module->aliases.shared(i);
          result->annotations.emplace(&declaration->target, contract->type);
          result->aliases.push_back(std::move(declaration));
        }
  index = std::move(result);
  return {};
}

namespace {
struct FunctionHeader {
  Span span;
  ImportedFunction::SignatureIndex signature;
  bool unsafeFunction = false, hasBody = false;
  std::optional<Span> body;
  std::vector<std::optional<Span>> defaults;
};
using InterfaceMethods = std::array<std::vector<std::optional<std::size_t>>, 2>;

struct Hygiene {
  std::map<std::uint64_t, std::uint64_t> binders;
  std::map<std::uint64_t, SyntaxContextPtr> contexts;
};
struct Remapping {
  std::unordered_map<std::uint32_t, Type> types;
  std::map<std::string, std::unordered_map<std::uint64_t, Span>> sources;
  std::map<metadata::SymbolKind,
           std::map<std::string, std::uint32_t, std::less<>>>
      symbols;
  static std::uint64_t position(const metadata::SourceReference &source) {
    return (std::uint64_t(source.begin) << 32) | source.end;
  }
};
class Archive {
public:
  explicit Archive(
      const metadata::EncodeReferences &references, TypeStore &types,
      std::shared_ptr<Hygiene> hygiene = std::make_shared<Hygiene>())
      : types(&types), encode(&references), hygiene(std::move(hygiene)),
        ownedRevisions(std::make_shared<std::vector<std::string>>()),
        revisions(ownedRevisions) {}
  Archive(std::span<const std::uint8_t> input,
          const metadata::DecodeReferences &references, TypeStore *types,
          std::shared_ptr<const std::vector<std::string>> sourceRevisions = {})
      : types(types), input(input), decode(&references),
        ownedRevisions(sourceRevisions
                           ? nullptr
                           : std::make_shared<std::vector<std::string>>()),
        revisions(sourceRevisions ? std::move(sourceRevisions)
                                  : ownedRevisions) {}
  bool reading() const { return decode != nullptr; }
  std::shared_ptr<Hygiene> hygieneState() const { return hygiene; }
  std::shared_ptr<const std::vector<std::string>> sourceRevisions() const {
    return revisions;
  }
  bool good() const { return error.empty(); }
  void fail(std::string message) {
    if (error.empty())
      error = std::move(message);
  }
  template <typename... T> void operator()(T &...values) {
    (value(values), ...);
  }
  template <typename T> void discard(T &item) {
    auto previous = std::exchange(discarding, true);
    value(item);
    discarding = previous;
  }
  template <typename T> void keep(T &item) {
    auto previous = std::exchange(discarding, false);
    value(item);
    discarding = previous;
  }
  std::size_t collectionSize() {
    std::uint64_t count = 0;
    value(count);
    if (!good() || count > input.size() - offset) {
      fail("declaration collection exceeds its payload");
      return 0;
    }
    return static_cast<std::size_t>(count);
  }
  template <typename T> std::size_t discardCollection(std::vector<T> &) {
    auto count = collectionSize();
    for (std::size_t i = 0; i < count && good(); ++i) {
      T item{};
      discard(item);
    }
    return count;
  }
  template <typename T> void value(const T &item) {
    value(const_cast<T &>(item));
  }
  template <typename T> void value(T &item) {
    if (!good())
      return;
    if constexpr (std::is_integral_v<T>) {
      // LEB128; signed values are zigzag-encoded so small magnitudes stay
      // short.
      constexpr bool isSigned = std::is_signed_v<T>;
      if (reading()) {
        std::uint64_t bits = 0;
        unsigned shift = 0;
        for (;;) {
          if (offset >= input.size() || shift > 63) {
            fail("truncated declaration integer");
            return;
          }
          auto byte = input[offset++];
          if (shift == 63 && byte > 1) {
            fail("declaration integer exceeds its representation");
            return;
          }
          bits |= std::uint64_t(byte & 0x7f) << shift;
          if (!(byte & 0x80))
            break;
          shift += 7;
        }
        if constexpr (std::is_same_v<T, bool>) {
          if (bits > 1)
            fail("invalid declaration boolean");
          item = bits != 0;
        } else if constexpr (isSigned) {
          auto decoded = static_cast<std::int64_t>(bits >> 1) ^
                         -static_cast<std::int64_t>(bits & 1);
          if (decoded < std::numeric_limits<T>::min() ||
              decoded > std::numeric_limits<T>::max())
            fail("declaration integer exceeds its representation");
          item = static_cast<T>(decoded);
        } else {
          if (bits > std::numeric_limits<T>::max())
            fail("declaration integer exceeds its representation");
          item = static_cast<T>(bits);
        }
      } else {
        std::uint64_t bits = static_cast<std::uint64_t>(item);
        if constexpr (isSigned) {
          auto number = static_cast<std::int64_t>(item);
          bits = (static_cast<std::uint64_t>(number) << 1) ^
                 static_cast<std::uint64_t>(number >> 63);
        }
        while (bits >= 0x80) {
          output.push_back(static_cast<std::uint8_t>(bits | 0x80));
          bits >>= 7;
        }
        output.push_back(static_cast<std::uint8_t>(bits));
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
      if (!discarding)
        text.assign(reinterpret_cast<const char *>(input.data() + offset),
                    static_cast<std::size_t>(size));
      offset += static_cast<std::size_t>(size);
    } else
      output.insert(output.end(), text.begin(), text.end());
  }
  template <typename T> void value(std::vector<T> &items) {
    if (reading() && discarding) {
      discardCollection(items);
      return;
    }
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > input.size() - offset) {
        fail("declaration collection exceeds its payload");
        return;
      }
      items.resize(static_cast<std::size_t>(count));
    }
    for (auto &item : items)
      value(item);
  }
  void value(std::vector<NodeOwner> &items) {
    if (!scanningExpression) {
      value<NodeOwner>(items);
      return;
    }
    std::uint64_t count = 0;
    value(count);
    if (!good())
      return;
    if (count > input.size() - offset) {
      fail("declaration collection exceeds its payload");
      return;
    }
    scanNodes.back().children = static_cast<std::size_t>(count);
    for (std::uint64_t i = 0; i < count && good(); ++i) {
      bool present = false;
      value(present);
      if (!present) {
        fail("checked expression contains an empty child");
        return;
      }
      scanPrimary = scanNodes.back().primary;
      Node item;
      value(item);
    }
  }
  template <typename T> void value(TypeRecords<T> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (!reading()) {
      for (const auto &item : std::as_const(items))
        value(item);
      return;
    }
    if (count > input.size() - offset) {
      fail("declaration collection exceeds its payload");
      return;
    }
    for (std::uint64_t i = 0; i < count && good(); ++i) {
      T item;
      value(item);
      items.push_back(std::move(item));
    }
  }
  template <typename T> void value(Declarations<T> &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (!reading()) {
      for (const auto &item : items)
        value(item);
      return;
    }
    if (count > input.size() - offset) {
      fail("declaration collection exceeds its payload");
      return;
    }
    items.reserve(static_cast<std::size_t>(count));
    for (std::uint64_t i = 0; i < count && good(); ++i) {
      T item;
      value(item);
      items.push_back(std::move(item));
    }
  }
  void value(ImportedDeclarations::TypeTable &items) {
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > input.size() - offset) {
        fail("declaration collection exceeds its payload");
        return;
      }
      items.reserve(static_cast<std::size_t>(count));
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        auto item = std::make_shared<ImportedTypeDeclaration>();
        value(*item);
        items.push_back(std::move(item));
      }
    } else
      for (const auto &item : items)
        value(*item);
  }
  void value(std::vector<bool> &items) {
    if (reading() && discarding) {
      discardCollection(items);
      return;
    }
    std::uint64_t count = items.size();
    value(count);
    if (!good())
      return;
    if (reading()) {
      if (count > input.size() - offset) {
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
      if (count > (input.size() - offset) / 2) {
        fail("declaration map exceeds its payload");
        return;
      }
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        K key{};
        V item{};
        keep(key);
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
      if (count > (input.size() - offset) / 2) {
        fail("hygienic declaration map exceeds its payload");
        return;
      }
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        std::string spelling;
        SyntaxContextPtr context;
        T item{};
        keep(spelling);
        (*this)(context, item);
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
    keep(ordered);
    if (reading())
      for (auto &item : ordered)
        if (!items.insert(std::move(item)).second)
          fail("duplicate declaration set item");
  }
  void symbol(metadata::SymbolKind kind, std::uint32_t &index) {
    if (reading()) {
      std::uint64_t size = 0;
      value(size);
      if (!good())
        return;
      if (size > input.size() - offset) {
        fail("truncated declaration string");
        return;
      }
      std::string_view identity(
          reinterpret_cast<const char *>(input.data() + offset),
          static_cast<std::size_t>(size));
      offset += static_cast<std::size_t>(size);
      auto resolved =
          decode->symbol ? decode->symbol(kind, identity) : std::nullopt;
      if (!resolved)
        fail("unknown logical declaration symbol: " + std::string(identity));
      else
        index = *resolved;
      return;
    }
    std::string identity;
    auto resolved = encode->symbol ? encode->symbol(kind, index) : std::nullopt;
    if (!resolved || resolved->empty()) {
      fail("unresolved logical declaration symbol");
      return;
    }
    identity = std::move(*resolved);
    keep(identity);
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
    if (!reading()) {
      auto resolved = encode->source ? encode->source(span) : std::nullopt;
      if (!resolved) {
        fail("unresolved declaration source revision");
        return;
      }
      if (resolved->begin > resolved->end) {
        fail("invalid declaration source extent");
        return;
      }
      auto [found, inserted] =
          revisionOrdinals.try_emplace(resolved->revision, revisions->size());
      std::uint64_t reference = (std::uint64_t(found->second) << 1) | inserted;
      value(reference);
      if (inserted) {
        ownedRevisions->push_back(resolved->revision);
        value(resolved->revision);
      }
      (*this)(resolved->begin, resolved->end);
      return;
    }
    std::uint64_t reference = 0;
    value(reference);
    auto ordinal = reference >> 1;
    if (good() && (reference & 1)) {
      std::string revision;
      keep(revision);
      if (!good())
        return;
      if (ownedRevisions) {
        if (ordinal != revisions->size()) {
          fail("invalid declaration source index");
          return;
        }
        ownedRevisions->push_back(std::move(revision));
      } else if (ordinal >= revisions->size() ||
                 (*revisions)[ordinal] != revision) {
        fail("conflicting declaration source revision");
        return;
      }
    }
    if (!good())
      return;
    if (ordinal >= revisions->size()) {
      fail("unknown declaration source index");
      return;
    }
    if (ordinal != currentRevision) {
      sourceReference.revision = (*revisions)[ordinal];
      currentRevision = ordinal;
    }
    (*this)(sourceReference.begin, sourceReference.end);
    if (sourceReference.begin > sourceReference.end)
      fail("invalid declaration source extent");
    if (good()) {
      auto resolved =
          decode->source ? decode->source(sourceReference) : std::nullopt;
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
      const auto resolved =
          types ? types->unitViewRegion(carrier) : std::nullopt;
      if (!resolved)
        fail("invalid declaration region reference");
      else
        region = *resolved;
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
    if (reading() && discarding && !scanningExpression) {
      discarding = false;
      scanSyntax();
      discarding = true;
      return;
    }
    bool present = node.get() != nullptr;
    value(present);
    if (!present || !good())
      return;
    if (scanningExpression) {
      Node item;
      value(item);
    } else if (reading()) {
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
  std::size_t position() const { return offset; }
  std::span<const std::uint8_t> readBlock() {
    std::uint64_t size = 0;
    value(size);
    if (!good() || size > input.size() - offset) {
      fail("checked function record exceeds its payload");
      return {};
    }
    auto block = input.subspan(offset, static_cast<std::size_t>(size));
    offset += block.size();
    return block;
  }
  void writeBlock(std::span<const std::uint8_t> block) {
    auto size = static_cast<std::uint64_t>(block.size());
    value(size);
    output.insert(output.end(), block.begin(), block.end());
  }
  std::pair<std::size_t, Span> scanSyntax() {
    scanningExpression = true;
    scanPrimary = true;
    scannedNodes = 0;
    NodeOwner ignored;
    value(ignored);
    scanningExpression = false;
    return {scannedNodes, scannedSpan};
  }
  std::function<void(CheckedExpression &, std::size_t, std::size_t)>
      deferExpression;
  const metadata::DecodeReferences *expressionReferences = nullptr;
  template <typename T> void record(T &item);
  std::vector<std::uint8_t> output;
  std::string error;
  TypeStore *types;

private:
  friend void expression(Archive &, std::shared_ptr<CheckedExpression> &);
  const metadata::EncodeReferences *encode = nullptr;
  std::span<const std::uint8_t> input;
  const metadata::DecodeReferences *decode = nullptr;
  std::size_t offset = 0;
  unsigned depth = 0;
  bool scanningExpression = false, scanPrimary = false, discarding = false;
  std::size_t scannedNodes = 0;
  Span scannedSpan{};
  struct ScanNode {
    std::size_t children = 0;
    bool primary = false, root = false;
  };
  std::vector<ScanNode> scanNodes;
  std::shared_ptr<Hygiene> hygiene = std::make_shared<Hygiene>();
  std::shared_ptr<std::vector<std::string>> ownedRevisions;
  std::shared_ptr<const std::vector<std::string>> revisions;
  std::map<std::string, std::size_t, std::less<>> revisionOrdinals;
  metadata::SourceReference sourceReference;
  std::uint64_t currentRevision = std::numeric_limits<std::uint64_t>::max();
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
    return unsigned(StaticConstant::Kind::TypeIdentity);
  }
  static unsigned maximum(ReceiverStep::Kind *) {
    return unsigned(ReceiverStep::Kind::Borrow);
  }
  static unsigned maximum(interfaces::Property *) {
    return unsigned(interfaces::Property::Thin);
  }
  static unsigned maximum(metadata::SymbolKind *) {
    return unsigned(metadata::SymbolKind::Static);
  }
};

#define WIRE(T, ...)                                                           \
  void wire(Archive &a, T &v) { a(__VA_ARGS__); }
#define HEADER_FIELDS(T, ...)                                                  \
  template <typename Value>                                                    \
  auto headerFields(std::type_identity<T>, Value &v) {                         \
    return std::tie(__VA_ARGS__);                                              \
  }
#define HEADER(T, ...)                                                         \
  WIRE(T, __VA_ARGS__)                                                         \
  HEADER_FIELDS(T, __VA_ARGS__)
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
HEADER(Function, v.name, v.annotation, v.span, v.parameters, v.owner,
       v.receiver, v.destructor, v.regions, v.item, v.constructor, v.error,
       v.genericParameters, v.constraints, v.implicitGenericParameters,
       v.interfaceOwner, v.implementation, v.unsafeFunction, v.constFunction,
       v.asynchronous, v.asyncDefaultFutureInferred, v.asyncDefaultBodyResult,
       v.asyncOutput, v.asyncError, v.asyncFuture, v.futureStorage, v.abi,
       v.foreignDeclaration, v.variadic, v.explicitReceiver, v.variadicCursor,
       v.variadicSpan, v.lexicalContext)
HEADER(Module::Static, v.name, v.annotation, v.span, v.item, v.mutableBinding,
       v.foreignDeclaration, v.constant)
WIRE(Module::Associated, v.name, v.span, v.visibility, v.constant,
     v.asyncFuture, v.asyncFutureDefaultInferred, v.annotation, v.value,
     v.genericParameters, v.bounds, v.constraints)
HEADER(Module::Product::Variant, v.name, v.fields, v.span, v.attributes)
HEADER(Module::Product, v.name, v.span, v.copyRequested, v.fields, v.regions,
       v.hasDestructor, v.enumeration, v.unionType, v.variants, v.item,
       v.genericParameters, v.constraints, v.interfaces, v.associated,
       v.nameContext)
WIRE(Module::Alias, v.name, v.target, v.span, v.item, v.genericParameters,
     v.constraints)
HEADER(Module::Interface, v.name, v.span, v.item, v.genericParameters,
       v.constraints, v.superinterfaces, v.associated, v.unsafeInterface,
       v.nameContext)
HEADER(Module::Implementation, v.target, v.interface, v.span, v.item,
       v.genericParameters, v.constraints, v.associated, v.methodFunctions,
       v.shorthand, v.negative, v.unsafeImplementation)
WIRE(Module::ModuleDeclaration, v.name, v.span, v.item)
WIRE(Module::MacroDeclaration, v.name, v.span, v.item)
WIRE(Module::Import::Name, v.name, v.alias, v.span)
WIRE(Module::Import, v.path, v.names, v.alias, v.glob, v.synthesized, v.span,
     v.item)
WIRE(Module::Prelude, v.names, v.libraryRoots)
HEADER(Module, v.functions, v.statics, v.products, v.aliases, v.interfaces,
       v.implementations, v.modules, v.macros, v.imports, v.prelude)
HEADER_FIELDS(Parameter, v.name, v.annotation, v.span, v.mode, v.visibility,
              v.pattern, v.attributes, v.format, v.syntaxSpan, v.context,
              v.compiledDefault)
#undef HEADER
#undef HEADER_FIELDS
WIRE(NumericLiteral, v.magnitude, v.floating, v.negative, v.floatingBits)
WIRE(FloatingPolicy, v.reassociate, v.contract, v.noNaNs, v.noInfinities,
     v.noSignedZeros, v.reciprocal, v.approximateFunctions)
WIRE(TypeBinding, v.parameter, v.argument)
WIRE(RegionRequirement, v.longer, v.shorter)
WIRE(Local, v.name, v.type, v.mutableBinding, v.span, v.mode, v.patternView,
     v.storage, v.readMatchPattern, v.context)
template <class A> void functionFacts(A &a, FunctionFacts &v) {
  a(v.result, v.asyncDefaultBodyResult, v.diverges, v.locals, v.resultSources,
    v.resultContents, v.withinFlows, v.error, v.abiResult, v.defaultAbiResults,
    v.defaultValueTypes, v.defaultBorrowed, v.defaultBorrowOperand,
    v.parameterBindings, v.parameterViewTypes, v.constructorSelfSlot,
    v.canonicalName, v.opaqueResult, v.regionSignature, v.genericParameters,
    v.genericResultSources, v.interfaceBounds, v.unpinBounds, v.sizedBounds,
    v.genericEqualities, v.externalName, v.floatingPolicy, v.library,
    v.variadicCursor, v.targetFeatures, v.naked);
}
void wire(Archive &a, FunctionFacts &v) { functionFacts(a, v); }
WIRE(ImportedFunction::SignatureIndex, v.result, v.error, v.parameters,
     v.externalName)
WIRE(FunctionHeader, v.span, v.signature, v.unsafeFunction, v.hasBody, v.body,
     v.defaults)
WIRE(StaticFacts, v.name, v.externalName, v.library, v.type, v.initializer)
WIRE(DeclarationEnvironment, v.names, v.bounds, v.parameters, v.defaults,
     v.equalities, v.declarationSpan)
WIRE(DeclarationRegions, v.names, v.parameters, v.assumptions)
WIRE(ImportedTypeDeclaration, v.span, v.name, v.type, v.generics)
void expression(Archive &archive, std::shared_ptr<CheckedExpression> &value);
void wire(Archive &a, ImportedInherentConstant &v) {
  a(v.implementation, v.declaration, v.name, v.target, v.declaredType, v.value,
    v.materialized);
  expression(a, v.initializer);
  if ((!v.materialized && v.value == Type::Unknown && !v.initializer) ||
      (v.initializer && (v.value != Type::Unknown || v.materialized ||
                         !a.types->isProduct(v.declaredType))) ||
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
void wire(Archive &a, interfaces::AssociatedValue &v) {
  a(v.parameters, v.value, v.regions, v.regionRequirements, v.requirements,
    v.fromDefault);
  a.symbol(metadata::SymbolKind::Function, v.initializer);
}
WIRE(interfaces::StructuralPropertyDeclaration, v.negative, v.implementation)
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
      (v.kind == StaticConstant::Kind::TypeIdentity &&
       (v.type != Type::U64 || v.text.empty() || !v.fields.empty() ||
        v.symbol != -1 || !v.projections.empty() || v.selection != -1 ||
        v.byteOffset != 0)) ||
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
    v.regions, v.regionRequirements, v.equalities, v.fallback);
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
    v.structuralDeclarations, v.argumentsReady, v.callableContracts);
}
void wire(Archive &a, ReceiverStep &v) {
  a(v.kind, v.source, v.target, v.resultView, v.count, v.mode);
  a.symbol(metadata::SymbolKind::Function, v.callee);
  a(v.typeArguments, v.interfaceSelf, v.interfaceType, v.interfaceMethod);
}
void wire(Archive &a, ReceiverPlan &v) { a(v.source, v.target, v.steps); }
template <class Writer> void nodeFacts(Writer &a, NodeFacts &v) {
  a(v.type);
  a.symbol(metadata::SymbolKind::Function, v.callee);
  a(v.slot, v.field, v.variant, v.number, v.numeric, v.machineOperation,
    v.machineType, v.constantParameter, v.constantValue, v.constantCount,
    v.callResult, v.typeArguments, v.lexicallyBound, v.unsafeContext,
    v.receiverPlan);
  a(v.interfaceSelf, v.interfaceType, v.interfaceMethod, v.outcomePropagation);
}
void wire(Archive &a, NodeFacts &v) { nodeFacts(a, v); }

struct DispatchScanner {
  Archive &archive;
  NodeFacts &facts;
  template <class T> void value(T &item) {
    if constexpr (std::is_same_v<T, Type>) {
      if (&item == &facts.interfaceSelf || &item == &facts.interfaceType)
        archive(item);
      else
        archive.discard(item);
    } else if constexpr (std::is_same_v<T, int>) {
      if (&item == &facts.interfaceMethod)
        archive(item);
      else
        archive.discard(item);
    } else
      archive.discard(item);
  }
  template <class... T> void operator()(T &...items) { (value(items), ...); }
  void symbol(metadata::SymbolKind kind, int &index) {
    archive.symbol(kind, index);
  }
};
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
  if constexpr (std::is_same_v<T, Node>)
    if (scanningExpression) {
      bool root = scanPrimary && scannedNodes == 0;
      scanNodes.push_back({0, scanPrimary, root});
      scannedNodes += scanPrimary;
      scanPrimary = false;
    }
  wire(*this, item);
  if constexpr (recursive)
    --depth;
  if constexpr (std::is_same_v<T, Node>) {
    auto count = item.children.size();
    if (scanningExpression) {
      const auto scan = scanNodes.back();
      scanNodes.pop_back();
      count = scan.children;
      if (scan.root)
        scannedSpan = item.span;
    }
    if (!good())
      return;
    if (!scanningExpression)
      for (const auto &child : item.children)
        if (!child.get()) {
          fail("checked expression contains an empty child");
          return;
        }
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
      valid = count == 2;
      break;
    case Kind::Range:
      valid = (item.text == ".." || item.text == "..=") &&
              ((item.name.empty() && count == 2) ||
               (item.name == "full" && item.text == ".." && count == 0) ||
               (item.name == "from" && item.text == ".." && count == 1) ||
               (item.name == "to" && count == 1));
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
  const auto begin = archive.position();
  bool present = bool(value);
  archive(present);
  if (!present || !archive.good())
    return;
  if (archive.reading())
    value = std::make_shared<CheckedExpression>();
  else
    value->materialize();
  if (archive.reading() && archive.deferExpression) {
    auto references =
        std::exchange(archive.decode, archive.expressionReferences);
    const auto [count, span] = archive.scanSyntax();
    if (archive.good() && count == 0)
      archive.fail("checked expression has no executable root");
    value->span = span;
    NodeFacts facts;
    DispatchScanner scanner{archive, facts};
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      facts = {};
      nodeFacts(scanner, facts);
      if (facts.interfaceMethod != -1)
        value->dispatches.push_back(
            {facts.interfaceSelf, facts.interfaceType, facts.interfaceMethod});
      std::optional<StaticConstant> constant;
      archive.discard(constant);
    }
    const auto size = archive.position() - begin;
    value->load = [read = archive.deferExpression, begin, size](
                      CheckedExpression &target) { read(target, begin, size); };
    archive.decode = references;
    return;
  }
  archive(value->syntax);
  if (archive.good() && !value->syntax.get())
    archive.fail("checked expression has no executable root");
  if (archive.good())
    value->span = value->syntax->span;
  auto visit = [&](auto &&self, const Node &node) -> void {
    NodeFacts facts;
    if (!archive.reading()) {
      auto found = value->facts.find(&node);
      if (found != value->facts.end())
        facts = found->second;
    }
    archive(facts);
    if (archive.reading() && facts.interfaceMethod != -1)
      value->dispatches.push_back(
          {facts.interfaceSelf, facts.interfaceType, facts.interfaceMethod});
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

struct FunctionScan {
  ImportedFunction::SignatureIndex signature;
  std::array<std::size_t, 4> defaults{};
  std::size_t staticLocals = 0;
};
struct FunctionFactsScanner {
  Archive &archive;
  FunctionFacts &facts;
  FunctionScan &scan;
  template <class... T> void operator()(T &...values) { (value(values), ...); }
  template <class T> void value(T &item) { archive.discard(item); }
  void value(std::vector<Local> &) {
    auto count = archive.collectionSize();
    scan.signature.parameters.reserve(count);
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      Local local;
      archive.discard(local);
      scan.signature.parameters.push_back(local.type);
      if (local.storage == StorageDuration::Static)
        ++scan.staticLocals;
    }
  }
  void value(std::vector<Type> &items) {
    auto count = archive.discardCollection(items);
    if (&items == &facts.defaultAbiResults)
      scan.defaults[0] = count;
    else if (&items == &facts.defaultValueTypes)
      scan.defaults[1] = count;
  }
  void value(std::vector<bool> &items) {
    auto count = archive.discardCollection(items);
    scan.defaults[&items == &facts.defaultBorrowed ? 2 : 3] = count;
  }
  void value(std::vector<std::size_t> &items) { archive(items); }
  void value(std::vector<std::pair<std::size_t, std::size_t>> &items) {
    archive(items);
  }
  void value(std::unordered_map<int, std::size_t> &items) { archive(items); }
  void value(std::string &text) {
    if (&text == &facts.externalName)
      archive(text);
    else
      archive.discard(text);
  }
};

void function(Archive &archive, ImportedFunction &value,
              FunctionScan *scan = nullptr) {
  archive(value.span);
  auto &contract = value.contract();
  if (scan) {
    FunctionFactsScanner scanner{archive, contract.facts, *scan};
    functionFacts(scanner, contract.facts);
    archive.discard(contract.generics);
    archive.discard(contract.regions);
  } else
    archive(contract.facts, contract.generics, contract.regions);
  archive(value.unsafeFunction, value.hasBody);
  expression(archive, value.body);
  std::uint64_t count = value.defaults.size();
  archive(count);
  if (!archive.good())
    return;
  if (archive.reading()) {
    if (count > (scan ? scan->signature.parameters.size()
                      : contract.facts.locals.size())) {
      archive.fail("default contract exceeds the parameter inventory");
      return;
    }
    value.defaults.resize(static_cast<std::size_t>(count));
  }
  for (auto &item : value.defaults)
    expression(archive, item);
  const auto parameters = value.defaults.size();
  const auto &facts = contract.facts;
  if ((scan ? scan->defaults[0] : facts.defaultAbiResults.size()) !=
          parameters ||
      (scan ? scan->defaults[1] : facts.defaultValueTypes.size()) !=
          parameters ||
      (scan ? scan->defaults[2] : facts.defaultBorrowed.size()) != parameters ||
      (scan ? scan->defaults[3] : facts.defaultBorrowOperand.size()) !=
          parameters ||
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
    if (slot < 0 ||
        std::size_t(slot) >=
            (scan ? scan->signature.parameters.size() : facts.locals.size()) ||
        parameter >= parameters)
      archive.fail("invalid checked parameter binding");
  if (scan && archive.good()) {
    scan->signature.parameters.resize(parameters);
    scan->signature.result = facts.result;
    scan->signature.error = facts.error;
    scan->signature.externalName = std::move(contract.facts.externalName);
  }
  if (!scan && archive.reading() && archive.good())
    value.prepareEvaluation();
}

FunctionHeader
functionHeader(const ImportedFunction &value,
               const ImportedFunction::SignatureIndex *signature = nullptr) {
  FunctionHeader result;
  result.span = value.span;
  result.unsafeFunction = value.unsafeFunction;
  result.hasBody = value.hasBody;
  if (signature)
    result.signature = *signature;
  else {
    const auto &facts = value.contract().facts;
    result.signature.result = facts.result;
    result.signature.error = facts.error;
    result.signature.externalName = facts.externalName;
    for (std::size_t p = 0; p < value.defaults.size(); ++p)
      result.signature.parameters.push_back(facts.locals.at(p).type);
  }
  auto expressionSpan = [](const std::shared_ptr<CheckedExpression> &body)
      -> std::optional<Span> {
    if (!body)
      return std::nullopt;
    return body->syntax.get() ? body->syntax->span : body->span;
  };
  result.body = expressionSpan(value.body);
  for (const auto &argument : value.defaults)
    result.defaults.push_back(expressionSpan(argument));
  return result;
}

bool matchesHeader(const FunctionHeader &expected,
                   const FunctionHeader &actual) {
  auto sameSpan = [](Span left, Span right) {
    return left.source == right.source && left.begin == right.begin &&
           left.end == right.end;
  };
  auto sameExpression = [&](const std::optional<Span> &left,
                            const std::optional<Span> &right) {
    return bool(left) == bool(right) && (!left || sameSpan(*left, *right));
  };
  return sameSpan(expected.span, actual.span) &&
         expected.signature == actual.signature &&
         expected.unsafeFunction == actual.unsafeFunction &&
         expected.hasBody == actual.hasBody &&
         sameExpression(expected.body, actual.body) &&
         expected.defaults.size() == actual.defaults.size() &&
         std::equal(expected.defaults.begin(), expected.defaults.end(),
                    actual.defaults.begin(), sameExpression);
}

void validateDispatches(const ImportedFunction &function,
                        const TypeStore &types,
                        const InterfaceMethods &interfaces) {
  auto expression = [&](const std::shared_ptr<CheckedExpression> &body) {
    if (!body)
      return;
    for (const auto &dispatch : body->dispatches) {
      if (!types.isErased(dispatch.interfaceType) || dispatch.method < 0 ||
          dispatch.self == Type::Unknown || !types.contains(dispatch.self))
        throw metadata::InvalidMetadata(
            "invalid checked expression interface dispatch");
      auto declaration = types.erasedDeclaration(dispatch.interfaceType);
      for (const auto &methods : interfaces)
        if (declaration >= methods.size() || !methods[declaration] ||
            static_cast<std::size_t>(dispatch.method) >= *methods[declaration])
          throw metadata::InvalidMetadata(
              "invalid checked expression interface dispatch");
    }
  };
  expression(function.body);
  for (const auto &argument : function.defaults)
    expression(argument);
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
    result.aggregate = std::make_shared<const evaluation::Shape::Aggregate>(
        evaluation::Shape::Aggregate{{std::move(*element)}, {}, {}});
    return result;
  }
  if (product.kind != AggregateKind::Tuple)
    return std::nullopt;
  result.kind = evaluation::Shape::Kind::Tuple;
  auto aggregate = std::make_shared<evaluation::Shape::Aggregate>();
  for (const auto &field : product.fields) {
    auto element = shape(types, field.type, depth + 1);
    if (!element)
      return std::nullopt;
    aggregate->elements.push_back(std::move(*element));
  }
  result.aggregate = std::move(aggregate);
  return result;
}

template <typename T> T copyHeader(const T &value);
template <typename T>
Declarations<T> copyHeader(const Declarations<T> &values) {
  return values;
}
template <typename T> std::vector<T> copyHeader(const std::vector<T> &values) {
  std::vector<T> result;
  result.reserve(values.size());
  for (const auto &value : values)
    result.push_back(copyHeader(value));
  return result;
}
template <typename T> T copyHeader(const T &value) {
  if constexpr (requires { headerFields(std::type_identity<T>{}, value); }) {
    T result;
    auto from = headerFields(std::type_identity<T>{}, value);
    auto to = headerFields(std::type_identity<T>{}, result);
    [&]<std::size_t... I>(std::index_sequence<I...>) {
      ((std::get<I>(to) = copyHeader(std::get<I>(from))), ...);
    }(std::make_index_sequence<std::tuple_size_v<decltype(from)>>{});
    return result;
  } else
    return value;
}
} // namespace

const ImportedFunction &ImportedFunction::materialize() const {
  if (!deferred)
    return *this;
  return deferred->materialize();
}

const ImportedFunction &ImportedFunction::Deferred::materialize() {
  std::call_once(once, [&] {
    auto loaded = load();
    if (!loaded || loaded->deferred)
      throw std::logic_error("deferred function has no admitted contract");
    value = std::move(loaded);
    load = {};
  });
  return *value;
}

ImportedFunction::Contract &ImportedFunction::contract() {
  if (deferred) {
    ImportedFunction expanded = materialize();
    *this = std::move(expanded);
  }
  if (!owned)
    owned = std::make_shared<Contract>();
  else if (!owned.unique())
    owned = std::make_shared<Contract>(*owned);
  if (evaluator)
    prepareEvaluation();
  return *owned;
}

const ImportedFunction::Contract &ImportedFunction::contract() const {
  const auto &loaded = materialize();
  if (!loaded.owned)
    throw std::logic_error("checked function has no admitted contract");
  return *loaded.owned;
}

void ImportedFunction::defer(
    SignatureIndex index,
    std::function<std::shared_ptr<const ImportedFunction>()> load) {
  if (!load || deferred)
    throw std::invalid_argument("invalid deferred function contract");
  signature = std::move(index);
  owned.reset();
  evaluator.reset();
  deferred = std::make_shared<Deferred>();
  deferred->load = std::move(load);
}

const FunctionFacts &
FunctionFactsTable::materialize(const ImportedFunctionReference &function) {
  return function->contract().facts;
}

const evaluation::CheckedFunction &
ImportedFunction::checkedFunction(const TypeStore &types) const {
  if (deferred)
    return materialize().checkedFunction(types);
  const auto &facts = contract().facts;
  if (!body || !evaluator)
    throw std::logic_error("checked function has no evaluation contract");
  std::call_once(evaluator->once, [&] {
    body->materialize();
    for (const auto &argument : defaults)
      if (argument)
        argument->materialize();
    evaluation::CheckedFunction result;
    auto resultShape = shape(types, facts.result);
    if (resultShape)
      result.result = std::move(*resultShape);
    result.unsafeFunction = unsafeFunction;
    bool supported = resultShape.has_value();
    for (std::size_t i = 0; i < defaults.size(); ++i) {
      auto parameter = shape(types, facts.locals[i].type);
      if (!parameter) {
        supported = false;
        break;
      }
      const auto &local = facts.locals[i];
      result.parameters.push_back(
          {local.name, std::move(*parameter), local.span,
           defaults[i] ? defaults[i]->syntax.get() : nullptr, local.context});
    }
    if (supported)
      result.body = body->syntax.get();
    evaluator->function = std::move(result);
  });
  return evaluator->function;
}

DeclarationInventory declarationInventory(const CheckedModule &module) {
  DeclarationInventory result;
  std::set<Type> known;
  using Position = std::tuple<SourceId, std::size_t, std::size_t>;
  auto position = [](Span span) {
    return Position{span.source, span.begin, span.end};
  };
  auto types = [&](const DeclarationEnvironment &environment,
                   const std::string &owner, Span span) {
    for (std::size_t p = 0; p < environment.parameters.size(); ++p)
      if (known.insert(environment.parameters[p]).second)
        result.types.push_back(
            {environment.parameters[p], span, owner, std::uint32_t(p)});
  };
  const auto &contracts = *module.declarationContracts;
  for (const auto &retained : contracts.products) {
    const auto &product = *retained;
    if (known.insert(product.type).second)
      result.types.push_back(
          {product.type, product.span, product.name, std::nullopt});
    types(product.generics, product.name, product.span);
  }
  for (const auto &alias : contracts.aliases)
    types(alias->generics, alias->name, alias->span);
  for (std::size_t i = 0; i < module.interfaceData->definitions.size(); ++i) {
    const auto &definition = module.interfaceData->definitions[i];
    result.symbols.push_back({metadata::SymbolKind::Interface, std::uint32_t(i),
                              definition.span, definition.name});
    if (known.insert(definition.self).second)
      result.types.push_back(
          {definition.self, definition.span, definition.name + "::<Self>", 0});
    if (i < contracts.interfaces.size())
      types(contracts.interfaces[i]->generics, definition.name,
            definition.span);
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
  std::map<Position, std::string> implementationNames;
  std::map<Position, std::size_t> syntaxImplementations;
  std::map<Position, std::pair<bool, std::size_t>> associatedOwners;
  for (std::size_t i = 0; i < module.tree.interfaces.size(); ++i)
    for (const auto &item : module.tree.interfaces[i].associated)
      associatedOwners[position(item.span)] = {false, i};
  for (std::size_t i = 0; i < module.tree.implementations.size(); ++i) {
    const auto &syntax = module.tree.implementations[i];
    syntaxImplementations.try_emplace(position(syntax.span), i);
    for (const auto &item : syntax.associated)
      associatedOwners[position(item.span)] = {true, i};
  }
  for (const auto &retained : contracts.implementations) {
    const auto &implementation = *retained;
    std::string owner;
    if (auto found = syntaxImplementations.find(position(implementation.span));
        found != syntaxImplementations.end()) {
      const auto &syntax = module.tree.implementations[found->second];
      for (const auto &scope : syntax.item.scope)
        owner += scope + "::";
      owner +=
          "<extend:" + syntax.target.name + ":" + syntax.interface.name + ">";
    }
    auto identity = owner + "::<implementation." +
                    std::to_string(implementationOrdinals[owner]++) + ">";
    implementationNames.emplace(std::tuple{implementation.span.source,
                                           implementation.span.begin,
                                           implementation.span.end},
                                identity);
    types(implementation.generics, identity, implementation.span);
  }
  for (const auto &retained : contracts.associated) {
    const auto &associated = *retained;
    std::string owner;
    if (auto found = associatedOwners.find(position(associated.span));
        found != associatedOwners.end()) {
      const auto &[implementation, index] = found->second;
      owner = implementation ? implementationNames.at(position(
                                   module.tree.implementations[index].span))
                             : module.interfaceData->definitions[index].name;
    }
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
      types(contract->second->contract().generics, facts.canonicalName,
            function.span);
    else if (module.imported(i)) {
      auto contract = module.importedDeclarations->functions.find(i);
      if (contract != module.importedDeclarations->functions.end())
        types(contract->second->contract().generics, facts.canonicalName,
              function.span);
    }
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
  auto package = [&](Span span) {
    if (auto owner = module.namespaces().packageOf(span);
        owner && packages.insert(*owner).second)
      result.symbols.push_back(
          {metadata::SymbolKind::Package, *owner, span, {}});
  };
  const auto symbolCount = result.symbols.size();
  for (std::size_t i = 0; i < symbolCount; ++i)
    package(result.symbols[i].span);
  for (const auto &type : result.types)
    package(type.span);
  for (const auto &implementation : contracts.implementations)
    package(implementation->span);
  for (const auto &declaration : module.tree.modules)
    package(declaration.span);
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
  header.tag("mettle.checked-header.2");
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
  contracts.tag("mettle.checked-contracts.15");
  auto &value = *module.declarationContracts;
  std::uint64_t count = value.functions.size() +
                        (module.importedDeclarations
                             ? module.importedDeclarations->functions.size()
                             : 0);
  contracts(count);
  auto writeFunction = [&](std::uint32_t index, ImportedFunction item) {
    auto symbol = index;
    contracts.symbol(metadata::SymbolKind::Function, symbol);
    if (item.defaults.size() >
        std::as_const(item).contract().facts.locals.size()) {
      contracts.fail("default contract exceeds the parameter inventory");
      return;
    }
    auto summary = functionHeader(item);
    contracts(summary);
    Archive record(references, *module.types, contracts.hygieneState());
    function(record, item);
    for (const auto &local : item.contract().facts.locals)
      if (local.storage == StorageDuration::Static) {
        auto index = local.staticIndex;
        record.symbol(metadata::SymbolKind::Static, index);
      }
    if (!record.good())
      contracts.fail(std::move(record.error));
    else
      contracts.writeBlock(record.output);
  };
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    if (module.imported(i)) {
      writeFunction(
          static_cast<std::uint32_t>(i),
          module.importedDeclarations->functions.at(i)->materialize());
    } else
      writeFunction(static_cast<std::uint32_t>(i),
                    *value.functions.at(static_cast<std::uint32_t>(i)));
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
  archive.tag("mettle.checked-header.2");
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
    auto imported = [](auto &items) {
      for (auto &item : items.local())
        item.item.checkedImport = true;
    };
    imported(module.functions);
    imported(module.statics);
    imported(module.products);
    imported(module.aliases);
    imported(module.interfaces);
    imported(module.implementations);
    result.module = std::move(module);
  }
  return result;
}

LibraryHeaderImport copyLibraryHeader(const LibraryHeaderImport &header) {
  LibraryHeaderImport result;
  if (header.module)
    result.module = copyHeader(*header.module);
  result.symbols = header.symbols;
  result.types = header.types;
  result.error = header.error;
  return result;
}

DeclarationQueryInputs
declarationQueryInputs(const Module &module,
                       const ImportedDeclarations *native) {
  DeclarationQueryInputs result;
  metadata::EncodeReferences references;
  references.source = [](Span span) {
    return std::optional{metadata::SourceReference{
        std::to_string(span.source), static_cast<std::uint32_t>(span.begin),
        static_cast<std::uint32_t>(span.end)}};
  };
  TypeStore types;
  Archive context(references, types);
  std::set<SourceId> importedSources;
  if (native) {
    for (const auto &[index, function] : native->functions) {
      (void)index;
      importedSources.insert(function.span().source);
    }
    for (const auto &product : native->products)
      importedSources.insert(product->span.source);
  }
  auto source = [&](Span span) {
    return !importedSources.contains(span.source);
  };
  auto declarations = [&](const auto &items) {
    auto count = items.size();
    context(count);
    for (std::size_t i = 0; i < items.size(); ++i)
      if (source(items[i].span))
        context(i, items[i]);
  };
  declarations(module.functions);
  declarations(module.statics);
  declarations(module.products);
  declarations(module.aliases);
  declarations(module.interfaces);
  declarations(module.implementations);
  declarations(module.modules);
  declarations(module.macros);
  declarations(module.imports);
  context(module.prelude, module.packageNames, module.globalAssembly);
  for (const auto &storage : module.statics)
    if (source(storage.span))
      context(storage.initializer);
  auto associated = [&](const auto &owners) {
    for (const auto &owner : owners)
      if (source(owner.span))
        for (const auto &item : owner.associated)
          context(item.constantValue);
  };
  associated(module.interfaces);
  associated(module.implementations);
  for (const auto &product : module.products)
    if (source(product.span))
      for (const auto &variant : product.variants)
        context(variant.discriminant);
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    const auto &function = module.functions[i];
    if (!source(function.span))
      continue;
    for (const auto &parameter : function.parameters)
      context(parameter.defaultValue);
    const bool reusable =
        function.body.get() && !function.constFunction &&
        !function.destructor && !function.constructor &&
        !function.asynchronous && !function.asyncDefaultFutureInferred &&
        std::none_of(function.parameters.begin(), function.parameters.end(),
                     [](const auto &parameter) {
                       return parameter.defaultValue.get() ||
                              parameter.compiledDefault;
                     });
    context(reusable);
    if (reusable) {
      Archive body(references, types);
      body(function.body);
      if (!body.good()) {
        result.error = std::move(body.error);
        return result;
      }
      result.bodies.emplace(i, std::move(body.output));
    } else
      context(function.body);
  }
  if (!context.good())
    result.error = std::move(context.error);
  else
    result.context = std::move(context.output);
  return result;
}

std::shared_ptr<const ImportedDeclarations> retainQueryDeclarations(
    const CheckedModule &module, const ImportedDeclarations *native,
    std::span<const std::size_t> functions, TypeProjection &projection,
    const std::function<bool(Type)> &reusableType) {
  auto result = native ? std::make_shared<ImportedDeclarations>(*native)
                       : std::make_shared<ImportedDeclarations>();
  const auto local = module.declarations();
  const auto imports = module.imports();
  result->types = projection.store();
  auto types = [&](auto &values) {
    for (auto &value : values)
      value = projection.type(value);
  };
  auto bindings = [&](auto &values) {
    for (auto &value : values) {
      value.parameter = projection.type(value.parameter);
      value.argument = projection.type(value.argument);
    }
  };
  auto environment = [&](DeclarationEnvironment &value) {
    for (auto &[name, type] : value.names) {
      (void)name;
      type = projection.type(type);
    }
    decltype(value.bounds) bounds;
    for (auto &[type, syntax] : value.bounds)
      bounds.emplace(projection.type(type), std::move(syntax));
    value.bounds = std::move(bounds);
    types(value.parameters);
    decltype(value.defaults) defaults;
    for (auto [parameter, argument] : value.defaults)
      defaults.emplace(projection.type(parameter), projection.type(argument));
    value.defaults = std::move(defaults);
    bindings(value.equalities);
  };
  auto projectDeclarations = [&](auto &items,
                                 const ImportedDeclarations::TypeTable *base) {
    for (auto &item : items) {
      if (base && native->findType(item->span, *base))
        continue;
      auto projected = std::make_shared<ImportedTypeDeclaration>(*item);
      projected->type = projection.type(projected->type);
      environment(projected->generics);
      item = std::move(projected);
    }
  };
  result->products = local->products;
  result->aliases = local->aliases;
  if (reusableType)
    for (auto *items : {&result->products, &result->aliases})
      std::erase_if(
          *items, [&](const auto &item) { return !reusableType(item->type); });
  projectDeclarations(result->products, native ? &native->products : nullptr);
  projectDeclarations(result->aliases, native ? &native->aliases : nullptr);
  for (auto index : functions) {
    const auto &source =
        module.imported(index) ? imports->functions : local->functions;
    auto projected =
        std::make_shared<ImportedFunction>(source.at(index)->materialize());
    auto &facts = projected->contract().facts;
    facts.result = projection.type(facts.result);
    facts.asyncDefaultBodyResult =
        projection.type(facts.asyncDefaultBodyResult);
    for (auto &local : facts.locals)
      local.type = projection.type(local.type);
    facts.error = projection.type(facts.error);
    facts.abiResult = projection.type(facts.abiResult);
    types(facts.defaultAbiResults);
    types(facts.defaultValueTypes);
    for (auto &[slot, views] : facts.parameterViewTypes) {
      (void)slot;
      views.first = projection.type(views.first);
      views.second = projection.type(views.second);
    }
    facts.opaqueResult = projection.type(facts.opaqueResult);
    facts.regionSignature = projection.type(facts.regionSignature);
    types(facts.genericParameters);
    for (auto &[subject, interface] : facts.interfaceBounds) {
      subject = projection.type(subject);
      interface = projection.type(interface);
    }
    types(facts.unpinBounds);
    types(facts.sizedBounds);
    bindings(facts.genericEqualities);
    environment(projected->contract().generics);
    for (auto &[name, region] : projected->contract().regions.names) {
      (void)name;
      region = projection.region(region);
    }
    for (auto &region : projected->contract().regions.parameters)
      region = projection.region(region);
    for (auto &requirement : projected->contract().regions.assumptions) {
      requirement.longer = projection.region(requirement.longer);
      requirement.shorter = projection.region(requirement.shorter);
    }
    result->functions.insert_or_assign(static_cast<std::uint32_t>(index),
                                       std::move(projected));
  }
  result->indexTypes();
  return result;
}

LibraryDeclarationImport importLibraryDeclarations(
    std::span<const std::uint8_t> bytes, std::shared_ptr<TypeStore> types,
    const metadata::DecodeReferences &references, const Module *module,
    std::shared_ptr<const void> backing,
    std::shared_ptr<const metadata::DecodeReferences> retainedReferences,
    metadata::ValidationMode validation) {
  LibraryDeclarationImport result;
  if (!types) {
    result.error = "checked declarations require an imported type store";
    return result;
  }
  if (retainedReferences && retainedReferences.get() != &references) {
    result.error = "retained declaration references do not own the resolver";
    return result;
  }
  if (validation == metadata::ValidationMode::OnDemand && !retainedReferences) {
    result.error = "demand-loaded declarations require an owned resolver";
    return result;
  }
  if (!backing) {
    auto owned = std::make_shared<const std::vector<std::uint8_t>>(
        bytes.begin(), bytes.end());
    bytes = *owned;
    backing = std::move(owned);
  }
  auto remapping = std::make_shared<Remapping>();
  metadata::DecodeReferences record;
  record.type = [&](std::uint32_t id) -> std::optional<Type> {
    auto value = references.type ? references.type(id) : std::nullopt;
    if (value) {
      auto [found, inserted] = remapping->types.emplace(id, *value);
      if (!inserted && found->second != *value)
        return std::nullopt;
    }
    return value;
  };
  record.source =
      [&](const metadata::SourceReference &source) -> std::optional<Span> {
    auto value = references.source ? references.source(source) : std::nullopt;
    if (value) {
      auto &positions = remapping->sources[source.revision];
      auto [found, inserted] =
          positions.emplace(Remapping::position(source), *value);
      if (!inserted && (found->second.source != value->source ||
                        found->second.begin != value->begin ||
                        found->second.end != value->end))
        return std::nullopt;
    }
    return value;
  };
  record.symbol = [&](metadata::SymbolKind kind,
                      std::string_view name) -> std::optional<std::uint32_t> {
    auto value =
        references.symbol ? references.symbol(kind, name) : std::nullopt;
    if (value) {
      auto [found, inserted] =
          remapping->symbols[kind].emplace(std::string(name), *value);
      if (!inserted && found->second != *value)
        return std::nullopt;
    }
    return value;
  };
  const bool retained = bool(retainedReferences);
  auto frozen = std::move(retainedReferences);
  if (!frozen) {
    auto mapped = std::make_shared<metadata::DecodeReferences>();
    mapped->type = [remapping](std::uint32_t id) -> std::optional<Type> {
      auto found = remapping->types.find(id);
      return found == remapping->types.end() ? std::nullopt
                                             : std::optional{found->second};
    };
    mapped->source =
        [remapping](
            const metadata::SourceReference &source) -> std::optional<Span> {
      auto revision = remapping->sources.find(source.revision);
      if (revision == remapping->sources.end())
        return std::nullopt;
      auto found = revision->second.find(Remapping::position(source));
      return found == revision->second.end() ? std::nullopt
                                             : std::optional{found->second};
    };
    mapped->symbol =
        [remapping](metadata::SymbolKind kind,
                    std::string_view name) -> std::optional<std::uint32_t> {
      auto symbols = remapping->symbols.find(kind);
      if (symbols == remapping->symbols.end())
        return std::nullopt;
      auto found = symbols->second.find(name);
      return found == symbols->second.end() ? std::nullopt
                                            : std::optional{found->second};
    };
    frozen = std::move(mapped);
  }
  auto storage =
      std::shared_ptr<const std::uint8_t>(std::move(backing), bytes.data());
  const auto &admission = retained ? references : record;
  Archive archive(bytes, admission, types.get());
  auto revisions = archive.sourceRevisions();
  archive.expressionReferences = &admission;
  archive.deferExpression = [storage, length = bytes.size(), frozen, revisions,
                             types](CheckedExpression &target,
                                    std::size_t begin, std::size_t size) {
    auto bytes = std::span(storage.get(), length);
    Archive reader(bytes.subspan(begin, size), *frozen, types.get(), revisions);
    std::shared_ptr<CheckedExpression> decoded;
    expression(reader, decoded);
    reader.finish();
    if (!reader.good() || !decoded)
      throw std::logic_error(
          "validated checked expression could not be materialized: " +
          reader.error);
    target.syntax = std::move(decoded->syntax);
    target.facts = std::move(decoded->facts);
    target.constants = std::move(decoded->constants);
  };
  archive.tag("mettle.checked-contracts.15");
  auto value = std::make_shared<ImportedDeclarations>();
  auto methods = std::make_shared<InterfaceMethods>();
  auto deferExpressions = [storage, frozen,
                           types](Archive &reader,
                                  std::span<const std::uint8_t> payload) {
    auto revisions = reader.sourceRevisions();
    reader.deferExpression = [storage, payload, frozen, types,
                              revisions](CheckedExpression &target,
                                         std::size_t begin, std::size_t size) {
      Archive expressionReader(payload.subspan(begin, size), *frozen,
                               types.get(), revisions);
      std::shared_ptr<CheckedExpression> decoded;
      expression(expressionReader, decoded);
      expressionReader.finish();
      if (!expressionReader.good() || !decoded)
        throw metadata::InvalidMetadata("invalid checked expression: " +
                                        expressionReader.error);
      target.span = decoded->span;
      target.syntax = std::move(decoded->syntax);
      target.facts = std::move(decoded->facts);
      target.constants = std::move(decoded->constants);
      target.dispatches = std::move(decoded->dispatches);
    };
  };
  value->types = types;
  auto compact = std::make_shared<ImportedFunctionRecords>();
  struct FunctionRecord {
    std::span<const std::uint8_t> header, payload;
  };
  auto functionRecords = std::make_shared<std::vector<FunctionRecord>>();
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size())
    archive.fail("function inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Function, index);
    auto headerBegin = archive.position();
    FunctionHeader summary;
    archive(summary);
    auto headerBytes =
        bytes.subspan(headerBegin, archive.position() - headerBegin);
    auto payload = archive.readBlock();
    if (!archive.good())
      break;
    if (summary.defaults.size() != summary.signature.parameters.size()) {
      archive.fail("invalid checked function signature inventory");
      break;
    }
    if (validation == metadata::ValidationMode::OnDemand) {
      auto ordinal = compact->headers.size();
      compact->headers.push_back(
          {summary.span, summary.signature.result, summary.signature.error,
           compact->parameters.size(), summary.signature.parameters.size(),
           summary.hasBody, std::move(summary.signature.externalName)});
      compact->parameters.insert(compact->parameters.end(),
                                 summary.signature.parameters.begin(),
                                 summary.signature.parameters.end());
      for (const auto &argument : summary.defaults)
        compact->defaults.push_back(argument.has_value());
      functionRecords->push_back({headerBytes, payload});
      compact->functions.push_uninitialized();
      if (!value->functions
               .emplace(index, ImportedFunctionReference(compact, ordinal))
               .second)
        archive.fail("duplicate checked function identity");
      continue;
    }
    ImportedFunction item;
    if (validation == metadata::ValidationMode::Eager) {
      Archive reader(payload, admission, types.get());
      reader.expressionReferences = &admission;
      deferExpressions(reader, payload);
      FunctionScan scanned;
      function(reader, item, &scanned);
      for (std::size_t s = 0; s < scanned.staticLocals; ++s) {
        int symbol = -1;
        reader.symbol(metadata::SymbolKind::Static, symbol);
      }
      reader.finish();
      if (!reader.good()) {
        archive.fail(std::move(reader.error));
        break;
      }
      if (!matchesHeader(summary, functionHeader(item, &scanned.signature))) {
        archive.fail(
            "checked function record does not match its signature index");
        break;
      }
    }
    item.defer(summary.signature, [storage, payload, frozen, types, summary,
                                   methods, deferExpressions] {
      Archive reader(payload, *frozen, types.get());
      reader.expressionReferences = frozen.get();
      deferExpressions(reader, payload);
      auto decoded = std::make_shared<ImportedFunction>();
      function(reader, *decoded);
      for (auto &local : decoded->contract().facts.locals)
        if (local.storage == StorageDuration::Static)
          reader.symbol(metadata::SymbolKind::Static, local.staticIndex);
      reader.finish();
      if (!reader.good())
        throw metadata::InvalidMetadata("invalid checked function contract: " +
                                        reader.error);
      if (!matchesHeader(summary, functionHeader(*decoded)))
        throw metadata::InvalidMetadata(
            "checked function record does not match its signature index");
      validateDispatches(*decoded, *types, *methods);
      return decoded;
    });
    auto retained = std::make_shared<ImportedFunction>(std::move(item));
    if (!value->functions.emplace(index, retained).second)
      archive.fail("duplicate checked function identity");
  }
  if (!functionRecords->empty()) {
    auto loader = std::make_shared<
        const TypeRecords<ImportedFunction, true>::Loader>(
        [storage, functionRecords, frozen, types, methods, deferExpressions,
         revisions](std::size_t index) {
          const auto &record = functionRecords->at(index);
          Archive header(record.header, *frozen, types.get(), revisions);
          FunctionHeader summary;
          header(summary);
          header.finish();
          Archive reader(record.payload, *frozen, types.get());
          reader.expressionReferences = frozen.get();
          deferExpressions(reader, record.payload);
          ImportedFunction decoded;
          function(reader, decoded);
          for (auto &local : decoded.contract().facts.locals)
            if (local.storage == StorageDuration::Static)
              reader.symbol(metadata::SymbolKind::Static, local.staticIndex);
          reader.finish();
          if (!header.good() || !reader.good())
            throw metadata::InvalidMetadata(
                "invalid checked function contract: " +
                (header.good() ? reader.error : header.error));
          if (!matchesHeader(summary, functionHeader(decoded)))
            throw metadata::InvalidMetadata(
                "checked function record does not match its signature index");
          validateDispatches(decoded, *types, *methods);
          return decoded;
        });
    for (std::size_t i = 0; i < compact->functions.size(); ++i)
      compact->functions.defer(i, i, loader);
  }
  archive(count);
  if (count > bytes.size())
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
  if (count > bytes.size())
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
  std::size_t phase = 0;
  for (const auto *database : {&value->checkingDatabase, &value->database}) {
    auto &counts = (*methods)[phase++];
    counts.reserve(database->definitions.size());
    for (const auto &definition : database->definitions)
      counts.push_back(definition.name.empty()
                           ? std::nullopt
                           : std::optional(definition.methods.size()));
  }
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
  std::map<std::tuple<SourceId, std::uint32_t, std::uint32_t>, std::size_t>
      implementationIndices;
  if (module)
    for (std::size_t i = 0; i < module->implementations.size(); ++i) {
      auto span = module->implementations[i].span;
      implementationIndices.emplace(
          std::tuple{span.source, span.begin, span.end}, i);
    }
  for (auto *database : {&value->checkingDatabase, &value->database})
    for (auto &rule : database->implementations) {
      rule.checkedImport = true;
      if (module) {
        auto found = implementationIndices.find(
            {rule.span.source, rule.span.begin, rule.span.end});
        if (found == implementationIndices.end()) {
          result.error = "checked implementation is absent from its header";
          return result;
        }
        rule.declaration = found->second;
      }
    }
  auto parameter = [&](Type type) {
    return value->types->isParameter(type) ||
           value->types->isConstParameter(type) ||
           value->types->isProjection(type);
  };
  auto parameters = [&](const std::vector<Type> &items) {
    return std::all_of(items.begin(), items.end(), parameter);
  };
  for (const auto *database : {&value->checkingDatabase, &value->database}) {
    for (auto [parameter, contract] : database->callableContracts)
      if (!value->types->isParameter(parameter) ||
          !value->types->isFunctionPointer(contract))
        archive.fail("invalid checked callable-bound contract");
    auto definition = [&](Type type) -> const interfaces::Definition * {
      if (!value->types->isErased(type))
        return nullptr;
      auto index = value->types->erasedDeclaration(type);
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
    for (const auto &[key, item] : database->structuralDeclarations) {
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
      for (const auto &dispatch : body->dispatches) {
        const auto *owner = definition(dispatch.interfaceType);
        if (dispatch.method < 0 || !owner ||
            static_cast<std::size_t>(dispatch.method) >=
                owner->methods.size() ||
            dispatch.self == Type::Unknown ||
            !value->types->contains(dispatch.self))
          archive.fail("invalid checked expression interface dispatch");
      }
    };
    for (const auto &[index, function] : value->functions) {
      (void)index;
      if (!function.isMaterialized())
        continue;
      expression(function->body);
      for (const auto &argument : function->defaults)
        expression(argument);
    }
  }
  if (!archive.good()) {
    result.error = std::move(archive.error);
    return result;
  }
  value->indexTypes();
  if (auto error = value->indexDeclarations(module); !error.empty()) {
    result.error = std::move(error);
    return result;
  }
  result.declarations = std::move(value);
  return result;
}
} // namespace mettle
