#include "driver/library_archive.h"
#include "ir/codec.h"
#include "packages/sha256.h"
#include "semantics/library.h"
#include "support/limits.h"
#include <algorithm>
#include <limits>
#include <thread>
#include <unordered_set>
#ifdef __linux__
#include <sys/mman.h>
#include <unistd.h>
#endif

namespace mettle::driver {
namespace {
void populate(const void *data, std::size_t size) {
#if defined(__linux__) && defined(MADV_POPULATE_READ)
  const auto page = static_cast<std::uintptr_t>(::sysconf(_SC_PAGESIZE));
  const auto begin = reinterpret_cast<std::uintptr_t>(data) & ~(page - 1);
  const auto end = reinterpret_cast<std::uintptr_t>(data) + size;
  ::madvise(reinterpret_cast<void *>(begin), end - begin, MADV_POPULATE_READ);
#else
  (void)data;
  (void)size;
#endif
}

template <class HashBlock>
std::string blockDigest(std::size_t size, HashBlock hashBlock) {
  constexpr std::size_t block = std::size_t{1} << 20;
  const std::size_t blocks = (size + block - 1) / block;
  std::vector<std::string> parts(blocks);
  const std::size_t workers =
      blocks <= 1
          ? blocks
          : std::min<std::size_t>(
                blocks,
                std::max(1u,
                         std::min(8u, std::thread::hardware_concurrency())));
  auto run = [&](std::size_t first) {
    for (std::size_t i = first; i < blocks; i += workers) {
      packages::Sha256 hash;
      hashBlock(hash, i * block, std::min(block, size - i * block));
      parts[i] = hash.finish();
    }
  };
  std::vector<std::thread> threads;
  for (std::size_t w = 1; w < workers; ++w)
    threads.emplace_back(run, w);
  if (workers)
    run(0);
  for (auto &thread : threads)
    thread.join();
  packages::Sha256 total;
  for (const auto &part : parts)
    total.update(part);
  return total.finish();
}
} // namespace

std::string archiveDigest(std::string_view bytes) {
  return blockDigest(bytes.size(), [&](packages::Sha256 &hash,
                                       std::size_t offset, std::size_t size) {
    hash.update(bytes.substr(offset, size));
  });
}

namespace {
struct PayloadRange {
  std::size_t offset, size;
};

std::string metadataDigest(std::string_view bytes,
                           std::span<const PayloadRange> payloads) {
  if (payloads.empty())
    return archiveDigest(bytes);
  std::vector<std::size_t> prefixes;
  prefixes.reserve(payloads.size() + 2);
  prefixes.push_back(0);
  std::size_t offset = 0;
  for (const auto &payload : payloads) {
    prefixes.push_back(prefixes.back() + (payload.offset - offset));
    offset = payload.offset + payload.size;
  }
  prefixes.push_back(prefixes.back() + (bytes.size() - offset));
  return blockDigest(prefixes.back(), [&](packages::Sha256 &hash,
                                          std::size_t position,
                                          std::size_t size) {
    auto fragment = static_cast<std::size_t>(
        std::upper_bound(prefixes.begin(), prefixes.end(), position) -
        prefixes.begin() - 1);
    const auto end = position + size;
    while (position < end) {
      const auto begin =
          fragment ? payloads[fragment - 1].offset + payloads[fragment - 1].size
                   : 0;
      const auto count = std::min(end, prefixes[fragment + 1]) - position;
      hash.update(bytes.substr(begin + position - prefixes[fragment], count));
      position += count;
      ++fragment;
    }
  });
}

std::string_view textBytes(std::span<const std::uint8_t> bytes) {
  return {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
}

struct PayloadSeals {
  std::shared_ptr<const void> backing;
  std::vector<std::string_view> digests;
};

void excludePayloads(std::vector<PayloadRange> &excluded,
                     std::size_t sectionOffset, const auto &payloads) {
  for (const auto &payload : payloads)
    excluded.push_back({sectionOffset + payload.offset, payload.size});
}

ir::FunctionBodyVerifier
payloadVerifier(std::shared_ptr<const void> backing,
                std::vector<std::string_view> digests) {
  auto integrity = std::make_shared<const PayloadSeals>(
      PayloadSeals{std::move(backing), std::move(digests)});
  return [integrity](std::size_t index, std::span<const std::uint8_t> payload) {
    return integrity->backing && index < integrity->digests.size() &&
           archiveDigest(textBytes(payload)) == integrity->digests[index];
  };
}

class Writer {
public:
  std::string bytes;
  void integer(std::uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8)
      bytes.push_back(static_cast<char>(value >> shift));
  }
  void boolean(bool value) { bytes.push_back(value ? 1 : 0); }
  void text(std::string_view value) {
    integer(static_cast<std::uint32_t>(value.size()));
    bytes.append(value);
  }
  void data(std::span<const std::uint8_t> value) {
    text({reinterpret_cast<const char *>(value.data()), value.size()});
  }
  void patch(std::size_t offset, std::uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8)
      bytes[offset++] = static_cast<char>(value >> shift);
  }
};

class Reader {
public:
  Reader(std::string_view bytes, std::string &error)
      : bytes(bytes), error(error) {}
  bool good() const { return error.empty(); }
  std::size_t position() const { return offset; }
  std::string_view range(std::size_t begin, std::size_t end) const {
    return bytes.substr(begin, end - begin);
  }
  std::size_t remaining() const { return bytes.size() - offset; }
  void fail(std::string_view message) {
    if (good())
      error = "invalid compiled library archive: " + std::string(message);
  }
  std::uint32_t integer() {
    if (!good() || remaining() < 4) {
      fail("truncated integer");
      return 0;
    }
    std::uint32_t value = 0;
    for (unsigned shift = 0; shift < 32; shift += 8)
      value |= static_cast<std::uint32_t>(
                   static_cast<unsigned char>(bytes[offset++]))
               << shift;
    return value;
  }
  bool boolean() {
    if (!good() || !remaining()) {
      fail("truncated boolean");
      return false;
    }
    auto value = static_cast<unsigned char>(bytes[offset++]);
    if (value > 1)
      fail("invalid boolean");
    return value != 0;
  }
  std::size_t count(std::size_t minimumBytes,
                    std::size_t limit = limits::tokens) {
    auto value = integer();
    if (value > limit || value > remaining() / minimumBytes) {
      fail("invalid table size");
      return 0;
    }
    return value;
  }
  std::string_view textView() {
    auto size = integer();
    if (!good() || size > remaining()) {
      fail("truncated string");
      return {};
    }
    auto result = bytes.substr(offset, size);
    offset += size;
    return result;
  }
  std::string text() { return std::string(textView()); }
  std::span<const std::uint8_t> data() {
    auto size = integer();
    if (!good() || size > remaining()) {
      fail("truncated section");
      return {};
    }
    const auto *begin =
        reinterpret_cast<const std::uint8_t *>(bytes.data() + offset);
    offset += size;
    return {begin, size};
  }
  Span span(std::size_t sourceCount) {
    auto source = integer();
    auto begin = integer();
    auto end = integer();
    if (source >= sourceCount || begin > end)
      fail("invalid source reference");
    return {begin, end, source};
  }

private:
  std::string_view bytes;
  std::string &error;
  std::size_t offset = 0;
};

std::string sourcePrefix(std::string_view identity, std::size_t ordinal,
                         std::string_view path, std::size_t size) {
  Writer prefix;
  prefix.text(identity);
  prefix.integer(static_cast<std::uint32_t>(ordinal));
  prefix.text(path);
  prefix.integer(static_cast<std::uint32_t>(size));
  return std::move(prefix.bytes);
}

std::string sourceDigest(std::string_view prefix, std::string_view text) {
  packages::Sha256 hash;
  hash.update(prefix);
  hash.update(text);
  return hash.finish();
}

std::optional<std::size_t>
sourceSpanIndex(Span span, std::span<const Source> sources,
                const std::unordered_map<SourceId, std::size_t> &index) {
  auto found = index.find(span.source);
  if (found == index.end() || span.begin > span.end ||
      span.end > sources[found->second].text.size())
    return std::nullopt;
  return found->second;
}

class ProvenanceValidator {
public:
  ProvenanceValidator(
      std::span<const Source> sources,
      const std::unordered_map<SourceId, std::size_t> &sourceIndex,
      std::string &error)
      : sources(sources), sourceIndex(sourceIndex), error(error),
        seen(sources.size(), std::numeric_limits<std::size_t>::max()) {}
  bool generation(SourceId source, Span origin, std::size_t description,
                  std::size_t mappings) {
    auto found = sourceIndex.find(source);
    if (found == sourceIndex.end() ||
        !parents.emplace(source, std::vector<SourceId>{}).second ||
        description > limits::sourceBytes || mappings > limits::tokens)
      return fail("invalid or duplicate generated source");
    edges = &parents.at(source);
    current = found->second;
    length = sources[found->second].text.size();
    previousEnd = 0;
    return parent(origin) || fail("invalid generation origin");
  }
  bool mapping(const Generation::Mapping &mapping,
               std::string_view description) {
    if (mapping.begin < previousEnd || mapping.begin > mapping.end ||
        mapping.end > length || description.size() > limits::sourceBytes ||
        !parent(mapping.target) ||
        (!description.empty() && !parent(mapping.origin)) ||
        (mapping.exact && mapping.end - mapping.begin >
                              mapping.target.end - mapping.target.begin))
      return fail("invalid generation mapping");
    previousEnd = mapping.end;
    return true;
  }
  bool context(Span definition, std::size_t scope, std::size_t longestPart) {
    return (sourceSpanIndex(definition, sources, sourceIndex) &&
            scope <= limits::tokens && longestPart <= limits::sourceBytes) ||
           fail("invalid syntax context");
  }
  bool finish() {
    std::unordered_map<SourceId, unsigned char> state;
    for (const auto &[source, edges] : parents) {
      if (state[source] == 2)
        continue;
      std::vector<std::pair<SourceId, std::size_t>> stack{{source, 0}};
      state[source] = 1;
      while (!stack.empty()) {
        auto &[current, next] = stack.back();
        auto found = parents.find(current);
        if (found == parents.end() || next == found->second.size()) {
          state[current] = 2;
          stack.pop_back();
          continue;
        }
        auto parent = found->second[next++];
        if (state[parent] == 1)
          return fail("cyclic generation provenance");
        if (state[parent] == 0) {
          state[parent] = 1;
          stack.emplace_back(parent, 0);
        }
      }
    }
    return true;
  }

private:
  bool parent(Span span) {
    const auto index = sourceSpanIndex(span, sources, sourceIndex);
    if (!index)
      return false;
    if (seen[*index] != current) {
      seen[*index] = current;
      edges->push_back(span.source);
    }
    return true;
  }
  bool fail(std::string_view message) {
    if (error.empty())
      error =
          "invalid compiled library source archive: " + std::string(message);
    return false;
  }
  std::span<const Source> sources;
  const std::unordered_map<SourceId, std::size_t> &sourceIndex;
  std::string &error;
  std::unordered_map<SourceId, std::vector<SourceId>> parents;
  std::vector<std::size_t> seen;
  std::vector<SourceId> *edges = nullptr;
  std::size_t current = 0, length = 0, previousEnd = 0;
};

struct ProvenanceScan {
  ProvenanceValidator validator;
  std::vector<std::uint64_t> binders;
  std::unordered_set<std::uint64_t> seenBinders;
};

template <bool Materialize>
Generation readGeneration(Reader &in, std::size_t sourceCount,
                          ProvenanceScan *scan = nullptr) {
  Generation generation;
  generation.source = in.integer();
  generation.origin = in.span(sourceCount);
  auto description = in.textView();
  const auto contextCount = in.count(20);
  std::vector<SyntaxContextPtr> contexts;
  std::unordered_map<std::string_view, SyntaxContextPtr> interned;
  if constexpr (Materialize)
    contexts.reserve(contextCount);
  for (std::size_t j = 0; in.good() && j < contextCount; ++j) {
    const auto contextBegin = in.position();
    const auto binder = in.integer();
    const auto parts = in.count(4);
    const auto scopeBegin = in.position();
    std::size_t longestPart = 0;
    for (std::size_t k = 0; in.good() && k < parts; ++k)
      longestPart = std::max(longestPart, in.textView().size());
    const auto scopeEnd = in.position();
    const auto definition = in.span(sourceCount);
    if constexpr (Materialize) {
      if (in.good()) {
        auto [entry, inserted] =
            interned.try_emplace(in.range(contextBegin, in.position()));
        if (inserted) {
          std::string error;
          Reader scopeReader(in.range(scopeBegin, scopeEnd), error);
          std::vector<std::string> scope;
          scope.reserve(parts);
          for (std::size_t k = 0; k < parts; ++k)
            scope.push_back(scopeReader.text());
          if (!scopeReader.good())
            in.fail("invalid syntax-context scope");
          entry->second = std::make_shared<const SyntaxContext>(
              SyntaxContext{std::move(scope), definition, binder});
        }
        contexts.push_back(entry->second);
      }
    } else if (in.good()) {
      scan->validator.context(definition, parts, longestPart);
      if (binder && scan->seenBinders.insert(binder).second)
        scan->binders.push_back(binder);
    }
  }
  auto mappings = in.count(30);
  if constexpr (Materialize) {
    generation.description = description;
    generation.mappings.reserve(mappings);
  } else if (in.good()) {
    scan->validator.generation(generation.source, generation.origin,
                               description.size(), mappings);
  }
  for (std::size_t j = 0; in.good() && j < mappings; ++j) {
    Generation::Mapping mapping;
    mapping.begin = in.integer();
    mapping.end = in.integer();
    mapping.target = in.span(sourceCount);
    mapping.exact = in.boolean();
    const auto hasOrigin = in.boolean();
    if (hasOrigin)
      mapping.origin = in.span(sourceCount);
    const auto description = in.textView();
    if (hasOrigin != !description.empty())
      in.fail("inconsistent mapping origin");
    if constexpr (!Materialize)
      if (in.good())
        scan->validator.mapping(mapping, description);
    const auto context = in.integer();
    if (context >= 2 && context - 2 >= contextCount)
      in.fail("invalid syntax-context reference");
    if constexpr (Materialize) {
      if (context == 1)
        mapping.syntaxContext = SyntaxContextPtr{};
      else if (context >= 2 && in.good())
        mapping.syntaxContext = contexts[context - 2];
      mapping.description = description;
      generation.mappings.push_back(std::move(mapping));
    }
  }
  return generation;
}
} // namespace

