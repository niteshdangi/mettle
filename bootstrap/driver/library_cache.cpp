#include "driver/library_cache.h"
#include "packages/sha256.h"
#include "support/limits.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <charconv>
#include <condition_variable>
#include <ctime>
#include <fstream>
#include <future>
#include <limits>
#include <mutex>
#include <sstream>
#include <sys/stat.h>
#include <system_error>
#include <thread>
#ifdef __linux__
#include <fcntl.h>
#include <linux/magic.h>
#include <poll.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <sys/signalfd.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

namespace mettle::driver {
namespace {
class SnapshotWatch {
public:
  SnapshotWatch() = default;
  void start() {
#ifdef __linux__
    changes = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    wakeup = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (changes < 0 || wakeup < 0) {
      fail("cannot create source change monitor");
      return;
    }
    mounts = mountInventory();
    if (mounts.empty()) {
      fail("cannot observe mount changes");
      return;
    }
    std::promise<void> started;
    auto ready = started.get_future();
    try {
      worker = std::thread([this, started = std::move(started)]() mutable {
        sigset_t mask;
        sigemptyset(&mask);
        sigaddset(&mask, SIGIO);
        if (pthread_sigmask(SIG_BLOCK, &mask, nullptr) != 0 ||
            (signals = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK)) < 0) {
          fail("cannot receive source lease invalidation");
          started.set_value();
          return;
        }
        owner = static_cast<pid_t>(syscall(SYS_gettid));
        started.set_value();
        std::array<pollfd, 2> descriptors{pollfd{signals, POLLIN, 0},
                                          pollfd{wakeup, POLLIN, 0}};
        for (;;) {
          auto result = poll(descriptors.data(), descriptors.size(), -1);
          if (result < 0 && errno == EINTR)
            continue;
          if (result < 0 || descriptors[0].revents) {
            if (result < 0 ||
                (descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL)))
              monitorError = result < 0 ? errno : EIO;
            invalidate();
            return;
          }
          if (descriptors[1].revents) {
            std::uint64_t value;
            ssize_t count;
            do {
              count = read(wakeup, &value, sizeof(value));
            } while (count < 0 && errno == EINTR);
            if (count != sizeof(value)) {
              monitorError = count < 0 ? errno : EIO;
              invalidate();
              return;
            }
            signalfd_siginfo signal;
            do {
              count = read(signals, &signal, sizeof(signal));
            } while (count < 0 && errno == EINTR);
            if (count >= 0 || errno != EAGAIN) {
              if (count < 0)
                monitorError = errno;
              invalidate();
              return;
            }
            {
              std::lock_guard lock(leaseMutex);
              if (stopping)
                return;
              acknowledged = requested;
            }
            observed.notify_all();
          }
        }
      });
    } catch (const std::system_error &error) {
      reason =
          "cannot start source change monitor: " + std::string(error.what());
      invalid = true;
      return;
    }
    ready.get();
#else
    fail("source change monitoring is unavailable on this platform");
#endif
  }
  ~SnapshotWatch() {
#ifdef __linux__
    invalidate();
    if (worker.joinable()) {
      {
        std::lock_guard lock(leaseMutex);
        stopping = true;
      }
      wake();
      worker.join();
    }
    for (auto descriptor : {signals, changes, wakeup})
      if (descriptor >= 0)
        close(descriptor);
#endif
  }
  SnapshotWatch(const SnapshotWatch &) = delete;
  SnapshotWatch &operator=(const SnapshotWatch &) = delete;

  void directory(const std::filesystem::path &path) {
#ifdef __linux__
    if (invalid)
      return;
    struct statfs filesystem{};
    if (statfs(path.c_str(), &filesystem) != 0 ||
        (filesystem.f_type != EXT4_SUPER_MAGIC &&
         filesystem.f_type != XFS_SUPER_MAGIC &&
         filesystem.f_type != BTRFS_SUPER_MAGIC &&
         filesystem.f_type != TMPFS_MAGIC)) {
      fail("source filesystem has no supported local change notification");
      return;
    }
    if (inotify_add_watch(changes, path.c_str(),
                          IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO |
                              IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF |
                              IN_ONLYDIR | IN_DONT_FOLLOW) < 0)
      fail("cannot watch source directory");
#else
    (void)path;
#endif
  }

