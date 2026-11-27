import alloc.hash_map.{ Map, new as map_new }
import alloc.vec.{ List, new }
import mettle_foundation.Span
import super.parser.parse
import super.token.{ Kind, reference_kind }
import super.tree.{ NodeKind, Parsed, SyntaxNode }

pub type InspectionToken { pub kind: u32; pub text: List<u8>; pub span: Span }
pub type InspectionNode {
    pub kind: u32
    pub text: List<u8>
    pub loop_label: List<u8>
    pub span: Span
    pub semicolon: bool
    pub children: List<usize>
}
pub type InspectionFunction { pub name: List<u8>; pub receiver_mode: List<u8>; pub body: usize }
pub type InspectionAlias { pub name: List<u8>; pub target: List<u8> }
pub type InspectionField { pub name: List<u8>; pub annotation: List<u8> }
pub type InspectionProduct { pub name: List<u8>; pub copy_requested: bool; pub fields: List<InspectionField> }
pub type Inspection {
    pub tokens: List<InspectionToken>
    pub nodes: List<InspectionNode>
    pub functions: List<InspectionFunction>
    pub aliases: List<InspectionAlias>
    pub products: List<InspectionProduct>
}
pub copy enum InspectionError { InvalidTree, Unsupported(NodeKind, Span) }

enum ExpressionWork {
    Visit(SyntaxNode),
    ConditionClause(SyntaxNode),
    FinishAwait(SyntaxNode),
    Finish(SyntaxNode, InspectionNode, usize),
    GenericSpan(SyntaxNode)
}

type Projector<region r> {
    bytes: read [u8] from r
    tree: read Parsed from r
    result: Inspection
    await_ids: Map<u32, u32>
}