LibrarySources::LibrarySources(std::string identity) {
  data->identity = std::move(identity);
}

void LibrarySources::edit() {
  if (!data.unique())
    data = std::make_shared<Data>(*data);
  if (!mounts.unique() || mounts->current)
    mounts = std::make_shared<MountCache>();
  validated = false;
}

std::optional<std::string> LibrarySources::record(const Source &source,
                                                  std::string &error) {
  if (auto found = data->sourceIndex.find(source.id);
      found != data->sourceIndex.end()) {
    const auto &previous = data->sources[found->second];
    if (previous.path != source.path || previous.text != source.text) {
      error = "compiled library source ID names conflicting revisions";
      return std::nullopt;
    }
    return data->revisions[found->second];
  }
  if (data->identity.empty() || data->identity.size() > limits::sourceBytes ||
      source.path.size() > limits::sourceBytes ||
      source.text.size() > limits::sourceBytes ||
      data->sources.size() >= limits::tokens || invalidUtf8(source.text)) {
    error = "invalid compiled library source identity, size or encoding";
    return std::nullopt;
  }
  auto name = sourceDigest(sourcePrefix(data->identity, data->sources.size(),
                                        source.path, source.text.size()),
                           source.text);
  edit();
  data->sourceIndex.emplace(source.id, data->sources.size());
  data->revisionIndex.emplace(name, data->sources.size());
  data->revisions.emplace_back(name);
  data->sources.push_back(source);
  return name;
}

