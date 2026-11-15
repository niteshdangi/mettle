import re
p="bootstrap/packages/store.h"
s=open(p).read()
s=s.replace("#include <filesystem>\n","#include <filesystem>\n#include <memory>\n#include <mutex>\n",1)
s=s.replace("//   leases/KEY/TOKEN","//   roots/ID           working set (source path, then keys) of one project\n//                      configuration, written by `commitProject`\n//   leases/KEY/TOKEN",1)
s=s.replace('''  StoreUsage usage() const;''','''  // Records the entries this store object read or wrote as the working set of
  // `project`, a stable name for one project configuration whose sources live
  // at `path`. Evicts the entries that set held before and no live project
  // holds now, and those held only by projects whose `path` is gone. The
  // cache stays proportional to the live projects' current builds without a
  // global size bound. Returns one explanation per removal.
  std::vector<std::string> commitProject(const std::string &project,
                                         const std::filesystem::path &path);
  StoreUsage usage() const;''',1)
s=s.replace('''  std::filesystem::path directory;
  StoreLimits bounds;
};''','''  struct Touched {
    std::mutex lock;
    std::set<std::string> keys;
  };
  void note(const std::string &key) const;
  std::filesystem::path directory;
  StoreLimits bounds;
  std::shared_ptr<Touched> touched = std::make_shared<Touched>();
};''',1)
open(p,"w").write(s)

p="bootstrap/packages/store.cpp"
s=open(p).read()
# note() at the start of each keyed operation
sigs=[
 "Store::Data Store::data(const std::string &key, std::uint64_t maximumBytes) {\n",
 "bool Store::put(const std::string &key, const fs::path &file, bool executable) {\n",
 "bool Store::putData(const std::string &key, std::string_view bytes) {\n",
 "std::optional<std::string> Store::text(const std::string &key) {\n",
 "bool Store::putText(const std::string &key, const std::string &text) {\n",
]
for sg in sigs:
    assert sg in s, sg
    s=s.replace(sg, sg+"  note(key);\n",1)
m="Store::Lookup Store::materialize(const std::string &key,"
i=s.index(m); j=s.index("{\n",i)+2
s=s[:j]+"  note(key);\n"+s[j:]
pm="bool Store::putMany(const std::vector<Artifact> &artifacts) {\n"
assert pm in s
s=s.replace(pm,pm+"  for (const auto &artifact : artifacts)\n    note(artifact.key);\n",1)
commit='''void Store::note(const std::string &key) const {
  std::lock_guard guard(touched->lock);
  touched->keys.insert(key);
}

std::vector<std::string>
Store::commitProject(const std::string &project, const fs::path &path) {
  if (project.empty() || !prepare())
    return {};
  StoreLock lock(directory);
  if (!lock)
    return {};
  Sha256 name;
  name.update(project);
  const auto rootsDirectory = directory / "roots";
  std::error_code error;
  fs::create_directories(rootsDirectory, error);
  struct Root {
    fs::path file, source;
    std::set<std::string> keys;
    fs::file_time_type used;
  };
  auto read = [](const fs::path &file) -> std::optional<Root> {
    auto content = readText(file);
    if (!content)
      return std::nullopt;
    Root root;
    root.file = file;
    std::istringstream lines(*content);
    std::string line;
    if (!std::getline(lines, line))
      return std::nullopt;
    root.source = line;
    while (std::getline(lines, line))
      if (!line.empty())
        root.keys.insert(line);
    std::error_code stale;
    root.used = fs::last_write_time(file, stale);
    return root;
  };
  const auto mine = rootsDirectory / name.finish();
  std::set<std::string> current;
  {
    std::lock_guard guard(touched->lock);
    current = touched->keys;
  }
  std::set<std::string> released;
  if (auto previous = read(mine))
    for (const auto &key : previous->keys)
      if (!current.contains(key))
        released.insert(key);
  std::string content = path.string() + "\n";
  for (const auto &key : current)
    content += key + "\n";
  if (!publishLocked(mine, content))
    return {};
  const auto now = fs::file_time_type::clock::now();
  std::set<std::string> claimed = current;
  for (fs::directory_iterator it(rootsDirectory, error), end;
       !error && it != end; it.increment(error)) {
    if (it->path() == mine)
      continue;
    auto other = read(it->path());
    std::error_code gone;
    const bool dead =
        !other || !fs::exists(other->source, gone) ||
        (bounds.maxAgeDays &&
         now - other->used >
             std::chrono::hours(24 * static_cast<long>(bounds.maxAgeDays)));
    if (dead) {
      if (other)
        released.insert(other->keys.begin(), other->keys.end());
      fs::remove(it->path(), gone);
    } else
      claimed.insert(other->keys.begin(), other->keys.end());
  }
  std::vector<std::string> notes;
  const auto leased = liveLeaseKeys(directory);
  for (const auto &key : released)
    if (!claimed.contains(key) && !leased.contains(key) && key.size() >= 2) {
      std::error_code removed;
      if (fs::remove(entryPath(key), removed))
        notes.push_back("evicted " + key.substr(0, 12) +
                        ": no live project build uses it");
    }
  for (auto &note : pruneLocked({}))
    notes.push_back(std::move(note));
  return notes;
}

std::vector<std::string> Store::prune(const std::string &keep) {'''
assert "std::vector<std::string> Store::prune(const std::string &keep) {" in s
s=s.replace("std::vector<std::string> Store::prune(const std::string &keep) {",commit,1)
open(p,"w").write(s)

p="bootstrap/driver/run.cpp"
s=open(p).read()
old='''    for (const auto &note : store->prune(*cacheKey))
      if (options.explain)
        std::cerr << "mettle: cache " << note << '\n';'''
new='''    for (const auto &note : store->prune(*cacheKey))
      if (options.explain)
        std::cerr << "mettle: cache " << note << '\n';
    std::error_code absolute;
    auto root = std::filesystem::absolute(source.path, absolute);
    if (!absolute) {
      packages::Sha256 project;
      for (const auto &field :
           {root.string(), options.profile, options.target, options.emit,
            std::string(options.library ? "library" : "executable"),
            std::string(options.freestanding ? "freestanding" : "hosted"),
            std::string(options.checks.value_or(options.profile != "release")
                            ? "checks"
                            : "wrap")}) {
        project.update(field);
        project.update(std::string_view("\0", 1));
      }
      for (const auto &sanitizer : options.sanitizers)
        project.update(sanitizer);
      for (const auto &note : store->commitProject(project.finish(), root))
        if (options.explain)
          std::cerr << "mettle: cache " << note << '\n';
    }'''
assert old in s
s=s.replace(old,new,1)
open(p,"w").write(s)
