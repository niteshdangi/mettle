#include "expansion/macros.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <string>

namespace {
using namespace mettle;
using namespace mettle::expansion;
int failures = 0;
void expect(bool condition, const char *description) {
  if (!condition) {
    std::cerr << "FAILED: " << description << '\n';
    ++failures;
  }
}

Source librarySource(SourceId id) {
  return {"macros.mt",
          "pub macro choose {\n"
          "  ($arg:expr) => {{ let temporary = 41; $arg + temporary }};\n"
          "}\n"
          "macro hidden { () => { 7 }; }\n"
          "pub macro support { () => { hidden!() }; }\n"
          "pub macro at_callsite { () => { $capture(temporary) }; }\n"
          "pub macro repeated { ($($x:expr),*) => { ($($x),*) }; }\n"
          "pub module bridge {\n"
          "  pub import super.choose as exposed;\n"
          "  pub import super.hidden as concealed;\n"
          "  import super.choose as local;\n"
          "  pub macro nested { () => { local!(19) }; }\n"
          "}\n"
          "module later;\n",
          id};
}

std::string identity(const Source &source) {
  return "package:dep/" + source.path + "@revision-one";
}

std::optional<MacroLibrary> extract(SourceId id) {
  Diagnostics diagnostics;
  auto source = librarySource(id);
  SourceId generated = id + 1;
  MacroLibrary library;
  expandMacros(
      source, diagnostics, [&] { return generated++; }, nullptr, {"dep"}, {},
      nullptr, {}, nullptr, &library, identity);
  expect(diagnostics.empty(), "valid macro library extracts");
  if (!diagnostics.empty()) {
    diagnostics.print(source, std::cerr);
    return std::nullopt;
  }
  return library;
}

Source overlapSource(SourceId id) {
  return {"reuse.mt",
          "pub import dep.bridge.exposed as exported;\n"
          "pub macro own { () => {{ let reused = 3; reused }}; }\n"
          "fn index_dependency() { dep.choose!(0) }\n",
          id};
}

std::optional<MacroLibrary> extractOverlap() {
  Diagnostics diagnostics;
  SourceId next = 12000;
  MacroModuleProvider provider =
      [](const std::vector<std::string> &path,
         const std::vector<std::string> &) -> std::optional<MacroModuleSource> {
    if (path.empty() || path.front() != "dep")
      return std::nullopt;
    return MacroModuleSource{librarySource(11000), path, {"dep"}, {}};
  };
  MacroLibrary library;
  expandMacros(
      overlapSource(10000), diagnostics, [&] { return next++; }, nullptr,
      {"reuse"}, provider, nullptr, {}, nullptr, &library, identity);
  expect(diagnostics.empty(),
         "independent archive extracts dependency closure");
  if (!diagnostics.empty())
    return std::nullopt;
  return library;
}

template <class Nodes, class Visit>
void visitTokens(Nodes &nodes, const Visit &visit) {
  for (auto &node : nodes) {
    visit(node.token);
    if (node.separator)
      visit(*node.separator);
    visitTokens(node.body, visit);
  }
}

void reorderReferences(MacroLibrary &library) {
  std::reverse(library.sources.begin(), library.sources.end());
  std::reverse(library.contexts.begin(), library.contexts.end());
  auto location = [&](MacroLocation &span) {
    if (span.source != UINT32_MAX)
      span.source =
          static_cast<std::uint32_t>(library.sources.size() - 1 - span.source);
  };
  auto token = [&](MacroToken &value) {
    location(value.origin);
    if (value.context)
      value.context = static_cast<std::uint32_t>(library.contexts.size() - 1 -
                                                 *value.context);
  };
  for (auto &context : library.contexts)
    location(context.definition);
  for (auto &definition : library.definitions) {
    location(definition.location);
    for (auto &rule : definition.rules) {
      visitTokens(rule.matcher, token);
      visitTokens(rule.expansion, token);
    }
  }
  for (auto &import : library.imports)
    location(import.location);
  std::reverse(library.definitions.begin(), library.definitions.end());
  std::reverse(library.imports.begin(), library.imports.end());
  std::reverse(library.indexedModules.begin(), library.indexedModules.end());
}

std::shared_ptr<const MacroLibrary> roundTrip(const MacroLibrary &library) {
  Diagnostics diagnostics;
  auto bytes = encodeMacros(library, diagnostics);
  auto decoded = bytes ? decodeMacros(*bytes, diagnostics) : std::nullopt;
  expect(decoded && diagnostics.empty(),
         "overlap fixture is structurally valid");
  return decoded ? std::make_shared<const MacroLibrary>(std::move(*decoded))
                 : nullptr;
}

void overlappingConsumer(const std::shared_ptr<const MacroLibrary> &first,
                         const MacroLibrary &second, bool accepted,
                         const char *description, bool reverse = false) {
  auto incoming = roundTrip(second);
  if (!incoming)
    return;
  Diagnostics diagnostics;
  SourceId next = 20000;
  unsigned loaded = 0;
  std::optional<SourceId> firstDependency;
  std::map<SourceId, std::string> logicalSources;
  MacroModuleProvider provider = [&](const std::vector<std::string> &path,
                                     const std::vector<std::string> &)
      -> std::optional<MacroModuleSource> {
    if (path.empty() || (path.front() != "dep" && path.front() != "reuse"))
      return std::nullopt;
    ++loaded;
    MacroModuleSource result;
    result.path = path;
    result.sourcePath = {path.front()};
    result.compiled = path.front() == "dep" ? first : incoming;
    result.remapSources =
        [&](const MacroSource &record) -> std::optional<SourceId> {
      auto source = record.path.ends_with("macros.mt") ? librarySource(next++)
                                                       : overlapSource(next++);
      source.path = record.path;
      if (source.text.size() != record.bytes)
        return std::nullopt;
      if (!firstDependency && record.path.ends_with("macros.mt"))
        firstDependency = source.id;
      logicalSources.emplace(source.id, record.identity);
      Diagnostics::SourceContext registered(diagnostics, source);
      return source.id;
    };
    return result;
  };
  auto body = reverse
                  ? "fn main() { let temporary = 4; "
                    "(reuse.exported!(temporary), dep.bridge.exposed!(5), "
                    "dep.support!(), dep.bridge.nested!(), reuse.own!()) }\n"
                  : "fn main() { let temporary = 4; "
                    "(dep.bridge.exposed!(temporary), reuse.exported!(5), "
                    "dep.support!(), dep.bridge.nested!(), reuse.own!()) }\n";
  MacroLibrary exported;
  auto identify = [&](const Source &source) {
    auto known = logicalSources.find(source.id);
    return known == logicalSources.end() ? std::string{} : known->second;
  };
  auto output = expandMacros(
      {"overlap.mt", body, 19999}, diagnostics, [&] { return next++; }, nullptr,
      {}, provider, nullptr, {}, nullptr, accepted ? &exported : nullptr,
      identify);
  if (!accepted) {
    expect(!output && !diagnostics.empty() && loaded >= 2, description);
    return;
  }
  expect(output && diagnostics.empty() && loaded >= 2, description);
  if (!output)
    return;
  auto portable = roundTrip(exported);
  if (portable) {
    std::optional<std::uint32_t> dependencyContext, ownContext;
    for (const auto &definition : portable->definitions) {
      auto *context = definition.name == "choose" ? &dependencyContext
                      : definition.name == "own"  ? &ownContext
                                                  : nullptr;
      if (context)
        visitTokens(definition.rules.front().expansion,
                    [&](const MacroToken &token) {
                      if (!*context && token.context)
                        *context = token.context;
                    });
    }
    expect(dependencyContext && ownContext && dependencyContext == ownContext,
           "re-export preserves shared hygiene across old and new definitions");
  }
  auto tokens = tokenize(*output, diagnostics);
  bool retained = false;
  for (const auto &token : tokens) {
    auto text = output->text.substr(token.span.begin,
                                    token.span.end - token.span.begin);
    auto context = diagnostics.syntaxContext(token.span);
    if (text == "temporary" && context && context->identity != 0)
      retained |=
          firstDependency && context->definition.source == *firstDependency;
  }
  auto parsed = parse(*output, diagnostics);
  expect(retained && diagnostics.empty() && !parsed.functions.empty(),
         "deduplication retains first admitted hygiene/provenance and syntax");
}

void rechecksum(std::string &bytes) {
  std::uint32_t crc = UINT32_MAX;
  for (std::size_t i = 0; i + 4 < bytes.size(); ++i) {
    crc ^= static_cast<unsigned char>(bytes[i]);
    for (unsigned bit = 0; bit < 8; ++bit)
      crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
  }
  crc = ~crc;
  for (unsigned i = 0; i < 4; ++i)
    bytes[bytes.size() - 4 + i] = static_cast<char>(crc >> (8 * i));
}

void rejected(const std::string &bytes, const char *description) {
  Diagnostics diagnostics;
  expect(!decodeMacros(bytes, diagnostics) && !diagnostics.empty(),
         description);
}

void consumer(const std::shared_ptr<const MacroLibrary> &library,
              SourceId remapped, const std::string &body, bool accepted,
              bool hygiene = false) {
  Diagnostics diagnostics;
  SourceId generated = remapped + 100;
  unsigned requests = 0, remaps = 0;
  MacroModuleProvider provider = [&](const std::vector<std::string> &path,
                                     const std::vector<std::string> &)
      -> std::optional<MacroModuleSource> {
    if (path.empty() || path.front() != "dep")
      return std::nullopt;
    ++requests;
    MacroModuleSource result;
    result.source = {"must-not-be-lexed.mt", "\"unterminated", remapped + 1};
    result.path = path;
    result.sourcePath = {"dep"};
    result.compiled = library;
    result.remapSources =
        [&](const MacroSource &source) -> std::optional<SourceId> {
      auto mapped = librarySource(remapped);
      if (source.identity != identity(mapped) ||
          source.bytes != mapped.text.size())
        return std::nullopt;
      ++remaps;
      Diagnostics::SourceContext registered(diagnostics, mapped);
      return mapped.id;
    };
    return result;
  };
  Source source{"consumer.mt", body, remapped + 2};
  auto expanded = expandMacros(
      source, diagnostics, [&] { return generated++; }, nullptr, {}, provider);
  if (!accepted) {
    expect(!expanded && !diagnostics.empty(), "invalid import is rejected");
    return;
  }
  expect(expanded.has_value() && diagnostics.empty(),
         "consumer expands compiled rules without library source");
  expect(requests != 0 && remaps == library->sources.size(),
         "compiled source revisions remap exactly once");
  if (!expanded)
    return;
  auto tokens = tokenize(*expanded, diagnostics);
  bool authored = false, argument = false, support = false;
  std::optional<Span> definitionToken;
  for (const auto &token : tokens) {
    auto text = expanded->text.substr(token.span.begin,
                                      token.span.end - token.span.begin);
    auto context = diagnostics.syntaxContext(token.span);
    if (text == "7" && context && context->identity != 0 &&
        context->definition.source == remapped)
      support = true;
    if (text != "temporary")
      continue;
    if (context && context->identity != 0) {
      authored |= context->scope == std::vector<std::string>{"dep"} &&
                  context->definition.source == remapped;
      definitionToken = token.span;
    } else if (context && context->scope.empty() &&
               context->definition.source == source.id) {
      argument = true;
    }
  }
  if (hygiene)
    expect(authored && argument,
           "template bindings retain remapped definition-site hygiene");
  auto parsed = parse(*expanded, diagnostics);
  expect(diagnostics.empty() && !parsed.functions.empty(),
         "compiled expansion remains valid consumer syntax");
  if (body.find("at_callsite") != std::string::npos) {
    expect(argument, "explicit capture retains the importing caller's context");
    expect(support, "nested macro can call an imported private support macro");
  }
  if (hygiene && definitionToken) {
    expect(diagnostics.debugSpan(*definitionToken).source == source.id,
           "imported macro debug provenance names the consumer invocation");
    diagnostics.error("type", *definitionToken, "provenance probe");
    std::ostringstream rendered;
    diagnostics.print(source, rendered);
    expect(rendered.str().find("macros.mt:") != std::string::npos &&
               rendered.str().find("consumer.mt:") != std::string::npos,
           "diagnostics retain remapped template and invocation provenance");
  }
}
void nativeShadowing(const std::string &root, bool compiled) {
  Source native{"native.mt", "pub macro remote { () => { 19 }; }\n", 51000};
  Diagnostics exportedDiagnostics;
  SourceId next = 52000;
  MacroLibrary archive;
  expandMacros(
      native, exportedDiagnostics, [&] { return next++; }, nullptr, {root}, {},
      nullptr, {}, nullptr, &archive, identity);
  auto imported = roundTrip(archive);
  expect(imported && exportedDiagnostics.empty(),
         "native shadow fixture exports");
  if (!imported)
    return;
  struct Case {
    std::string modules, invocation;
    bool accepted, local, sourceProvider, nativeProvider;
  };
  const Case cases[]{
      {"module " + root + " { pub macro remote { () => { 7 }; } }\n",
       root + ".remote!()", true, true, false, false},
      {"module " + root + " {}\n", root + ".remote!()", false, false, false,
       false},
      {"module " + root + " {}\nmodule sibling {\n", root + ".remote!()", false,
       false, false, false},
      {"module " + root + ";\n", root + ".remote!()", true, true, true, false},
      {"module " + root + " { pub module child; }\n", root + ".child.remote!()",
       true, true, true, false},
      {"@cfg(false)\nmodule " + root + " {}\n", root + ".remote!()", true,
       false, false, true},
      {"module sibling {\n", root + ".remote!()", true, false, false, true},
      {"@cfg(false)\nmodule " + root + ";\n", root + ".remote!()", true, false,
       false, true},
      {"@cfg(false)\nmodule " + root + " {}\nimport " + root +
           ".remote as selected;\n",
       "selected!()", true, false, false, true},
  };
  for (const auto &test : cases) {
    Diagnostics diagnostics;
    unsigned sourceCalls = 0, nativeCalls = 0;
    MacroModuleProvider sourceProvider =
        [&](const std::vector<std::string> &path,
            const std::vector<std::string> &)
        -> std::optional<MacroModuleSource> {
      ++sourceCalls;
      return MacroModuleSource{
          {"local.mt", "pub macro remote { () => { 7 }; }\n", next++},
          path,
          path,
          {}};
    };
    MacroModuleProvider nativeProvider =
        [&](const std::vector<std::string> &path,
            const std::vector<std::string> &)
        -> std::optional<MacroModuleSource> {
      ++nativeCalls;
      MacroModuleSource result{native, path, {root}, {}};
      if (compiled) {
        result.compiled = imported;
        result.remapSources =
            [&](const MacroSource &) -> std::optional<SourceId> {
          Diagnostics::SourceContext registered(diagnostics, native);
          return native.id;
        };
      }
      return result;
    };
    Source source{"shadow.mt",
                  test.modules + "fn main() { " + test.invocation + " }\n" +
                      (test.modules.ends_with("sibling {\n") ? "}\n" : ""),
                  next++};
    Configuration configuration;
    auto expanded = expandMacros(
        source, diagnostics, [&] { return next++; }, nullptr, {},
        sourceProvider, nullptr, nativeProvider, &configuration);
    expect(diagnostics.empty(),
           "native shadow discovery does not produce expansion errors");
    expect((sourceCalls != 0) == test.sourceProvider &&
               (nativeCalls != 0) == test.nativeProvider,
           "native shadowing selects only the owning macro provider");
    if (test.accepted) {
      expect(expanded && expanded->text.find(test.local ? "7" : "19") !=
                             std::string::npos,
             "native shadowing expands the selected source or compiled rule");
      if (expanded)
        parse(*expanded, diagnostics);
      expect(diagnostics.empty(), "native shadow expansion parses");
    } else {
      parse(expanded ? *expanded : source, diagnostics);
      expect(!diagnostics.empty(),
             "missing shadowed macro remains invalid consumer syntax");
    }
  }
}
} // namespace