extend<region r> Projector<region r> {
    fn child(node: SyntaxNode, index: usize): SyntaxNode {
        self.tree.nodes[self.tree.children[node.children.begin as usize + index].index as usize]
    }
    fn spelling(span: Span): List<u8> { self.bytes[span.begin as usize..span.end as usize].to_vec() }
    fn name(node: SyntaxNode): List<u8> {
        let token = self.tree.tokens[node.tokens.begin as usize]
        let trim = if token.kind.is(Kind.QuotedWord) { 1usize } else { 0usize }
        self.bytes[node.span.begin as usize + trim..node.span.end as usize - trim].to_vec()
    }
    fn operation(node: SyntaxNode): Span {
        let index = match node.operation { present(index) => index, none => node.tokens.begin }
        self.tree.tokens[index as usize].span
    }
    fn throws_body(node: SyntaxNode): bool {
        for index in 0usize..count(node) - 1usize {
            if self.child(node, index).kind.is(NodeKind.TypeEffect) { return true }
        }
        false
    }
    fn function_keyword(name: SyntaxNode): Span {
        var index = name.tokens.begin as usize
        loop {
            index -= 1usize
            let token = self.tree.tokens[index]
            if token.kind.is(Kind.Word) { return token.span }
        }
    }
    fn type_name(node: SyntaxNode): List<u8> throws InspectionError {
        match node.kind {
            NodeKind.TypeName => {
                var name = new<u8>()
                for index in 0usize..count(node) {
                    if index != 0usize { name.extend_from_slice("::".as_bytes()) }
                    let segment = self.name(self.child(node, index))
                    name.extend_from_slice(segment.as_slice())
                }
                name
            },
            NodeKind.TypeGroup | NodeKind.TypeApply | NodeKind.TypeSources | NodeKind.TypeFor => try self.type_name(self.child(node, if node.kind.is(NodeKind.TypeFor) { 1usize } else { 0usize })),
            NodeKind.TypePointer => self.spelling(self.operation(node)),
            NodeKind.TypeProjection => {
                var index = count(node) - 1usize
                if self.child(node, index).kind.is(NodeKind.TypeArguments) { index -= 1 }
                self.name(self.child(node, index))
            },
            NodeKind.TypeTuple | NodeKind.TypeSlice | NodeKind.TypeArray | NodeKind.TypeOwner | NodeKind.TypePinned | NodeKind.TypeBorrow | NodeKind.TypeOptional | NodeKind.TypeOutcome | NodeKind.TypeErased | NodeKind.TypeOpaque | NodeKind.TypeCallable => new<u8>(),
            _ => throw InspectionError.Unsupported(node.kind, node.span)
        }
    }
    mut fn expression(node: SyntaxNode): usize throws InspectionError {
        var work = new<ExpressionWork>()
        var completed = new<usize>()
        work.push(ExpressionWork.Visit(node))
        loop {
            let popped = work.pop()
            let present(step) = take popped else { break }
            match take step {
                ExpressionWork.Visit(next) => { try self.schedule_expression(next, completed.len(), mut work) },
                ExpressionWork.ConditionClause(clause) => {
                    let span = self.tree.tokens[clause.tokens.begin as usize].span
                    let view = InspectionNode(39u32, new<u8>(), new<u8>(), span, false, new<usize>())
                    work.push(ExpressionWork.Finish(clause, take view, completed.len()))
                    let value = if clause.kind.is(NodeKind.Condition) { self.child(clause, 1usize) } else { clause }
                    work.push(ExpressionWork.Visit(value))
                },
                ExpressionWork.FinishAwait(awaited) => {
                    let operand = completed.pop().or_panic()
                    let id = self.await_view(awaited, operand)
                    completed.push(take id)
                },
                ExpressionWork.Finish(native, view, mark) => {
                    var finished = take view
                    finished.children.extend_from_slice(read completed.as_slice()[mark..completed.len()])
                    completed.truncate(mark)
                    let id = self.finish_expression(native, take finished)
                    completed.push(take id)
                },
                ExpressionWork.GenericSpan(generic) => {
                    let id = completed[completed.len() - 1usize]
                    self.result.nodes[id].span.end = generic.span.end
                    self.result.nodes[id].semicolon = generic.semicolon
                }
            }
        }
        completed[0usize]
    }
    fn schedule_expression(node: SyntaxNode, mark: usize, mut work: List<ExpressionWork>): Unit throws InspectionError {
        let kind = match node.kind {
            NodeKind.Integer => 0u32, NodeKind.Boolean => 1u32, NodeKind.Unit => 2u32,
            NodeKind.Name | NodeKind.Projection | NodeKind.TypeProjection => 3u32,
            NodeKind.Group => 4u32, NodeKind.Unary => 5u32, NodeKind.Binary => 6u32,
            NodeKind.Call => 7u32, NodeKind.Block => 8u32, NodeKind.If => 9u32,
            NodeKind.Binding => 10u32, NodeKind.Assign => 11u32, NodeKind.Return => 12u32,
            NodeKind.While => 13u32, NodeKind.Loop => 14u32, NodeKind.Break => 15u32,
            NodeKind.Continue => 16u32, NodeKind.Field | NodeKind.OptionalField => 17u32,
            NodeKind.None => 18u32, NodeKind.Present | NodeKind.Success | NodeKind.Failure => 19u32,
            NodeKind.Match => 20u32, NodeKind.Arm => 21u32,
            NodeKind.Throw => 22u32, NodeKind.Try => 23u32, NodeKind.Capture => 24u32,
            NodeKind.Tuple => 25u32, NodeKind.Array | NodeKind.Repeat => 26u32,
            NodeKind.Index => 27u32, NodeKind.Range => 28u32, NodeKind.For => 29u32,
            NodeKind.Coalesce => 30u32, NodeKind.Character | NodeKind.Byte => 31u32,
            NodeKind.Text => 32u32, NodeKind.Closure => 33u32, NodeKind.Floating => 34u32, NodeKind.Cast => 35u32,
            NodeKind.Unsafe => 36u32, NodeKind.Conditions => 40u32,
            NodeKind.Await => {
                work.push(ExpressionWork.FinishAwait(node))
                work.push(ExpressionWork.Visit(self.child(node, 0usize)))
                return
            },
            NodeKind.GenericApply => {
                work.push(ExpressionWork.GenericSpan(node))
                work.push(ExpressionWork.Visit(self.child(node, 0usize)))
                return
            },
            _ => throw InspectionError.Unsupported(node.kind, node.span)
        }
        var view = InspectionNode(kind, new<u8>(), new<u8>(), node.span, node.semicolon, new<usize>())
        var first = 0usize
        var last = count(node)
        match node.kind {
            NodeKind.Name => { view.text = self.name(node) },
            NodeKind.Integer | NodeKind.Floating | NodeKind.Boolean | NodeKind.Character | NodeKind.Byte | NodeKind.Text => { view.text = self.spelling(node.span) },
            NodeKind.Unary | NodeKind.Binary | NodeKind.Coalesce | NodeKind.Assign | NodeKind.Present | NodeKind.Success | NodeKind.Failure => { view.text = self.spelling(self.operation(node)) },
            NodeKind.Match => {
                view.text = if node.operation.is_present() { self.spelling(self.operation(node)) } else { "read".as_bytes().to_vec() }
            },
            NodeKind.Arm | NodeKind.Conditions => {
                view.span = self.tree.tokens[node.tokens.begin as usize].span
                if node.kind.is(NodeKind.Arm) { first = 1usize }
            },
            NodeKind.Closure => {
                view.span = self.tree.tokens[node.tokens.begin as usize].span
                first = last - 1usize
            },
            NodeKind.Range => {
                let operation = self.operation(node)
                view.text = self.spelling(operation)
            },
            NodeKind.Cast => { last = 1usize },
            NodeKind.Field | NodeKind.OptionalField => {
                view.text = self.name(self.child(node, 1usize))
                last = 1usize
                let base = self.child(node, 0usize)
                if node.kind.is(NodeKind.Field) && base.kind.is(NodeKind.GenericApply) {
                    let owner = self.child(base, 0usize)
                    if owner.kind.is(NodeKind.Name) {
                        var qualified = self.name(owner)
                        qualified.extend_from_slice("::".as_bytes())
                        qualified.extend_from_slice(view.text.as_slice())
                        view.kind = 3u32
                        view.text = take qualified
                        last = 0usize
                    }
                }
            },
            NodeKind.Projection | NodeKind.TypeProjection => {
                let subject = self.child(node, 0usize)
                if (node.kind.is(NodeKind.Projection) && !subject.kind.is(NodeKind.Name) &&
                    !subject.kind.is(NodeKind.Field) && !subject.kind.is(NodeKind.GenericApply)) ||
                    (node.kind.is(NodeKind.TypeProjection) && !subject.kind.is(NodeKind.TypePointer) &&
                    !subject.kind.is(NodeKind.TypeArray) && !subject.kind.is(NodeKind.TypeSlice)) {
                    throw InspectionError.Unsupported(node.kind, node.span)
                }
                if self.child(node, last - 1usize).kind.is(NodeKind.TypeArguments) { last -= 1 }
                view.text = self.name(self.child(node, last - 1usize))
                last = 0usize
            },
            NodeKind.Binding => {
                let pattern = self.child(node, 0usize)
                view.text = if pattern.kind.is(NodeKind.Name) || pattern.kind.is(NodeKind.PatternWildcard) {
                    self.name(pattern)
                } else { "<pattern>".as_bytes().to_vec() }
                first = 1usize
                if first < last {
                    let next = self.child(node, first)
                    if next.kind.is(NodeKind.LetElse) { throw InspectionError.Unsupported(node.kind, node.span) }
                    if is_type(next.kind) { first += 1 }
                }
                if first == last { view.span.end = self.operation(node).end }
            },
            NodeKind.While | NodeKind.Loop | NodeKind.For | NodeKind.Break | NodeKind.Continue => {
                if first < last {
                    let loop_label = self.child(node, first)
                    if loop_label.kind.is(NodeKind.Label) { view.loop_label = self.name(self.child(loop_label, 0usize)); first += 1 }
                }
                if node.kind.is(NodeKind.For) { first += 1 }
            },
            _ => {}
        }
        work.push(ExpressionWork.Finish(node, take view, mark))
        var index = last
        while index > first {
            index -= 1
            let child = self.child(node, index)
            if node.kind.is(NodeKind.Conditions) {
                work.push(ExpressionWork.ConditionClause(child))
            } else if child.kind.is(NodeKind.Arguments) {
                var argument_index = count(child)
                while argument_index != 0usize {
                    argument_index -= 1
                    let argument = self.child(child, argument_index)
                    let value = if argument.kind.is(NodeKind.NamedArgument) { self.child(argument, 1usize) } else { argument }
                    work.push(ExpressionWork.Visit(value))
                }
            } else if child.kind.is(NodeKind.LetElse) || child.kind.is(NodeKind.Guard) {
                work.push(ExpressionWork.Visit(self.child(child, 0usize)))
            } else {
                let value = if child.kind.is(NodeKind.Conditions) && count(child) == 1usize {
                    let condition = self.child(child, 0usize)
                    self.child(condition, count(condition) - 1usize)
                } else { child }
                work.push(ExpressionWork.Visit(value))
            }
        }
    }
    mut fn finish_expression(node: SyntaxNode, take view: InspectionNode): usize {
        var view = take view
        if view.kind == 21u32 || view.kind == 39u32 || view.kind == 40u32 || node.kind.is(NodeKind.Closure) {
            for child in view.children.as_slice() {
                let end = self.result.nodes[child].span.end
                if view.span.end < end { view.span.end = end }
            }
        } else if node.kind.is(NodeKind.Cast) || (node.kind.is(NodeKind.Block) && node.operation.is_present()) {
            let child = view.children[0usize]
            view.span = self.result.nodes[child].span
        } else if !view.children.is_empty() && (node.kind.is(NodeKind.Unary) || node.kind.is(NodeKind.Binary) ||
            node.kind.is(NodeKind.Coalesce) || node.kind.is(NodeKind.Range) || node.kind.is(NodeKind.Assign) ||
            node.kind.is(NodeKind.Binding) || node.kind.is(NodeKind.Return) || node.kind.is(NodeKind.Break) ||
            node.kind.is(NodeKind.Throw) || node.kind.is(NodeKind.Try) || node.kind.is(NodeKind.Capture)) {
            let last_child = view.children[view.children.len() - 1usize]
            view.span.end = self.result.nodes[last_child].span.end
        }
        if node.kind.is(NodeKind.Closure) && self.child(node, 0usize).kind.is(NodeKind.Modifier) {
            let prefix = self.child(node, 0usize)
            if self.spelling(self.operation(prefix)) == "async".as_bytes() {
                let body = view.children[0usize]
                if node.operation.is_none() {
                    let call = self.coroutine(self.operation(prefix), body, false)
                    self.result.nodes[call].semicolon = view.semicolon
                    return call
                }
                let wrapped = self.coroutine_block(self.operation(prefix), body, self.throws_body(node))
                view.children[0usize] = wrapped
            }
        }
        let id = self.result.nodes.len()
        self.result.nodes.push(take view)
        id
    }
    mut fn synthetic(kind: u32, span: Span, read text: [u8], read children: [usize]): usize {
        let id = self.result.nodes.len()
        self.result.nodes.push(InspectionNode(kind, text.to_vec(), new<u8>(), span, false, children.to_vec()))
        id
    }
    mut fn coroutine(span: Span, body: usize, throwing: bool): usize {
        let full_span = Span(span.source, span.begin, self.result.nodes[body].span.end)
        let callee = if throwing { "core::future::throwing_coroutine" } else { "core::future::coroutine" }
        let name = self.synthetic(3u32, span, callee.as_bytes(), [0usize; 0])
        let closure = self.synthetic(33u32, full_span, "coroutine".as_bytes(), [body])
        self.synthetic(7u32, full_span, "".as_bytes(), [name, closure])
    }
    mut fn coroutine_block(span: Span, body: usize, throwing: bool): usize {
        let body_span = self.result.nodes[body].span
        let call = self.coroutine(span, body, throwing)
        self.synthetic(8u32, body_span, "".as_bytes(), [call])
    }
    mut fn await_view(node: SyntaxNode, operand: usize): usize {
        let span = self.operation(node)
        let empty = "".as_bytes()
        let no_children = [0usize; 0]
        let id = self.await_ids[span.begin]
        let pending = await_name("<await-".as_bytes(), id)
        let ready = await_name("<ready-".as_bytes(), id)
        var full_span = span
        let operand_end = self.result.nodes[operand].span.end
        if full_span.end < operand_end { full_span.end = operand_end }
        let binding = self.synthetic(10u32, full_span, pending.as_slice(), [operand])
        let poll_name = self.synthetic(3u32, span, "core::future::poll_await".as_bytes(), no_children)
        let place_name = self.synthetic(3u32, span, pending.as_slice(), no_children)
        let place = self.synthetic(5u32, span, "mut".as_bytes(), [place_name])
        let context_name = self.synthetic(3u32, span, "core::intrinsics::coroutine_context".as_bytes(), no_children)
        let context = self.synthetic(7u32, span, empty, [context_name])
        let call = self.synthetic(7u32, span, empty, [poll_name, place, context])
        let guarded = self.synthetic(36u32, span, empty, [call])
        let ready_name = self.synthetic(3u32, span, ready.as_slice(), no_children)
        let leave = self.synthetic(15u32, span, empty, [ready_name])
        let ready_body = self.synthetic(8u32, span, empty, [leave])
        let present_arm = self.synthetic(21u32, span, empty, [ready_body])
        let suspend_name = self.synthetic(3u32, span, "core::intrinsics::coroutine_suspend".as_bytes(), no_children)
        let suspend = self.synthetic(7u32, span, empty, [suspend_name])
        let absent_arm = self.synthetic(21u32, span, empty, [suspend])
        let poll = self.synthetic(20u32, span, "take".as_bytes(), [guarded, present_arm, absent_arm])
        let iteration = self.synthetic(8u32, span, empty, [poll])
        let repeat = self.synthetic(14u32, span, empty, [iteration])
        let result = self.synthetic(8u32, full_span, empty, [binding, repeat])
        self.result.nodes[result].semicolon = node.semicolon
        result
    }
    mut fn items(node: SyntaxNode): Unit throws InspectionError {
        for index in 0usize..count(node) {
            let item = self.child(node, index)
            match item.kind {
                NodeKind.ModuleDeclaration => {
                    let last = self.child(item, count(item) - 1usize)
                    if last.kind.is(NodeKind.ModuleBody) { try self.items(last) }
                },
                NodeKind.Import | NodeKind.Constant | NodeKind.Static => {},
                NodeKind.Function => {
                    var index = 0usize
                    var asynchronous = false
                    while !self.child(item, index).kind.is(NodeKind.Name) {
                        let prefix = self.child(item, index)
                        if prefix.kind.is(NodeKind.Modifier) {
                            let mode = self.spelling(self.operation(prefix))
                            if mode == "async".as_bytes() && prefix.span.end == self.operation(prefix).end { asynchronous = true }
                            else if mode != "unsafe".as_bytes() && mode != "const".as_bytes() { throw InspectionError.Unsupported(item.kind, item.span) }
                        }
                        index += 1
                    }
                    let name_node = self.child(item, index)
                    let name = self.name(name_node)
                    var body = try self.expression(self.child(item, count(item) - 1usize))
                    if asynchronous {
                        var span = self.function_keyword(name_node)
                        span.end = self.result.nodes[body].span.end
                        body = self.coroutine_block(span, body, self.throws_body(item))
                    }
                    self.result.functions.push(InspectionFunction(take name, new<u8>(), body))
                },
                NodeKind.Alias => {
                    let name = self.item_name(item)
                    let target = try self.type_name(self.child(item, count(item) - 1usize))
                    self.result.aliases.push(InspectionAlias(take name, take target))
                },
                NodeKind.Product | NodeKind.Union => {
                    let name = self.item_name(item)
                    var copy_requested = false
                    let members = self.child(item, count(item) - 1usize)
                    for child in 0usize..count(item) - 1usize {
                        let prefix = self.child(item, child)
                        if prefix.kind.is(NodeKind.Modifier) && self.spelling(self.operation(prefix)) == "copy".as_bytes() { copy_requested = true }
                    }
                    var fields = new<InspectionField>()
                    for child in 0usize..count(members) {
                        let field = self.child(members, child)
                        if !field.kind.is(NodeKind.FieldDeclaration) { throw InspectionError.Unsupported(field.kind, field.span) }
                        let field_name = self.item_name(field)
                        let annotation = try self.type_name(self.child(field, count(field) - 1usize))
                        fields.push(InspectionField(take field_name, take annotation))
                    }
                    self.result.products.push(InspectionProduct(take name, copy_requested, take fields))
                },
                _ => { throw InspectionError.Unsupported(item.kind, item.span) }
            }
        }
    }
    fn item_name(node: SyntaxNode): List<u8> {
        var index = 0usize
        while !self.child(node, index).kind.is(NodeKind.Name) { index += 1 }
        self.name(self.child(node, index))
    }
}

