#include "pipeline/compile.h"
#include "resolution/load.h"
#include "resolution/resolve.h"
#include "syntax/parser.h"
#include <iostream>
#include <sstream>
#include <stdexcept>

namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

void inMemorySources() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "module math;\nimport math::{answer as result};\n"
                         "fn main() { result() - 42 }\n"},
      {"memory/math.mt", "pub fn answer() { 42 }\n"}};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::resolution::load(sources, diagnostics);
  auto resolved =
      tree ? mettle::resolution::resolve(*tree, diagnostics) : nullptr;
  if (!resolved)
    diagnostics.print(sources.front(), std::cerr);
  require(resolved && diagnostics.empty(), "in-memory module loading failed");
  require(tree->functions[0].span.source != tree->functions[1].span.source,
          "external source spans were flattened into the root source");
  mettle::Diagnostics compilationDiagnostics;
  require(
      mettle::pipeline::compile(sources, compilationDiagnostics).has_value(),
      "in-memory multi-source pipeline failed");
}

void syntaxAndIdentities() {
  mettle::Source source{"memory/root.mt",
                        "module left { pub fn value() { 20 } }\n"
                        "module right { pub fn value() { 22 } }\n"
                        "import left::value as first;\n"
                        "fn main() { first() + right::value() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(), "module resolution failed");
  require(tree.functions[0].name == "value" &&
              tree.functions[1].name == "value",
          "resolution rewrote syntax declaration names");
  auto left = resolved->moduleOf(tree.functions[0].span);
  auto right = resolved->moduleOf(tree.functions[1].span);
  require(left != right, "distinct modules share an identity");
  require(resolved->canonical(tree.functions[0].span) == "left::value",
          "missing canonical definition side table");
  require(resolved->lookup(0, "first", mettle::resolution::Namespace::Value,
                           {}) == "left::value",
          "import alias did not preserve declaration identity");
  require(resolved->lookup(right, "super::left::value",
                           mettle::resolution::Namespace::Value,
                           {}) == "left::value",
          "super path did not resolve from declaration scope");
}

void sameDeclarationGlobs() {
  mettle::Source source{"memory/root.mt",
                        "module base { pub fn answer() { 42 } }\n"
                        "module a { pub import package::base::answer; }\n"
                        "module b { pub import package::base::answer; }\n"
                        "import a::*;\nimport b::*;\nfn main() { answer() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(),
          "two glob paths to one declaration became ambiguous");
}

void delayedExplicitImport() {
  mettle::Source source{"memory/root.mt",
                        "module a { pub fn answer() { 1 } }\n"
                        "module b { pub fn answer() { 42 } }\n"
                        "module selected {\n"
                        "pub import package::a::*;\n"
                        "pub import package::relay::answer;\n}\n"
                        "module relay { pub import package::b::answer; }\n"
                        "import selected::*;\nfn main() { answer() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(),
          "glob export raced an unresolved explicit import");
  require(resolved->lookup(0, "answer", mettle::resolution::Namespace::Value,
                           {}) == "b::answer",
          "import order changed explicit binding selection");
}

void sourceDiagnostic() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "module child;\nfn main() { 0 }\n"},
      {"memory/child.mt", "fn invalid() { let x = ; }\n"}};
  mettle::Diagnostics diagnostics;
  require(!mettle::resolution::load(sources, diagnostics),
          "malformed external source was accepted");
  std::ostringstream rendered;
  diagnostics.print(sources.front(), rendered);
  require(rendered.str().find("memory/child.mt:1:") != std::string::npos,
          "external diagnostic lost its source identity");
}

void duplicateFileIdentity() {
  mettle::Diagnostics diagnostics;
  mettle::resolution::SourceProvider provider =
      [](const std::string &path) -> std::optional<mettle::Source> {
    if (path == "memory/one.mt" || path == "memory/two.mt")
      return mettle::Source{"memory/same.mt", "pub fn value() { 42 }\n"};
    return std::nullopt;
  };
  auto tree = mettle::resolution::load(
      {"memory/root.mt", "module one;\nmodule two;\n"}, provider, diagnostics);
  require(!tree && !diagnostics.empty(),
          "one source acquired two module identities");
}

void privateRootReexport() {
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(
      {"memory/root.mt",
       "fn hidden() { 42 }\npub import self::hidden as exposed;\n"},
      diagnostics);
  require(!mettle::resolution::resolve(tree, diagnostics),
          "package-private root declaration became globally public");
  require(!diagnostics.empty() && diagnostics.items.back().message.find(
                                      "cannot reexport") != std::string::npos,
          "private reexport failed for an unrelated reason");
}

void associatedImports() {
  mettle::Diagnostics diagnostics;
  auto tree =
      mettle::parse({"memory/root.mt",
                     "pub enum Choice { Answer(i32), Empty }\n"
                     "type Maker { pub static fn answer() { 42 }; drop {} }\n"
                     "alias Alias = Choice;\n"
                     "import Alias::{Answer as result};\n"
                     "import Choice::*;\n"
                     "import Maker::answer as get;\n"},
                    diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  if (!resolved)
    diagnostics.print({"memory/root.mt", ""}, std::cerr);
  require(resolved && diagnostics.empty(), "associated import failed");
  require(resolved->lookup(0, "result", mettle::resolution::Namespace::Value,
                           {}) == "Choice::Answer",
          "alias variant import lost the nominal declaration");
  require(resolved->lookup(0, "Empty", mettle::resolution::Namespace::Value,
                           {}) == "Choice::Empty",
          "enum variant glob did not resolve");
  require(resolved->lookup(0, "get", mettle::resolution::Namespace::Value,
                           {}) == "Maker.answer",
          "associated function import did not resolve");
  require(!resolved->lookup(0, "Maker::drop",
                            mettle::resolution::Namespace::Value, {}),
          "destructor was exposed as an associated callable binding");
}
void catalogLibrary() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "fn main() { core::answer() - 42 }\n"},
      {"memory/lib/core/module.mt", "pub fn answer() { 42 }\n"},
      {"memory/lib/std/module.mt", "pub fn broken() { missing() }\n"}};
  mettle::resolution::Library library{"memory/lib", false, {}};
  mettle::Diagnostics diagnostics;
  require(mettle::pipeline::compile(sources, diagnostics, library).has_value(),
          "catalog-supplied library failed or loaded an unreferenced root");
  sources.front().text = "fn main() { std::broken() }\n";
  mettle::Diagnostics failing;
  require(!mettle::pipeline::compile(sources, failing, library).has_value(),
          "referenced library error was not reported");
}
} // namespace

int main() {
  try {
    inMemorySources();
    syntaxAndIdentities();
    sameDeclarationGlobs();
    delayedExplicitImport();
    sourceDiagnostic();
    duplicateFileIdentity();
    privateRootReexport();
    associatedImports();
    catalogLibrary();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
