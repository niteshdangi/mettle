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
    Finish(SyntaxNode, InspectionNode, usize),
    GenericSpan(SyntaxNode)
}

type Projector<region r> {
    bytes: read [u8] from r
    tree: read Parsed from r
    result: Inspection
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
            NodeKind.Throw => 22u32, NodeKind.Try => 23u32, NodeKind.Capture => 24u32,
            NodeKind.Tuple => 25u32, NodeKind.Array | NodeKind.Repeat => 26u32,
            NodeKind.Index => 27u32, NodeKind.Range => 28u32, NodeKind.For => 29u32,
            NodeKind.Coalesce => 30u32, NodeKind.Character | NodeKind.Byte => 31u32,
            NodeKind.Text => 32u32, NodeKind.Floating => 34u32, NodeKind.Cast => 35u32,
            NodeKind.Unsafe => 36u32,
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
            if child.kind.is(NodeKind.Arguments) {
                var argument_index = count(child)
                while argument_index != 0usize {
                    argument_index -= 1
                    let argument = self.child(child, argument_index)
                    let value = if argument.kind.is(NodeKind.NamedArgument) { self.child(argument, 1usize) } else { argument }
                    work.push(ExpressionWork.Visit(value))
                }
            } else if child.kind.is(NodeKind.LetElse) {
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
        if node.kind.is(NodeKind.Cast) || (node.kind.is(NodeKind.Block) && node.operation.is_present()) {
            let child = view.children[0usize]
            view.span = self.result.nodes[child].span
        } else if !view.children.is_empty() && (node.kind.is(NodeKind.Unary) || node.kind.is(NodeKind.Binary) ||
            node.kind.is(NodeKind.Coalesce) || node.kind.is(NodeKind.Range) || node.kind.is(NodeKind.Assign) ||
            node.kind.is(NodeKind.Binding) || node.kind.is(NodeKind.Return) || node.kind.is(NodeKind.Break) ||
            node.kind.is(NodeKind.Throw) || node.kind.is(NodeKind.Try) || node.kind.is(NodeKind.Capture)) {
            let last_child = view.children[view.children.len() - 1usize]
            view.span.end = self.result.nodes[last_child].span.end
        }
        let id = self.result.nodes.len()
        self.result.nodes.push(take view)
        id
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
                    while !self.child(item, index).kind.is(NodeKind.Name) {
                        let prefix = self.child(item, index)
                        if prefix.kind.is(NodeKind.Modifier) {
                            let mode = self.spelling(self.operation(prefix))
                            if mode != "unsafe".as_bytes() && mode != "const".as_bytes() { throw InspectionError.Unsupported(item.kind, item.span) }
                        }
                        index += 1
                    }
                    let name = self.name(self.child(item, index))
                    let body = try self.expression(self.child(item, count(item) - 1usize))
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

fn is_type(kind: NodeKind): bool {
    let ordinal = kind as u32
    kind.is(NodeKind.TypeName) || (ordinal >= (NodeKind.TypeGroup as u32) && ordinal <= (NodeKind.TypeEffect as u32))
}

pub fn project(read tree: Parsed, read bytes: [u8]): Inspection throws InspectionError {
    if tree.diagnostics.error_count != 0usize { throw InspectionError.InvalidTree }
    let present(root_id) = tree.root else { throw InspectionError.InvalidTree }
    let root = tree.nodes[root_id.index as usize]
    if !root.kind.is(NodeKind.Module) || root.span.end as usize != bytes.len() { throw InspectionError.InvalidTree }
    var projector = Projector(read bytes, read tree, Inspection(new<InspectionToken>(), new<InspectionNode>(), new<InspectionFunction>(), new<InspectionAlias>(), new<InspectionProduct>()))
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
fn bootstrap_inspection_refuses_incompatible_trees(): Unit {
    let source = "async fn f() { await g() }".as_bytes()
    let valid = parse(source, 0u32)
    let failure(InspectionError.Unsupported(kind, span)) = capture project(read valid, source) else {
        core.panic.panic("async function was silently projected")
    }
    assert(kind.is(NodeKind.Function) && span.begin == 0u32 && span.end == source.len() as u32, "unsupported function lost its location")
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
