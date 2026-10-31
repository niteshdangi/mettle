#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace mettle::packages {
// The user-level build cache: a content-addressed, deduplicated, bounded
// store. Artifacts are blobs named by their SHA-256, shared by every entry
// (and every project) that produced the same bytes. An entry maps a build key
// to a blob or to a small text record. Layout under the root:
//   VERSION            marks a directory as a store (required before `clear`)
//   entries/AA/KEY     one small file per key; its mtime is the last use
//   blobs/AA/SHA       immutable, read-only artifact bytes
//   leases/KEY/TOKEN   live-build markers; excluded from cache accounting
//   store.lock         cross-process lease/prune coordination
//   tmp/               in-flight writes, published by atomic rename
// Sizes are logical file sizes; allocated bytes are never smaller.
struct StoreLimits {
  // Upper bound on entry files plus referenced blobs after `prune`.
  std::uint64_t bytes = std::uint64_t(512) << 20;
  // Entries unused for longer are evicted; 0 disables the age limit.
  std::uint64_t maxAgeDays = 30;
};

struct StoreUsage {
  std::size_t entries = 0, blobs = 0;
  std::uint64_t bytes = 0;
};

class Store {
public:
  class Lease {
  public:
    Lease() = default;
    Lease(const Lease &) = delete;
    Lease &operator=(const Lease &) = delete;
    Lease(Lease &&other) noexcept;
    Lease &operator=(Lease &&other) noexcept;
    ~Lease();
    explicit operator bool() const { return !marker.empty(); }

  private:
    friend class Store;
    explicit Lease(std::filesystem::path marker);
    void release() noexcept;
    std::filesystem::path marker;
  };

  Store(std::filesystem::path root, StoreLimits limits);
  const std::filesystem::path &root() const { return directory; }
  const StoreLimits &limits() const { return bounds; }
  // Protects this key from age/size pruning until the lease is destroyed.
  Lease acquireLease(const std::string &key);

  enum class Lookup {
    Miss,
    Hit,
    // The entry or its blob failed verification and was deleted.
    Corrupt
  };
  // Copies the blob of `key` to `destination` (a fresh, privately owned
  // file; the shared blob is never exposed) and refreshes the entry's age.
  Lookup materialize(const std::string &key,
                     const std::filesystem::path &destination);
  // Stores the bytes of `file` under `key`; identical bytes share one blob.
  bool put(const std::string &key, const std::filesystem::path &file,
           bool executable);
  std::optional<std::string> text(const std::string &key);
  bool putText(const std::string &key, const std::string &text);

  // Applies the age then byte limit, oldest use first, and removes blobs no
  // entry references and stale scratch files. `keep` (the entry just
  // published) is evicted last. Returns one explanation per removal.
  std::vector<std::string> prune(const std::string &keep = {});
  StoreUsage usage() const;
  // Deletes the store's own directories (never anything else). With `dryRun`
  // only counts. Refuses a non-empty directory that lacks the VERSION marker.
  std::optional<StoreUsage> clear(bool dryRun, std::string &error);

private:
  struct Record {
    std::filesystem::path path;
    std::string key, blob;
    std::uint64_t size = 0;
    std::filesystem::file_time_type used;
  };
  std::filesystem::path entryPath(const std::string &key) const;
  std::filesystem::path blobPath(const std::string &blob) const;
  std::filesystem::path scratch() const;
  bool prepare();
  bool publish(const std::filesystem::path &path, const std::string &content);
  bool publishLocked(const std::filesystem::path &path,
                     const std::string &content);
  std::vector<Record> records() const;
  std::filesystem::path directory;
  StoreLimits bounds;
};

// Lowercase hexadecimal SHA-256 of a file's bytes; `size` receives its length.
std::optional<std::string> hashFile(const std::filesystem::path &file,
                                    std::uint64_t &size);
} // namespace mettle::packages
