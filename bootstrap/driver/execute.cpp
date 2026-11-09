#include "driver/execute.h"
#include "documentation/doctest.h"
#include "expansion/harness.h"
#include "support/path.h"
#include "llvm/Support/FileSystem.h"
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <map>
#include <optional>
#include <set>
#include <signal.h>
#include <spawn.h>
#include <sstream>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char **environ;

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

// A private directory for the executable and per-run output; the user's tree
// is never written.
struct WorkDirectory {
  llvm::SmallString<256> path;
  ~WorkDirectory() {
    if (!path.empty()) {
      std::error_code ignored;
      fs::remove_all(path.str().str(), ignored);
    }
  }
  std::error_code create() {
    std::error_code error;
    auto base = fs::temp_directory_path(error);
    if (error)
      return error;
    return llvm::sys::fs::createUniqueDirectory((base / "mettle-").string(),
                                                path);
  }
  fs::path file(const std::string &name) const {
    return fs::path(path.str().str()) / name;
  }
};

struct Termination {
  bool started = false, signaled = false, timedOut = false;
  int code = 0, signal = 0;
  std::string problem;
};

// Runs `program` with `arguments` and waits. A non-empty `capture` names a
// file receiving both output streams (standard input is then empty); otherwise
// the child shares this process's standard streams.
Termination spawn(const std::string &program,
                  const std::vector<std::string> &arguments,
                  const std::string &capture,
                  std::optional<unsigned> timeoutSeconds = std::nullopt) {
  Termination result;
  std::vector<std::string> storage{program};
  storage.insert(storage.end(), arguments.begin(), arguments.end());
  std::vector<char *> argv;
  for (auto &argument : storage)
    argv.push_back(argument.data());
  argv.push_back(nullptr);
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  if (!capture.empty()) {
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 1, capture.c_str(),
                                     O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, 1, 2);
  }
  posix_spawnattr_t attributes;
  posix_spawnattr_t *attributePointer = nullptr;
  if (timeoutSeconds) {
    int error = posix_spawnattr_init(&attributes);
    if (error != 0) {
      posix_spawn_file_actions_destroy(&actions);
      result.problem = std::strerror(error);
      return result;
    }
    short flags = POSIX_SPAWN_SETPGROUP;
    error = posix_spawnattr_setpgroup(&attributes, 0);
    if (error == 0)
      error = posix_spawnattr_setflags(&attributes, flags);
    if (error != 0) {
      posix_spawnattr_destroy(&attributes);
      posix_spawn_file_actions_destroy(&actions);
      result.problem = std::strerror(error);
      return result;
    }
    attributePointer = &attributes;
  }
  pid_t child = 0;
  int error = posix_spawn(&child, program.c_str(), &actions, attributePointer,
                          argv.data(), environ);
  if (attributePointer)
    posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  if (error != 0) {
    result.problem = std::strerror(error);
    return result;
  }
  int status = 0;
  if (timeoutSeconds) {
    const auto startedAt = std::chrono::steady_clock::now();
    for (;;) {
      auto waited = waitpid(child, &status, WNOHANG);
      if (waited == child)
        break;
      if (waited < 0) {
        if (errno == EINTR)
          continue;
        result.problem = std::strerror(errno);
        return result;
      }
      if (std::chrono::steady_clock::now() - startedAt >=
          std::chrono::seconds(*timeoutSeconds)) {
        result.timedOut = true;
        if (kill(-child, SIGKILL) < 0 && errno != ESRCH)
          result.problem = std::strerror(errno);
        do {
          waited = waitpid(child, &status, 0);
        } while (waited < 0 && errno == EINTR);
        if (waited < 0 && result.problem.empty())
          result.problem = std::strerror(errno);
        result.started = true;
        return result;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  } else
    while (waitpid(child, &status, 0) < 0)
      if (errno != EINTR) {
        result.problem = std::strerror(errno);
        return result;
      }
  result.started = true;
  if (WIFSIGNALED(status)) {
    result.signaled = true;
    result.signal = WTERMSIG(status);
  } else
    result.code = WEXITSTATUS(status);
  return result;
}

std::string signalName(int signal) {
  const char *name = strsignal(signal);
  return "signal " + std::to_string(signal) +
         (name ? " (" + std::string(name) + ")" : "");
}

std::string contents(const fs::path &path) {
  std::ifstream in(path, std::ios::binary);
  std::ostringstream text;
  text << in.rdbuf();
  return text.str();
}

std::string name(const Module::TestFunction &entry) {
  std::string joined;
  for (const auto &part : entry.path)
    joined += (joined.empty() ? "" : "::") + part;
  return displayPath(joined);
}

// Builds the input into the work directory. Returns 0 or the build status.
int buildInto(const Options &options, const WorkDirectory &work,
              std::vector<Module::TestFunction> *tests, std::string &program,
              std::vector<resolution::SourceModule> *sourceModules = nullptr) {
  Options selected = options;
  selected.command = "build";
  program = work.file("mettle-program").string();
  selected.output = program;
  return build(selected, tests, sourceModules);
}

int runProgram(const Options &options) {
  WorkDirectory work;
  if (auto error = work.create()) {
    std::cerr << "mettle: error[io]: cannot create a temporary directory: "
              << error.message() << '\n';
    return 1;
  }
  std::string program;
  if (int status = buildInto(options, work, nullptr, program))
    return status;
  auto outcome = spawn(program, options.programArguments, "");
  if (!outcome.started) {
    std::cerr << "mettle: error[io]: cannot run the program: "
              << outcome.problem << '\n';
    return 1;
  }
  if (outcome.signaled) {
    std::cerr << "mettle: program terminated by " << signalName(outcome.signal)
              << '\n';
    return 128 + outcome.signal;
  }
  return outcome.code;
}

// The entries of the requested kind that the filters and selection options
// leave in play, plus how many the filters removed.
struct Selection {
  std::vector<std::size_t> run, ignored;
  std::size_t filtered = 0;
};

Selection select(const Options &options,
                 const std::vector<Module::TestFunction> &tests, bool bench) {
  Selection selection;
  for (std::size_t i = 0; i < tests.size(); ++i) {
    if (tests[i].bench != bench)
      continue;
    auto full = name(tests[i]);
    bool matches = options.filters.empty();
    for (const auto &filter : options.filters)
      matches |= options.exact ? full == filter
                               : full.find(filter) != std::string::npos;
    if (!matches || (options.onlyIgnored && !tests[i].ignored)) {
      ++selection.filtered;
      continue;
    }
    if (tests[i].ignored && !options.includeIgnored && !options.onlyIgnored)
      selection.ignored.push_back(i);
    else
      selection.run.push_back(i);
  }
  return selection;
}

enum class Verdict { Passed, Failed, Terminated, Infrastructure, TimedOut };

struct Result {
  Verdict verdict = Verdict::Infrastructure;
  std::string reason, output, note;
  std::uint64_t durationNs = 0;
  // Decided without running a process (a compile-only or compile_fail
  // example, or one that did not compile).
  bool done = false;
};

// Classifies one isolated test process. A panic ends the process with the
// runtime's status 101; an aborting profile ends it by a signal.
Result classify(const Module::TestFunction &entry, const Termination &outcome,
                std::string output) {
  Result result;
  result.output = std::move(output);
  if (outcome.timedOut) {
    result.verdict = Verdict::TimedOut;
    result.reason = "timed out";
    return result;
  }
  if (!outcome.started) {
    result.reason = "cannot start the test process: " + outcome.problem;
    return result;
  }
  bool panicked = !outcome.signaled && outcome.code == 101;
  if (!outcome.signaled && outcome.code == expansion::harnessUsageStatus) {
    result.reason = "the harness did not know the selected test";
    return result;
  }
  if (entry.shouldPanic) {
    if (!(panicked || outcome.signaled)) {
      result.verdict = Verdict::Failed;
      result.reason = "test did not panic as declared";
    } else if (!entry.panicMessage.empty() &&
               result.output.find(entry.panicMessage) == std::string::npos) {
      result.verdict = Verdict::Failed;
      result.reason =
          "panic output does not contain \"" + entry.panicMessage + "\"";
    } else
      result.verdict = Verdict::Passed;
    return result;
  }
  if (outcome.signaled) {
    result.verdict = Verdict::Terminated;
    result.reason = "terminated by " + signalName(outcome.signal);
  } else if (outcome.code == 0)
    result.verdict = Verdict::Passed;
  else if (panicked) {
    // The runtime's own `panicked: ...` report is in the captured output.
    result.verdict = Verdict::Failed;
    if (result.output.find("panicked") == std::string::npos)
      result.reason = "panicked";
  } else if (outcome.code == expansion::harnessFailureStatus) {
    result.verdict = Verdict::Failed;
    result.reason = "returned its failure";
  } else {
    result.verdict = Verdict::Terminated;
    result.reason = "exited with status " + std::to_string(outcome.code);
  }
  return result;
}

unsigned workers(const Options &options, std::size_t count) {
  unsigned jobs = options.jobs
                      ? options.jobs
                      : std::max(1u, std::thread::hardware_concurrency());
  return static_cast<unsigned>(
      std::min<std::size_t>(jobs, std::max<std::size_t>(count, 1)));
}

// What runs one entry: the executable and the harness index of the entry in
// it.
struct Target {
  std::string program;
  std::size_t index = 0;
};

// Runs the selected entries, `jobs` processes at a time, into `results`;
// entries whose result is already `done` are left alone.
void runSelected(const Options &options, const WorkDirectory &work,
                 const std::vector<Module::TestFunction> &tests,
                 const std::vector<Target> &targets, const Selection &selection,
                 std::vector<Result> &results) {
  std::atomic<std::size_t> next{0};
  auto worker = [&] {
    for (auto turn = next++; turn < selection.run.size(); turn = next++) {
      auto index = selection.run[turn];
      if (results[index].done)
        continue;
      auto captured = work.file("output-" + std::to_string(index) + ".txt");
      const auto &target = targets[index];
      auto startedAt = std::chrono::steady_clock::now();
      auto outcome =
          spawn(target.program,
                {expansion::harnessTestSelector, std::to_string(target.index)},
                captured.string(), options.timeoutSeconds);
      results[index] = classify(tests[index], outcome, contents(captured));
      results[index].durationNs = static_cast<std::uint64_t>(
          std::chrono::duration_cast<std::chrono::nanoseconds>(
              std::chrono::steady_clock::now() - startedAt)
              .count());
    }
  };
  std::vector<std::thread> pool;
  for (unsigned i = 1; i < workers(options, selection.run.size()); ++i)
    pool.emplace_back(worker);
  worker();
  for (auto &thread : pool)
    thread.join();
}

std::string jsonString(const std::string &value) {
  static constexpr char hex[] = "0123456789abcdef";
  std::string result = "\"";
  for (unsigned char character : value) {
    switch (character) {
    case '"':
      result += "\\\"";
      break;
    case '\\':
      result += "\\\\";
      break;
    case '\b':
      result += "\\b";
      break;
    case '\f':
      result += "\\f";
      break;
    case '\n':
      result += "\\n";
      break;
    case '\r':
      result += "\\r";
      break;
    case '\t':
      result += "\\t";
      break;
    default:
      if (character < 0x20) {
        result += "\\u00";
        result += hex[character >> 4];
        result += hex[character & 0x0f];
      } else
        result += static_cast<char>(character);
    }
  }
  result += '"';
  return result;
}

void jsonSuiteStart(const std::string &suite, std::size_t total,
                    std::size_t filtered) {
  std::cout << "{\"event\":\"suite\",\"name\":" << jsonString(suite)
            << ",\"total\":" << total << ",\"filtered\":" << filtered << "}\n";
}

void jsonTest(const std::string &test, const std::string &outcome,
              std::uint64_t durationNs, const std::string &output,
              const std::string &message) {
  std::cout << "{\"event\":\"test\",\"name\":" << jsonString(test)
            << ",\"outcome\":" << jsonString(outcome)
            << ",\"duration_ns\":" << durationNs
            << ",\"output\":" << jsonString(output)
            << ",\"message\":" << jsonString(message) << "}\n";
}

std::string jsonOutcome(Verdict verdict) {
  switch (verdict) {
  case Verdict::Passed:
    return "passed";
  case Verdict::Failed:
    return "failed";
  case Verdict::Terminated:
    return "terminated";
  case Verdict::Infrastructure:
    return "infrastructure_failure";
  case Verdict::TimedOut:
    return "timed_out";
  }
  return "infrastructure_failure";
}

// Prints the report of a test run in declaration order; true when every
// selected test passed.
bool report(const std::vector<Module::TestFunction> &tests,
            const Selection &selection, const std::vector<Result> &results,
            const Options &options, const std::string &suite = "test") {
  std::size_t counts[5] = {0, 0, 0, 0, 0};
  bool machineReadable = options.format == "json";
  auto total = selection.run.size() + selection.ignored.size();
  if (machineReadable)
    jsonSuiteStart(suite, total, selection.filtered);
  else
    std::cout << "running " << total << (total == 1 ? " test\n" : " tests\n");
  for (std::size_t i = 0; i < tests.size(); ++i) {
    if (tests[i].bench)
      continue;
    auto ignored = std::find(selection.ignored.begin(), selection.ignored.end(),
                             i) != selection.ignored.end();
    if (ignored) {
      if (machineReadable)
        jsonTest(name(tests[i]), "ignored", 0, "", tests[i].ignoreReason);
      else
        std::cout << "test " << name(tests[i]) << " ... ignored"
                  << (tests[i].ignoreReason.empty()
                          ? ""
                          : ", " + tests[i].ignoreReason)
                  << '\n';
      continue;
    }
    if (std::find(selection.run.begin(), selection.run.end(), i) ==
        selection.run.end())
      continue;
    const auto &result = results[i];
    ++counts[static_cast<int>(result.verdict)];
    if (machineReadable) {
      const auto &message = result.reason.empty() ? result.note : result.reason;
      jsonTest(name(tests[i]), jsonOutcome(result.verdict), result.durationNs,
               result.output, message);
    } else
      std::cout << "test " << name(tests[i]) << " ... "
                << (result.verdict == Verdict::Passed       ? "ok"
                    : result.verdict == Verdict::Failed     ? "FAILED"
                    : result.verdict == Verdict::Terminated ? "TERMINATED"
                    : result.verdict == Verdict::TimedOut   ? "TIMED OUT"
                                                            : "ERROR")
                << (result.note.empty() ? "" : ", " + result.note) << '\n';
  }
  bool good = counts[1] + counts[2] + counts[3] + counts[4] == 0;
  if (machineReadable) {
    std::cout << "{\"event\":\"summary\",\"passed\":" << counts[0]
              << ",\"failed\":" << counts[1]
              << ",\"ignored\":" << selection.ignored.size()
              << ",\"terminated\":" << counts[2]
              << ",\"infrastructure_failures\":" << counts[3]
              << ",\"timed_out\":" << counts[4]
              << ",\"filtered\":" << selection.filtered << "}\n";
    return good;
  }
  bool header = false;
  for (auto index : selection.run) {
    const auto &result = results[index];
    if (result.verdict == Verdict::Passed)
      continue;
    if (!header)
      std::cout << "\nfailures:\n";
    header = true;
    std::cout << "---- " << name(tests[index]) << " ----\n"
              << result.reason << (result.reason.empty() ? "" : "\n")
              << result.output
              << (result.output.ends_with('\n') || result.output.empty()
                      ? ""
                      : "\n");
  }
  std::cout << "\ntest result: " << (good ? "ok" : "FAILED") << ". "
            << counts[0] << " passed; " << counts[1] << " failed; "
            << selection.ignored.size() << " ignored; " << counts[2]
            << " terminated; " << counts[3] << " infrastructure failures; "
            << counts[4] << " timed out; " << selection.filtered
            << " filtered out\n";
  return good;
}

// Builds the unit tests and runs them. `built` is false when the build failed.
int runUnitTests(const Options &options, bool &built,
                 std::vector<resolution::SourceModule> &sourceModules) {
  WorkDirectory work;
  if (auto error = work.create()) {
    std::cerr << "mettle: error[io]: cannot create a temporary directory: "
              << error.message() << '\n';
    return 1;
  }
  std::string program;
  std::vector<Module::TestFunction> tests;
  if (int status = buildInto(options, work, &tests, program, &sourceModules)) {
    built = false;
    return status;
  }
  auto selection = select(options, tests, false);
  std::vector<Result> results(tests.size());
  std::vector<Target> targets;
  for (std::size_t i = 0; i < tests.size(); ++i)
    targets.push_back({program, i});
  runSelected(options, work, tests, targets, selection, results);
  return report(tests, selection, results, options) ? 0 : 1;
}

struct Compiled {
  int status = 0;
  std::string diagnostics;
};

// Builds a test executable with generated source overlays, capturing
// diagnostics instead of printing them.
Compiled compile(const Options &options, const WorkDirectory &work,
                 const std::string &stem,
                 const std::map<std::string, std::string> &sourceOverrides,
                 std::vector<Module::TestFunction> &tests) {
  Options selected = options;
  selected.command = "build";
  selected.output = work.file(stem).string();
  selected.harness = "test";
  selected.filters.clear();
  std::ostringstream captured;
  auto *previous = std::cerr.rdbuf(captured.rdbuf());
  Compiled result;
  result.status = build(selected, &tests, nullptr, &sourceOverrides);
  std::cerr.rdbuf(previous);
  result.diagnostics = captured.str();
  return result;
}

// The harness index of the generated test of example `index`, if any.
std::optional<std::size_t>
harnessIndex(const std::vector<Module::TestFunction> &tests,
             std::size_t index) {
  auto wanted = documentation::testName(index);
  for (std::size_t i = 0; i < tests.size(); ++i)
    if (!tests[i].bench && !tests[i].path.empty() &&
        tests[i].path.back() == wanted)
      return i;
  return std::nullopt;
}

// The checking phases of the `error[PHASE]` diagnostics in `text`.
std::set<std::string> phases(const std::string &text) {
  std::set<std::string> found;
  for (std::size_t at = text.find("error["); at != std::string::npos;
       at = text.find("error[", at + 1)) {
    auto end = text.find(']', at);
    if (end != std::string::npos)
      found.insert(text.substr(at + 6, end - at - 6));
  }
  return found;
}

// A compile_fail example passes when its program is rejected in the expected
// phase. Without a named phase a malformed (lex/parse) or unsupported
// (feature) program does not count: the example must fail checking.
Result judgeCompileFail(const documentation::Example &example,
                        const Compiled &compiled) {
  Result result;
  auto found = phases(compiled.diagnostics);
  bool expected = false;
  for (const auto &phase : found)
    expected |= example.phase.empty()
                    ? phase != "lex" && phase != "parse" && phase != "feature"
                    : phase == example.phase;
  if (expected) {
    result.verdict = Verdict::Passed;
    result.note = "failed to compile as declared";
  } else {
    result.verdict = Verdict::Failed;
    result.reason = compiled.status == 0
                        ? "the example compiled but is marked compile_fail"
                        : "the example does not fail in the expected phase" +
                              (example.phase.empty()
                                   ? std::string(" (not lex, parse or feature)")
                                   : " (" + example.phase + ")");
    result.output = compiled.diagnostics;
  }
  result.done = true;
  return result;
}

// Runs the fenced examples from every source file in the selected package.
// Generated tests are overlaid on their original source paths, preserving the
// package's module graph and avoiding writes beside user files.
int runDoctests(const Options &requested,
                std::vector<resolution::SourceModule> sourceModules) {
  WorkDirectory work;
  if (auto error = work.create()) {
    std::cerr << "mettle: error[io]: cannot create a temporary directory: "
              << error.message() << '\n';
    return 1;
  }
  if (sourceModules.empty()) {
    std::string program;
    std::vector<Module::TestFunction> discovered;
    if (int status =
            buildInto(requested, work, &discovered, program, &sourceModules))
      return status;
  }
  std::vector<documentation::Example> examples;
  std::vector<std::size_t> sourceForExample;
  for (std::size_t sourceIndex = 0; sourceIndex < sourceModules.size();
       ++sourceIndex) {
    const auto &source = sourceModules[sourceIndex];
    std::string pageName;
    for (const auto &part : source.path)
      pageName += (pageName.empty() ? "" : "::") + part;
    if (pageName.empty())
      pageName = fs::path(source.source.path).stem().string();
    else
      pageName = displayPath(pageName);
    auto page = documentation::extract(source.source, pageName, true);
    for (auto &example : documentation::examples(page)) {
      examples.push_back(std::move(example));
      sourceForExample.push_back(sourceIndex);
    }
  }
  // Ignored-ness is a property of the example, not of a test attribute.
  Options options = requested;
  options.includeIgnored = options.onlyIgnored = false;
  std::vector<Module::TestFunction> tests;
  for (const auto &example : examples) {
    Module::TestFunction entry;
    entry.path = {example.name};
    entry.ignored = example.mode == documentation::Mode::Ignore;
    entry.shouldPanic = example.mode == documentation::Mode::ShouldPanic;
    tests.push_back(std::move(entry));
  }
  auto selection = select(options, tests, false);
  if (examples.empty()) {
    if (requested.format != "json" || !requested.docOnly)
      return 0;
    std::vector<Result> results;
    return report(tests, selection, results, options, "doctest") ? 0 : 1;
  }
  if (requested.format != "json")
    std::cout << "\nDoc-tests " << requested.input << '\n';
  std::vector<Result> results(tests.size());
  std::vector<Target> targets(tests.size());
  std::vector<std::size_t> built;
  auto overlays = [&](const std::vector<std::size_t> &picks) {
    std::map<std::size_t, std::vector<std::size_t>> grouped;
    for (auto index : picks)
      grouped[sourceForExample[index]].push_back(index);
    std::map<std::string, std::string> overrides;
    for (const auto &[sourceIndex, sourcePicks] : grouped) {
      const auto &source = sourceModules[sourceIndex].source;
      overrides.emplace(source.path, documentation::withTests(
                                         source.text, examples, sourcePicks));
    }
    return overrides;
  };
  for (auto index : selection.run)
    if (examples[index].mode == documentation::Mode::CompileFail) {
      std::vector<Module::TestFunction> ignored;
      auto stem = "doctest-" + std::to_string(index);
      auto startedAt = std::chrono::steady_clock::now();
      auto compiled = compile(options, work, stem, overlays({index}), ignored);
      results[index] = judgeCompileFail(examples[index], compiled);
      results[index].durationNs = static_cast<std::uint64_t>(
          std::chrono::duration_cast<std::chrono::nanoseconds>(
              std::chrono::steady_clock::now() - startedAt)
              .count());
    } else
      built.push_back(index);
  auto place = [&](std::size_t index, const std::string &program,
                   const std::vector<Module::TestFunction> &found) {
    auto harness = harnessIndex(found, index);
    if (!harness)
      return;
    targets[index] = {program, *harness};
    if (examples[index].mode == documentation::Mode::NoRun) {
      results[index].verdict = Verdict::Passed;
      results[index].note = "compiled, not run";
      results[index].done = true;
    }
  };
  if (!built.empty()) {
    std::vector<Module::TestFunction> found;
    auto program = work.file("doctests").string();
    auto compiled = compile(options, work, "doctests", overlays(built), found);
    if (compiled.status == 0)
      for (auto index : built)
        place(index, program, found);
    else
      for (auto index : built) {
        auto stem = "doctest-" + std::to_string(index);
        auto single = work.file(stem).string();
        std::vector<Module::TestFunction> own;
        auto startedAt = std::chrono::steady_clock::now();
        auto one = compile(options, work, stem, overlays({index}), own);
        if (one.status == 0) {
          place(index, single, own);
          continue;
        }
        results[index].verdict = Verdict::Failed;
        results[index].reason = "the example does not compile";
        results[index].output = one.diagnostics;
        results[index].durationNs = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now() - startedAt)
                .count());
        results[index].done = true;
      }
  }
  for (auto index : built)
    if (!results[index].done && targets[index].program.empty()) {
      results[index].verdict = Verdict::Infrastructure;
      results[index].reason = "the harness has no test for this example";
      results[index].done = true;
    }
  runSelected(options, work, tests, targets, selection, results);
  return report(tests, selection, results, options, "doctest") ? 0 : 1;
}