std::optional<metadata::SourceReference>
LibrarySources::reference(Span span) const {
  const auto index = sourceSpanIndex(span, data->sources, data->sourceIndex);
  if (!index)
    return std::nullopt;
  return metadata::SourceReference{data->revisions[*index],
                                   static_cast<std::uint32_t>(span.begin),
                                   static_cast<std::uint32_t>(span.end)};
}

std::optional<Span>
LibrarySources::resolve(const metadata::SourceReference &reference) const {
  auto found = data->revisionIndex.find(reference.revision);
  if (found == data->revisionIndex.end() || reference.begin > reference.end ||
      reference.end > data->sources[found->second].text.size())
    return std::nullopt;
  return Span{reference.begin, reference.end, data->sources[found->second].id};
}

const Source *LibrarySources::source(std::string_view revision) const {
  auto found = data->revisionIndex.find(std::string(revision));
  return found == data->revisionIndex.end() ? nullptr
                                            : &data->sources[found->second];
}

bool LibrarySources::validate(std::string &error) const {
  if (validated)
    return true;
  auto fail = [&](std::string_view message) {
    error = "invalid compiled library source archive: " + std::string(message);
    return false;
  };
  if (data->identity.empty() || data->sources.size() > limits::tokens ||
      data->generations.size() > data->sources.size())
    return fail("invalid identity or table size");
  ProvenanceValidator validator(data->sources, data->sourceIndex, error);
  for (const auto &record : data->generations) {
    const auto &generation = record.get();
    if (!validator.generation(generation.source, generation.origin,
                              generation.description.size(),
                              generation.mappings.size()))
      return false;
    for (const auto &mapping : generation.mappings) {
      if (!validator.mapping(mapping, mapping.description))
        return false;
      if (mapping.syntaxContext && *mapping.syntaxContext) {
        const auto &context = **mapping.syntaxContext;
        std::size_t longestPart = 0;
        for (const auto &part : context.scope)
          longestPart = std::max(longestPart, part.size());
        if (!validator.context(context.definition, context.scope.size(),
                               longestPart))
          return false;
      }
    }
  }
  return validator.finish();
}

