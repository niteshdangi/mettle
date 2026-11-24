#include "packages/store.h"
#include "packages/sha256.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

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

bool hexName(const std::string &name) {
  return name.size() >= 2 && std::all_of(name.begin(), name.end(), [](char c) {
           return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
         });
}

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
      entry.blob.size() != 64 || !hexName(entry.blob) ||
      (mode != "x" && mode != "-"))
    return std::nullopt;
  entry.executable = mode == "x";
  return entry;
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

struct Store::Accounting {
  struct Blob {
    std::uint64_t size = 0;
    std::size_t references = 0;
  };
  struct Project {
    fs::path source;
    fs::file_time_type used;
    std::set<std::string> keys;
  };
  std::map<std::string, Record> entries;
  std::map<std::string, Blob> blobs;
  std::map<std::string, Project> projects;
  std::map<fs::path, fs::file_time_type> directories;
  std::map<std::string, std::size_t> claims;
  std::set<std::string> released;
  std::set<std::pair<fs::file_time_type, std::string>> oldest;
  using Ages = std::set<std::pair<fs::file_time_type, std::string>>;
  std::array<Ages, 256> ages;
  std::array<std::uint64_t, 256> entryCounts{}, blobCounts{};
  std::array<fs::file_time_type, 256> firstUse{};
  std::array<bool, 256> entryLoaded{}, blobLoaded{}, entryDirty{}, blobDirty{};
  std::uint64_t total = 0, offset = 0;
  dev_t device = 0;
  ino_t inode = 0;
  fs::file_time_type modified;
  bool loaded = false;
  bool reading = false;
  bool healthy = true;

  static unsigned shard(const std::string &key) {
    return static_cast<unsigned>(checksum(key) & 255);
  }
  static fs::path shardPath(const Store &store, bool blob, unsigned bucket) {
    static constexpr char hex[] = "0123456789abcdef";
    std::string name = blob ? "blobs-" : "entries-";
    name += hex[bucket >> 4];
    name += hex[bucket & 15];
    return store.directory / "accounting" / name;
  }

