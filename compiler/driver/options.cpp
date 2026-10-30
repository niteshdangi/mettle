#include "driver/options.h"
#include "backend/llvm/object.h"
#include "lint/lint.h"
#include <algorithm>
#include <iostream>

namespace mettle::driver {
Options::Options()
    : target(backend::defaultTargetTriple()), cc(METTLE_CXX_PATH),
      sysroot(METTLE_SYSROOT_PATH), libraryDirectory(METTLE_LIBRARY_PATH) {}
void usage() {
  std::cout
      << "Usage: mettle check|tokens|syntax FILE\n"
         "       mettle migrate FILE [-o OUTPUT]\n"
         "         (rewrites pre-cutover spellings to the target syntax of "
         "language-grammar section 13; prints to stdout, never edits FILE)\n"
         "       mettle fmt FILE... [--check]\n"
         "         (canonical layout, rewriting files in place; --check lists "
         "files that would change and exits 1 without rewriting)\n"
         "       mettle doc [PATH...] [-o DIR] [--private]\n"
         "         (writes static HTML documentation of the `pub` items of "
         "the .mt files under each PATH, default `.`, to DIR, default "
         "target/mettle/doc; fenced examples are run by mettle test)\n"
         "       mettle lint FILE|PACKAGE [--allow|--warn|--deny RULE]... "
         "[build options]\n"
         "         (runs the front end, then semantic lints over the checked "
         "program: unused-binding, unused-mutability, unused-import, "
         "unreachable-code, unused-outcome; RULE `warnings` selects all; "
         "exits 1 on a denied finding; @allow/@warn/@deny(RULE) on a function "
         "overrides the flags inside it)\n"
         "       mettle build FILE -o OUTPUT [--emit "
         "executable|object|llvm|ir]\n"
         "         [--profile debug|release] [--overflow-checks on|off]\n"
         "         [--target TRIPLE] [--cc CXX] [--sysroot PATH]\n"
         "         [--library-dir PATH] [--features a,b]\n"
         "         [-g] (source-level DWARF; on Darwin an executable also gets "
         "OUTPUT.dSYM from dsymutil)\n"
         "         [--freestanding] (object/LLVM/IR output, aborting panics, "
         "no implicit hosted entry)\n"
         "       mettle check|build PACKAGE_DIR|Mettle.toml [-o OUTPUT]\n"
         "         [--bin NAME] [--features a,b] [--no-default-features]\n"
         "         [--registry DIR]... [--locked] [--offline] [--frozen]\n"
         "         (resolves Mettle.toml, verifies or writes Mettle.lock and "
         "mounts dependencies)\n"
         "       mettle run FILE|PACKAGE [build options] [-- ARGS...]\n"
         "         (builds into a temporary directory, runs the program with "
         "ARGS and exits with its status; a signal exits 128+signal)\n"
         "       mettle test FILE|PACKAGE [FILTER...] [--exact] "
         "[--include-ignored|--ignored] [--doc] [--jobs N] [build options]\n"
         "         (runs the root module's @test functions and the fenced "
         "examples of its documentation comments, each in its own process; "
         "--doc runs only the examples)\n"
         "       mettle bench FILE|PACKAGE [FILTER...] [--exact] [build "
         "options]\n"
         "         (runs the root module's @bench functions; release profile "
         "unless --profile is given)\n"
         "       mettle clean [PACKAGE_DIR] [--cache-dir DIR] [--dry-run]\n"
         "         (empties the build cache; with a package also removes its "
         "target/mettle outputs)\n"
         "Build cache (builds of executables/objects): [--cache-dir DIR] "
         "[--no-cache] [--cache-limit-kib N] [--cache-max-age-days N] "
         "[--explain]\n"
         "Executable output requires the runtime target (the default); use "
         "--emit object for other targets.\n"
         "Scalar/product compiler with field initialization, owned moves, "
         "read/mut/take calls and control flow.\n"
         "Stored views, destructors and unwind cleanup remain incomplete.\n";
}
std::optional<Options> options(int argc, char **argv) {
  if (argc < 2)
    return std::nullopt;
  Options result;
  result.command = argv[1];
  if (result.command != "build" && result.command != "check" &&
      result.command != "tokens" && result.command != "syntax" &&
      result.command != "clean" && result.command != "migrate" &&
      result.command != "fmt" && result.command != "run" &&
      result.command != "test" && result.command != "bench" &&
      result.command != "doc" && result.command != "lint")
    return std::nullopt;
  bool selection = result.command == "test" || result.command == "bench";
  bool profileGiven = false;
  for (int i = 2; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--" && result.command == "run") {
      result.programArguments.assign(argv + i + 1, argv + argc);
      break;
    }
    if (selection && (arg == "--exact" || arg == "--include-ignored" ||
                      arg == "--ignored")) {
      result.exact |= arg == "--exact";
      result.includeIgnored |= arg == "--include-ignored";
      result.onlyIgnored |= arg == "--ignored";
      continue;
    }
    if (selection && arg == "--jobs") {
      if (++i == argc)
        return std::nullopt;
      std::string value = argv[i];
      if (value.empty() || value.size() > 4 ||
          value.find_first_not_of("0123456789") != std::string::npos ||
          std::stoul(value) == 0)
        return std::nullopt;
      result.jobs = static_cast<unsigned>(std::stoul(value));
      continue;
    }
    if (result.command == "test" && arg == "--doc") {
      result.docOnly = true;
      continue;
    }
    if (result.command == "doc" && arg == "--private") {
      result.documentPrivate = true;
      continue;
    }
    if (arg == "--freestanding") {
      result.freestanding = true;
      continue;
    }
    if (arg == "--check") {
      result.check = true;
      continue;
    }
    if (arg == "-g") {
      result.debugInfo = true;
      continue;
    }
    if (arg == "--no-cache" || arg == "--explain" || arg == "--dry-run") {
      result.noCache |= arg == "--no-cache";
      result.explain |= arg == "--explain";
      result.dryRun |= arg == "--dry-run";
      continue;
    }
    if (arg == "--no-default-features" || arg == "--locked" ||
        arg == "--offline" || arg == "--frozen") {
      result.packageOptions = true;
      result.defaultFeatures &= arg != "--no-default-features";
      result.locked |= arg == "--locked" || arg == "--frozen";
      result.offline |= arg == "--offline" || arg == "--frozen";
      continue;
    }
    if (!arg.empty() && arg[0] == '-') {
      if (++i == argc)
        return std::nullopt;
      std::string value = argv[i];
      if (result.command == "lint" &&
          (arg == "--allow" || arg == "--warn" || arg == "--deny")) {
        if (value != "warnings" && !lint::known(value))
          return std::nullopt;
        result.lintLevels.emplace_back(arg.substr(2), value);
      } else if (arg == "-o")
        result.output = value;
      else if (arg == "--emit")
        result.emit = value;
      else if (arg == "--profile") {
        result.profile = value;
        profileGiven = true;
      } else if (arg == "--target")
        result.target = value;
      else if (arg == "--cc")
        result.cc = value;
      else if (arg == "--library-dir")
        result.libraryDirectory = value;
      else if (arg == "--sysroot")
        result.sysroot = value;
      else if (arg == "--cache-dir")
        result.cacheDir = value;
      else if ((arg == "--cache-limit-kib" || arg == "--cache-max-age-days") &&
               !value.empty() && value.size() < 10 &&
               value.find_first_not_of("0123456789") == std::string::npos)
        (arg == "--cache-limit-kib" ? result.cacheLimitKib
                                    : result.cacheMaxAgeDays) =
            std::stoull(value);
      else if (arg == "--bin" || arg == "--registry") {
        result.packageOptions = true;
        if (arg == "--bin")
          result.bin = value;
        else
          result.registries.push_back(value);
      } else if (arg == "--features")
        for (std::size_t begin = 0; begin <= value.size();) {
          auto end = std::min(value.find(',', begin), value.size());
          if (end > begin)
            result.features.push_back(value.substr(begin, end - begin));
          begin = end + 1;
        }
      else if (arg == "--overflow-checks" && (value == "on" || value == "off"))
        result.checks = value == "on";
      else
        return std::nullopt;
    } else if (result.input.empty())
      result.input = arg;
    else if (result.command == "fmt" || result.command == "doc")
      result.moreInputs.push_back(arg);
    else if (selection)
      result.filters.push_back(arg);
    else
      return std::nullopt;
  }
  if (result.command == "doc" && result.input.empty())
    result.input = ".";
  if (result.command == "bench" && !profileGiven)
    result.profile = "release";
  if ((result.input.empty() && result.command != "clean") ||
      (result.check && result.command != "fmt") ||
      (result.freestanding && result.command == "build" &&
       result.emit == "executable") ||
      (result.command == "build" && result.output.empty()) ||
      ((result.command == "run" || selection) &&
       (!result.output.empty() || result.emit != "executable" ||
        result.freestanding)) ||
      (result.includeIgnored && result.onlyIgnored) ||
      (result.profile != "debug" && result.profile != "release") ||
      (result.emit != "executable" && result.emit != "object" &&
       result.emit != "llvm" && result.emit != "ir"))
    return std::nullopt;
  return result;
}
} // namespace mettle::driver
