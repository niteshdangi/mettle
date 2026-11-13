// Host side of procedural macros (API 1.0). A macro is a program that the
// compiler builds for the host and runs once per `name!(...)` invocation: it
// reads the argument tokens from standard input, writes generated source text
// to standard output, and may declare the external inputs its result depends
// on. The compiler re-lexes and re-parses the text; every generated token is
// attributed to the invocation. The wire format is documented in
// compiler/expansion/procedural.h; a different major version is rejected.
import alloc.vec
import alloc.vec.List
import alloc.string
import alloc.string.String
import core.cmp.PartialEq
import core.fmt
import core.fmt.Debug
import core.iter.Iterator
import core.text.Text
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
    let decoded = capture alloc.string.from_utf8(bytes)
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
    let decoded = capture alloc.string.from_utf8(out)
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
        var options = fmt.spec()
        options.alternate = true
        var formatter = fmt.formatter(mut output, options)
        match capture T.(Debug).fmt(read value, mut formatter) {
            success(_) => {},
            failure(_) => { core.panic.panic("debug formatting failed") }
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

pub fn format(message: format fmt.Message): String {
    var output = string.new()
    match capture output.write_fmt(message) {
        success(_) => {},
        failure(_) => { core.panic.panic("formatting failed") }
    }
    output
}

pub fn println(message: format fmt.Message): Unit {
    let guard = io.stdout().lock()
    io.print(message)
    io.print("\n")
    core.mem.drop(take guard)
}

pub fn eprintln(message: format fmt.Message): Unit {
    let guard = io.stderr().lock()
    io.eprint(message)
    io.eprint("\n")
    core.mem.drop(take guard)
}

fn panic_with_prefix(read prefix: Text, message: format fmt.Message): Never {
    var output = string.from_text(prefix)
    match capture output.write_fmt(message) {
        success(_) => {},
        failure(_) => { core.panic.panic("formatting failed") }
    }
    core.panic.panic(output.as_text())
}

fn assertion_values<T: Debug, U: Debug>(read left: T, read right: U): String {
    var output = string.new()
    output.push_str("\n  left: ")
    let left_text = debug_text(left)
    output.push_str(left_text.as_text())
    output.push_str("\n right: ")
    let right_text = debug_text(right)
    output.push_str(right_text.as_text())
    output
}

fn assertion_failure<T: Debug, U: Debug>(
    read left: T,
    read right: U,
    read operator: Text
): Never {
    var output = string.from_text("assertion failed: left ")
    output.push_str(operator)
    output.push_str(" right")
    let values = assertion_values(left, right)
    output.push_str(values.as_text())
    core.panic.panic(output.as_text())
}

fn assertion_failure_with_message<T: Debug, U: Debug>(
    read left: T,
    read right: U,
    read operator: Text,
    read message: String
): Never {
    var output = string.from_text("assertion failed: left ")
    output.push_str(operator)
    output.push_str(" right: ")
    output.push_str(message.as_text())
    let values = assertion_values(left, right)
    output.push_str(values.as_text())
    core.panic.panic(output.as_text())
}

fn assert_values<T: PartialEq<U> + Debug, U: Debug>(
    read left: T,
    read right: U,
    expected_equal: bool,
    read operator: Text
) {
    if (left == right) != expected_equal {
        assertion_failure(left, right, operator)
    }
}

pub macro assert_eq {
    ($left:expr, $right:expr $(,)?) => {
        assert_values($left, $right, true, "==")
    };
    ($left:expr, $right:expr, $message:expr $(,)?) => {
        {
            let left = read $left
            let right = read $right
            if !(*left == *right) {
                assertion_failure_with_message(*left, *right, "==", format($message))
            }
        }
    };
}

pub macro assert_ne {
    ($left:expr, $right:expr $(,)?) => {
        assert_values($left, $right, false, "!=")
    };
    ($left:expr, $right:expr, $message:expr $(,)?) => {
        {
            let left = read $left
            let right = read $right
            if *left == *right {
                assertion_failure_with_message(*left, *right, "!=", format($message))
            }
        }
    };
}

pub macro todo {
    () => { core.panic.panic("not yet implemented") };
    ($message:expr $(,)?) => { panic_with_prefix("not yet implemented: ", $message) };
}

pub macro unimplemented {
    () => { core.panic.panic("not implemented") };
    ($message:expr $(,)?) => { panic_with_prefix("not implemented: ", $message) };
}