  static void number(std::string &out, std::uint64_t value) {
    for (unsigned shift = 0; shift < 64; shift += 8)
      out.push_back(static_cast<char>(value >> shift));
  }
  static void string(std::string &out, const std::string &value) {
    number(out, value.size());
    out += value;
  }
  struct Reader {
    std::string_view bytes;
    bool valid = true;
    std::uint64_t number() {
      if (bytes.size() < 8) {
        valid = false;
        return 0;
      }
      std::uint64_t value = 0;
      for (unsigned shift = 0; shift < 64; shift += 8)
        value |= static_cast<std::uint64_t>(
                     static_cast<unsigned char>(bytes[shift / 8]))
                 << shift;
      bytes.remove_prefix(8);
      return value;
    }
    std::string string() {
      auto length = number();
      if (!valid || length > bytes.size()) {
        valid = false;
        return {};
      }
      std::string value(bytes.substr(0, length));
      bytes.remove_prefix(length);
      return value;
    }
    fs::file_time_type time() {
      return fs::file_time_type(
          fs::file_time_type::duration(static_cast<std::int64_t>(number())));
    }
  };
  static std::uint64_t checksum(std::string_view bytes) {
    std::uint64_t value = 14695981039346656037ull;
    for (unsigned char byte : bytes)
      value = (value ^ byte) * 1099511628211ull;
    return value;
  }
  static void frame(std::string &out, const std::string &event) {
    number(out, event.size());
    out += event;
    number(out, checksum(event));
  }
  static std::optional<std::string_view> contents(const std::string &file) {
    Reader in{file};
    auto size = in.number();
    if (!in.valid || in.bytes.size() < 8 || size != in.bytes.size() - 8)
      return std::nullopt;
    auto payload = in.bytes.substr(0, size);
    in.bytes.remove_prefix(size);
    if (in.number() != checksum(payload))
      return std::nullopt;
    return payload;
  }
  static bool save(Store &store, const fs::path &path,
                   const std::string &content) {
    if (content.empty()) {
      std::error_code error;
      fs::remove(path, error);
      return !error;
    }
    std::string file;
    frame(file, content);
    return store.publishLocked(path, file);
  }
  void erase(const std::string &key) {
    auto found = entries.find(key);
    if (found == entries.end())
      return;
    auto bucket = shard(key);
    auto record = std::move(found->second);
    if (!reading) {
      released.erase(key);
      total -= record.size;
      --entryCounts[bucket];
      entryDirty[bucket] = true;
    }
    oldest.erase({record.used, key});
    ages[bucket].erase({record.used, key});
    if (!reading && !record.blob.empty()) {
      auto blobBucket = shard(record.blob);
      blobDirty[blobBucket] = true;
      auto blob = blobs.find(record.blob);
      if (blob != blobs.end() && --blob->second.references == 0) {
        total -= blob->second.size;
        blobs.erase(blob);
        --blobCounts[blobBucket];
      }
    }
    entries.erase(found);
    if (!ages[bucket].empty())
      firstUse[bucket] = ages[bucket].begin()->first;
  }
  void insert(Record record, std::uint64_t blobSize) {
    auto bucket = shard(record.key);
    bool unclaimed = released.contains(record.key);
    erase(record.key);
    if (unclaimed)
      released.insert(record.key);
    oldest.emplace(record.used, record.key);
    ages[bucket].emplace(record.used, record.key);
    firstUse[bucket] = ages[bucket].begin()->first;
    if (!reading) {
      total += record.size;
      ++entryCounts[bucket];
      entryDirty[bucket] = true;
    }
    if (!reading && !record.blob.empty()) {
      auto blobBucket = shard(record.blob);
      blobDirty[blobBucket] = true;
      if (!blobs.contains(record.blob))
        ++blobCounts[blobBucket];
      auto &blob = blobs[record.blob];
      total -= blob.size;
      blob.size = blobSize;
      total += blob.size;
      ++blob.references;
    }
    entries.emplace(record.key, std::move(record));
  }
  void project(const std::string &id, std::optional<Project> next) {
    auto old = projects.find(id);
    if (old != projects.end()) {
      for (const auto &key : old->second.keys) {
        auto found = claims.find(key);
        if (found != claims.end() && --found->second == 0) {
          claims.erase(found);
          released.insert(key);
        }
      }
      projects.erase(old);
    }
    if (next) {
      for (const auto &key : next->keys) {
        ++claims[key];
        released.erase(key);
      }
      projects.emplace(id, std::move(*next));
    }
  }
  std::string entryEvent(const Record &record) const {
    std::string event(1, 'E');
    string(event, record.key);
    string(event, record.blob);
    number(event, record.size);
    number(event, record.used.time_since_epoch().count());
    return event;
  }
  static std::string projectEvent(const std::string &id,
                                  const Project &project) {
    std::string event(1, 'P');
    string(event, id);
    string(event, project.source.string());
    number(event, project.used.time_since_epoch().count());
    number(event, project.keys.size());
    for (const auto &key : project.keys)
      string(event, key);
    return event;
  }
  bool apply(std::string_view bytes) {
    if (bytes.empty())
      return false;
    auto kind = bytes.front();
    Reader in{bytes.substr(1)};
    auto key = in.string();
    if (kind == 'E') {
      Record record;
      record.key = key;
      record.blob = in.string();
      record.size = in.number();
      record.used = in.time();
      if (!in.valid || !in.bytes.empty())
        return false;
      insert(std::move(record), 0);
    } else if (kind == 'B') {
      auto size = in.number();
      auto references = in.number();
      if (!in.valid || !in.bytes.empty())
        return false;
      blobs[key] = Blob{size, static_cast<std::size_t>(references)};
    } else if (kind == 'S') {
      if (key != "mettle-accounting-2")
        return false;
      total = in.number();
      for (unsigned bucket = 0; bucket < 256; ++bucket) {
        entryCounts[bucket] = in.number();
        blobCounts[bucket] = in.number();
        firstUse[bucket] = in.time();
      }
      if (!in.valid || !in.bytes.empty())
        return false;
    } else if (kind == 'P') {
      Project next;
      next.source = in.string();
      next.used = in.time();
      auto count = in.number();
      if (!in.valid || count > in.bytes.size() / 8)
        return false;
      for (std::uint64_t i = 0; i < count && in.valid; ++i)
        next.keys.insert(in.string());
      if (!in.valid || !in.bytes.empty())
        return false;
      project(key, std::move(next));
    } else if (kind == 'R') {
      if (!in.valid || !in.bytes.empty())
        return false;
      released.insert(key);
    } else if (kind == 'V') {
      auto used = in.time();
      if (!in.valid || !in.bytes.empty())
        return false;
      directories[key] = used;
    } else {
      return false;
    }
    return true;
  }
  bool replay(std::string_view bytes) {
    while (!bytes.empty()) {
      Reader in{bytes};
      auto size = in.number();
      if (!in.valid || size > in.bytes.size() || in.bytes.size() - size < 8)
        return false;
      auto event = in.bytes.substr(0, size);
      in.bytes.remove_prefix(size);
      if (in.number() != checksum(event) || !apply(event))
        return false;
      bytes = in.bytes;
    }
    return true;
  }
  void rememberIdentity(const Store &store) {
    struct stat status{};
    auto path = store.directory / "accounting" / "state";
    if (stat(path.c_str(), &status) == 0) {
      device = status.st_dev;
      inode = status.st_ino;
      offset = status.st_size;
      std::error_code error;
      modified = fs::last_write_time(path, error);
      loaded = !error;
    } else {
      loaded = false;
    }
  }
  static fs::file_time_type directoryTime(const fs::path &path) {
    std::error_code error;
    auto used = fs::last_write_time(path, error);
    return error ? fs::file_time_type::min() : used;
  }
  bool directoriesMatch(const Store &store) const {
    if (directories.empty())
      return false;
    for (const auto &[path, used] : directories)
      if (directoryTime(store.directory / path) != used)
        return false;
    return true;
  }
  void rememberDirectories(const Store &store) {
    directories.clear();
    for (const std::string parent : {"entries", "blobs", "roots"}) {
      auto path = store.directory / parent;
      directories[parent] = directoryTime(path);
      if (parent == "roots")
        continue;
      std::error_code error;
      for (fs::directory_iterator it(path, error), end; !error && it != end;
           it.increment(error))
        directories[fs::path(parent) / it->path().filename()] =
            directoryTime(it->path());
    }
  }
  bool snapshot(Store &store) {
    std::string content;
    for (unsigned bucket = 0; bucket < 256; ++bucket) {
      if (entryDirty[bucket]) {
        content.clear();
        for (const auto &[used, key] : ages[bucket])
          frame(content, entryEvent(entries.at(key)));
        if (!save(store, shardPath(store, false, bucket), content))
          return false;
        entryDirty[bucket] = false;
      }
      if (blobDirty[bucket]) {
        content.clear();
        for (const auto &[key, blob] : blobs) {
          if (shard(key) != bucket)
            continue;
          std::string event(1, 'B');
          string(event, key);
          number(event, blob.size);
          number(event, blob.references);
          frame(content, event);
        }
        if (!save(store, shardPath(store, true, bucket), content))
          return false;
        blobDirty[bucket] = false;
      }
    }
    content.clear();
    std::string summary(1, 'S');
    string(summary, "mettle-accounting-2");
    number(summary, total);
    for (unsigned bucket = 0; bucket < 256; ++bucket) {
      number(summary, entryCounts[bucket]);
      number(summary, blobCounts[bucket]);
      number(summary, firstUse[bucket].time_since_epoch().count());
    }
    frame(content, summary);
    for (const auto &[id, root] : projects)
      frame(content, projectEvent(id, root));
    for (const auto &key : released) {
      std::string event(1, 'R');
      string(event, key);
      frame(content, event);
    }
    rememberDirectories(store);
    for (const auto &[path, used] : directories) {
      std::string event(1, 'V');
      string(event, path.string());
      number(event, used.time_since_epoch().count());
      frame(content, event);
    }
    if (!save(store, store.directory / "accounting" / "state", content))
      return false;
    rememberIdentity(store);
    return loaded;
  }
  bool recover(Store &store) {
    auto previouslyClaimed = claims;
    auto previouslyReleased = released;
    *this = Accounting{};
    entryLoaded.fill(true);
    blobLoaded.fill(true);
    std::error_code error;
    fs::remove_all(store.directory / "accounting", error);
    if (error) {
      healthy = false;
      return false;
    }
    for (auto &record : store.records()) {
      auto size = record.blob.empty() ? 0 : sizeOf(store.blobPath(record.blob));
      insert(std::move(record), size);
    }
    for (fs::recursive_directory_iterator it(store.directory / "blobs", error),
         end;
         !error && it != end; it.increment(error)) {
      std::error_code ignored;
      if (it->is_regular_file(ignored) &&
          !blobs.contains(it->path().filename().string()))
        fs::remove(it->path(), ignored);
    }
    error.clear();
    for (fs::directory_iterator it(store.directory / "roots", error), end;
         !error && it != end; it.increment(error)) {
      auto content = readText(it->path());
      if (!content)
        continue;
      std::istringstream lines(*content);
      std::string line;
      if (!std::getline(lines, line))
        continue;
      Project root;
      root.source = line;
      while (std::getline(lines, line))
        if (!line.empty())
          root.keys.insert(line);
      std::error_code ignored;
      root.used = fs::last_write_time(it->path(), ignored);
      project(it->path().filename().string(), std::move(root));
    }
    released.insert(previouslyReleased.begin(), previouslyReleased.end());
    for (const auto &[key, count] : previouslyClaimed)
      if (!claims.contains(key))
        released.insert(key);
    healthy = snapshot(store);
    return healthy;
  }
  bool begin(Store &store) {
    const auto path = store.directory / "accounting" / "state";
    struct stat status{};
    const bool available = stat(path.c_str(), &status) == 0;
    std::error_code error;
    auto written = fs::last_write_time(path, error);
    bool good = available;
    if (!loaded || !good || device != status.st_dev || inode != status.st_ino ||
        static_cast<std::uint64_t>(status.st_size) != offset ||
        modified != written) {
      *this = Accounting{};
      auto content = readText(path);
      auto payload = content ? contents(*content) : std::nullopt;
      reading = true;
      good = payload && !payload->empty() && replay(*payload);
      reading = false;
    }
    if (!good || fs::exists(store.directory / "accounting.dirty", error) ||
        !directoriesMatch(store)) {
      if (!store.publishLocked(store.directory / "accounting.dirty", "") ||
          !recover(store))
        return false;
    } else {
      rememberIdentity(store);
    }
    return store.publishLocked(store.directory / "accounting.dirty", "");
  }
  bool finish(Store &store) {
    if (!healthy || !snapshot(store)) {
      loaded = false;
      return false;
    }
    std::error_code error;
    fs::remove(store.directory / "accounting.dirty", error);
    if (error) {
      loaded = false;
      return false;
    }
    return true;
  }
  void setProject(const std::string &id, std::optional<Project> root) {
    project(id, std::move(root));
  }
  bool loadShard(Store &store, bool blob, unsigned bucket) {
    if (!healthy)
      return false;
    auto &ready = blob ? blobLoaded : entryLoaded;
    if (ready[bucket])
      return true;
    auto content = readText(shardPath(store, blob, bucket));
    const auto count = blob ? blobCounts[bucket] : entryCounts[bucket];
    if (!content && !count) {
      ready[bucket] = true;
      return true;
    }
    auto payload = content ? contents(*content) : std::nullopt;
    reading = true;
    bool good = payload && replay(*payload);
    reading = false;
    if (good) {
      std::uint64_t actual = 0;
      if (blob) {
        for (const auto &[key, record] : blobs)
          actual += shard(key) == bucket;
      } else {
        actual = ages[bucket].size();
      }
      good = actual == count;
    }
    if (!good)
      return recover(store);
    ready[bucket] = true;
    return true;
  }
  bool ensureKey(Store &store, const std::string &key) {
    if (!loadShard(store, false, shard(key)))
      return false;
    auto found = entries.find(key);
    if (found != entries.end() && !found->second.blob.empty()) {
      auto blob = found->second.blob;
      return loadShard(store, true, shard(blob));
    }
    return true;
  }
  bool preparePrune(Store &store, bool budget, fs::file_time_type cutoff) {
    bool expires = false;
    for (unsigned bucket = 0; bucket < 256; ++bucket)
      if (entryCounts[bucket] && (budget || firstUse[bucket] < cutoff)) {
        expires = true;
        if (!loadShard(store, false, bucket))
          return false;
      }
    if (expires)
      for (unsigned bucket = 0; bucket < 256; ++bucket)
        if (blobCounts[bucket] && !loadShard(store, true, bucket))
          return false;
    return true;
  }
  void remove(Store &store, const std::string &key) {
    if (!ensureKey(store, key))
      return;
    auto found = entries.find(key);
    auto blob = found == entries.end() ? std::string() : found->second.blob;
    erase(key);
    released.erase(key);
    if (!blob.empty() && !blobs.contains(blob)) {
      std::error_code ignored;
      fs::remove(store.blobPath(blob), ignored);
    }
  }
  void refresh(Store &store, const std::string &key) {
    if (key.size() < 2)
      return;
    if (!ensureKey(store, key))
      return;
    auto path = store.entryPath(key);
    auto content = readText(path);
    std::error_code error;
    if (!content) {
      if (!fs::exists(path, error) && !error)
        remove(store, key);
      return;
    }
    Record record;
    record.key = key;
    record.size = sizeOf(path);
    record.used = fs::last_write_time(path, error);
    if (error) {
      remove(store, key);
      return;
    }
    if (auto entry = parseEntry(*content))
      record.blob = entry->blob;
    if (!record.blob.empty() && !loadShard(store, true, shard(record.blob)))
      return;
    auto blobSize =
        record.blob.empty() ? 0 : sizeOf(store.blobPath(record.blob));
    auto old = entries.find(key);
    auto previousBlob = old == entries.end() ? std::string() : old->second.blob;
    insert(std::move(record), blobSize);
    if (!previousBlob.empty() && !blobs.contains(previousBlob))
      fs::remove(store.blobPath(previousBlob), error);
  }
};

