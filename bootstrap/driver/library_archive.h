#pragma once

#include "diagnostics/diagnostics.h"
#include "metadata/references.h"
#include <functional>
#include <map>
#include <unordered_map>

namespace mettle::driver {
struct LibraryArchive;

class LibrarySources {
public:
  explicit LibrarySources(std::string identity);
  std::optional<std::string> record(const Source &source, std::string &error);
  bool capture(const Diagnostics &diagnostics, std::string &error);
  std::optional<metadata::SourceReference> reference(Span span) const;
  std::optional<Span> resolve(const metadata::SourceReference &reference) const;
  const Source *source(std::string_view revision) const;
  bool mount(Diagnostics &diagnostics,
             const std::function<std::optional<SourceId>()> &allocate,
             std::string &error);

private:
  friend std::optional<std::string> encodeLibraryArchive(const LibraryArchive &,
                                                         std::string &);
  friend std::optional<LibraryArchive>
  decodeLibraryArchive(std::string_view, std::string_view, std::string &);
  bool validate(std::string &error) const;
  std::string identity;
  std::vector<Source> sources;
  std::vector<Generation> generations;
  std::vector<std::string> revisions;
  std::unordered_map<SourceId, std::size_t> sourceIndex;
  std::unordered_map<std::string, std::size_t> revisionIndex;
};

struct LibraryArchive {
  explicit LibraryArchive(std::string identity)
      : sources(std::move(identity)) {}
  LibrarySources sources;
  std::map<std::string, std::vector<std::string>> sourceModules;
  std::string macros;
  std::vector<std::uint8_t> header, types, declarations, ir;
};

std::optional<std::string> encodeLibraryArchive(const LibraryArchive &archive,
                                                std::string &error);
std::optional<LibraryArchive> decodeLibraryArchive(std::string_view bytes,
                                                   std::string_view identity,
                                                   std::string &error);
} // namespace mettle::driver
