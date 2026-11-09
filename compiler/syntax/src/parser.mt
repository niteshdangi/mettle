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
copy type Checkpoint { pending: usize; nodes: usize; children: usize; depth: usize; suppressed: usize }

type Parser<region r> {
    bytes: read [u8] from r
    source: u32
    position: Position
    look: Look
    last_end: u32
    last_token: usize
    depth: usize
    suppressed: usize
    pending: List<NodeId>
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
                    self.look = Look(token, position.token, Position(next, 0u32))
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
    fn checkpoint(): Checkpoint { Checkpoint(self.pending.len(), self.result.nodes.len(), self.result.children.len(), self.depth, self.suppressed) }
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
        if !(self.look.token.kind.is(Kind.QuotedWord) || (self.look.token.kind.is(Kind.Word) && (!self.reserved() || (discard && self.at("_"))))) {
            try self.fail("expected a name", Phase.Parse)
        }
        let start = self.anchor()
        let mark = self.pending.len()
        self.advance()
        try self.finish(NodeKind.Name, start, mark, none)
    }
    mut fn type_name(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        if self.at("[") || self.at("(") || self.at("read") || self.at("mut") || self.at("heap") || self.at("shared") || self.at("weak") || self.at("local") || self.at("pinned") || self.at("any") || self.at("some") || self.at("for") {
            try self.fail("this type form is not implemented in the Mettle parser yet", Phase.Feature)
        }
        try self.name(false)
        while self.consume(".") { try self.name(false) }
        if self.at("<") || self.at("?") || self.at("from") { try self.fail("this type form is not implemented in the Mettle parser yet", Phase.Feature) }
        try self.finish(NodeKind.TypeName, start, mark, none)
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
    fn named_application(): bool {
        let kind = self.result.nodes[self.pending[self.pending.len() - 1].index as usize].kind
        if !kind.is(NodeKind.Name) && !kind.is(NodeKind.Field) { return false }
        var index = self.look.index + 1
        var named = false
        var trailing = false
        var depth = 1usize
        while index < self.result.tokens.len() {
            let token = self.result.tokens[index]
            if token.kind.is(Kind.Space) || token.kind.is(Kind.Comment) || token.kind.is(Kind.Newline) { index += 1; continue }
            if (token.kind.is(Kind.Word) || token.kind.is(Kind.QuotedWord)) && !named { named = true; trailing = false }
            else if self.brace(index, b'<') && named { depth += 1; named = false; trailing = false }
            else if self.brace(index, b'.') && named { named = false; trailing = false }
            else if self.brace(index, b',') && named { named = false; trailing = true }
            else if token.kind.is(Kind.Symbol) && (named || trailing) && self.bytes[token.span.begin as usize] == b'>' {
                let width = (token.span.end - token.span.begin) as usize
                if width > 2 || (width == 2 && self.bytes[token.span.begin as usize + 1] != b'>') || width > depth { return false }
                depth -= width
                if depth == 0 {
                    index += 1
                    while index < self.result.tokens.len() && (self.result.tokens[index].kind.is(Kind.Space) || self.result.tokens[index].kind.is(Kind.Comment)) { index += 1 }
                    return index < self.result.tokens.len() && self.brace(index, b'(')
                }
                named = true
                trailing = false
            } else { return false }
            index += 1
        }
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
            let level = self.level()
            if ranged && level == 1 { try self.fail("ranges do not chain", Phase.Parse) }
            if level == 5 && compared { try self.fail("comparisons do not chain", Phase.Parse) }
            if level == 5 { compared = true }
            let operation = self.look.index as u32
            let inclusive = self.at("..=")
            self.advance()
            if level == 12 {
                try self.type_name()
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
                if self.look.token.kind.is(Kind.Integer) {
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
            } else if self.at("<") && self.named_application() { try self.fail("generic applications are not implemented in the Mettle parser yet", Phase.Feature) }
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
            if self.consume(":") { typed = true; try self.type_name() }
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
            } else if open == 0 && (self.look.token.kind.is(Kind.Newline) || self.at(";") || self.at("fn")) { break }
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
        self.suppressed = 0usize
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
        self.refresh()
        try self.finish(NodeKind.Block, start, mark, none)
        self.depth -= 1
    }
    mut fn function(): Unit throws Failure {
        let start = self.anchor()
        let mark = self.pending.len()
        try self.expect("fn", "expected a declaration")
        try self.name(false)
        if self.at("<") { try self.fail("generic declarations are not implemented in the Mettle parser yet", Phase.Feature) }
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
            try self.name(false)
            try self.expect(":", "expected ':'")
            try self.type_name()
            if self.at("=") { try self.fail("default parameters are not implemented in the Mettle parser yet", Phase.Feature) }
            try self.finish(NodeKind.Parameter, parameter, child_mark, mode)
            if !self.consume(",") { break }
        }
        try self.close(")", "expected ')'")
        try self.finish(NodeKind.Parameters, parameters, parameter_mark, none)
        if self.consume(":") { try self.type_name() }
        if self.at("throws") { try self.fail("effect declarations are not implemented in the Mettle parser yet", Phase.Feature) }
        self.newlines()
        try self.block()
        try self.finish(NodeKind.Function, start, mark, none)
    }
    mut fn program(): Unit throws Failure {
        let start = Anchor(0usize, 0u32)
        self.separators()
        while !self.look.token.kind.is(Kind.End) {
            let before = self.anchor()
            let saved = self.checkpoint()
            var outcome = capture {
                if self.at("fn") { try self.function() }
                else if self.at("type") || self.at("copy") || self.at("enum") || self.at("union") || self.at("extend") || self.at("alias") || self.at("interface") || self.at("module") || self.at("import") || self.at("const") || self.at("static") || self.at("pub") || self.at("extern") || self.at("unsafe") || self.at("async") || self.at("macro") || self.at("@") { try self.fail("this declaration is not implemented in the Mettle parser yet", Phase.Feature) }
                else { try self.fail("expected a declaration", Phase.Parse) }
            }
            if outcome.is_failure() { try self.recover(before, saved, false) }
            self.separators()
        }
        self.last_end = self.bytes.len() as u32
        self.last_token = self.result.tokens.len() - 1
        try self.finish(NodeKind.Module, start, 0usize, none)
        self.result.root = present(self.pending[0usize])
    }
}

pub fn parse(read bytes: [u8], source: u32): Parsed {
    let lexed = tokenize(bytes, source)
    let first = lexed.tokens[0usize]
    var parser = Parser(read bytes, source, Position(0usize, 0u32), Look(first, 0usize, Position(0usize, 0u32)), 0u32, 0usize, 0usize, 0usize, new<NodeId>(), Parsed(lexed.tokens, new<SyntaxNode>(), new<NodeId>(), none, lexed.diagnostics))
    if parser.result.diagnostics.error_count == 0 {
        parser.refresh()
        let _ = capture parser.program()
    }
    parser.result
}