Store::Accounting &Store::accountingLocked() {
  if (!accounting)
    accounting = std::make_shared<Accounting>();
  return *accounting;
}

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

bool Store::publish(const std::string &key, const std::string &content) {
  if (!prepare())
    return false;
  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock)
    return false;
  auto &index = accountingLocked();
  if (!index.begin(*this) || !publishLocked(entryPath(key), content))
    return false;
  index.refresh(*this, key);
  return index.finish(*this);
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
    out.close();
    if (!out) {
      std::error_code ignored;
      fs::remove(temporary, ignored);
      return false;
    }
  }
  fs::rename(temporary, path, error);
  if (error) {
    std::error_code ignored;
    fs::remove(temporary, ignored);
    return false;
  }
  return true;
}

bool Store::put(const std::string &key, const fs::path &file, bool executable) {
  note(key);
  if (key.size() < 2 || !prepare())
    return false;
  auto temporary = scratch();
  std::error_code error;
  fs::copy_file(file, temporary, fs::copy_options::overwrite_existing, error);
  if (error) {
    fs::remove(temporary, error);
    return false;
  }
  struct Cleanup {
    fs::path path;
    ~Cleanup() {
      std::error_code ignored;
      fs::remove(path, ignored);
    }
  } cleanup{temporary};
  std::uint64_t size = 0;
  auto blob = hashFile(temporary, size);
  if (!blob)
    return false;
  fs::permissions(temporary,
                  fs::perms::owner_read | fs::perms::group_read |
                      fs::perms::others_read,
                  fs::perm_options::replace, error);
  if (error)
    return false;
  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock)
    return false;
  auto &index = accountingLocked();
  if (!index.begin(*this))
    return false;
  auto path = blobPath(*blob);
  fs::create_directories(path.parent_path(), error);
  if (!error)
    fs::rename(temporary, path, error);
  if (error)
    return false;
  if (!publishLocked(entryPath(key), "file " + *blob + " " +
                                         std::to_string(size) +
                                         (executable ? " x\n" : " -\n")))
    return false;
  index.refresh(*this, key);
  return index.finish(*this);
}

