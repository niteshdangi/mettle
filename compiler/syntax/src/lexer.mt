import alloc.vec.{ List, new }
import core.text.Text
import mettle_foundation.{ Span, invalid_utf8, SOURCE_BYTES }
import mettle_foundation.{ Diagnostics, Phase }
import super.token.{ Kind, Token }
import super.characters.character_value

pub type Lexed { pub tokens: List<Token>; pub diagnostics: Diagnostics }

type Scanner<region r> {
    bytes: read [u8] from r
    source: u32
    pos: usize
    after_dot: bool
    holes: List<usize>
    result: Lexed
}

fn word_start(byte: u8): bool {
    (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || byte == b'_'
}
fn digit(byte: u8): bool { byte >= b'0' && byte <= b'9' }
fn word_byte(byte: u8): bool { word_start(byte) || digit(byte) }
fn space(byte: u8): bool { byte == 32u8 || byte == 9u8 || byte == 11u8 || byte == 12u8 }
fn newline(byte: u8): bool { byte == 10u8 || byte == 13u8 }

extend<region r> Scanner<region r> {
    fn span(begin: usize, end: usize): Span { Span(self.source, begin as u32, end as u32) }
    fn at(read text: Text): bool {
        let pattern = text.as_bytes()
        if pattern.len() > self.bytes.len() - self.pos { return false }
        var index = 0usize
        while index < pattern.len() {
            if self.bytes[self.pos + index] != pattern[index] { return false }
            index += 1
        }
        true
    }
    mut fn error(phase: Phase, begin: usize, end: usize, read message: Text from static): Unit {
        let span = self.span(begin, end)
        self.result.diagnostics.report(phase, span, message)
    }
    mut fn add(kind: Kind, begin: usize): Unit {
        let span = self.span(begin, self.pos)
        self.result.tokens.push(Token(kind, span))
        match kind {
            Kind.Space => {}, Kind.Comment => {}, Kind.Newline => {},
            _ => { self.after_dot = self.pos == begin + 1 && self.bytes[begin] == b'.' }
        }
    }
    mut fn word(): Unit {
        while self.pos < self.bytes.len() && word_byte(self.bytes[self.pos]) { self.pos += 1 }
    }
    fn raw_quote(prefix: usize): usize? {
        var index = self.pos + prefix
        while index < self.bytes.len() && self.bytes[index] == b'#' { index += 1 }
        if index < self.bytes.len() && self.bytes[index] == b'"' { present(index) } else { none }
    }
    mut fn raw_text(quote: usize, begin: usize): Unit {
        let prefix = if self.bytes[begin] == b'b' { 2usize } else { 1usize }
        let fence = quote - begin - prefix
        self.pos = quote + 1
        var closed = false
        while self.pos < self.bytes.len() {
            let byte = self.bytes[self.pos]
            self.pos += 1
            if byte != b'"' { continue }
            var seen = 0usize
            while seen < fence && self.pos + seen < self.bytes.len() && self.bytes[self.pos + seen] == b'#' { seen += 1 }
            if seen == fence { self.pos += fence; closed = true; break }
        }
        if !closed { self.error(Phase.Lex, begin, self.pos, "unterminated raw text literal") }
        self.add(Kind.PrefixedText, begin)
    }
    mut fn quoted(quote: u8): bool {
        var escaped = false
        while self.pos < self.bytes.len() && !newline(self.bytes[self.pos]) {
            let byte = self.bytes[self.pos]
            self.pos += 1
            if byte == quote && !escaped { return true }
            escaped = byte == b'\\' && !escaped
        }
        false
    }
    mut fn format_text(): Unit {
        let begin = self.pos
        var piece = false
        var escaped = false
        while self.pos < self.bytes.len() && !newline(self.bytes[self.pos]) {
            let byte = self.bytes[self.pos]
            if byte == b'"' && !escaped {
                if piece { self.add(Kind.FormatPiece, begin) }
                let quote = self.pos
                self.pos += 1
                self.add(Kind.FormatClose, quote)
                return
            }
            if !escaped && (byte == b'{' || byte == b'}') {
                if self.pos + 1 < self.bytes.len() && self.bytes[self.pos + 1] == byte {
                    piece = true
                    self.pos += 2
                    continue
                }
                if byte == b'}' {
                    self.error(Phase.Lex, self.pos, self.pos + 1, "a single '}' in an f-string must be written '}}'")
                    self.pos += 1
                    continue
                }
                if piece { self.add(Kind.FormatPiece, begin) }
                let hole = self.pos
                self.pos += 1
                self.add(Kind.FormatHoleOpen, hole)
                self.holes.push(0usize)
                return
            }
            piece = true
            escaped = byte == b'\\' && !escaped
            self.pos += 1
        }
        if piece { self.add(Kind.FormatPiece, begin) }
        self.error(Phase.Lex, begin, self.pos, "unterminated f-string literal")
        self.holes.clear()
    }
    mut fn number(begin: usize): Unit {
        let based = self.at("0x") || self.at("0o") || self.at("0b")
        self.word()
        var floating = false
        if (!self.after_dot && !based && self.pos + 1 < self.bytes.len()
            && self.bytes[self.pos] == b'.' && digit(self.bytes[self.pos + 1])) {
            floating = true
            self.pos += 1
            self.word()
        }
        var exponent = begin
        while exponent < self.pos && (digit(self.bytes[exponent]) || self.bytes[exponent] == b'_' || self.bytes[exponent] == b'.') { exponent += 1 }
        if !based && exponent < self.pos && (self.bytes[exponent] == b'e' || self.bytes[exponent] == b'E') {
            floating = true
            if exponent == self.pos - 1 && self.pos < self.bytes.len() && (self.bytes[self.pos] == b'+' || self.bytes[self.pos] == b'-') {
                self.pos += 1
                self.word()
            }
        }
        if (!based && self.pos - begin >= 3 && self.bytes[self.pos - 3] == b'f'
            && ((self.bytes[self.pos - 2] == b'3' && self.bytes[self.pos - 1] == b'2')
                || (self.bytes[self.pos - 2] == b'6' && self.bytes[self.pos - 1] == b'4'))) { floating = true }
        self.add(if floating { Kind.Floating } else { Kind.Integer }, begin)
    }
    mut fn symbol(begin: usize): Unit {
        var width = 1usize
        if self.at("...") || self.at("..=") || self.at(">>=") || self.at("<<=") { width = 3 }
        else if (self.at("..") || self.at("==") || self.at("!=") || self.at("<=") || self.at(">=")
            || self.at("&&") || self.at("||") || self.at("+=") || self.at("-=") || self.at("*=")
            || self.at("/=") || self.at("%=") || self.at("&=") || self.at("|=") || self.at("^=")
            || self.at("<<") || self.at(">>") || self.at("->") || self.at("=>") || self.at("?.") || self.at("??")) { width = 2 }
        let byte = self.bytes[begin]
        self.pos += width
        if width == 1 {
            var valid = false
            for allowed in "(){}[],;:+-*/%!=<>&|^.?@$".as_bytes().bytes() {
                if byte == allowed { valid = true; break }
            }
            if !valid { self.error(Phase.Lex, begin, self.pos, "unsupported character or literal") }
        }
        if !self.holes.is_empty() && width == 1 {
            let last = self.holes.len() - 1
            if byte == b'{' { self.holes[last] += 1 }
            else if byte == b'}' {
                if self.holes[last] != 0 { self.holes[last] -= 1 }
                else {
                    self.add(Kind.FormatHoleClose, begin)
                    let _ = self.holes.pop()
                    self.format_text()
                    return
                }
            }
        }
        self.add(Kind.Symbol, begin)
    }
    mut fn scan(): Unit {
        while self.pos < self.bytes.len() && self.result.tokens.len() < 67108864usize {
            let begin = self.pos
            let byte = self.bytes[begin]
            if space(byte) {
                while self.pos < self.bytes.len() && space(self.bytes[self.pos]) { self.pos += 1 }
                self.add(Kind.Space, begin)
            } else if newline(byte) {
                if !self.holes.is_empty() {
                    self.error(Phase.Lex, begin, begin, "unterminated f-string literal")
                    self.holes.clear()
                }
                self.pos += 1
                if byte == 13u8 && self.pos < self.bytes.len() && self.bytes[self.pos] == 10u8 { self.pos += 1 }
                self.add(Kind.Newline, begin)
            } else if self.at("//") {
                while self.pos < self.bytes.len() && !newline(self.bytes[self.pos]) { self.pos += 1 }
                self.add(Kind.Comment, begin)
            } else if self.at("/*") {
                self.pos += 2
                var depth = 1usize
                while self.pos < self.bytes.len() && depth != 0 {
                    if self.at("/*") { depth += 1; self.pos += 2 }
                    else if self.at("*/") { depth -= 1; self.pos += 2 }
                    else { self.pos += 1 }
                }
                self.add(Kind.Comment, begin)
                if depth != 0 { self.error(Phase.Lex, begin, self.pos, "unterminated block comment") }
            } else if byte == b'`' {
                self.pos += 1
                let content = self.pos
                var valid = self.pos < self.bytes.len() && word_start(self.bytes[self.pos])
                while self.pos < self.bytes.len() && self.bytes[self.pos] != b'`' && !newline(self.bytes[self.pos]) {
                    valid = valid && word_byte(self.bytes[self.pos])
                    self.pos += 1
                }
                if self.pos == self.bytes.len() || self.bytes[self.pos] != b'`' {
                    self.error(Phase.Lex, begin, self.pos, "unterminated backtick identifier")
                } else { self.pos += 1 }
                if !valid || self.pos == content { self.error(Phase.Lex, begin, self.pos, "backtick contents must be an identifier") }
                self.add(Kind.QuotedWord, begin)
            } else if (byte == b'r' || self.at("br")) && self.raw_quote(if byte == b'b' { 2usize } else { 1usize }).is_present() {
                if let present(quote) = self.raw_quote(if byte == b'b' { 2usize } else { 1usize }) { self.raw_text(quote, begin) }
            } else if self.at("f\"") {
                self.pos += 2
                self.add(Kind.FormatOpen, begin)
                self.format_text()
            } else if byte == b'"' || self.at("b\"") {
                let bytes = byte == b'b'
                self.pos += if bytes { 2usize } else { 1usize }
                if !self.quoted(b'"') { self.error(Phase.Lex, begin, self.pos, "unterminated text literal") }
                self.add(if bytes { Kind.PrefixedText } else { Kind.Text }, begin)
            } else if byte == b'\'' || self.at("b'") {
                let bytes = byte == b'b'
                self.pos += if bytes { 2usize } else { 1usize }
                let _ = self.quoted(b'\'')
                self.add(if bytes { Kind.Byte } else { Kind.Character }, begin)
                let span = self.span(begin, self.pos)
                let _ = character_value(read self.bytes[begin..self.pos], bytes, span, mut self.result.diagnostics)
            } else if word_start(byte) {
                self.word()
                self.add(Kind.Word, begin)
            } else if digit(byte) { self.number(begin) }
            else if byte >= 128u8 {
                self.pos += if byte >= 0xf0u8 { 4usize } else if byte >= 0xe0u8 { 3usize } else { 2usize }
                self.add(Kind.Word, begin)
                self.error(Phase.Feature, begin, self.pos, "Unicode identifiers are not implemented in I02")
            } else { self.symbol(begin) }
        }
        if !self.holes.is_empty() { self.error(Phase.Lex, self.bytes.len(), self.bytes.len(), "unterminated f-string literal") }
        if self.pos != self.bytes.len() { self.error(Phase.Limit, self.pos, self.pos, "token limit exceeded") }
        self.pos = self.bytes.len()
        self.add(Kind.End, self.pos)
    }
}

pub fn tokenize(read bytes: [u8], source: u32): Lexed {
    var scanner = Scanner(read bytes, source, 0usize, false, new<usize>(), Lexed(new<Token>(), Diagnostics()))
    if bytes.len() > SOURCE_BYTES {
        scanner.error(Phase.Limit, 0usize, 0usize, "source file must be smaller than 4 GiB")
        scanner.add(Kind.End, 0usize)
    } else if let present(offset) = invalid_utf8(bytes) {
        scanner.error(Phase.Lex, offset, offset + 1, "source is not valid UTF-8")
        scanner.pos = offset
        scanner.add(Kind.End, offset)
    } else { scanner.scan() }
    scanner.result
}
