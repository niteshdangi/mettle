import alloc.vec.{ List, new }
import core.text.Text
import mettle_foundation.{ Span, Diagnostics, Phase }
import super.lexer.tokenize
import super.token.{ Token, Kind }
import super.characters.validate_text
import super.tree.{ NodeId, IndexRange, NodeKind, SyntaxNode, Parsed }

copy type Failure {}
copy enum BodyContext { File, Product, Union, Interface, Extension, Foreign, ForeignDefinition }
extend BodyContext { fn is(other: BodyContext): bool { (self as u32) == (other as u32) } }
copy type Position { token: usize; offset: u32 }
copy type Look { token: Token; index: usize; next: Position }
copy type Anchor { token: usize; begin: u32 }
copy type Checkpoint { pending: usize; nodes: usize; children: usize; depth: usize; suppressed: usize; generic_level: usize; header_level: usize? }

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
    header_level: usize?
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
    fn checkpoint(): Checkpoint { Checkpoint(self.pending.len(), self.result.nodes.len(), self.result.children.len(), self.depth, self.suppressed, self.generic_level, self.header_level) }
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
            || self.at("pub") || self.at("internal") || self.at("module") || self.at("import") || self.at("interface")
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
    mut fn followed_by_word(): bool {
        let position = self.position
        let look = self.look
        self.position = look.next
        self.refresh()
        let followed = self.look.token.kind.is(Kind.Word) || self.look.token.kind.is(Kind.QuotedWord)
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
                self.newlines()
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
                } else { try self.name(false); while self.consume(".") { try self.name(false) } }
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
        if self.at("!") {
            self.advance()
            try self.token_tree()
            try self.finish(NodeKind.MacroInvocation, start, mark, none)
        } else if self.at("<") {
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
        if self.pending.len() == mark { try self.fail("expected a region binder", Phase.Parse) }
        try self.angle_close("expected '>' after region binders")
        try self.finish(NodeKind.TypeBinders, start, mark, none)
    }
    mut fn bound_type(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let ranked = self.at("for")
        if ranked { try self.type_binders() }
        if self.at("fn") || self.at("mut") || self.at("take") || self.at("unsafe") || self.at("extern") || self.at("async") { try self.callable_type(start, mark) }
        else { try self.type_path() }
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
        if self.pending.len() == mark { try self.fail("expected a generic argument", Phase.Parse) }
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
        let foreign = self.at("extern")
        if self.at("extern") { try self.type_modifier() }
        if self.at("async") { try self.type_modifier() }
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
                if !foreign || self.pending.len() == parameter_mark { try self.fail("variadic callable types require a foreign ABI and a fixed parameter", Phase.Parse) }
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
        self.newlines()
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
            || self.look.token.kind.is(Kind.FormatHoleClose) || self.at("=>")
            || self.at("]") || self.at(")") || self.at(",") || self.at("}") || self.at(";")
            || (self.at("{") && self.header_here()))
    }
    fn header_here(): bool { match self.header_level { present(level) => level == self.suppressed, none => false } }
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
        if !kind.is(NodeKind.Name) && !kind.is(NodeKind.Field) && !kind.is(NodeKind.Projection) { return false }
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
        self.header_level = saved.header_level
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
        var named = false
        if !self.at(close) {
            loop {
                if self.name_token() && self.followed_by(":") {
                    named = true
                    let start = self.anchor()
                    let mark = self.pending.len()
                    try self.name(false)
                    try self.expect(":", "expected ':'")
                    try self.expression(1usize)
                    try self.finish(NodeKind.NamedArgument, start, mark, none)
                } else {
                    if named { try self.fail("positional arguments must precede named arguments", Phase.Parse) }
                    try self.expression(1usize)
                }
                if !self.consume(",") || self.at(close) { break }
            }
        }
        try self.close(close, message)
    }
    mut fn leaf(kind: NodeKind): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        try self.finish(kind, start, mark, none)
    }
    fn pattern_literal(): bool {
        let kind = self.look.token.kind
        kind.is(Kind.Integer) || kind.is(Kind.Floating) || kind.is(Kind.Character) || kind.is(Kind.Byte) || kind.is(Kind.Text) || kind.is(Kind.PrefixedText) || self.at("true") || self.at("false")
    }
    fn rest_pattern(id: NodeId): bool {
        let node = self.result.nodes[id.index as usize]
        if node.kind.is(NodeKind.PatternRest) { return true }
        if !node.kind.is(NodeKind.PatternAt) { return false }
        self.rest_pattern(self.result.children[node.children.end as usize - 1])
    }
    mut fn pattern(minimum: usize, rest_allowed: bool): Unit throws Failure {
        self.depth += 1
        if self.depth > 128 { try self.fail("pattern nesting limit exceeded", Phase.Limit) }
        let start = self.anchor()
        let mark = self.pending.len()
        if self.at("..") {
            if !rest_allowed { try self.fail("rest patterns belong to slice patterns", Phase.Parse) }
            try self.leaf(NodeKind.PatternRest)
        }
        else if self.at("_") { try self.leaf(NodeKind.PatternWildcard) }
        else if self.at("(") || self.at("[") {
            let tuple = self.at("(")
            self.advance()
            self.suppressed += 1
            self.refresh()
            let close = if tuple { ")" } else { "]" }
            var rest = false
            while !self.at(close) && !self.look.token.kind.is(Kind.End) {
                try self.pattern(0usize, !tuple)
                if self.rest_pattern(self.pending[self.pending.len() - 1]) {
                    if rest { try self.fail("a slice pattern has only one rest", Phase.Parse) }
                    rest = true
                }
                if !self.consume(",") { break }
            }
            try self.close(close, "expected a pattern closing delimiter")
            try self.finish(if tuple { NodeKind.PatternTuple } else { NodeKind.PatternArray }, start, mark, none)
        } else if self.pattern_literal() || self.at("-") {
            if self.consume("-") && !(self.look.token.kind.is(Kind.Integer) || self.look.token.kind.is(Kind.Floating)) { try self.fail("expected a numeric literal after '-' in a pattern", Phase.Parse) }
            if self.look.token.kind.is(Kind.Text) || self.look.token.kind.is(Kind.PrefixedText) {
                let span = self.look.token.span
                validate_text(read self.bytes[span.begin as usize..span.end as usize], span, mut self.result.diagnostics)
            }
            self.advance()
            try self.finish(NodeKind.PatternLiteral, start, mark, none)
            if self.at("..") || self.at("..=") {
                let operation = self.look.index as u32
                self.advance()
                try self.pattern(1usize, false)
                if !self.result.nodes[self.pending[self.pending.len() - 1].index as usize].kind.is(NodeKind.PatternLiteral) { try self.fail("range pattern requires literal bounds", Phase.Parse) }
                try self.finish(NodeKind.PatternRange, start, mark, present(operation))
            }
        } else {
            let builtin = self.at("none") || self.at("present") || self.at("success") || self.at("failure")
            if builtin { try self.leaf(NodeKind.Name) } else { try self.name(false) }
            var qualified = false
            while self.consume(".") { qualified = true; try self.name(false) }
            if self.consume("(") {
                self.suppressed += 1
                self.refresh()
                while !self.at(")") && !self.look.token.kind.is(Kind.End) { try self.pattern(0usize, false); if !self.consume(",") { break } }
                try self.close(")", "expected ')'")
                try self.finish(NodeKind.PatternVariant, start, mark, none)
            } else if self.consume("{") {
                self.separators()
                while !self.at("}") && !self.look.token.kind.is(Kind.End) {
                    if self.at("..") {
                        try self.leaf(NodeKind.PatternRest)
                        let _ = self.consume(",")
                        self.separators()
                        if !self.at("}") { try self.fail("product rest must be the final field pattern", Phase.Parse) }
                        break
                    }
                    let field = self.anchor()
                    let field_mark = self.pending.len()
                    try self.name(false)
                    if self.consume(":") { try self.pattern(0usize, false) }
                    try self.finish(NodeKind.PatternField, field, field_mark, none)
                    if !self.consume(",") && !self.at("}") && !self.look.token.kind.is(Kind.Newline) { try self.fail("expected a field pattern separator", Phase.Parse) }
                    self.separators()
                }
                try self.expect("}", "expected '}'")
                try self.finish(NodeKind.PatternProduct, start, mark, none)
            } else if builtin || qualified { try self.finish(NodeKind.PatternVariant, start, mark, none) }
        }
        if self.at("@") {
            if !self.result.nodes[self.pending[self.pending.len() - 1].index as usize].kind.is(NodeKind.Name) { try self.fail("a pattern binding before '@' must be a name", Phase.Parse) }
            self.advance()
            try self.pattern(1usize, rest_allowed)
            try self.finish(NodeKind.PatternAt, start, mark, none)
        }
        if minimum == 0 && self.consume("|") {
            loop { try self.pattern(1usize, false); if !self.consume("|") { break } }
            try self.finish(NodeKind.PatternOr, start, mark, none)
        }
        self.depth -= 1
    }
    mut fn conditions(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        loop {
            let condition = self.anchor()
            let child_mark = self.pending.len()
            let binding = self.consume("let")
            if binding { try self.pattern(0usize, false); try self.expect("=", "expected '='") }
            try self.expression(1usize)
            if binding { try self.finish(NodeKind.Condition, condition, child_mark, none) }
            if !self.consume(",") { break }
            self.newlines()
        }
        if self.pending.len() - mark != 1 || self.result.nodes[self.pending[mark].index as usize].kind.is(NodeKind.Condition) { try self.finish(NodeKind.Conditions, start, mark, none) }
    }
    mut fn match_expression(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("match", "expected 'match'")
        var operation: u32? = none
        if self.at("mut") || self.at("take") { operation = present(self.look.index as u32); self.advance() }
        let enclosing_header = self.header_level
        self.header_level = present(self.suppressed)
        try self.expression(1usize)
        self.header_level = enclosing_header
        self.newlines()
        try self.expect("{", "expected '{'")
        let suppressed = self.suppressed
        let generic_level = self.generic_level
        let header = self.header_level
        self.suppressed = 0usize
        self.generic_level = 0usize
        self.header_level = none
        self.refresh()
        self.separators()
        while !self.at("}") && !self.look.token.kind.is(Kind.End) {
            let arm = self.anchor()
            let arm_mark = self.pending.len()
            try self.pattern(0usize, false)
            if self.at("if") {
                let guard = self.anchor()
                let guard_mark = self.pending.len()
                self.advance()
                try self.expression(1usize)
                try self.finish(NodeKind.Guard, guard, guard_mark, none)
            }
            try self.expect("=>", "expected '=>'")
            self.newlines()
            try self.expression(1usize)
            try self.finish(NodeKind.Arm, arm, arm_mark, none)
            if !self.consume(",") && !self.at("}") && !self.look.token.kind.is(Kind.Newline) { try self.fail("expected a match arm separator", Phase.Parse) }
            self.separators()
        }
        try self.expect("}", "expected '}'")
        self.suppressed = suppressed
        self.generic_level = generic_level
        self.header_level = header
        self.refresh()
        try self.finish(NodeKind.Match, start, mark, operation)
    }
    mut fn closure(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        if self.at("async") { try self.declaration_modifier(); self.newlines() }
        if self.at("{") { try self.block(); try self.finish(NodeKind.Closure, start, mark, none); return }
        if self.at("take") { try self.declaration_modifier() }
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
            var mode: u32? = none
            if self.at("read") || self.at("mut") || self.at("take") { mode = present(self.look.index as u32); self.advance() }
            try self.pattern(1usize, false)
            if self.consume(":") { try self.type_name(true) }
            try self.finish(NodeKind.Parameter, parameter, child_mark, mode)
            if !self.consume(",") { break }
        }
        try self.close(")", "expected ')'")
        try self.finish(NodeKind.Parameters, parameters, parameter_mark, none)
        if self.consume(":") { try self.type_name(false) }
        try self.effect()
        self.newlines()
        try self.function_body(false)
        try self.finish(NodeKind.Closure, start, mark, present(operation))
    }
    mut fn token_tree(): Unit throws Failure {
        self.depth += 1
        if self.depth > 128 { try self.fail("token tree nesting limit exceeded", Phase.Limit) }
        let start = self.anchor()
        let mark = self.pending.len()
        let close = if self.at("(") { ")" } else if self.at("[") { "]" } else if self.at("{") { "}" } else { try self.fail("expected a delimited token tree", Phase.Parse) }
        self.advance()
        while !self.look.token.kind.is(Kind.End) {
            if self.look.token.kind.is(Kind.Symbol) {
                if self.at(close) { break }
                if self.at("(") || self.at("[") || self.at("{") { try self.token_tree(); continue }
                if self.at(")") || self.at("]") || self.at("}") { try self.fail("mismatched token tree delimiter", Phase.Parse) }
            }
            self.advance()
        }
        try self.expect(close, "unterminated token tree")
        try self.finish(NodeKind.TokenTree, start, mark, none)
        self.depth -= 1
    }
    mut fn interpolation(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        while !self.look.token.kind.is(Kind.FormatClose) && !self.look.token.kind.is(Kind.End) {
            if self.look.token.kind.is(Kind.FormatPiece) {
                let span = self.look.token.span
                super.characters.validate_fragment(read self.bytes[span.begin as usize..span.end as usize], span, mut self.result.diagnostics)
                try self.leaf(NodeKind.FormatPiece)
            } else if self.look.token.kind.is(Kind.FormatHoleOpen) {
                let hole = self.anchor()
                let hole_mark = self.pending.len()
                self.advance()
                self.suppressed += 1
                self.refresh()
                let generic_level = self.generic_level
                let header = self.header_level
                self.generic_level = 0usize
                self.header_level = none
                try self.expression(1usize)
                if !self.look.token.kind.is(Kind.FormatHoleClose) { try self.fail("expected an interpolation closing brace", Phase.Parse) }
                self.generic_level = generic_level
                self.header_level = header
                self.suppressed -= 1
                self.advance()
                try self.finish(NodeKind.FormatHole, hole, hole_mark, none)
            } else { try self.fail("expected an interpolation piece or expression hole", Phase.Parse) }
        }
        if !self.look.token.kind.is(Kind.FormatClose) { try self.fail("unterminated interpolation", Phase.Parse) }
        self.advance()
        try self.finish(NodeKind.Interpolation, start, mark, none)
    }
    mut fn primary(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        let kind = self.look.token.kind
        if self.at("fn") || self.at("async") || (self.at("take") && self.followed_by("fn")) { try self.closure() }
        else if kind.is(Kind.FormatOpen) { try self.interpolation() }
        else if self.at("match") { try self.match_expression() }
        else if self.at("unsafe") {
            self.advance()
            self.newlines()
            try self.block()
            try self.finish(NodeKind.Unsafe, start, mark, present(operation))
        } else if self.at("none") { try self.leaf(NodeKind.None) }
        else if self.at("present") || self.at("success") || self.at("failure") {
            let variant = if self.at("present") { NodeKind.Present } else if self.at("success") { NodeKind.Success } else { NodeKind.Failure }
            self.advance()
            try self.expect("(", "expected '('")
            self.suppressed += 1
            self.refresh()
            try self.expression(1usize)
            try self.close(")", "expected ')'")
            try self.finish(variant, start, mark, present(operation))
        } else if self.at("try") || self.at("capture") || self.at("throw") || self.at("await") {
            let form = if self.at("try") { NodeKind.Try } else if self.at("capture") { NodeKind.Capture } else if self.at("throw") { NodeKind.Throw } else { NodeKind.Await }
            self.advance()
            self.newlines()
            try self.expression(if form.is(NodeKind.Throw) { 1usize } else { 13usize })
            try self.finish(form, start, mark, present(operation))
        } else if self.at("heap") || self.at("shared") || self.at("local") || self.at("weak") || self.at("pinned") {
            if self.at("pinned") {
                try self.declaration_modifier()
                if !self.at("heap") && !self.at("shared") && !self.at("local") { try self.fail("pinned construction requires an owner constructor", Phase.Parse) }
            }
            if self.at("local") { try self.declaration_modifier(); try self.expect("shared", "expected 'shared'") }
            else if self.at("heap") || self.at("shared") || self.at("weak") { try self.declaration_modifier() }
            self.newlines()
            try self.expression(13usize)
            try self.finish(NodeKind.Owner, start, mark, present(operation))
        } else if self.at("-") || self.at("!") || self.at("*") || self.at("read") || self.at("mut") || self.at("take") {
            self.advance()
            self.newlines()
            try self.expression(13usize)
            try self.finish(NodeKind.Unary, start, mark, present(operation))
        } else if self.at("{") { try self.block() }
        else if self.at("if") || self.at("while") || self.at("loop") || self.at("for") || self.at("label") { try self.control() }
        else if (self.at("[") || self.at("(")) && self.compound_projection() { try self.type_name(false) }
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
        else { try self.fail("expected an expression", Phase.Parse) }
        loop {
            if self.at(".") || self.at("?.") {
                let optional = self.at("?.")
                self.advance()
                self.newlines()
                if self.consume("(") {
                    if optional { try self.fail("optional access requires a member name", Phase.Parse) }
                    self.suppressed += 1
                    self.refresh()
                    try self.type_name(false)
                    try self.close(")", "expected ')'")
                    try self.expect(".", "expected '.'")
                    if self.at("drop") { try self.leaf(NodeKind.Name) } else { try self.name(false) }
                    try self.finish(NodeKind.Projection, start, mark, none)
                    continue
                }
                if self.look.token.kind.is(Kind.Integer) || self.at("drop") || self.at("copy") {
                    if optional && self.look.token.kind.is(Kind.Integer) { try self.fail("optional access requires a member name", Phase.Parse) }
                    let field = self.anchor()
                    self.advance()
                    try self.finish(NodeKind.Name, field, self.pending.len(), none)
                } else { try self.name(false) }
                try self.finish(if optional { NodeKind.OptionalField } else { NodeKind.Field }, start, mark, none)
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
            else if self.at("!") {
                self.advance()
                try self.token_tree()
                try self.finish(NodeKind.MacroInvocation, start, mark, present(operation))
            }
            else { break }
        }
    }
    fn compound_projection(): bool {
        let opening = if self.at("[") { b'[' } else { b'(' }
        let closing = if self.at("[") { b']' } else { b')' }
        var index = self.look.index
        var depth = 0usize
        while index < self.result.tokens.len() {
            let token = self.result.tokens[index]
            if token.kind.is(Kind.Symbol) && token.span.end == token.span.begin + 1u32 {
                let byte = self.bytes[token.span.begin as usize]
                if byte == opening { depth += 1 }
                else if byte == closing {
                    depth -= 1
                    if depth == 0 {
                        var suffix = 0usize
                        index += 1
                        while index < self.result.tokens.len() {
                            let next = self.result.tokens[index]
                            if !next.kind.is(Kind.Space) && !next.kind.is(Kind.Comment) && !next.kind.is(Kind.Newline) {
                                if !next.kind.is(Kind.Symbol) || next.span.end != next.span.begin + 1u32 { return false }
                                let expected = if suffix == 0 { b'.' } else { b'(' }
                                if self.bytes[next.span.begin as usize] != expected { return false }
                                if suffix == 1 { return true }
                                suffix += 1
                            }
                            index += 1
                        }
                        return false
                    }
                }
            }
            index += 1
        }
        false
    }
    mut fn control(): Unit throws Failure {
        try self.enter()
        let start = self.anchor()
        let mark = self.pending.len()
        let labeled = self.at("label")
        if labeled {
            let loop_label = self.anchor()
            let label_mark = self.pending.len()
            self.advance()
            try self.name(false)
            try self.expect(":", "expected ':'")
            try self.finish(NodeKind.Label, loop_label, label_mark, none)
            self.newlines()
            if !self.at("for") && !self.at("while") && !self.at("loop") { try self.fail("a label must introduce a loop", Phase.Parse) }
        }
        let kind = if self.at("if") { NodeKind.If } else if self.at("while") { NodeKind.While } else if self.at("for") { NodeKind.For } else { NodeKind.Loop }
        self.advance()
        let header = self.header_level
        self.header_level = present(self.suppressed)
        if kind.is(NodeKind.For) { try self.pattern(0usize, false); try self.expect("in", "expected 'in'"); try self.expression(1usize) }
        else if !kind.is(NodeKind.Loop) { try self.conditions() }
        self.header_level = header
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
    mut fn named_function_ahead(): bool {
        if !(self.at("fn") || self.at("unsafe") || self.at("async") || self.at("mut") || self.at("take")) { return false }
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        while self.at("unsafe") || self.at("const") || self.at("async") || self.at("mut") || self.at("take") || self.at("static") {
            let asynchronous = self.at("async")
            self.advance()
            if asynchronous && self.consume("(") { let _ = self.consume("heap"); let _ = self.consume(")") }
        }
        let named = self.at("fn") && self.followed_by_name()
        self.position = position
        self.look = look
        self.last_end = last_end
        self.last_token = last_token
        named
    }
    mut fn statement(): Unit throws Failure {
        if self.at("extend") {
            let saved = self.checkpoint()
            let position = self.position
            let look = self.look
            let last_end = self.last_end
            let last_token = self.last_token
            let issues = self.result.diagnostics.issues.len()
            let errors = self.result.diagnostics.error_count
            if (capture self.declaration(BodyContext.File)).is_success() { return }
            if self.result.diagnostics.issues.len() > issues && (self.result.diagnostics.issues[issues].phase as u32) == (Phase.Limit as u32) { throw Failure() }
            self.pending.truncate(saved.pending)
            self.result.nodes.truncate(saved.nodes)
            self.result.children.truncate(saved.children)
            self.depth = saved.depth
            self.suppressed = saved.suppressed
            self.generic_level = saved.generic_level
            self.header_level = saved.header_level
            self.position = position
            self.look = look
            self.last_end = last_end
            self.last_token = last_token
            self.result.diagnostics.issues.truncate(issues)
            self.result.diagnostics.error_count = errors
        }
        if self.at("@") || self.at("pub") || self.at("internal") || self.at("type") || self.at("copy") || self.at("enum") || self.at("interface") || self.at("module") || self.at("import") || self.at("extern") || self.at("const") || self.at("static") || self.at("alias") || self.at("macro") || self.named_function_ahead() {
            try self.declaration(BodyContext.File)
            return
        }
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        if self.at("let") || self.at("var") {
            let mutable_binding = self.at("var")
            self.advance()
            if self.at("mut") { try self.fail("`let mut` is not valid syntax", Phase.Parse) }
            let discard = self.at("_")
            if discard && mutable_binding { try self.fail("discard uses 'let _ = expression'", Phase.Parse) }
            try self.pattern(0usize, false)
            var typed = false
            if self.consume(":") { typed = true; try self.type_name(true) }
            if self.consume("=") { self.newlines(); try self.expression(1usize) }
            else if !typed || discard { try self.fail("binding requires an initializer or a declared type", Phase.Parse) }
            if self.at("else") {
                let otherwise = self.anchor()
                let otherwise_mark = self.pending.len()
                self.advance()
                self.newlines()
                try self.block()
                try self.finish(NodeKind.LetElse, otherwise, otherwise_mark, none)
            }
            try self.finish(NodeKind.Binding, start, mark, present(operation))
        } else if self.at("return") || self.at("break") || self.at("continue") {
            let kind = if self.at("return") { NodeKind.Return } else if self.at("break") { NodeKind.Break } else { NodeKind.Continue }
            self.advance()
            if !kind.is(NodeKind.Return) && self.at("label") {
                let loop_label = self.anchor()
                let label_mark = self.pending.len()
                self.advance()
                try self.name(false)
                try self.finish(NodeKind.Label, loop_label, label_mark, none)
            }
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
        self.header_level = saved.header_level
        self.refresh()
        if self.look.index == start.token && !self.look.token.kind.is(Kind.End) && !(block && self.at("}")) { self.advance() }
        var open = 0usize
        var enclosed = 0usize
        var index = start.token
        while index < self.look.index {
            if self.brace(index, b'{') { open += 1 }
            else if self.brace(index, b'}') && open != 0 { open -= 1 }
            else if self.brace(index, b'(') || self.brace(index, b'[') { enclosed += 1 }
            else if (self.brace(index, b')') || self.brace(index, b']')) && enclosed != 0 { enclosed -= 1 }
            index += 1
        }
        while !self.look.token.kind.is(Kind.End) {
            if self.at("(") || self.at("[") { enclosed += 1 }
            else if (self.at(")") || self.at("]")) && enclosed != 0 { enclosed -= 1 }
            if self.at("{") { open += 1 }
            else if self.at("}") {
                if open == 0 && block { break }
                if open != 0 { open -= 1 }
            } else if open == 0 && (self.look.token.kind.is(Kind.Newline) || self.at(";") || (enclosed == 0 && (self.at("fn") || self.at("pub") || self.at("internal") || self.at("module") || self.at("import")))) { break }
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
        let header = self.header_level
        self.suppressed = 0usize
        self.generic_level = 0usize
        self.header_level = none
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
        self.header_level = header
        self.refresh()
        try self.finish(NodeKind.Block, start, mark, none)
        self.depth -= 1
    }
    mut fn visibility(): Unit throws Failure {
        if self.at("pub") || self.at("internal") {
            let visibility = self.anchor()
            let visibility_mark = self.pending.len()
            let operation = self.look.index as u32
            let public = self.at("pub")
            self.advance()
            if public {
                if self.at("parent") && self.followed_by_word() { self.advance() }
                else if self.at("(") {
                    try self.fail("'pub(path)' visibility was removed; use 'internal' for package visibility or 'pub parent' for the parent module", Phase.Parse)
                }
            }
            try self.finish(NodeKind.Visibility, visibility, visibility_mark, present(operation))
        }
    }
    mut fn effect(): Unit throws Failure {
        if !self.at("throws") { return }
        let start = self.anchor()
        let mark = self.pending.len()
        let operation = self.look.index as u32
        self.advance()
        try self.type_name(true)
        try self.finish(NodeKind.TypeEffect, start, mark, present(operation))
    }
    mut fn function_body(constructor: bool): Unit throws Failure {
        self.newlines()
        if self.at("=>") {
            if constructor { try self.fail("constructors require a block body", Phase.Parse) }
            let operation = self.look.index as u32
            self.advance()
            self.newlines()
            let start = self.anchor()
            let mark = self.pending.len()
            let header = self.header_level
            self.header_level = none
            try self.expression(1usize)
            self.header_level = header
            try self.finish(NodeKind.Block, start, mark, present(operation))
        } else { try self.block() }
    }
    mut fn function(start: Anchor, mark: usize, context: BodyContext): Unit throws Failure {
        if self.at("unsafe") { try self.declaration_modifier() }
        if self.at("const") { try self.declaration_modifier() }
        if self.at("async") {
            let modifier = self.anchor()
            let modifier_mark = self.pending.len()
            let operation = self.look.index as u32
            self.advance()
            if self.consume("(") { try self.expect("heap", "expected 'heap'"); try self.expect(")", "expected ')'") }
            try self.finish(NodeKind.Modifier, modifier, modifier_mark, present(operation))
        }
        if self.at("mut") || self.at("take") || self.at("static") { try self.declaration_modifier() }
        if self.at("unsafe") { try self.declaration_modifier() }
        let constructor = self.at("init")
        if constructor && !context.is(BodyContext.Product) && !context.is(BodyContext.Extension) { try self.fail("constructors belong to product or extension bodies", Phase.Parse) }
        if constructor { try self.leaf(NodeKind.Name) } else { try self.expect("fn", "expected a declaration"); try self.name(false) }
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
            if self.at("...") {
                if !context.is(BodyContext.Foreign) || self.pending.len() == parameter_mark { try self.fail("foreign varargs require a named fixed parameter", Phase.Parse) }
                try self.leaf(NodeKind.TypeVariadic)
                break
            }
            if self.at("receiver") { try self.declaration_modifier() }
            if self.at("read") || self.at("mut") || self.at("take") { mode = present(self.look.index as u32); self.advance() }
            try self.pattern(0usize, false)
            if context.is(BodyContext.Foreign) && !self.result.nodes[self.pending[self.pending.len() - 1].index as usize].kind.is(NodeKind.Name) { try self.fail("foreign declarations require named parameters", Phase.Parse) }
            try self.expect(":", "expected ':'")
            if self.at("...") {
                if !context.is(BodyContext.ForeignDefinition) || child_mark == parameter_mark { try self.fail("a variadic cursor requires a foreign definition with a fixed parameter", Phase.Parse) }
                try self.leaf(NodeKind.TypeVariadic)
                try self.finish(NodeKind.Parameter, parameter, child_mark, mode)
                break
            }
            if self.at("format") && self.followed_by_name() { try self.declaration_modifier() }
            try self.type_name(true)
            if self.at("=") {
                if context.is(BodyContext.Foreign) { try self.fail("foreign declarations cannot have parameter defaults", Phase.Parse) }
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
        let has_result = self.consume(":")
        if has_result { self.newlines(); try self.type_name(false) }
        if self.consume("->") { try self.fail("function results use ': Type', not '->'", Phase.Parse) }
        try self.effect()
        try self.constraints()
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        self.newlines()
        if !self.at("{") && !self.at("=>") && (context.is(BodyContext.Interface) || context.is(BodyContext.Foreign)) {
            self.position = position
            self.look = look
            self.last_end = last_end
            self.last_token = last_token
            if !has_result { try self.fail("function declarations require an explicit result type", Phase.Parse) }
            try self.finish(NodeKind.Function, start, mark, none)
            try self.end_item("expected a function declaration separator")
        } else {
            if context.is(BodyContext.Foreign) { try self.fail("foreign declarations cannot have bodies", Phase.Parse) }
            try self.function_body(constructor)
            try self.finish(if constructor { NodeKind.Constructor } else { NodeKind.Function }, start, mark, none)
        }
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
            self.newlines()
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
        if self.pending.len() == mark { try self.fail("expected a generic parameter", Phase.Parse) }
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
            self.newlines()
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
                    if self.at(".") && self.followed_by_name() { try self.fail("import group members must be single names", Phase.Parse) }
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
        try self.declaration(BodyContext.File)
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
    mut fn attributes(): Unit throws Failure {
        while self.at("@") {
            let start = self.anchor()
            let mark = self.pending.len()
            self.advance()
            if !self.look.token.kind.is(Kind.Word) && !self.look.token.kind.is(Kind.QuotedWord) { try self.fail("expected an attribute name", Phase.Parse) }
            try self.leaf(NodeKind.Name)
            while self.consume(".") { try self.name(false) }
            if self.at("(") { try self.token_tree() }
            try self.finish(NodeKind.Attribute, start, mark, none)
            self.newlines()
        }
    }
    mut fn continuation(read text: Text): bool {
        let position = self.position
        let look = self.look
        let last_end = self.last_end
        let last_token = self.last_token
        self.newlines()
        if self.consume(text) { return true }
        self.position = position
        self.look = look
        self.last_end = last_end
        self.last_token = last_token
        false
    }
    mut fn fields(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("{", "expected '{'")
        self.separators()
        while !self.at("}") && !self.look.token.kind.is(Kind.End) {
            let field = self.anchor()
            let field_mark = self.pending.len()
            try self.attributes()
            try self.visibility()
            try self.name(false)
            try self.expect(":", "expected ':'")
            try self.type_name(true)
            try self.finish(NodeKind.FieldDeclaration, field, field_mark, none)
            if !self.consume(",") { try self.end_item("expected a field separator") }
            self.separators()
        }
        try self.expect("}", "expected '}'")
        try self.finish(NodeKind.Members, start, mark, none)
    }
    mut fn declaration_body(context: BodyContext): Unit throws Failure {
        self.depth += 1
        if self.depth > 128 { try self.fail("declaration nesting limit exceeded", Phase.Limit) }
        let start = self.anchor()
        let mark = self.pending.len()
        self.newlines()
        try self.expect("{", "expected '{'")
        self.separators()
        while !self.at("}") && !self.look.token.kind.is(Kind.End) {
            let before = self.anchor()
            let saved = self.checkpoint()
            if (capture self.declaration(context)).is_failure() { try self.recover(before, saved, true) }
            self.separators()
        }
        try self.expect("}", "expected '}'")
        try self.finish(NodeKind.Members, start, mark, none)
        self.depth -= 1
    }
    mut fn enumeration(start: Anchor, mark: usize): Unit throws Failure {
        try self.expect("enum", "expected 'enum'")
        try self.name(false)
        if self.at("<") { try self.generic_parameters() }
        try self.constraints()
        self.newlines()
        try self.expect("{", "expected '{'")
        self.separators()
        while !self.at("}") && !self.look.token.kind.is(Kind.End) {
            let variant = self.anchor()
            let variant_mark = self.pending.len()
            try self.attributes()
            try self.name(false)
            if self.consume("(") {
                self.suppressed += 1
                self.refresh()
                while !self.at(")") && !self.look.token.kind.is(Kind.End) { try self.type_name(true); if !self.consume(",") { break } }
                try self.close(")", "expected ')'")
            } else if self.at("{") { try self.fields() }
            if self.at("=") {
                let value = self.anchor()
                let value_mark = self.pending.len()
                self.advance()
                try self.expression(1usize)
                try self.finish(NodeKind.DefaultValue, value, value_mark, none)
            }
            try self.finish(NodeKind.VariantDeclaration, variant, variant_mark, none)
            if !self.consume(",") { try self.end_item("expected a variant separator") }
            self.separators()
        }
        try self.expect("}", "expected '}'")
        try self.finish(NodeKind.Enumeration, start, mark, none)
    }
    mut fn product(start: Anchor, mark: usize): Unit throws Failure {
        let overlapping = self.at("union")
        self.advance()
        try self.name(false)
        if self.at("<") { try self.generic_parameters() }
        if self.continuation("implements") { try self.bounds(false) }
        try self.constraints()
        try self.declaration_body(if overlapping { BodyContext.Union } else { BodyContext.Product })
        try self.finish(if overlapping { NodeKind.Union } else { NodeKind.Product }, start, mark, none)
    }
    mut fn interface_declaration(start: Anchor, mark: usize): Unit throws Failure {
        try self.expect("interface", "expected 'interface'")
        try self.name(false)
        if self.at("<") { try self.generic_parameters() }
        if self.consume(":") { try self.bounds(false) }
        try self.constraints()
        try self.declaration_body(BodyContext.Interface)
        try self.finish(NodeKind.Interface, start, mark, none)
    }
    mut fn extension(start: Anchor, mark: usize): Unit throws Failure {
        try self.expect("extend", "expected 'extend'")
        if self.at("<") { try self.generic_parameters() }
        try self.type_name(false)
        let negative = self.consume("not")
        if negative { try self.type_name(false) }
        else if self.continuation("implements") { try self.type_name(false) }
        try self.constraints()
        if !negative { try self.declaration_body(BodyContext.Extension) }
        try self.finish(if negative { NodeKind.NegativeExtension } else { NodeKind.Extension }, start, mark, none)
        if negative { try self.end_item("expected a negative extension separator") }
    }
    mut fn associated(start: Anchor, mark: usize): Unit throws Failure {
        let constant = self.at("const")
        self.advance()
        try self.name(false)
        if self.at("<") { try self.generic_parameters() }
        if self.consume(":") { if constant { try self.type_name(false) } else { try self.bounds(false) } }
        try self.constraints()
        if self.at("=") {
            let value = self.anchor()
            let value_mark = self.pending.len()
            self.advance()
            if constant { try self.expression(1usize) } else { try self.type_name(true) }
            try self.finish(if constant { NodeKind.DefaultValue } else { NodeKind.DefaultType }, value, value_mark, none)
        }
        try self.finish(if constant { NodeKind.Constant } else { NodeKind.AssociatedType }, start, mark, none)
        try self.end_item("expected an associated item separator")
    }
    mut fn value_declaration(start: Anchor, mark: usize, foreign: bool): Unit throws Failure {
        let constant = self.at("const")
        self.advance()
        if !constant && self.at("mut") { try self.declaration_modifier() }
        try self.name(false)
        try self.expect(":", "expected ':'")
        try self.type_name(true)
        if !foreign { try self.expect("=", "expected '='"); self.newlines(); try self.expression(1usize) }
        try self.finish(if constant { NodeKind.Constant } else { NodeKind.Static }, start, mark, none)
        try self.end_item("expected a constant or static item separator")
    }
    mut fn foreign_declaration(start: Anchor, mark: usize): Unit throws Failure {
        try self.expect("extern", "expected 'extern'")
        if !self.look.token.kind.is(Kind.Text) { try self.fail("expected a constant ABI text literal", Phase.Parse) }
        let span = self.look.token.span
        validate_text(read self.bytes[span.begin as usize..span.end as usize], span, mut self.result.diagnostics)
        try self.leaf(NodeKind.Text)
        self.newlines()
        if self.at("{") { try self.declaration_body(BodyContext.Foreign) }
        else { try self.function(self.anchor(), self.pending.len(), BodyContext.ForeignDefinition) }
        try self.finish(NodeKind.Foreign, start, mark, none)
    }
    mut fn declaration(context: BodyContext): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.attributes()
        try self.visibility()
        if context.is(BodyContext.Union) {
            try self.name(false)
            try self.expect(":", "expected ':'")
            try self.type_name(true)
            try self.finish(NodeKind.FieldDeclaration, start, mark, none)
            if !self.consume(",") { try self.end_item("expected a union field separator") }
            return
        }
        if context.is(BodyContext.Foreign) && !(self.at("fn") || self.at("unsafe") || self.at("static")) { try self.fail("expected a foreign function or static declaration", Phase.Parse) }
        if self.at("unsafe") && (self.followed_by("extern") || self.followed_by("interface") || self.followed_by("extend")) { try self.declaration_modifier() }
        if self.at("module") { try self.module_declaration(start, mark) }
        else if self.at("import") { try self.import_declaration(start, mark) }
        else if self.at("extern") { try self.foreign_declaration(start, mark) }
        else if self.at("interface") { try self.interface_declaration(start, mark) }
        else if self.at("extend") { try self.extension(start, mark) }
        else if self.at("enum") { try self.enumeration(start, mark) }
        else if self.at("copy") {
            try self.declaration_modifier()
            if self.at("enum") { try self.enumeration(start, mark) } else if self.at("type") || self.at("union") { try self.product(start, mark) } else { try self.fail("expected a type or enum after 'copy'", Phase.Parse) }
        } else if self.at("type") || self.at("union") {
            if self.at("type") && (context.is(BodyContext.Interface) || context.is(BodyContext.Extension) || context.is(BodyContext.Product)) { try self.associated(start, mark) }
            else { try self.product(start, mark) }
        } else if self.at("alias") {
            self.advance()
            try self.name(false)
            if self.at("<") { try self.generic_parameters() }
            try self.constraints()
            try self.expect("=", "expected '='")
            try self.type_name(true)
            try self.finish(NodeKind.Alias, start, mark, none)
            try self.end_item("expected an alias separator")
        } else if self.at("macro") {
            self.advance()
            try self.name(false)
            if !self.at("{") { try self.fail("expected a macro body", Phase.Parse) }
            try self.token_tree()
            try self.finish(NodeKind.MacroDefinition, start, mark, none)
        } else if self.at("drop") {
            if !context.is(BodyContext.Product) && !context.is(BodyContext.Extension) { try self.fail("destructors belong to product or extension bodies", Phase.Parse) }
            self.advance()
            self.newlines()
            try self.block()
            try self.finish(NodeKind.Destructor, start, mark, none)
        } else if self.at("const") && !self.followed_by("fn") {
            if context.is(BodyContext.Interface) || context.is(BodyContext.Extension) || context.is(BodyContext.Product) { try self.associated(start, mark) }
            else { try self.value_declaration(start, mark, context.is(BodyContext.Foreign)) }
        } else if self.at("static") && !self.followed_by("fn") && !self.followed_by("unsafe") { try self.value_declaration(start, mark, context.is(BodyContext.Foreign)) }
        else if self.at("fn") || self.at("unsafe") || self.at("const") || self.at("async") || self.at("mut") || self.at("take") || self.at("static") || self.at("init") { try self.function(start, mark, context) }
        else if context.is(BodyContext.Product) {
            try self.name(false)
            try self.expect(":", "expected ':'")
            try self.type_name(true)
            try self.finish(NodeKind.FieldDeclaration, start, mark, none)
            if !self.consume(",") { try self.end_item("expected a newline or ';' between fields") }
        } else if self.name_token() {
            try self.name(false)
            while self.consume(".") { try self.name(false) }
            try self.expect("!", "expected a declaration or macro invocation")
            try self.token_tree()
            try self.finish(NodeKind.MacroInvocation, start, mark, none)
            let _ = self.consume(";")
        } else { try self.fail("expected a declaration", Phase.Parse) }
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
    var parser = Parser(read bytes, source, Position(0usize, 0u32), Look(first, 0usize, Position(0usize, 0u32)), 0u32, 0usize, 0usize, 0usize, 0usize, none, new<NodeId>(), new<u8>(), new<usize>(), new<u8>(), Parsed(lexed.tokens, new<SyntaxNode>(), new<NodeId>(), none, lexed.diagnostics))
    if parser.result.diagnostics.error_count == 0 {
        parser.refresh()
        let _ = capture parser.program()
    }
    parser.result
}

@test
fn contextual_extend_names(): Unit {
    let parsed = parse("fn extend() { 0 }\nfn call() { let extend = out; extend.extend(items) }".as_bytes(), 0u32)
    assert(parsed.diagnostics.error_count == 0usize && parsed.root.is_present(), "contextual extend names rejected")
    let declaration = parse("extend Item {}".as_bytes(), 0u32)
    assert(declaration.diagnostics.error_count == 0usize && declaration.root.is_present(), "extension declaration rejected")
    assert(declaration.nodes[declaration.nodes.len() - 2usize].kind.is(NodeKind.Extension), "extension declaration became an ordinary name")
}

@test
fn nonempty_angle_lists(): Unit {
    let parsed = parse("fn empty<>() { 0 }\nfn argument(value: List<>) { 0 }\nfn binder(value: for<> fn(): Unit) { 0 }\nfn nested(value: Outer<Inner<>>) { 0 }".as_bytes(), 0u32)
    assert(parsed.diagnostics.error_count == 4usize, "empty angle list accepted")
    for issue in parsed.diagnostics.issues.as_slice() {
        assert((issue.phase as u32) == (Phase.Parse as u32), "empty angle list has the wrong diagnostic phase")
    }
    let trailing = parse("fn accepted<T,>(value: List<T,>, callback: for<region r,> fn(): Unit) { 0 }".as_bytes(), 0u32)
    assert(trailing.diagnostics.error_count == 0usize && trailing.root.is_present(), "valid trailing comma or empty callable parameters rejected")
}

@test
fn constraint_newline_continuations(): Unit {
    let parsed = parse("fn lines<T, U>() where T: Trait,\nU: Other +\nThird { 0 }\nfn comments<T, U>() where T: Trait, /* comma\n */ U: Other + /* bound\r\n */ Third { 0 }\nfn erased(): any Trait +\nOther { 0 }".as_bytes(), 0u32)
    assert(parsed.diagnostics.error_count == 0usize && parsed.root.is_present(), "constraint continuation rejected")
    var constraints = 0usize
    var compound_bounds = 0usize
    for node in parsed.nodes.as_slice() {
        if node.kind.is(NodeKind.Constraint) { constraints += 1 }
        if node.kind.is(NodeKind.Bounds) && node.children.end - node.children.begin == 2u32 { compound_bounds += 1 }
    }
    assert(constraints == 4usize && compound_bounds == 2usize, "continued constraints lost their structure")
}

@test
fn structured_statement_syntax(): Unit {
    let parsed = parse("fn labeled() { label outer: loop { break } }\nfn tuple() { let (a, b) = (1, 2) }\nfn slice() { let [a, b] = values }\nfn variant() { let Choice.pair(value) = input else { return } }\nfn binding() { let all @ (a, b) = value }\nfn fallback() { let value = input else { return } }\nfn breaking() { loop { break label outer } }\nfn continuing() { loop { continue label outer } }".as_bytes(), 0u32)
    assert(parsed.diagnostics.error_count == 0usize && parsed.root.is_present(), "structured statements rejected")
    let malformed = parse("fn invalid() { continue 2 }".as_bytes(), 0u32)
    assert(malformed.diagnostics.error_count == 1usize, "invalid continue value accepted")
    assert((malformed.diagnostics.issues[0usize].phase as u32) == (Phase.Parse as u32), "invalid continue value became an unsupported feature")
}
