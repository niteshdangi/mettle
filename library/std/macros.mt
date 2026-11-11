// Host side of procedural macros (API 1.0). A macro is a program that the
// compiler builds for the host and runs once per `name!(...)` invocation: it
// reads the argument tokens from standard input, writes generated source text
// to standard output, and may declare the external inputs its result depends
// on. The compiler re-lexes and re-parses the text; every generated token is
// attributed to the invocation. The wire format is documented in
// compiler/expansion/procedural.h; a different major version is rejected.
import package.alloc.vec
import package.alloc.vec.List
import package.alloc.string
import package.alloc.string.String
import package.core.fmt
import package.core.fmt.Debug
import package.core.iter.Iterator
import package.core.text.Text
import super.io
import super.io.{Error, ErrorKind, Reader, Writer}

// One argument token. `kind` is the compiler's token kind (`word`, `integer`,
// `symbol`, `newline`, `text`, ...); `spaced` tells whether whitespace preceded
// it in the invocation.
pub type Token { pub kind: String; pub text: String; pub spaced: bool }

// What the invocation passed: the macro's name and its argument tokens.
pub type Invocation { pub name: String; pub tokens: List<Token> }

extend Invocation {
    // The argument tokens as source text, spaced as written.
    pub fn text(): String {
        var out = string.new()
        var i = 0usize
        while i < self.tokens.len() {
            match self.tokens.get(i) {
                present(t) => {
                    if t.spaced && i > 0usize { out.push_str(" ") }
                    out.push_str(t.text.as_text())
                },
                none => {}
            }
            i += 1usize
        }
        out
    }
}

fn invalid(): Error { io.from_kind(ErrorKind.InvalidData) }

fn read_request(): String throws Error {
    var bytes = vec.new<u8>()
    var input = io.stdin()
    let n = try input.read_to_end(bytes)
    let decoded = capture package.alloc.string.from_utf8(bytes)
    match take decoded {
        success(s) => s,
        failure(e) => throw invalid()
    }
}

fn unescape(read text: Text): String throws Error {
    let bytes = text.as_bytes()
    var out = vec.with_capacity<u8>(bytes.len())
    var i = 0usize
    while i < bytes.len() {
        let b = bytes[i]
        if b == 92u8 && i + 1usize < bytes.len() {
            i += 1usize
            let c = bytes[i]
            if c == 110u8 { out.push(10u8) } else if c == 114u8 { out.push(13u8) } else { out.push(c) }
        } else {
            out.push(b)
        }
        i += 1usize
    }
    let decoded = capture package.alloc.string.from_utf8(out)
    match take decoded {
        success(s) => s,
        failure(e) => throw invalid()
    }
}

fn escape(read text: Text): List<u8> {
    let bytes = text.as_bytes()
    var out = vec.with_capacity<u8>(bytes.len())
    var i = 0usize
    while i < bytes.len() {
        let b = bytes[i]
        if b == 92u8 { out.push(92u8); out.push(92u8) } else if b == 10u8 { out.push(92u8); out.push(110u8) } else if b == 13u8 { out.push(92u8); out.push(114u8) } else { out.push(b) }
        i += 1usize
    }
    out
}

// Reads the request from standard input. Fails with `InvalidData` when the
// request is malformed or speaks another major API version.
pub fn read_invocation(): Invocation throws Error {
    let raw = try read_request()
    var name = string.new()
    var tokens = vec.new<Token>()
    var versioned = false
    var named = false
    let view = raw.as_text()
    var lines = view.lines()
    var more = true
    while more {
        match lines.next() {
            present(line) => {
                if line.starts_with("mettle-macro ") {
                    if versioned || named { throw invalid() }
                    if !line.starts_with("mettle-macro 1.") { throw invalid() }
                    let minor = match line.get(15usize, line.len()) {
                        present(value) => value.as_bytes(),
                        none => throw invalid()
                    }
                    if minor.is_empty() { throw invalid() }
                    var index = 0usize
                    while index < minor.len() {
                        if minor[index] < 48u8 || minor[index] > 57u8 { throw invalid() }
                        index += 1usize
                    }
                    versioned = true
                } else if line.starts_with("name ") {
                    if !versioned || named { throw invalid() }
                    match line.split_once(" ") {
                        present(a) => {
                            if a.1.is_empty() { throw invalid() }
                            name = string.from_text(a.1)
                        },
                        none => { throw invalid() }
                    }
                    named = true
                } else if line.starts_with("tok ") {
                    if !named { throw invalid() }
                    match line.split_once(" ") {
                        present(a) => match a.1.split_once(" ") {
                            present(b) => match b.1.split_once(" ") {
                                present(c) => {
                                    if b.0.is_empty() || (c.0 != "0" && c.0 != "1") {
                                        throw invalid()
                                    }
                                    let text = try unescape(c.1)
                                    tokens.push(Token(string.from_text(b.0), text, c.0 == "1"))
                                },
                                none => { throw invalid() }
                            },
                            none => { throw invalid() }
                        },
                        none => { throw invalid() }
                    }
                } else { throw invalid() }
            },
            none => { more = false }
        }
    }
    if !versioned || !named { throw invalid() }
    Invocation(name, tokens)
}

fn put(read key: Text, read value: Text): Unit throws Error {
    var out = io.stdout()
    let body = escape(value)
    try out.write_all("mettle:".as_bytes())
    try out.write_all(key.as_bytes())
    try out.write_all("=".as_bytes())
    try out.write_all(body.as_slice())
    try out.write_all("\n".as_bytes())
}

// Appends `text` to the generated source exactly (include the line breaks).
pub fn emit(read text: Text): Unit throws Error { try put("text", text) }

// Fails the invocation; the compiler reports `message` at the invocation.
pub fn fail(read message: Text): Unit throws Error { try put("error", message) }

// Declares a file or directory (relative to the macro's package directory)
// that the output depends on.
pub fn depends_on_file(read path: Text): Unit throws Error { try put("rerun-if-changed", path) }

// Declares an environment variable that the output depends on.
pub fn depends_on_env(read name: Text): Unit throws Error { try put("rerun-if-env-changed", name) }

// Promises that the output is a function of the arguments and the declared
// inputs, which lets the compiler reuse it. Without this the macro reruns on
// every build.
pub fn reproducible(): Unit throws Error {
    var out = io.stdout()
    try out.write_all("mettle:reproducible\n".as_bytes())
}

fn debug_text<T: Debug>(read value: T): String {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(read value, mut formatter) {
            success(_) => {},
            failure(_) => { package.core.panic.panic("debug formatting failed") }
        }
    }
    output
}

pub fn debug_value<T: Debug>(take value: T): T {
    let rendered = debug_text(read value)
    io.eprint(f"{rendered}\n")
    value
}

pub macro dbg {
    ($value:expr $(,)?) => { debug_value($value) };
    ($first:expr, $($rest:expr),+ $(,)?) => { (debug_value($first), $(debug_value($rest)),+) };
}

pub macro matches {
    ($value:expr, $pattern:pat if $guard:expr $(,)?) => {
        match $value { $pattern if $guard => true, _ => false }
    };
    ($value:expr, $pattern:pat $(,)?) => { match $value { $pattern => true, _ => false } };
}

pub macro format_args {
    ($message:expr) => { $message };
}

pub macro todo {
    () => { package.core.panic.panic("not yet implemented") };
    ($message:expr) => { package.core.panic.panic($message) };
}

pub macro unimplemented {
    () => { package.core.panic.panic("not implemented") };
    ($message:expr) => { package.core.panic.panic($message) };
}
