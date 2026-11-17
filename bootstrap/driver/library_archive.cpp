#include "driver/library_archive.h"
#include "ir/codec.h"
#include "packages/sha256.h"
#include "semantics/library.h"
#include "support/limits.h"
#include <algorithm>
#include <limits>
#include <thread>
#include <unordered_set>

namespace mettle::driver {
namespace {
template <class HashBlock>
std::string blockDigest(std::size_t size, HashBlock hashBlock) {
  constexpr std::size_t block = std::size_t{1} << 20;
  const std::size_t blocks = (size + block - 1) / block;
  std::vector<std::string> parts(blocks);
  const std::size_t workers = std::min<std::size_t>(
      blocks, std::max(1u, std::min(8u, std::thread::hardware_concurrency())));
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
  std::vector<std::size_t> sizes;
};

void excludePayloads(std::vector<PayloadRange> &excluded,
                     std::size_t sectionOffset, const auto &payloads) {
  for (const auto &payload : payloads)
    excluded.push_back({sectionOffset + payload.offset, payload.size});
}

ir::FunctionBodyVerifier payloadVerifier(std::shared_ptr<const void> backing,
                                         std::vector<std::string_view> digests,
                                         const auto &payloads) {
  std::vector<std::size_t> sizes;
  sizes.reserve(payloads.size());
  for (const auto &payload : payloads)
    sizes.push_back(payload.size);
  auto integrity = std::make_shared<const PayloadSeals>(
      PayloadSeals{std::move(backing), std::move(digests), std::move(sizes)});
  return [integrity](std::size_t index, std::span<const std::uint8_t> payload) {
    return integrity->backing && index < integrity->digests.size() &&
           payload.size() == integrity->sizes[index] &&
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
};

class Reader {
public:
  Reader(std::string_view bytes, std::string &error)
      : bytes(bytes), error(error) {}
  bool good() const { return error.empty(); }
  std::size_t position() const { return offset; }
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
  return record(source, error, std::nullopt);
}

std::optional<std::string>
LibrarySources::record(const Source &source, std::string &error,
                       std::optional<SourceText> revision) {
  if (auto found = data->sourceIndex.find(source.id);
      found != data->sourceIndex.end()) {
    const auto &previous = data->sources[found->second];
    if (previous.path != source.path || previous.text != source.text ||
        (revision && *revision != data->revisions[found->second])) {
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
  Writer prefix;
  prefix.text(data->identity);
  prefix.integer(static_cast<std::uint32_t>(data->sources.size()));
  prefix.text(source.path);
  prefix.integer(static_cast<std::uint32_t>(source.text.size()));
  packages::Sha256 hash;
  hash.update(prefix.bytes);
  hash.update(source.text);
  auto name = hash.finish();
  if (revision && *revision != name) {
    error = "invalid compiled library archive: source revision does not match "
            "its identity and contents";
    return std::nullopt;
  }
  edit();
  data->sourceIndex.emplace(source.id, data->sources.size());
  data->revisionIndex.emplace(name, data->sources.size());
  data->revisions.push_back(revision ? std::move(*revision) : SourceText(name));
  data->sources.push_back(source);
  return name;
}

std::optional<metadata::SourceReference>
LibrarySources::reference(Span span) const {
  auto found = data->sourceIndex.find(span.source);
  if (found == data->sourceIndex.end() || span.begin > span.end ||
      span.end > data->sources[found->second].text.size())
    return std::nullopt;
  return metadata::SourceReference{data->revisions[found->second],
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
  std::unordered_map<SourceId, std::vector<SourceId>> parents;
  for (const auto &generation : data->generations) {
    auto found = data->sourceIndex.find(generation.source);
    if (found == data->sourceIndex.end() ||
        !parents.emplace(generation.source, std::vector<SourceId>{}).second ||
        generation.description.size() > limits::sourceBytes ||
        generation.mappings.size() > limits::tokens)
      return fail("invalid or duplicate generated source");
    auto &edges = parents.at(generation.source);
    auto span = [&](Span value) {
      if (!reference(value))
        return false;
      edges.push_back(value.source);
      return true;
    };
    if (!span(generation.origin))
      return fail("invalid generation origin");
    std::size_t previousEnd = 0;
    for (const auto &mapping : generation.mappings) {
      if (mapping.begin < previousEnd || mapping.begin > mapping.end ||
          mapping.end > data->sources[found->second].text.size() ||
          mapping.description.size() > limits::sourceBytes ||
          !span(mapping.target) ||
          (!mapping.description.empty() && !span(mapping.origin)) ||
          (mapping.exact && mapping.end - mapping.begin >
                                mapping.target.end - mapping.target.begin))
        return fail("invalid generation mapping");
      previousEnd = mapping.end;
      if (mapping.syntaxContext && *mapping.syntaxContext) {
        const auto &context = **mapping.syntaxContext;
        if (!reference(context.definition) ||
            context.scope.size() > limits::tokens ||
            std::any_of(context.scope.begin(), context.scope.end(),
                        [](const auto &part) {
                          return part.size() > limits::sourceBytes;
                        }))
          return fail("invalid syntax context");
      }
    }
  }
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

bool LibrarySources::capture(const Diagnostics &diagnostics,
                             std::string &error) {
  auto candidate = *this;
  for (const auto &source : diagnostics.registeredSources())
    if (!candidate.record(source, error))
      return false;
  candidate.edit();
  const auto generations = diagnostics.registeredGenerations();
  candidate.data->generations.assign(generations.begin(), generations.end());
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
      diagnostics.generated(
          std::shared_ptr<const Generation>(data, &generation));
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
  auto span = [&](Span value) {
    value.source = remap.at(value.source);
    return value;
  };
  std::unordered_map<SourceId, std::size_t> mountedIndex;
  for (std::size_t i = 0; i < data->sources.size(); ++i)
    mountedIndex.emplace(remap.at(data->sources[i].id), i);
  std::unordered_map<std::uint64_t, std::uint64_t> binders;
  for (auto &generation : data->generations) {
    generation.source = remap.at(generation.source);
    generation.origin = span(generation.origin);
    for (auto &mapping : generation.mappings) {
      mapping.target = span(mapping.target);
      if (!mapping.description.empty())
        mapping.origin = span(mapping.origin);
      if (!mapping.syntaxContext || !*mapping.syntaxContext)
        continue;
      const auto &context = **mapping.syntaxContext;
      auto definition = span(context.definition);
      std::uint64_t identity = 0;
      if (context.identity) {
        auto found = binders.find(context.identity);
        if (found == binders.end()) {
          identity = diagnostics.makeSyntaxContext(context.scope, definition)
                         ->identity;
          binders.emplace(context.identity, identity);
        } else {
          identity = found->second;
        }
      }
      mapping.syntaxContext = std::make_shared<const SyntaxContext>(
          SyntaxContext{context.scope, definition, identity});
    }
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
  out.text("mettle-checked-library-4");
  out.text(data.identity);
  out.integer(static_cast<std::uint32_t>(data.sources.size()));
  for (std::size_t i = 0; i < data.sources.size(); ++i) {
    const auto &source = data.sources[i];
    out.text(source.path);
    out.text(source.text);
    out.text(data.revisions[i]);
  }
  auto span = [&](Span value) {
    out.integer(static_cast<std::uint32_t>(data.sourceIndex.at(value.source)));
    out.integer(static_cast<std::uint32_t>(value.begin));
    out.integer(static_cast<std::uint32_t>(value.end));
  };
  std::unordered_map<std::uint64_t, std::uint32_t> binders;
  out.integer(static_cast<std::uint32_t>(data.generations.size()));
  for (const auto &generation : data.generations) {
    out.integer(
        static_cast<std::uint32_t>(data.sourceIndex.at(generation.source)));
    span(generation.origin);
    out.text(generation.description);
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
      out.boolean(mapping.syntaxContext.has_value());
      if (!mapping.syntaxContext)
        continue;
      out.boolean(static_cast<bool>(*mapping.syntaxContext));
      if (!*mapping.syntaxContext)
        continue;
      const auto &context = **mapping.syntaxContext;
      auto binder =
          context.identity
              ? binders
                    .try_emplace(context.identity,
                                 static_cast<std::uint32_t>(binders.size() + 1))
                    .first->second
              : 0;
      out.integer(binder);
      out.integer(static_cast<std::uint32_t>(context.scope.size()));
      for (const auto &part : context.scope)
        out.text(part);
      span(context.definition);
    }
  }
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
  std::vector<PayloadRange> excluded;
  excluded.reserve(declarationsLayout.payloads.size() + irLayout.bodies.size());
  excludePayloads(excluded, declarationsOffset, declarationsLayout.payloads);
  excludePayloads(excluded, irOffset, irLayout.bodies);
  out.bytes += metadataDigest(out.bytes, excluded);
  return std::move(out.bytes);
}

std::optional<LibraryArchive>
decodeLibraryArchive(std::string_view bytes, std::string_view identity,
                     std::string &error, std::shared_ptr<const void> backing) {
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
  if (in.textView() != "mettle-checked-library-4")
    in.fail("unsupported format");
  auto revision = in.text();
  if (revision != identity || revision.empty())
    in.fail("compiler, content or configuration identity mismatch");
  LibraryArchive archive(std::move(revision));
  auto count = in.count(12);
  for (std::size_t i = 0; in.good() && i < count; ++i) {
    auto path = in.text();
    auto text = in.textView();
    auto revision = in.textView();
    if (in.good())
      archive.sources.record({std::move(path),
                              SourceText::retain(text, backing),
                              static_cast<SourceId>(i)},
                             error, SourceText::retain(revision, backing));
  }
  auto generationCount = in.count(24);
  if (generationCount > count)
    in.fail("too many generated sources");
  for (std::size_t i = 0; in.good() && i < generationCount; ++i) {
    Generation generation;
    generation.source = in.integer();
    generation.origin = in.span(count);
    generation.description = in.text();
    auto mappings = in.count(26);
    for (std::size_t j = 0; in.good() && j < mappings; ++j) {
      Generation::Mapping mapping;
      mapping.begin = in.integer();
      mapping.end = in.integer();
      mapping.target = in.span(count);
      mapping.exact = in.boolean();
      auto hasOrigin = in.boolean();
      if (hasOrigin)
        mapping.origin = in.span(count);
      mapping.description = in.text();
      if (hasOrigin != !mapping.description.empty())
        in.fail("inconsistent mapping origin");
      if (in.boolean()) {
        mapping.syntaxContext = SyntaxContextPtr{};
        if (in.boolean()) {
          auto binder = in.integer();
          auto parts = in.count(4);
          std::vector<std::string> scope;
          for (std::size_t k = 0; in.good() && k < parts; ++k)
            scope.push_back(in.text());
          auto definition = in.span(count);
          mapping.syntaxContext = std::make_shared<const SyntaxContext>(
              SyntaxContext{std::move(scope), definition, binder});
        }
      }
      generation.mappings.push_back(std::move(mapping));
    }
    archive.sources.data->generations.push_back(std::move(generation));
  }
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
  auto readSeals = [&] {
    const auto count = in.count(68, limits::functions);
    std::vector<std::string_view> seals;
    seals.reserve(count);
    for (std::size_t i = 0; in.good() && i < count; ++i) {
      auto seal = in.textView();
      if (seal.size() != 64 ||
          std::any_of(seal.begin(), seal.end(), [](unsigned char byte) {
            return !(byte >= '0' && byte <= '9') &&
                   !(byte >= 'a' && byte <= 'f');
          }))
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
  auto declarationsLayout = archive.declarations.size()
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
  std::vector<PayloadRange> excluded;
  excluded.reserve(declarationsLayout.payloads.size() + irLayout.bodies.size());
  excludePayloads(excluded, declarationsOffset, declarationsLayout.payloads);
  excludePayloads(excluded, irOffset, irLayout.bodies);
  if (metadataDigest(bytes.substr(0, bytes.size() - 64), excluded) !=
      bytes.substr(bytes.size() - 64)) {
    error = "invalid compiled library archive metadata checksum";
    return std::nullopt;
  }
  if (!archive.sources.validate(error))
    return std::nullopt;
  archive.verifyDeclarationPayload = payloadVerifier(
      backing, std::move(declarationSeals), declarationsLayout.payloads);
  archive.verifyIRBody =
      payloadVerifier(backing, std::move(irSeals), irLayout.bodies);
  archive.backing = std::move(backing);
  archive.sources.validated = true;
  return archive;
}
} // namespace mettle::driver