bool LibrarySources::capture(const Diagnostics &diagnostics,
                             std::string &error) {
  auto candidate = *this;
  for (const auto &source : diagnostics.registeredSources())
    if (!candidate.record(source, error))
      return false;
  candidate.edit();
  const auto generations = diagnostics.registeredGenerations();
  candidate.data->generations.assign(generations.begin(), generations.end());
  candidate.data->binders.reset();
  if (!candidate.validate(error))
    return false;
  candidate.validated = true;
  *this = std::move(candidate);
  return true;
}

bool LibrarySources::mount(
    Diagnostics &diagnostics,
    const std::function<std::optional<SourceId>()> &allocate,
    std::string &error) {
  if (!allocate || !validate(error)) {
    if (error.empty())
      error = "compiled library import requires a source allocator";
    return false;
  }
  std::unordered_set<SourceId> occupied;
  for (const auto &source : diagnostics.registeredSources())
    occupied.insert(source.id);
  std::unordered_map<SourceId, SourceId> remap;
  std::vector<SourceId> ids;
  ids.reserve(data->sources.size());
  for (const auto &source : data->sources) {
    auto id = allocate();
    if (!id || *id == 0 || !occupied.insert(*id).second) {
      error = "compiled library source allocation exhausted or collided";
      return false;
    }
    remap.emplace(source.id, *id);
    ids.push_back(*id);
  }
  const auto syntaxBegin = diagnostics.syntaxContextCount();
  std::shared_ptr<const Mounted> cached;
  {
    std::lock_guard lock(mounts->mutex);
    cached = mounts->current;
  }
  auto registerSnapshot = [&] {
    for (const auto &source : data->sources)
      diagnostics.registerSource(std::shared_ptr<const Source>(data, &source));
    for (const auto &generation : data->generations)
      diagnostics.generated(generation);
    validated = true;
    mounted = true;
  };
  if (cached && cached->ids == ids && cached->syntaxBegin == syntaxBegin) {
    data = cached->data;
    diagnostics.reserveSyntaxContexts(cached->syntaxEnd - cached->syntaxBegin);
    registerSnapshot();
    return true;
  }
  if (!data.unique())
    data = std::make_shared<Data>(*data);
  std::unordered_map<SourceId, std::size_t> mountedIndex;
  for (std::size_t i = 0; i < data->sources.size(); ++i)
    mountedIndex.emplace(remap.at(data->sources[i].id), i);
  if (!data->binders) {
    data->binders.emplace();
    std::unordered_set<std::uint64_t> seen;
    for (const auto &record : data->generations)
      for (const auto &mapping : record.get().mappings)
        if (mapping.syntaxContext && *mapping.syntaxContext)
          if (auto id = (**mapping.syntaxContext).identity;
              id && seen.insert(id).second)
            data->binders->push_back(id);
  }
  struct Remapping {
    std::unordered_map<SourceId, SourceId> sources;
    std::unordered_map<std::uint64_t, std::uint64_t> binders;
    Span span(Span value) const {
      value.source = sources.at(value.source);
      return value;
    }
  };
  Remapping values{remap, {}};
  for (auto &binder : *data->binders) {
    const auto identity = syntaxBegin + values.binders.size() + 1;
    values.binders.emplace(binder, identity);
    binder = identity;
  }
  diagnostics.reserveSyntaxContexts(values.binders.size());
  auto mapping = std::make_shared<const Remapping>(std::move(values));
  for (auto &record : data->generations) {
    record = GenerationRecord(remap.at(record.source()), [original = record,
                                                          mapping] {
      auto generation = original.get();
      generation.source = mapping->sources.at(generation.source);
      generation.origin = mapping->span(generation.origin);
      std::unordered_map<SyntaxContextPtr, SyntaxContextPtr> contexts;
      for (auto &entry : generation.mappings) {
        entry.target = mapping->span(entry.target);
        if (!entry.description.empty())
          entry.origin = mapping->span(entry.origin);
        if (!entry.syntaxContext || !*entry.syntaxContext)
          continue;
        auto [found, inserted] = contexts.try_emplace(*entry.syntaxContext);
        if (inserted) {
          const auto &context = **entry.syntaxContext;
          found->second = std::make_shared<const SyntaxContext>(SyntaxContext{
              context.scope, mapping->span(context.definition),
              context.identity ? mapping->binders.at(context.identity) : 0});
        }
        entry.syntaxContext = found->second;
      }
      return generation;
    });
  }
  for (auto &source : data->sources) {
    source.id = remap.at(source.id);
  }
  data->sourceIndex = std::move(mountedIndex);
  registerSnapshot();
  {
    std::lock_guard lock(mounts->mutex);
    mounts->current = std::make_shared<const Mounted>(Mounted{
        data, std::move(ids), syntaxBegin, diagnostics.syntaxContextCount()});
  }
  return true;
}

