# Mettle language support for VS Code

Local, declarative support for `.mt` and `.mettle` files: language recognition, syntax
highlighting, comment toggling, bracket pairs and four-space indentation.
It registers the language as **Mettle**, not Rust. No executable extension code,
language server, completion, compiler diagnostics or formatter is included.
Highlighting is lexical, not proof that the compiler accepts a construct.

The grammar covers contextual `extend` declarations, `from` view sources,
`any`/`some` types, `unsized` bounds, negative implementations, `format`
parameters and macro definitions. Ordinary methods such as `.extend()` remain
identifiers. Tuple field chains stay distinct from decimal literals; logical,
range and variadic operators are highlighted as complete tokens.

Generic brackets have their own punctuation scope and participate in VS Code's
bracket matching/coloring. Comparisons and shifts remain operators and are
excluded from bracket pairing. Typing `<` does not automatically insert `>`.
Declaration parameter lists support multiple lines; complete same-line
type/call argument lists are balanced before recognizing their brackets,
including nested generics and const-expression braces. Calls, macro invocations
and metavariables have dedicated scopes. An unfinished interpolated string
does not carry its interpolation scope into the next source line.

This is a TextMate grammar, not the compiler parser or semantic highlighting.
Ambiguous, incomplete, commented or multiline type/call argument references
can still fall back to operator highlighting. Capitalization is a convention,
not name resolution; highlighting cannot identify every type, field or variant.

Package and lock files (`.mettle`) use **Mettle Data**, a separate grammar for
Mettle's data format, not JSON or Mettle source. It highlights unquoted and
quoted keys, object shorthand, strings and escapes, numbers, booleans, `none`
and nested comments. Objects and arrays support bracket pairing and indentation.

## Package and install locally

With the existing `vsce` tool, from this directory:

```sh
vsce package --no-dependencies --allow-missing-repository --skip-license \
  --out ../../build/mettle-language-0.0.4.vsix
code --install-extension ../../build/mettle-language-0.0.4.vsix
```

`--skip-license` packages this unpublished local extension without selecting a
project license. Do not publish it without the repository owner's decisions.
The output stays in the ignored build directory.

On macOS, if `code` is not on PATH, use:

```sh
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
  --install-extension ../../build/mettle-language-0.0.4.vsix
```

Run **Developer: Reload Window** if an already-open editor still shows
Plain Text. Its language-mode indicator should read **Mettle** for `.mt`
or **Mettle Data** for `.mettle`.

On Windows (PowerShell), from this directory:

```powershell
vsce package --no-dependencies --allow-missing-repository --skip-license `
  --out ..\..\build\mettle-language-0.0.4.vsix
code --install-extension ..\..\build\mettle-language-0.0.4.vsix
```

## Validate

The test uses VS Code's own bundled TextMate and Oniguruma engines; it installs
no npm packages. From the repository root on macOS:

```sh
ELECTRON_RUN_AS_NODE=1 \
  "/Applications/Visual Studio Code.app/Contents/MacOS/Code" \
  tools/vscode/test/grammar.cjs \
  "/Applications/Visual Studio Code.app/Contents/Resources/app"
```

For another desktop installation, pass its application resource directory and
use its Electron/Code executable in Node mode. The test checks representative
token scopes and tokenizes the current compiler, example, library and test `.mt`
and `.mettle` corpus.

On Windows (PowerShell), from the repository root:

```powershell
$install = "$env:LOCALAPPDATA\Programs\Microsoft VS Code"
# Use the resources\app path referenced by the installed bin\code.cmd.
$app = "$install\resources\app"
$env:ELECTRON_RUN_AS_NODE = "1"
& "$install\Code.exe" tools\vscode\test\grammar.cjs $app 2>&1 | Out-String
```

Some VS Code releases put `resources\app` under a versioned subdirectory.
Adjust `$install` for a system-wide or custom installation and `$app` to match
the installed launcher.
