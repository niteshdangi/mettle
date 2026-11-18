#include "semantics/library.h"
#include "support/limits.h"
#include "types/layout.h"
#include "types/project.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <unordered_set>
#include <utility>

namespace mettle {
const DeclarationEnvironment &ImportedTypeDeclaration::environment() const {
  if (!deferred)
    return generics;
  std::call_once(deferred->once, [&] {
    deferred->value.emplace(deferred->load());
    deferred->load = {};
  });
  return *deferred->value;
}
std::array<const ImportedDeclarations::TypeTable *, 5>
ImportedDeclarations::typeTables() const {
  return {&products, &aliases, &interfaces, &implementations, &associated};
}

void ImportedDeclarations::indexTypes() {
  auto tables = typeTables();
  for (std::size_t i = 0; i < tables.size(); ++i) {
    auto &index = typeIndices[i];
    index.clear();
    index.reserve(tables[i]->size());
    for (std::size_t j = 0; j < tables[i]->size(); ++j) {
      auto span = (*tables[i])[j]->span;
      index.emplace_back(std::tuple{span.source, span.begin, span.end}, j);
    }
    std::sort(index.begin(), index.end());
  }
}

std::shared_ptr<const ImportedTypeDeclaration>
ImportedDeclarations::findType(Span span, const TypeTable &items) const {
  auto tables = typeTables();
  for (std::size_t i = 0; i < tables.size(); ++i) {
    if (tables[i] != &items || typeIndices[i].empty())
      continue;
    auto key = std::tuple{span.source, span.begin, span.end};
    auto found = std::lower_bound(typeIndices[i].begin(), typeIndices[i].end(),
                                  std::pair{key, std::size_t{0}});
    return found == typeIndices[i].end() || found->first != key
               ? nullptr
               : items.at(found->second);
  }
  auto found = std::find_if(items.begin(), items.end(), [&](const auto &item) {
    return item->span.source == span.source && item->span.begin == span.begin &&
           item->span.end == span.end;
  });
  return found == items.end() ? nullptr : *found;
}

std::string ImportedDeclarations::indexDeclarations(const Module *module) {
  auto result = std::make_shared<Index>();
  std::size_t spanCount = functions.size();
  for (const auto *items : typeTables())
    spanCount += items->size();
  result->spans.reserve(spanCount + statics.size());
  if (module)
    result->functions.resize(module->functions.size());
  auto remember = [&](Span span) {
    result->spans.emplace_back(span.source, span.begin, span.end);
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
    const auto &syntax = module->functions.header(position);
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
    auto declaration = module->functions.sharedHeader(position);
    auto name = std::string(function.symbolName());
    if (!name.empty()) {
      if (syntax.constructor) {
        auto suffix = name.rfind("$init");
        if (suffix == std::string::npos)
          return "checked constructor has no canonical ordinal";
        name.resize(suffix);
        ++result->constructorOrdinals[name];
      }
      result->functionNames.emplace(std::move(name), position);
    }
    result->functions[position] = {std::move(declaration), function};
  }
  if (module)
    module->functions.onMaterializeAll(
        [owner = std::weak_ptr(result)](
            std::size_t position, std::shared_ptr<const Function> declaration) {
          auto index = owner.lock();
          if (!index || !index->functions[position].declaration)
            return;
          const auto &function = index->functions[position].contract;
          std::lock_guard lock(index->annotationMutex);
          index->materializedFunctions.emplace(position, declaration);
          index->annotations.emplace(&declaration->annotation,
                                     function.resultType());
          index->annotations.emplace(&declaration->error, function.errorType());
          for (std::size_t p = 0; p < declaration->parameters.size() &&
                                  p < function.parameterCount();
               ++p)
            index->annotations.emplace(&declaration->parameters[p].annotation,
                                       function.parameterType(p));
        });
  for (const auto *items : typeTables())
    for (const auto &item : *items)
      remember(item->span);
  if (module)
    for (const auto &[position, facts] : statics) {
      (void)facts;
      if (position < module->statics.size())
        remember(module->statics.header(position).span);
    }
  std::multimap<std::tuple<SourceId, std::size_t, std::size_t>, std::size_t>
      implementationSpans;
  auto spanKey = [](Span span) {
    return std::tuple{span.source, span.begin, span.end};
  };
  if (module)
    for (std::size_t i = 0; i < module->implementations.size(); ++i) {
      implementationSpans.emplace(
          spanKey(module->implementations.header(i).span), i);
      result->implementationHeaders.push_back(
          module->implementations.sharedHeader(i));
    }
  for (std::size_t i = 0; i < checkingDatabase.definitions.size(); ++i)
    result->interfaceNames.emplace_back(checkingDatabase.definitionName(i));
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
    const auto &owner = module->implementations.header(found->second);
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
             ? module->implementations.sharedHeader(found->second)
             : nullptr});
  }
  if (module) {
    result->aliasHeaders.reserve(module->aliases.size());
    result->aliasTypes.resize(module->aliases.size());
    for (std::size_t i = 0; i < module->aliases.size(); ++i) {
      result->aliasHeaders.push_back(module->aliases.sharedHeader(i));
      if (module->aliases.header(i).item.checkedImport)
        if (auto contract = findType(module->aliases.header(i).span, aliases))
          result->aliasTypes[i] = contract->type;
    }
    module->aliases.onMaterializeAll(
        [owner = std::weak_ptr(result)](
            std::size_t position,
            std::shared_ptr<const Module::Alias> declaration) {
          if (auto index = owner.lock(); index && index->aliasTypes[position]) {
            std::lock_guard lock(index->annotationMutex);
            index->annotations.emplace(&declaration->target,
                                       *index->aliasTypes[position]);
            index->aliases.push_back(std::move(declaration));
          }
        });
  }
  std::sort(result->spans.begin(), result->spans.end());
  result->spans.erase(std::unique(result->spans.begin(), result->spans.end()),
                      result->spans.end());
  result->functionNames.freeze();
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
struct HeaderSources {
  std::map<std::tuple<SourceId, std::size_t, std::size_t>, std::uint64_t>
      indices;
  std::map<std::string, std::uint64_t, std::less<>> revisionOrdinals;
  std::vector<std::string> revisions;
  std::vector<std::array<std::uint64_t, 3>> references;
  std::vector<Span> spans;
};
class Archive {
public:
  explicit Archive(const metadata::EncodeReferences &references)
      : encode(&references),
        ownedRevisions(std::make_shared<std::vector<std::string>>()),
        revisions(ownedRevisions) {}
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
  template <class T> bool same(const T &left, const T &right) {
    Archive first(*encode, *types, hygiene);
    Archive second(*encode, *types, hygiene);
    first(left);
    second(right);
    if (!first.good() || !second.good()) {
      fail(first.good() ? std::move(second.error) : std::move(first.error));
      return false;
    }
    return first.output == second.output;
  }
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
    } else if constexpr (std::is_same_v<T, TypeSyntax>) {
      if (reading() && discarding)
        scanDiscardedType();
      else
        record(item);
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
    recordCollection<T>(items);
  }
  template <typename T> void value(interfaces::DatabaseRecords<T> &items) {
    recordCollection<T>(items);
  }
  template <typename T, class Records> void recordCollection(Records &items) {
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
      for (const auto &item : items) {
        if (!headerSources) {
          value(item);
          continue;
        }
        projectHeader(const_cast<T &>(item));
        Archive syntax(*encode, *types, hygiene);
        syntax.headerSources = headerSources;
        syntax(item);
        if (!syntax.good()) {
          fail(std::move(syntax.error));
          return;
        }
        writeBlock(syntax.output);
      }
      return;
    }
    if (count > input.size() - offset) {
      fail("declaration collection exceeds its payload");
      return;
    }
    if (readSyntax) {
      if (count > remaining() / minimumHeaderSize<T>()) {
        fail("declaration collection exceeds its payload");
        return;
      }
      items.reserve(static_cast<std::size_t>(count));
      struct Block {
        std::size_t begin, size;
        const T *header;
      };
      auto blocks = std::make_shared<std::vector<Block>>();
      blocks->reserve(static_cast<std::size_t>(count));
      auto loader = Declarations<T>::deferredLoader(
          static_cast<std::size_t>(count),
          [read = readSyntax, blocks](std::size_t index) {
            const auto &block = blocks->at(index);
            T value;
            read(block.begin, block.size, [&](Archive &archive) {
              archive(value);
              if (archive.good() && !archive.sameHeader(*block.header, value))
                archive.fail("declaration syntax does not match its query");
            });
            value.item.checkedImport = true;
            return value;
          });
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        auto &item =
            items.emplace_deferred(loader, static_cast<std::size_t>(i));
        projectHeader(item);
        item.item.checkedImport = true;
        auto payload = readBlock();
        blocks->push_back({position() - payload.size(), payload.size(), &item});
      }
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
    if constexpr (std::is_same_v<T, Node>)
      if (reading() && discarding && !scanningExpression) {
        discarding = false;
        scanSyntax();
        discarding = true;
        return;
      }
    bool present = bool(item);
    value(present);
    if (!good())
      return;
    if constexpr (std::is_same_v<T, TypeSyntax> ||
                  std::is_same_v<T, CallableTypeSyntax>)
      if (reading() && present && discarding) {
        T ignored;
        value(ignored);
        return;
      }
    if (reading() && present) {
      auto result = std::make_shared<T>();
      value(*result);
      item = std::move(result);
    } else if (present)
      value(*item);
  }
  template <typename K, typename V> void value(std::map<K, V> &items) {
    map(items);
  }
  template <typename K, typename V> void value(OverlayMap<K, V> &items) {
    map(items);
    if (reading())
      items.freeze();
  }
  template <typename K, typename V>
  void value(interfaces::DatabaseMap<K, V> &items) {
    map(items);
    if (reading())
      items.freeze();
  }
  template <typename Map> void map(Map &items) {
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
        typename Map::key_type key{};
        typename Map::mapped_type item{};
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
    if (literalSpans) {
      (*this)(span.source, span.begin, span.end);
      return;
    }
    if (headerSources) {
      std::uint64_t index = 0;
      if (!reading()) {
        auto key = std::tuple{span.source, span.begin, span.end};
        auto [found, inserted] = headerSources->indices.try_emplace(
            key, headerSources->references.size());
        index = found->second;
        if (inserted) {
          auto resolved = encode->source ? encode->source(span) : std::nullopt;
          if (!resolved || resolved->begin > resolved->end) {
            fail("unresolved declaration source revision");
            return;
          }
          auto [revision, newRevision] =
              headerSources->revisionOrdinals.try_emplace(
                  resolved->revision, headerSources->revisions.size());
          if (newRevision)
            headerSources->revisions.push_back(resolved->revision);
          headerSources->references.push_back(
              {revision->second, resolved->begin, resolved->end});
        }
      }
      value(index);
      if (reading() && good()) {
        if (index >= headerSources->spans.size())
          fail("unknown declaration source index");
        else
          span = headerSources->spans[index];
      }
      return;
    }
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
      else if (!discarding)
        signature = types->callable(carrier);
    }
  }
  void value(SyntaxContextPtr &context) {
    bool present = bool(context);
    value(present);
    if (!present || !good())
      return;
    SyntaxContext result = reading() ? SyntaxContext{} : *context;
    if (!reading() && result.identity && !literalSpans) {
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
      if (!discarding)
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
  std::size_t remaining() const { return input.size() - offset; }
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
  std::function<void(ImportedTypeDeclaration &, std::span<const std::uint8_t>)>
      deferEnvironment;
  std::function<void(std::size_t, std::size_t,
                     const std::function<void(Archive &)> &)>
      readSyntax;
  const std::map<std::tuple<SourceId, std::uint32_t, std::uint32_t>,
                 std::size_t> *implementationIndices = nullptr;
  template <class T> void projectHeader(T &declaration);
  template <class T> bool sameHeader(const T &left, const T &right);
  template <class T> std::size_t minimumHeaderSize() const;
  void scanTypeName(TypeSyntax &syntax);
  void scanDiscardedType();
  void typeEnvironment(ImportedTypeDeclaration &declaration);
  std::shared_ptr<HeaderSources> headerSources;
  const metadata::DecodeReferences *expressionReferences = nullptr;
  template <typename T> void record(T &item);
  std::vector<std::uint8_t> output;
  std::string error;
  TypeStore *types = nullptr;

private:
  friend void expression(Archive &, std::shared_ptr<CheckedExpression> &);
  const metadata::EncodeReferences *encode = nullptr;
  std::span<const std::uint8_t> input;
  const metadata::DecodeReferences *decode = nullptr;
  std::size_t offset = 0;
  unsigned depth = 0;
  bool scanningExpression = false, scanPrimary = false, discarding = false;
  bool literalSpans = false;
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
HEADER(LexicalNameSyntax, v.spelling, v.span, v.context)
HEADER(GenericArgument, v.type, v.value, v.region, v.span, v.binding)
HEADER(TypeSyntax, v.name, v.view, v.sources, v.regions, v.nested, v.form,
       v.ownerKind, v.elements, v.count, v.countExpression, v.arguments,
       v.callable, v.binders, v.context)
HEADER(CallableParameterSyntax, v.annotation, v.mode, v.name)
HEADER(CallableTypeSyntax, v.parameters, v.result, v.error, v.mode, v.regions,
       v.unsafeCall, v.abi, v.variadic)
HEADER(GenericParameter, v.kind, v.name, v.span, v.bounds, v.annotation,
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
HEADER(ItemSyntax, v.scope, v.visibility, v.attributes)
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
HEADER(Module::Associated, v.name, v.span, v.visibility, v.constant,
       v.asyncFuture, v.asyncFutureDefaultInferred, v.annotation, v.value,
       v.genericParameters, v.bounds, v.constraints)
HEADER(Module::Product::Variant, v.name, v.fields, v.span, v.attributes)
HEADER(Module::Product, v.name, v.span, v.copyRequested, v.fields, v.regions,
       v.hasDestructor, v.enumeration, v.unionType, v.variants, v.item,
       v.genericParameters, v.constraints, v.interfaces, v.associated,
       v.nameContext, v.deriveRequests)
HEADER(Module::Alias, v.name, v.target, v.span, v.item, v.genericParameters,
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
struct DiscardedSyntaxScanner {
  Archive &archive;
  template <class T> void value(std::type_identity<T>) {
    if constexpr (std::is_same_v<T, TypeSyntax>)
      archive.scanDiscardedType();
    else if constexpr (requires(T &item) {
                         headerFields(std::type_identity<T>{}, item);
                       })
      fields<T>();
    else {
      T item{};
      archive.discard(item);
    }
  }
  template <class T> void value(std::type_identity<std::vector<T>>) {
    auto count = archive.collectionSize();
    for (std::size_t i = 0; i < count && archive.good(); ++i)
      value(std::type_identity<T>{});
  }
  template <class T> void value(std::type_identity<std::shared_ptr<const T>>) {
    if constexpr (std::is_same_v<T, TypeSyntax> ||
                  std::is_same_v<T, CallableTypeSyntax>) {
      bool present = false;
      archive(present);
      if (present && archive.good())
        value(std::type_identity<T>{});
    } else {
      std::shared_ptr<const T> item;
      archive.discard(item);
    }
  }
  template <class Tuple, std::size_t... I>
  void fields(std::index_sequence<I...>) {
    (value(std::type_identity<
           std::remove_cvref_t<std::tuple_element_t<I, Tuple>>>{}),
     ...);
  }
  template <class T> void fields() {
    using Fields =
        decltype(headerFields(std::type_identity<T>{}, std::declval<T &>()));
    fields<Fields>(std::make_index_sequence<std::tuple_size_v<Fields>>{});
  }
};
void Archive::scanDiscardedType() {
  if (depth >= limits::syntaxDepth) {
    fail("checked declaration nesting limit exceeded");
    return;
  }
  ++depth;
  DiscardedSyntaxScanner{*this}.fields<TypeSyntax>();
  --depth;
}
template <class T>
constexpr bool omittedQueryField =
    std::is_same_v<T, TypeSyntax> || std::is_same_v<T, GenericConstraint> ||
    std::is_same_v<T, Attribute> ||
    std::is_same_v<T, std::shared_ptr<const Node>> ||
    std::is_same_v<T, std::optional<Pattern>>;
template <class T>
constexpr bool omittedQueryField<std::vector<T>> =
    std::is_same_v<T, TypeSyntax> || std::is_same_v<T, GenericConstraint> ||
    std::is_same_v<T, Attribute>;
struct DeclarationProjection {
  Archive &archive;
  struct TypeName {
    Archive &archive;
    template <class T> void value(T &item) {
      if constexpr (std::is_same_v<T, std::string> ||
                    std::is_same_v<T, TypeForm> ||
                    std::is_same_v<T, OwnerKind> ||
                    std::is_same_v<T, SyntaxContextPtr>)
        archive.keep(item);
    }
    void value(std::shared_ptr<const TypeSyntax> &item) {
      bool present = bool(item);
      archive(present);
      if (present && archive.good()) {
        if (archive.reading()) {
          auto nested = std::make_shared<TypeSyntax>();
          archive.scanTypeName(*nested);
          item = std::move(nested);
        } else
          archive.scanTypeName(const_cast<TypeSyntax &>(*item));
      }
    }
    void scan(TypeSyntax &item) {
      std::apply([&](auto &...fields) { (value(fields), ...); },
                 headerFields(std::type_identity<TypeSyntax>{}, item));
    }
  };
  template <class T> void namedDeclaration(T &item) {
    std::apply(
        [&](auto &...fields) {
          (
              [&] {
                if constexpr (std::is_same_v<
                                  std::remove_cvref_t<decltype(fields)>,
                                  TypeSyntax>)
                  archive.scanTypeName(fields);
                else
                  value(fields);
              }(),
              ...);
        },
        headerFields(std::type_identity<T>{}, item));
  }
  void value(Module::Alias &item) { namedDeclaration(item); }
  void value(Module::Implementation &item) { namedDeclaration(item); }
  void value(ItemSyntax &item) { archive.keep(item); }
  void value(Parameter &item) {
    auto fields = headerFields(std::type_identity<Parameter>{}, item);
    [&]<std::size_t... I>(std::index_sequence<I...>) {
      (value(std::get<I>(fields)), ...);
    }(std::make_index_sequence<std::tuple_size_v<decltype(fields)> - 1>{});
    bool hasDefault = item.defaultValue.get() || item.compiledDefault;
    archive(hasDefault);
    if (archive.reading())
      item.compiledDefault = hasDefault;
  }
  template <class T> void value(T &item) {
    if constexpr (omittedQueryField<T>)
      return;
    else if constexpr (requires {
                         headerFields(std::type_identity<T>{}, item);
                       }) {
      std::apply([&](auto &...fields) { (value(fields), ...); },
                 headerFields(std::type_identity<T>{}, item));
    } else
      archive.keep(item);
  }
  template <class T> void value(std::vector<T> &items) {
    if constexpr (!omittedQueryField<std::vector<T>>) {
      std::uint64_t count = items.size();
      archive(count);
      if (!archive.good())
        return;
      if (archive.reading()) {
        if (count > archive.remaining()) {
          archive.fail("declaration query collection exceeds its payload");
          return;
        }
        items.resize(static_cast<std::size_t>(count));
      }
      for (auto &item : items)
        value(item);
    }
  }
};
template <class T> std::size_t Archive::minimumHeaderSize() const {
  using Fields =
      decltype(headerFields(std::type_identity<T>{}, std::declval<T &>()));
  return []<std::size_t... I>(std::index_sequence<I...>) {
    return (
        std::size_t{0} + ... +
        std::size_t(!omittedQueryField<
                        std::remove_cvref_t<std::tuple_element_t<I, Fields>>> ||
                    ((std::is_same_v<T, Module::Alias> ||
                      std::is_same_v<T, Module::Implementation>) &&
                     std::is_same_v<
                         std::remove_cvref_t<std::tuple_element_t<I, Fields>>,
                         TypeSyntax>)));
  }(std::make_index_sequence<std::tuple_size_v<Fields>>{});
}
template <class T> void Archive::projectHeader(T &declaration) {
  DeclarationProjection{*this}.value(declaration);
}
template <class T> bool Archive::sameHeader(const T &left, const T &right) {
  metadata::EncodeReferences references;
  Archive first(references), second(references);
  first.literalSpans = second.literalSpans = true;
  first.projectHeader(const_cast<T &>(left));
  second.projectHeader(const_cast<T &>(right));
  return first.good() && second.good() && first.output == second.output;
}
void Archive::scanTypeName(TypeSyntax &syntax) {
  if (depth >= limits::syntaxDepth) {
    fail("checked declaration nesting limit exceeded");
    return;
  }
  ++depth;
  DeclarationProjection::TypeName{*this}.scan(syntax);
  --depth;
}
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
template <class A>
void signatureFields(A &a, ImportedFunction::SignatureIndex &v) {
  a(v.result, v.error, v.parameters, v.externalName);
}
void wire(Archive &a, ImportedFunction::SignatureIndex &v) {
  signatureFields(a, v);
}
template <class A> void functionHeaderFields(A &a, FunctionHeader &v) {
  a(v.span, v.signature, v.unsafeFunction, v.hasBody, v.body, v.defaults);
}
void wire(Archive &a, FunctionHeader &v) { functionHeaderFields(a, v); }
struct FunctionIndexScanner {
  Archive &archive;
  ImportedFunctionRecords &records;
  std::size_t parameters = 0, defaults = 0;
  template <class... T> void operator()(T &...items) { (value(items), ...); }
  template <class T> void value(T &item) { archive(item); }
  void value(ImportedFunction::SignatureIndex &signature) {
    signatureFields(*this, signature);
  }
  void value(std::vector<Type> &) {
    parameters = archive.collectionSize();
    for (std::size_t i = 0; i < parameters && archive.good(); ++i) {
      Type type = Type::Unknown;
      archive(type);
      records.parameters.push_back(type);
    }
  }
  void value(std::vector<std::optional<Span>> &) {
    defaults = archive.collectionSize();
    for (std::size_t i = 0; i < defaults && archive.good(); ++i) {
      std::optional<Span> span;
      archive(span);
      records.defaults.push_back(span.has_value());
    }
  }
};
WIRE(StaticFacts, v.name, v.externalName, v.library, v.type, v.initializer)
WIRE(DeclarationEnvironment, v.names, v.bounds, v.parameters, v.defaults,
     v.equalities, v.declarationSpan)
WIRE(DeclarationRegions, v.names, v.parameters, v.assumptions)
void wire(Archive &a, ImportedTypeDeclaration &v) { a.typeEnvironment(v); }
void Archive::typeEnvironment(ImportedTypeDeclaration &declaration) {
  (*this)(declaration.span, declaration.name, declaration.type,
          declaration.generics.parameters);
  if (!reading()) {
    Archive record(*encode, *types, hygiene);
    record(declaration.environment());
    if (!record.good())
      fail(std::move(record.error));
    else
      writeBlock(record.output);
    return;
  }
  auto payload = readBlock();
  if (!good())
    return;
  if (deferEnvironment) {
    deferEnvironment(declaration, payload);
    return;
  }
  auto parameters = std::move(declaration.generics.parameters);
  Archive reader(payload, *decode, types);
  reader(declaration.generics);
  reader.finish();
  if (!reader.good())
    fail(std::move(reader.error));
  else if (parameters != declaration.generics.parameters)
    fail("declaration environment does not match its parameter index");
}
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
  if (a.reading()) {
    v.checkedImport = true;
    if (a.implementationIndices) {
      auto found = a.implementationIndices->find(
          {v.span.source, v.span.begin, v.span.end});
      if (found == a.implementationIndices->end())
        a.fail("checked implementation is absent from its header");
      else
        v.declaration = found->second;
    }
  }
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
      a(std::as_const(v).definitions[i]);
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
template <class T>
void phaseRecords(Archive &archive,
                  const interfaces::DatabaseRecords<T> &checking,
                  interfaces::DatabaseRecords<T> &finalized,
                  bool interfaces = false) {
  std::uint64_t size = finalized.size();
  if (!interfaces)
    archive(size);
  if (archive.reading()) {
    if (!interfaces) {
      if (size > UINT32_MAX || (size > checking.size() &&
                                size - checking.size() > archive.remaining())) {
        archive.fail("checked phase inventory exceeds its representation");
        return;
      }
    }
    if (interfaces)
      size = checking.size();
  }
  std::vector<std::uint32_t> changed;
  if (!archive.reading())
    for (std::size_t i = 0; i < finalized.size(); ++i)
      if (i >= checking.size() ||
          !archive.same(checking[i], std::as_const(finalized)[i]))
        changed.push_back(static_cast<std::uint32_t>(i));
  std::uint64_t count = changed.size();
  archive(count);
  if (count > size) {
    archive.fail("checked phase changes exceed their inventory");
    return;
  }
  if (archive.reading() && !count) {
    finalized = checking;
    finalized.resize(static_cast<std::size_t>(size));
    return;
  }
  std::vector<std::pair<std::uint32_t, T>> replacements;
  if (archive.reading())
    replacements.reserve(static_cast<std::size_t>(count));
  std::set<std::uint32_t> seen;
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = archive.reading() ? 0 : changed[i];
    if (interfaces)
      archive.symbol(metadata::SymbolKind::Interface, index);
    else
      archive(index);
    if (index >= size || !seen.insert(index).second) {
      archive.fail("invalid checked phase record identity");
      break;
    }
    if (archive.reading()) {
      T item;
      archive(item);
      replacements.emplace_back(index, std::move(item));
    } else
      archive(std::as_const(finalized)[index]);
  }
  if (archive.reading() && archive.good()) {
    std::sort(replacements.begin(), replacements.end(),
              [](const auto &left, const auto &right) {
                return left.first < right.first;
              });
    interfaces::DatabaseRecords<T> records;
    records.reserve(static_cast<std::size_t>(size));
    auto replacement = replacements.begin();
    for (std::size_t i = 0; i < size; ++i)
      if (replacement != replacements.end() && replacement->first == i) {
        records.push_back(std::move(replacement->second));
        ++replacement;
      } else if (i < checking.size())
        records.push_shared(checking.retain(i));
      else
        records.push_uninitialized();
    finalized = std::move(records);
  }
}
template <class Map>
void phaseMap(Archive &archive, const Map &checking, Map &finalized) {
  bool shared = !archive.reading() && archive.same(checking, finalized);
  archive(shared);
  if (archive.reading())
    finalized = shared ? checking : Map{};
  if (!shared)
    archive(finalized);
}
void databases(Archive &archive, interfaces::Database &checking,
               interfaces::Database &finalized) {
  if (!archive.reading() &&
      checking.definitions.size() != finalized.definitions.size()) {
    archive.fail("checked interface phases have conflicting inventories");
    return;
  }
  archive(checking);
  if (archive.reading())
    finalized = checking;
  phaseRecords(archive, checking.definitions, finalized.definitions, true);
  phaseRecords(archive, checking.implementations, finalized.implementations);
  phaseRecords(archive, checking.projections, finalized.projections);
  phaseMap(archive, checking.unpinImplementations,
           finalized.unpinImplementations);
  phaseMap(archive, checking.structuralDeclarations,
           finalized.structuralDeclarations);
  archive(finalized.argumentsReady);
  phaseMap(archive, checking.callableContracts, finalized.callableContracts);
  if (archive.reading()) {
    finalized.implementationsByDeclaration.clear();
    finalized.indexedImplementations = 0;
    finalized.projectionsByParameter.clear();
    finalized.indexedProjections = 0;
  }
}
class DatabaseAdmission {
  struct Block {
    std::size_t offset, size;
  };
  template <class T> struct Records {
    std::shared_ptr<std::vector<Block>> blocks =
        std::make_shared<std::vector<Block>>();
    std::shared_ptr<const typename TypeRecords<T>::Loader> load;
  };
  using ImplementationIndices =
      std::map<std::tuple<SourceId, std::uint32_t, std::uint32_t>, std::size_t>;

public:
  DatabaseAdmission(
      Archive &archive, std::span<const std::uint8_t> bytes,
      std::shared_ptr<const void> storage,
      std::shared_ptr<const metadata::DecodeReferences> references,
      std::shared_ptr<TypeStore> types,
      std::shared_ptr<const ImplementationIndices> implementationIndices,
      const std::map<std::uint32_t, ImportedFunctionReference> &functions)
      : archive(archive), bytes(bytes), storage(std::move(storage)),
        references(std::move(references)), types(std::move(types)),
        implementationIndices(std::move(implementationIndices)),
        functions(functions) {}

  void read(interfaces::Database &checking, interfaces::Database &finalized) {
    auto definitions =
        std::make_shared<std::vector<interfaces::Database::DefinitionHeader>>();
    auto count = archive.collectionSize();
    if (count > limits::interfaces) {
      archive.fail("interface inventory exceeds the compiler representation");
      return;
    }
    std::set<std::uint32_t> seen;
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      auto index = std::uint32_t{0};
      archive.symbol(metadata::SymbolKind::Interface, index);
      if (index >= limits::interfaces || !seen.insert(index).second) {
        archive.fail("invalid checked interface identity");
        return;
      }
      if (checking.definitions.size() <= index) {
        checking.definitions.resize(std::size_t(index) + 1);
        definitions->resize(std::size_t(index) + 1);
      }
      record(checking.definitions, index, definitionRecords,
             [&] { definition((*definitions)[index]); });
    }
    if (!archive.good())
      return;
    for (const auto &header : *definitions)
      for (auto parent : header.parents)
        if (parent >= definitions->size() ||
            (*definitions)[parent].name.empty()) {
          archive.fail("unknown checked superinterface");
          return;
        }
    checking.importedDefinitions = definitions;
    auto implementations = std::make_shared<
        std::vector<interfaces::Database::ImplementationHeader>>();
    count = archive.collectionSize();
    checking.implementations.resize(count);
    implementations->resize(count);
    for (std::size_t i = 0; i < count && archive.good(); ++i)
      record(checking.implementations, i, implementationRecords,
             [&] { implementation((*implementations)[i], checking); });
    if (!archive.good())
      return;
    checking.importedImplementations = implementations;
    indexImplementations(checking);
    count = archive.collectionSize();
    checking.projections.resize(count);
    for (std::size_t i = 0; i < count && archive.good(); ++i)
      record(checking.projections, i, projectionRecords,
             [&] { projection(checking, i); });
    map(checking.unpinImplementations, checking, unpinRecords);
    map(checking.structuralDeclarations, checking, structuralRecords);
    archive(checking.argumentsReady, checking.callableContracts);
    validateCallableContracts(checking);
    if (!archive.good())
      return;
    checking.indexedProjections = checking.projections.size();
    checking.projectionsByParameter.freeze();
    finalized = checking;
    auto finalDefinitions = definitions;
    changes(checking.definitions, finalized.definitions, definitionRecords,
            true, [&](std::size_t index) {
              interfaces::Database::DefinitionHeader after;
              definition(after);
              const auto &before = (*definitions)[index];
              if (before.name != after.name ||
                  !sameSpan(before.span, after.span))
                archive.fail(
                    "checked interface phases have conflicting inventories");
              for (auto parent : after.parents)
                if (parent >= definitions->size() ||
                    (*definitions)[parent].name.empty())
                  archive.fail("unknown checked superinterface");
              if (before.methods != after.methods ||
                  before.parents != after.parents ||
                  before.associated != after.associated) {
                if (finalDefinitions == definitions)
                  finalDefinitions = std::make_shared<
                      std::vector<interfaces::Database::DefinitionHeader>>(
                      *definitions);
                (*finalDefinitions)[index] = std::move(after);
              }
            });
    finalized.importedDefinitions = finalDefinitions;
    if (!archive.good())
      return;
    auto finalImplementations = implementations;
    bool implementationIndexChanged = false;
    changes(checking.implementations, finalized.implementations,
            implementationRecords, false, [&](std::size_t index) {
              interfaces::Database::ImplementationHeader after;
              implementation(after, finalized);
              if (index >= implementations->size() ||
                  !sameSpan((*implementations)[index].span, after.span)) {
                archive.fail(
                    "checked interface phases have conflicting inventories");
                return;
              }
              const auto &before = (*implementations)[index];
              implementationIndexChanged |=
                  (types->isErased(before.interfaceType)
                       ? types->erasedDeclaration(before.interfaceType)
                       : UINT32_MAX) !=
                  (types->isErased(after.interfaceType)
                       ? types->erasedDeclaration(after.interfaceType)
                       : UINT32_MAX);
              if (before.interfaceType != after.interfaceType ||
                  before.inherent != after.inherent ||
                  before.fallback != after.fallback) {
                if (finalImplementations == implementations)
                  finalImplementations = std::make_shared<
                      std::vector<interfaces::Database::ImplementationHeader>>(
                      *implementations);
                (*finalImplementations)[index] = std::move(after);
              }
            });
    if (finalized.implementations.size() != checking.implementations.size())
      archive.fail("checked interface phases have conflicting inventories");
    finalized.importedImplementations = finalImplementations;
    if (!archive.good())
      return;
    if (implementationIndexChanged)
      indexImplementations(finalized);
    changes(checking.projections, finalized.projections, projectionRecords,
            false, [&](std::size_t index) { projection(finalized, index); });
    finalProjectionParameters.resize(finalized.projections.size());
    if (projectionIndexChanged ||
        finalized.projections.size() != checking.projections.size()) {
      finalized.projectionsByParameter.clear();
      for (std::size_t i = 0; i < finalProjectionParameters.size(); ++i)
        finalized.projectionsByParameter.emplace(finalProjectionParameters[i],
                                                 i);
    }
    mapPhase(checking.unpinImplementations, finalized.unpinImplementations,
             finalized, unpinRecords);
    mapPhase(checking.structuralDeclarations, finalized.structuralDeclarations,
             finalized, structuralRecords);
    archive(finalized.argumentsReady);
    phaseMap(archive, checking.callableContracts, finalized.callableContracts);
    validateCallableContracts(finalized);
    finalized.indexedProjections = finalized.projections.size();
    finalized.projectionsByParameter.freeze();
  }

private:
  Archive &archive;
  std::span<const std::uint8_t> bytes;
  std::shared_ptr<const void> storage;
  std::shared_ptr<const metadata::DecodeReferences> references;
  std::shared_ptr<TypeStore> types;
  std::shared_ptr<const ImplementationIndices> implementationIndices;
  const std::map<std::uint32_t, ImportedFunctionReference> &functions;
  Records<interfaces::Definition> definitionRecords;
  Records<interfaces::Implementation> implementationRecords;
  Records<interfaces::Projection> projectionRecords;
  Records<std::pair<Type, interfaces::Implementation>> unpinRecords;
  Records<std::pair<std::pair<interfaces::Property, Type>,
                    interfaces::StructuralPropertyDeclaration>>
      structuralRecords;
  std::vector<Type> finalProjectionParameters;
  bool projectionIndexChanged = false;

  static bool sameSpan(Span left, Span right) {
    return left.source == right.source && left.begin == right.begin &&
           left.end == right.end;
  }
  void indexImplementations(interfaces::Database &database) {
    const auto &headers = *database.importedImplementations;
    database.implementationsByDeclaration.clear();
    for (std::size_t i = 0; i < headers.size(); ++i) {
      auto interfaceType = headers[i].interfaceType;
      if (!types->isErased(interfaceType))
        continue;
      auto owner = types->erasedDeclaration(interfaceType);
      if (database.implementationsByDeclaration.size() <= owner)
        database.implementationsByDeclaration.resize(std::size_t(owner) + 1);
      database.implementationsByDeclaration[owner].push_back(i);
    }
    database.indexedImplementations = database.implementations.size();
  }
  template <class... T> void discard(T &...items) {
    (archive.discard(items), ...);
  }
  bool parameter(Type type) const {
    return types->isParameter(type) || types->isConstParameter(type) ||
           types->isProjection(type);
  }
  bool function(int index) const {
    return index >= 0 && functions.contains(std::uint32_t(index));
  }
  void parameters(const char *error) {
    auto count = archive.collectionSize();
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      Type type = Type::Unknown;
      archive(type);
      if (!parameter(type))
        archive.fail(error);
    }
  }
  template <class T> void loader(Records<T> &records) {
    if (!records.load)
      records.load = std::make_shared<const typename TypeRecords<T>::Loader>(
          [storage = storage, bytes = bytes, references = references,
           types = types, indices = implementationIndices,
           revisions = archive.sourceRevisions(),
           blocks = records.blocks](std::size_t index) {
            const auto &block = blocks->at(index);
            Archive reader(bytes.subspan(block.offset, block.size), *references,
                           types.get(), revisions);
            reader.implementationIndices = indices.get();
            T value;
            reader(value);
            reader.finish();
            if (!reader.good())
              throw metadata::InvalidMetadata(
                  "invalid checked interface record: " + reader.error);
            return value;
          });
  }
  template <class T, class Scan>
  void record(interfaces::DatabaseRecords<T> &target, std::size_t index,
              Records<T> &records, Scan scan) {
    auto begin = archive.position();
    scan();
    if (!archive.good())
      return;
    loader(records);
    auto ordinal = records.blocks->size();
    records.blocks->push_back({begin, archive.position() - begin});
    target.defer(index, ordinal, records.load);
  }
  template <class K, class V>
  void map(interfaces::DatabaseMap<K, V> &target,
           const interfaces::Database &database,
           Records<std::pair<K, V>> &records) {
    auto count = archive.collectionSize();
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      auto begin = archive.position();
      K key{};
      archive(key);
      if constexpr (std::is_same_v<V,
                                   interfaces::StructuralPropertyDeclaration>) {
        bool negative = false;
        archive(negative);
      }
      interfaces::Database::ImplementationHeader header;
      implementation(header, database);
      if (!archive.good())
        return;
      loader(records);
      auto ordinal = records.blocks->size();
      records.blocks->push_back({begin, archive.position() - begin});
      if (!target.defer(std::move(key), ordinal, records.load))
        archive.fail("duplicate declaration map key");
    }
    target.freeze();
  }
  template <class K, class V>
  void mapPhase(const interfaces::DatabaseMap<K, V> &checking,
                interfaces::DatabaseMap<K, V> &finalized,
                const interfaces::Database &database,
                Records<std::pair<K, V>> &records) {
    bool shared = false;
    archive(shared);
    if (shared)
      finalized = checking;
    else {
      finalized.clear();
      map(finalized, database, records);
    }
  }
  template <class T, class Scan>
  void changes(const interfaces::DatabaseRecords<T> &checking,
               interfaces::DatabaseRecords<T> &finalized, Records<T> &records,
               bool interfaces, Scan scan) {
    std::uint64_t size = checking.size();
    if (!interfaces)
      archive(size);
    if (size > UINT32_MAX || (size > checking.size() &&
                              size - checking.size() > archive.remaining())) {
      archive.fail("checked phase inventory exceeds its representation");
      return;
    }
    auto count = archive.collectionSize();
    if (count > size) {
      archive.fail("checked phase changes exceed their inventory");
      return;
    }
    finalized.resize(static_cast<std::size_t>(size));
    std::set<std::uint32_t> seen;
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      std::uint32_t index = 0;
      if (interfaces)
        archive.symbol(metadata::SymbolKind::Interface, index);
      else
        archive(index);
      if (index >= size || !seen.insert(index).second) {
        archive.fail("invalid checked phase record identity");
        return;
      }
      record(finalized, index, records, [&] { scan(index); });
    }
    if (size > checking.size())
      for (auto i = checking.size(); i < size; ++i)
        if (!seen.contains(static_cast<std::uint32_t>(i))) {
          archive.fail("missing checked phase record");
          return;
        }
  }
  const interfaces::Database::DefinitionHeader *
  owner(Type type, const interfaces::Database &database) const {
    if (!types->isErased(type))
      return nullptr;
    auto index = types->erasedDeclaration(type);
    const auto &headers = *database.importedDefinitions;
    return index < headers.size() && !headers[index].name.empty()
               ? &headers[index]
               : nullptr;
  }
  void definition(interfaces::Database::DefinitionHeader &header) {
    header = {};
    interfaces::Definition item;
    archive(header.name, header.span);
    archive.package(item.package);
    archive(item.self);
    if (!types->isParameter(item.self) && !header.name.empty())
      archive.fail("invalid checked interface parameter inventory");
    parameters("invalid checked interface parameter inventory");
    auto count = archive.collectionSize();
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      interfaces::Obligation parent;
      archive(parent);
      if (parent.property == interfaces::Property::Interface &&
          types->isErased(parent.interfaceType))
        header.parents.push_back(
            types->erasedDeclaration(parent.interfaceType));
    }
    count = archive.collectionSize();
    header.associated = count;
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      interfaces::Associated associated;
      archive.discard(associated.name);
      archive(associated.parameter);
      if (!parameter(associated.parameter))
        archive.fail("invalid checked associated parameter inventory");
      parameters("invalid checked associated parameter inventory");
      discard(associated.defaultValue, associated.bounds,
              associated.requirements, associated.constant, associated.regions,
              associated.regionRequirements, associated.asyncFuture,
              associated.asyncFutureDefaultInferred, associated.equalities,
              associated.defaults);
    }
    count = archive.collectionSize();
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      interfaces::Method method;
      archive(method.name);
      archive.symbol(metadata::SymbolKind::Function, method.function);
      if (!function(method.function))
        archive.fail("unknown checked interface method");
      header.methods.push_back(std::move(method.name));
      discard(method.signature, method.implicitParameters, method.dispatchable);
    }
    discard(item.regions, item.regionRequirements, item.requirements,
            item.equalities, item.unsafeInterface);
  }
  void binding(const char *error) {
    interfaces::MethodBinding item;
    archive.symbol(metadata::SymbolKind::Function, item.function);
    if (!function(item.function))
      archive.fail(error);
    discard(item.arguments, item.defaultMethod);
  }
  void implementation(interfaces::Database::ImplementationHeader &header,
                      const interfaces::Database &database) {
    header = {};
    interfaces::Implementation item;
    archive(item.target, header.interfaceType, header.span);
    archive.package(item.package);
    if (!types->contains(item.target))
      archive.fail("invalid checked implementation parameter inventory");
    parameters("invalid checked implementation parameter inventory");
    archive.discard(item.requirements);
    auto *definition = owner(header.interfaceType, database);
    if (header.interfaceType != Type::Unknown && !definition)
      archive.fail("unknown checked implementation interface");
    auto count = archive.collectionSize();
    std::set<std::size_t> seen;
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      std::size_t ordinal = 0;
      archive(ordinal);
      if (!definition || ordinal >= definition->methods.size() ||
          !seen.insert(ordinal).second)
        archive.fail("invalid checked implementation method");
      binding("invalid checked implementation method");
    }
    count = archive.collectionSize();
    seen.clear();
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      std::size_t ordinal = 0;
      archive(ordinal);
      if (!definition || ordinal >= definition->associated ||
          !seen.insert(ordinal).second)
        archive.fail("invalid checked implementation associated item");
      interfaces::AssociatedValue associated;
      parameters("invalid checked implementation associated item");
      discard(associated.value, associated.regions,
              associated.regionRequirements, associated.requirements,
              associated.fromDefault);
      archive.symbol(metadata::SymbolKind::Function, associated.initializer);
    }
    count = archive.collectionSize();
    std::set<std::string> names;
    for (std::size_t i = 0; i < count && archive.good(); ++i) {
      std::string name;
      archive(name);
      if (!names.insert(name).second)
        archive.fail("duplicate declaration map key");
      header.inherent.push_back(std::move(name));
      binding("unknown checked inherent method");
    }
    discard(item.regions, item.regionRequirements, item.equalities);
    archive(header.fallback);
    if (implementationIndices) {
      auto found = implementationIndices->find(
          {header.span.source, header.span.begin, header.span.end});
      if (found == implementationIndices->end())
        archive.fail("checked implementation is absent from its header");
      else
        header.declaration = found->second;
    }
  }
  void projection(interfaces::Database &database, std::size_t index) {
    interfaces::Projection item{};
    archive(item.parameter, item.subject, item.interfaceType, item.associated);
    discard(item.arguments, item.regionArguments);
    auto *definition = owner(item.interfaceType, database);
    if (!definition || item.associated >= definition->associated ||
        !parameter(item.parameter) || !types->contains(item.subject))
      archive.fail("invalid checked associated projection");
    if (finalProjectionParameters.size() <= index)
      finalProjectionParameters.resize(index + 1, Type::Unknown);
    else
      projectionIndexChanged |=
          finalProjectionParameters[index] != item.parameter;
    finalProjectionParameters[index] = item.parameter;
    database.projectionsByParameter.emplace(item.parameter, index);
  }
  void validateCallableContracts(const interfaces::Database &database) {
    for (const auto &[parameter, contract] : database.callableContracts)
      if (!types->isParameter(parameter) || !types->isFunctionPointer(contract))
        archive.fail("invalid checked callable-bound contract");
  }
};
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
  header.headerSources = std::make_shared<HeaderSources>();
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
  Archive framed(references, *module.types, header.hygieneState());
  framed.tag("mettle.checked-header.4");
  framed(header.headerSources->revisions, header.headerSources->references);
  framed.writeBlock(header.output);
  result.header = std::move(framed.output);
  decltype(header.output){}.swap(header.output);
  header.headerSources.reset();
  Archive contracts(references, *module.types, header.hygieneState());
  contracts.tag("mettle.checked-contracts.17");
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
  databases(contracts, value.checkingDatabase, value.database);
  result.contracts = std::move(contracts.output);
  result.error = std::move(contracts.error);
  return result;
}