bool Store::putData(const std::string &key, std::string_view bytes) {
  note(key);
  if (key.size() < 2 ||
      bytes.size() > static_cast<std::uint64_t>(
                         std::numeric_limits<std::streamsize>::max()) ||
      !prepare())
    return false;
  struct Temporary {
    fs::path path;
    ~Temporary() {
      std::error_code error;
      fs::remove(path, error);
    }
  } temporary{scratch()};
  std::ofstream out(temporary.path, std::ios::binary | std::ios::trunc);
  out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  out.close();
  return out && put(key, temporary.path, false);
}

void Store::useShipped(fs::path root) {
  shipped = std::make_unique<Store>(std::move(root), StoreLimits{0, 0});
  shipped->readOnly = true;
}

Store::Data Store::data(const std::string &key, std::uint64_t maximumBytes) {
  auto result = localData(key, maximumBytes);
  return result.status == Lookup::Miss && shipped
             ? shipped->localData(key, maximumBytes)
             : result;
}

Store::Mapping::~Mapping() {
  if (length)
    munmap(const_cast<void *>(address), length);
}

Store::Mapped Store::mapped(const std::string &key, std::uint64_t maximumBytes,
                            const Verifier &verify) {
  auto result = localMapped(key, maximumBytes, verify);
  return result.status == Lookup::Miss && shipped
             ? shipped->localMapped(key, maximumBytes, verify)
             : result;
}

