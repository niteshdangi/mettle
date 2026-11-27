import alloc.hash_map.Set
import alloc.string
import alloc.string.{ String, from_text }
import alloc.vec.List
import core.text.Text
import std.macros.format

pub copy enum Kind { Object, Array, String, Integer, Number, Boolean, Nil }

extend Kind {
    pub fn is(other: Kind): bool { (self as u32) == (other as u32) }
}

pub copy type Range { pub begin: u32; pub end: u32 }
pub type DataError { pub span: Range; pub message: String }
pub type Node {
    pub kind: Kind
    pub key: String
    pub key_span: Range
    pub span: Range
    pub text: String
    pub next: usize
}
pub type Data { pub nodes: List<Node> }

extend Data {
    pub fn field(object: usize, read key: Text): usize? {
        var child = object + 1
        while child < self.nodes[object].next {
            if self.nodes[child].key.as_text() == key { return present(child) }
            child = self.nodes[child].next
        }
        none
    }
}

fn digit(c: u8): bool { c >= b'0' && c <= b'9' }
pub fn alpha(c: u8): bool { (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') }
fn key_start(c: u8): bool { alpha(c) || c == b'_' }
fn key_part(c: u8): bool { key_start(c) || digit(c) }

type Parser<region r> {
    input: read Text from r
    position: usize
    data: Data
}

extend<region r> Parser<region r> {
    fn end(): bool { self.position == self.input.len() }
    fn peek(): u8 { if self.end() { 0u8 } else { self.input.as_bytes()[self.position] } }
    fn pair(first: u8, second: u8): bool {
        self.input.len() - self.position >= 2 && self.peek() == first && self.input.as_bytes()[self.position + 1] == second
    }
    fn span(begin: usize): Range { Range(begin as u32, self.position as u32) }
    fn diagnostic(begin: usize, read message: Text): DataError {
        let end = if self.position <= begin && begin < self.input.len() { begin + 1 } else { self.position }
        DataError(Range(begin as u32, end as u32), from_text(message))
    }
    fn spelling(begin: usize): String {
        from_text(self.input.split_at(begin).1.split_at(self.position - begin).0)
    }
    mut fn skip(): bool throws DataError {
        var newline = false
        while !self.end() {
            let c = self.peek()
            if c == b' ' || (c >= 9u8 && c <= 13u8) {
                newline = newline || c == 10u8 || c == 13u8
                self.position += 1
            } else if self.pair(b'/', b'/') {
                while !self.end() && self.peek() != 10u8 && self.peek() != 13u8 { self.position += 1 }
            } else if self.pair(b'/', b'*') {
                let begin = self.position
                self.position += 2
                var depth = 1usize
                while !self.end() && depth != 0 {
                    if self.pair(b'/', b'*') {
                        depth += 1
                        self.position += 2
                    } else if self.pair(b'*', b'/') {
                        depth -= 1
                        self.position += 2
                    } else {
                        newline = newline || self.peek() == 10u8 || self.peek() == 13u8
                        self.position += 1
                    }
                }
                if depth != 0 { throw self.diagnostic(begin, "unterminated block comment") }
            } else { break }
        }
        newline
    }
    mut fn separator(close: u8): Unit throws DataError {
        let newline = try self.skip()
        if self.peek() == b',' {
            self.position += 1
            let _ = try self.skip()
        } else if !self.end() && self.peek() != close && !newline {
            throw self.diagnostic(self.position, "expected a newline or ',' between entries")
        }
    }
    mut fn hex(begin: usize): u32 throws DataError {
        let c = self.peek()
        let value = if digit(c) { c - b'0' }
            else if c >= b'a' && c <= b'f' { c - b'a' + 10u8 }
            else if c >= b'A' && c <= b'F' { c - b'A' + 10u8 }
            else { throw self.diagnostic(begin, "invalid hexadecimal escape") }
        self.position += 1
        value as u32
    }
    mut fn quoted(): String throws DataError {
        let begin = self.position
        self.position += 1
        var out = string.new()
        loop {
            let start = self.position
            while self.peek() >= 32u8 && self.peek() != b'"' && self.peek() != b'\\' { self.position += 1 }
            out.push_str(self.input.split_at(start).1.split_at(self.position - start).0)
            if self.end() { throw self.diagnostic(begin, "unterminated string") }
            let c = self.peek()
            self.position += 1
            if c == b'"' { return out }
            if c != b'\\' { throw self.diagnostic(begin, "unescaped control character in string") }
            if self.end() { throw self.diagnostic(begin, "unterminated string") }
            let escape = self.peek()
            let at = self.position - 1
            self.position += 1
            let code = match escape {
                b'n' => 10u32, b'r' => 13u32, b't' => 9u32, b'0' => 0u32,
                b'\\' | b'"' | b'\'' => escape as u32,
                b'x' => {
                    let high = try self.hex(at)
                    let code = high * 16 + try self.hex(at)
                    if code > 127 { throw self.diagnostic(at, "text byte escape must not exceed 7f") }
                    code
                },
                b'u' => {
                    if self.peek() != b'{' { throw self.diagnostic(at, "Unicode escape requires '\\u{hex}'") }
                    self.position += 1
                    let digits = self.position
                    var scalar = 0u32
                    while self.peek() != b'}' && self.position - digits < 6 {
                        scalar = scalar * 16 + try self.hex(at)
                    }
                    if self.peek() != b'}' || self.position == digits { throw self.diagnostic(at, "invalid Unicode scalar escape") }
                    self.position += 1
                    scalar
                },
                _ => { throw self.diagnostic(at, "invalid string escape") }
            }
            let present(scalar) = core.char.from_u32(code) else { throw self.diagnostic(at, "invalid Unicode scalar escape") }
            out.push(scalar)
        }
    }
    mut fn key(): String throws DataError {
        if self.peek() == b'"' { return try self.quoted() }
        let begin = self.position
        if !key_start(self.peek()) { throw self.diagnostic(begin, "expected an identifier or quoted key") }
        while key_part(self.peek()) || self.peek() == b'-' { self.position += 1 }
        self.spelling(begin)
    }
    mut fn number(begin: usize): Kind throws DataError {
        if self.peek() == b'-' { self.position += 1 }
        let start = self.position
        let zero = self.peek() == b'0'
        while digit(self.peek()) { self.position += 1 }
        if self.position == start || (zero && self.position - start > 1) { throw self.diagnostic(begin, "invalid decimal number") }
        var fractional = false
        if self.peek() == b'.' {
            self.position += 1
            let point = self.position
            while digit(self.peek()) { self.position += 1 }
            if self.position == point { throw self.diagnostic(begin, "expected digits after decimal point") }
            fractional = true
        }
        if self.peek() == b'e' || self.peek() == b'E' {
            self.position += 1
            if self.peek() == b'+' || self.peek() == b'-' { self.position += 1 }
            let exponent = self.position
            while digit(self.peek()) { self.position += 1 }
            if self.position == exponent { throw self.diagnostic(begin, "expected exponent digits") }
            fractional = true
        }
        if fractional { return Kind.Number }
        let digits = self.position - start
        if digits > 19 { throw self.diagnostic(begin, "integer out of range") }
        if digits == 19 {
            let spelling = self.spelling(start)
            let maximum = if start == begin { "9223372036854775807" } else { "9223372036854775808" }
            if spelling.as_text() > maximum { throw self.diagnostic(begin, "integer out of range") }
        }
        Kind.Integer
    }
    mut fn children(close: u8, object: bool, depth: u32): Unit throws DataError {
        let begin = self.position
        if close != 0u8 { self.position += 1 }
        var keys = Set<String>()
        let _ = try self.skip()
        while !self.end() && (close == 0u8 || self.peek() != close) {
            let key_begin = self.position
            let key = if object { try self.key() } else { string.new() }
            let key_span = self.span(key_begin)
            if object {
                if !keys.insert(from_text(key.as_text())) {
                    let name = key.as_text()
                    throw DataError(key_span, format(f"duplicate key '{name}'"))
                }
                let _ = try self.skip()
                if self.peek() != b'{' {
                    if self.peek() != b':' { throw self.diagnostic(self.position, "expected ':' or '{' after key") }
                    self.position += 1
                    let _ = try self.skip()
                }
            }
            try self.value(take key, key_span, depth + 1, false)
            try self.separator(close)
        }
        if close != 0u8 {
            if self.end() {
                let message: read Text = if object { "unterminated object" } else { "unterminated list" }
                throw self.diagnostic(begin, message)
            }
            self.position += 1
        }
    }
    mut fn value(take key: String, key_span: Range, depth: u32, unbraced: bool): Unit throws DataError {
        if depth > 128 { throw self.diagnostic(self.position, "data nesting limit exceeded") }
        if self.data.nodes.len() > 67108864 { throw self.diagnostic(self.position, "data value limit exceeded") }
        let begin = self.position
        let index = self.data.nodes.len()
        self.data.nodes.push(Node(Kind.Nil, take key, key_span, Range(0, 0), string.new(), 0))
        let c = self.peek()
        var text = string.new()
        let kind = if unbraced || c == b'{' {
            try self.children(if unbraced { 0u8 } else { b'}' }, true, depth)
            Kind.Object
        } else if c == b'[' {
            try self.children(b']', false, depth)
            Kind.Array
        } else if c == b'"' {
            text = try self.quoted()
            Kind.String
        } else if digit(c) || c == b'-' {
            let number = try self.number(begin)
            text = self.spelling(begin)
            number
        } else {
            while key_part(self.peek()) { self.position += 1 }
            text = self.spelling(begin)
            let word = text.as_text()
            if word == "true" || word == "false" { Kind.Boolean }
            else if word == "none" { Kind.Nil }
            else { throw self.diagnostic(begin, "expected a data value") }
        }
        let span = self.span(begin)
        let next = self.data.nodes.len()
        self.data.nodes[index].kind = kind
        self.data.nodes[index].span = span
        self.data.nodes[index].text = take text
        self.data.nodes[index].next = next
    }
}

pub fn parse(read input: Text): Data throws DataError {
    var parser = Parser(read input, 0, Data(List<Node>()))
    let _ = try parser.skip()
    let first = parser.peek()
    try parser.value(string.new(), Range(0, 0), 0, first != b'{' && first != b'[')
    let _ = try parser.skip()
    if !parser.end() { throw parser.diagnostic(parser.position, "unexpected text after data") }
    take parser.data
}

@test
fn escaped_keys_and_nested_entries(): Unit throws DataError {
    let table = try parse("dependencies { /* outer /* inner */\n */\n \"\\u{61}\" { path: \"../dep\", flags: [true, none] }\n}\nversion: \"1.0.0\"\n")
    let dependencies = table.field(0, "dependencies").or_panic()
    let dependency = table.field(dependencies, "a").or_panic()
    let path = table.field(dependency, "path").or_panic()
    let version = table.field(0, "version").or_panic()
    assert(table.nodes[path].text.as_text() == "../dep" && table.nodes[version].text.as_text() == "1.0.0",
        "nested values hid sibling fields")
    match take capture parse("name: \"first\"\n\"\\x6eame\": \"second\"") {
        success(_) => assert(false, "escaped duplicate key accepted"),
        failure(issue) => {
            assert(issue.span.begin == 14 && issue.message.as_text() == "duplicate key 'name'", "wrong duplicate-key diagnostic")
        }
    }
}
