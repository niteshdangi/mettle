# Native formatter

`mettle_editor.format_source(read bytes: [u8], source: u32)` returns an owned
`List<u8>` or throws `FormatError`. It reads source bytes without retaining
them or performing I/O. Invalid input returns native syntax diagnostics
with the supplied source ID; a candidate that changes tokens or syntax or
fails the fixed-point check returns no bytes.

The formatter normalizes indentation and horizontal gaps. It preserves line
endings (including blank lines and a missing final newline), semicolons, and
the spelling of non-whitespace tokens. Macro invocations, token trees, and
interpolations keep their original contents. Syntax comparison uses the
unexpanded native tree; matching the bootstrap driver's post-expansion
validation requires an in-memory macro expansion hook. Wrapping and file
replacement are outside this API.
