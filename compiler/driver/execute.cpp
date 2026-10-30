#include "driver/execute.h"
#include "expansion/harness.h"
#include "llvm/Support/FileSystem.h"
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
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
  bool started = false, signaled = false;
  int code = 0, signal = 0;
  std::string problem;
};

// Runs `program` with `arguments` and waits. A non-empty `capture` names a
// file receiving both output streams (standard input is then empty); otherwise
// the child shares this process's standard streams.
Termination spawn(const std::string &program,
                  const std::vector<std::string> &arguments,
                  const std::string &capture) {
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
  pid_t child = 0;
  int error = posix_spawn(&child, program.c_str(), &actions, nullptr,
                          argv.data(), environ);
  posix_spawn_file_actions_destroy(&actions);
  if (error != 0) {
    result.problem = std::strerror(error);
    return result;
  }
  int status = 0;
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
  return joined;
}

// Builds the input into the work directory. Returns 0 or the build status.
int buildInto(const Options &options, const WorkDirectory &work,
              std::vector<Module::TestFunction> *tests, std::string &program) {
  Options selected = options;
  selected.command = "build";
  program = work.file("mettle-program").string();
  selected.output = program;
  return build(selected, tests);
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

enum class Verdict { Passed, Failed, Terminated, Infrastructure };

struct Result {
  Verdict verdict = Verdict::Infrastructure;
  std::string reason, output;
};

// Classifies one isolated test process. A panic ends the process with the
// runtime's status 101; an aborting profile ends it by a signal.
Result classify(const Module::TestFunction &entry, const Termination &outcome,
                std::string output) {
  Result result;
  result.output = std::move(output);
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

int runTests(const Options &options) {
  WorkDirectory work;
  if (auto error = work.create()) {
    std::cerr << "mettle: error[io]: cannot create a temporary directory: "
              << error.message() << '\n';
    return 1;
  }
  std::string program;
  std::vector<Module::TestFunction> tests;
  if (int status = buildInto(options, work, &tests, program))
    return status;
  auto selection = select(options, tests, false);
  std::vector<Result> results(tests.size());
  std::atomic<std::size_t> next{0};
  auto worker = [&] {
    for (auto turn = next++; turn < selection.run.size(); turn = next++) {
      auto index = selection.run[turn];
      auto captured = work.file("output-" + std::to_string(index) + ".txt");
      auto outcome = spawn(
          program, {expansion::harnessTestSelector, std::to_string(index)},
          captured.string());
      results[index] = classify(tests[index], outcome, contents(captured));
    }
  };
  std::vector<std::thread> pool;
  for (unsigned i = 1; i < workers(options, selection.run.size()); ++i)
    pool.emplace_back(worker);
  worker();
  for (auto &thread : pool)
    thread.join();

  std::size_t counts[4] = {0, 0, 0, 0};
  std::cout << "running " << selection.run.size() + selection.ignored.size()
            << (selection.run.size() + selection.ignored.size() == 1
                    ? " test\n"
                    : " tests\n");
  for (std::size_t i = 0; i < tests.size(); ++i) {
    if (tests[i].bench)
      continue;
    auto ignored = std::find(selection.ignored.begin(), selection.ignored.end(),
                             i) != selection.ignored.end();
    if (ignored) {
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
    std::cout << "test " << name(tests[i]) << " ... "
              << (result.verdict == Verdict::Passed       ? "ok"
                  : result.verdict == Verdict::Failed     ? "FAILED"
                  : result.verdict == Verdict::Terminated ? "TERMINATED"
                                                          : "ERROR")
              << '\n';
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
  bool good = counts[1] + counts[2] + counts[3] == 0;
  std::cout << "\ntest result: " << (good ? "ok" : "FAILED") << ". "
            << counts[0] << " passed; " << counts[1] << " failed; "
            << selection.ignored.size() << " ignored; " << counts[2]
            << " terminated; " << counts[3] << " infrastructure failures; "
            << selection.filtered << " filtered out\n";
  return good ? 0 : 1;
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
  std::cout << "running " << selection.run.size() + selection.ignored.size()
            << (selection.run.size() + selection.ignored.size() == 1
                    ? " benchmark\n"
                    : " benchmarks\n");
  for (auto index : selection.ignored)
    std::cout << "bench " << name(benches[index]) << " ... ignored"
              << (benches[index].ignoreReason.empty()
                      ? ""
                      : ", " + benches[index].ignoreReason)
              << '\n';
  std::size_t failed = 0;
  // Benchmarks run one at a time so they do not compete for the machine.
  for (auto index : selection.run) {
    auto captured = work.file("bench-" + std::to_string(index) + ".txt");
    auto outcome =
        spawn(program, {expansion::harnessBenchSelector, std::to_string(index)},
              captured.string());
    auto output = contents(captured);
    std::istringstream words(output);
    unsigned long long iterations = 0;
    std::vector<double> samples;
    words >> iterations;
    for (unsigned long long total; words >> total;)
      samples.push_back(static_cast<double>(total));
    if (!outcome.started || outcome.signaled || outcome.code != 0 ||
        iterations == 0 ||
        samples.size() !=
            static_cast<std::size_t>(expansion::harnessBenchSamples)) {
      ++failed;
      std::cout << "bench " << name(benches[index]) << " ... FAILED ("
                << (!outcome.started ? "cannot start: " + outcome.problem
                    : outcome.signaled
                        ? "terminated by " + signalName(outcome.signal)
                        : "exit status " + std::to_string(outcome.code))
                << ")\n"
                << output;
      continue;
    }
    std::sort(samples.begin(), samples.end());
    auto per = [&](double total) {
      return total / static_cast<double>(iterations);
    };
    std::cout << "bench " << name(benches[index]) << " ... "
              << number(per(samples[samples.size() / 2]))
              << " ns/iter (median of " << samples.size() << " samples; min "
              << number(per(samples.front())) << ", max "
              << number(per(samples.back())) << "; " << iterations
              << " iterations per sample)\n";
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
