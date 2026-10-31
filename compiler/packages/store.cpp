#include "packages/store.h"
#include "packages/sha256.h"
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace mettle::packages {
namespace {
namespace fs = std::filesystem;

std::optional<std::string> readText(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream)
    return std::nullopt;
  std::ostringstream text;
  text << stream.rdbuf();
  return text.str();
}

struct Entry {
  bool text = false;
  std::string blob, payload;
  std::uint64_t size = 0;
  bool executable = false;
};

std::optional<Entry> parseEntry(const std::string &content) {
  auto end = content.find('\n');
  if (end == std::string::npos)
    return std::nullopt;
  std::istringstream head(content.substr(0, end));
  std::string kind;
  head >> kind;
  Entry entry;
  if (kind == "text") {
    entry.text = true;
    entry.payload = content.substr(end + 1);
    return entry;
  }
  std::string mode;
  if (kind != "file" || !(head >> entry.blob >> entry.size >> mode) ||
      entry.blob.size() != 64 || (mode != "x" && mode != "-"))
    return std::nullopt;
  entry.executable = mode == "x";
  return entry;
}

bool hexName(const std::string &name) {
  return name.size() >= 2 && std::all_of(name.begin(), name.end(), [](char c) {
           return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
         });
}

std::uint64_t sizeOf(const fs::path &path) {
  std::error_code error;
  auto size = fs::file_size(path, error);
  return error ? 0 : size;
}

void touch(const fs::path &path) {
  std::error_code error;
  fs::last_write_time(path, fs::file_time_type::clock::now(), error);
}

class StoreLock {
public:
  explicit StoreLock(const fs::path &directory)
      : path(directory / "store.lock") {
    descriptor = open(path.c_str(), O_CREAT | O_RDWR, 0600);
    if (descriptor < 0 || flock(descriptor, LOCK_EX) != 0) {
      release();
      return;
    }
    struct stat opened{}, current{};
    if (fstat(descriptor, &opened) != 0 || stat(path.c_str(), &current) != 0 ||
        opened.st_dev != current.st_dev || opened.st_ino != current.st_ino)
      release();
  }

  StoreLock(const StoreLock &) = delete;
  StoreLock &operator=(const StoreLock &) = delete;
  ~StoreLock() { release(); }
  explicit operator bool() const { return descriptor >= 0; }

  void release() {
    if (descriptor < 0)
      return;
    flock(descriptor, LOCK_UN);
    close(descriptor);
    descriptor = -1;
  }

private:
  fs::path path;
  int descriptor = -1;
};

std::set<std::string> liveLeaseKeys(const fs::path &directory) {
  std::set<std::string> keys;
  std::error_code error;
  auto root = directory / "leases";
  for (fs::directory_iterator key(root, error), end; !error && key != end;
       key.increment(error)) {
    std::error_code statusError;
    if (!key->is_directory(statusError) || statusError)
      continue;
    bool live = false;
    std::error_code markerError;
    for (fs::directory_iterator marker(key->path(), markerError), markerEnd;
         !markerError && marker != markerEnd; marker.increment(markerError)) {
      std::ifstream owner(marker->path());
      long process = 0;
      if (owner >> process && process > 0 &&
          (kill(static_cast<pid_t>(process), 0) == 0 || errno == EPERM)) {
        live = true;
        continue;
      }
      std::error_code ignored;
      fs::remove(marker->path(), ignored);
    }
    if (live) {
      keys.insert(key->path().filename().string());
    } else {
      std::error_code ignored;
      fs::remove(key->path(), ignored);
    }
  }
  return keys;
}
} // namespace

std::optional<std::string> hashFile(const fs::path &file, std::uint64_t &size) {
  std::ifstream stream(file, std::ios::binary);
  if (!stream)
    return std::nullopt;
  Sha256 hash;
  std::string buffer(1 << 16, '\0');
  size = 0;
  while (stream) {
    stream.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    auto count = static_cast<std::size_t>(stream.gcount());
    hash.update(std::string_view(buffer.data(), count));
    size += count;
  }
  if (!stream.eof())
    return std::nullopt;
  return hash.finish();
}

