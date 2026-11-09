import alloc.vec.{ List, new }
import core.text.Text
import mettle_foundation.{ Span, Diagnostics, Phase }
import super.lexer.tokenize
import super.token.{ Token, Kind }
import super.characters.validate_text
import super.tree.{ NodeId, IndexRange, NodeKind, SyntaxNode, Parsed }

copy type Failure {}
copy type Position { token: usize; offset: u32 }
copy type Look { token: Token; index: usize; next: Position }
copy type Anchor { token: usize; begin: u32 }
copy type Checkpoint { pending: usize; nodes: usize; children: usize; depth: usize; suppressed: usize; generic_level: usize }

type Parser<region r> {
    bytes: read [u8] from r
    source: u32
    position: Position
    look: Look
    last_end: u32
    last_token: usize
    depth: usize
    suppressed: usize
    generic_level: usize
    pending: List<NodeId>
    rejected_applications: List<u8>
    application_stack: List<usize>
    application_delimiters: List<u8>
    result: Parsed
}

extend<region r> Parser<region r> {
    mut fn refresh(): Unit {
        var position = self.position
        loop {
            let token = self.result.tokens[position.token]
            match token.kind {
                Kind.Space => { position.token += 1; position.offset = 0u32 },
                Kind.Comment => {
                    var offset = if position.offset == 0u32 { token.span.begin } else { position.offset }
                    while offset < token.span.end && self.bytes[offset as usize] != 10u8 && self.bytes[offset as usize] != 13u8 { offset += 1u32 }
                    if offset < token.span.end {
                        var end = offset + 1u32
                        if self.bytes[offset as usize] == 13u8 && end < token.span.end && self.bytes[end as usize] == 10u8 { end += 1u32 }
                        if self.suppressed == 0 {
                            self.look = Look(Token(Kind.Newline, Span(self.source, offset, end)), position.token, Position(position.token, end))
                            return
                        }
                        position.offset = end
                    } else { position.token += 1; position.offset = 0u32 }
                },
                Kind.Newline => {
                    if self.suppressed == 0 {
                        self.look = Look(token, position.token, Position(position.token + 1, 0u32))
                        return
                    }
                    position.token += 1
                    position.offset = 0u32
                },
                _ => {
                    let next = if token.kind.is(Kind.End) { position.token } else { position.token + 1 }
                    var fragment = token
                    if position.offset != 0u32 { fragment.span.begin = position.offset }
                    self.look = Look(fragment, position.token, Position(next, 0u32))
                    return
                }
            }
        }
    }
    fn at(read text: Text): bool {
        let span = self.look.token.span
        let pattern = text.as_bytes()
        if (span.end - span.begin) as usize != pattern.len() { return false }
        var index = 0usize
        while index < pattern.len() {
            if self.bytes[span.begin as usize + index] != pattern[index] { return false }
            index += 1
        }
        true
    }
    fn anchor(): Anchor { Anchor(self.look.index, self.look.token.span.begin) }
    fn checkpoint(): Checkpoint { Checkpoint(self.pending.len(), self.result.nodes.len(), self.result.children.len(), self.depth, self.suppressed, self.generic_level) }
    mut fn followed_by(read text: Text): bool {
        let position = self.position
        let look = self.look
        self.position = look.next
        self.refresh()
        let followed = self.at(text)
        self.position = position
        self.look = look
        followed
    }
    mut fn advance(): Unit {
        self.last_end = self.look.token.span.end
        self.last_token = self.look.index
        self.position = self.look.next
        self.refresh()
    }
    mut fn consume(read text: Text): bool {
        if !self.at(text) { return false }
        self.advance()
        true
    }
    mut fn newlines(): Unit { while self.look.token.kind.is(Kind.Newline) { self.advance() } }
    mut fn separators(): Unit {
        while self.look.token.kind.is(Kind.Newline) || self.at(";") { self.advance() }
    }
    mut fn fail(read message: Text from static, phase: Phase): Never throws Failure {
        self.result.diagnostics.report(phase, self.look.token.span, message)
        throw Failure()
    }
    mut fn expect(read text: Text, read message: Text from static): Unit throws Failure {
        if !self.consume(text) { try self.fail(message, Phase.Parse) }
    }
    mut fn close(read text: Text, read message: Text from static): Unit throws Failure {
        if !self.at(text) { try self.fail(message, Phase.Parse) }
        self.suppressed -= 1
        self.advance()
    }
    mut fn enter(): Unit throws Failure {
        self.depth += 1
        if self.depth > 128 { try self.fail("expression nesting limit exceeded", Phase.Limit) }
    }
    mut fn finish(kind: NodeKind, start: Anchor, mark: usize, operation: u32?): Unit throws Failure {
        if self.result.nodes.len() >= 67108864usize { try self.fail("syntax node limit exceeded", Phase.Limit) }
        let first = self.result.children.len() as u32
        var index = mark
        while index < self.pending.len() {
            let child = self.pending[index]
            self.result.children.push(child)
            index += 1
        }
        let children = IndexRange(first, self.result.children.len() as u32)
        let end = if self.last_end < start.begin { start.begin } else { self.last_end }
        let token_end = if self.last_token + 1 < start.token { start.token } else { self.last_token + 1 }
        let node = SyntaxNode(kind, Span(self.source, start.begin, end), IndexRange(start.token as u32, token_end as u32), children, operation, false)
        let id = NodeId(self.result.nodes.len() as u32)
        self.result.nodes.push(node)
        self.pending.truncate(mark)
        self.pending.push(id)
    }
    fn reserved(): bool {
        (self.at("fn") || self.at("let") || self.at("var") || self.at("if") || self.at("else")
            || self.at("while") || self.at("loop") || self.at("return") || self.at("break") || self.at("continue")
            || self.at("true") || self.at("false") || self.at("type") || self.at("copy") || self.at("enum")
            || self.at("pub") || self.at("module") || self.at("import") || self.at("interface") || self.at("extend")
            || self.at("read") || self.at("mut") || self.at("take") || self.at("const") || self.at("static")
            || self.at("unsafe") || self.at("extern") || self.at("async") || self.at("await") || self.at("throws")
            || self.at("throw") || self.at("try") || self.at("capture") || self.at("match") || self.at("for")
            || self.at("in") || self.at("none") || self.at("present") || self.at("success") || self.at("failure")
            || self.at("region") || self.at("where") || self.at("as") || self.at("alias") || self.at("union")
            || self.at("heap") || self.at("shared") || self.at("local") || self.at("weak") || self.at("pinned") || self.at("_")
            || self.at("init") || self.at("drop") || self.at("implements") || self.at("receiver") || self.at("label") || self.at("macro"))
    }
    mut fn name(discard: bool): Unit throws Failure {
        if !(self.name_token() || (discard && self.at("_"))) {
            try self.fail("expected a name", Phase.Parse)
        }
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        try self.finish(NodeKind.Name, start, mark, none)
    }
    fn name_token(): bool {
        self.look.token.kind.is(Kind.QuotedWord) || (self.look.token.kind.is(Kind.Word) && !self.reserved())
    }
    mut fn followed_by_name(): bool {
        let position = self.position
        let look = self.look
        self.position = look.next
        self.refresh()
        let followed = self.name_token()
        self.position = position
        self.look = look
        followed
    }
    mut fn type_name(effect: bool): Unit throws Failure {
        self.depth += 1
        if self.depth > 128 { try self.fail("type nesting limit exceeded", Phase.Limit) }
        let start = self.anchor()
        let mark = self.pending.len()
        var view: u32? = none
        if self.at("read") || (self.at("mut") && !self.followed_by("fn")) {
            view = present(self.look.index as u32)
            self.advance()
        }
        let payload = self.anchor()
        if self.at("take") && !self.followed_by("fn") { try self.fail("'take' is an access mode, not a type qualifier", Phase.Feature) }
        let ranked = self.at("for")
        if ranked { try self.type_binders() }
        let body_mark = self.pending.len()
        let base = self.anchor()
        let callable = self.at("fn") || self.at("mut") || self.at("take") || self.at("unsafe") || self.at("extern") || self.at("async")
        if callable { try self.callable_type(payload, mark) }
        else if self.at("heap") || self.at("shared") || self.at("weak") || self.at("local") || self.at("pinned") {
            let operation = self.look.index as u32
            let is_pinned = self.at("pinned")
            let is_local = self.at("local")
            self.advance()
            if is_local {
                if !self.at("shared") && !self.at("weak") { try self.fail("expected 'shared' or 'weak' after 'local'", Phase.Parse) }
                self.advance()
            }
            try self.type_name(false)
            try self.finish(if is_pinned { NodeKind.TypePinned } else { NodeKind.TypeOwner }, base, body_mark, present(operation))
        } else if self.consume("ptr") {
            try self.expect("<", "expected '<'")
            self.suppressed += 1
            self.refresh()
            if !self.at("read") && !self.at("mut") { try self.fail("raw pointers require read or mut access", Phase.Parse) }
            let operation = self.look.index as u32
            self.advance()
            try self.type_name(false)
            try self.angle_close("expected '>' after a raw pointer type")
            try self.finish(NodeKind.TypePointer, base, body_mark, present(operation))
        } else if self.consume("(") {
            self.suppressed += 1
            self.refresh()
            if self.at(")") {
                self.result.diagnostics.report(Phase.Parse, self.result.tokens[payload.token].span, "use Unit in type positions; () is a value")
                throw Failure()
            }
            try self.type_name(true)
            let tuple = self.consume(",")
            if tuple {
                while !self.at(")") && !self.look.token.kind.is(Kind.End) {
                    try self.type_name(true)
                    if !self.consume(",") { break }
                }
            }
            try self.close(")", "expected ')'")
            try self.finish(if tuple { NodeKind.TypeTuple } else { NodeKind.TypeGroup }, base, body_mark, none)
        } else if self.consume("[") {
            self.suppressed += 1
            self.refresh()
            try self.type_name(true)
            let array = self.consume(";")
            if array { try self.expression(1usize) }
            try self.close("]", "expected ']'")
            try self.finish(if array { NodeKind.TypeArray } else { NodeKind.TypeSlice }, base, body_mark, none)
        } else if self.at("any") || self.at("some") {
            let erased = self.at("any")
            self.advance()
            loop {
                try self.bound_type()
                if !self.consume("+") { break }
            }
            try self.finish(if erased { NodeKind.TypeErased } else { NodeKind.TypeOpaque }, base, body_mark, none)
        } else { try self.type_path() }
        if ranked && !callable { try self.finish(NodeKind.TypeFor, payload, mark, none) }
        while self.at(".") && self.followed_by("(") {
            self.advance()
            try self.expect("(", "expected '('")
            self.suppressed += 1
            self.refresh()
            try self.type_name(false)
            try self.close(")", "expected ')'")
            try self.expect(".", "expected '.'")
            try self.name(false)
            if self.at("<") { try self.type_arguments(false) }
            try self.finish(NodeKind.TypeProjection, payload, mark, none)
        }
        while self.at("?") || self.at("??") {
            let operation = self.look.index as u32
            self.symbol_prefix()
            try self.finish(NodeKind.TypeOptional, payload, mark, present(operation))
        }
        if view.is_present() { try self.finish(NodeKind.TypeBorrow, start, mark, view) }
        if self.at("from") {
            let operation = self.look.index as u32
            self.advance()
            let grouped = self.consume("(")
            if grouped { self.suppressed += 1; self.refresh() }
            loop {
                if self.at("static") {
                    let source = self.anchor()
                    let source_mark = self.pending.len()
                    self.advance()
                    try self.finish(NodeKind.Name, source, source_mark, none)
                } else { try self.name(false) }
                if !grouped || !self.consume(",") { break }
            }
            if grouped { try self.close(")", "expected ')'") }
            try self.finish(NodeKind.TypeSources, start, mark, present(operation))
        }
        if effect && self.at("throws") { try self.fail("stored outcomes use Outcome<T, E>; throws declares a callable effect", Phase.Parse) }
        self.depth -= 1
    }
    mut fn type_path(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let outcome_name = self.at("Outcome") || self.at("`Outcome`")
        if self.at("_") { try self.name(true) } else { try self.name(false) }
        while self.at(".") && !self.followed_by("(") { self.advance(); try self.name(false) }
        let outcome = outcome_name && self.pending.len() == mark + 1
        try self.finish(NodeKind.TypeName, start, mark, none)
        if self.at("<") {
            try self.type_arguments(outcome)
            try self.finish(if outcome { NodeKind.TypeOutcome } else { NodeKind.TypeApply }, start, mark, none)
        } else if outcome { try self.fail("Outcome requires a success type and an error type", Phase.Parse) }
    }
    mut fn region_name(): Unit throws Failure {
        if !self.at("static") { try self.name(false); return }
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        try self.finish(NodeKind.Name, start, mark, none)
    }
    mut fn type_binders(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("for", "expected 'for'")
        try self.expect("<", "expected '<'")
        self.suppressed += 1
        self.refresh()
        while !self.at(">") && !self.at(">>") && !self.look.token.kind.is(Kind.End) {
            try self.expect("region", "expected 'region'")
            try self.name(false)
            if self.pending.len() - mark > 4194304usize { try self.fail("generic parameter limit exceeded", Phase.Limit) }
            if !self.consume(",") { break }
        }
        try self.angle_close("expected '>' after region binders")
        try self.finish(NodeKind.TypeBinders, start, mark, none)
    }
    mut fn bound_type(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let ranked = self.at("for")
        if ranked { try self.type_binders() }
        try self.type_path()
        if ranked { try self.finish(NodeKind.TypeFor, start, mark, none) }
    }
    mut fn generic_value(): Unit throws Failure {
        let level = self.generic_level
        if self.consume("{") {
            self.generic_level = 0usize
            try self.expression(1usize)
            try self.expect("}", "expected '}'")
        } else {
            self.generic_level = self.suppressed
            try self.expression(6usize)
        }
        self.generic_level = level
    }
    mut fn type_arguments(outcome: bool): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("<", "expected '<'")
        self.suppressed += 1
        self.refresh()
        while !self.at(">") && !self.at(">>") && !self.look.token.kind.is(Kind.End) {
            let argument = self.anchor()
            let argument_mark = self.pending.len()
            var operation: u32? = none
            let explicit_type = self.at("type")
            var constant = self.at("const")
            if explicit_type || constant { operation = present(self.look.index as u32); self.advance() }
            if explicit_type || (constant && !self.at("{")) || ((self.look.token.kind.is(Kind.Word) || self.look.token.kind.is(Kind.QuotedWord)) && self.followed_by("=")) {
                try self.name(false)
                try self.expect("=", "expected '='")
            }
            var region_argument = false
            if self.at("region") {
                region_argument = true
                operation = present(self.look.index as u32)
                self.advance()
                try self.region_name()
            } else {
                let literal = self.look.token.kind.is(Kind.Integer) || self.look.token.kind.is(Kind.Character) || self.look.token.kind.is(Kind.Byte) || self.at("-") || self.at("!") || self.at("true") || self.at("false") || self.at("{")
                if constant || (!explicit_type && literal) { constant = true; try self.generic_value() }
                else {
                    let saved = self.checkpoint()
                    let position = self.position
                    let last_end = self.last_end
                    let last_token = self.last_token
                    try self.type_name(false)
                    if !explicit_type && !self.at(">>") && !self.at(">>=") && self.level() >= 6 && self.level() <= 11 {
                        self.pending.truncate(saved.pending)
                        self.result.nodes.truncate(saved.nodes)
                        self.result.children.truncate(saved.children)
                        self.position = position
                        self.last_end = last_end
                        self.last_token = last_token
                        self.refresh()
                        constant = true
                        try self.generic_value()
                    }
                }
            }
            try self.finish(if region_argument { NodeKind.TypeRegionArgument } else if constant { NodeKind.TypeConstArgument } else { NodeKind.TypeArgument }, argument, argument_mark, operation)
            if self.pending.len() - mark > 4194304usize { try self.fail("generic argument limit exceeded", Phase.Limit) }
            if !self.consume(",") { break }
        }
        try self.angle_close("expected '>' after generic arguments")
        if outcome {
            if self.pending.len() - mark != 2 { try self.fail("Outcome requires a success type and an error type", Phase.Parse) }
            var index = mark
            while index < self.pending.len() {
                let node = self.result.nodes[self.pending[index].index as usize]
                if !node.kind.is(NodeKind.TypeArgument) || node.children.end - node.children.begin != 1u32 { try self.fail("Outcome arguments must be positional types", Phase.Parse) }
                index += 1
            }
        }
        try self.finish(NodeKind.TypeArguments, start, mark, none)
    }
    mut fn callable_type(start: Anchor, mark: usize): Unit throws Failure {
        if self.at("unsafe") { try self.type_modifier() }
        if self.at("extern") { try self.type_modifier() }
        if self.at("async") { try self.fail("async callables require task lowering", Phase.Feature) }
        if self.at("mut") || self.at("take") { try self.type_modifier() }
        let operation = self.look.index as u32
        try self.expect("fn", "expected 'fn'")
        let parameters = self.anchor()
        let parameter_mark = self.pending.len()
        try self.expect("(", "expected '('")
        self.suppressed += 1
        self.refresh()
        while !self.at(")") && !self.look.token.kind.is(Kind.End) {
            let parameter = self.anchor()
            let child_mark = self.pending.len()
            if self.at("...") {
                let variadic = self.look.index as u32
                self.advance()
                try self.finish(NodeKind.TypeVariadic, parameter, child_mark, present(variadic))
                break
            }
            var mode: u32? = none
            if self.at("read") || self.at("mut") || self.at("take") { mode = present(self.look.index as u32); self.advance() }
            try self.type_name(true)
            try self.finish(NodeKind.TypeParameter, parameter, child_mark, mode)
            if !self.consume(",") { break }
        }
        try self.close(")", "expected ')'")
        try self.finish(NodeKind.TypeParameters, parameters, parameter_mark, none)
        try self.expect(":", "expected ':'")
        try self.type_name(false)
        if self.at("throws") {
            let effect = self.anchor()
            let effect_mark = self.pending.len()
            let throws_token = self.look.index as u32
            self.advance()
            try self.type_name(true)
            try self.finish(NodeKind.TypeEffect, effect, effect_mark, present(throws_token))
        }
        try self.finish(NodeKind.TypeCallable, start, mark, present(operation))
    }
    mut fn type_modifier(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        let foreign = self.at("extern")
        self.advance()
        if foreign {
            if !self.look.token.kind.is(Kind.Text) { try self.fail("expected a constant text literal", Phase.Parse) }
            let text = self.anchor()
            let span = self.look.token.span
            validate_text(read self.bytes[span.begin as usize..span.end as usize], span, mut self.result.diagnostics)
            self.advance()
            try self.finish(NodeKind.Text, text, mark, none)
        }
        try self.finish(NodeKind.TypeModifier, start, mark, present(operation))
    }
    mut fn angle_close(read message: Text from static): Unit throws Failure {
        let span = self.look.token.span
        if !self.look.token.kind.is(Kind.Symbol) || span.begin == span.end || self.bytes[span.begin as usize] != b'>' {
            try self.fail(message, Phase.Parse)
        }
        self.suppressed -= 1
        self.symbol_prefix()
    }
    mut fn symbol_prefix(): Unit {
        let span = self.look.token.span
        self.last_end = span.begin + 1u32
        self.last_token = self.look.index
        self.position = if self.last_end == span.end { self.look.next } else { Position(self.look.index, self.last_end) }
        self.refresh()
    }
    fn level(): usize {
        if self.at("..") || self.at("..=") { 1usize }
        else if self.at("??") { 2usize }
        else if self.at("||") { 3usize }
        else if self.at("&&") { 4usize }
        else if self.at("==") || self.at("!=") || self.at("<") || self.at(">") || self.at("<=") || self.at(">=") { 5usize }
        else if self.at("|") { 6usize }
        else if self.at("^") { 7usize }
        else if self.at("&") { 8usize }
        else if self.at("<<") || self.at(">>") { 9usize }
        else if self.at("+") || self.at("-") { 10usize }
        else if self.at("*") || self.at("/") || self.at("%") { 11usize }
        else if self.at("as") { 12usize }
        else { 0usize }
    }
    fn range_end(): bool {
        (self.look.token.kind.is(Kind.Newline) || self.look.token.kind.is(Kind.End)
            || self.at("]") || self.at(")") || self.at(",") || self.at("}") || self.at(";"))
    }
    mut fn reject_application(index: usize): Unit {
        let slot = index / 4
        while self.rejected_applications.len() <= slot { self.rejected_applications.push(0u8) }
        self.rejected_applications[slot] |= self.application_mask(index)
    }
    fn application_mask(index: usize): u8 {
        1u8 << ((index % 4) * 2 + if self.suppressed == 0 { 0usize } else { 1usize })
    }
    fn application_follower(index: usize): bool {
        var next = index
        while next < self.result.tokens.len() {
            let token = self.result.tokens[next]
            if token.kind.is(Kind.Space) { next += 1; continue }
            if token.kind.is(Kind.Comment) {
                if self.suppressed == 0 {
                    var offset = token.span.begin
                    while offset < token.span.end {
                        let byte = self.bytes[offset as usize]
                        if byte == 10u8 || byte == 13u8 { return true }
                        offset += 1u32
                    }
                }
                next += 1
                continue
            }
            if token.kind.is(Kind.Newline) {
                if self.suppressed == 0 { return true }
                next += 1
                continue
            }
            return token.kind.is(Kind.End) || token.kind.is(Kind.FormatHoleClose) || self.brace(next, b'(') || self.brace(next, b'.') || self.brace(next, b')') || self.brace(next, b']') || self.brace(next, b'}') || self.brace(next, b',') || self.brace(next, b';')
        }
        false
    }
    mut fn application_candidate(): bool {
        let kind = self.result.nodes[self.pending[self.pending.len() - 1].index as usize].kind
        if !kind.is(NodeKind.Name) && !kind.is(NodeKind.Field) { return false }
        let slot = self.look.index / 4
        if slot < self.rejected_applications.len() && (self.rejected_applications[slot] & self.application_mask(self.look.index)) != 0u8 { return false }
        let opening = self.look.index
        self.application_stack.push(opening)
        var index = self.look.index + 1
        while index < self.result.tokens.len() {
            let token = self.result.tokens[index]
            if token.kind.is(Kind.End) { break }
            let byte = if token.kind.is(Kind.Symbol) && token.span.end == token.span.begin + 1u32 { self.bytes[token.span.begin as usize] } else { 0u8 }
            if byte == b'(' || byte == b'[' || byte == b'{' {
                let delimiter = byte
                self.application_delimiters.push(delimiter)
            } else if byte == b')' || byte == b']' || byte == b'}' {
                if self.application_delimiters.is_empty() { break }
                let last = self.application_delimiters.len() - 1
                let expected = if byte == b')' { b'(' } else if byte == b']' { b'[' } else { b'{' }
                if self.application_delimiters[last] != expected { break }
                self.application_delimiters.truncate(last)
            } else if !self.application_delimiters.is_empty() { index += 1; continue }
            else if byte == b';' || token.kind.is(Kind.FormatHoleClose) { break }
            else if byte == b'<' {
                let opening = index
                self.application_stack.push(opening)
            }
            else if token.kind.is(Kind.Symbol) && self.bytes[token.span.begin as usize] == b'>' {
                let width = (token.span.end - token.span.begin) as usize
                if width > 2 || (width == 2 && self.bytes[token.span.begin as usize + 1] != b'>') || width > self.application_stack.len() { break }
                let followed = self.application_follower(index + 1)
                var remaining = width
                while remaining != 0 {
                    let last = self.application_stack.len() - 1
                    let opening = self.application_stack[last]
                    self.application_stack.truncate(last)
                    if remaining != 1 || !followed { self.reject_application(opening) }
                    remaining -= 1
                }
                if self.application_stack.is_empty() { return followed }
            }
            index += 1
        }
        index = 0usize
        while index < self.application_stack.len() {
            let opening = self.application_stack[index]
            self.reject_application(opening)
            index += 1
        }
        self.application_stack.clear()
        self.application_delimiters.clear()
        false
    }
    mut fn generic_application(): bool throws Failure {
        if !self.application_candidate() { return false }
        let saved = self.checkpoint()
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        let issues = self.result.diagnostics.issues.len()
        let errors = self.result.diagnostics.error_count
        let outcome = capture self.type_arguments(false)
        if outcome.is_success() {
            let arguments = self.result.nodes[self.pending[self.pending.len() - 1].index as usize]
            if arguments.children.begin != arguments.children.end && self.application_follower(self.look.index) { return true }
        }
        if self.result.diagnostics.issues.len() > issues {
            let issue = self.result.diagnostics.issues[issues]
            if (issue.phase as u32) != (Phase.Parse as u32) { throw Failure() }
        }
        self.pending.truncate(saved.pending)
        self.result.nodes.truncate(saved.nodes)
        self.result.children.truncate(saved.children)
        self.depth = saved.depth
        self.suppressed = saved.suppressed
        self.generic_level = saved.generic_level
        self.position = position
        self.look = look
        self.last_end = last_end
        self.last_token = last_token
        self.result.diagnostics.issues.truncate(issues)
        self.result.diagnostics.error_count = errors
        self.reject_application(look.index)
        false
    }
    mut fn expression(minimum: usize): Unit throws Failure {
        try self.enter()
        let start = self.anchor()
        let mark = self.pending.len()
        var ranged = false
        if minimum <= 1 && (self.at("..") || self.at("..=")) {
            let operation = self.look.index as u32
            let inclusive = self.at("..=")
            self.advance()
            if !self.range_end() { try self.expression(2usize) }
            else if inclusive { try self.fail("an inclusive range requires an upper bound", Phase.Parse) }
            try self.finish(NodeKind.Range, start, mark, present(operation))
            ranged = true
        } else { try self.primary() }
        var compared = false
        while self.level() >= minimum && self.level() != 0 {
            if self.generic_level != 0 && self.generic_level == self.suppressed && (self.at(">>") || self.at(">>=")) { break }
            let level = self.level()
            if ranged && level == 1 { try self.fail("ranges do not chain", Phase.Parse) }
            if level == 5 && compared { try self.fail("comparisons do not chain", Phase.Parse) }
            if level == 5 { compared = true }
            let operation = self.look.index as u32
            let inclusive = self.at("..=")
            self.advance()
            if level == 12 {
                try self.type_name(true)
                try self.finish(NodeKind.Cast, start, mark, present(operation))
            } else {
                if level == 1 && self.range_end() {
                    if inclusive { try self.fail("an inclusive range requires an upper bound", Phase.Parse) }
                } else {
                    self.newlines()
                    try self.expression(if level == 2 { level } else { level + 1 })
                }
                let kind = if level == 1 { NodeKind.Range } else if level == 2 { NodeKind.Coalesce } else { NodeKind.Binary }
                try self.finish(kind, start, mark, present(operation))
                if level == 1 { ranged = true }
            }
        }
        self.depth -= 1
    }
    mut fn sequence(read close: Text, read message: Text from static): Unit throws Failure {
        if !self.at(close) {
            loop {
                try self.expression(1usize)
                if self.at(":") { try self.fail("labelled arguments are not implemented in the Mettle parser yet", Phase.Feature) }
                if !self.consume(",") || self.at(close) { break }
            }
        }
        try self.close(close, message)
    }
    mut fn primary(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        let kind = self.look.token.kind
        if self.at("-") || self.at("!") || self.at("*") || self.at("read") || self.at("mut") || self.at("take") {
            self.advance()
            self.newlines()
            try self.expression(13usize)
            try self.finish(NodeKind.Unary, start, mark, present(operation))
        } else if self.at("{") { try self.block() }
        else if self.at("if") || self.at("while") || self.at("loop") { try self.control() }
        else if self.consume("(") {
            self.suppressed += 1
            self.refresh()
            var tuple = false
            if !self.at(")") {
                try self.expression(1usize)
                while self.consume(",") {
                    tuple = true
                    if self.at(")") { break }
                    try self.expression(1usize)
                }
            }
            let count = self.pending.len() - mark
            try self.close(")", "expected ')'")
            try self.finish(if count == 0 { NodeKind.Unit } else if tuple { NodeKind.Tuple } else { NodeKind.Group }, start, mark, none)
        } else if self.consume("[") {
            self.suppressed += 1
            self.refresh()
            var repeat = false
            if !self.at("]") {
                try self.expression(1usize)
                if self.consume(";") { repeat = true; try self.expression(1usize) }
                else { while self.consume(",") && !self.at("]") { try self.expression(1usize) } }
            }
            try self.close("]", "expected ']'")
            try self.finish(if repeat { NodeKind.Repeat } else { NodeKind.Array }, start, mark, none)
        } else if kind.is(Kind.Integer) || kind.is(Kind.Floating) || kind.is(Kind.Character) || kind.is(Kind.Byte) || kind.is(Kind.Text) || kind.is(Kind.PrefixedText) || self.at("true") || self.at("false") {
            let literal = if kind.is(Kind.Integer) { NodeKind.Integer } else if kind.is(Kind.Floating) { NodeKind.Floating }
            else if kind.is(Kind.Character) { NodeKind.Character } else if kind.is(Kind.Byte) { NodeKind.Byte }
            else if kind.is(Kind.Text) || kind.is(Kind.PrefixedText) { NodeKind.Text } else { NodeKind.Boolean }
            if literal.is(NodeKind.Text) {
                let span = self.look.token.span
                validate_text(read self.bytes[span.begin as usize..span.end as usize], span, mut self.result.diagnostics)
            }
            self.advance()
            try self.finish(literal, start, mark, present(operation))
        } else if kind.is(Kind.QuotedWord) || (kind.is(Kind.Word) && !self.reserved()) { try self.name(false) }
        else if kind.is(Kind.FormatOpen) || self.at("match") || self.at("for") || self.at("fn") || self.at("none") || self.at("present") || self.at("success") || self.at("failure") || self.at("try") || self.at("capture") || self.at("throw") || self.at("await") || self.at("async") || self.at("unsafe") || self.at("heap") || self.at("shared") || self.at("local") || self.at("weak") || self.at("pinned") { try self.fail("this expression form is not implemented in the Mettle parser yet", Phase.Feature) }
        else { try self.fail("expected an expression", Phase.Parse) }
        loop {
            if self.consume(".") {
                self.newlines()
                if self.at("(") { try self.fail("interface-member projections are not implemented in the Mettle parser yet", Phase.Feature) }
                if self.look.token.kind.is(Kind.Integer) || self.at("drop") {
                    let field = self.anchor()
                    self.advance()
                    try self.finish(NodeKind.Name, field, self.pending.len(), none)
                } else { try self.name(false) }
                try self.finish(NodeKind.Field, start, mark, none)
            } else if self.consume("(") {
                let arguments = Anchor(self.last_token, self.last_end - 1u32)
                let argument_mark = self.pending.len()
                self.suppressed += 1
                self.refresh()
                try self.sequence(")", "expected ')'")
                try self.finish(NodeKind.Arguments, arguments, argument_mark, none)
                try self.finish(NodeKind.Call, start, mark, none)
            } else if self.consume("[") {
                self.suppressed += 1
                self.refresh()
                try self.expression(1usize)
                try self.close("]", "expected ']'")
                try self.finish(NodeKind.Index, start, mark, none)
            } else if self.at("<") && (try self.generic_application()) { try self.finish(NodeKind.GenericApply, start, mark, none) }
            else if self.at("?.") || self.at("!") { try self.fail("this postfix form is not implemented in the Mettle parser yet", Phase.Feature) }
            else { break }
        }
    }
    mut fn control(): Unit throws Failure {
        try self.enter()
        let start = self.anchor()
        let mark = self.pending.len()
        let kind = if self.at("if") { NodeKind.If } else if self.at("while") { NodeKind.While } else { NodeKind.Loop }
        self.advance()
        if self.at("let") { try self.fail("pattern conditions are not implemented in the Mettle parser yet", Phase.Feature) }
        if !kind.is(NodeKind.Loop) { try self.expression(1usize) }
        if self.at(",") { try self.fail("condition chains are not implemented in the Mettle parser yet", Phase.Feature) }
        self.newlines()
        try self.block()
        if kind.is(NodeKind.If) {
            let position = self.position
            let last_end = self.last_end
            let last_token = self.last_token
            self.newlines()
            if self.consume("else") {
                self.newlines()
                if self.at("if") { try self.control() } else { try self.block() }
            } else { self.position = position; self.last_end = last_end; self.last_token = last_token; self.refresh() }
        }
        try self.finish(kind, start, mark, none)
        self.depth -= 1
    }
    mut fn statement(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        if self.at("let") || self.at("var") {
            let mutable_binding = self.at("var")
            self.advance()
            if self.at("mut") { try self.fail("`let mut` is not valid syntax", Phase.Parse) }
            let discard = self.at("_")
            if discard && mutable_binding { try self.fail("discard uses 'let _ = expression'", Phase.Parse) }
            try self.name(true)
            var typed = false
            if self.consume(":") { typed = true; try self.type_name(true) }
            if self.consume("=") { self.newlines(); try self.expression(1usize) }
            else if !typed || discard { try self.fail("binding requires an initializer or a declared type", Phase.Parse) }
            try self.finish(NodeKind.Binding, start, mark, present(operation))
        } else if self.at("return") || self.at("break") || self.at("continue") {
            let kind = if self.at("return") { NodeKind.Return } else if self.at("break") { NodeKind.Break } else { NodeKind.Continue }
            self.advance()
            if !self.range_end() {
                if kind.is(NodeKind.Continue) { try self.fail("continue cannot carry a value", Phase.Parse) }
                try self.expression(1usize)
            }
            try self.finish(kind, start, mark, none)
        } else {
            try self.expression(1usize)
            if self.at("=") || self.at("+=") || self.at("-=") || self.at("*=") || self.at("/=") || self.at("%=") || self.at("&=") || self.at("|=") || self.at("^=") || self.at("<<=") || self.at(">>=") {
                let assignment = self.look.index as u32
                self.advance()
                self.newlines()
                try self.expression(1usize)
                try self.finish(NodeKind.Assign, start, mark, present(assignment))
            }
        }
        var separated = false
        var semicolon = false
        while self.look.token.kind.is(Kind.Newline) || self.at(";") {
            separated = true
            if self.at(";") { semicolon = true }
            self.advance()
        }
        if semicolon {
            let id = self.pending[self.pending.len() - 1].index as usize
            self.result.nodes[id].semicolon = true
        }
        if !separated && !self.look.token.kind.is(Kind.End) && !self.at("}") {
            try self.fail("expected a newline or ';' between statements", Phase.Parse)
        }
    }
    fn brace(index: usize, byte: u8): bool {
        let token = self.result.tokens[index]
        token.kind.is(Kind.Symbol) && token.span.end == token.span.begin + 1u32 && self.bytes[token.span.begin as usize] == byte
    }
    mut fn recover(start: Anchor, saved: Checkpoint, block: bool): Unit throws Failure {
        self.pending.truncate(saved.pending)
        self.result.nodes.truncate(saved.nodes)
        self.result.children.truncate(saved.children)
        self.depth = saved.depth
        self.suppressed = saved.suppressed
        self.generic_level = saved.generic_level
        self.refresh()
        if self.look.index == start.token && !self.look.token.kind.is(Kind.End) && !(block && self.at("}")) { self.advance() }
        var open = 0usize
        var index = start.token
        while index < self.look.index {
            if self.brace(index, b'{') { open += 1 }
            else if self.brace(index, b'}') && open != 0 { open -= 1 }
            index += 1
        }
        while !self.look.token.kind.is(Kind.End) {
            if self.at("{") { open += 1 }
            else if self.at("}") {
                if open == 0 && block { break }
                if open != 0 { open -= 1 }
            } else if open == 0 && (self.look.token.kind.is(Kind.Newline) || self.at(";") || self.at("fn") || self.at("pub") || self.at("module") || self.at("import")) { break }
            self.advance()
        }
        try self.finish(NodeKind.Error, start, saved.pending, none)
    }
    mut fn block(): Unit throws Failure {
        try self.enter()
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("{", "expected '{'")
        let suppressed = self.suppressed
        let generic_level = self.generic_level
        self.suppressed = 0usize
        self.generic_level = 0usize
        self.refresh()
        self.separators()
        while !self.at("}") && !self.look.token.kind.is(Kind.End) {
            let before = self.anchor()
            let saved = self.checkpoint()
            if (capture self.statement()).is_failure() { try self.recover(before, saved, true) }
            self.separators()
        }
        try self.expect("}", "expected '}'")
        self.suppressed = suppressed
        self.generic_level = generic_level
        self.refresh()
        try self.finish(NodeKind.Block, start, mark, none)
        self.depth -= 1
    }
    mut fn visibility(): Unit throws Failure {
        if self.at("pub") {
            let visibility = self.anchor()
            let visibility_mark = self.pending.len()
            let operation = self.look.index as u32
            self.advance()
            if self.consume("(") {
                self.suppressed += 1
                self.refresh()
                try self.name(false)
                while self.consume(".") { try self.name(false) }
                try self.close(")", "expected ')'")
            }
            try self.finish(NodeKind.Visibility, visibility, visibility_mark, present(operation))
        }
    }
    mut fn function(start: Anchor, mark: usize): Unit throws Failure {
        if self.at("unsafe") { try self.declaration_modifier() }
        if self.at("const") && !self.followed_by("fn") { try self.fail("this declaration is not implemented in the Mettle parser yet", Phase.Feature) }
        if self.at("const") { try self.declaration_modifier() }
        if self.at("async") { try self.fail("async function bodies are not implemented in the Mettle parser yet", Phase.Feature) }
        if !self.at("fn") && (self.at("type") || self.at("copy") || self.at("union") || self.at("enum") || self.at("module") || self.at("import") || self.at("extend") || self.at("interface") || self.at("static") || self.at("alias") || self.at("extern")) { try self.fail("this declaration is not implemented in the Mettle parser yet", Phase.Feature) }
        try self.expect("fn", "expected a declaration")
        try self.name(false)
        if self.at("<") { try self.generic_parameters() }
        let parameters = self.anchor()
        let parameter_mark = self.pending.len()
        try self.expect("(", "expected '('")
        self.suppressed += 1
        self.refresh()
        while !self.at(")") && !self.look.token.kind.is(Kind.End) {
            let parameter = self.anchor()
            let child_mark = self.pending.len()
            var mode: u32? = none
            if self.at("read") || self.at("mut") || self.at("take") { mode = present(self.look.index as u32); self.advance() }
            if self.at("(") || self.at("[") || self.at("_") || self.at("receiver") { try self.fail("parameter patterns and explicit receivers are not implemented in the Mettle parser yet", Phase.Feature) }
            try self.name(false)
            try self.expect(":", "expected ':'")
            if self.at("format") && self.followed_by_name() { try self.declaration_modifier() }
            try self.type_name(true)
            if self.at("=") {
                let value = self.anchor()
                let value_mark = self.pending.len()
                self.advance()
                try self.expression(1usize)
                try self.finish(NodeKind.DefaultValue, value, value_mark, none)
            }
            try self.finish(NodeKind.Parameter, parameter, child_mark, mode)
            if !self.consume(",") { break }
        }
        try self.close(")", "expected ')'")
        try self.finish(NodeKind.Parameters, parameters, parameter_mark, none)
        if self.consume(":") { try self.type_name(false) }
        if self.consume("->") { try self.fail("function results use ': Type', not '->'", Phase.Parse) }
        if self.at("throws") {
            let effect = self.anchor()
            let effect_mark = self.pending.len()
            let operation = self.look.index as u32
            self.advance()
            try self.type_name(true)
            try self.finish(NodeKind.TypeEffect, effect, effect_mark, present(operation))
        }
        try self.constraints()
        self.newlines()
        if self.at("=>") {
            let operation = self.look.index as u32
            self.advance()
            self.newlines()
            let body = self.anchor()
            let body_mark = self.pending.len()
            try self.expression(1usize)
            try self.finish(NodeKind.Block, body, body_mark, present(operation))
        } else { try self.block() }
        try self.finish(NodeKind.Function, start, mark, none)
    }
    mut fn declaration_modifier(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        self.advance()
        try self.finish(NodeKind.Modifier, start, mark, present(operation))
    }
    mut fn bounds(region_bound: bool): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        loop {
            if region_bound && self.at("static") { try self.region_name() }
            else if self.at("?") {
                let bound = self.anchor()
                let bound_mark = self.pending.len()
                let operation = self.look.index as u32
                self.advance()
                try self.name(false)
                try self.finish(NodeKind.Modifier, bound, bound_mark, present(operation))
            } else { try self.type_name(false) }
            if !self.consume("+") { break }
        }
        try self.finish(NodeKind.Bounds, start, mark, none)
    }
    mut fn generic_parameters(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("<", "expected '<'")
        self.suppressed += 1
        self.refresh()
        while !self.at(">") && !self.at(">>") && !self.look.token.kind.is(Kind.End) {
            let parameter = self.anchor()
            let parameter_mark = self.pending.len()
            var operation: u32? = none
            let is_region = self.at("region")
            let is_constant = self.at("const")
            if is_region || is_constant { operation = present(self.look.index as u32); self.advance() }
            try self.name(false)
            if self.consume(":") {
                if is_constant { try self.type_name(false) } else { try self.bounds(is_region) }
            } else if is_constant { try self.fail("const parameter requires a declared scalar type", Phase.Parse) }
            if self.at("=") {
                let value = self.anchor()
                let value_mark = self.pending.len()
                self.advance()
                if is_region { try self.fail("region parameters cannot have defaults", Phase.Parse) }
                if is_constant { try self.generic_value() } else { try self.type_name(false) }
                try self.finish(if is_constant { NodeKind.DefaultValue } else { NodeKind.DefaultType }, value, value_mark, none)
            }
            try self.finish(NodeKind.GenericParameter, parameter, parameter_mark, operation)
            if self.pending.len() - mark > 4194304usize { try self.fail("generic parameter limit exceeded", Phase.Limit) }
            if !self.consume(",") { break }
        }
        try self.angle_close("expected '>' after generic parameters")
        try self.finish(NodeKind.GenericParameters, start, mark, none)
    }
    mut fn constraints(): Unit throws Failure {
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        self.newlines()
        if !self.at("where") { self.position = position; self.look = look; self.last_end = last_end; self.last_token = last_token; return }
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        loop {
            let constraint = self.anchor()
            let constraint_mark = self.pending.len()
            if self.at("region") {
                let operation = self.look.index as u32
                self.advance()
                try self.region_name()
                try self.finish(NodeKind.Modifier, constraint, constraint_mark, present(operation))
            } else { try self.type_name(false) }
            let operation = self.look.index as u32
            if self.consume("=") { try self.type_name(false) }
            else { try self.expect(":", "expected ':'"); try self.bounds(true) }
            try self.finish(NodeKind.Constraint, constraint, constraint_mark, present(operation))
            if !self.consume(",") { break }
        }
        try self.finish(NodeKind.Constraints, start, mark, none)
    }
    mut fn import_path(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.name(false)
        while self.at(".") && self.followed_by_name() { self.advance(); try self.name(false) }
        try self.finish(NodeKind.ImportPath, start, mark, none)
    }
    mut fn import_alias(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("as", "expected 'as'")
        try self.name(false)
        try self.finish(NodeKind.ImportAlias, start, mark, none)
    }
    mut fn end_item(read message: Text from static): Unit throws Failure {
        if self.consume(";") {
            let id = self.pending[self.pending.len() - 1].index as usize
            self.result.nodes[id].semicolon = true
        } else if !self.look.token.kind.is(Kind.Newline) && !self.look.token.kind.is(Kind.End) && !self.at("}") { try self.fail(message, Phase.Parse) }
    }
    mut fn import_declaration(start: Anchor, mark: usize): Unit throws Failure {
        let operation = self.look.index as u32
        try self.expect("import", "expected 'import'")
        try self.import_path()
        if self.at("as") { try self.import_alias() }
        else if self.consume(".") {
            let selection = self.anchor()
            let selection_mark = self.pending.len()
            if self.consume("*") { try self.finish(NodeKind.ImportGlob, selection, selection_mark, none) }
            else {
                try self.expect("{", "expected '{'")
                self.newlines()
                if self.at("}") { try self.fail("an import group requires at least one name", Phase.Parse) }
                loop {
                    self.newlines()
                    if self.at("}") { break }
                    let entry = self.anchor()
                    let entry_mark = self.pending.len()
                    try self.name(false)
                    if self.at(".") && self.followed_by_name() { try self.fail("dotted names in import groups are not implemented", Phase.Feature) }
                    if self.at("as") { try self.import_alias() }
                    try self.finish(NodeKind.ImportName, entry, entry_mark, none)
                    self.newlines()
                    if !self.consume(",") { break }
                }
                try self.expect("}", "expected '}'")
                try self.finish(NodeKind.ImportGroup, selection, selection_mark, none)
            }
        }
        try self.finish(NodeKind.Import, start, mark, present(operation))
        try self.end_item("expected a newline after an import")
    }
    mut fn module_declaration(start: Anchor, mark: usize): Unit throws Failure {
        let operation = self.look.index as u32
        try self.expect("module", "expected 'module'")
        try self.name(false)
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        self.newlines()
        if self.at("{") {
            let body = self.anchor()
            let body_mark = self.pending.len()
            self.advance()
            self.depth += 1
            if self.depth > 128 { try self.fail("module nesting limit exceeded", Phase.Limit) }
            try self.items(true)
            try self.expect("}", "expected '}'")
            self.depth -= 1
            try self.finish(NodeKind.ModuleBody, body, body_mark, none)
            try self.finish(NodeKind.ModuleDeclaration, start, mark, present(operation))
        } else {
            self.position = position
            self.look = look
            self.last_end = last_end
            self.last_token = last_token
            try self.finish(NodeKind.ModuleDeclaration, start, mark, present(operation))
            try self.end_item("expected a newline after an external module")
        }
    }
    mut fn item(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.visibility()
        if self.at("module") { try self.module_declaration(start, mark) }
        else if self.at("import") { try self.import_declaration(start, mark) }
        else if self.at("fn") || self.at("unsafe") || (self.at("const") && self.followed_by("fn")) { try self.function(start, mark) }
        else if self.at("type") || self.at("copy") || self.at("enum") || self.at("union") || self.at("extend") || self.at("alias") || self.at("interface") || self.at("const") || self.at("static") || self.at("extern") || self.at("async") || self.at("macro") || self.at("@") { try self.fail("this declaration is not implemented in the Mettle parser yet", Phase.Feature) }
        else { try self.fail("expected a declaration", Phase.Parse) }
    }
    mut fn items(nested: bool): Unit throws Failure {
        self.separators()
        while !self.look.token.kind.is(Kind.End) && !(nested && self.at("}")) {
            let before = self.anchor()
            let saved = self.checkpoint()
            if (capture self.item()).is_failure() { try self.recover(before, saved, nested) }
            self.separators()
        }
    }
    mut fn program(): Unit throws Failure {
        let start = Anchor(0usize, 0u32)
        try self.items(false)
        self.last_end = self.bytes.len() as u32
        self.last_token = self.result.tokens.len() - 1
        try self.finish(NodeKind.Module, start, 0usize, none)
        self.result.root = present(self.pending[0usize])
    }
}

pub fn parse(read bytes: [u8], source: u32): Parsed {
    let lexed = tokenize(bytes, source)
    let first = lexed.tokens[0usize]
    var parser = Parser(read bytes, source, Position(0usize, 0u32), Look(first, 0usize, Position(0usize, 0u32)), 0u32, 0usize, 0usize, 0usize, 0usize, new<NodeId>(), new<u8>(), new<usize>(), new<u8>(), Parsed(lexed.tokens, new<SyntaxNode>(), new<NodeId>(), none, lexed.diagnostics))
    if parser.result.diagnostics.error_count == 0 {
        parser.refresh()
        let _ = capture parser.program()
    }
    parser.result
}