fn count(node: SyntaxNode): usize { (node.children.end - node.children.begin) as usize }

fn await_name(read prefix: [u8], id: u32): List<u8> {
    var digits = [0u8; 10]
    var index = digits.len()
    var remaining = id
    loop {
        index -= 1usize
        digits[index] = b'0' + (remaining % 10u32) as u8
        remaining /= 10u32
        if remaining == 0u32 { break }
    }
    var name = prefix.to_vec()
    name.extend_from_slice(digits[index..digits.len()])
    name.push(b'>')
    name
}

fn is_type(kind: NodeKind): bool {
    let ordinal = kind as u32
    kind.is(NodeKind.TypeName) || (ordinal >= (NodeKind.TypeGroup as u32) && ordinal <= (NodeKind.TypeEffect as u32))
}

pub fn project(read tree: Parsed, read bytes: [u8]): Inspection throws InspectionError {
    if tree.diagnostics.error_count != 0usize { throw InspectionError.InvalidTree }
    let present(root_id) = tree.root else { throw InspectionError.InvalidTree }
    let root = tree.nodes[root_id.index as usize]
    if !root.kind.is(NodeKind.Module) || root.span.end as usize != bytes.len() { throw InspectionError.InvalidTree }
    var await_ids = map_new<u32, u32>()
    for node in tree.nodes.as_slice() {
        if node.kind.is(NodeKind.Await) {
            let id = await_ids.len() as u32
            let _ = await_ids.insert(node.span.begin, id)
        }
    }
    var projector = Projector(read bytes, read tree, Inspection(new<InspectionToken>(), new<InspectionNode>(), new<InspectionFunction>(), new<InspectionAlias>(), new<InspectionProduct>()), take await_ids)
    for token in tree.tokens.as_slice() {
        if token.kind.is(Kind.FormatPiece) { throw InspectionError.Unsupported(NodeKind.Interpolation, token.span) }
        let text = projector.spelling(token.span)
        projector.result.tokens.push(InspectionToken(reference_kind(token.kind), take text, token.span))
    }
    try projector.items(root)
    projector.result
}