  void source(const std::filesystem::path &path) {
#ifdef __linux__
    if (invalid)
      return;
    if (inotify_add_watch(changes, path.c_str(),
                          IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF |
                              IN_MOVE_SELF | IN_DONT_FOLLOW) < 0) {
      fail("cannot watch source file");
      return;
    }
    std::lock_guard lock(leaseMutex);
    if (invalid)
      return;
    leases.push_back(-1);
    auto &descriptor = leases.back();
    descriptor = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    struct f_owner_ex destination{F_OWNER_TID, owner};
    if (descriptor < 0 || fcntl(descriptor, F_SETOWN_EX, &destination) < 0 ||
        fcntl(descriptor, F_SETSIG, SIGIO) < 0 ||
        fcntl(descriptor, F_SETLEASE, F_RDLCK) < 0) {
      if (descriptor >= 0)
        close(descriptor);
      leases.pop_back();
      reason = "source read leases are unavailable or a writer is active";
      invalid = true;
      return;
    }
#else
    (void)path;
#endif
  }

  bool unchanged() {
#ifdef __linux__
    if (invalid)
      return false;
    {
      std::unique_lock lock(leaseMutex);
      auto sequence = ++requested;
      if (!wake())
        return false;
      observed.wait(lock, [&] { return invalid || acknowledged >= sequence; });
      if (invalid)
        return false;
    }
    std::array<char, 4096> events;
    ssize_t count;
    do {
      count = read(changes, events.data(), events.size());
    } while (count < 0 && errno == EINTR);
    if (count >= 0 || errno != EAGAIN) {
      if (count < 0)
        monitorError = errno;
      invalidate();
      return false;
    }
    auto currentMounts = mountInventory();
    if (currentMounts != mounts) {
      if (currentMounts.empty())
        monitorError = EIO;
      invalidate();
      return false;
    }
    return !invalid;
#else
    return false;
#endif
  }
  std::string fallback() const {
    if (auto failure = monitorError.load())
      return "source change monitor failed: " +
             std::error_code(failure, std::generic_category()).message();
    return reason;
  }

private:
  void fail(std::string message) {
    reason = std::move(message);
    invalid = true;
  }
#ifdef __linux__
  static std::string mountInventory() {
    std::ifstream stream("/proc/self/mountinfo", std::ios::binary);
    std::ostringstream bytes;
    bytes << stream.rdbuf();
    return stream && !stream.bad() ? bytes.str() : std::string{};
  }
  void invalidate() {
    invalid = true;
    {
      std::lock_guard lock(leaseMutex);
      for (auto descriptor : leases)
        close(descriptor);
      leases.clear();
    }
    observed.notify_all();
  }
  bool wake() {
    std::uint64_t value = 1;
    ssize_t count;
    do {
      count = write(wakeup, &value, sizeof(value));
    } while (count < 0 && errno == EINTR);
    if (count == sizeof(value) || (count < 0 && errno == EAGAIN))
      return true;
    monitorError = count < 0 ? errno : EIO;
    return false;
  }
  int changes = -1, signals = -1, wakeup = -1;
  pid_t owner = 0;
  std::string mounts;
  std::mutex leaseMutex;
  std::condition_variable observed;
  std::uint64_t requested = 0, acknowledged = 0;
  bool stopping = false;
  std::vector<int> leases;
  std::thread worker;
#endif
  std::atomic<bool> invalid = false;
  std::atomic<int> monitorError = 0;
  std::string reason;
};

} // namespace