Store::Data Store::shippedData(const std::string &key,
                               std::uint64_t maximumBytes) {
  return shipped ? shipped->localData(key, maximumBytes) : Data{};
}

Store::Mapped Store::shippedMapped(const std::string &key,
                                   std::uint64_t maximumBytes,
                                   const Verifier &verify) {
  return shipped ? shipped->localMapped(key, maximumBytes, verify) : Mapped{};
}

Store::Data Store::localData(const std::string &key,
                             std::uint64_t maximumBytes) {
  auto found = localMapped(key, maximumBytes, {});
  if (!found.mapping)
    return {found.status, {}};
  return {Lookup::Hit, std::string(found.mapping->bytes())};
}

void Store::invalidate(const std::string &key, const std::string &content,
                       bool blob) {
  if (readOnly)
    return;
  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock || readText(entryPath(key)) != content)
    return;
  auto &index = accountingLocked();
  if (!index.begin(*this))
    return;
  if (!index.ensureKey(*this, key))
    return;
  std::error_code error;
  if (blob)
    if (auto entry = parseEntry(content); entry && !entry->blob.empty()) {
      fs::remove(blobPath(entry->blob), error);
      auto found = index.blobs.find(entry->blob);
      if (found != index.blobs.end()) {
        index.total -= found->second.size;
        found->second.size = sizeOf(blobPath(entry->blob));
        index.total += found->second.size;
        index.blobDirty[Accounting::shard(entry->blob)] = true;
      }
    }
  if (fs::remove(entryPath(key), error) || !error)
    index.remove(*this, key);
  index.finish(*this);
}