@test
fn bootstrap_inspection_shapes(): Unit {
    let bytes = "copy type P { value: ptr<read i32> }\nalias A = x.Y<i32>\nfn f() { var x: i32; x += 1 as i32; thing<T>.member<U>(arg: x); x .. }\n".as_bytes()
    let tree = parse(bytes, 0u32)
    let projected = capture project(read tree, bytes)
    let success(view) = take projected else { core.panic.panic("bootstrap projection rejected core grammar") }
    assert(view.products.len() == 1usize && view.products[0usize].copy_requested &&
        view.products[0usize].fields[0usize].annotation == "read".as_bytes(), "pointer field inspection changed")
    assert(view.aliases[0usize].name == "A".as_bytes() && view.aliases[0usize].target == "x::Y".as_bytes(), "alias path inspection changed")
    let body = read view.nodes[view.functions[0usize].body]
    let binding = read view.nodes[body.children[0usize]]
    let assignment = read view.nodes[body.children[1usize]]
    let cast = read view.nodes[assignment.children[1usize]]
    let call = read view.nodes[body.children[2usize]]
    let callee = read view.nodes[call.children[0usize]]
    let range = read view.nodes[body.children[3usize]]
    assert(binding.kind == 10u32 && binding.text == "x".as_bytes() && binding.semicolon &&
        binding.span.end - binding.span.begin == 3u32 && binding.children.is_empty(), "uninitialized binding inspection changed")
    assert(assignment.kind == 11u32 && assignment.text == "+=".as_bytes() &&
        cast.kind == 35u32 && cast.span.end - cast.span.begin == 1u32 && assignment.span.end == cast.span.end, "cast or assignment span includes the cast target")
    assert(call.kind == 7u32 && call.children.len() == 2usize && callee.kind == 3u32 &&
        callee.text == "thing::member".as_bytes() && callee.children.is_empty(), "qualified generic callee or named argument inspection changed")
    assert(range.kind == 28u32 && range.text == "..".as_bytes() && range.span.end - range.span.begin == 1u32 && !range.semicolon, "open-ended range span includes its operator")
}