int runTests(const Options &options) {
  int status = 0;
  bool built = true;
  std::vector<resolution::SourceModule> sourceModules;
  if (!options.docOnly) {
    status = runUnitTests(options, built, sourceModules);
    if (!built)
      return status;
  }
  if (!options.onlyIgnored)
    status |= runDoctests(options, std::move(sourceModules));
  return status;
}

std::string number(double value) {
  std::ostringstream text;
  text << std::fixed << std::setprecision(value < 100 ? 2 : 0) << value;
  return text.str();
}

int runBenchmarks(const Options &options) {
  WorkDirectory work;
  if (auto error = work.create()) {
    std::cerr << "mettle: error[io]: cannot create a temporary directory: "
              << error.message() << '\n';
    return 1;
  }
  std::string program;
  std::vector<Module::TestFunction> benches;
  if (int status = buildInto(options, work, &benches, program))
    return status;
  auto selection = select(options, benches, true);
  std::vector<Result> results(benches.size());
  std::vector<unsigned long long> iterations(benches.size());
  std::vector<std::vector<double>> samples(benches.size());
  bool machineReadable = options.format == "json";
  auto selectedCount = selection.run.size() + selection.ignored.size();
  if (machineReadable)
    jsonSuiteStart("bench", selectedCount, selection.filtered);
  else {
    std::cout << "running " << selectedCount
              << (selectedCount == 1 ? " benchmark\n" : " benchmarks\n");
    for (auto index : selection.ignored)
      std::cout << "bench " << name(benches[index]) << " ... ignored"
                << (benches[index].ignoreReason.empty()
                        ? ""
                        : ", " + benches[index].ignoreReason)
                << '\n';
  }
  // Benchmarks run one at a time so they do not compete for the machine.
  for (auto index : selection.run) {
    auto captured = work.file("bench-" + std::to_string(index) + ".txt");
    auto startedAt = std::chrono::steady_clock::now();
    auto outcome =
        spawn(program, {expansion::harnessBenchSelector, std::to_string(index)},
              captured.string());
    auto &result = results[index];
    result.output = contents(captured);
    result.durationNs = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now() - startedAt)
            .count());
    std::istringstream words(result.output);
    words >> iterations[index];
    for (unsigned long long total; words >> total;)
      samples[index].push_back(static_cast<double>(total));
    if (!outcome.started || outcome.signaled || outcome.code != 0 ||
        iterations[index] == 0 ||
        samples[index].size() !=
            static_cast<std::size_t>(expansion::harnessBenchSamples)) {
      result.verdict = Verdict::Failed;
      result.reason =
          !outcome.started    ? "cannot start: " + outcome.problem
          : outcome.signaled  ? "terminated by " + signalName(outcome.signal)
          : outcome.code != 0 ? "exit status " + std::to_string(outcome.code)
                              : "invalid benchmark output";
      if (!machineReadable)
        std::cout << "bench " << name(benches[index]) << " ... FAILED ("
                  << result.reason << ")\n"
                  << result.output;
      continue;
    }
    result.verdict = Verdict::Passed;
    std::sort(samples[index].begin(), samples[index].end());
    if (!machineReadable) {
      const auto &sample = samples[index];
      auto per = [&](double total) {
        return total / static_cast<double>(iterations[index]);
      };
      std::cout << "bench " << name(benches[index]) << " ... "
                << number(per(sample[sample.size() / 2]))
                << " ns/iter (median of " << sample.size() << " samples; min "
                << number(per(sample.front())) << ", max "
                << number(per(sample.back())) << "; " << iterations[index]
                << " iterations per sample)\n";
    }
  }
  auto failed = static_cast<std::size_t>(std::count_if(
      selection.run.begin(), selection.run.end(), [&](std::size_t index) {
        return results[index].verdict != Verdict::Passed;
      }));
  if (machineReadable) {
    for (std::size_t index = 0; index < benches.size(); ++index) {
      if (std::find(selection.ignored.begin(), selection.ignored.end(),
                    index) != selection.ignored.end()) {
        jsonTest(name(benches[index]), "ignored", 0, "",
                 benches[index].ignoreReason);
        continue;
      }
      if (std::find(selection.run.begin(), selection.run.end(), index) ==
          selection.run.end())
        continue;
      const auto &result = results[index];
      jsonTest(name(benches[index]),
               result.verdict == Verdict::Passed ? "measured" : "failed",
               result.durationNs, result.output, result.reason);
    }
    std::cout << "{\"event\":\"summary\",\"measured\":"
              << selection.run.size() - failed << ",\"failed\":" << failed
              << ",\"ignored\":" << selection.ignored.size()
              << ",\"filtered\":" << selection.filtered << "}\n";
    return failed ? 1 : 0;
  }
  std::cout << "\nbench result: " << (failed ? "FAILED" : "ok") << ". "
            << selection.run.size() - failed << " measured; " << failed
            << " failed; " << selection.ignored.size() << " ignored; "
            << selection.filtered << " filtered out\n";
  return failed ? 1 : 0;
}
} // namespace

int execute(const Options &options) {
  Options selected = options;
  if (options.command == "run")
    return runProgram(selected);
  selected.harness = options.command == "test" ? "test" : "bench";
  return options.command == "test" ? runTests(selected)
                                   : runBenchmarks(selected);
}
} // namespace mettle::driver