Store::Store(fs::path root, StoreLimits limits)
    : directory(std::move(root)), bounds(limits) {}

Store::Lease::Lease(fs::path marker) : marker(std::move(marker)) {}

Store::Lease::Lease(Lease &&other) noexcept : marker(std::move(other.marker)) {
  other.marker.clear();
}

Store::Lease &Store::Lease::operator=(Lease &&other) noexcept {
  if (this != &other) {
    release();
    marker = std::move(other.marker);
    other.marker.clear();
  }
  return *this;
}

Store::Lease::~Lease() { release(); }

void Store::Lease::release() noexcept {
  if (marker.empty())
    return;
  std::error_code error;
  auto directory = marker.parent_path();
  fs::remove(marker, error);
  error.clear();
  fs::remove(directory, error);
  marker.clear();
}

Store::Lease Store::acquireLease(const std::string &key) {
  if (key.size() != 64 || !hexName(key) || !prepare())
    return {};
  StoreLock lock(directory);
  if (!lock)
    return {};
  auto leaseDirectory = directory / "leases" / key;
  std::error_code error;
  fs::create_directories(leaseDirectory, error);
  if (error)
    return {};
  static std::atomic<unsigned> counter{0};
  auto marker = leaseDirectory / (std::to_string(getpid()) + "-" +
                                  std::to_string(counter.fetch_add(1)));
  int descriptor = open(marker.c_str(), O_CREAT | O_EXCL | O_WRONLY, 0600);
  if (descriptor < 0)
    return {};
  auto owner = std::to_string(getpid()) + "\n";
  auto written = write(descriptor, owner.data(), owner.size());
  close(descriptor);
  if (written != static_cast<ssize_t>(owner.size())) {
    fs::remove(marker, error);
    return {};
  }
  return Lease(std::move(marker));
}

fs::path Store::entryPath(const std::string &key) const {
  return directory / "entries" / key.substr(0, 2) / key;
}

fs::path Store::blobPath(const std::string &blob) const {
  return directory / "blobs" / blob.substr(0, 2) / blob;
}

fs::path Store::scratch() const {
  static std::atomic<unsigned> counter{0};
  auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  return directory / "tmp" /
         (std::to_string(getpid()) + "-" + std::to_string(stamp) + "-" +
          std::to_string(counter++));
}

bool Store::prepare() {
  std::error_code error;
  fs::create_directories(directory / "entries", error);
  if (!error)
    fs::create_directories(directory / "blobs", error);
  if (!error)
    fs::create_directories(directory / "tmp", error);
  if (!error)
    fs::create_directories(directory / "leases", error);
  if (error)
    return false;
  auto marker = directory / "VERSION";
  if (!fs::exists(marker, error)) {
    std::ofstream out(marker, std::ios::trunc);
    out << "mettle-store 1\n";
  }
  return true;
}

bool Store::publish(const fs::path &path, const std::string &content) {
  if (!prepare())
    return false;
  StoreLock lock(directory);
  return lock && publishLocked(path, content);
}

bool Store::publishLocked(const fs::path &path, const std::string &content) {
  if (!prepare())
    return false;
  std::error_code error;
  fs::create_directories(path.parent_path(), error);
  if (error)
    return false;
  auto temporary = scratch();
  {
    std::ofstream out(temporary, std::ios::binary | std::ios::trunc);
    out << content;
    if (!out) {
      std::error_code ignored;
      fs::remove(temporary, ignored);
      return false;
    }
  }
  fs::rename(temporary, path, error);
  if (error)
    fs::remove(temporary, error);
  return !error;
}