@test
fn bootstrap_inspection_match(): Unit {
    let bytes = "fn f() { match x { -3..=0 | 2 if ready => y as i32, _ => 0 }; match mut x { _ => 1 }; match take x {} }".as_bytes()
    let tree = parse(bytes, 0u32)
    let success(view) = capture project(read tree, bytes) else { core.panic.panic("match projection failed") }
    let body = read view.nodes[view.functions[0usize].body]
    let first = read view.nodes[body.children[0usize]]
    let guarded = read view.nodes[first.children[1usize]]
    let unguarded = read view.nodes[first.children[2usize]]
    assert(first.kind == 20u32 && first.text == "read".as_bytes() && first.semicolon &&
        first.span.begin == 9u32 && first.span.end == 60u32 && first.children.len() == 3usize &&
        view.nodes[first.children[0usize]].text == "x".as_bytes(), "default match mode, span, or scrutinee changed")
    assert(guarded.kind == 21u32 && guarded.span.begin == 19u32 && guarded.span.end == 43u32 &&
        guarded.children.len() == 2usize && view.nodes[guarded.children[0usize]].text == "ready".as_bytes() &&
        view.nodes[guarded.children[1usize]].kind == 35u32, "guarded arm did not omit its pattern or preserve guard/value order")
    assert(unguarded.kind == 21u32 && unguarded.children.len() == 1usize &&
        view.nodes[unguarded.children[0usize]].text == "0".as_bytes(), "unguarded arm lost its value")
    let mutable = read view.nodes[body.children[1usize]]
    let owned = read view.nodes[body.children[2usize]]
    assert(mutable.text == "mut".as_bytes() && owned.text == "take".as_bytes() &&
        owned.children.len() == 1usize, "explicit match modes or empty arms changed")
}

