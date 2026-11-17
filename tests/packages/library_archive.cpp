#include "driver/library_archive.h"
#include "driver/library_cache.h"
#include "packages/sha256.h"
#include "packages/store.h"
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>

namespace {
void expect(bool condition, const char *message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}
} // namespace

int main() {
  using namespace mettle;
  auto digest = [](const std::string &text) {
    packages::Sha256 hash;
    hash.update(text);
    return hash.finish();
  };
  expect(digest("abc") ==
             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
         "SHA-256 of one block changed");
  expect(digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
             "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
         "SHA-256 across a padding boundary changed");
  for (const auto &[size, expected] :
       {std::pair{56, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82"
                      "a60895f562"},
        std::pair{65, "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f"
                      "2fabb31781"},
        std::pair{4097, "a16560d668b843fb3be99ace41dbd18471f342bd3255a1d21204"
                        "b35e43f74436"}}) {
    std::string input;
    for (int i = 0; i < size; ++i)
      input.push_back(static_cast<char>(i % 251));
    packages::Sha256 hash;
    for (std::size_t offset = 0; offset < input.size(); offset += 29)
      hash.update(std::string_view(input).substr(offset, 29));
    expect(digest(input) == expected && hash.finish() == expected,
           "SHA-256 binary and incremental hashing must agree");
  }
  {
    packages::Sha256 hash;
    const std::string chunk(1000, 'a');
    for (int i = 0; i < 1000; ++i)
      hash.update(chunk);
    expect(
        hash.finish() ==
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
        "SHA-256 of a long input changed");
  }
  Diagnostics original;
  Source first{"core/main.mt", "macro value", 4};
  Source generated{"core/main.mt", "generated", 9};
  {
    Diagnostics::SourceContext registerFirst(original, first);
    Diagnostics::SourceContext registerGenerated(original, generated);
  }
  auto context = original.makeSyntaxContext({"core"}, {0, 5, first.id});
  original.generated(
      {generated.id,
       {0, 5, first.id},
       "macro value",
       {{0, 9, {1, 10, first.id}, false, {0, 5, first.id}, "value", context}}});
  driver::LibraryArchive archive("library-revision");
  std::string error;
  expect(archive.sources.capture(original, error), error.c_str());
  auto reference = archive.sources.reference({1, 4, generated.id});
  expect(reference.has_value(), "generated source must have a revision");
  auto originalReference = archive.sources.reference({0, 0, first.id});
  expect(originalReference.has_value(), "original source must have a revision");
  archive.sourceModules[originalReference->revision] = {"core", "values"};
  archive.sourceModules[reference->revision] = {"core", "values"};
  archive.macros = std::string("macro\0rules", 11);
  archive.types = {0, 1, 2, 255};
  archive.header = {5, 6, 7};
  archive.declarations = {8, 9, 0, 10};
  archive.ir = {4, 3, 2, 1};
  auto bytes = driver::encodeLibraryArchive(archive, error);
  expect(bytes.has_value(), error.c_str());
  auto imported =
      driver::decodeLibraryArchive(*bytes, "library-revision", error);
  expect(imported.has_value(), error.c_str());
  expect(imported->macros == archive.macros &&
             imported->types == archive.types &&
             imported->header == archive.header &&
             imported->declarations == archive.declarations &&
             imported->ir == archive.ir &&
             imported->sourceModules == archive.sourceModules,
         "all independent compilation sections must survive");
  Diagnostics consumer;
  Source occupied{"consumer.mt", "consumer source", 50};
  {
    Diagnostics::SourceContext registerConsumer(consumer, occupied);
  }
  consumer.makeSyntaxContext({}, {});
  SourceId next = 80;
  expect(imported->sources.mount(
             consumer, [&] { return next++; }, error),
         error.c_str());
  auto span = imported->sources.resolve(*reference);
  expect(span && span->source == 81 && span->begin == 1 && span->end == 4,
         "source IDs must be remapped, not restored");
  auto remappedContext = consumer.syntaxContext(*span);
  expect(remappedContext && remappedContext->identity != context->identity &&
             remappedContext->scope == context->scope &&
             remappedContext->definition.source == 80,
         "generated hygiene and definition provenance must be remapped");
  auto debug = consumer.debugSpan(*span);
  expect(debug.source == 80 && debug.begin == 0,
         "generated debug locations must retain their invocation");
  expect(!driver::encodeLibraryArchive(*imported, error),
         "a mounted archive has moved its generations and must not encode");
  expect(!driver::decodeLibraryArchive(*bytes, "other-revision", error),
         "a different compiler/content/config identity must reject");
  for (auto size : {std::size_t(0), bytes->size() / 2, bytes->size() - 1})
    expect(!driver::decodeLibraryArchive(bytes->substr(0, size),
                                         "library-revision", error),
           "truncated library archives must reject");
  auto corrupt = *bytes;
  corrupt.back() ^= 1;
  expect(!driver::decodeLibraryArchive(corrupt, "library-revision", error),
         "corrupt payload must reject");
  expect(!driver::decodeLibraryArchive(*bytes + "x", "library-revision", error),
         "trailing archive data must reject");
  auto invalidSource = *bytes;
  auto sourceText = invalidSource.find("generated");
  expect(sourceText != std::string::npos, "fixture must contain source text");
  invalidSource[sourceText] = static_cast<char>(255);
  invalidSource.resize(invalidSource.size() - 64);
  invalidSource += driver::archiveDigest(invalidSource);
  expect(
      !driver::decodeLibraryArchive(invalidSource, "library-revision", error),
      "well-checksummed invalid source encoding must reject");
  auto before = consumer.registeredSources().size();
  auto collision =
      driver::decodeLibraryArchive(*bytes, "library-revision", error);
  expect(collision &&
             !collision->sources.mount(
                 consumer, [] { return SourceId{50}; }, error) &&
             consumer.registeredSources().size() == before,
         "source ID collision must reject before registering anything");
  namespace fs = std::filesystem;
  auto root = fs::temp_directory_path() /
              ("mettle-library-archive-" + std::to_string(getpid()));
  expect(fs::create_directory(root), "must create a private test store");
  struct Cleanup {
    fs::path root;
    ~Cleanup() {
      std::error_code error;
      fs::remove_all(root, error);
    }
  } cleanup{root};
  packages::Store store(root, {1, 0});
  auto key = std::string(64, 'a'), other = std::string(64, 'b');
  auto lease = store.acquireLease(key);
  expect(static_cast<bool>(lease), "must lease checked-library input");
  expect(store.putData(key, *bytes) && store.putData(other, *bytes),
         "must publish binary archives through the bounded blob store");
  auto read = store.data(key, bytes->size());
  expect(read.status == packages::Store::Lookup::Hit && read.bytes == *bytes,
         "stored archive bytes must be verified before decoding");
  expect(store.usage().blobs == 1, "equal interfaces must share a blob");
  store.prune();
  expect(store.data(key, bytes->size()).status == packages::Store::Lookup::Hit,
         "active checked library must survive byte-limit pruning");
  lease = {};
  store.prune();
  expect(store.data(key, bytes->size()).status == packages::Store::Lookup::Miss,
         "evicting checked metadata must become a recomputable miss");
  expect(store.putData(key, *bytes), "must restore evicted metadata");
  expect(store.data(key, bytes->size() - 1).status ==
             packages::Store::Lookup::Corrupt,
         "oversized metadata must reject before allocating its payload");
  expect(store.putData(key, *bytes), "must republish after invalidation");
  packages::Sha256 hash;
  hash.update(*bytes);
  auto blob = hash.finish();
  auto blobPath = root / "blobs" / blob.substr(0, 2) / blob;
  fs::permissions(blobPath, fs::perms::owner_write, fs::perm_options::add);
  {
    std::ofstream corruptBlob(blobPath, std::ios::binary | std::ios::trunc);
    corruptBlob << "corrupt";
  }
  expect(store.data(key, bytes->size()).status ==
             packages::Store::Lookup::Corrupt,
         "changed interface blobs must never be treated as valid metadata");
  expect(
      store.putData(key, *bytes) &&
          store.data(key, bytes->size()).bytes == *bytes,
      "corrupt-size blobs must be removed so source rebuilds can repair them");
  auto corruptWithoutChangingStamp = [&] {
    auto modified = *bytes;
    modified[0] ^= 1;
    auto stamp = fs::last_write_time(blobPath);
    struct stat status{};
    expect(stat(blobPath.c_str(), &status) == 0, "must stat the cached blob");
    auto legacyStamp =
        static_cast<std::uint64_t>(status.st_mtim.tv_sec) * 1000000000u +
        static_cast<std::uint64_t>(status.st_mtim.tv_nsec) + 1;
    {
      std::ofstream entry(root / "entries" / key.substr(0, 2) / key,
                          std::ios::trunc);
      entry << "file " << blob << ' ' << bytes->size() << " - " << legacyStamp
            << '\n';
      expect(static_cast<bool>(entry), "must create a legacy cache entry");
    }
    fs::permissions(blobPath, fs::perms::owner_write, fs::perm_options::add);
    {
      std::ofstream out(blobPath, std::ios::binary | std::ios::trunc);
      out.write(modified.data(), static_cast<std::streamsize>(modified.size()));
      expect(static_cast<bool>(out), "must modify the cached blob");
    }
    fs::last_write_time(blobPath, stamp);
  };
  corruptWithoutChangingStamp();
  expect(store.data(key, bytes->size()).status ==
             packages::Store::Lookup::Corrupt,
         "same-size corruption with a restored timestamp must reject on read");
  expect(store.putData(key, *bytes), "must restore verified metadata");
  auto destination = root / "materialized";
  {
    std::ofstream out(destination);
    out << "existing";
  }
  corruptWithoutChangingStamp();
  expect(store.materialize(key, destination) ==
             packages::Store::Lookup::Corrupt,
         "same-size corruption with a restored timestamp must reject on copy");
  {
    std::ifstream in(destination);
    std::string value;
    in >> value;
    expect(value == "existing", "corrupt blobs must not replace outputs");
  }
  expect(store.putData(key, *bytes), "must restore verified metadata");
  corruptWithoutChangingStamp();
  expect(store.putData(key, *bytes) &&
             store.data(key, bytes->size()).bytes == *bytes,
         "publication must repair an existing corrupt blob");
  auto artifact = root / "artifact";
  {
    std::ofstream out(artifact, std::ios::binary);
    out.write(bytes->data(), static_cast<std::streamsize>(bytes->size()));
    expect(static_cast<bool>(out), "must create a batch artifact");
  }
  corruptWithoutChangingStamp();
  packages::Store unbounded(root, {0, 0});
  expect(unbounded.putMany({{key, artifact, false}}) &&
             unbounded.data(key, bytes->size()).bytes == *bytes,
         "batch publication must repair an existing corrupt blob");
  store.prune();
  auto child = fork();
  expect(child >= 0, "must start concurrent publisher");
  if (child == 0)
    _exit(store.putData(key, *bytes) ? 0 : 1);
  expect(store.putData(key, *bytes), "parent publication must succeed");
  int childStatus = 0;
  expect(waitpid(child, &childStatus, 0) == child && WIFEXITED(childStatus) &&
             WEXITSTATUS(childStatus) == 0 &&
             store.data(key, bytes->size()).bytes == *bytes,
         "concurrent checked-library publication must remain atomic");
  auto libraryRoot = root / "core";
  fs::create_directory(libraryRoot);
  {
    std::ofstream source(libraryRoot / "main.mt");
    source << "pub const fn value(): i32 { 41 }";
  }
  driver::LibraryCacheConfiguration configuration;
  configuration.compiler = "compiler-content-hash";
  configuration.identity = "core";
  configuration.target = "x86_64-unknown-linux-gnu";
  configuration.profile = "release";
  configuration.checks = false;
  auto inputs = driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(inputs && inputs->sources.size() == 1, error.c_str());
  auto same = driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(same && same->key == inputs->key,
         "independent consumers must share the same library key");
  auto previousTime = fs::last_write_time(libraryRoot / "main.mt");
  {
    std::ofstream source(libraryRoot / "main.mt");
    source << "pub const fn value(): i32 { 42 }";
  }
  fs::last_write_time(libraryRoot / "main.mt", previousTime);
  auto edited = driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(edited && edited->key != inputs->key,
         "private/body content edits must invalidate even at identical mtime");
  configuration.features.insert("feature");
  auto feature =
      driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(feature && feature->key != edited->key,
         "library cfg/features must invalidate checked contracts");
  configuration.dependencies["alloc"] = "dependency-interface-identity";
  auto dependency =
      driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(dependency && dependency->key != feature->key,
         "resolved dependency interfaces must participate in identity");
  configuration.compiler += "-rebuilt";
  auto compiler =
      driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(compiler && compiler->key != dependency->key,
         "rebuilt compiler identity must invalidate checked metadata");
  {
    std::ofstream source(libraryRoot / "new.mt");
    source << "";
  }
  auto addition =
      driver::collectLibraryInputs(libraryRoot, configuration, error);
  expect(addition && addition->key != compiler->key,
         "a formerly absent module appearing must invalidate the library");
  driver::LibraryInputSnapshots snapshots;
  std::string fallback;
  auto snapshot = [&]() {
    auto value = snapshots.collect(libraryRoot, configuration, error, fallback);
    expect(static_cast<bool>(value), error.c_str());
    return value;
  };
  auto retained = snapshot();
  auto monitored = fallback.empty();
  auto reused = snapshot();
  expect(reused->key == retained->key && (!monitored || reused == retained),
         "unchanged monitored sources must reuse their resident snapshot");
  previousTime = fs::last_write_time(libraryRoot / "main.mt");
  {
    std::ofstream source(libraryRoot / "main.mt");
    source << "pub const fn value(): i32 { 43 }";
  }
  fs::last_write_time(libraryRoot / "main.mt", previousTime);
  auto changed = snapshot();
  expect(
      changed->key != reused->key,
      "resident snapshots must invalidate same-size writes at identical mtime");
  {
    std::ofstream replacement(root / "replacement.mt");
    replacement << "pub const fn value(): i32 { 44 }";
  }
  fs::last_write_time(root / "replacement.mt", previousTime);
  fs::rename(root / "replacement.mt", libraryRoot / "main.mt");
  auto replaced = snapshot();
  expect(replaced->key != changed->key,
         "resident snapshots must invalidate atomic same-stamp replacements");
  fs::create_directories(libraryRoot / "nested");
  {
    std::ofstream added(libraryRoot / "nested" / "added.mt");
    added << "pub const ADDED: i32 = 1";
  }
  auto nested = snapshot();
  expect(nested->key != replaced->key && nested->sources.size() == 3,
         "resident snapshots must discover newly added subdirectories");
  fs::remove_all(libraryRoot / "nested");
  expect(snapshot()->key == replaced->key,
         "resident snapshots must invalidate removed source directories");
  fs::create_hard_link(libraryRoot / "main.mt", root / "outside-alias.mt");
  auto aliased = snapshot();
  {
    std::ofstream alias(root / "outside-alias.mt");
    alias << "pub const fn value(): i32 { 45 }";
  }
  expect(
      snapshot()->key != aliased->key,
      "writes through a hard link outside the root must invalidate snapshots");
  auto descriptor = open((libraryRoot / "main.mt").c_str(), O_RDWR);
  expect(descriptor >= 0, "must open a mapped source writer");
  auto length =
      static_cast<std::size_t>(fs::file_size(libraryRoot / "main.mt"));
  auto mapping =
      mmap(nullptr, length, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
  expect(mapping != MAP_FAILED, "must map a source writer");
  close(descriptor);
  auto mapped = snapshot();
  static_cast<char *>(mapping)[length - 3] = '6';
  expect(msync(mapping, length, MS_SYNC) == 0,
         "must flush the mapped source edit");
  expect(snapshot()->key != mapped->key,
         "writable mappings must prevent unsound notification-only reuse");
  expect(munmap(mapping, length) == 0, "must release mapped source writer");
  auto rootLink = root / "linked-core";
  fs::create_directory_symlink(libraryRoot, rootLink);
  auto linked = snapshots.collect(rootLink, configuration, error, fallback);
  expect(linked && linked->key == snapshot()->key,
         "source root aliases must preserve canonical content identity");
  fs::create_directory(root / "other-core");
  {
    std::ofstream source(root / "other-core" / "module.mt");
    source << "pub const OTHER: i32 = 1";
  }
  fs::remove(rootLink);
  fs::create_directory_symlink(root / "other-core", rootLink);
  auto retargeted = snapshots.collect(rootLink, configuration, error, fallback);
  expect(retargeted && retargeted->key != linked->key,
         "retargeting a library root symlink must invalidate its snapshot");
  fs::create_symlink(root / "outside-alias.mt", libraryRoot / "escape.mt");
  expect(!snapshots.collect(libraryRoot, configuration, error, fallback) &&
             error.find("source link escapes") != std::string::npos,
         "an invalidated snapshot must reject newly introduced escaping links");
}