Store::Mapped Store::localMapped(const std::string &key,
                                 std::uint64_t maximumBytes,
                                 const Verifier &verify) {
  note(key);
  if (key.size() < 2)
    return {};
  auto path = entryPath(key);
  auto content = readText(path);
  if (!content)
    return {};
  auto entry = parseEntry(*content);
  std::error_code error;
  if (!entry || entry->text) {
    invalidate(key, *content);
    return {entry ? Lookup::Miss : Lookup::Corrupt, {}};
  }
  if (entry->size > maximumBytes || entry->size > std::string().max_size()) {
    invalidate(key, *content);
    return {Lookup::Corrupt, {}};
  }
  auto blob = blobPath(entry->blob);
  auto size = fs::file_size(blob, error);
  if (error) {
    invalidate(key, *content);
    return {};
  }
  if (size != entry->size) {
    invalidate(key, *content, true);
    return {Lookup::Corrupt, {}};
  }
  auto corrupt = [&] {
    invalidate(key, *content, true);
    return Mapped{Lookup::Corrupt, {}};
  };
  int descriptor = open(blob.c_str(), O_RDONLY);
  if (descriptor < 0)
    return corrupt();
  const void *address = size ? mmap(nullptr, static_cast<std::size_t>(size),
                                    PROT_READ, MAP_PRIVATE, descriptor, 0)
                             : nullptr;
  close(descriptor);
  if (size && address == MAP_FAILED)
    return corrupt();
  auto mapping =
      std::make_shared<const Mapping>(address, static_cast<std::size_t>(size));
  if (verify) {
    if (!verify(mapping))
      return corrupt();
  } else {
    packages::Sha256 hash;
    hash.update(mapping->bytes());
    if (hash.finish() != entry->blob)
      return corrupt();
  }
  if (!readOnly)
    touch(path);
  return {Lookup::Hit, std::move(mapping)};
}

bool Store::putMany(const std::vector<Artifact> &artifacts) {
  for (const auto &artifact : artifacts)
    note(artifact.key);
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
    auto temporary = scratch();
    std::error_code error;
    fs::copy_file(artifact.file, temporary,
                  fs::copy_options::overwrite_existing, error);
    if (error) {
      fs::remove(temporary, error);
      discardTemporaries();
      return false;
    }
    std::uint64_t size = 0;
    auto blob = hashFile(temporary, size);
    if (!blob) {
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
    prepared.push_back(
        {&artifact, std::move(*blob), size, std::move(temporary)});
  }

  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock) {
    discardTemporaries();
    return false;
  }
  auto &index = accountingLocked();
  if (!index.begin(*this)) {
    discardTemporaries();
    return false;
  }
  for (const auto &item : prepared) {
    std::error_code error;
    auto blob = blobPath(item.blob);
    fs::create_directories(blob.parent_path(), error);
    if (!error)
      fs::rename(item.temporary, blob, error);
    if (error) {
      discardTemporaries();
      return false;
    }
    if (!publishLocked(entryPath(item.artifact->key),
                       "file " + item.blob + " " + std::to_string(item.size) +
                           (item.artifact->executable ? " x\n" : " -\n"))) {
      discardTemporaries();
      return false;
    }
    index.refresh(*this, item.artifact->key);
  }
  discardTemporaries();
  return index.finish(*this);
}

Store::Lookup Store::materialize(const std::string &key,
                                 const fs::path &destination) {
  auto result = localMaterialize(key, destination);
  return result == Lookup::Miss && shipped
             ? shipped->localMaterialize(key, destination)
             : result;
}

Store::Lookup Store::localMaterialize(const std::string &key,
                                      const fs::path &destination) {
  note(key);
  if (key.size() < 2)
    return Lookup::Miss;
  auto path = entryPath(key);
  auto content = readText(path);
  if (!content)
    return Lookup::Miss;
  std::error_code error;
  auto entry = parseEntry(*content);
  if (!entry || entry->text) {
    invalidate(key, *content);
    return entry ? Lookup::Miss : Lookup::Corrupt;
  }
  auto blob = blobPath(entry->blob);
  if (!fs::exists(blob, error)) {
    invalidate(key, *content);
    return Lookup::Miss;
  }
  std::string temporary = destination.string() + ".mettle-cache-XXXXXX";
  int descriptor = mkstemp(temporary.data());
  if (descriptor < 0)
    return Lookup::Miss;
  std::ifstream source(blob, std::ios::binary);
  char buffer[1 << 16];
  Sha256 hash;
  std::uint64_t size = 0;
  bool copied = static_cast<bool>(source);
  while (copied && source.read(buffer, sizeof buffer).gcount() != 0) {
    auto count = source.gcount();
    hash.update({buffer, static_cast<std::size_t>(count)});
    size += static_cast<std::uint64_t>(count);
    std::streamsize written = 0;
    while (written < count) {
      auto result = ::write(descriptor, buffer + written, count - written);
      if (result < 0 && errno == EINTR)
        continue;
      if (result <= 0) {
        copied = false;
        break;
      }
      written += result;
    }
  }
  copied = copied && source.eof();
  const bool corrupt =
      copied && (size != entry->size || hash.finish() != entry->blob);
  mode_t mode = entry->executable ? 0755 : 0644;
  if (fchmod(descriptor, mode) != 0)
    copied = false;
  if (close(descriptor) != 0)
    copied = false;
  if (copied && !corrupt)
    fs::rename(temporary, destination, error);
  if (!copied || corrupt || error) {
    fs::remove(temporary, error);
    if (corrupt)
      invalidate(key, *content, true);
    return corrupt ? Lookup::Corrupt : Lookup::Miss;
  }
  if (!readOnly)
    touch(path);
  return Lookup::Hit;
}

