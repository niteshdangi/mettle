#include "driver/library_archive.h"
#include "packages/sha256.h"
#include "support/limits.h"
#include <algorithm>
#include <limits>
#include <unordered_set>

namespace mettle::driver {
namespace {
std::string digest(std::string_view bytes) {
  packages::Sha256 hash;
  hash.update(bytes);
  return hash.finish();
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
  void data(const std::vector<std::uint8_t> &value) {
    text({reinterpret_cast<const char *>(value.data()), value.size()});
  }
};

class Reader {
public:
  Reader(std::string_view bytes, std::string &error)
      : bytes(bytes), error(error) {}
  bool good() const { return error.empty(); }
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
  std::size_t count(std::size_t minimumBytes) {
    auto value = integer();
    if (value > limits::tokens || value > remaining() / minimumBytes) {
      fail("invalid table size");
      return 0;
    }
    return value;
  }
  std::string text() {
    auto size = integer();
    if (!good() || size > remaining()) {
      fail("truncated string");
      return {};
    }
    auto result = std::string(bytes.substr(offset, size));
    offset += size;
    return result;
  }
  std::vector<std::uint8_t> data() {
    auto size = integer();
    if (!good() || size > remaining()) {
      fail("truncated section");
      return {};
    }
    const auto *begin =
        reinterpret_cast<const std::uint8_t *>(bytes.data() + offset);
    offset += size;
    return {begin, begin + size};
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

LibrarySources::LibrarySources(std::string identity)
    : identity(std::move(identity)) {}

std::optional<std::string> LibrarySources::record(const Source &source,
                                                  std::string &error) {
  if (auto found = sourceIndex.find(source.id); found != sourceIndex.end()) {
    const auto &previous = sources[found->second];
    if (previous.path != source.path || previous.text != source.text) {
      error = "compiled library source ID names conflicting revisions";
      return std::nullopt;
    }
    return revisions[found->second];
  }
  if (identity.empty() || identity.size() > limits::sourceBytes ||
      source.path.size() > limits::sourceBytes ||
      source.text.size() > limits::sourceBytes ||
      sources.size() >= limits::tokens || invalidUtf8(source.text)) {
    error = "invalid compiled library source identity, size or encoding";
    return std::nullopt;
  }
  Writer revision;
  revision.text(identity);
  revision.integer(static_cast<std::uint32_t>(sources.size()));
  revision.text(source.path);
  revision.integer(static_cast<std::uint32_t>(source.text.size()));
  packages::Sha256 hash;
  hash.update(revision.bytes);
  hash.update(source.text);
  auto name = hash.finish();
  sourceIndex.emplace(source.id, sources.size());
  revisionIndex.emplace(name, sources.size());
  revisions.push_back(name);
  sources.push_back(source);
  return name;
}

std::optional<metadata::SourceReference>
LibrarySources::reference(Span span) const {
  auto found = sourceIndex.find(span.source);
  if (found == sourceIndex.end() || span.begin > span.end ||
      span.end > sources[found->second].text.size())
    return std::nullopt;
  return metadata::SourceReference{revisions[found->second],
                                   static_cast<std::uint32_t>(span.begin),
                                   static_cast<std::uint32_t>(span.end)};
}

std::optional<Span>
LibrarySources::resolve(const metadata::SourceReference &reference) const {
  auto found = revisionIndex.find(reference.revision);
  if (found == revisionIndex.end() || reference.begin > reference.end ||
      reference.end > sources[found->second].text.size())
    return std::nullopt;
  return Span{reference.begin, reference.end, sources[found->second].id};
}

const Source *LibrarySources::source(std::string_view revision) const {
  auto found = revisionIndex.find(std::string(revision));
  return found == revisionIndex.end() ? nullptr : &sources[found->second];
}

bool LibrarySources::validate(std::string &error) const {
  auto fail = [&](std::string_view message) {
    error = "invalid compiled library source archive: " + std::string(message);
    return false;
  };
  if (identity.empty() || sources.size() > limits::tokens ||
      generations.size() > sources.size())
    return fail("invalid identity or table size");
  std::unordered_map<SourceId, std::vector<SourceId>> parents;
  for (const auto &generation : generations) {
    auto found = sourceIndex.find(generation.source);
    if (found == sourceIndex.end() ||
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
          mapping.end > sources[found->second].text.size() ||
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
  candidate.generations = diagnostics.registeredGenerations();
  if (!candidate.validate(error))
    return false;
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
  for (const auto &source : sources) {
    auto id = allocate();
    if (!id || *id == 0 || !occupied.insert(*id).second) {
      error = "compiled library source allocation exhausted or collided";
      return false;
    }
    remap.emplace(source.id, *id);
  }
  auto span = [&](Span value) {
    value.source = remap.at(value.source);
    return value;
  };
  auto mountedGenerations = generations;
  std::unordered_map<SourceId, std::size_t> mountedIndex;
  for (std::size_t i = 0; i < sources.size(); ++i)
    mountedIndex.emplace(remap.at(sources[i].id), i);
  std::unordered_map<std::uint64_t, std::uint64_t> binders;
  for (auto &generation : mountedGenerations) {
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
  for (auto &source : sources) {
    source.id = remap.at(source.id);
    Diagnostics::SourceContext registerSource(diagnostics, source);
  }
  for (const auto &generation : mountedGenerations)
    diagnostics.generated(generation);
  sourceIndex = std::move(mountedIndex);
  generations = std::move(mountedGenerations);
  return true;
}

std::optional<std::string> encodeLibraryArchive(const LibraryArchive &archive,
                                                std::string &error) {
  error.clear();
  const auto &sources = archive.sources;
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
  if (archive.sourceModules.size() > sources.sources.size()) {
    error = "compiled library source-module table exceeds its source table";
    return std::nullopt;
  }
  for (const auto &[revision, path] : archive.sourceModules)
    if (!sources.revisionIndex.contains(revision) ||
        path.size() > limits::tokens ||
        std::any_of(path.begin(), path.end(), [](const auto &part) {
          return part.size() > limits::sourceBytes;
        })) {
      error = "invalid compiled library source-module reference";
      return std::nullopt;
    }
  Writer out;
  out.text("mettle-checked-library-1");
  out.text(sources.identity);
  out.integer(static_cast<std::uint32_t>(sources.sources.size()));
  for (const auto &source : sources.sources) {
    out.text(source.path);
    out.text(source.text);
  }
  auto span = [&](Span value) {
    out.integer(
        static_cast<std::uint32_t>(sources.sourceIndex.at(value.source)));
    out.integer(static_cast<std::uint32_t>(value.begin));
    out.integer(static_cast<std::uint32_t>(value.end));
  };
  std::unordered_map<std::uint64_t, std::uint32_t> binders;
  out.integer(static_cast<std::uint32_t>(sources.generations.size()));
  for (const auto &generation : sources.generations) {
    out.integer(
        static_cast<std::uint32_t>(sources.sourceIndex.at(generation.source)));
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
  out.data(archive.declarations);
  out.data(archive.ir);
  if (out.bytes.size() > limits::sourceBytes - 64) {
    error = "compiled library archive exceeds the compiler data-file limit";
    return std::nullopt;
  }
  out.bytes += digest(out.bytes);
  return std::move(out.bytes);
}

std::optional<LibraryArchive> decodeLibraryArchive(std::string_view bytes,
                                                   std::string_view identity,
                                                   std::string &error) {
  error.clear();
  if (bytes.size() > limits::sourceBytes || bytes.size() < 64 ||
      digest(bytes.substr(0, bytes.size() - 64)) !=
          bytes.substr(bytes.size() - 64)) {
    error = "invalid compiled library archive size or checksum";
    return std::nullopt;
  }
  Reader in(bytes.substr(0, bytes.size() - 64), error);
  if (in.text() != "mettle-checked-library-1")
    in.fail("unsupported format");
  auto revision = in.text();
  if (revision != identity || revision.empty())
    in.fail("compiler, content or configuration identity mismatch");
  LibraryArchive archive(std::move(revision));
  auto count = in.count(8);
  for (std::size_t i = 0; in.good() && i < count; ++i) {
    auto path = in.text();
    auto text = in.text();
    if (in.good())
      archive.sources.record(
          {std::move(path), std::move(text), static_cast<SourceId>(i)}, error);
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
    archive.sources.generations.push_back(std::move(generation));
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
    if (!archive.sources.revisionIndex.contains(revision) ||
        !archive.sourceModules.emplace(std::move(revision), std::move(path))
             .second)
      in.fail("invalid or duplicate source-module reference");
  }
  archive.macros = in.text();
  archive.header = in.data();
  archive.types = in.data();
  archive.declarations = in.data();
  archive.ir = in.data();
  if (in.remaining())
    in.fail("trailing data");
  if (!in.good() || !archive.sources.validate(error))
    return std::nullopt;
  return archive;
}
} // namespace mettle::driver
