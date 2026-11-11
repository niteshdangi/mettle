#include "driver/library_archive.h"
#include "driver/library_cache.h"
#include "packages/sha256.h"
#include "packages/store.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>

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
  packages::Sha256 invalidHash;
  invalidHash.update(invalidSource);
  invalidSource += invalidHash.finish();
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
  packages::Store store(root, {0, 0});
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
}