@test
fn bootstrap_inspection_condition_chains(): Unit {
    let bytes = "fn f() { if a, b, c { 1 } else if d { 2 }; label outer: while check(), y as bool { break label outer } }".as_bytes()
    let tree = parse(bytes, 0u32)
    let success(view) = capture project(read tree, bytes) else { core.panic.panic("condition chain projection failed") }
    let body = read view.nodes[view.functions[0usize].body]
    let branch = read view.nodes[body.children[0usize]]
    let chain = read view.nodes[branch.children[0usize]]
    assert(branch.kind == 9u32 && branch.children.len() == 3usize && chain.kind == 40u32 &&
        chain.span.begin == 12u32 && chain.span.end == 19u32 && chain.children.len() == 3usize, "if chain lost its structure or span")
    let expected = "abc".as_bytes()
    for index in 0usize..3usize {
        let clause = read view.nodes[chain.children[index]]
        assert(clause.kind == 39u32 && clause.children.len() == 1usize &&
            view.nodes[clause.children[0usize]].text == expected[index..index + 1usize], "if clauses lost their wrapper or order")
    }
    let alternative = read view.nodes[branch.children[2usize]]
    assert(alternative.kind == 9u32 && view.nodes[alternative.children[0usize]].text == "d".as_bytes(),
        "single condition was incorrectly wrapped")
    let repeat = read view.nodes[body.children[1usize]]
    let loop_chain = read view.nodes[repeat.children[0usize]]
    let call = read view.nodes[loop_chain.children[0usize]]
    let cast = read view.nodes[loop_chain.children[1usize]]
    assert(repeat.kind == 13u32 && repeat.loop_label == "outer".as_bytes() && loop_chain.kind == 40u32 &&
        loop_chain.span.begin == 62u32 && loop_chain.span.end == 72u32 && loop_chain.children.len() == 2usize &&
        call.span.end == 69u32 && cast.span.begin == 71u32 && cast.span.end == 72u32, "while chain lost its label or bootstrap clause spans")
}