std::optional<std::string> encodeLibraryArchive(const LibraryArchive &archive,
                                                std::string &error) {
  error.clear();
  const auto &sources = archive.sources;
  const auto &data = *sources.data;
  if (sources.mounted) {
    error = "a mounted compiled library cannot be encoded";
    return std::nullopt;
  }
  if (!sources.validate(error))
    return std::nullopt;
  if (archive.macros.size() > limits::sourceBytes ||
      archive.header.size() > limits::sourceBytes ||
      archive.types.size() > limits::sourceBytes ||
      archive.declarations.size() > limits::sourceBytes ||
      archive.ir.size() > limits::sourceBytes) {
    error = "compiled library section exceeds the compiler data-file limit";
    return std::nullopt;
  }
  if (archive.sourceModules.size() > data.sources.size()) {
    error = "compiled library source-module table exceeds its source table";
    return std::nullopt;
  }
  for (const auto &[revision, path] : archive.sourceModules)
    if (!data.revisionIndex.contains(revision) ||
        path.size() > limits::tokens ||
        std::any_of(path.begin(), path.end(), [](const auto &part) {
          return part.size() > limits::sourceBytes;
        })) {
      error = "invalid compiled library source-module reference";
      return std::nullopt;
    }
  auto irLayout = ir::programLayout(archive.ir);
  if (!irLayout) {
    error = "invalid compiled library IR framing: " + irLayout.error;
    return std::nullopt;
  }
  auto declarationsLayout = archive.declarations.size()
                                ? declarationPayloadLayout(archive.declarations)
                                : DeclarationPayloadLayout{};
  if (!declarationsLayout) {
    error = "invalid compiled library declaration framing: " +
            declarationsLayout.error;
    return std::nullopt;
  }
  Writer out;
  out.text("mettle-checked-library-7");
  out.text(data.identity);
  out.integer(static_cast<std::uint32_t>(data.sources.size()));
  std::vector<PayloadRange> excluded;
  excluded.reserve(data.sources.size() + declarationsLayout.payloads.size() +
                   irLayout.bodies.size());
  for (std::size_t i = 0; i < data.sources.size(); ++i) {
    const auto &source = data.sources[i];
    out.text(source.path);
    excluded.push_back({out.bytes.size() + 4, source.text.size()});
    out.text(source.text);
    out.text(data.revisions[i]);
    out.text(sourceDigest(
        sourcePrefix(data.identity, i, source.path, source.text.size()),
        data.revisions[i]));
  }
  auto span = [&](Span value) {
    out.integer(static_cast<std::uint32_t>(data.sourceIndex.at(value.source)));
    out.integer(static_cast<std::uint32_t>(value.begin));
    out.integer(static_cast<std::uint32_t>(value.end));
  };
  std::unordered_map<std::uint64_t, std::uint32_t> binders;
  out.integer(static_cast<std::uint32_t>(data.generations.size()));
  for (const auto &record : data.generations) {
    const auto &generation = record.get();
    const auto frame = out.bytes.size();
    out.integer(0);
    out.integer(
        static_cast<std::uint32_t>(data.sourceIndex.at(generation.source)));
    span(generation.origin);
    out.text(generation.description);
    std::unordered_map<const SyntaxContext *, std::uint32_t> contextIndices;
    std::vector<const SyntaxContext *> contexts;
    for (const auto &mapping : generation.mappings)
      if (mapping.syntaxContext && *mapping.syntaxContext) {
        const auto *context = mapping.syntaxContext->get();
        if (contextIndices
                .try_emplace(context,
                             static_cast<std::uint32_t>(contexts.size() + 2))
                .second)
          contexts.push_back(context);
      }
    out.integer(static_cast<std::uint32_t>(contexts.size()));
    for (const auto *context : contexts) {
      const auto binder =
          context->identity
              ? binders
                    .try_emplace(context->identity,
                                 static_cast<std::uint32_t>(binders.size() + 1))
                    .first->second
              : 0;
      out.integer(binder);
      out.integer(static_cast<std::uint32_t>(context->scope.size()));
      for (const auto &part : context->scope)
        out.text(part);
      span(context->definition);
    }
    out.integer(static_cast<std::uint32_t>(generation.mappings.size()));
    for (const auto &mapping : generation.mappings) {
      out.integer(static_cast<std::uint32_t>(mapping.begin));
      out.integer(static_cast<std::uint32_t>(mapping.end));
      span(mapping.target);
      out.boolean(mapping.exact);
      out.boolean(!mapping.description.empty());
      if (!mapping.description.empty())
        span(mapping.origin);
      out.text(mapping.description);
      out.integer(!mapping.syntaxContext ? 0
                  : !*mapping.syntaxContext
                      ? 1
                      : contextIndices.at(mapping.syntaxContext->get()));
    }
    out.patch(frame, static_cast<std::uint32_t>(out.bytes.size() - frame - 4));
  }
  out.integer(static_cast<std::uint32_t>(binders.size()));
  out.integer(static_cast<std::uint32_t>(archive.sourceModules.size()));
  for (const auto &[revision, path] : archive.sourceModules) {
    out.text(revision);
    out.integer(static_cast<std::uint32_t>(path.size()));
    for (const auto &part : path)
      out.text(part);
  }
  out.text(archive.macros);
  out.data(archive.header);
  out.data(archive.types);
  const auto declarationsOffset = out.bytes.size() + 4;
  out.data(archive.declarations);
  out.integer(static_cast<std::uint32_t>(declarationsLayout.payloads.size()));
  for (const auto &payload : declarationsLayout.payloads)
    out.text(archiveDigest(textBytes(
        archive.declarations.bytes().subspan(payload.offset, payload.size))));
  out.integer(static_cast<std::uint32_t>(irLayout.bodies.size()));
  for (const auto &body : irLayout.bodies)
    out.text(archiveDigest(
        textBytes(archive.ir.bytes().subspan(body.offset, body.size))));
  const auto irOffset = out.bytes.size() + 4;
  out.data(archive.ir);
  if (out.bytes.size() > limits::sourceBytes - 64) {
    error = "compiled library archive exceeds the compiler data-file limit";
    return std::nullopt;
  }
  excludePayloads(excluded, declarationsOffset, declarationsLayout.payloads);
  excludePayloads(excluded, irOffset, irLayout.bodies);
  out.bytes += metadataDigest(out.bytes, excluded);
  return std::move(out.bytes);
}

