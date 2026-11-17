#include "driver/session.h"
#include "driver/cache.h"
#include "driver/checked_library.h"
#include "driver/options.h"
#include "lsp/json.h"
#include "support/limits.h"
#include <array>
#include <cerrno>
#include <cstdio>
#include <exception>
#include <iostream>
#include <limits>
#include <memory>
#include <system_error>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

namespace mettle::driver {
namespace {
#ifdef _WIN32
constexpr auto descriptor = &_fileno;
constexpr auto duplicate = &_dup;
constexpr auto replace = &_dup2;
constexpr auto closeDescriptor = &_close;
#else
constexpr auto descriptor = &fileno;
constexpr auto duplicate = &dup;
constexpr auto replace = &dup2;
constexpr auto closeDescriptor = &close;
#endif

int redirect(int from, int to) {
  int result;
  do {
    result = replace(from, to);
  } while (result < 0 && errno == EINTR);
  return result;
}

class CapturedStream {
public:
  explicit CapturedStream(std::FILE *stream)
      : stream(stream), file(std::tmpfile(), &std::fclose) {
    if (!file)
      throw std::system_error(errno, std::generic_category(),
                              "cannot capture compiler output");
    do {
      previous = duplicate(descriptor(stream));
    } while (previous < 0 && errno == EINTR);
    if (previous < 0)
      throw std::system_error(errno, std::generic_category(),
                              "cannot preserve compiler output");
    if (redirect(descriptor(file.get()), descriptor(stream)) < 0) {
      auto failure = errno;
      closeDescriptor(previous);
      throw std::system_error(failure, std::generic_category(),
                              "cannot redirect compiler output");
    }
  }
  ~CapturedStream() {
    std::fflush(stream);
    if (redirect(previous, descriptor(stream)) < 0)
      std::terminate();
    closeDescriptor(previous);
  }
  CapturedStream(const CapturedStream &) = delete;
  CapturedStream &operator=(const CapturedStream &) = delete;
  std::string contents() {
    if (std::fflush(stream) || std::fseek(file.get(), 0, SEEK_SET))
      throw std::system_error(errno, std::generic_category(),
                              "cannot read compiler output");
    std::string result;
    std::array<char, 4096> bytes;
    while (auto count = std::fread(bytes.data(), 1, bytes.size(), file.get()))
      result.append(bytes.data(), count);
    if (std::ferror(file.get()))
      throw std::system_error(errno, std::generic_category(),
                              "cannot read compiler output");
    return result;
  }

private:
  std::FILE *stream;
  std::unique_ptr<std::FILE, decltype(&std::fclose)> file;
  int previous = -1;
};

int compile(const lsp::Json &request,
            const std::shared_ptr<LibraryQueries> &queries,
            const std::shared_ptr<pipeline::FunctionQueries> &functions) {
  auto arguments = request.find("arguments");
  auto values = arguments ? arguments->asArray() : nullptr;
  if (!values || values->empty() ||
      values->size() >=
          static_cast<std::size_t>(std::numeric_limits<int>::max())) {
    std::cerr
        << "mettle: error[request]: expected a nonempty arguments array\n";
    return 2;
  }
  std::vector<std::string> strings{"mettle"};
  for (const auto &value : *values) {
    auto text = value.asString();
    if (!text || text->find('\0') != std::string::npos) {
      std::cerr
          << "mettle: error[request]: arguments must be strings without NUL\n";
      return 2;
    }
    strings.push_back(*text);
  }
  if (strings[1] != "check" && strings[1] != "build") {
    std::cerr << "mettle: error[request]: resident requests support check and "
                 "build\n";
    return 2;
  }
  std::vector<char *> argv;
  for (auto &value : strings)
    argv.push_back(value.data());
  argv.push_back(nullptr);
  auto selected = options(static_cast<int>(strings.size()), argv.data());
  if (!selected) {
    std::cerr << "mettle: invalid arguments; use --help\n";
    return 2;
  }
  selected->libraryQueries = queries;
  if (!selected->noCache)
    selected->functionQueries = functions;
  resetRuntimeIdentity();
  return run(*selected);
}
} // namespace

int compilationServer(std::istream &input, std::ostream &output) {
  auto queries = std::make_shared<LibraryQueries>();
  auto functions = std::make_shared<pipeline::FunctionQueries>();
  (void)compilerIdentity();
  std::string line;
  while (std::getline(input, line)) {
    auto request = line.size() <= limits::sourceBytes ? lsp::Json::parse(line)
                                                      : std::nullopt;
    std::string standardOutput, standardError;
    int status = 2;
    const auto previousHits = queries->hits();
    const auto previousFunctions = functions->hits();
    const auto previousInstances = functions->specializationHits();
    {
      std::cout.flush();
      std::cerr.flush();
      CapturedStream outputCapture(stdout), errorCapture(stderr);
      if (!request || request->type() != lsp::Json::Type::Object) {
        std::cerr
            << "mettle: error[request]: expected one JSON object per line\n";
      } else {
        try {
          status = compile(*request, queries, functions);
        } catch (const std::exception &error) {
          std::cerr << "mettle: error[internal]: " << error.what() << '\n';
          status = 1;
        }
      }
      std::cout.flush();
      std::cerr.flush();
      standardOutput = outputCapture.contents();
      standardError = errorCapture.contents();
    }
    auto id = request ? request->find("id") : nullptr;
    auto response = lsp::Json::object(
        {{"id", id ? *id : lsp::Json{}},
         {"status", lsp::Json::integer(status)},
         {"stdout", lsp::Json::string(std::move(standardOutput))},
         {"stderr", lsp::Json::string(std::move(standardError))},
         {"queryHits", lsp::Json::integer(queries->hits() - previousHits)},
         {"functionQueryHits",
          lsp::Json::integer(functions->hits() - previousFunctions)},
         {"instanceQueryHits",
          lsp::Json::integer(functions->specializationHits() -
                             previousInstances)}});
    output << response.dump() << '\n' << std::flush;
    if (!output)
      return 1;
  }
  return input.bad() ? 1 : 0;
}
} // namespace mettle::driver