std::optional<std::string> Store::text(const std::string &key) {
  auto result = localText(key);
  return !result && shipped ? shipped->localText(key) : result;
}

std::optional<std::string> Store::localText(const std::string &key) {
  note(key);
  if (key.size() < 2)
    return std::nullopt;
  auto path = entryPath(key);
  auto content = readText(path);
  if (!content)
    return std::nullopt;
  auto entry = parseEntry(*content);
  if (!entry || !entry->text) {
    invalidate(key, *content);
    return std::nullopt;
  }
  if (!readOnly)
    touch(path);
  return entry->payload;
}

bool Store::putText(const std::string &key, const std::string &text) {
  note(key);
  return key.size() >= 2 && publish(key, "text\n" + text);
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

void Store::note(const std::string &key) const {
  std::lock_guard guard(touched->lock);
  touched->keys.insert(key);
}

std::vector<std::string> Store::commitProject(const std::string &project,
                                              const fs::path &path,
                                              const std::string &keep) {
  if (project.empty() || !prepare())
    return {};
  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock)
    return {};
  auto &index = accountingLocked();
  if (!index.begin(*this))
    return {};
  std::set<std::string> retained;
  if (!keep.empty())
    retained.insert(keep);
  Sha256 name;
  name.update(project);
  const auto rootsDirectory = directory / "roots";
  std::error_code error;
  fs::create_directories(rootsDirectory, error);
  const auto id = name.finish();
  const auto mine = rootsDirectory / id;
  std::set<std::string> current;
  {
    std::lock_guard guard(touched->lock);
    current = touched->keys;
  }
  std::string content = path.string() + "\n";
  for (const auto &key : current)
    content += key + "\n";
  if (!publishLocked(mine, content))
    return {};
  const auto now = fs::file_time_type::clock::now();
  index.setProject(id, Accounting::Project{path, now, std::move(current)});
  std::map<fs::path, std::size_t> siblings;
  for (const auto &[otherId, other] : index.projects)
    if (otherId != id && other.source.has_filename())
      ++siblings[other.source.parent_path()];
  std::map<fs::path, std::optional<std::map<fs::path, bool>>> listings;
  auto exists = [&](const fs::path &source) {
    std::error_code error;
    auto parent = source.parent_path();
    auto shared = siblings.find(parent);
    if (!source.has_filename() || !source.has_parent_path() ||
        shared == siblings.end() || shared->second < 2)
      return fs::exists(source, error);
    auto [listing, fresh] = listings.try_emplace(parent);
    if (fresh) {
      std::map<fs::path, bool> names;
      fs::directory_iterator it(parent, error), end;
      for (; !error && it != end; it.increment(error)) {
        std::error_code kind;
        names[it->path().filename()] = it->is_symlink(kind) || kind;
      }
      if (!error)
        listing->second = std::move(names);
      else if (error == std::errc::no_such_file_or_directory ||
               error == std::errc::not_a_directory)
        listing->second.emplace();
    }
    if (!listing->second)
      return fs::exists(source, error);
    auto found = listing->second->find(source.filename());
    if (found == listing->second->end())
      return false;
    return !found->second || fs::exists(source, error);
  };
  std::vector<std::string> dead;
  for (const auto &[otherId, other] : index.projects) {
    if (otherId == id)
      continue;
    if (!exists(other.source) ||
        (bounds.maxAgeDays &&
         now - other.used >
             std::chrono::hours(24 * static_cast<long>(bounds.maxAgeDays))))
      dead.push_back(otherId);
  }
  for (const auto &otherId : dead) {
    std::error_code removed;
    if (fs::remove(rootsDirectory / otherId, removed) || !removed)
      index.setProject(otherId, std::nullopt);
  }
  auto notes = pruneLocked(retained, liveLeaseKeys(directory));
  index.finish(*this);
  return notes;
}

std::vector<std::string> Store::prune(const std::string &keep) {
  if (!prepare())
    return {};
  std::lock_guard accountingGuard(touched->accountingLock);
  StoreLock lock(directory);
  if (!lock)
    return {};
  auto &index = accountingLocked();
  if (!index.begin(*this))
    return {};
  std::set<std::string> retained;
  if (!keep.empty())
    retained.insert(keep);
  auto notes = pruneLocked(retained, liveLeaseKeys(directory));
  index.finish(*this);
  return notes;
}

