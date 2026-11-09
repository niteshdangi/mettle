#pragma once

namespace mettle::driver {
// `mettle lsp [--library-dir DIR] [--target TRIPLE] [--freestanding]`: the
// language server on standard input and output. Returns the process status,
// or 2 for invalid arguments.
int languageServer(int argc, char **argv);
} // namespace mettle::driver