@test
fn bootstrap_inspection_async_await(): Unit {
    let bytes = "const skip: T = async { await a() }\nasync fn f(x: T = async { await b() }) throws E => await await c()".as_bytes()
    let tree = parse(bytes, 0u32)
    let success(view) = capture project(read tree, bytes) else { core.panic.panic("async projection failed") }
    let body = read view.nodes[view.functions[0usize].body]
    let call = read view.nodes[body.children[0usize]]
    let callee = read view.nodes[call.children[0usize]]
    let closure = read view.nodes[call.children[1usize]]
    assert(body.kind == 8u32 && body.span.begin == 87u32 && body.span.end == 102u32 &&
        call.kind == 7u32 && callee.text == "core::future::throwing_coroutine".as_bytes() &&
        callee.span.begin == 42u32 && callee.span.end == 102u32 &&
        closure.kind == 33u32 && closure.text == "coroutine".as_bytes(), "throwing async function lost its coroutine shape or spans")
    let original = read view.nodes[closure.children[0usize]]
    let waiting = read view.nodes[original.children[0usize]]
    let outer = read view.nodes[waiting.children[0usize]]
    let inner = read view.nodes[view.nodes[outer.children[0usize]].children[0usize]]
    assert(outer.text == "<await-3>".as_bytes() && inner.text == "<await-2>".as_bytes(),
        "nested awaits did not follow parsed order after the omitted constant and default")
    let repeat = read view.nodes[waiting.children[1usize]]
    let poll = read view.nodes[view.nodes[repeat.children[0usize]].children[0usize]]
    let guarded = read view.nodes[poll.children[0usize]]
    assert(repeat.kind == 14u32 && repeat.span.begin == 87u32 && repeat.span.end == 92u32 &&
        poll.kind == 20u32 && poll.text == "take".as_bytes() && poll.children.len() == 3usize &&
        guarded.kind == 36u32, "await polling tree lost its keyword span or ordered branches")
}

