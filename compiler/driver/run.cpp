#include "driver/inspect.h"
#include "driver/options.h"
#include "driver/output.h"
#include "pipeline/compile.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "llvm/Support/MemoryBuffer.h"
#include <iostream>

namespace mettle::driver {
int run(const Options &options) {
  auto buffer = llvm::MemoryBuffer::getFile(options.input);
  if (!buffer) {
    std::cerr << "mettle: error[io]: cannot read " << options.input << ": "
              << buffer.getError().message() << '\n';
    return 1;
  }
  Source source{options.input, (*buffer)->getBuffer().str()};
  Diagnostics diagnostics;
  if (options.command == "tokens" || options.command == "syntax") {
    Module tree;
    if (options.command == "tokens")
      tree.tokens = tokenize(source, diagnostics);
    else
      tree = parse(source, diagnostics);
    inspect(tree);
    diagnostics.print(source, std::cerr);
    return diagnostics.empty() ? 0 : 1;
  }
  auto program = pipeline::compile(source, diagnostics);
  if (!program) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  return options.command == "check" ? 0 : emit(options, source, *program);
}
} // namespace mettle::driver