std::optional<std::string> entryStamp(const std::filesystem::path &path,
                                      std::time_t before) {
  struct stat status{};
  if (lstat(path.c_str(), &status) != 0)
    return std::nullopt;
#ifdef __APPLE__
  const auto &modified = status.st_mtimespec, &changed = status.st_ctimespec;
#else
  const auto &modified = status.st_mtim, &changed = status.st_ctim;
#endif
  if (changed.tv_sec > before - 2)
    return std::nullopt;
  std::ostringstream text;
  text << status.st_dev << ' ' << status.st_ino << ' ' << status.st_mode << ' '
       << status.st_size << ' ' << modified.tv_sec << ' ' << modified.tv_nsec
       << ' ' << changed.tv_sec << ' ' << changed.tv_nsec;
  return text.str();
}

namespace {
void putField(std::string &record, std::string_view value) {
  record += std::to_string(value.size());
  record += ':';
  record += value;
}

bool takeField(std::string_view &record, std::string_view &value) {
  std::size_t size = 0;
  auto [end, error] =
      std::from_chars(record.data(), record.data() + record.size(), size);
  if (error != std::errc{} || end == record.data() ||
      end == record.data() + record.size() || *end != ':')
    return false;
  record.remove_prefix(static_cast<std::size_t>(end - record.data()) + 1);
  if (size > record.size())
    return false;
  value = record.substr(0, size);
  record.remove_prefix(size);
  return true;
}

bool takeCount(std::string_view &record, std::size_t &count) {
  std::string_view value;
  if (!takeField(record, value))
    return false;
  auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), count);
  return error == std::errc{} && end == value.data() + value.size();
}

void hashField(packages::Sha256 &hash, std::string_view value) {
  char length[8];
  auto size = static_cast<std::uint64_t>(value.size());
  for (unsigned i = 0; i < 8; ++i)
    length[i] = static_cast<char>(size >> (i * 8));
  hash.update({length, sizeof(length)});
  hash.update(value);
}

void hashConfiguration(packages::Sha256 &hash,
                       const std::filesystem::path &root,
                       const LibraryCacheConfiguration &configuration) {
  auto field = [&](std::string_view value) { hashField(hash, value); };
  auto strings = [&](const std::set<std::string> &values) {
    field(std::to_string(values.size()));
    for (const auto &value : values)
      field(value);
  };
  field(configuration.compiler);
  field(configuration.identity);
  field(root.generic_string());
  field(configuration.target);
  field(configuration.profile);
  field(configuration.cc);
  field(configuration.sysroot);
  field(configuration.checks ? "checks" : "wrap");
  field(configuration.freestanding ? "freestanding" : "hosted");
  field(configuration.debugInfo ? "debug-info" : "no-debug-info");
  strings(configuration.features);
  strings(configuration.targetFeatures);
  strings(configuration.sanitizers);
  field(std::to_string(configuration.dependencies.size()));
  for (const auto &[identity, key] : configuration.dependencies) {
    field(identity);
    field(key);
  }
}

