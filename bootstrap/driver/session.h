#pragma once

#include <iosfwd>
#include <memory>
#include <optional>

namespace mettle::lsp {
class Json;
}
namespace mettle::pipeline {
class FunctionQueries;
}

namespace mettle::driver {
class LibraryQueries;
struct Options;
class CompilationSession {
public:
  CompilationSession();
  lsp::Json request(const lsp::Json &request);

private:
  std::shared_ptr<LibraryQueries> queries;
  std::shared_ptr<pipeline::FunctionQueries> functions;
};
int compilationServer(std::istream &input, std::ostream &output);
std::optional<int> residentCompilation(const Options &options, int argc,
                                       char **argv);
int stopResidentCompilation(const Options &options);
}
