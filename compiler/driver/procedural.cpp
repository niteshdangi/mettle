#include "driver/procedural.h"
#include "driver/observe.h"
#include "packages/sha256.h"
#include "llvm/Support/Program.h"
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;
using expansion::ProcedureResponse;

std::string slurp(const std::string &path) {
  std::ifstream stream(path, std::ios::binary);
  std::ostringstream text;
  text << stream.rdbuf();
  return text.str();
}

ProcedureResponse failure(std::string message) {
  ProcedureResponse response;
  response.fault = std::move(message);
  return response;
}

// A reproducible result: the state of every declared input when the program
// ran, and its raw response.
struct Record {
  Files inputs, variables;
  std::string response;
};

std::string serialize(const Record &record) {
  std::string text = "reproducible\n";
  for (const auto &[state, path] : record.inputs)
    text += "input " + state + " " + path + "\n";
  for (const auto &[state, name] : record.variables)
    text += "env " + state + " " + name + "\n";
  return text + "response\n" + record.response;
}

std::optional<Record> parseRecord(const std::string &text) {
  static const std::string marker = "\nresponse\n";
  auto split = text.find(marker);
  if (text.rfind("reproducible\n", 0) != 0 || split == std::string::npos)
    return std::nullopt;
  Record record;
  record.response = text.substr(split + marker.size());
  std::istringstream lines(text.substr(0, split));
  std::string line;
  std::getline(lines, line);
  while (std::getline(lines, line)) {
    auto first = line.find(' ');
    auto second =
        first == std::string::npos ? first : line.find(' ', first + 1);
    if (second == std::string::npos)
      return std::nullopt;
    auto kind = line.substr(0, first);
    auto state = line.substr(first + 1, second - first - 1);
    auto name = line.substr(second + 1);
    if (kind == "input")
      record.inputs.emplace_back(state, name);
    else if (kind == "env")
      record.variables.emplace_back(state, name);
    else
      return std::nullopt;
  }
  return record;
}

std::optional<std::string> stale(const Record &record,
                                 const fs::path &directory) {
  for (const auto &[state, path] : record.inputs)
    if (inputState(directory / path) != state)
      return "input '" + path + "' changed";
  for (const auto &[state, name] : record.variables)
    if (variableState(name) != state)
      return "environment variable " + name + " changed";
  return std::nullopt;
}
} // namespace

ProcedureHost::ProcedureHost(const Options &options,
                             std::vector<packages::Macro> macros,
                             packages::Store *store, BuildInputs &inputs)
    : options(options), store(store), inputs(inputs) {
  for (auto &macro : macros) {
    available.names.insert(macro.name);
    programs.push_back({std::move(macro), "", ""});
  }
  available.run = [this](const std::string &name, const std::string &request) {
    return invoke(name, request);
  };
}

bool ProcedureHost::prepare() {
  for (auto &program : programs) {
    const auto &macro = program.macro;
    auto work = fs::path(macro.directory) / "target" / "mettle" / "macros";
    std::error_code error;
    fs::create_directories(work, error);
    if (error) {
      std::cerr << "mettle: error[build]: procedural macro '" << macro.name
                << "' of '" << macro.package << "': cannot create "
                << work.generic_string() << ": " << error.message() << '\n';
      return false;
    }
    program.binary = (work / macro.name).generic_string();
    // Programs are compiled for the host whatever the build target is.
    Options host;
    host.command = "build";
    host.input = macro.source;
    host.output = program.binary;
    host.cc = options.cc;
    host.sysroot = options.sysroot;
    host.libraryDirectory = options.libraryDirectory;
    host.cacheDir = options.cacheDir;
    host.cacheLimitKib = options.cacheLimitKib;
    host.cacheMaxAgeDays = options.cacheMaxAgeDays;
    host.noCache = options.noCache;
    host.explain = options.explain;
    std::uint64_t size = 0;
    auto hash = driver::run(host) == 0
                    ? packages::hashFile(program.binary, size)
                    : std::nullopt;
    if (!hash) {
      std::cerr << "mettle: error[build]: procedural macro '" << macro.name
                << "' of '" << macro.package << "' " << macro.version
                << ": compiling the program failed\n";
      return false;
    }
    program.binaryHash = *hash;
  }
  return true;
}

