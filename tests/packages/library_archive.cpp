#include "driver/library_archive.h"
#include "driver/library_cache.h"
#include "ir/codec.h"
#include "packages/sha256.h"
#include "packages/store.h"
#include "semantics/check.h"
#include "semantics/library.h"
#include "syntax/parser.h"
#include <cerrno>
#include <chrono>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <utility>
#if defined(__linux__)
#include <sys/inotify.h>
#endif

namespace {
void expect(bool condition, const char *message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}

void testStoreAccounting(const std::filesystem::path &root) {
  namespace fs = std::filesystem;
  using mettle::packages::Store;
  fs::create_directories(root);
  const auto source = root / "source", otherSource = root / "other-source";
  fs::create_directory(source);
  fs::create_directory(otherSource);
  const std::string first(64, 'a'), second(64, 'b'), third(64, 'c');
  {
    Store store(root, {0, 0});
    expect(store.putData(first, "shared") &&
               store.commitProject("first", source).empty(),
           "must index the first project's shared blob");
  }
  {
    Store store(root, {0, 0});
    expect(store.putData(second, "shared") &&
               store.commitProject("second", otherSource).empty(),
           "must retain a blob shared across independent project updates");
  }
#if defined(__linux__)
  int events = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  expect(events >= 0 && inotify_add_watch(
                            events, (root / "entries" / "bb" / second).c_str(),
                            IN_OPEN) >= 0,
         "must observe unrelated entry reads");
  {
    std::ifstream observed(root / "entries" / "bb" / second);
    expect(observed.good(), "must open the entry-read observation control");
  }
  char controlEvents[sizeof(inotify_event) + 256];
  expect(read(events, controlEvents, sizeof controlEvents) > 0,
         "cache test filesystem must report watched entry opens");
#endif
  {
    Store store(root, {0, 0});
    expect(store.putText(third, "replacement"),
           "must publish the replacement working set");
    store.commitProject("first", source);
#if defined(__linux__)
    char buffer[sizeof(inotify_event) + 256];
    expect(read(events, buffer, sizeof buffer) < 0 && errno == EAGAIN,
           "successful builds must not open unrelated cache entry files");
    close(events);
#endif
    expect(!fs::exists(root / "entries" / "aa" / first) &&
               store.data(second, 6).bytes == "shared" &&
               store.usage().blobs == 1,
           "project replacement must preserve other projects' blob references");
  }
  {
    Store store(root, {0, 0});
    auto lease = store.acquireLease(second);
    fs::remove(otherSource);
    store.text(third);
    store.commitProject("first", source);
    expect(store.data(second, 6).bytes == "shared",
           "project retirement must preserve live leases");
    lease = {};
  }
  {
    Store store(root, {0, 0});
    store.prune();
    expect(store.data(second, 6).status == Store::Lookup::Miss &&
               store.usage().blobs == 0,
           "retired project entries must be reclaimed when their leases end");
  }
  {
    std::ofstream dirty(root / "accounting.dirty");
    dirty.close();
    const auto entry = root / "entries" / "dd" / std::string(64, 'd');
    fs::create_directories(entry.parent_path());
    std::ofstream(entry) << "text\n" << std::string(1024, 'x');
    const auto orphan = root / "blobs" / "ee" / std::string(64, 'e');
    fs::create_directories(orphan.parent_path());
    std::ofstream(orphan) << "interrupted publication";
    Store store(root, {1, 0});
    store.prune();
    expect(store.usage().bytes <= 1 && !fs::exists(orphan),
           "interrupted publications must recover accounting before budgeting");
    std::ofstream(entry) << "text\n" << std::string(1024, 'x');
    Store legacyWriter(root, {1, 0});
    legacyWriter.prune();
    expect(legacyWriter.usage().bytes <= 1,
           "unindexed publications must be accounted before enforcing budgets");
  }
  {
    Store store(root, {0, 0});
    expect(store.putData(first, "shared") && store.putData(second, "shared"),
           "must repopulate deduplicated references after recovery");
    mettle::packages::Sha256 digest;
    digest.update("shared");
    auto blob = digest.finish();
    auto file = root / "blobs" / blob.substr(0, 2) / blob;
    fs::permissions(file, fs::perms::owner_write, fs::perm_options::add);
    std::ofstream(file, std::ios::trunc) << "broken";
    expect(
        store.data(first, 6).status == Store::Lookup::Corrupt &&
            store.putData(first, "shared") &&
            store.data(second, 6).bytes == "shared",
        "corruption repair must restore accounting for every shared reference");
  }
  for (const std::string kind : {"state", "entries-", "blobs-"}) {
    Store seed(root, {0, 0});
    expect(seed.putData(first, "shared") && seed.putData(second, "shared"),
           "must seed independently persisted accounting references");
    fs::path damaged;
    for (const auto &file : fs::directory_iterator(root / "accounting")) {
      if (!file.path().filename().string().starts_with(kind))
        continue;
      std::ifstream input(file.path(), std::ios::binary);
      std::string content{std::istreambuf_iterator<char>(input), {}};
      mettle::packages::Sha256 hash;
      hash.update("shared");
      if (kind == "state" ||
          content.find(kind == "blobs-" ? hash.finish() : first) !=
              std::string::npos) {
        damaged = file.path();
        break;
      }
    }
    expect(!damaged.empty(), "must locate the accounting corruption fixture");
    fs::resize_file(damaged, fs::file_size(damaged) - 1);
    Store store(root, {1, 0});
    auto lease = store.acquireLease(first);
    store.prune();
    expect(store.data(first, 6).bytes == "shared" &&
               store.data(second, 6).status == Store::Lookup::Miss,
           "torn accounting must rebuild blob references and preserve leases");
    lease = {};
    store.prune();
    expect(store.usage().bytes <= 1,
           "recovered accounting must enforce the budget without deferral");
  }
  {
    Store store(root, {0, 0});
    expect(store.putText(first, "old"), "must publish an age-limited entry");
    expect(store.putText(second, "read"),
           "must publish a concurrently refreshed age-limited entry");
    fs::last_write_time(root / "entries" / "aa" / first,
                        fs::file_time_type::clock::now() -
                            std::chrono::hours(72));
    fs::last_write_time(root / "entries" / "bb" / second,
                        fs::file_time_type::clock::now() -
                            std::chrono::hours(72));
    std::ofstream(root / "accounting.dirty").close();
    Store aged(root, {0, 1});
    auto lease = aged.acquireLease(first);
    auto otherLease = aged.acquireLease(second);
    aged.prune();
    expect(fs::exists(root / "entries" / "aa" / first),
           "age pruning must preserve leased entries after recovery");
    Store reader(root, {0, 0});
    expect(reader.text(second) == "read",
           "must refresh a use time without a project update");
    lease = {};
    otherLease = {};
    aged.prune();
    expect(
        !fs::exists(root / "entries" / "aa" / first) &&
            fs::exists(root / "entries" / "bb" / second),
        "age pruning must reclaim expired leases but observe concurrent reads");
  }
  {
    auto child = fork();
    expect(child >= 0, "must fork an independent accounting publisher");
    if (child == 0) {
      Store store(root, {0, 0});
      _exit(store.putData(first, "shared") ? 0 : 1);
    }
    Store store(root, {0, 0});
    expect(store.putData(third, "shared"),
           "parent accounting publication must succeed");
    int status = 0;
    expect(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
               WEXITSTATUS(status) == 0,
           "child accounting publication must succeed");
    Store parallel(root, {0, 0});
    std::thread publisher([&] {
      expect(parallel.putData(first, "shared"),
             "threaded accounting publication must succeed");
    });
    expect(parallel.putData(third, "shared"),
           "concurrent accounting publication must succeed");
    publisher.join();
    Store fresh(root, {0, 0});
    fresh.prune();
    expect(
        fresh.data(first, 6).bytes == "shared" &&
            fresh.data(third, 6).bytes == "shared" && fresh.usage().blobs == 1,
        "independent publishers must retain both entries and one shared blob");
  }
  {
    Store store(root, {0, 0});
    std::string error;
    fs::remove(source);
    expect(store.clear(false, error).has_value(), error.c_str());
  }
}
} // namespace

