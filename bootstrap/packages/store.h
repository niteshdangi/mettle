#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::packages {
// The user-level build cache: a content-addressed, deduplicated, bounded
// store. Artifacts are blobs named by their SHA-256, shared by every entry
// (and every project) that produced the same bytes. An entry maps a build key
// to a blob or to a small text record. Layout under the root:
//   VERSION            marks a directory as a store (required before `clear`)
//   entries/AA/KEY     one small file per key; its mtime is the last use
//   blobs/AA/SHA       immutable, read-only artifact bytes
//   roots/ID           working set (source path, then keys) of one project
//                      configuration, written by `commitProject`
//   leases/KEY/TOKEN   live-build markers; excluded from cache accounting
//   store.lock         cross-process lease/prune coordination
//   tmp/               in-flight writes, published by atomic rename
// Sizes are logical file sizes; allocated bytes are never smaller.
struct StoreLimits {
  // Upper bound on entry files plus referenced blobs after `prune`; 0 is
  // unbounded.
  std::uint64_t bytes = 0;
  // Entries unused for longer are evicted; 0 disables the age limit.
  std::uint64_t maxAgeDays = 30;
};

struct StoreUsage {
  std::size_t entries = 0, blobs = 0;
  std::uint64_t bytes = 0;
};

class Store {
public:
  struct Artifact {
    std::string key;
    std::filesystem::path file;
    bool executable = false;
  };

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
  struct Data {
    Lookup status = Lookup::Miss;
    std::string bytes;
  };
  // Entries a toolchain ships (its prebuilt library) are read through this
  // store on a miss; the shipped store is never written, touched or pruned.
  void useShipped(std::filesystem::path root);
  Data data(const std::string &key, std::uint64_t maximumBytes);
  // A read-only view of an artifact's bytes that owns its file mapping.
  class Mapping {
  public:
    Mapping(const void *address, std::size_t size)
        : address(address), length(size) {}
    Mapping(const Mapping &) = delete;
    Mapping &operator=(const Mapping &) = delete;
    ~Mapping();
    std::string_view bytes() const {
      return {static_cast<const char *>(address), length};
    }

  private:
    const void *address;
    std::size_t length;
  };
  struct Mapped {
    Lookup status = Lookup::Miss;
    std::shared_ptr<const Mapping> mapping;
  };
  using Verifier = std::function<bool(const std::shared_ptr<const Mapping> &)>;
  Mapped mapped(const std::string &key, std::uint64_t maximumBytes,
                const Verifier &verify = {});
  bool putData(const std::string &key, std::string_view bytes);
  // Copies the blob of `key` to `destination` (a fresh, privately owned
  // file; the shared blob is never exposed) and refreshes the entry's age.
  Lookup materialize(const std::string &key,
                     const std::filesystem::path &destination);
  // Stores the bytes of `file` under `key`; identical bytes share one blob.
  bool put(const std::string &key, const std::filesystem::path &file,
           bool executable);
  // Stores multiple files after hashing and staging them outside the store
  // lock, then publishes all entry metadata under one lock.
  bool putMany(const std::vector<Artifact> &artifacts);
  std::optional<std::string> text(const std::string &key);
  bool putText(const std::string &key, const std::string &text);

  // Applies the age then byte limit, oldest use first, and removes blobs no
  // entry references and stale scratch files. `keep` (the entry just
  // published) is evicted last. Returns one explanation per removal.
  std::vector<std::string> prune(const std::string &keep = {});
  // Records the entries this store object read or wrote as the working set of
  // `project`, a stable name for one project configuration whose sources live
  // at `path`. Evicts the entries that set held before and no live project
  // holds now, and those held only by projects whose `path` is gone. The
  // cache stays proportional to the live projects' current builds without a
  // global size bound. Returns one explanation per removal.
  std::vector<std::string> commitProject(const std::string &project,
                                         const std::filesystem::path &path,
                                         const std::string &keep = {});
  StoreUsage usage() const;
  // Deletes the store's own directories (never anything else). With `dryRun`
  // only counts. Refuses a non-empty directory that lacks the VERSION marker.
  std::optional<StoreUsage> clear(bool dryRun, std::string &error);

private:
  Data localData(const std::string &key, std::uint64_t maximumBytes);
  Mapped localMapped(const std::string &key, std::uint64_t maximumBytes,
                     const Verifier &verify);
  Lookup localMaterialize(const std::string &key,
                          const std::filesystem::path &destination);
  std::optional<std::string> localText(const std::string &key);
  std::unique_ptr<Store> shipped;
  struct Record {
    std::string key, blob;
    std::uint64_t size = 0;
    std::filesystem::file_time_type used;
  };
  std::filesystem::path entryPath(const std::string &key) const;
  std::filesystem::path blobPath(const std::string &blob) const;
  std::filesystem::path scratch() const;
  bool prepare();
  bool publish(const std::string &key, const std::string &content);
  bool publishLocked(const std::filesystem::path &path,
                     const std::string &content);
  void invalidate(const std::string &key, const std::string &content,
                  bool blob = false);
  struct Accounting;
  Accounting &accountingLocked();
  std::shared_ptr<Accounting> accounting;
  std::vector<std::string> pruneLocked(const std::set<std::string> &keep,
                                       std::set<std::string> leased);
  std::vector<Record> records() const;
  struct Touched {
    std::mutex lock, accountingLock;
    std::set<std::string> keys;
  };
  void note(const std::string &key) const;
  std::filesystem::path directory;
  StoreLimits bounds;
  std::shared_ptr<Touched> touched = std::make_shared<Touched>();
};

// Lowercase hexadecimal SHA-256 of a file's bytes; `size` receives its length.
std::optional<std::string> hashFile(const std::filesystem::path &file,
                                    std::uint64_t &size);
} // namespace mettle::packages