std::optional<LibraryInputs>
collectInputs(const std::filesystem::path &directory,
              const LibraryCacheConfiguration &configuration,
              std::string &problem, SnapshotWatch *watch = nullptr,
              std::string *snapshot = nullptr) {
  namespace fs = std::filesystem;
  problem.clear();
  auto started = std::time(nullptr);
  auto fail = [&](const std::string &message) -> std::optional<LibraryInputs> {
    problem = "cannot snapshot checked library: " + message;
    return std::nullopt;
  };
  if (configuration.compiler.empty() || configuration.identity.empty())
    return fail("compiler and package identities are required");
  std::error_code error;
  auto root = fs::canonical(directory, error);
  if (error || !fs::is_directory(root, error))
    return fail(directory.string() + " is not a readable directory");
  if (watch)
    watch->directory(root);
  std::vector<fs::path> paths, stamped{root};
  for (fs::recursive_directory_iterator item(root, error), end;
       !error && item != end; item.increment(error)) {
    paths.push_back(item->path());
    if (watch) {
      auto status = item->symlink_status(error);
      if (error)
        break;
      if (fs::is_directory(status))
        watch->directory(item->path());
    }
    if (paths.size() > limits::tokens)
      return fail("source inventory exceeds the compiler count limit");
  }
  if (error)
    return fail("directory traversal failed: " + error.message());
  std::sort(paths.begin(), paths.end());
  packages::Sha256 hash;
  auto field = [&](std::string_view value) { hashField(hash, value); };
  field("mettle-checked-library-inputs-1");
  hashConfiguration(hash, root, configuration);
  LibraryInputs inputs;
  for (const auto &path : paths) {
    auto status = fs::symlink_status(path, error);
    if (error)
      return fail("cannot inspect " + path.string() + ": " + error.message());
    if (!fs::is_directory(status) && !fs::is_symlink(status) &&
        path.extension() != ".mt")
      continue;
    stamped.push_back(path);
    auto canonical = fs::canonical(path, error);
    if (error)
      return fail("cannot identify " + path.string() + ": " + error.message());
    auto relative = canonical.lexically_relative(root);
    if (relative.empty() || *relative.begin() == "..")
      return fail("source link escapes the declared library root: " +
                  path.string());
    field(path.lexically_relative(root).generic_string());
    field(canonical.generic_string());
    if (fs::is_directory(canonical, error)) {
      field("directory");
      continue;
    }
    if (error || !fs::is_regular_file(canonical, error))
      return fail("unsupported source entry: " + path.string());
    if (path.extension() != ".mt") {
      field("non-source-link");
      continue;
    }
    if (watch)
      watch->source(canonical);
    auto size = fs::file_size(canonical, error);
    if (error || size > limits::sourceBytes)
      return fail("source size is unavailable or exceeds the compiler limit: " +
                  path.string());
    std::ifstream stream(canonical, std::ios::binary);
    std::string text(static_cast<std::size_t>(size), '\0');
    stream.read(text.data(), static_cast<std::streamsize>(text.size()));
    if (!stream || stream.peek() != std::char_traits<char>::eof())
      return fail("source changed or could not be read: " + path.string());
    field("source");
    field(text);
    auto name = canonical.generic_string();
    auto found = inputs.sources.find(name);
    if (found != inputs.sources.end() && found->second.text != text)
      return fail("source changed during snapshot: " + path.string());
    if (found == inputs.sources.end()) {
      packages::Sha256 content;
      content.update(text);
      inputs.digests.emplace(name, content.finish());
      inputs.sources.emplace(name, Source{name, std::move(text), SourceId{0}});
    }
  }
  if (inputs.sources.empty())
    return fail("no library sources");
  inputs.key = hash.finish();
  if (snapshot) {
    std::string record;
    putField(record, "mettle-library-snapshot-1");
    putField(record, inputs.key);
    putField(record, std::to_string(inputs.digests.size()));
    for (const auto &[name, digest] : inputs.digests) {
      putField(record, name);
      putField(record, digest);
    }
    putField(record, std::to_string(stamped.size()));
    for (const auto &path : stamped) {
      auto stamp = entryStamp(path, started);
      if (!stamp)
        return inputs;
      putField(record, path.generic_string());
      putField(record, *stamp);
    }
    *snapshot = std::move(record);
  }
  return inputs;
}

std::string selector(std::string_view tag, const std::filesystem::path &root,
                     const LibraryCacheConfiguration &configuration) {
  packages::Sha256 hash;
  hashField(hash, tag);
  hashConfiguration(hash, root, configuration);
  return hash.finish();
}
} // namespace

std::string
shippedLibrarySelector(const std::filesystem::path &directory,
                       const LibraryCacheConfiguration &configuration,
                       const std::filesystem::path &canonicalLibraryPath) {
  namespace fs = std::filesystem;
  std::error_code error;
  fs::path root;
  if (canonicalLibraryPath.is_absolute()) {
    auto child = canonicalLibraryPath / directory.filename();
    if (fs::is_directory(fs::symlink_status(child, error)))
      root = std::move(child);
  }
  if (root.empty())
    root = fs::weakly_canonical(directory, error);
  return error ? std::string()
               : selector("mettle-shipped-library-selector-1", root,
                          configuration);
}