LibraryHeaderImport
decodeLibraryHeader(std::span<const std::uint8_t> bytes,
                    const metadata::DecodeReferences &references,
                    std::shared_ptr<const void> backing) {
  LibraryHeaderImport result;
  if (!backing) {
    auto storage = std::make_shared<const std::vector<std::uint8_t>>(
        bytes.begin(), bytes.end());
    bytes = *storage;
    backing = std::move(storage);
  }
  auto storage =
      std::shared_ptr<const std::uint8_t>(std::move(backing), bytes.data());
  Archive envelope(bytes, references, nullptr);
  envelope.tag("mettle.checked-header.4");
  auto sources = std::make_shared<HeaderSources>();
  envelope(sources->revisions, sources->references);
  std::unordered_set<std::string_view> revisions;
  for (const auto &revision : sources->revisions)
    if (!revisions.insert(revision).second)
      envelope.fail("duplicate declaration source revision");
  sources->spans.reserve(sources->references.size());
  std::vector<std::size_t> order;
  std::vector<std::optional<Span>> ranges;
  if (references.sourceRange)
    ranges.resize(sources->revisions.size());
  else
    order.reserve(sources->references.size());
  metadata::SourceReference reference;
  auto revisionIndex = sources->revisions.size();
  for (const auto &source : sources->references) {
    if (!envelope.good())
      break;
    if (source[0] >= sources->revisions.size() || source[1] > source[2] ||
        source[2] > UINT32_MAX) {
      envelope.fail("invalid declaration source reference");
      break;
    }
    std::optional<Span> span;
    if (references.sourceRange) {
      auto &range = ranges[source[0]];
      if (!range)
        range = references.sourceRange(sources->revisions[source[0]]);
      if (range && range->begin <= range->end &&
          source[2] <= range->end - range->begin)
        span = Span{range->begin + source[1], range->begin + source[2],
                    range->source};
    } else {
      if (source[0] != revisionIndex) {
        reference.revision = sources->revisions[source[0]];
        revisionIndex = source[0];
      }
      reference.begin = static_cast<std::uint32_t>(source[1]);
      reference.end = static_cast<std::uint32_t>(source[2]);
      span = references.source ? references.source(reference) : std::nullopt;
      order.push_back(sources->spans.size());
    }
    if (!span) {
      envelope.fail("unknown declaration source revision");
      break;
    }
    sources->spans.push_back(*span);
  }
  if (envelope.good() && !references.sourceRange) {
    std::sort(order.begin(), order.end(), [&](auto left, auto right) {
      return sources->references[left] < sources->references[right];
    });
    for (std::size_t i = 1; i < order.size(); ++i)
      if (sources->references[order[i - 1]] == sources->references[order[i]] &&
          sources->spans[order[i - 1]] != sources->spans[order[i]])
        envelope.fail("conflicting declaration source binding");
  }
  auto payload = envelope.readBlock();
  envelope.finish();
  if (!envelope.good()) {
    result.error = std::move(envelope.error);
    return result;
  }
  decltype(sources->references){}.swap(sources->references);
  decltype(sources->revisions){}.swap(sources->revisions);
  auto frozen = std::make_shared<const metadata::DecodeReferences>();
  Archive archive(payload, *frozen, nullptr);
  archive.headerSources = sources;
  archive.readSyntax = [storage, frozen, sources,
                        payload](std::size_t begin, std::size_t size,
                                 const std::function<void(Archive &)> &decode) {
    Archive reader(payload.subspan(begin, size), *frozen, nullptr);
    reader.headerSources = sources;
    decode(reader);
    reader.finish();
    if (!reader.good())
      throw metadata::InvalidMetadata("invalid checked syntax: " +
                                      reader.error);
  };
  Module module;
  archive(module);
  archive(result.symbols);
  archive(result.types);
  archive.finish();
  if (!archive.good())
    result.error = std::move(archive.error);
  else {
    std::vector<std::vector<std::size_t>> methods(
        module.implementations.size());
    for (std::size_t i = 0; i < module.functions.size(); ++i) {
      const auto &function = module.functions.header(i);
      if (function.implementation >= 0 &&
          std::size_t(function.implementation) >=
              module.implementations.size()) {
        result.error = "invalid declaration implementation reference";
        return result;
      }
      if (function.implementation >= 0)
        methods[function.implementation].push_back(i);
    }
    for (std::size_t i = 0; i < methods.size(); ++i) {
      const auto &declared = module.implementations.header(i).methodFunctions;
      for (auto function : declared)
        if (function >= module.functions.size()) {
          result.error = "invalid declaration method reference";
          return result;
        }
      if (methods[i].empty())
        continue;
      auto indexed = declared;
      if (declared.empty())
        indexed = std::move(methods[i]);
      else {
        std::unordered_set<std::size_t> seen(declared.begin(), declared.end());
        for (auto function : methods[i])
          if (seen.insert(function).second)
            indexed.push_back(function);
      }
      if (indexed != declared)
        module.implementations.transformHeader(
            i, [indexed = std::move(indexed)](auto &implementation) {
              implementation.methodFunctions = indexed;
            });
    }
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
    for (std::size_t i = 0; i < items.size(); ++i) {
      auto span = [&] {
        if constexpr (requires { items.header(i); })
          return items.header(i).span;
        else
          return items[i].span;
      }();
      if (source(span))
        context(i, items[i]);
    }
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
  for (const auto &storage : module.statics.headers())
    if (source(storage.span))
      context(storage.initializer);
  auto associated = [&](const auto &owners) {
    for (const auto &owner : owners)
      if (source(owner.span))
        for (const auto &item : owner.associated)
          context(item.constantValue);
  };
  associated(module.interfaces.headers());
  associated(module.implementations.headers());
  for (const auto &product : module.products.headers())
    if (source(product.span))
      for (const auto &variant : product.variants)
        context(variant.discriminant);
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    if (!source(module.functions.header(i).span))
      continue;
    const auto &function = module.functions[i];
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
      if (projected->deferred) {
        projected->generics = item->environment();
        projected->deferred.reset();
      }
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

DeclarationPayloadLayout
declarationPayloadLayout(std::span<const std::uint8_t> bytes) {
  DeclarationPayloadLayout result;
  metadata::DecodeReferences references;
  references.type = [](std::uint32_t) { return std::optional{Type::Unknown}; };
  references.source = [](const metadata::SourceReference &source) {
    return std::optional{Span{source.begin, source.end, 0}};
  };
  references.symbol = [](metadata::SymbolKind, std::string_view) {
    return std::optional<std::uint32_t>{0};
  };
  Archive archive(bytes, references, nullptr);
  archive.tag("mettle.checked-contracts.17");
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size())
    archive.fail("function inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Function, index);
    FunctionHeader summary;
    archive.discard(summary);
    auto payload = archive.readBlock();
    if (archive.good())
      result.payloads.push_back(
          {archive.position() - payload.size(), payload.size()});
  }
  result.error = std::move(archive.error);
  return result;
}

LibraryDeclarationImport importLibraryDeclarations(
    std::span<const std::uint8_t> bytes, std::shared_ptr<TypeStore> types,
    const metadata::DecodeReferences &references, const Module *module,
    std::shared_ptr<const void> backing,
    std::shared_ptr<const metadata::DecodeReferences> retainedReferences,
    metadata::ValidationMode validation,
    std::span<const std::string_view> functionNames,
    std::function<bool(std::size_t, std::span<const std::uint8_t>)>
        verifyPayload) {
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
      auto [found, inserted] = remapping->types.try_emplace(id, *value);
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
          positions.try_emplace(Remapping::position(source), *value);
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
  std::map<std::tuple<SourceId, std::uint32_t, std::uint32_t>, std::size_t>
      implementationIndices;
  if (module)
    for (std::size_t i = 0; i < module->implementations.size(); ++i) {
      auto span = module->implementations.header(i).span;
      implementationIndices.emplace(
          std::tuple{span.source, span.begin, span.end}, i);
    }
  if (module)
    archive.implementationIndices = &implementationIndices;
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
  archive.tag("mettle.checked-contracts.17");
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
  if (validation == metadata::ValidationMode::OnDemand)
    archive.deferEnvironment = [storage, frozen,
                                types](ImportedTypeDeclaration &declaration,
                                       std::span<const std::uint8_t> payload) {
      declaration.deferred =
          std::make_shared<ImportedTypeDeclaration::Deferred>();
      declaration.deferred->load = [storage, frozen, types, payload,
                                    parameters =
                                        declaration.generics.parameters] {
        Archive reader(payload, *frozen, types.get());
        DeclarationEnvironment environment;
        reader(environment);
        reader.finish();
        if (!reader.good())
          throw metadata::InvalidMetadata("invalid declaration environment: " +
                                          reader.error);
        if (environment.parameters != parameters)
          throw metadata::InvalidMetadata(
              "declaration environment does not match its parameter "
              "index");
        return environment;
      };
    };
  auto compact = std::make_shared<ImportedFunctionRecords>();
  struct FunctionRecord {
    std::span<const std::uint8_t> header, payload;
    std::size_t ordinal;
  };
  auto functionRecords = std::make_shared<std::vector<FunctionRecord>>();
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size())
    archive.fail("function inventory exceeds its payload");
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    std::uint32_t index = 0;
    archive.symbol(metadata::SymbolKind::Function, index);
    std::string symbolName;
    if (!functionNames.empty()) {
      if (index >= functionNames.size() || functionNames[index].empty()) {
        archive.fail("checked function has no admitted canonical name");
        break;
      }
      symbolName = functionNames[index];
    }
    auto headerBegin = archive.position();
    FunctionHeader summary;
    auto parameterBegin = compact->parameters.size();
    FunctionIndexScanner scanner{archive, *compact};
    if (validation == metadata::ValidationMode::OnDemand)
      functionHeaderFields(scanner, summary);
    else
      archive(summary);
    auto headerBytes =
        bytes.subspan(headerBegin, archive.position() - headerBegin);
    auto payload = archive.readBlock();
    if (!archive.good())
      break;
    if (validation == metadata::ValidationMode::OnDemand
            ? scanner.defaults != scanner.parameters
            : summary.defaults.size() != summary.signature.parameters.size()) {
      archive.fail("invalid checked function signature inventory");
      break;
    }
    if (validation == metadata::ValidationMode::OnDemand) {
      auto ordinal = compact->headers.size();
      compact->headers.push_back(
          {summary.span, summary.signature.result, summary.signature.error,
           parameterBegin, scanner.parameters, summary.hasBody,
           std::move(summary.signature.externalName), std::move(symbolName)});
      functionRecords->push_back(
          {headerBytes, payload, static_cast<std::size_t>(i)});
      compact->functions.push_uninitialized();
      if (!value->functions
               .emplace(index, ImportedFunctionReference(compact, ordinal))
               .second)
        archive.fail("duplicate checked function identity");
      continue;
    }
    ImportedFunction item;
    item.symbolName = std::move(symbolName);
    if (validation == metadata::ValidationMode::Eager) {
      if (verifyPayload &&
          !verifyPayload(static_cast<std::size_t>(i), payload)) {
        archive.fail("checked function payload integrity mismatch");
        break;
      }
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
                                   methods, deferExpressions, verifyPayload,
                                   ordinal = static_cast<std::size_t>(i)] {
      if (verifyPayload && !verifyPayload(ordinal, payload))
        throw metadata::InvalidMetadata(
            "checked function payload integrity mismatch");
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
         revisions, verifyPayload](std::size_t index) {
          const auto &record = functionRecords->at(index);
          if (verifyPayload && !verifyPayload(record.ordinal, record.payload))
            throw metadata::InvalidMetadata(
                "checked function payload integrity mismatch");
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
  auto indices = module
                     ? std::make_shared<const decltype(implementationIndices)>(
                           implementationIndices)
                     : nullptr;
  DatabaseAdmission(archive, bytes, storage, frozen, types, std::move(indices),
                    value->functions)
      .read(value->checkingDatabase, value->database);
  if (!archive.good()) {
    result.error = std::move(archive.error);
    return result;
  }
  std::size_t phase = 0;
  for (const auto *database : {&value->checkingDatabase, &value->database}) {
    auto &counts = (*methods)[phase++];
    counts.reserve(database->definitions.size());
    for (std::size_t i = 0; i < database->definitions.size(); ++i) {
      auto name = database->definitionName(i);
      auto count = (*database->importedDefinitions)[i].methods.size();
      counts.push_back(name.empty() ? std::nullopt : std::optional(count));
    }
  }
  archive.finish();
  if (!archive.good()) {
    result.error = std::move(archive.error);
    return result;
  }
  try {
    for (const auto &[index, function] : value->functions) {
      (void)index;
      if (function.isMaterialized())
        validateDispatches(*function, *types, *methods);
    }
  } catch (const metadata::InvalidMetadata &error) {
    result.error = error.what();
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