bool Store::put(const std::string &key, const fs::path &file, bool executable) {
  if (key.size() < 2 || !prepare())
    return false;
  std::uint64_t size = 0;
  auto blob = hashFile(file, size);
  if (!blob)
    return false;
  StoreLock lock(directory);
  if (!lock)
    return false;
  std::error_code error;
  auto path = blobPath(*blob);
  if (!fs::exists(path, error)) {
    fs::create_directories(path.parent_path(), error);
    auto temporary = scratch();
    fs::copy_file(file, temporary, fs::copy_options::overwrite_existing, error);
    if (error)
      return false;
    fs::permissions(temporary,
                    fs::perms::owner_read | fs::perms::group_read |
                        fs::perms::others_read,
                    fs::perm_options::replace, error);
    fs::rename(temporary, path, error);
    if (error) {
      fs::remove(temporary, error);
      return false;
    }
  }
  return publishLocked(entryPath(key), "file " + *blob + " " +
                                           std::to_string(size) +
                                           (executable ? " x\n" : " -\n"));
}

bool Store::putMany(const std::vector<Artifact> &artifacts) {
  if (artifacts.empty())
    return true;
  if (!prepare())
    return false;

  struct Prepared {
    const Artifact *artifact;
    std::string blob;
    std::uint64_t size;
    fs::path temporary;
  };
  std::vector<Prepared> prepared;
  prepared.reserve(artifacts.size());
  auto discardTemporaries = [&] {
    for (const auto &item : prepared) {
      std::error_code ignored;
      fs::remove(item.temporary, ignored);
    }
  };

  for (const auto &artifact : artifacts) {
    if (artifact.key.size() < 2) {
      discardTemporaries();
      return false;
    }
    std::uint64_t size = 0;
    auto blob = hashFile(artifact.file, size);
    if (!blob) {
      discardTemporaries();
      return false;
    }
    auto temporary = scratch();
    std::error_code error;
    fs::copy_file(artifact.file, temporary,
                  fs::copy_options::overwrite_existing, error);
    if (error) {
      fs::remove(temporary, error);
      discardTemporaries();
      return false;
    }
    fs::permissions(temporary,
                    fs::perms::owner_read | fs::perms::group_read |
                        fs::perms::others_read,
                    fs::perm_options::replace, error);
    if (error) {
      fs::remove(temporary, error);
      discardTemporaries();
      return false;
    }
    prepared.push_back({&artifact, std::move(*blob), size,
                        std::move(temporary)});
  }

  StoreLock lock(directory);
  if (!lock) {
    discardTemporaries();
    return false;
  }
  for (const auto &item : prepared) {
    std::error_code error;
    auto blob = blobPath(item.blob);
    auto exists = fs::exists(blob, error);
    if (error) {
      discardTemporaries();
      return false;
    }
    if (exists) {
      fs::remove(item.temporary, error);
      if (error) {
        discardTemporaries();
        return false;
      }
    } else {
      fs::create_directories(blob.parent_path(), error);
      if (!error)
        fs::rename(item.temporary, blob, error);
      if (error) {
        discardTemporaries();
        return false;
      }
    }
    if (!publishLocked(entryPath(item.artifact->key),
                       "file " + item.blob + " " +
                           std::to_string(item.size) +
                           (item.artifact->executable ? " x\n" : " -\n"))) {
      discardTemporaries();
      return false;
    }
  }
  discardTemporaries();
  std::set<std::string> keep;
  for (const auto &artifact : artifacts)
    keep.insert(artifact.key);
  pruneLocked(keep);
  return true;
}

