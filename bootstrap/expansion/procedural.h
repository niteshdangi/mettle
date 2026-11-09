#pragma once

#include <functional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::expansion {
// The procedural macro protocol. A macro is a host program: the compiler
// writes one request to its standard input and reads one response from its
// standard output. Both are line based and versioned independently of the
// compiler internals; a reader rejects another major version.
//
// Request (API 1.0):
//   mettle-macro 1.0
//   name NAME
//   tok KIND SPACED TEXT      one line per argument token, in order
// KIND is the token kind (`word`, `integer`, `symbol`, `newline`, ...);
// SPACED is 1 when whitespace preceded the token, else 0; the token's index
// is its identity. TEXT is escaped (see `escapeField`) and runs to the end of
// the line.
//
// Response lines, each starting with `mettle:` (other lines are ignored):
//   text=ESCAPED               append source text to the output
//   error=ESCAPED              fail the invocation with a message
//   rerun-if-changed=PATH      declared input: file or directory (relative to
//                              the macro's package directory)
//   rerun-if-env-changed=VAR   declared input: environment variable
//   reproducible               the output is a function of the request and the
//                              declared inputs
constexpr unsigned procedureApiMajor = 1, procedureApiMinor = 0;

// `\` becomes `\\`, a line feed `\n` and a carriage return `\r`, so any text
// fits on one line.
std::string escapeField(std::string_view text);
std::string unescapeField(std::string_view text);

struct ProcedureToken {
  std::string kind, text;
  bool spaced = false;
};
std::string encodeRequest(const std::string &name,
                          const std::vector<ProcedureToken> &tokens);

struct ProcedureResponse {
  // The generated source text, to be re-lexed and re-parsed.
  std::string text;
  std::vector<std::string> errors, files, variables;
  bool reproducible = false;
  // Why no response exists: the program did not build or run, or its output
  // violates the protocol. Empty for a well-formed response.
  std::string fault;
};
// Parses the standard output of a macro program.
ProcedureResponse parseResponse(const std::string &output);

// The procedural macros available to a build and how to run one. `run`
// receives the macro name and the encoded request.
struct Procedures {
  std::set<std::string> names;
  std::function<ProcedureResponse(const std::string &name,
                                  const std::string &request)>
      run;
};
} // namespace mettle::expansion
