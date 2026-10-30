const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

async function main() {
  const app = process.argv[2];
  if (!app) {
    throw new Error("Pass VS Code's Resources/app path; run with its ELECTRON_RUN_AS_NODE binary.");
  }
  const bundled = path.join(app, "node_modules.asar");
  const textmate = require(path.join(bundled, "vscode-textmate"));
  const oniguruma = require(path.join(bundled, "vscode-oniguruma"));
  const wasm = fs.readFileSync(path.join(bundled, "vscode-oniguruma/release/onig.wasm"));
  await oniguruma.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));

  const extension = path.resolve(__dirname, "..");
  const manifest = JSON.parse(fs.readFileSync(path.join(extension, "package.json"), "utf8"));
  const language = manifest.contributes.languages.find(item => item.extensions.includes(".mt"));
  assert.equal(language.id, "mettle");
  const contribution = manifest.contributes.grammars.find(item => item.language === language.id);
  const grammarPath = path.join(extension, contribution.path);
  const raw = textmate.parseRawGrammar(fs.readFileSync(grammarPath, "utf8"), grammarPath);
  JSON.parse(fs.readFileSync(path.join(extension, language.configuration), "utf8"));
  const registry = new textmate.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: patterns => new oniguruma.OnigScanner(patterns),
      createOnigString: value => new oniguruma.OnigString(value)
    }),
    loadGrammar: async scope => scope === contribution.scopeName ? raw : null
  });
  const grammar = await registry.loadGrammar(contribution.scopeName);

  function tokenize(source) {
    let state = textmate.INITIAL;
    return source.split("\n").map(line => {
      const result = grammar.tokenizeLine(line, state);
      state = result.ruleStack;
      return result.tokens.map(token => ({
        text: line.slice(token.startIndex, token.endIndex),
        scopes: token.scopes
      }));
    });
  }

  function scoped(tokens, text, scope) {
    assert(tokens.some(token => token.text.includes(text) && token.scopes.includes(scope)),
      `Missing ${scope} for ${JSON.stringify(text)}: ${JSON.stringify(tokens)}`);
  }

  const declaration = tokenize("fn count(value: mut Vec<u8>): i32 throws Error {")[0];
  scoped(declaration, "count", "entity.name.function.mettle");
  scoped(declaration, "mut", "storage.modifier.mettle");
  scoped(declaration, "u8", "support.type.primitive.mettle");
  scoped(declaration, "throws", "keyword.control.mettle");

  const comments = tokenize("/* outer\n/* inner */ still outer\n*/ let value = 42");
  scoped(comments[1], "still outer", "comment.block.mettle");
  scoped(comments[2], "let", "storage.type.mettle");

  const rawString = tokenize('let text = r##"quote "# // text"##; let done = true')[0];
  scoped(rawString, "// text", "string.quoted.double.raw.mettle");
  scoped(rawString, "done", "source.mettle");
  scoped(rawString, "true", "constant.language.mettle");
  const afterRaw = rawString.find(token => token.text.includes("done"));
  assert(!afterRaw.scopes.some(scope => scope.startsWith("string.")));

  const escaped = tokenize(String.raw`let byte = b'\n'; let quoted = "a\"b"`)[0];
  scoped(escaped, String.raw`\n`, "constant.character.escape.mettle");
  scoped(escaped, String.raw`\"`, "constant.character.escape.mettle");

  const format = tokenize('f"{a < b} {call::<i32>(42)} {{brace}}"')[0];
  scoped(format, "<", "meta.interpolation.mettle");
  scoped(format, "42", "constant.numeric.integer.mettle");
  scoped(format, "{{", "constant.character.escape.mettle");
  const nested = tokenize('f"{call(const { 1 })} {\"}\"}"')[0];
  scoped(nested, "1", "meta.interpolation.mettle");
  scoped(nested, "}", "string.quoted.double.mettle");

  const numbers = tokenize("0..3 0xffu8 1.25f64 3e-2f32 7usize")[0];
  scoped(numbers, "..", "keyword.operator.mettle");
  for (const number of ["0xffu8", "7usize"]) {
    scoped(numbers, number, "constant.numeric.integer.mettle");
  }
  for (const number of ["1.25f64", "3e-2f32"]) {
    scoped(numbers, number, "constant.numeric.float.mettle");
  }
  scoped(tokenize("fn `read`(): Unit {}")[0], "`read`", "entity.name.function.mettle");
  const malformed = tokenize('let text = "unfinished\nfn next(): Unit {}');
  scoped(malformed[1], "next", "entity.name.function.mettle");

  const root = path.resolve(extension, "../..");
  let files = 0;
  for (const directory of ["examples", "library", "tests"]) {
    function walk(current) {
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const file = path.join(current, entry.name);
        if (entry.isDirectory()) walk(file);
        else if (entry.name.endsWith(".mt")) {
          tokenize(fs.readFileSync(file, "utf8"));
          files += 1;
        }
      }
    }
    walk(path.join(root, directory));
  }
  registry.dispose();
  console.log(`Mettle language registration and grammar cases passed; tokenized ${files} .mt files.`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