int main() {
  for (const auto *root : {"core", "alloc", "std"}) {
    nativeShadowing(root, false);
    nativeShadowing(root, true);
  }
  auto library = extract(17);
  auto other = extract(117);
  if (!library || !other)
    return 1;
  Diagnostics diagnostics;
  auto bytes = encodeMacros(*library, diagnostics);
  auto otherBytes = encodeMacros(*other, diagnostics);
  expect(bytes && otherBytes && *bytes == *otherBytes,
         "wire identities do not depend on exporter SourceIds");
  if (!bytes)
    return 1;
  auto decoded = decodeMacros(*bytes, diagnostics);
  expect(decoded.has_value() && diagnostics.empty(),
         "macro archive round-trips");
  if (!decoded)
    return 1;
  auto imported = std::make_shared<const MacroLibrary>(std::move(*decoded));
  consumer(imported, 901,
           "import dep.bridge.exposed as picked;\n"
           "fn main() { let temporary = 5; picked!(temporary) }\n",
           true, true);
  consumer(imported, 1901,
           "fn main() { let temporary = 8; "
           "(dep.at_callsite!(), dep.support!(), dep.repeated!(1, 2, 3)) }\n",
           true);
  consumer(imported, 2901, "fn main() { dep.hidden!() }\n", false);
  consumer(imported, 3001, "fn main() { dep.bridge.concealed!() }\n", false);

  auto overlapping = extractOverlap();
  if (overlapping) {
    auto shared = *imported;
    for (auto &context : shared.contexts)
      context.hygienic = true;
    for (auto &context : overlapping->contexts)
      context.hygienic = true;
    std::optional<MacroToken> sharedToken;
    for (const auto &definition : overlapping->definitions)
      if (definition.name == "choose")
        visitTokens(definition.rules.front().expansion,
                    [&](const MacroToken &token) {
                      if (!sharedToken && token.context)
                        sharedToken = token;
                    });
    if (sharedToken)
      for (auto &definition : overlapping->definitions)
        if (definition.name == "own") {
          for (auto &rule : definition.rules)
            visitTokens(rule.expansion, [&](MacroToken &token) {
              token.context = sharedToken->context;
            });
          definition.rules.front().expansion.front().token.origin =
              sharedToken->origin;
        }
    reorderReferences(*overlapping);
    for (auto &source : overlapping->sources)
      source.path = "relocated/" + source.path;
    auto first = roundTrip(shared);
    if (first) {
      overlappingConsumer(first, *overlapping, true,
                          "equal independent dependency closures deduplicate");
      overlappingConsumer(first, *overlapping, true,
                          "equal overlaps deduplicate in reverse load order",
                          true);

      auto changedRevision = *overlapping;
      for (auto &source : changedRevision.sources)
        if (source.path.ends_with("macros.mt"))
          source.identity += "-revision-two";
      overlappingConsumer(first, changedRevision, false,
                          "overlap rejects a different source revision");

      auto changedOwner = *overlapping;
      for (auto &source : changedOwner.sources)
        if (source.path.ends_with("macros.mt"))
          source.identity = "other-package/" + source.identity;
      overlappingConsumer(first, changedOwner, false,
                          "overlap rejects a different logical package owner");

      auto changedModule = *overlapping;
      changedModule.indexedModules.push_back("dep::bridge");
      overlappingConsumer(
          first, changedModule, false,
          "overlap rejects changed definition module ownership");

      auto changedBody = *overlapping;
      for (auto &definition : changedBody.definitions)
        if (definition.name == "choose")
          for (auto &rule : definition.rules)
            visitTokens(rule.expansion, [](MacroToken &token) {
              if (token.kind == TokenKind::Integer && token.text == "41")
                token.text = "42";
            });
      overlappingConsumer(first, changedBody, false,
                          "overlap rejects a changed rule body");

      auto changedVisibility = *overlapping;
      for (auto &definition : changedVisibility.definitions)
        if (definition.name == "choose")
          definition.publicItem = false;
      overlappingConsumer(first, changedVisibility, false,
                          "overlap rejects changed definition visibility");

      auto changedReexport = *overlapping;
      for (auto &import : changedReexport.imports)
        if (import.alias == "exposed")
          import.publicItem = false;
      overlappingConsumer(first, changedReexport, false,
                          "overlap rejects changed reexport visibility");

      auto missingImportOrigin = *overlapping;
      for (auto &import : missingImportOrigin.imports)
        if (import.alias == "local")
          import.location = {};
      overlappingConsumer(first, missingImportOrigin, false,
                          "overlap rejects erased private-import provenance");

      auto removedSupport = *overlapping;
      std::erase_if(removedSupport.definitions, [](const auto &definition) {
        return definition.name == "hidden";
      });
      overlappingConsumer(first, removedSupport, false,
                          "overlap rejects a removed private support macro");

      auto changedDeclarations = *overlapping;
      changedDeclarations.declaredModules.clear();
      overlappingConsumer(
          first, changedDeclarations, false,
          "overlap rejects changed external module declarations");

      auto changedBinders = *overlapping;
      bool split = false;
      for (auto &definition : changedBinders.definitions)
        if (definition.name == "choose")
          for (auto &rule : definition.rules)
            visitTokens(rule.expansion, [&](MacroToken &token) {
              if (split || token.text != "temporary" || !token.context)
                return;
              changedBinders.contexts.push_back(
                  changedBinders.contexts[*token.context]);
              token.context = static_cast<std::uint32_t>(
                  changedBinders.contexts.size() - 1);
              split = true;
            });
      expect(split, "fixture creates a distinct hygienic binder partition");
      overlappingConsumer(first, changedBinders, false,
                          "overlap rejects changed hygiene sharing");
    }
  }

  Diagnostics transitive;
  Source bridge{"bridge.mt", "pub import dep.choose as exported;\n", 6000};
  MacroLibrary bridgeLibrary;
  SourceId bridgeNext = 6100;
  expandMacros(
      bridge, transitive, [&] { return bridgeNext++; }, nullptr, {"bridge"}, {},
      nullptr, {}, nullptr, &bridgeLibrary, identity);
  auto bridgeBytes = encodeMacros(bridgeLibrary, transitive);
  auto bridgeDecoded =
      bridgeBytes ? decodeMacros(*bridgeBytes, transitive) : std::nullopt;
  expect(bridgeDecoded.has_value() && transitive.empty(),
         "source-free reexport module round-trips independently");
  if (bridgeDecoded) {
    auto reexports =
        std::make_shared<const MacroLibrary>(std::move(*bridgeDecoded));
    unsigned loaded = 0;
    MacroModuleProvider provider = [&](const std::vector<std::string> &path,
                                       const std::vector<std::string> &)
        -> std::optional<MacroModuleSource> {
      if (path.empty() || (path.front() != "dep" && path.front() != "bridge"))
        return std::nullopt;
      ++loaded;
      MacroModuleSource result;
      result.path = path;
      result.sourcePath = {path.front()};
      result.compiled = path.front() == "dep" ? imported : reexports;
      result.remapSources =
          [&](const MacroSource &source) -> std::optional<SourceId> {
        auto mapped = source.path == bridge.path ? bridge : librarySource(6001);
        Diagnostics::SourceContext registered(transitive, mapped);
        return mapped.id;
      };
      return result;
    };
    auto output = expandMacros(
        {"transitive.mt", "fn main() { bridge.exported!(9) }\n", 6002},
        transitive, [&] { return bridgeNext++; }, nullptr, {}, provider);
    expect(output && transitive.empty() && loaded == 2,
           "reexports load another compiled library without dependency source");
  }

  Diagnostics sourceProviderDiagnostics;
  SourceId sourceNext = 5000;
  MacroModuleProvider sourceProvider =
      [](const std::vector<std::string> &path,
         const std::vector<std::string> &) -> std::optional<MacroModuleSource> {
    if (path.empty() || path.front() != "dep")
      return std::nullopt;
    return MacroModuleSource{librarySource(4900), path, {"dep"}, {}};
  };
  auto fromSource = expandMacros(
      {"legacy.mt", "fn main() { dep.choose!(9) }\n", 4901},
      sourceProviderDiagnostics, [&] { return sourceNext++; }, nullptr, {},
      sourceProvider);
  expect(fromSource && sourceProviderDiagnostics.empty(),
         "existing source-provider expansion remains compatible");

  Diagnostics missingIdentity;
  MacroLibrary unavailable;
  SourceId next = 80;
  expandMacros(
      librarySource(70), missingIdentity, [&] { return next++; }, nullptr,
      {"dep"}, {}, nullptr, {}, nullptr, &unavailable);
  expect(!missingIdentity.empty(),
         "extraction without revision identities fails explicitly");

  Diagnostics invalidSource;
  expandMacros(
      {"broken.mt", "\"unterminated", 71}, invalidSource,
      [&] { return next++; }, nullptr, {"dep"}, {}, nullptr, {}, nullptr,
      &unavailable, identity);
  expect(!invalidSource.empty(),
         "invalid source cannot export an empty success");

  for (std::size_t size = 0; size < bytes->size(); ++size) {
    Diagnostics truncated;
    if (decodeMacros(std::string_view(*bytes).substr(0, size), truncated)) {
      expect(false, "all truncated archives are rejected");
      break;
    }
  }
  for (std::size_t offset = 0; offset < bytes->size(); ++offset) {
    auto corrupt = *bytes;
    corrupt[offset] ^= 1;
    Diagnostics damaged;
    if (decodeMacros(corrupt, damaged)) {
      expect(false, "checksum rejects every single-byte corruption");
      break;
    }
  }
  auto oversized = *bytes;
  for (unsigned i = 0; i < 4; ++i)
    oversized[8 + i] = static_cast<char>(0xff);
  rechecksum(oversized);
  rejected(oversized, "bounded decoder rejects an impossible table length");

  auto marker = bytes->find("temporary");
  expect(marker != std::string::npos && marker >= 6,
         "fixture contains a portable template token");
  if (marker != std::string::npos && marker >= 6) {
    auto badTag = *bytes;
    badTag[marker - 5] = static_cast<char>(0xff);
    rechecksum(badTag);
    rejected(badTag,
             "decoder rejects an invalid token tag with valid checksum");
    auto badReference = *bytes;
    for (unsigned i = 0; i < 4; ++i)
      badReference[marker + std::string("temporary").size() + i] =
          static_cast<char>(0xfe);
    rechecksum(badReference);
    rejected(badReference,
             "decoder rejects an invalid source reference with valid checksum");
    auto badFlag = *bytes;
    badFlag[marker + std::string("temporary").size() + 12] = 2;
    rechecksum(badFlag);
    rejected(badFlag, "decoder rejects a noncanonical boolean flag");
  }
  auto badVersion = *bytes;
  badVersion[7] = 2;
  rechecksum(badVersion);
  rejected(badVersion, "incompatible macro format is rejected");

  auto invalid = *imported;
  invalid.contexts.front().definition.source = UINT32_MAX - 1;
  Diagnostics invalidContext;
  expect(!encodeMacros(invalid, invalidContext),
         "encoder rejects invalid context provenance");
  consumer(std::make_shared<const MacroLibrary>(std::move(invalid)), 3901,
           "fn main() { dep.choose!(1) }\n", false);
  auto unbound = *imported;
  for (auto &definition : unbound.definitions)
    if (definition.name == "choose") {
      MacroNode variable;
      variable.kind = MacroNodeKind::Variable;
      variable.token = definition.rules.front().matcher.front().token;
      variable.name = "missing";
      definition.rules.front().expansion = {std::move(variable)};
    }
  consumer(std::make_shared<const MacroLibrary>(std::move(unbound)), 4001,
           "fn main() { dep.choose!(1) }\n", false);
  auto stale = *imported;
  stale.sources.front().identity += "-stale";
  consumer(std::make_shared<const MacroLibrary>(std::move(stale)), 4101,
           "fn main() { dep.choose!(1) }\n", false);
  return failures == 0 ? 0 : 1;
}