std::string
librarySnapshotSelector(const std::filesystem::path &directory,
                        const LibraryCacheConfiguration &configuration) {
  std::error_code error;
  auto root = std::filesystem::weakly_canonical(directory, error);
  return error ? std::string()
               : selector("mettle-library-snapshot-selector-1", root,
                          configuration);
}

std::optional<LibraryInputs> restoreLibraryInputs(std::string_view record) {
  std::string_view value, stamp;
  std::size_t digests = 0, stamps = 0;
  if (!takeField(record, value) || value != "mettle-library-snapshot-1" ||
      !takeField(record, value) || !takeCount(record, digests) || !digests)
    return std::nullopt;
  LibraryInputs inputs;
  inputs.key = value;
  for (std::size_t i = 0; i < digests; ++i) {
    if (!takeField(record, value) || !takeField(record, stamp))
      return std::nullopt;
    inputs.digests.emplace(value, stamp);
  }
  if (!takeCount(record, stamps) || !stamps)
    return std::nullopt;
  for (std::size_t i = 0; i < stamps; ++i) {
    if (!takeField(record, value) || !takeField(record, stamp))
      return std::nullopt;
    auto current = entryStamp(std::filesystem::path(value),
                              std::numeric_limits<std::time_t>::max());
    if (!current || *current != stamp)
      return std::nullopt;
  }
  if (!record.empty())
    return std::nullopt;
  return inputs;
}

struct LibraryInputSnapshots::Entry {
  std::filesystem::path root;
  LibraryCacheConfiguration configuration;
  std::shared_ptr<const LibraryInputs> inputs;
  SnapshotWatch watch;
};

LibraryInputSnapshots::LibraryInputSnapshots() = default;
LibraryInputSnapshots::~LibraryInputSnapshots() = default;

std::shared_ptr<const LibraryInputs>
LibraryInputSnapshots::collect(const std::filesystem::path &directory,
                               const LibraryCacheConfiguration &configuration,
                               std::string &error, std::string &fallback) {
  namespace fs = std::filesystem;
  error.clear();
  fallback.clear();
  std::error_code fileError;
  auto requested = fs::absolute(directory, fileError);
  if (fileError) {
    error = "cannot snapshot checked library: cannot identify " +
            directory.string() + ": " + fileError.message();
    return nullptr;
  }
  auto name = requested.lexically_normal().generic_string();
  auto root = fs::canonical(requested, fileError);
  auto found = entries.find(name);
  if (found != entries.end()) {
    const auto &entry = *found->second;
    if (!fileError && entry.root == root &&
        entry.configuration == configuration &&
        found->second->watch.unchanged())
      return entry.inputs;
    fallback = entry.watch.fallback();
    entries.erase(found);
  }
  auto entry = std::make_unique<Entry>();
  entry->watch.start();
  auto inputs = collectInputs(directory, configuration, error, &entry->watch);
  if (!inputs)
    return nullptr;
  auto result = std::make_shared<const LibraryInputs>(std::move(*inputs));
  if (entry->watch.unchanged()) {
    entry->root = std::move(root);
    entry->configuration = configuration;
    entry->inputs = result;
    entries.emplace(std::move(name), std::move(entry));
  } else {
    if (auto note = entry->watch.fallback(); !note.empty())
      fallback = std::move(note);
    if (fallback.empty())
      fallback = "source tree or monitor changed during snapshot";
  }
  return result;
}

std::optional<LibraryInputs>
collectLibraryInputs(const std::filesystem::path &directory,
                     const LibraryCacheConfiguration &configuration,
                     std::string &problem, std::string *snapshot) {
  return collectInputs(directory, configuration, problem, nullptr, snapshot);
}
} // namespace mettle::driver
