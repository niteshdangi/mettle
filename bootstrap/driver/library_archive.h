#pragma once

#include "diagnostics/diagnostics.h"
#include "metadata/references.h"
#include <algorithm>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <span>
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
  std::span<const Source> snapshots() const { return data->sources; }
  // Published snapshots retain source text and provenance through diagnostics.
  bool mount(Diagnostics &diagnostics,
             const std::function<std::optional<SourceId>()> &allocate,
             std::string &error);

private:
  friend std::optional<std::string> encodeLibraryArchive(const LibraryArchive &,
                                                         std::string &);
  friend std::optional<LibraryArchive>
  decodeLibraryArchive(std::string_view, std::string_view, std::string &,
                       std::shared_ptr<const void>);
  std::optional<std::string> record(const Source &source, std::string &error,
                                    std::optional<SourceText> revision);
  bool validate(std::string &error) const;
  struct Data {
    std::string identity;
    std::vector<Source> sources;
    std::vector<Generation> generations;
    std::vector<SourceText> revisions;
    std::unordered_map<SourceId, std::size_t> sourceIndex;
    std::unordered_map<std::string, std::size_t> revisionIndex;
  };
  struct Mounted {
    std::shared_ptr<Data> data;
    std::vector<SourceId> ids;
    std::uint64_t syntaxBegin = 0, syntaxEnd = 0;
  };
  struct MountCache {
    std::mutex mutex;
    std::shared_ptr<const Mounted> current;
  };
  void edit();
  std::shared_ptr<Data> data = std::make_shared<Data>();
  std::shared_ptr<MountCache> mounts = std::make_shared<MountCache>();
  bool mounted = false;
  bool validated = false;
};

// Immutable storage, or a view kept alive by the archive's backing.
class Section {
public:
  Section() = default;
  Section &operator=(std::vector<std::uint8_t> bytes) {
    auto owner =
        std::make_shared<const std::vector<std::uint8_t>>(std::move(bytes));
    storage = std::shared_ptr<const std::uint8_t>(owner, owner->data());
    length = owner->size();
    return *this;
  }
  void borrow(std::span<const std::uint8_t> bytes,
              std::shared_ptr<const void> owner) {
    if (!owner) {
      *this = std::vector<std::uint8_t>(bytes.begin(), bytes.end());
      return;
    }
    storage =
        std::shared_ptr<const std::uint8_t>(std::move(owner), bytes.data());
    length = bytes.size();
  }
  std::span<const std::uint8_t> bytes() const {
    return storage ? std::span<const std::uint8_t>(storage.get(), length)
                   : std::span<const std::uint8_t>{};
  }
  operator std::span<const std::uint8_t>() const { return bytes(); }
  std::size_t size() const { return bytes().size(); }
  bool operator==(const Section &other) const {
    return std::ranges::equal(bytes(), other.bytes());
  }

private:
  std::shared_ptr<const std::uint8_t> storage;
  std::size_t length = 0;
};

struct LibraryArchive {
  explicit LibraryArchive(std::string identity)
      : sources(std::move(identity)) {}
  LibrarySources sources;
  std::map<std::string, std::vector<std::string>> sourceModules;
  std::string macros;
  Section header, types, declarations, ir;
  std::function<bool(std::size_t, std::span<const std::uint8_t>)> verifyIRBody,
      verifyDeclarationPayload;
  // Keeps the memory the borrowed sections point into alive.
  std::shared_ptr<const void> backing;
};

std::string archiveDigest(std::string_view bytes);
std::optional<std::string> encodeLibraryArchive(const LibraryArchive &archive,
                                                std::string &error);
// With `backing`, `bytes` lives in it and the sections are views, not copies.
std::optional<LibraryArchive>
decodeLibraryArchive(std::string_view bytes, std::string_view identity,
                     std::string &error,
                     std::shared_ptr<const void> backing = nullptr);
} // namespace mettle::driver
