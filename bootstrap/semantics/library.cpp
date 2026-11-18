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
namespace {
std::string validateNativeOverrides(const Module &module);
}
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
  if (catalog)
    return;
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
    if (catalog && tables[i] == &items) {
      auto ordinal = catalog->typeOrdinal(i, span);
      if (ordinal)
        return *ordinal < items.size() ? items.at(*ordinal) : nullptr;
      for (std::size_t j = nativeTypeCounts[i]; j < items.size(); ++j)
        if (items[j]->span == span)
          return items[j];
      return nullptr;
    }
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
  if (catalog && module) {
    if (auto error = validateNativeOverrides(*module); !error.empty())
      return error;
    auto contracts = std::make_shared<const ImportedFunctionTable>(functions);
    module->functions.onMaterializeAll(
        [owner = std::weak_ptr(result), contracts](
            std::size_t position, std::shared_ptr<const Function> declaration) {
          if (position >= contracts->nativeSize())
            return;
          auto index = owner.lock();
          if (!index)
            return;
          const auto &function = contracts->at(position);
          if (declaration->span != function.span() ||
              declaration->parameters.size() != function.defaultCount() ||
              declaration->parameters.size() > function.parameterCount() ||
              declaration->body.get())
            throw metadata::InvalidMetadata(
                "checked function does not match its indexed declaration");
          for (std::size_t p = 0; p < declaration->parameters.size(); ++p)
            if (declaration->parameters[p].compiledDefault !=
                function.hasDefault(p))
              throw metadata::InvalidMetadata(
                  "checked default does not match its indexed declaration");
          std::lock_guard lock(index->annotationMutex);
          index->materializedFunctions.emplace(position, declaration);
          index->annotations.emplace(&declaration->annotation,
                                     function.resultType());
          index->annotations.emplace(&declaration->error, function.errorType());
          for (std::size_t p = 0; p < declaration->parameters.size(); ++p)
            index->annotations.emplace(&declaration->parameters[p].annotation,
                                       function.parameterType(p));
        });
    module->aliases.onMaterializeAll(
        [owner = std::weak_ptr(result), aliases = aliases, catalog = catalog](
            std::size_t, std::shared_ptr<const Module::Alias> declaration) {
          auto position = catalog->typeOrdinal(1, declaration->span);
          auto index = owner.lock();
          if (!position || !index)
            return;
          std::lock_guard lock(index->annotationMutex);
          index->annotations.emplace(&declaration->target,
                                     aliases.at(*position)->type);
          index->aliases.push_back(std::move(declaration));
        });
    index = std::move(result);
    return {};
  }
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
    for (std::size_t i = module->implementations.nativeSize();
         i < module->implementations.size(); ++i) {
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
  std::map<SourceId, std::string> mountedRevisions;
  std::map<SourceId, std::optional<std::pair<std::size_t, std::size_t>>>
      mountedOrigins;
  std::optional<std::pair<std::size_t, std::size_t>>
  coordinates(Span span) const {
    auto origin = mountedOrigins.find(span.source);
    if (origin != mountedOrigins.end() && origin->second) {
      auto [raw, mounted] = *origin->second;
      auto translate = [&](std::size_t point) -> std::optional<std::size_t> {
        if (point >= mounted) {
          auto delta = point - mounted;
          if (delta <= UINT32_MAX - raw)
            return raw + delta;
        } else if (mounted - point <= raw)
          return raw - (mounted - point);
        return std::nullopt;
      };
      auto begin = translate(span.begin), end = translate(span.end);
      if (begin && end)
        return std::pair{*begin, *end};
      return std::nullopt;
    }
    for (std::size_t i = 0; i < references.size(); ++i)
      if (spans[i] == span)
        return std::pair{std::size_t(references[i][1]),
                         std::size_t(references[i][2])};
    return std::nullopt;
  }
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
      : types(types), input(input), decode(&references), hygiene(nullptr),
        revisions(std::move(sourceRevisions)) {}
  bool reading() const { return decode != nullptr; }
  std::shared_ptr<Hygiene> hygieneState() const { return hygiene; }
  const metadata::EncodeReferences &encoding() const { return *encode; }
  const metadata::DecodeReferences &decoding() const { return *decode; }
  std::shared_ptr<const std::vector<std::string>> sourceRevisions() {
    if (!revisions) {
      ownedRevisions = std::make_shared<std::vector<std::string>>();
      revisions = ownedRevisions;
    }
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
  std::string_view textView() {
    std::uint64_t size = 0;
    value(size);
    if (!good() || size > remaining()) {
      fail("declaration string exceeds its payload");
      return {};
    }
    auto result = std::string_view(
        reinterpret_cast<const char *>(input.data() + offset), size);
    offset += size;
    return result;
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
      if (headerSources) {
        Archive records(*encode, *types, hygiene);
        std::vector<std::uint8_t> offsets;
        offsets.reserve(items.size() * sizeof(std::uint64_t));
        for (const auto &item : items) {
          auto position = std::uint64_t(records.output.size());
          for (unsigned byte = 0; byte < sizeof(position); ++byte)
            offsets.push_back(std::uint8_t(position >> (byte * 8)));
          Archive header(*encode, *types, hygiene);
          header.headerSources = headerSources;
          header.projectHeader(const_cast<T &>(item));
          Archive syntax(*encode, *types, hygiene);
          syntax.headerSources = headerSources;
          syntax(item);
          if (!header.good() || !syntax.good()) {
            fail(header.good() ? std::move(syntax.error)
                               : std::move(header.error));
            return;
          }
          records.writeBlock(header.output);
          records.writeBlock(syntax.output);
        }
        writeBlock(offsets);
        writeBlock(records.output);
        return;
      }
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
      auto offsets = readBlock();
      auto records = readBlock();
      if (!good() || count > offsets.size() / sizeof(std::uint64_t) ||
          offsets.size() != count * sizeof(std::uint64_t)) {
        fail("invalid indexed declaration directory");
        return;
      }
      auto recordOffset = [offsets](std::size_t index) {
        std::uint64_t result = 0;
        for (unsigned byte = 0; byte < sizeof(result); ++byte)
          result |= std::uint64_t(offsets[index * sizeof(result) + byte])
                    << (byte * 8);
        return result;
      };
      auto base = position() - records.size();
      Archive frames(records, *decode, types, sourceRevisions());
      frames.headerSources = headerSources;
      for (std::uint64_t i = 0; i < count && good(); ++i) {
        if (recordOffset(i) != frames.position()) {
          fail("invalid indexed declaration offset");
          break;
        }
        auto header = frames.readBlock();
        frames.readBlock();
        Archive scan(header, *decode, types, sourceRevisions());
        scan.headerSources = headerSources;
        scan.scanningProjection = true;
        T discarded;
        scan.projectHeader(discarded);
        scan.finish();
        if (!scan.good())
          fail(std::move(scan.error));
      }
      frames.finish();
      if (!frames.good())
        fail(std::move(frames.error));
      if (!good())
        return;
      auto read = readSyntax;
      auto block = [read, base, records, recordOffset](
                       std::size_t index, bool syntax,
                       const std::function<void(Archive &)> &decode) {
        auto begin = recordOffset(index);
        read(base + begin, records.size() - begin, [&](Archive &frame) {
          auto header = frame.readBlock();
          auto payload = frame.readBlock();
          auto selected = syntax ? payload : header;
          read(base + begin + (selected.data() - (records.data() + begin)),
               selected.size(), decode);
          frame.offset = frame.input.size();
        });
      };
      auto header = [block](std::size_t index) {
        T value;
        block(index, false,
              [&](Archive &reader) { reader.projectHeader(value); });
        value.item.checkedImport = true;
        return value;
      };
      items.mountIndexed(
          static_cast<std::size_t>(count), header,
          [header, block](std::size_t index) {
            T value;
            block(index, true, [&](Archive &reader) {
              reader(value);
              auto expected = header(index);
              if (reader.good() && !reader.sameHeader(expected, value))
                reader.fail("declaration syntax does not match its query");
            });
            value.item.checkedImport = true;
            return value;
          });
      return;
    }
    items.reserve(static_cast<std::size_t>(count));
    for (std::uint64_t i = 0; i < count && good(); ++i) {
      T item;
      value(item);
      items.push_back(std::move(item));
    }
  }
  template <class Declaration, class Table, class Read>
  void indexedDeclarations(Table &items, Read read) {
    std::uint64_t count = items.size();
    value(count);
    std::size_t category = 0;
    if constexpr (std::is_same_v<Declaration, ImportedTypeDeclaration>) {
      category = nextTypeTable++;
      if (declarationIndex && count != declarationIndex->typeCount(category))
        fail("checked type count does not match its declaration directory");
    } else if (declarationIndex && count != declarationIndex->constantCount())
      fail("checked constant count does not match its declaration directory");
    if (!good())
      return;
    if (!reading()) {
      Archive records(*encode, *types, hygiene);
      std::vector<std::uint8_t> offsets;
      for (const auto &item : items) {
        auto offset = std::uint64_t(records.output.size());
        for (unsigned byte = 0; byte < sizeof(offset); ++byte)
          offsets.push_back(std::uint8_t(offset >> (byte * 8)));
        if constexpr (requires { *item; })
          records(*item);
        else
          records(item);
      }
      if (!records.good())
        fail(std::move(records.error));
      writeBlock(offsets);
      writeBlock(records.output);
      return;
    }
    auto offsets = readBlock();
    auto records = readBlock();
    if (count > offsets.size() / sizeof(std::uint64_t) ||
        offsets.size() != count * sizeof(std::uint64_t)) {
      fail("invalid checked type declaration directory");
      return;
    }
    auto recordOffset = [offsets](std::size_t index) {
      std::uint64_t result = 0;
      for (unsigned byte = 0; byte < sizeof(result); ++byte)
        result |= std::uint64_t(offsets[index * sizeof(result) + byte])
                  << (byte * 8);
      return static_cast<std::size_t>(result);
    };
    Archive scan(records, *decode, types);
    scan.deferEnvironment = deferEnvironment;
    if (prepareIndexedReader)
      prepareIndexedReader(scan, records);
    auto revisions = scan.sourceRevisions();
    for (std::size_t i = 0; i < count && good() && scan.good(); ++i) {
      if (recordOffset(i) != scan.position()) {
        scan.fail("invalid checked type declaration offset");
        break;
      }
      Declaration item;
      scan(item);
      if (declarationIndex) {
        if constexpr (std::is_same_v<Declaration, ImportedTypeDeclaration>) {
          if (declarationIndex->typeOrdinal(category, item.span) != i)
            scan.fail("checked type does not match its declaration directory");
        } else {
          auto owner = declarationIndex->constantOwner(i);
          if (declarationIndex->namedConstant(item.name) != i || !owner ||
              owner->first >= declarationIndex->typeCount(3) ||
              owner->second >= declarationIndex->associatedCount(owner->first))
            scan.fail(
                "checked constant does not match its declaration directory");
        }
      }
    }
    scan.finish();
    if (!scan.good()) {
      fail(std::move(scan.error));
      return;
    }
    if (read) {
      auto loader = std::make_shared<const typename Table::Loader>(
          [records, recordOffset, revisions, read,
           count = static_cast<std::size_t>(count)](std::size_t index) {
            auto begin = recordOffset(index);
            auto end =
                index + 1 == count ? records.size() : recordOffset(index + 1);
            return read(records.subspan(begin, end - begin), revisions);
          });
      items.deferPrefix(static_cast<std::size_t>(count), std::move(loader));
    } else
      fail("checked type declarations have no retained reader");
  }
  void value(ImportedDeclarations::TypeTable &items) {
    indexedDeclarations<ImportedTypeDeclaration>(items, readTypeDeclaration);
  }
  void value(ImportedDeclarations::ConstantTable &items) {
    indexedDeclarations<ImportedInherentConstant>(items,
                                                  readConstantDeclaration);
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
    if (!revisions)
      sourceRevisions();
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
  std::function<std::shared_ptr<const ImportedTypeDeclaration>(
      std::span<const std::uint8_t>,
      std::shared_ptr<const std::vector<std::string>>)>
      readTypeDeclaration;
  std::function<ImportedInherentConstant(
      std::span<const std::uint8_t>,
      std::shared_ptr<const std::vector<std::string>>)>
      readConstantDeclaration;
  std::function<void(Archive &, std::span<const std::uint8_t>)>
      prepareIndexedReader;
  std::shared_ptr<const LibraryDeclarationIndex> declarationIndex;
  std::size_t nextTypeTable = 0;
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
  bool scanningProjection = false;
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
  static unsigned maximum(DeclarationNamespace *) {
    return unsigned(DeclarationNamespace::Macro);
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
WIRE(NativeBinding, v.space, v.module, v.name, v.canonical, v.boundary, v.span,
     v.target, v.publicBoundary, v.explicitBinding)
WIRE(NativeItem, v.span, v.module, v.canonical, v.boundary, v.publicBoundary)
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
                    std::is_same_v<T, SyntaxContextPtr>) {
        if (archive.scanningProjection)
          archive.discard(item);
        else
          archive.keep(item);
      }
    }
    void value(std::shared_ptr<const TypeSyntax> &item) {
      bool present = bool(item);
      archive(present);
      if (present && archive.good()) {
        if (archive.scanningProjection) {
          TypeSyntax discarded;
          archive.scanTypeName(discarded);
          return;
        }
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
  void value(ItemSyntax &item) {
    if (archive.scanningProjection)
      archive.discard(item);
    else
      archive.keep(item);
  }
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
    } else if (archive.scanningProjection)
      archive.discard(item);
    else
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
        if (archive.scanningProjection) {
          for (std::size_t i = 0; i < count && archive.good(); ++i) {
            T item{};
            value(item);
          }
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
std::string validateNativeOverrides(const Module &module) {
  metadata::EncodeReferences references;
  Archive archive(references);
  bool valid = true;
  auto validate = [&](const auto &declarations) {
    declarations.nativeOverrides(
        [&](std::size_t, const auto &actual, const auto &expected) {
          valid &= archive.sameHeader(actual, expected);
        });
  };
  validate(module.functions);
  validate(module.statics);
  validate(module.products);
  validate(module.aliases);
  validate(module.interfaces);
  validate(module.implementations);
  return valid ? std::string{}
               : "checked declarations do not match their archive headers";
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
  bool retain = true;
  const LibraryDeclarationIndex *catalog = nullptr;
  std::uint32_t function = 0;
  std::size_t *indexedDefaults = nullptr;
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
      if (retain)
        records.parameters.push_back(type);
    }
  }
  void value(std::vector<std::optional<Span>> &) {
    defaults = archive.collectionSize();
    for (std::size_t i = 0; i < defaults && archive.good(); ++i) {
      std::optional<Span> span;
      archive(span);
      if (span && catalog) {
        auto ordinal = catalog->defaultOrdinal(function, i);
        if (!ordinal || *ordinal >= catalog->defaultCount() ||
            catalog->defaultAt(*ordinal) !=
                std::pair{function, std::uint32_t(i)})
          archive.fail(
              "default helper does not match its declaration directory");
        ++*indexedDefaults;
      }
      if (retain)
        records.defaults.push_back(span.has_value());
    }
  }
};
void wire(Archive &archive, StaticFacts &value) {
  archive(value.name, value.externalName, value.library, value.type,
          value.initializer);
  auto identity = static_cast<std::uint32_t>(value.identity);
  archive.symbol(metadata::SymbolKind::Static, identity);
  value.identity = identity;
}
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
    if (a.declarationIndex) {
      auto declaration = a.declarationIndex->typeOrdinal(3, v.span);
      if (!declaration)
        a.fail("checked implementation is absent from its header");
      else
        v.declaration = *declaration;
    } else if (a.implementationIndices) {
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
      const ImportedFunctionTable &functions)
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
  const ImportedFunctionTable &functions;
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
           catalog = archive.declarationIndex,
           revisions = archive.sourceRevisions(),
           blocks = records.blocks](std::size_t index) {
            const auto &block = blocks->at(index);
            Archive reader(bytes.subspan(block.offset, block.size), *references,
                           types.get(), revisions);
            reader.implementationIndices = indices.get();
            reader.declarationIndex = catalog;
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
    if (archive.declarationIndex) {
      auto declaration = archive.declarationIndex->typeOrdinal(3, header.span);
      if (!declaration)
        archive.fail("checked implementation is absent from its header");
      else
        header.declaration = *declaration;
    } else if (implementationIndices) {
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
std::string ordinalKey(std::uint64_t value) {
  std::string result(sizeof(value), '\0');
  for (std::size_t i = 0; i < result.size(); ++i)
    result[i] = static_cast<char>(value >> ((result.size() - i - 1) * 8));
  return result;
}
std::string bindingKey(std::string_view module, std::string_view name,
                       DeclarationNamespace space) {
  return "b:" + std::string(module) + '\0' + static_cast<char>(space) + '\0' +
         std::string(name);
}
std::string symbolKey(char prefix, metadata::SymbolKind kind) {
  return std::string{prefix, ':'} + static_cast<char>(kind);
}
class DeclarationDirectoryBuilder {
public:
  explicit DeclarationDirectoryBuilder(Archive &archive) : archive(archive) {}
  template <class T> void add(std::string key, const T &value) {
    Archive record(archive.encoding(), *archive.types, archive.hygieneState());
    record.headerSources = archive.headerSources;
    record(value);
    if (!record.good())
      archive.fail(std::move(record.error));
    entries.emplace_back(std::move(key), std::move(record.output));
  }
  void write() {
    std::stable_sort(entries.begin(), entries.end(),
                     [](const auto &left, const auto &right) {
                       return left.first < right.first;
                     });
    std::vector<std::uint8_t> offsets;
    Archive records(archive.encoding(), *archive.types, archive.hygieneState());
    for (const auto &[key, payload] : entries) {
      auto offset = std::uint64_t(records.output.size());
      for (unsigned byte = 0; byte < sizeof(offset); ++byte)
        offsets.push_back(static_cast<std::uint8_t>(offset >> (byte * 8)));
      records(key);
      records.writeBlock(payload);
    }
    archive.writeBlock(offsets);
    archive.writeBlock(records.output);
  }

private:
  Archive &archive;
  std::vector<std::pair<std::string, std::vector<std::uint8_t>>> entries;
};
class ArchiveDeclarationIndex final : public LibraryDeclarationIndex {
public:
  ArchiveDeclarationIndex(std::shared_ptr<const void> owner,
                          std::shared_ptr<HeaderSources> sources)
      : owner(std::move(owner)), sources(std::move(sources)) {}
  void read(Archive &archive, const Module &module) {
    offsets = archive.readBlock();
    records = archive.readBlock();
    if (offsets.size() % sizeof(std::uint64_t)) {
      archive.fail("invalid declaration lookup directory");
      return;
    }
    Archive scan(records, references, nullptr);
    std::string_view previous;
    for (std::size_t i = 0; i < size() && scan.good(); ++i) {
      if (offset(i) != scan.position()) {
        scan.fail("invalid declaration lookup offset");
        break;
      }
      auto key = scan.textView();
      auto payload = scan.readBlock();
      if (i && key < previous)
        scan.fail("unordered declaration lookup directory");
      if (i && key == previous && !key.starts_with("b:") &&
          !key.starts_with("i:") && !key.starts_with("m:") &&
          !key.starts_with("x:") && !key.starts_with("X:") &&
          !key.starts_with("B:") && !key.starts_with("J:") &&
          !key.starts_with("r:"))
        scan.fail("duplicate declaration lookup key");
      Archive record(payload, references, nullptr);
      record.headerSources = sources;
      if (key.starts_with("b:")) {
        NativeBinding binding;
        record.discard(binding);
      } else if (key.starts_with("i:")) {
        NativeItem item;
        record.discard(item);
      } else if (key.starts_with("S:")) {
        DeclarationSymbolIdentity identity;
        record.discard(identity);
      } else if (key.starts_with("s:") || key.starts_with("f:") ||
                 key.starts_with("m:") || key.starts_with("v:") ||
                 key.starts_with("x:") || key.starts_with("z:") ||
                 key.starts_with("q:") || key.starts_with("X:")) {
        std::uint32_t ordinal = 0;
        record(ordinal);
      } else if (key.starts_with("a:") || key.starts_with("B:")) {
        std::string alias;
        record.discard(alias);
      } else if (key.starts_with("F:")) {
        std::string name;
        record.discard(name);
      } else if (key.starts_with("n:")) {
        std::pair<std::size_t, std::size_t> type;
        record(type);
      } else if (key.starts_with("D:") || key.starts_with("Q:")) {
        std::pair<std::uint32_t, std::uint32_t> parameter;
        record(parameter);
      } else if (key.starts_with("k:") || key.starts_with("J:") ||
                 key.starts_with("r:") || key.starts_with("o:") ||
                 key == "links") {
        bool constructor = false;
        record(constructor);
      } else if (key.starts_with("C:") || key.starts_with("d:") ||
                 key.starts_with("t:") || key.starts_with("T:") ||
                 key.starts_with("A:") || key == "defaults" ||
                 key == "constructors" || key == "constants") {
        std::uint64_t ordinal = 0;
        record(ordinal);
      } else
        record.fail("invalid declaration lookup key");
      record.finish();
      if (!record.good())
        scan.fail(std::move(record.error));
      previous = key;
    }
    scan.finish();
    if (!scan.good()) {
      archive.fail(std::move(scan.error));
      return;
    }
    if (symbolCount(metadata::SymbolKind::Function) !=
            module.functions.size() ||
        symbolCount(metadata::SymbolKind::Static) != module.statics.size()) {
      archive.fail("declaration symbol counts do not match their headers");
      return;
    }
    auto ordinal = [](std::string_view key, std::size_t prefix) {
      std::uint64_t result = 0;
      if (key.size() != prefix + sizeof(result))
        return std::optional<std::uint64_t>{};
      for (auto byte : key.substr(prefix))
        result = (result << 8) | static_cast<unsigned char>(byte);
      return std::optional{result};
    };
    std::map<metadata::SymbolKind, std::size_t> symbolRows;
    std::size_t names = 0, defaults = 0, inverseDefaults = 0, constructors = 0,
                typeCounts = 0;
    const std::array declarationCounts{module.products.size(),
                                       module.aliases.size(),
                                       module.interfaces.size()};
    for (std::size_t i = 0; i < size() && archive.good(); ++i) {
      auto key = keyAt(i);
      bool valid = true;
      if (key.starts_with("S:")) {
        auto identity = value<DeclarationSymbolIdentity>(i);
        valid =
            key == symbolKey('S', identity.kind) + ordinalKey(identity.index) &&
            identity.index < symbolCount(identity.kind);
        ++symbolRows[identity.kind];
      } else if (key.starts_with("s:")) {
        valid = key.size() >= 3;
        if (valid) {
          auto kind = static_cast<metadata::SymbolKind>(key[2]);
          auto id = value<std::uint32_t>(i);
          auto identity = symbol(kind, id);
          valid = identity && identity->definition == key.substr(3);
        }
      } else if (key.starts_with("F:")) {
        auto id = ordinal(key, 2);
        auto name = value<std::string>(i);
        valid = id && *id < module.functions.size() && function(name) == *id;
        ++names;
      } else if (key.starts_with("f:") || key.starts_with("m:") ||
                 key.starts_with("X:") || key.starts_with("z:")) {
        auto id = value<std::uint32_t>(i);
        valid = id < module.functions.size();
        if (valid && key.starts_with("f:"))
          valid = functionName(id) == key.substr(2);
      } else if (key.starts_with("v:") || key.starts_with("x:"))
        valid = value<std::uint32_t>(i) < module.statics.size();
      else if (key.starts_with("n:")) {
        auto [kind, id] = value<std::pair<std::size_t, std::size_t>>(i);
        valid = kind < declarationCounts.size() && id < declarationCounts[kind];
      } else if (key.starts_with("D:")) {
        auto id = ordinal(key, 2);
        auto pair = value<std::pair<std::uint32_t, std::uint32_t>>(i);
        valid = id && *id < defaultCount() &&
                pair.first < module.functions.size() &&
                defaultOrdinal(pair.first, pair.second) == *id;
        ++defaults;
      } else if (key.starts_with("d:")) {
        auto id = value<std::uint64_t>(i);
        valid = id < defaultCount() && key.size() == 18;
        if (valid) {
          auto pair = defaultAt(id);
          valid =
              key == "d:" + ordinalKey(pair.first) + ordinalKey(pair.second);
        }
        ++inverseDefaults;
      } else if (key.starts_with("k:")) {
        auto id = ordinal(key, 2);
        valid = id && *id < module.functions.size() && value<bool>(i);
        ++constructors;
      } else if (key.starts_with("T:")) {
        auto kind = ordinal(key, 2);
        valid = kind && *kind < 5;
        ++typeCounts;
      } else if (key.starts_with("t:")) {
        auto kind = ordinal(key.substr(0, 10), 2);
        valid = key.size() >= 27 && kind && *kind < 5 &&
                value<std::uint64_t>(i) < typeCount(*kind);
      } else if (key.starts_with("A:")) {
        auto id = ordinal(key, 2);
        valid = id && *id < module.implementations.size();
      } else if (key.starts_with("q:"))
        valid = value<std::uint32_t>(i) < constantCount();
      else if (key.starts_with("Q:")) {
        auto id = ordinal(key, 2);
        auto owner = value<std::pair<std::uint32_t, std::uint32_t>>(i);
        valid = id && *id < constantCount() &&
                owner.first < module.implementations.size() &&
                owner.second < associatedCount(owner.first);
      } else if (key.starts_with("J:") || key.starts_with("r:") ||
                 key.starts_with("o:"))
        valid = value<bool>(i);
      else if (key.starts_with("b:")) {
        auto binding = value<NativeBinding>(i);
        auto end = key.find('\0', 2);
        valid = end != std::string_view::npos &&
                key == bindingKey(key.substr(2, end - 2), binding.name,
                                  binding.space);
      } else if (key.starts_with("i:")) {
        auto item = value<NativeItem>(i);
        auto revision = sources->mountedRevisions.find(item.span.source);
        auto coordinates = sources->coordinates(item.span);
        valid = revision != sources->mountedRevisions.end() && coordinates &&
                key == "i:" + revision->second + '\0' +
                           ordinalKey(coordinates->first) +
                           ordinalKey(UINT64_MAX - coordinates->second);
      }
      if (!valid)
        archive.fail("invalid declaration lookup reference");
    }
    if (names != module.functions.size() ||
        symbolRows[metadata::SymbolKind::Function] != module.functions.size() ||
        symbolRows[metadata::SymbolKind::Static] != module.statics.size() ||
        defaults != defaultCount() || inverseDefaults != defaultCount() ||
        constructors != constructorCount() || typeCounts != 5 ||
        !one<bool>("links"))
      archive.fail("incomplete declaration lookup directory");
  }
  std::vector<NativeBinding> lookup(std::string_view module,
                                    std::string_view name,
                                    DeclarationNamespace space) const override {
    return equal<NativeBinding>(bindingKey(module, name, space));
  }
  std::vector<NativeBinding> glob(std::string_view module) const override {
    return prefix<NativeBinding>("b:" + std::string(module) + '\0');
  }
  std::vector<NativeBinding> associated(std::string_view type,
                                        std::string_view name) const override {
    return lookup("@" + std::string(type), name, DeclarationNamespace::Value);
  }
  std::optional<NativeItem> item(Span span) const override {
    auto revision = sources->mountedRevisions.find(span.source);
    if (revision == sources->mountedRevisions.end())
      return std::nullopt;
    auto prefix = "i:" + revision->second + '\0';
    auto coordinates = sources->coordinates(span);
    if (!coordinates) {
      std::optional<NativeItem> result;
      for (auto i = lowerBound(prefix); i < size(); ++i) {
        if (!keyAt(i).starts_with(prefix))
          break;
        auto candidate = value<NativeItem>(i);
        if (candidate.span.begin <= span.begin &&
            candidate.span.end >= span.end &&
            (!result || candidate.span.end - candidate.span.begin <
                            result->span.end - result->span.begin))
          result = std::move(candidate);
      }
      return result;
    }
    auto key = prefix + ordinalKey(coordinates->first) + ordinalKey(UINT64_MAX);
    auto position = lowerBound(key);
    while (position) {
      --position;
      auto current = keyAt(position);
      if (!current.starts_with(prefix))
        break;
      auto candidate = value<NativeItem>(position);
      if (candidate.span.begin <= span.begin && candidate.span.end >= span.end)
        return candidate;
    }
    return std::nullopt;
  }
  std::optional<std::string> alias(std::string_view canonical) const override {
    return one<std::string>("a:" + std::string(canonical));
  }
  bool source(SourceId source) const override {
    return sources->mountedRevisions.contains(source);
  }
  std::optional<std::string>
  builtinMethod(std::string_view name) const override {
    return one<std::string>("B:" + std::string(name));
  }
  bool iteratorMethod(std::string_view name) const override {
    return one<bool>("J:" + std::string(name)).value_or(false);
  }
  bool associatedOwner(std::string_view canonical) const override {
    return one<bool>("o:" + std::string(canonical)).value_or(false);
  }
  std::vector<std::string> exportAssociatedOwners() const override {
    std::vector<std::string> result;
    for (auto i = lowerBound("o:"); i < size(); ++i) {
      auto key = keyAt(i);
      if (!key.starts_with("o:"))
        break;
      result.emplace_back(key.substr(2));
    }
    return result;
  }
  std::vector<std::pair<std::string, NativeBinding>>
  exportBindings() const override {
    std::vector<std::pair<std::string, NativeBinding>> result;
    for (auto i = lowerBound("b:"); i < size(); ++i) {
      auto key = keyAt(i);
      if (!key.starts_with("b:"))
        break;
      auto end = key.find('\0', 2);
      result.emplace_back(key.substr(2, end - 2), value<NativeBinding>(i));
    }
    return result;
  }
  std::vector<NativeItem> exportItems() const override {
    return prefix<NativeItem>("i:");
  }
  std::vector<std::pair<std::string, std::string>>
  exportAliases() const override {
    std::vector<std::pair<std::string, std::string>> result;
    for (auto i = lowerBound("a:"); i < size(); ++i) {
      auto key = keyAt(i);
      if (!key.starts_with("a:"))
        break;
      result.emplace_back(key.substr(2), value<std::string>(i));
    }
    return result;
  }
  std::optional<DeclarationSymbolIdentity>
  symbol(metadata::SymbolKind kind, std::uint32_t index) const override {
    return one<DeclarationSymbolIdentity>(symbolKey('S', kind) +
                                          ordinalKey(index));
  }
  std::optional<std::uint32_t>
  symbol(metadata::SymbolKind kind, std::string_view identity) const override {
    return one<std::uint32_t>(symbolKey('s', kind) + std::string(identity));
  }
  std::size_t symbolCount(metadata::SymbolKind kind) const override {
    return one<std::uint64_t>(symbolKey('C', kind)).value_or(0);
  }
  std::size_t defaultCount() const override {
    return one<std::uint64_t>("defaults").value_or(0);
  }
  bool hasExternalLibraries() const override {
    return one<bool>("links").value();
  }
  std::pair<std::uint32_t, std::uint32_t>
  defaultAt(std::size_t ordinal) const override {
    auto result = one<std::pair<std::uint32_t, std::uint32_t>>(
        "D:" + ordinalKey(ordinal));
    if (!result)
      throw metadata::InvalidMetadata("invalid native default-helper ordinal");
    return *result;
  }
  std::optional<std::size_t>
  defaultOrdinal(std::uint32_t function,
                 std::uint32_t parameter) const override {
    return one<std::uint64_t>("d:" + ordinalKey(function) +
                              ordinalKey(parameter));
  }
  std::optional<std::size_t> typeOrdinal(std::size_t kind,
                                         Span span) const override {
    auto revision = sources->mountedRevisions.find(span.source);
    if (revision == sources->mountedRevisions.end())
      return std::nullopt;
    auto coordinates = sources->coordinates(span);
    if (!coordinates)
      return std::nullopt;
    return one<std::uint64_t>("t:" + ordinalKey(kind) + revision->second +
                              '\0' + ordinalKey(coordinates->first) +
                              ordinalKey(coordinates->second));
  }
  std::optional<std::uint32_t>
  function(std::string_view canonical) const override {
    return one<std::uint32_t>("f:" + std::string(canonical));
  }
  std::optional<std::string> functionName(std::uint32_t index) const override {
    return one<std::string>("F:" + ordinalKey(index));
  }
  std::optional<std::pair<std::size_t, std::size_t>>
  namedType(std::string_view canonical) const override {
    return one<std::pair<std::size_t, std::size_t>>("n:" +
                                                    std::string(canonical));
  }
  std::vector<std::uint32_t> methods(std::string_view name) const override {
    return equal<std::uint32_t>("m:" + std::string(name));
  }
  std::size_t constructorCount() const override {
    return one<std::uint64_t>("constructors").value_or(0);
  }
  bool constructor(std::uint32_t function) const override {
    return one<bool>("k:" + ordinalKey(function)).value_or(false);
  }
  std::optional<std::uint32_t>
  namedStatic(std::string_view canonical) const override {
    return one<std::uint32_t>("v:" + std::string(canonical));
  }
  std::vector<std::uint32_t>
  externalStatics(std::string_view symbol) const override {
    return equal<std::uint32_t>("x:" + std::string(symbol));
  }
  std::vector<std::uint32_t>
  externalFunctions(std::string_view symbol) const override {
    return equal<std::uint32_t>("X:" + std::string(symbol));
  }
  std::optional<std::uint32_t>
  destructor(std::string_view owner) const override {
    return one<std::uint32_t>("z:" + std::string(owner));
  }
  std::optional<std::uint32_t>
  namedConstant(std::string_view canonical) const override {
    return one<std::uint32_t>("q:" + std::string(canonical));
  }
  std::optional<std::pair<std::size_t, std::size_t>>
  constantOwner(std::uint32_t ordinal) const override {
    return one<std::pair<std::size_t, std::size_t>>("Q:" + ordinalKey(ordinal));
  }
  bool constantMember(std::string_view name) const override {
    return one<bool>("r:" + std::string(name)).value_or(false);
  }
  std::size_t typeCount(std::size_t category) const override {
    return one<std::uint64_t>("T:" + ordinalKey(category)).value_or(0);
  }
  std::size_t constantCount() const override {
    return one<std::uint64_t>("constants").value_or(0);
  }
  std::size_t associatedCount(std::size_t implementation) const override {
    return one<std::uint64_t>("A:" + ordinalKey(implementation)).value_or(0);
  }

private:
  std::shared_ptr<const void> owner;
  std::shared_ptr<HeaderSources> sources;
  metadata::DecodeReferences references;
  std::span<const std::uint8_t> offsets, records;
  std::size_t size() const { return offsets.size() / sizeof(std::uint64_t); }
  std::size_t offset(std::size_t index) const {
    std::uint64_t result = 0;
    for (unsigned byte = 0; byte < sizeof(result); ++byte)
      result |= std::uint64_t(offsets[index * sizeof(result) + byte])
                << (byte * 8);
    return static_cast<std::size_t>(result);
  }
  std::string_view keyAt(std::size_t index) const {
    Archive reader(records.subspan(offset(index)), references, nullptr);
    return reader.textView();
  }
  std::size_t lowerBound(std::string_view key) const {
    std::size_t begin = 0, end = size();
    while (begin != end) {
      auto middle = begin + (end - begin) / 2;
      if (keyAt(middle) < key)
        begin = middle + 1;
      else
        end = middle;
    }
    return begin;
  }
  template <class T> T value(std::size_t index) const {
    Archive frame(records.subspan(offset(index)), references, nullptr);
    frame.textView();
    auto payload = frame.readBlock();
    Archive reader(payload, references, nullptr);
    reader.headerSources = sources;
    T result{};
    reader(result);
    reader.finish();
    if (!reader.good())
      throw metadata::InvalidMetadata("invalid declaration lookup: " +
                                      reader.error);
    return result;
  }
  template <class T> std::optional<T> one(std::string_view key) const {
    auto position = lowerBound(key);
    return position < size() && keyAt(position) == key
               ? std::optional(value<T>(position))
               : std::nullopt;
  }
  template <class T> std::vector<T> equal(std::string_view key) const {
    std::vector<T> result;
    for (auto i = lowerBound(key); i < size() && keyAt(i) == key; ++i)
      result.push_back(value<T>(i));
    return result;
  }
  template <class T> std::vector<T> prefix(std::string_view key) const {
    std::vector<T> result;
    for (auto i = lowerBound(key); i < size() && keyAt(i).starts_with(key); ++i)
      result.push_back(value<T>(i));
    return result;
  }
};
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
  const auto &retainedContracts = *module.declarationContracts;
  DeclarationDirectoryBuilder directory(header);
  directory.add("constants",
                std::uint64_t(retainedContracts.inherentConstants.size()));
  for (const auto &owner : module.namespaces().archiveAssociatedOwners())
    directory.add("o:" + owner, true);
  for (auto &symbol : inventory.symbols) {
    if (symbol.kind == metadata::SymbolKind::Function) {
      directory.add("f:" + symbol.definition, symbol.index);
      directory.add("F:" + ordinalKey(symbol.index), symbol.definition);
    }
    auto logical = references.symbol
                       ? references.symbol(symbol.kind, symbol.index)
                       : std::nullopt;
    if (!logical || logical->empty()) {
      header.fail("unresolved header symbol identity");
      break;
    }
    symbol.definition = std::move(*logical);
  }
  std::map<metadata::SymbolKind, std::uint64_t> symbolCounts;
  for (const auto &symbol : inventory.symbols) {
    directory.add(symbolKey('S', symbol.kind) + ordinalKey(symbol.index),
                  symbol);
    directory.add(symbolKey('s', symbol.kind) + symbol.definition,
                  symbol.index);
    symbolCounts[symbol.kind] =
        std::max(symbolCounts[symbol.kind], std::uint64_t(symbol.index) + 1);
  }
  for (const auto &[kind, count] : symbolCounts)
    directory.add(symbolKey('C', kind), count);
  for (const auto &[scope, binding] :
       module.namespaces().archiveBindings(omitImportSources))
    directory.add(bindingKey(scope, binding.name, binding.space), binding);
  for (const auto &item : module.namespaces().archiveItems()) {
    auto source =
        references.source ? references.source(item.span) : std::nullopt;
    if (!source) {
      header.fail("unresolved declaration lookup source");
      break;
    }
    directory.add("i:" + source->revision + '\0' + ordinalKey(item.span.begin) +
                      ordinalKey(UINT64_MAX - item.span.end),
                  item);
  }
  for (const auto &[name, target] : module.namespaces().archiveAliases())
    directory.add("a:" + name, target);
  std::size_t typeKind = 0;
  for (const auto *table :
       {&retainedContracts.products, &retainedContracts.aliases,
        &retainedContracts.interfaces, &retainedContracts.implementations,
        &retainedContracts.associated}) {
    directory.add("T:" + ordinalKey(typeKind), std::uint64_t(table->size()));
    for (std::size_t i = 0; i < table->size(); ++i) {
      const auto &item = *(*table)[i];
      auto source =
          references.source ? references.source(item.span) : std::nullopt;
      if (!source) {
        header.fail("unresolved declaration contract lookup source");
        break;
      }
      directory.add("t:" + ordinalKey(typeKind) + source->revision + '\0' +
                        ordinalKey(item.span.begin) + ordinalKey(item.span.end),
                    std::uint64_t(i));
    }
    ++typeKind;
  }
  auto namedDeclarations = [&](const auto &items, std::size_t kind) {
    for (std::size_t i = 0; i < items.size(); ++i) {
      const auto &item = items.header(i);
      auto name = module.namespaces().canonical(item.span);
      directory.add("n:" + (name.empty() ? item.name : name),
                    std::pair{kind, i});
    }
  };
  namedDeclarations(tree.products, 0);
  namedDeclarations(tree.aliases, 1);
  namedDeclarations(tree.interfaces, 2);
  auto linked = [](const auto &item) {
    return std::any_of(
        item.item.attributes.begin(), item.item.attributes.end(),
        [](const auto &attribute) { return attribute.name == "link"; });
  };
  directory.add("links", std::any_of(tree.functions.headers().begin(),
                                     tree.functions.headers().end(), linked) ||
                             std::any_of(tree.statics.headers().begin(),
                                         tree.statics.headers().end(), linked));
  std::uint64_t defaultCount = 0;
  for (std::size_t i = 0; i < tree.functions.size(); ++i)
    for (std::size_t p = 0; p < tree.functions.header(i).parameters.size(); ++p)
      if (module.hasDefault(i, p)) {
        auto pair = std::pair{std::uint32_t(i), std::uint32_t(p)};
        directory.add("D:" + ordinalKey(defaultCount), pair);
        directory.add("d:" + ordinalKey(i) + ordinalKey(p), defaultCount++);
      }
  directory.add("defaults", defaultCount);
  std::uint64_t constructors = 0;
  for (const auto &group : retainedContracts.constructorGroups)
    for (const auto &constructor : group->headers) {
      directory.add("k:" + ordinalKey(constructor.function), true);
      ++constructors;
    }
  directory.add("constructors", constructors);
  std::map<std::tuple<SourceId, std::size_t, std::size_t>,
           std::pair<std::size_t, std::size_t>>
      constantOwners;
  for (std::size_t i = 0; i < tree.implementations.size(); ++i) {
    const auto &owner = tree.implementations.header(i);
    directory.add("A:" + ordinalKey(i), std::uint64_t(owner.associated.size()));
    for (std::size_t j = 0; j < owner.associated.size(); ++j) {
      auto span = owner.associated[j].span;
      constantOwners.emplace(std::tuple{span.source, span.begin, span.end},
                             std::pair{i, j});
    }
  }
  for (std::size_t i = 0; i < retainedContracts.inherentConstants.size(); ++i) {
    const auto &constant = retainedContracts.inherentConstants[i];
    auto span = constant.declaration;
    auto owner =
        constantOwners.find(std::tuple{span.source, span.begin, span.end});
    if (owner == constantOwners.end()) {
      header.fail("associated constant has no declaring implementation");
      break;
    }
    directory.add("q:" + constant.name, std::uint32_t(i));
    directory.add("Q:" + ordinalKey(i), owner->second);
    directory.add("r:" + constant.name.substr(constant.name.rfind("::") + 2),
                  true);
  }
  for (std::size_t i = 0; i < module.statics().size(); ++i) {
    const auto &facts = module.statics()[i];
    directory.add("v:" + facts.name, std::uint32_t(i));
    if (!facts.externalName.empty())
      directory.add("x:" + facts.externalName, std::uint32_t(i));
  }
  for (std::size_t i = 0; i < tree.functions.size(); ++i) {
    const auto &function = tree.functions.header(i);
    auto symbol = module.function(i).externalName;
    if (!symbol.empty())
      directory.add("X:" + symbol, std::uint32_t(i));
    if (function.destructor)
      if (auto owner = module.symbols->lookup(
              module.symbols->moduleOf(function.span), function.owner,
              resolution::Namespace::Type, function.span))
        directory.add("z:" + *owner, std::uint32_t(i));
    if (!function.owner.empty()) {
      auto delimiter = function.name.rfind('.');
      auto name = function.name.substr(delimiter + 1);
      directory.add("m:" + name, std::uint32_t(i));
      auto module = function.item.scope.empty() ? std::string{}
                                                : function.item.scope.back();
      if (function.implementation >= 0 && function.interfaceOwner.empty() &&
          (module == "option" || module == "outcome" || module == "slice"))
        directory.add("B:" + name, module);
      else if (function.interfaceOwner == "Iterator")
        directory.add("J:" + name, true);
    }
  }
  directory.write();
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
  framed.tag("mettle.checked-header.5");
  framed(header.headerSources->revisions, header.headerSources->references);
  framed.writeBlock(header.output);
  result.header = std::move(framed.output);
  decltype(header.output){}.swap(header.output);
  header.headerSources.reset();
  Archive contracts(references, *module.types, header.hygieneState());
  contracts.tag("mettle.checked-contracts.19");
  auto &value = *module.declarationContracts;
  std::uint64_t count = value.functions.size() +
                        (module.importedDeclarations
                             ? module.importedDeclarations->functions.size()
                             : 0);
  contracts(count);
  Archive functionRecords(references, *module.types, contracts.hygieneState());
  std::vector<std::uint8_t> functionOffsets;
  auto writeFunction = [&](std::uint32_t index, ImportedFunction item) {
    auto offset = std::uint64_t(functionRecords.output.size());
    for (unsigned byte = 0; byte < sizeof(offset); ++byte)
      functionOffsets.push_back(std::uint8_t(offset >> (byte * 8)));
    auto symbol = index;
    functionRecords.symbol(metadata::SymbolKind::Function, symbol);
    if (item.defaults.size() >
        std::as_const(item).contract().facts.locals.size()) {
      contracts.fail("default contract exceeds the parameter inventory");
      return;
    }
    auto summary = functionHeader(item);
    functionRecords(summary);
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
      functionRecords.writeBlock(record.output);
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
  if (!functionRecords.good())
    contracts.fail(std::move(functionRecords.error));
  contracts.writeBlock(functionOffsets);
  contracts.writeBlock(functionRecords.output);
  count = 0;
  for (const auto &group : value.constructorGroups)
    count += group->headers.size();
  contracts(count);
  for (const auto &group : value.constructorGroups)
    for (std::size_t i = 0; i < group->headers.size(); ++i) {
      auto header = group->headers[i];
      contracts.symbol(metadata::SymbolKind::Function, header.function);
      contracts(header.origin);
      Archive record(references, *module.types, contracts.hygieneState());
      auto applicability = group->applicability[i];
      record(applicability);
      if (!record.good())
        contracts.fail(std::move(record.error));
      else
        contracts.writeBlock(record.output);
    }
  count = module.staticStorage.size();
  contracts(count);
  Archive staticRecords(references, *module.types, contracts.hygieneState());
  std::vector<std::uint8_t> staticOffsets;
  for (std::size_t i = 0; i < count; ++i) {
    auto offset = std::uint64_t(staticRecords.output.size());
    for (unsigned byte = 0; byte < sizeof(offset); ++byte)
      staticOffsets.push_back(std::uint8_t(offset >> (byte * 8)));
    auto symbol = std::uint32_t(i);
    staticRecords.symbol(metadata::SymbolKind::Static, symbol);
    auto item = module.staticStorage[i];
    staticRecords(item);
  }
  if (!staticRecords.good())
    contracts.fail(std::move(staticRecords.error));
  contracts.writeBlock(staticOffsets);
  contracts.writeBlock(staticRecords.output);
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
                    std::shared_ptr<const void> backing,
                    metadata::ValidationMode validation) {
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
  envelope.tag("mettle.checked-header.5");
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
    auto origin =
        sources->mountedOrigins
            .try_emplace(span->source,
                         std::pair{std::size_t(source[1]), span->begin})
            .first;
    if (origin->second &&
        sources->coordinates(*span) !=
            std::pair{std::size_t(source[1]), std::size_t(source[2])})
      origin->second.reset();
    auto [mounted, inserted] = sources->mountedRevisions.try_emplace(
        span->source, sources->revisions[source[0]]);
    if (!inserted && mounted->second != sources->revisions[source[0]])
      envelope.fail("conflicting declaration source revision");
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
  if (std::all_of(sources->mountedOrigins.begin(),
                  sources->mountedOrigins.end(),
                  [](const auto &origin) { return origin.second.has_value(); }))
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
  auto index = std::make_shared<ArchiveDeclarationIndex>(storage, sources);
  index->read(archive, module);
  if (validation == metadata::ValidationMode::Eager)
    archive(result.types);
  else
    archive.discard(result.types);
  archive.finish();
  if (!archive.good())
    result.error = std::move(archive.error);
  else {
    result.index = index;
    module.nativeDeclarations.push_back(index);
    if (validation == metadata::ValidationMode::OnDemand) {
      module.imports.clear();
      module.macros.clear();
      module.modules.clear();
      result.module = std::move(module);
      return result;
    }
    for (auto kind :
         {metadata::SymbolKind::Function, metadata::SymbolKind::Static,
          metadata::SymbolKind::Interface, metadata::SymbolKind::Closure,
          metadata::SymbolKind::Package})
      for (std::uint32_t i = 0; i < index->symbolCount(kind); ++i)
        if (auto symbol = index->symbol(kind, i))
          result.symbols.push_back(std::move(*symbol));
    for (std::size_t i = 0; i < module.functions.size(); ++i) {
      const auto &function = module.functions.header(i);
      if (function.implementation >= 0 &&
          std::size_t(function.implementation) >=
              module.implementations.size()) {
        result.error = "invalid declaration implementation reference";
        return result;
      }
    }
    for (std::size_t i = 0; i < module.implementations.size(); ++i) {
      const auto &declared = module.implementations.header(i).methodFunctions;
      for (auto function : declared)
        if (function >= module.functions.size() ||
            module.functions.header(function).implementation !=
                static_cast<int>(i)) {
          result.error = "invalid declaration method reference";
          return result;
        }
    }
    result.module = std::move(module);
  }
  return result;
}

LibraryHeaderImport copyLibraryHeader(const LibraryHeaderImport &header) {
  LibraryHeaderImport result;
  if (header.module)
    result.module = copyHeader(*header.module);
  if (result.module)
    result.module->nativeDeclarations = header.module->nativeDeclarations;
  result.index = header.index;
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
  if (native && !native->catalog) {
    for (const auto &[index, function] : native->functions) {
      (void)index;
      importedSources.insert(function.span().source);
    }
    for (const auto &product : native->products)
      importedSources.insert(product->span.source);
  }
  auto source = [&](Span span) {
    return native && native->catalog ? !native->catalog->source(span.source)
                                     : !importedSources.contains(span.source);
  };
  auto declarations = [&](const auto &items) {
    auto count = items.size();
    context(count);
    auto begin = [&] {
      if constexpr (requires { items.nativeSize(); })
        return items.nativeSize();
      else
        return std::size_t{0};
    }();
    for (std::size_t i = begin; i < items.size(); ++i) {
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
  for (const auto &storage : module.statics.localHeaders())
    if (source(storage.span))
      context(storage.initializer);
  auto associated = [&](const auto &owners) {
    for (const auto &owner : owners)
      if (source(owner.span))
        for (const auto &item : owner.associated)
          context(item.constantValue);
  };
  associated(module.interfaces.localHeaders());
  associated(module.implementations.localHeaders());
  for (const auto &product : module.products.localHeaders())
    if (source(product.span))
      for (const auto &variant : product.variants)
        context(variant.discriminant);
  for (std::size_t i = module.functions.nativeSize();
       i < module.functions.size(); ++i) {
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
                                 const ImportedDeclarations::TypeTable &source,
                                 std::size_t kind) {
    items.resize(native ? native->nativeTypeCounts[kind] : 0);
    for (std::size_t i = local->nativeTypeCounts[kind]; i < source.size();
         ++i) {
      const auto &item = source[i];
      if (reusableType && !reusableType(item->type))
        continue;
      auto projected = std::make_shared<ImportedTypeDeclaration>(*item);
      if (projected->deferred) {
        projected->generics = item->environment();
        projected->deferred.reset();
      }
      projected->type = projection.type(projected->type);
      environment(projected->generics);
      items.push_back(std::move(projected));
    }
  };
  projectDeclarations(result->products, local->products, 0);
  projectDeclarations(result->aliases, local->aliases, 1);
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
  archive.tag("mettle.checked-contracts.19");
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size())
    archive.fail("function inventory exceeds its payload");
  auto offsets = archive.readBlock();
  auto records = archive.readBlock();
  auto base = archive.position() - records.size();
  if (offsets.size() != count * sizeof(std::uint64_t))
    archive.fail("invalid checked function directory");
  Archive rows(records, references, nullptr);
  for (std::uint64_t i = 0; i < count && archive.good() && rows.good(); ++i) {
    std::uint64_t offset = 0;
    for (unsigned byte = 0; byte < sizeof(offset); ++byte)
      offset |= std::uint64_t(offsets[i * sizeof(offset) + byte]) << (byte * 8);
    if (offset != rows.position()) {
      rows.fail("invalid checked function offset");
      break;
    }
    std::uint32_t index = 0;
    rows.symbol(metadata::SymbolKind::Function, index);
    FunctionHeader summary;
    rows.discard(summary);
    auto payload = rows.readBlock();
    if (rows.good())
      result.payloads.push_back(
          {base + rows.position() - payload.size(), payload.size()});
  }
  rows.finish();
  if (!rows.good())
    archive.fail(std::move(rows.error));
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
        verifyPayload,
    std::shared_ptr<const LibraryDeclarationIndex> catalog) {
  LibraryDeclarationImport result;
  if (!types) {
    result.error = "checked declarations require an imported type store";
    return result;
  }
  if (!catalog && module && module->nativeDeclarations.size() == 1)
    catalog = std::dynamic_pointer_cast<const LibraryDeclarationIndex>(
        module->nativeDeclarations.front());
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
  if (module && !catalog)
    for (std::size_t i = 0; i < module->implementations.size(); ++i) {
      auto span = module->implementations.header(i).span;
      implementationIndices.emplace(
          std::tuple{span.source, span.begin, span.end}, i);
    }
  if (module && !catalog)
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
  archive.tag("mettle.checked-contracts.19");
  auto value = std::make_shared<ImportedDeclarations>();
  value->catalog = std::move(catalog);
  archive.declarationIndex = value->catalog;
  auto methods = std::make_shared<InterfaceMethods>();
  auto deferExpressions = [storage, frozen,
                           types](Archive &reader,
                                  std::span<const std::uint8_t> payload) {
    reader.expressionReferences = &reader.decoding();
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
  archive.readTypeDeclaration =
      [storage, frozen, types, environment = archive.deferEnvironment](
          std::span<const std::uint8_t> payload,
          std::shared_ptr<const std::vector<std::string>> revisions) {
        Archive reader(payload, *frozen, types.get(), std::move(revisions));
        reader.deferEnvironment = environment;
        auto item = std::make_shared<ImportedTypeDeclaration>();
        reader(*item);
        reader.finish();
        if (!reader.good())
          throw metadata::InvalidMetadata("invalid checked type declaration: " +
                                          reader.error);
        return std::shared_ptr<const ImportedTypeDeclaration>(std::move(item));
      };
  archive.prepareIndexedReader = deferExpressions;
  archive.readConstantDeclaration =
      [storage, frozen, types, deferExpressions](
          std::span<const std::uint8_t> payload,
          std::shared_ptr<const std::vector<std::string>> revisions) {
        Archive reader(payload, *frozen, types.get(), revisions);
        deferExpressions(reader, payload);
        ImportedInherentConstant result;
        reader(result);
        reader.finish();
        if (!reader.good())
          throw metadata::InvalidMetadata("invalid associated constant: " +
                                          reader.error);
        return result;
      };
  std::uint64_t count = 0;
  archive(count);
  if (count > bytes.size())
    archive.fail("function inventory exceeds its payload");
  if (value->catalog &&
      count != value->catalog->symbolCount(metadata::SymbolKind::Function))
    archive.fail("function inventory does not match its declaration directory");
  auto functionOffsets = archive.readBlock();
  auto functionBytes = archive.readBlock();
  if (functionOffsets.size() != count * sizeof(std::uint64_t))
    archive.fail("invalid checked function directory");
  auto functionOffset = [functionOffsets](std::size_t index) {
    std::uint64_t result = 0;
    for (unsigned byte = 0; byte < sizeof(result); ++byte)
      result |= std::uint64_t(functionOffsets[index * sizeof(result) + byte])
                << (byte * 8);
    return static_cast<std::size_t>(result);
  };
  Archive rows(functionBytes, admission, types.get());
  auto functionRevisions = rows.sourceRevisions();
  ImportedFunctionRecords discarded;
  std::size_t indexedDefaults = 0;
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    if (functionOffset(i) != rows.position()) {
      archive.fail("invalid checked function offset");
      break;
    }
    std::uint32_t index = 0;
    rows.symbol(metadata::SymbolKind::Function, index);
    FunctionHeader summary;
    FunctionIndexScanner scanner{rows, discarded, 0, 0, false};
    scanner.catalog = value->catalog.get();
    scanner.function = index;
    scanner.indexedDefaults = &indexedDefaults;
    functionHeaderFields(scanner, summary);
    auto payload = rows.readBlock();
    if (scanner.defaults != scanner.parameters)
      archive.fail("invalid checked function signature inventory");
    if (value->catalog && index != i)
      archive.fail("native declaration IDs do not match archive ordinals");
    if (value->catalog) {
      auto identity =
          value->catalog->symbol(metadata::SymbolKind::Function, index);
      if (!identity || identity->span != summary.span)
        archive.fail(
            "checked function has inconsistent declaration provenance");
    }
    if (validation == metadata::ValidationMode::Eager && archive.good() &&
        rows.good()) {
      if (verifyPayload && !verifyPayload(i, payload)) {
        archive.fail("checked function payload integrity mismatch");
        break;
      }
      Archive reader(payload, admission, types.get());
      deferExpressions(reader, payload);
      ImportedFunction decoded;
      FunctionScan scanned;
      function(reader, decoded, &scanned);
      for (std::size_t local = 0; local < scanned.staticLocals; ++local) {
        int storage = -1;
        reader.symbol(metadata::SymbolKind::Static, storage);
      }
      reader.finish();
      if (!reader.good())
        archive.fail(std::move(reader.error));
    }
    if (!rows.good())
      archive.fail(std::move(rows.error));
  }
  rows.finish();
  if (value->catalog && indexedDefaults != value->catalog->defaultCount())
    archive.fail("incomplete default-helper declaration directory");
  if (!rows.good())
    archive.fail(std::move(rows.error));
  std::vector<std::string> retainedFunctionNames;
  for (auto name : functionNames)
    retainedFunctionNames.emplace_back(name);
  auto loadFunction =
      [storage, functionBytes, functionOffset, functionRevisions, frozen, types,
       methods, deferExpressions, verifyPayload, catalog = value->catalog,
       names = std::move(retainedFunctionNames)](
          std::uint32_t ordinal) -> ImportedFunctionReference {
    Archive row(functionBytes.subspan(functionOffset(ordinal)), *frozen,
                types.get(), functionRevisions);
    std::uint32_t index = 0;
    row.symbol(metadata::SymbolKind::Function, index);
    auto headerBegin = row.position();
    auto records = std::make_shared<ImportedFunctionRecords>();
    FunctionHeader summary;
    FunctionIndexScanner scanner{row, *records};
    functionHeaderFields(scanner, summary);
    auto header = functionBytes.subspan(functionOffset(ordinal) + headerBegin,
                                        row.position() - headerBegin);
    auto payload = row.readBlock();
    std::string name;
    if (catalog) {
      auto canonical = catalog->functionName(index);
      if (!canonical)
        row.fail("checked function has no indexed canonical name");
      else
        name = std::move(*canonical);
    } else if (!names.empty()) {
      if (index >= names.size() || names[index].empty())
        row.fail("checked function has no admitted canonical name");
      else
        name = names[index];
    }
    if (!row.good())
      throw metadata::InvalidMetadata("invalid checked function index: " +
                                      row.error);
    records->headers.push_back(
        {summary.span, summary.signature.result, summary.signature.error, 0,
         scanner.parameters, summary.hasBody,
         std::move(summary.signature.externalName), std::move(name)});
    auto loader = std::make_shared<
        const TypeRecords<ImportedFunction, true>::Loader>(
        [storage, header, payload, functionRevisions, frozen, types, methods,
         deferExpressions, verifyPayload, ordinal](std::size_t) {
          if (verifyPayload && !verifyPayload(ordinal, payload))
            throw metadata::InvalidMetadata(
                "checked function payload integrity mismatch");
          Archive index(header, *frozen, types.get(), functionRevisions);
          FunctionHeader expected;
          index(expected);
          index.finish();
          Archive reader(payload, *frozen, types.get());
          reader.expressionReferences = frozen.get();
          deferExpressions(reader, payload);
          ImportedFunction decoded;
          function(reader, decoded);
          for (auto &local : decoded.contract().facts.locals)
            if (local.storage == StorageDuration::Static)
              reader.symbol(metadata::SymbolKind::Static, local.staticIndex);
          reader.finish();
          if (!index.good() || !reader.good())
            throw metadata::InvalidMetadata(
                "invalid checked function contract: " +
                (index.good() ? reader.error : index.error));
          if (!matchesHeader(expected, functionHeader(decoded)))
            throw metadata::InvalidMetadata(
                "checked function record does not match its signature index");
          validateDispatches(decoded, *types, *methods);
          return decoded;
        });
    records->functions.deferPrefix(1, std::move(loader));
    return {std::move(records), 0};
  };
  if (value->catalog)
    value->functions.mountIndexed(static_cast<std::size_t>(count),
                                  loadFunction);
  else
    for (std::uint32_t ordinal = 0; ordinal < count && archive.good();
         ++ordinal) {
      Archive row(functionBytes.subspan(functionOffset(ordinal)), admission,
                  types.get(), functionRevisions);
      std::uint32_t index = 0;
      row.symbol(metadata::SymbolKind::Function, index);
      if (!value->functions.emplace(index, loadFunction(ordinal)).second)
        archive.fail("duplicate checked function identity");
    }
  archive(count);
  if (count > value->functions.size())
    archive.fail("constructor inventory exceeds the function inventory");
  if (value->catalog && count != value->catalog->constructorCount())
    archive.fail(
        "constructor inventory does not match its declaration directory");
  auto constructors = std::make_shared<ImportedConstructors>();
  std::set<std::uint32_t> constructorFunctions;
  auto validConstructor = [types](const interfaces::Implementation &item,
                                  const ImportedConstructors::Header &header,
                                  Type result) {
    if (item.target != result || !types->isProduct(item.target))
      return false;
    const auto &product = types->product(item.target);
    auto origin = product.genericOrigin == Type::Unknown
                      ? item.target
                      : product.genericOrigin;
    return product.kind == AggregateKind::Product &&
           !product.layout.unionType && origin == header.origin;
  };
  for (std::uint64_t i = 0; i < count && archive.good(); ++i) {
    ImportedConstructors::Header header;
    archive.symbol(metadata::SymbolKind::Function, header.function);
    archive(header.origin);
    auto payload = archive.readBlock();
    if (!archive.good())
      break;
    if (!value->functions.contains(header.function) ||
        !constructorFunctions.insert(header.function).second ||
        !types->isProduct(header.origin) ||
        (value->catalog && !value->catalog->constructor(header.function)) ||
        (module && !value->catalog &&
         (header.function >= module->functions.size() ||
          !module->functions.header(header.function).constructor))) {
      archive.fail("invalid checked constructor identity");
      break;
    }
    constructors->headers.push_back(header);
    auto constructorFunction = value->catalog
                                   ? ImportedFunctionReference{}
                                   : value->functions.at(header.function);
    if (validation == metadata::ValidationMode::OnDemand) {
      constructors->applicability.push_uninitialized();
      auto loader = std::make_shared<const interfaces::DatabaseRecords<
          interfaces::Implementation>::Loader>([storage, frozen, types, payload,
                                                header, loadFunction,
                                                constructorFunction,
                                                validConstructor](std::size_t) {
        Archive reader(payload, *frozen, types.get());
        interfaces::Implementation item;
        reader(item);
        reader.finish();
        if (!reader.good())
          throw metadata::InvalidMetadata(
              "invalid checked constructor applicability: " + reader.error);
        if (!validConstructor(item, header,
                              constructorFunction
                                  ? constructorFunction.resultType()
                                  : loadFunction(header.function).resultType()))
          throw metadata::InvalidMetadata(
              "constructor applicability does not match its signature index");
        return item;
      });
      constructors->applicability.defer(i, i, std::move(loader));
    } else {
      auto resultType = value->functions.at(header.function).resultType();
      Archive reader(payload, admission, types.get());
      interfaces::Implementation item;
      reader(item);
      reader.finish();
      if (!reader.good())
        archive.fail("invalid checked constructor applicability: " +
                     reader.error);
      else if (!validConstructor(item, header, resultType))
        archive.fail(
            "constructor applicability does not match its signature index");
      else
        constructors->applicability.push_back(std::move(item));
    }
  }
  if (module && !value->catalog)
    for (std::size_t i = 0; i < module->functions.size() && archive.good(); ++i)
      if (module->functions.header(i).constructor &&
          value->functions.contains(static_cast<std::uint32_t>(i)) &&
          !constructorFunctions.contains(static_cast<std::uint32_t>(i)))
        archive.fail("missing checked constructor applicability");
  if (!constructors->headers.empty())
    value->constructorGroups.push_back(std::move(constructors));
  archive(count);
  if (count > bytes.size())
    archive.fail("static inventory exceeds its payload");
  if (value->catalog &&
      count != value->catalog->symbolCount(metadata::SymbolKind::Static))
    archive.fail("static inventory does not match its declaration directory");
  auto staticOffsets = archive.readBlock();
  auto staticRows = archive.readBlock();
  if (count > staticOffsets.size() / sizeof(std::uint64_t) ||
      staticOffsets.size() != count * sizeof(std::uint64_t))
    archive.fail("invalid checked static directory");
  auto staticOffset = [staticOffsets, staticRows, count](std::size_t index) {
    if (index == count)
      return staticRows.size();
    std::uint64_t offset = 0;
    for (unsigned byte = 0; byte < sizeof(offset); ++byte)
      offset |= std::uint64_t(staticOffsets[index * sizeof(offset) + byte])
                << (byte * 8);
    return static_cast<std::size_t>(offset);
  };
  Archive staticScanner(staticRows, admission, types.get());
  deferExpressions(staticScanner, staticRows);
  for (std::size_t i = 0; i < count && archive.good() && staticScanner.good();
       ++i) {
    if (staticOffset(i) != staticScanner.position()) {
      staticScanner.fail("invalid checked static offset");
      break;
    }
    std::uint32_t index = 0;
    StaticFacts item;
    staticScanner.symbol(metadata::SymbolKind::Static, index);
    staticScanner(item);
    if (value->catalog &&
        (index != i || value->catalog->namedStatic(item.name) != i))
      staticScanner.fail("invalid native static declaration identity");
    if (!value->catalog &&
        !value->statics.emplace(index, std::move(item)).second)
      staticScanner.fail("duplicate checked static identity");
  }
  staticScanner.finish();
  if (!staticScanner.good())
    archive.fail(std::move(staticScanner.error));
  if (value->catalog && archive.good()) {
    auto staticRevisions = staticScanner.sourceRevisions();
    value->statics.mountIndexed(count, [storage, staticRows, staticOffset,
                                        staticRevisions, frozen, types,
                                        deferExpressions](std::uint32_t index) {
      auto begin = staticOffset(index), end = staticOffset(index + 1);
      auto payload = staticRows.subspan(begin, end - begin);
      Archive reader(payload, *frozen, types.get(), staticRevisions);
      deferExpressions(reader, payload);
      std::uint32_t identity = 0;
      StaticFacts item;
      reader.symbol(metadata::SymbolKind::Static, identity);
      reader(item);
      reader.finish();
      if (!reader.good() || identity != index)
        throw metadata::InvalidMetadata("invalid static declaration: " +
                                        reader.error);
      return item;
    });
  }
  archive(value->products, value->aliases, value->interfaces,
          value->implementations, value->associated, value->inherentConstants);
  if (value->catalog)
    value->nativeConstantCount = value->inherentConstants.size();
  {
    std::size_t kind = 0;
    for (const auto *table :
         {&value->products, &value->aliases, &value->interfaces,
          &value->implementations, &value->associated})
      value->nativeTypeCounts[kind++] = table->size();
  }
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
  auto indices = module && !value->catalog
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
    if (validation == metadata::ValidationMode::Eager)
      for (std::size_t i = 0; i < value->functions.nativeSize(); ++i)
        value->functions.at(i)->materialize();
    for (const auto &[index, function] : value->functions) {
      (void)index;
      if (validation == metadata::ValidationMode::Eager ||
          function.isMaterialized())
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
