import alloc.string.String
import alloc.vec.List
import mettle_foundation.Span
import mettle_syntax.{ Kind, Token }
import super.{ CheckError, CheckPhase }

type Predicate<region r> {
    bytes: read [u8] from r
    tokens: read [Token] from r
    features: read List<String> from r
    debug_assertions: bool
    position: usize
    attribute: Span
}

extend<region r> Predicate<region r> {
    mut fn peek(): Token? {
        while self.position < self.tokens.len() {
            let token = self.tokens[self.position]
            if !(token.kind.is(Kind.Space) || token.kind.is(Kind.Newline) || token.kind.is(Kind.Comment)) {
                return present(token)
            }
            self.position += 1usize
        }
        none
    }

    mut fn consume(read spelling: [u8]): bool {
        let present(token) = self.peek() else { return false }
        if read self.bytes[token.span.begin as usize..token.span.end as usize] != spelling { return false }
        self.position += 1usize
        true
    }

    mut fn span(): Span {
        if let present(token) = self.peek() { return token.span }
        self.attribute
    }

    mut fn evaluate(): bool throws CheckError {
        let present(token) = self.peek() else {
            throw CheckError(CheckPhase.Attribute, self.attribute, "expected a cfg predicate")
        }
        if !token.kind.is(Kind.Word) {
            throw CheckError(CheckPhase.Attribute, token.span, "expected a cfg predicate")
        }
        let name = read self.bytes[token.span.begin as usize..token.span.end as usize]
        self.position += 1usize
        if name == b"true" { return true }
        if name == b"false" { return false }
        if name == b"debug_assertions" { return self.debug_assertions }
        if self.consume(b"(") {
            if name != b"all" && name != b"any" && name != b"not" {
                throw CheckError(CheckPhase.Attribute, token.span, "unknown cfg predicate")
            }
            let all = name == b"all"
            let negate = name == b"not"
            var value = all
            var count = 0usize
            while !self.consume(b")") {
                let operand = try self.evaluate()
                value = if all { value && operand } else { value || operand }
                count += 1usize
                if self.consume(b",") { continue }
                if self.consume(b")") { break }
                throw CheckError(CheckPhase.Attribute, self.span(), "expected ',' or ')' in the cfg predicate")
            }
            if negate {
                if count != 1usize {
                    throw CheckError(CheckPhase.Attribute, token.span, "not(...) takes exactly one predicate")
                }
                return !value
            }
            return value
        }
        if name != b"feature" && name != b"target_os" && name != b"target_arch" &&
            name != b"target_family" && name != b"target_endian" && name != b"target_pointer_width" &&
            name != b"target_feature" {
            throw CheckError(CheckPhase.Attribute, token.span, "unknown cfg predicate")
        }
        if !self.consume(b"=") {
            throw CheckError(CheckPhase.Attribute, token.span, "cfg predicate requires = \"value\"")
        }
        let present(text) = self.peek() else {
            throw CheckError(CheckPhase.Attribute, self.attribute, "cfg predicate requires a constant text value")
        }
        if !text.kind.is(Kind.Text) {
            throw CheckError(CheckPhase.Attribute, text.span, "cfg predicate requires a constant text value")
        }
        self.position += 1usize
        let value = read self.bytes[text.span.begin as usize + 1usize..text.span.end as usize - 1usize]
        if name == b"target_os" { return value == b"linux" }
        if name == b"target_arch" { return value == b"x86_64" }
        if name == b"target_family" { return value == b"unix" }
        if name == b"target_endian" { return value == b"little" }
        if name == b"target_pointer_width" { return value == b"64" }
        if name == b"target_feature" { return value == b"sse" || value == b"sse2" }
        for feature in self.features.as_slice() {
            if feature.as_text().as_bytes() == value { return true }
        }
        false
    }
}

pub parent fn included(read bytes: [u8], read tokens: [Token], read features: List<String>,
    debug_assertions: bool, span: Span): bool throws CheckError {
    var predicate = Predicate(read bytes, read tokens, read features, debug_assertions, 0usize, span)
    if !predicate.consume(b"(") {
        throw CheckError(CheckPhase.Attribute, span, "cfg requires one predicate")
    }
    if predicate.consume(b")") {
        throw CheckError(CheckPhase.Attribute, span, "cfg requires one predicate")
    }
    let value = try predicate.evaluate()
    if !predicate.consume(b")") || predicate.peek().is_present() {
        throw CheckError(CheckPhase.Attribute, predicate.span(), "unexpected tokens after the cfg predicate; combine predicates with all(...) or any(...)")
    }
    value
}