std::vector<std::string> Store::pruneLocked(const std::set<std::string> &keep,
                                            std::set<std::string> leased) {
  std::vector<std::string> notes;
  auto &index = accountingLocked();
  for (const auto &key : keep)
    leased.erase(key);
  std::set<std::string> current;
  {
    std::lock_guard guard(touched->lock);
    current = touched->keys;
  }
  for (const auto &key : current)
    index.refresh(*this, key);
  std::error_code error;
  auto now = fs::file_time_type::clock::now();
  for (fs::directory_iterator it(directory / "tmp", error), end;
       !error && it != end; it.increment(error)) {
    std::error_code stale;
    auto written = fs::last_write_time(it->path(), stale);
    if (!stale && now - written > std::chrono::hours(1))
      fs::remove(it->path(), stale);
  }
  auto evict = [&](const std::string &key, const std::string &reason) {
    if (!index.ensureKey(*this, key))
      return;
    auto found = index.entries.find(key);
    if (found == index.entries.end()) {
      index.remove(*this, key);
      return;
    }
    auto blob = found->second.blob;
    std::error_code ignored;
    if (!fs::remove(entryPath(key), ignored) && ignored)
      return;
    index.remove(*this, key);
    notes.push_back("evicted " + key.substr(0, 12) + ": " + reason);
    if (!blob.empty() && !index.blobs.contains(blob))
      notes.push_back("removed blob " + blob.substr(0, 12) +
                      ": no entry references it");
  };
  auto released = index.released;
  for (const auto &key : released)
    if (!index.claims.contains(key) && !leased.contains(key))
      evict(key, "no live project build uses it");
  auto expiration =
      std::chrono::hours(24 * static_cast<long>(bounds.maxAgeDays));
  if (!index.preparePrune(*this, bounds.bytes && index.total > bounds.bytes,
                          bounds.maxAgeDays ? now - expiration
                                            : fs::file_time_type::min()))
    return notes;
  if (bounds.maxAgeDays) {
    for (auto it = index.oldest.begin(); it != index.oldest.end();) {
      auto [used, key] = *it++;
      if (std::chrono::duration_cast<std::chrono::hours>(now - used) <=
          expiration)
        break;
      if (leased.contains(key))
        continue;
      std::error_code vanished;
      auto actual = fs::last_write_time(entryPath(key), vanished);
      if (!vanished && actual != used) {
        index.refresh(*this, key);
        it = index.oldest.upper_bound({used, key});
        continue;
      }
      evict(key, "unused for more than " + std::to_string(bounds.maxAgeDays) +
                     " days");
    }
  }
  if (bounds.bytes && index.total > bounds.bytes) {
    for (bool retained : {false, true}) {
      for (auto it = index.oldest.begin(); bounds.bytes &&
                                           index.total > bounds.bytes &&
                                           it != index.oldest.end();) {
        auto [used, key] = *it++;
        if (keep.contains(key) != retained || leased.contains(key))
          continue;
        std::error_code vanished;
        auto actual = fs::last_write_time(entryPath(key), vanished);
        if (!vanished && actual != used) {
          index.refresh(*this, key);
          auto refreshed = index.entries.find(key);
          if (refreshed == index.entries.end() ||
              refreshed->second.used != used) {
            it = index.oldest.begin();
            continue;
          }
        }
        evict(key, "over the " + std::to_string(bounds.bytes) +
                       "-byte budget, least recently used");
      }
    }
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
  const bool exists = fs::exists(directory, code);
  if (code) {
    error = "cannot inspect cache directory: " + code.message();
    return std::nullopt;
  }
  if (!exists)
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
  for (const char *name : {"entries", "blobs", "tmp", "leases", "roots",
                           "accounting", "accounting.dirty"}) {
    fs::remove_all(directory / name, code);
    if (code) {
      error = "cannot remove " + (directory / name).generic_string() + ": " +
              code.message();
      return std::nullopt;
    }
  }
  // Git source checkouts share this root but are not build artifacts. Preserve
  // them and the marker; a failed clean must also remain recognizable.
  bool sourceCheckouts = false;
  for (fs::directory_iterator it(directory, code), end; !code && it != end;
       it.increment(code)) {
    auto name = it->path().filename();
    if (name == "sources") {
      sourceCheckouts = true;
      continue;
    }
    if (name != "VERSION" && name != "store.lock") {
      error = "cache directory contains unexpected entry: " +
              it->path().generic_string();
      return std::nullopt;
    }
  }
  if (code) {
    error = "cannot inspect cache contents: " + code.message();
    return std::nullopt;
  }
  if (sourceCheckouts)
    return removed;
  auto restoreMarker = [&] {
    std::ofstream marker(directory / "VERSION", std::ios::trunc);
    marker << "mettle-store 1\n";
    marker.close();
    if (!marker)
      error += "; could not restore cache marker";
  };
  fs::remove(directory / "VERSION", code);
  if (code) {
    error = "cannot remove cache marker: " + code.message();
    return std::nullopt;
  }
  fs::remove(directory / "store.lock", code);
  if (code) {
    error = "cannot remove cache lock: " + code.message();
    restoreMarker();
    return std::nullopt;
  }
  lock.release();
  fs::remove(directory, code);
  if (code) {
    error = "cannot remove cache directory: " + code.message();
    restoreMarker();
    return std::nullopt;
  }
  return removed;
}
} // namespace mettle::packages