@test
fn bootstrap_inspection_closures(): Unit {
    let bytes = "fn f() { take fn(x: i32) => x as i64; async { await a() }; async take fn() throws E { await b() } }".as_bytes()
    let tree = parse(bytes, 0u32)
    let success(view) = capture project(read tree, bytes) else { core.panic.panic("closure projection failed") }
    let body = read view.nodes[view.functions[0usize].body]
    let plain = read view.nodes[body.children[0usize]]
    let arrow = read view.nodes[plain.children[0usize]]
    assert(plain.kind == 33u32 && plain.text.is_empty() && plain.semicolon &&
        plain.span.begin == 9u32 && plain.span.end == 29u32 &&
        arrow.kind == 8u32 && arrow.span.begin == 28u32 && arrow.span.end == 29u32, "closure arrow body includes syntax-only metadata or cast type")
    let bare = read view.nodes[body.children[1usize]]
    let bare_callee = read view.nodes[bare.children[0usize]]
    assert(bare.kind == 7u32 && bare.semicolon && bare.span.end == 57u32 &&
        bare_callee.text == "core::future::coroutine".as_bytes() &&
        bare_callee.span.begin == 38u32 && bare_callee.span.end == 43u32, "async block did not project directly to its coroutine call")
    let asynchronous = read view.nodes[body.children[2usize]]
    let wrapper = read view.nodes[asynchronous.children[0usize]]
    let call = read view.nodes[wrapper.children[0usize]]
    let callee = read view.nodes[call.children[0usize]]
    assert(asynchronous.kind == 33u32 && asynchronous.text.is_empty() &&
        wrapper.span.begin == 84u32 && wrapper.span.end == 97u32 &&
        callee.text == "core::future::throwing_coroutine".as_bytes() &&
        callee.span.begin == 59u32 && callee.span.end == 64u32, "async closure lost its outer closure or throwing body wrapper")
}

@test
fn bootstrap_inspection_refuses_incompatible_trees(): Unit {
    let source = "fn f() { item!() }".as_bytes()
    let valid = parse(source, 0u32)
    let failure(InspectionError.Unsupported(kind, span)) = capture project(read valid, source) else {
        core.panic.panic("macro invocation was silently projected")
    }
    assert(kind.is(NodeKind.MacroInvocation) && span.begin == 9u32 && span.end == 16u32, "unsupported macro invocation lost its location")
    let broken = "fn f() { 1 + }".as_bytes()
    let recovered = parse(broken, 0u32)
    let failure(InspectionError.InvalidTree) = capture project(read recovered, broken) else {
        core.panic.panic("recovered syntax was silently projected")
    }
}

@test
fn bootstrap_inspection_long_flat_binary_chain(): Unit {
    var source = new<u8>()
    source.extend_from_slice("fn f() { 0".as_bytes())
    for _ in 0usize..300usize { source.extend_from_slice(" + 1".as_bytes()) }
    source.extend_from_slice(" }".as_bytes())
    let bytes = source.as_slice()
    let tree = parse(bytes, 0u32)
    assert(tree.diagnostics.error_count == 0usize, "native parser rejected a flat binary chain")
    let projected = capture project(read tree, bytes)
    let success(view) = take projected else { core.panic.panic("inspection rejected a flat binary chain") }
    let body = read view.nodes[view.functions[0usize].body]
    var left = body.children[0usize]
    let outer = read view.nodes[left]
    assert(outer.span.begin == 9u32 && outer.span.end as usize == bytes.len() - 2usize, "flat chain lost its source span")
    for _ in 0usize..300usize {
        let binary = read view.nodes[left]
        let right = read view.nodes[binary.children[1usize]]
        assert(binary.kind == 6u32 && binary.text == "+".as_bytes() && right.kind == 0u32 &&
            right.text == "1".as_bytes(), "flat chain lost its left association or operands")
        left = binary.children[0usize]
    }
    assert(view.nodes[left].text == "0".as_bytes(), "flat chain lost its first operand")
}