ProcedureResponse ProcedureHost::invoke(const std::string &name,
                                        const std::string &request) {
  auto memoKey = name + std::string(1, '\0') + request;
  auto remembered = memo.find(memoKey);
  if (remembered != memo.end())
    return remembered->second;
  const Program *selected = nullptr;
  for (const auto &program : programs)
    if (program.macro.name == name)
      selected = &program;
  if (!selected)
    return failure("no program is built for this macro");
  const auto &macro = selected->macro;
  packages::Sha256 identity;
  for (const auto &field :
       {std::string("mettle-macro-key-1"), compilerIdentity(), macro.package,
        macro.version, macro.directory, name, selected->binaryHash,
        options.target, options.profile, request}) {
    identity.update(field);
    identity.update(std::string_view("\0", 1));
  }
  auto key = identity.finish();
  auto explain = [&](const std::string &message) {
    if (options.explain)
      std::cerr << "mettle: procedural macro '" << name << "!': " << message
                << '\n';
  };

  std::optional<ProcedureResponse> response;
  if (!store)
    explain("rerun (caching is off)");
  else if (auto text = store->text(key)) {
    auto record = parseRecord(*text);
    auto reason = record ? stale(*record, macro.directory)
                         : std::optional<std::string>("unreadable record");
    if (!reason) {
      explain("reused (declared reproducible; inputs unchanged)");
      response = expansion::parseResponse(record->response);
    } else
      explain("rerun (" + *reason + ")");
  } else
    explain("rerun (no reproducible record)");
  if (!response)
    response = execute(*selected, request, key);
  inputs.generated(name + ":" + digest(request), response->text);
  memo.emplace(memoKey, *response);
  return *response;
}

ProcedureResponse ProcedureHost::execute(const Program &program,
                                         const std::string &request,
                                         const std::string &key) {
  const auto &macro = program.macro;
  fs::path directory = macro.directory;
  fs::path work = directory / "target" / "mettle" / "macros";
  auto requestPath = (work / (macro.name + ".request")).generic_string();
  auto responsePath = (work / (macro.name + ".response")).generic_string();
  auto errorPath = (work / (macro.name + ".stderr")).generic_string();
  {
    std::ofstream out(requestPath, std::ios::binary | std::ios::trunc);
    out << request;
    if (!out)
      return failure("cannot write " + requestPath);
  }
  const std::vector<std::pair<const char *, std::string>> environment{
      {"METTLE_PACKAGE_DIR", macro.directory},
      {"METTLE_PACKAGE_NAME", macro.package},
      {"METTLE_PACKAGE_VERSION", macro.version},
      {"METTLE_TARGET", options.target},
      {"METTLE_PROFILE", options.profile},
      {"METTLE_MACRO_API", "1.0"}};
  for (const auto &[name, value] : environment)
    setenv(name, value.c_str(), 1);
  std::error_code error;
  auto previous = fs::current_path(error);
  fs::current_path(directory, error);
  if (error)
    return failure("cannot enter " + macro.directory);
  std::vector<llvm::StringRef> arguments{program.binary};
  std::optional<llvm::StringRef> redirects[3] = {
      llvm::StringRef(requestPath), llvm::StringRef(responsePath),
      llvm::StringRef(errorPath)};
  std::string message;
  bool notLaunched = false;
  int status =
      llvm::sys::ExecuteAndWait(program.binary, arguments, std::nullopt,
                                redirects, 0, 0, &message, &notLaunched);
  std::error_code restored;
  fs::current_path(previous, restored);
  if (notLaunched)
    return failure("cannot run the program: " + message);
  if (status != 0) {
    auto detail = slurp(errorPath);
    while (!detail.empty() && (detail.back() == '\n' || detail.back() == '\r'))
      detail.pop_back();
    return failure("the program exited with status " + std::to_string(status) +
                   (detail.empty() ? "" : ": " + detail));
  }
  auto raw = slurp(responsePath);
  auto response = expansion::parseResponse(raw);
  if (response.reproducible && response.fault.empty() && store) {
    Record record;
    for (const auto &path : response.files)
      record.inputs.emplace_back(inputState(directory / path), path);
    for (const auto &name : response.variables)
      record.variables.emplace_back(variableState(name), name);
    record.response = raw;
    store->putText(key, serialize(record));
  }
  return response;
}
} // namespace mettle::driver