Store::Lookup Store::materialize(const std::string &key,
                                 const fs::path &destination) {
  if (key.size() < 2)
    return Lookup::Miss;
  auto path = entryPath(key);
  auto content = readText(path);
  if (!content)
    return Lookup::Miss;
  std::error_code error;
  auto entry = parseEntry(*content);
  if (!entry || entry->text) {
    fs::remove(path, error);
    return entry ? Lookup::Miss : Lookup::Corrupt;
  }
  auto blob = blobPath(entry->blob);
  if (!fs::exists(blob, error)) {
    fs::remove(path, error);
    return Lookup::Miss;
  }
  std::uint64_t size = 0;
  auto actual = hashFile(blob, size);
  if (!actual || *actual != entry->blob || size != entry->size) {
    fs::remove(blob, error);
    fs::remove(path, error);
    return Lookup::Corrupt;
  }
  auto temporary = destination;
  temporary += ".mettle-cache-" + std::to_string(getpid());
  fs::copy_file(blob, temporary, fs::copy_options::overwrite_existing, error);
  if (!error) {
    using fs::perms;
    auto mode = perms::owner_read | perms::owner_write | perms::group_read |
                perms::others_read;
    if (entry->executable)
      mode |= perms::owner_exec | perms::group_exec | perms::others_exec;
    fs::permissions(temporary, mode, fs::perm_options::replace, error);
  }
  if (!error)
    fs::rename(temporary, destination, error);
  if (error) {
    fs::remove(temporary, error);
    return Lookup::Miss;
  }
  touch(path);
  return Lookup::Hit;
}

std::optional<std::string> Store::text(const std::string &key) {
  if (key.size() < 2)
    return std::nullopt;
  auto path = entryPath(key);
  auto content = readText(path);
  if (!content)
    return std::nullopt;
  auto entry = parseEntry(*content);
  if (!entry || !entry->text) {
    std::error_code error;
    fs::remove(path, error);
    return std::nullopt;
  }
  touch(path);
  return entry->payload;
}

bool Store::putText(const std::string &key, const std::string &text) {
  return key.size() >= 2 && publish(entryPath(key), "text\n" + text);
}

std::vector<Store::Record> Store::records() const {
  std::vector<Record> found;
  std::error_code error;
  for (fs::recursive_directory_iterator it(directory / "entries", error), end;
       !error && it != end; it.increment(error)) {
    std::error_code vanished;
    if (!it->is_regular_file(vanished))
      continue;
    Record record;
    record.path = it->path();
    record.key = it->path().filename().string();
    record.size = sizeOf(it->path());
    record.used = fs::last_write_time(it->path(), vanished);
    if (vanished)
      continue;
    if (auto content = readText(it->path()))
      if (auto entry = parseEntry(*content))
        record.blob = entry->blob;
    found.push_back(std::move(record));
  }
  return found;
}

std::vector<std::string> Store::prune(const std::string &keep) {
  if (!prepare())
    return {};
  StoreLock lock(directory);
  if (!lock)
    return {};
  std::set<std::string> retained;
  if (!keep.empty())
    retained.insert(keep);
  return pruneLocked(retained);
}

