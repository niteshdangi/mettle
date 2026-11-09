#pragma once

#include "documentation/document.h"
#include <string>
#include <vector>

namespace mettle::documentation {
// What a fenced code block in documentation asks of the test runner.
enum class Mode { Run, NoRun, Ignore, ShouldPanic, CompileFail };

// The fence info string is a comma/space separated list: `mettle` (default,
// may be omitted), `no_run`, `ignore`, `should_panic`, `compile_fail` or
// `compile_fail(PHASE)`. Any other word (`text`, `sh`, ...) marks a block that
// is not Mettle source.
struct Fence {
  bool mettle = true;
  Mode mode = Mode::Run;
  std::string phase;
};
Fence classify(const std::string &info);

// A code line starting with `~ ` (or only `~`) is compiled but not rendered.
bool hidden(const std::string &line);
std::string unhidden(const std::string &line);

// An executable example: the body of a function, or a whole program when it
// declares `fn main()`. `name` is `PAGE - OWNER (line N)`.
struct Example {
  std::string name;
  std::size_t line = 0;
  Mode mode = Mode::Run;
  std::string phase, code;
};
// The examples of a page in source order.
std::vector<Example> examples(const Page &page);

// The name of the generated test function of `examples[index]`.
std::string testName(std::size_t index);
// `source` followed by one `@test` function per picked example, so that each
// runs in its own process of the ordinary test harness.
std::string withTests(const std::string &source,
                      const std::vector<Example> &examples,
                      const std::vector<std::size_t> &picks);
} // namespace mettle::documentation