std::optional<LibraryArchive>
decodeLibraryArchive(std::string_view bytes, std::string_view identity,
                     std::string &error, std::shared_ptr<const void> backing,
                     bool authenticated) {
  error.clear();
  if (bytes.size() > limits::sourceBytes || bytes.size() < 64) {
    error = "invalid compiled library archive size or checksum";
    return std::nullopt;
  }
  if (!backing) {
    auto snapshot = std::make_shared<const std::string>(bytes);
    bytes = *snapshot;
    backing = std::move(snapshot);
  }
  Reader in(bytes.substr(0, bytes.size() - 64), error);
  if (in.textView() != "mettle-checked-library-7")
    in.fail("unsupported format");
  auto revision = in.text();
  if (revision != identity || revision.empty())
    in.fail("compiler, content or configuration identity mismatch");
  LibraryArchive archive(std::move(revision));
  auto count = in.count(144);
  std::vector<PayloadRange> excluded;
  excluded.reserve(count);
  for (std::size_t i = 0; in.good() && i < count; ++i) {
    auto path = in.text();
    const auto offset = in.position() + 4;
    auto text = in.textView();
    auto revision = in.textView();
    auto binding = in.textView();
    auto prefix =
        sourcePrefix(archive.sources.data->identity, i, path, text.size());
    if (!authenticated && (revision.size() != 64 ||
                           std::any_of(revision.begin(), revision.end(),
                                       [](unsigned char byte) {
                                         return !(byte >= '0' && byte <= '9') &&
                                                !(byte >= 'a' && byte <= 'f');
                                       }) ||
                           sourceDigest(prefix, revision) != binding))
      in.fail("source revision binding does not match its identity");
    if (!in.good())
      break;
    excluded.push_back({offset, text.size()});
    auto &data = *archive.sources.data;
    data.sourceIndex.emplace(static_cast<SourceId>(i), i);
    if (!data.revisionIndex.emplace(std::string(revision), i).second) {
      in.fail("duplicate source revision");
      break;
    }
    data.revisions.push_back(SourceText::retain(revision, backing));
    data.sources.push_back(
        {std::move(path),
         SourceText::retain(
             text, backing,
             [prefix = std::move(prefix), revision](std::string_view text) {
               if (sourceDigest(prefix, text) != revision)
                 throw metadata::InvalidMetadata(
                     "invalid compiled library archive: source "
                     "revision does not match its identity and "
                     "contents");
               if (invalidUtf8(text))
                 throw metadata::InvalidMetadata(
                     "invalid compiled library archive: invalid "
                     "source encoding");
             }),
         static_cast<SourceId>(i)});
  }
  auto generationCount = in.count(32);
  if (generationCount > count)
    in.fail("too many generated sources");
  std::optional<ProvenanceScan> scan;
  if (!authenticated)
    scan.emplace(ProvenanceValidator(archive.sources.data->sources,
                                     archive.sources.data->sourceIndex, error));
  for (std::size_t i = 0; in.good() && i < generationCount; ++i) {
    const auto frame = in.textView();
    Reader generation(frame, error);
    SourceId source = 0;
    if (scan) {
      source = readGeneration<false>(generation, count, &*scan).source;
      if (generation.remaining())
        generation.fail("trailing generated-source data");
    } else
      source = generation.integer();
    if (in.good())
      archive.sources.data->generations.emplace_back(
          source, [frame, count, backing] {
            std::string error;
            Reader reader(frame, error);
            auto generation = readGeneration<true>(reader, count);
            if (!reader.good() || reader.remaining())
              throw metadata::InvalidMetadata(
                  error.empty() ? "trailing generated-source data" : error);
            return generation;
          });
  }
  const auto binderCount = in.count(1, limits::tokens);
  if (scan && in.good()) {
    scan->validator.finish();
    for (std::size_t i = 0; in.good() && i < scan->binders.size(); ++i)
      if (scan->binders[i] != i + 1)
        in.fail("non-canonical syntax-context binder order");
    if (scan->binders.size() != binderCount)
      in.fail("syntax-context binder count mismatch");
  }
  archive.sources.data->binders.emplace(binderCount);
  for (std::size_t i = 0; i < binderCount; ++i)
    (*archive.sources.data->binders)[i] = i + 1;
  auto modules = in.count(8);
  if (modules > count)
    in.fail("source-module table exceeds source table");
  for (std::size_t i = 0; in.good() && i < modules; ++i) {
    auto revision = in.text();
    auto parts = in.count(4);
    std::vector<std::string> path;
    for (std::size_t j = 0; in.good() && j < parts; ++j)
      path.push_back(in.text());
    if (!archive.sources.data->revisionIndex.contains(revision) ||
        !archive.sourceModules.emplace(std::move(revision), std::move(path))
             .second)
      in.fail("invalid or duplicate source-module reference");
  }
  archive.macros = in.text();
  auto section = [&](Section &target) { target.borrow(in.data(), backing); };
  section(archive.header);
  section(archive.types);
  const auto declarationsOffset = in.position() + 4;
  section(archive.declarations);
  if (in.good())
    populate(archive.declarations.bytes().data(), archive.declarations.size());
  auto readSeals = [&] {
    const auto count = in.count(68, limits::functions);
    std::vector<std::string_view> seals;
    seals.reserve(count);
    for (std::size_t i = 0; in.good() && i < count; ++i) {
      auto seal = in.textView();
      if (!authenticated &&
          (seal.size() != 64 ||
           std::any_of(seal.begin(), seal.end(), [](unsigned char byte) {
             return !(byte >= '0' && byte <= '9') &&
                    !(byte >= 'a' && byte <= 'f');
           })))
        in.fail("invalid deferred payload seal");
      seals.push_back(seal);
    }
    return seals;
  };
  auto declarationSeals = readSeals();
  auto irSeals = readSeals();
  const auto irOffset = in.position() + 4;
  section(archive.ir);
  if (in.remaining())
    in.fail("trailing data");
  if (!in.good())
    return std::nullopt;
  if (!authenticated) {
    auto declarationsLayout =
        archive.declarations.size()
            ? declarationPayloadLayout(archive.declarations)
            : DeclarationPayloadLayout{};
    if (!declarationsLayout ||
        declarationsLayout.payloads.size() != declarationSeals.size()) {
      error =
          "invalid compiled library declaration framing or payload seal count";
      return std::nullopt;
    }
    auto irLayout = ir::programLayout(archive.ir);
    if (!irLayout || irLayout.bodies.size() != irSeals.size()) {
      error = "invalid compiled library IR framing or body seal count";
      return std::nullopt;
    }
    excluded.reserve(excluded.size() + declarationsLayout.payloads.size() +
                     irLayout.bodies.size());
    excludePayloads(excluded, declarationsOffset, declarationsLayout.payloads);
    excludePayloads(excluded, irOffset, irLayout.bodies);
    if (metadataDigest(bytes.substr(0, bytes.size() - 64), excluded) !=
        bytes.substr(bytes.size() - 64)) {
      error = "invalid compiled library archive metadata checksum";
      return std::nullopt;
    }
  }
  if (!authenticated) {
    archive.verifyDeclarationPayload =
        payloadVerifier(backing, std::move(declarationSeals));
    archive.verifyIRBody = payloadVerifier(backing, std::move(irSeals));
  }
  archive.trusted = authenticated;
  archive.backing = std::move(backing);
  archive.sources.validated = true;
  return archive;
}
} // namespace mettle::driver