std::vector<std::string>
Store::pruneLocked(const std::set<std::string> &keep) {
  std::vector<std::string> notes;
  // The caller's own output is already published, so its lease only protects
  // the entry from other builds' pruning, not from this budget.
  auto leased = liveLeaseKeys(directory);
  for (const auto &key : keep)
    leased.erase(key);
  std::error_code error;
  auto now = fs::file_time_type::clock::now();
  // Scratch files left by a crashed build.
  for (fs::directory_iterator it(directory / "tmp", error), end;
       !error && it != end; it.increment(error)) {
    // A concurrent build may remove its scratch file between listing and
    // stat; such an entry has no meaningful age.
    std::error_code stale;
    auto written = fs::last_write_time(it->path(), stale);
    if (!stale && now - written > std::chrono::hours(1))
      fs::remove(it->path(), stale);
  }
  error.clear();
  std::map<std::string, std::uint64_t> sizes;
  std::map<std::string, fs::path> blobPaths;
  for (fs::recursive_directory_iterator it(directory / "blobs", error), end;
       !error && it != end; it.increment(error))
    if (std::error_code vanished; it->is_regular_file(vanished) &&
                                  hexName(it->path().filename().string())) {
      sizes[it->path().filename().string()] = sizeOf(it->path());
      blobPaths[it->path().filename().string()] = it->path();
    }
  auto all = records();
  std::map<std::string, std::size_t> references;
  for (const auto &record : all)
    if (!record.blob.empty())
      ++references[record.blob];
  std::uint64_t total = 0;
  for (const auto &record : all)
    total += record.size;
  for (const auto &[blob, count] : references)
    if (auto size = sizes.find(blob); size != sizes.end())
      total += size->second;

  auto evict = [&](const Record &record, const std::string &reason) {
    std::error_code ignored;
    fs::remove(record.path, ignored);
    total -= std::min(total, record.size);
    notes.push_back("evicted " + record.key.substr(0, 12) + ": " + reason);
    if (!record.blob.empty() && --references[record.blob] == 0) {
      total -= std::min(total, sizes[record.blob]);
      fs::remove(blobPaths[record.blob], ignored);
      notes.push_back("removed blob " + record.blob.substr(0, 12) +
                      ": no entry references it");
    }
  };

  std::vector<Record> live;
  for (auto &record : all) {
    auto age =
        std::chrono::duration_cast<std::chrono::hours>(now - record.used);
    if (!leased.contains(record.key) && bounds.maxAgeDays &&
        age > std::chrono::hours(24 * static_cast<long>(bounds.maxAgeDays)))
      evict(record, "unused for more than " +
                        std::to_string(bounds.maxAgeDays) + " days");
    else
      live.push_back(std::move(record));
  }
  std::stable_sort(live.begin(), live.end(),
                   [&](const Record &a, const Record &b) {
                     if (keep.contains(a.key) != keep.contains(b.key))
                       return keep.contains(b.key);
                     return a.used < b.used;
                   });
  std::size_t next = 0;
  while (total > bounds.bytes && next < live.size()) {
    const auto &record = live[next++];
    if (!leased.contains(record.key))
      evict(record, "over the " + std::to_string(bounds.bytes) +
                        "-byte budget, least recently used");
  }
  // Blobs no entry references (an interrupted publication or removal).
  for (const auto &[blob, path] : blobPaths)
    if (!references.count(blob) || references[blob] == 0) {
      std::error_code ignored;
      if (fs::remove(path, ignored))
        notes.push_back("removed blob " + blob.substr(0, 12) +
                        ": no entry references it");
    }
  return notes;
}

StoreUsage Store::usage() const {
  StoreUsage result;
  std::error_code error;
  for (const auto &record : records()) {
    ++result.entries;
    result.bytes += record.size;
  }
  for (fs::recursive_directory_iterator it(directory / "blobs", error), end;
       !error && it != end; it.increment(error))
    if (std::error_code vanished; it->is_regular_file(vanished)) {
      ++result.blobs;
      result.bytes += sizeOf(it->path());
    }
  return result;
}

std::optional<StoreUsage> Store::clear(bool dryRun, std::string &error) {
  std::error_code code;
  if (!fs::exists(directory, code))
    return StoreUsage{};
  if (!fs::exists(directory / "VERSION", code)) {
    if (!fs::is_empty(directory, code)) {
      error = directory.generic_string() +
              " is not a mettle store (no VERSION file); refusing to delete";
      return std::nullopt;
    }
    return StoreUsage{};
  }
  auto removed = usage();
  if (dryRun)
    return removed;
  StoreLock lock(directory);
  if (!lock) {
    error = "cannot lock the cache store";
    return std::nullopt;
  }
  if (!liveLeaseKeys(directory).empty()) {
    error = "cache store has live build leases";
    return std::nullopt;
  }
  for (const char *name : {"entries", "blobs", "tmp", "leases"})
    fs::remove_all(directory / name, code);
  fs::remove(directory / "VERSION", code);
  fs::remove(directory / "store.lock", code);
  lock.release();
  fs::remove(directory, code);
  return removed;
}
} // namespace mettle::packages