int main() {
  using namespace mettle;
  {
    std::size_t loads = 0;
    Diagnostics diagnostics;
    diagnostics.generated(GenerationRecord(9, [&] {
      ++loads;
      return Generation{9, {1, 2, 4}, "deferred expansion", {}};
    }));
    auto shared = diagnostics;
    expect(
        diagnostics.isGenerated(9) &&
            diagnostics.registeredGenerations().size() == 1 &&
            diagnostics.debugSpan({1, 2, 4}).source == 4 &&
            !diagnostics.syntaxContext({1, 2, 4}) && loads == 0,
        "unrelated source queries must not reconstruct generated provenance");
    expect(diagnostics.debugSpan({0, 1, 9}).source == 4 &&
               shared.debugSpan({0, 1, 9}).source == 4 && loads == 1,
           "shared generated provenance must materialize only once on demand");
  }
  auto digest = [](const std::string &text) {
    packages::Sha256 hash;
    hash.update(text);
    return hash.finish();
  };
  auto sourcePayloads = [](const std::string &bytes) {
    std::size_t offset = 0;
    auto integer = [&] {
      std::uint32_t value = 0;
      for (unsigned shift = 0; shift < 32; shift += 8)
        value |= static_cast<std::uint32_t>(
                     static_cast<unsigned char>(bytes[offset++]))
                 << shift;
      return value;
    };
    auto skip = [&] {
      const auto size = integer();
      offset += size;
    };
    skip();
    skip();
    const auto count = integer();
    std::vector<std::pair<std::size_t, std::size_t>> ranges;
    for (std::size_t i = 0; i < count; ++i) {
      skip();
      const auto size = integer();
      ranges.emplace_back(offset, size);
      offset += size;
      skip();
      skip();
    }
    return ranges;
  };
  auto reseal = [&](std::string &value) {
    auto metadata = value.substr(0, value.size() - 64);
    const auto payloads = sourcePayloads(value);
    for (auto payload = payloads.rbegin(); payload != payloads.rend();
         ++payload)
      metadata.erase(payload->first, payload->second);
    value.replace(value.size() - 64, 64, driver::archiveDigest(metadata));
  };
  expect(digest("abc") ==
             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
         "SHA-256 of one block changed");
  expect(digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
             "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
         "SHA-256 across a padding boundary changed");
  for (const auto &[size, expected] :
       {std::pair{55, "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45"
                      "ae59b598b59"},
        std::pair{56, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82"
                      "a60895f562"},
        std::pair{63, "29af2686fd53374a36b0846694cc342177e428d1647515f078784"
                      "d69cdb9e488"},
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
  auto variant = std::make_shared<const SyntaxContext>(
      SyntaxContext{{"core", "variant"}, {1, 6, first.id}, context->identity});
  auto unbound = std::make_shared<const SyntaxContext>(
      SyntaxContext{{"core"}, {0, 5, first.id}, 0});
  original.generated(
      {generated.id,
       {0, 5, first.id},
       "macro value",
       {{0, 4, {1, 5, first.id}, false, {0, 5, first.id}, "value", context},
        {4, 5, {5, 6, first.id}, false, {0, 5, first.id}, "value", context},
        {5, 6, {6, 7, first.id}, false, {0, 5, first.id}, "value", variant},
        {6, 7, {7, 8, first.id}, false, {0, 5, first.id}, "value", unbound},
        {7,
         9,
         {8, 10, first.id},
         false,
         {0, 5, first.id},
         "value",
         SyntaxContextPtr{}}}});
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
  auto emptyIR = ir::encodeProgram({}, {});
  expect(bool(emptyIR), emptyIR.error.c_str());
  archive.ir = std::move(emptyIR.bytes);
  auto cyclic = original;
  cyclic.generated({first.id, {0, 1, generated.id}, "cycle", {}});
  auto recaptured = archive.sources;
  expect(!recaptured.capture(cyclic, error),
         "recapturing validated sources must still reject cyclic provenance");
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
  std::weak_ptr<const std::string> sourceBacking;
  {
    Diagnostics surviving;
    const char *retainedText = nullptr;
    {
      auto snapshot = std::make_shared<const std::string>(*bytes);
      sourceBacking = snapshot;
      auto retained = driver::decodeLibraryArchive(
          *snapshot, "library-revision", error, snapshot);
      expect(retained.has_value(), error.c_str());
      const auto *source = retained->sources.source(reference->revision);
      const auto offset = snapshot->find("generated");
      expect(offset != std::string::npos, "source slice fixture must exist");
      retainedText = snapshot->data() + offset;
      expect(source && source->text.data() == retainedText,
             "admitted source text must remain a slice of immutable backing");
      Source edited = *source;
      edited.text[0] = 'G';
      expect(edited.text == "Generated" && source->text == generated.text &&
                 source->text.data() == retainedText,
             "editing a copied source must detach its retained text");
      SourceId id = 80;
      expect(retained->sources.mount(
                 surviving, [&] { return id++; }, error),
             error.c_str());
      expect(retained->sources.source(reference->revision)->text.data() ==
                 retainedText,
             "source mounting must not materialize retained text");
    }
    expect(!sourceBacking.expired() &&
               surviving.registeredSources()[1].text.data() == retainedText,
           "diagnostics must retain source backing after archive destruction");
    surviving.error("retained", {2, 3, 80}, "retained source");
    std::ostringstream rendered;
    surviving.print({"fallback.mt", "", 0}, rendered);
    expect(rendered.str().find("core/main.mt:1:3:") != std::string::npos &&
               rendered.str().find("macro value") != std::string::npos,
           "diagnostics must render retained source slices after import ends");
  }
  expect(sourceBacking.expired(),
         "source backing must release after its final diagnostic owner");
  {
    driver::Section retained;
    {
      auto temporary =
          driver::decodeLibraryArchive(*bytes, "library-revision", error);
      expect(temporary.has_value(), error.c_str());
      retained = temporary->types;
    }
    expect(retained == archive.types,
           "retained sections must own their bytes after archive destruction");
    auto moved = std::move(retained);
    expect(moved == archive.types && retained.bytes().empty(),
           "moving a retained section must not leave an unowned byte view");
  }
  {
    SourceText text;
    std::size_t validations = 0;
    {
      auto snapshot = std::make_shared<const std::string>(std::string(80, 'x'));
      text = SourceText::retain(
          *snapshot, snapshot, [&](std::string_view contents) {
            ++validations;
            expect(contents == std::string(80, 'x'),
                   "deferred validation must receive the retained contents");
          });
    }
    const auto shared = text;
    expect(text.size() == 80 && !text.empty() && validations == 0,
           "retained source bounds must not demand diagnostic text");
    SourceText moved;
    moved = std::move(text);
    expect(text.empty(), "moved retained text must not retain an unowned view");
    expect(shared.view() == moved.view() && validations == 1,
           "source copies must share one successful deferred validation");
    moved += std::string_view(moved).substr(1);
    expect(moved == std::string(159, 'x'),
           "self-appending a retained slice must preserve its backing");
    auto owned = moved;
    moved[0] = 'y';
    expect(owned == std::string(159, 'x'),
           "ordinary source-text copies must retain value mutation semantics");
  }
  Diagnostics consumer;
  Source occupied{"consumer.mt", "consumer source", 50};
  {
    Diagnostics::SourceContext registerConsumer(consumer, occupied);
  }
  consumer.makeSyntaxContext({}, {});
  const auto retainedSources = imported->sources;
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
  const auto remappedVariant = consumer.syntaxContext({5, 6, 81});
  const auto remappedUnbound = consumer.syntaxContext({6, 7, 81});
  expect(
      consumer.syntaxContext({4, 5, 81}) == remappedContext &&
          remappedVariant && remappedVariant != remappedContext &&
          remappedVariant->identity == remappedContext->identity &&
          remappedVariant->scope == variant->scope &&
          remappedVariant->definition ==
              (Span{variant->definition.begin, variant->definition.end, 80}) &&
          remappedUnbound && remappedUnbound->identity == 0 &&
          remappedUnbound->definition.source == 80 &&
          !consumer.syntaxContext({7, 9, 81}),
      "deferred provenance must share exact contexts without merging binder "
      "variants or null contexts");
  auto debug = consumer.debugSpan(*span);
  expect(debug.source == 80 && debug.begin == 0,
         "generated debug locations must retain their invocation");
  {
    Diagnostics replay;
    replay.makeSyntaxContext({}, {});
    auto sources = retainedSources;
    SourceId id = 80;
    expect(sources.mount(replay, [&] { return id++; }, error), error.c_str());
    expect(
        replay.syntaxContext(*span) == remappedContext &&
            sources.source(reference->revision) ==
                imported->sources.source(reference->revision) &&
            replay.makeSyntaxContext({}, {})->identity ==
                remappedContext->identity + 1,
        "reused provenance must retain its snapshot and reserve hygiene IDs");
    Diagnostics differentHygiene;
    differentHygiene.makeSyntaxContext({}, {});
    differentHygiene.makeSyntaxContext({}, {});
    auto rebased = retainedSources;
    id = 80;
    expect(rebased.mount(
               differentHygiene, [&] { return id++; }, error),
           error.c_str());
    const auto rebasedContext = differentHygiene.syntaxContext(*span);
    expect(rebasedContext && rebasedContext->identity == 3 &&
               rebasedContext->definition.source == 80,
           "matching source IDs must not reuse a different hygiene allocation");
    auto shifted = retainedSources;
    id = 90;
    expect(shifted.mount(replay, [&] { return id++; }, error), error.c_str());
    const auto shiftedSpan = shifted.resolve(*reference);
    auto shiftedContext = replay.syntaxContext(*shiftedSpan);
    expect(shiftedSpan->source == 91 && shiftedContext &&
               shiftedContext->identity != remappedContext->identity &&
               shiftedContext->definition.source == 90 &&
               replay.debugSpan(*shiftedSpan).source == 90,
           "different source and hygiene allocations must remount provenance");
  }
  {
    Diagnostics surviving;
    {
      auto mutableBytes = *bytes;
      auto temporary =
          driver::decodeLibraryArchive(mutableBytes, "library-revision", error);
      mutableBytes.assign(mutableBytes.size(), 'x');
      SourceId id = 80;
      expect(temporary && temporary->sources.mount(
                              surviving, [&] { return id++; }, error),
             error.c_str());
    }
    expect(surviving.registeredSources()[1].text == generated.text &&
               surviving.syntaxContext(*span)->definition.source == 80 &&
               surviving.debugSpan(*span).source == 80,
           "diagnostic source and provenance must outlive the mounted archive");
  }
  expect(!driver::encodeLibraryArchive(*imported, error),
         "a mounted archive must not encode");
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
  {
    auto changed = first;
    changed.text[0] = 'M';
    driver::LibraryArchive baseline("library-revision");
    driver::LibraryArchive replacement("library-revision");
    expect(baseline.sources.record(first, error).has_value(), error.c_str());
    expect(replacement.sources.record(changed, error).has_value(),
           error.c_str());
    baseline.ir = archive.ir;
    replacement.ir = archive.ir;
    auto before = driver::encodeLibraryArchive(baseline, error);
    auto after = driver::encodeLibraryArchive(replacement, error);
    expect(before && after &&
               before->substr(before->size() - 64) !=
                   after->substr(after->size() - 64),
           "changed source contents must invalidate archive metadata identity");
  }
  auto invalidSource = *bytes;
  auto sourceText = invalidSource.find("generated");
  expect(sourceText != std::string::npos, "fixture must contain source text");
  invalidSource[sourceText] = static_cast<char>(255);
  auto invalid =
      driver::decodeLibraryArchive(invalidSource, "library-revision", error);
  expect(invalid.has_value(), error.c_str());
  Diagnostics invalidDiagnostics;
  SourceId invalidId = 80;
  expect(invalid->sources.mount(
             invalidDiagnostics, [&] { return invalidId++; }, error) &&
             invalid->sources.resolve(*reference).has_value(),
         "unused diagnostic text must not be read while mounting provenance");
  bool invalidRejected = false;
  try {
    invalid->sources.source(reference->revision)->text.view();
  } catch (const metadata::InvalidMetadata &failure) {
    invalidRejected =
        std::string_view(failure.what()).find("source revision") !=
        std::string_view::npos;
  }
  expect(invalidRejected,
         "corrupt retained text must reject before exposing source bytes");
  {
    const auto *source = invalid->sources.source(reference->revision);
    Source edited = *source;
    bool rejected = false;
    try {
      edited.text[0] = 'x';
    } catch (const metadata::InvalidMetadata &) {
      rejected = true;
    }
    expect(
        rejected,
        "editing a copied corrupt source must not bypass deferred integrity");
  }
  for (const auto &field :
       {std::string("library-revision"), first.path, reference->revision}) {
    auto changed = *bytes;
    auto offset = changed.find(field);
    expect(offset != std::string::npos, "source identity fixture must exist");
    changed[offset] ^= 1;
    auto identity = std::string("library-revision");
    if (field == identity)
      identity[0] ^= 1;
    reseal(changed);
    expect(!driver::decodeLibraryArchive(changed, identity, error) &&
               error.find("source revision") != std::string::npos,
           "source revision bindings must reject changed identity, path and "
           "digest");
  }
  auto firstPath = bytes->find(first.path);
  auto secondPath = bytes->find(generated.path, firstPath + first.path.size());
  auto secondRevision = bytes->find(reference->revision, secondPath);
  expect(firstPath != std::string::npos && secondPath != std::string::npos &&
             secondRevision != std::string::npos,
         "source order fixture must contain both complete records");
  auto firstRecord = firstPath - 4;
  auto secondRecord = secondPath - 4;
  auto secondEnd = secondRevision + reference->revision.size() + 68;
  {
    auto invalidEncoding = invalidSource;
    const auto identityOffset = bytes->find("library-revision");
    auto prefix = bytes->substr(identityOffset - 4,
                                std::string("library-revision").size() + 4);
    prefix.append("\1\0\0\0", 4);
    prefix += bytes->substr(secondRecord, sourceText - secondRecord);
    const auto revision = digest(
        prefix + invalidEncoding.substr(sourceText, generated.text.size()));
    invalidEncoding.replace(secondRevision + 68, 64, digest(prefix + revision));
    for (auto offset = invalidEncoding.find(reference->revision);
         offset != std::string::npos;
         offset = invalidEncoding.find(reference->revision, offset + 64))
      invalidEncoding.replace(offset, 64, revision);
    reseal(invalidEncoding);
    auto encoded = driver::decodeLibraryArchive(invalidEncoding,
                                                "library-revision", error);
    expect(encoded.has_value(), error.c_str());
    bool rejected = false;
    try {
      encoded->sources.source(revision)->text.view();
    } catch (const metadata::InvalidMetadata &failure) {
      rejected = std::string_view(failure.what()).find("source encoding") !=
                 std::string_view::npos;
    }
    expect(
        rejected,
        "revision-consistent malformed UTF8 must reject when text is demanded");
  }
  const auto variantScope = bytes->find("variant", secondEnd);
  const auto mappingDescription = bytes->find("value", variantScope + 7);
  expect(variantScope != std::string::npos &&
             mappingDescription != std::string::npos,
         "provenance fixture must contain its context table and mappings");
  for (const auto &[offset, value, message] :
       {std::tuple{secondEnd + 8, 1u, "cyclic generation provenance"},
        std::tuple{secondEnd + 16, static_cast<unsigned>(first.text.size() + 1),
                   "invalid generation origin"},
        std::tuple{variantScope + 7 + 8,
                   static_cast<unsigned>(first.text.size() + 1),
                   "invalid syntax context"},
        std::tuple{mappingDescription + 5, ~0u,
                   "invalid syntax-context reference"}}) {
    auto changed = *bytes;
    for (unsigned shift = 0; shift < 32; shift += 8)
      changed[offset + shift / 8] = static_cast<char>(value >> shift);
    reseal(changed);
    expect(!driver::decodeLibraryArchive(changed, "library-revision", error) &&
               error.find(message) != std::string::npos,
           "unused deferred provenance must reject invalid spans and cycles at "
           "admission");
  }
  auto reordered = bytes->substr(0, firstRecord) +
                   bytes->substr(secondRecord, secondEnd - secondRecord) +
                   bytes->substr(firstRecord, secondRecord - firstRecord) +
                   bytes->substr(secondEnd);
  reseal(reordered);
  expect(!driver::decodeLibraryArchive(reordered, "library-revision", error) &&
             error.find("source revision") != std::string::npos,
         "source revisions must bind each source's archive ordinal");
  {
    ir::Program program;
    for (const auto &[name, literal] :
         {std::pair{"first", "17392451"}, std::pair{"other", "19613861"}}) {
      ir::Instruction value{};
      value.op = ir::Op::Constant;
      value.result = {0, Type::I32};
      value.text = literal;
      program.functions.push_back(
          {name,
           Type::I32,
           0,
           {},
           {{{value}, {ir::Exit::Return, {0, Type::I32}}}},
           1});
    }
    metadata::EncodeReferences encode;
    encode.type = [](Type type) { return std::optional{type.index()}; };
    encode.symbol = [](metadata::SymbolKind, std::uint32_t index) {
      return std::optional{"function/" + std::to_string(index)};
    };
    encode.source = [&](Span) {
      return archive.sources.reference({0, 0, first.id});
    };
    program.functions.edit(1).name.append(std::size_t{1} << 20, 'n');
    auto encodedIR = ir::encodeProgram(program, encode);
    expect(bool(encodedIR), encodedIR.error.c_str());
    auto layout = ir::programLayout(encodedIR.bytes);
    expect(layout && layout.bodies.size() == 2,
           "IR framing must identify both independently sealed bodies");
    auto deferred = archive;
    deferred.ir = std::move(encodedIR.bytes);
    deferred.macros.append(std::size_t{1} << 20, 'm');
    auto sealed = driver::encodeLibraryArchive(deferred, error);
    expect(sealed.has_value(), error.c_str());
    const auto irOffset = sealed->size() - 64 - deferred.ir.size();
    auto metadata = sealed->substr(0, sealed->size() - 64);
    for (auto body = layout.bodies.rbegin(); body != layout.bodies.rend();
         ++body)
      metadata.erase(irOffset + body->offset, body->size);
    const auto sourceRanges = sourcePayloads(*sealed);
    for (auto source = sourceRanges.rbegin(); source != sourceRanges.rend();
         ++source)
      metadata.erase(source->first, source->second);
    expect(driver::archiveDigest(metadata) ==
               sealed->substr(sealed->size() - 64),
           "fragmented parallel metadata hashing must preserve logical chunks");
    auto replacementProgram = program;
    replacementProgram.functions.edit(1).blocks[0].instructions[0].text =
        "19613862";
    auto replacementIR = ir::encodeProgram(replacementProgram, encode);
    expect(bool(replacementIR), replacementIR.error.c_str());
    auto replacementArchive = deferred;
    replacementArchive.ir = std::move(replacementIR.bytes);
    auto replacement = driver::encodeLibraryArchive(replacementArchive, error);
    expect(
        replacement && replacement->substr(replacement->size() - 64) !=
                           sealed->substr(sealed->size() - 64),
        "changed body commitments must invalidate resident archive identity");
    auto changed = *sealed;
    const auto body = layout.bodies[1];
    const auto literal =
        std::search(deferred.ir.bytes().begin() + body.offset,
                    deferred.ir.bytes().begin() + body.offset + body.size,
                    std::string_view("19613861").begin(),
                    std::string_view("19613861").end());
    expect(literal != deferred.ir.bytes().begin() + body.offset + body.size,
           "body-only string must be stored inside its deferred payload");
    const auto literalOffset =
        static_cast<std::size_t>(literal - deferred.ir.bytes().begin());
    changed[irOffset + literalOffset] ^= 1;
    auto snapshot = std::make_shared<const std::string>(std::move(changed));
    auto admitted = driver::decodeLibraryArchive(*snapshot, "library-revision",
                                                 error, snapshot);
    expect(admitted.has_value(), error.c_str());
    metadata::DecodeReferences decode;
    decode.type = [](std::uint32_t index) -> std::optional<Type> {
      for (auto type : {Type::Unknown, Type::Never, Type::I32})
        if (type.index() == index)
          return type;
      return std::nullopt;
    };
    decode.symbol = [](metadata::SymbolKind,
                       std::string_view name) -> std::optional<std::uint32_t> {
      for (std::uint32_t i = 0; i < 2; ++i)
        if (name == "function/" + std::to_string(i))
          return i;
      return std::nullopt;
    };
    decode.source = [sources = admitted->sources](const auto &reference) {
      return sources.resolve(reference);
    };
    auto references =
        std::make_shared<const metadata::DecodeReferences>(decode);
    auto pending =
        ir::decodeProgramLazy(admitted->ir, *references, true, references,
                              admitted->backing, admitted->verifyIRBody);
    expect(bool(pending), pending.error.c_str());
    admitted.reset();
    snapshot.reset();
    auto firstBody =
        pending.lazyFunctions->load(0, pending.program.functions[0], decode);
    expect(bool(firstBody), firstBody.error.c_str());
    auto corruptBody =
        pending.lazyFunctions->load(1, pending.program.functions[1], decode);
    expect(!corruptBody &&
               corruptBody.error == "IR function body checksum mismatch",
           "unused body corruption must reject before demanded decoding");
    changed = *sealed;
    changed[irOffset + layout.bodies[0].offset - 1] ^= 1;
    expect(!driver::decodeLibraryArchive(changed, "library-revision", error),
           "header corruption must reject before deferred body use");
    changed = *sealed;
    const auto digest =
        driver::archiveDigest({reinterpret_cast<const char *>(
                                   deferred.ir.bytes().data() + body.offset),
                               body.size});
    const auto sealOffset = changed.find(digest);
    expect(sealOffset != std::string::npos,
           "body commitment must be embedded in query metadata");
    changed[sealOffset] = changed[sealOffset] == '0' ? '1' : '0';
    expect(!driver::decodeLibraryArchive(changed, "library-revision", error) &&
               error.find("metadata checksum") != std::string::npos,
           "body commitment corruption must reject at archive admission");
  }
  {
    Source source{"checked-seal.mt",
                  "const fn first(): i32 { 17392451 }\n"
                  "const fn other(): i32 { 19613861 }\n",
                  0};
    Diagnostics diagnostics;
    auto checked = check(parse(source, diagnostics), diagnostics, false);
    expect(checked.has_value(), "checked payload fixture must type-check");
    auto deferred = archive;
    expect(deferred.sources.capture(diagnostics, error), error.c_str());
    std::map<std::uint32_t, Type> typeReferences;
    metadata::EncodeReferences encode;
    encode.type = [&](Type type) {
      typeReferences.emplace(type.index(), type);
      return std::optional{type.index()};
    };
    encode.source = [&](Span span) { return deferred.sources.reference(span); };
    encode.symbol = [](metadata::SymbolKind kind, std::uint32_t index) {
      return std::optional{std::to_string(static_cast<unsigned>(kind)) + "/" +
                           std::to_string(index)};
    };
    auto contracts = exportLibraryDeclarations(*checked, encode);
    expect(bool(contracts), contracts.error.c_str());
    deferred.declarations = std::move(contracts.contracts);
    auto layout = declarationPayloadLayout(deferred.declarations);
    expect(layout && layout.payloads.size() == 2,
           "declaration codec must index independently sealed function blocks");
    auto sealed = driver::encodeLibraryArchive(deferred, error);
    expect(sealed.has_value(), error.c_str());
    auto changed = *sealed;
    const auto declarationsOffset = changed.find(
        {reinterpret_cast<const char *>(deferred.declarations.bytes().data()),
         deferred.declarations.size()});
    expect(declarationsOffset != std::string::npos,
           "checked declaration section must be embedded unchanged");
    const auto payload = layout.payloads[1];
    expect(payload.size != 0, "checked function block must not be empty");
    changed[declarationsOffset + payload.offset] ^= 0x40;
    auto snapshot = std::make_shared<const std::string>(std::move(changed));
    auto admitted = driver::decodeLibraryArchive(*snapshot, "library-revision",
                                                 error, snapshot);
    expect(admitted.has_value(), error.c_str());
    metadata::DecodeReferences decode;
    decode.type = [types = std::move(typeReferences)](
                      std::uint32_t index) -> std::optional<Type> {
      auto found = types.find(index);
      return found == types.end() ? std::nullopt : std::optional{found->second};
    };
    decode.source = [sources = admitted->sources](const auto &reference) {
      return sources.resolve(reference);
    };
    decode.symbol = [](metadata::SymbolKind kind,
                       std::string_view name) -> std::optional<std::uint32_t> {
      for (std::uint32_t i = 0; i < 2; ++i)
        if (name == std::to_string(static_cast<unsigned>(kind)) + "/" +
                        std::to_string(i))
          return i;
      return std::nullopt;
    };
    auto references =
        std::make_shared<const metadata::DecodeReferences>(decode);
    auto types = std::make_shared<TypeStore>(*checked->typeStore());
    auto pending = importLibraryDeclarations(
        admitted->declarations, types, *references, nullptr, admitted->backing,
        references, metadata::ValidationMode::OnDemand, {},
        admitted->verifyDeclarationPayload);
    expect(bool(pending), pending.error.c_str());
    admitted.reset();
    snapshot.reset();
    const auto &firstFunction =
        pending.declarations->functions.at(0)->materialize();
    expect(firstFunction.body != nullptr,
           "checked fixture must retain its compile-time expression");
    firstFunction.body->materialize();
    expect(firstFunction.body->syntax.get() != nullptr,
           "demanded checked expression must outlive its archive and caller");
    bool rejected = false;
    try {
      pending.declarations->functions.at(1)->materialize();
    } catch (const metadata::InvalidMetadata &failure) {
      rejected =
          std::string_view(failure.what()).find("payload integrity mismatch") !=
          std::string::npos;
    }
    expect(rejected,
           "unused checked payload corruption must reject before demanded use");
    changed = *sealed;
    changed[declarationsOffset + layout.payloads[0].offset - 1] ^= 1;
    expect(!driver::decodeLibraryArchive(changed, "library-revision", error),
           "checked summary corruption must reject at archive admission");
    const auto commitment = driver::archiveDigest(
        {reinterpret_cast<const char *>(deferred.declarations.bytes().data() +
                                        payload.offset),
         payload.size});
    changed = *sealed;
    const auto sealOffset = changed.find(commitment);
    expect(sealOffset != std::string::npos,
           "checked payload commitment must be embedded in query metadata");
    changed[sealOffset] = changed[sealOffset] == '0' ? '1' : '0';
    expect(!driver::decodeLibraryArchive(changed, "library-revision", error) &&
               error.find("metadata checksum") != std::string::npos,
           "checked commitment corruption must reject at archive admission");
  }
  auto before = consumer.registeredSources().size();
  auto collision =
      driver::decodeLibraryArchive(*bytes, "library-revision", error);
  expect(collision &&
             !collision->sources.mount(
                 consumer, [] { return SourceId{50}; }, error) &&
             consumer.registeredSources().size() == before,
         "source ID collision must reject before registering anything");
  namespace fs = std::filesystem;
  auto root = fs::current_path() /
              ("mettle-library-archive-" + std::to_string(getpid()));
  expect(fs::create_directory(root), "must create a private test store");
  struct Cleanup {
    fs::path root;
    ~Cleanup() {
      std::error_code error;
      fs::remove_all(root, error);
    }
  } cleanup{root};
  testStoreAccounting(root / "accounting-test");
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
  {
    std::optional<driver::LibraryArchive> retained;
    auto mapped = store.mapped(key, bytes->size(), [&](const auto &mapping) {
      retained = driver::decodeLibraryArchive(
          mapping->bytes(), "library-revision", error, mapping);
      return retained.has_value();
    });
    expect(mapped.status == packages::Store::Lookup::Hit && retained,
           "archive admission must retain the Store mapping");
    const auto *source = retained->sources.source(reference->revision);
    expect(source &&
               reinterpret_cast<const char *>(retained->ir.bytes().data()) ==
                   mapped.mapping->bytes().data() +
                       mapped.mapping->bytes().size() - 64 -
                       retained->ir.size() &&
               source->text.data() ==
                   mapped.mapping->bytes().data() +
                       mapped.mapping->bytes().find("generated"),
           "mapped admission must retain source and section slices");
    Source surviving = *source;
    auto section = retained->ir;
    std::weak_ptr<const packages::Store::Mapping> lifetime = mapped.mapping;
    mapped.mapping.reset();
    retained.reset();
    expect(store.putData(key, *bytes),
           "same-content atomic publication must preserve mapped readers");
    auto replacement = archive;
    replacement.macros += "replacement";
    auto changed = driver::encodeLibraryArchive(replacement, error);
    expect(changed && store.putData(key, *changed) &&
               store.putData(other, *changed),
           "new archive publication must preserve old mapped readers");
    store.prune();
    expect(
        !lifetime.expired() && surviving.text == generated.text &&
            section == archive.ir,
        "source and section owners must survive blob replacement and pruning");
    surviving.text = "";
    section = std::vector<std::uint8_t>{};
    expect(lifetime.expired(),
           "mapped archive storage must release after its final slice owner");
    expect(store.putData(key, *bytes) && store.putData(other, *bytes),
           "must restore original entries after mapped lifetime regression");
  }
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
