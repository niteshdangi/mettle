# Mettle language support for VS Code

Local, declarative support for `.mt` files: language recognition, syntax
highlighting, comment toggling, bracket pairs and four-space indentation.
It registers the language as **Mettle**, not Rust. No executable extension code,
language server, completion, compiler diagnostics or formatter is included.
Highlighting is lexical, not proof that the compiler accepts a construct.

## Package and install locally

With the existing `vsce` tool, from this directory:

```sh
vsce package --no-dependencies --allow-missing-repository --skip-license \
  --out ../../build/mettle-language-0.0.1.vsix
code --install-extension ../../build/mettle-language-0.0.1.vsix
```

`--skip-license` packages this unpublished local extension without selecting a
project license. Do not publish it without the repository owner's decisions.
The output stays in the ignored build directory.

On macOS, if `code` is not on PATH, use:

```sh
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
  --install-extension ../../build/mettle-language-0.0.1.vsix
```

Run **Developer: Reload Window** if an already-open `.mt` editor still shows
Plain Text. Its language-mode indicator should then read **Mettle**.

## Validate

The test uses VS Code's own bundled TextMate and Oniguruma engines; it installs
no npm packages. From the repository root on macOS:

```sh
ELECTRON_RUN_AS_NODE=1 \
  "/Applications/Visual Studio Code.app/Contents/MacOS/Code" \
  tools/vscode/test/grammar.cjs \
  "/Applications/Visual Studio Code.app/Contents/Resources/app"
python3 tools/check_quality.py
```

For another desktop installation, pass its application resource directory and
use its Electron/Code executable in Node mode. The test checks representative
token scopes and tokenizes the current example, library and test `.mt` corpus.
