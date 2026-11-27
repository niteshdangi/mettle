import alloc.hash_map.Map
import alloc.vec.List
import core.text.Text
import mettle_foundation.Span
import mettle_syntax.{ NodeId, NodeKind, Parsed, SyntaxNode }
import mettle_types.Scalar

pub copy enum CheckPhase { Feature, Lex, Name, Type }

pub copy type CheckError {
    pub phase: CheckPhase
    pub span: Span
    pub message: read Text from static
}

pub copy type Function {
    pub declaration: NodeId
    pub body: NodeId
    pub result: Scalar
}

pub copy type Expression {
    pub scalar: Scalar
    pub callee: usize?
}

pub type CheckedModule {
    pub functions: List<Function>
    pub expressions: List<Expression?>
    pub entry: usize
}

fn unsupported(span: Span): CheckError {
    CheckError(CheckPhase.Feature, span, "native semantic checking does not support this construct yet")
}

fn node(read parsed: Parsed, id: NodeId): SyntaxNode {
    parsed.nodes[id.index as usize]
}

fn child(read parsed: Parsed, parent: SyntaxNode, index: u32): NodeId {
    parsed.children[(parent.children.begin + index) as usize]
}

fn name(read bytes: [u8], read parsed: Parsed, item: SyntaxNode): List<u8> throws CheckError {
    let present(identifier) = parsed.tokens[item.tokens.begin as usize].identifier(bytes) else {
        throw unsupported(item.span)
    }
    identifier
}

fn signature(read bytes: [u8], read parsed: Parsed, id: NodeId): (List<u8>, Function) throws CheckError {
    let item = node(parsed, id)
    if !item.kind.is(NodeKind.Function) { throw unsupported(item.span) }
    let first = node(parsed, child(parsed, item, 0))
    let offset = if first.kind.is(NodeKind.Visibility) { 1u32 } else { 0u32 }
    if item.children.end - item.children.begin != offset + 4u32 { throw unsupported(item.span) }
    let identifier = node(parsed, child(parsed, item, offset))
    let parameters = node(parsed, child(parsed, item, offset + 1u32))
    let annotation = node(parsed, child(parsed, item, offset + 2u32))
    let body = child(parsed, item, offset + 3u32)
    if (!identifier.kind.is(NodeKind.Name) || !parameters.kind.is(NodeKind.Parameters)
        || parameters.children.begin != parameters.children.end || !annotation.kind.is(NodeKind.TypeName)
        || annotation.children.end - annotation.children.begin != 1u32 || !node(parsed, body).kind.is(NodeKind.Block)) {
        throw unsupported(item.span)
    }
    let type_name = read bytes[annotation.span.begin as usize..annotation.span.end as usize]
    let scalar = if type_name == "i32".as_bytes() { Scalar.I32 }
        else if type_name == "bool".as_bytes() { Scalar.Bool }
        else if type_name == "Unit".as_bytes() { Scalar.Unit }
        else { throw unsupported(annotation.span) }
    (try name(bytes, parsed, identifier), Function(id, body, scalar))
}

fn integer(read bytes: [u8], span: Span): Scalar throws CheckError {
    var magnitude = 0u32
    var needs_digit = true
    var overflow = false
    for byte in bytes {
        if byte == b'_' {
            if needs_digit {
                throw CheckError(CheckPhase.Lex, span, "numeric separators must occur between digits")
            }
            needs_digit = true
            continue
        }
        if byte < b'0' || byte > b'9' { throw unsupported(span) }
        let digit = (byte - b'0') as u32
        if magnitude > (2147483647u32 - digit) / 10u32 { overflow = true }
        if !overflow {
            magnitude = magnitude * 10u32 + digit
        }
        needs_digit = false
    }
    if needs_digit {
        throw CheckError(CheckPhase.Lex, span, "numeric separators must occur between digits")
    }
    if overflow { throw CheckError(CheckPhase.Type, span, "integer literal is outside the i32 range") }
    Scalar.I32
}

fn value(read expressions: List<Expression?>, id: NodeId, span: Span): Expression throws CheckError {
    let present(result) = expressions[id.index as usize] else { throw unsupported(span) }
    result
}

fn expression(read bytes: [u8], read parsed: Parsed, item: SyntaxNode,
    read functions: List<Function>, read names: Map<List<u8>, usize>,
    read expressions: List<Expression?>): Expression? throws CheckError {
    let scalar = match item.kind {
        NodeKind.Integer => try integer(read bytes[item.span.begin as usize..item.span.end as usize], item.span),
        NodeKind.Boolean => Scalar.Bool,
        NodeKind.Unit => Scalar.Unit,
        NodeKind.Group => (try value(expressions, child(parsed, item, 0), item.span)).scalar,
        NodeKind.Block => {
            var result = Scalar.Unit
            for index in item.children.begin..item.children.end {
                let id = parsed.children[index as usize]
                let expression = try value(expressions, id, node(parsed, id).span)
                result = if node(parsed, id).semicolon { Scalar.Unit } else { expression.scalar }
            }
            result
        },
        NodeKind.Call => {
            let callee = node(parsed, child(parsed, item, 0))
            let arguments = node(parsed, child(parsed, item, 1))
            if !callee.kind.is(NodeKind.Name) || arguments.children.begin != arguments.children.end {
                throw unsupported(item.span)
            }
            let identifier = try name(bytes, parsed, callee)
            let present(id) = names.get(identifier) else {
                throw CheckError(CheckPhase.Name, callee.span, "unresolved function")
            }
            let id = *id
            return present(Expression(functions[id].result, present(id)))
        },
        NodeKind.Binary => {
            let present(operation) = item.operation else { throw unsupported(item.span) }
            let operator = parsed.tokens[operation as usize].span
            if operator.end - operator.begin != 1u32 { throw unsupported(operator) }
            match bytes[operator.begin as usize] {
                b'+' | b'-' | b'*' | b'/' | b'%' => (),
                _ => { throw unsupported(operator) }
            }
            let lhs = try value(expressions, child(parsed, item, 0), item.span)
            let rhs = try value(expressions, child(parsed, item, 1), item.span)
            if !lhs.scalar.is(Scalar.I32) || !rhs.scalar.is(Scalar.I32) {
                throw CheckError(CheckPhase.Type, operator, "arithmetic operands must both be i32")
            }
            Scalar.I32
        },
        _ => { return none }
    }
    present(Expression(scalar, none))
}

pub fn check_module(read bytes: [u8], read parsed: Parsed): CheckedModule throws CheckError {
    let present(root_id) = parsed.root else { throw unsupported(Span(0, 0, 0)) }
    let root = node(parsed, root_id)
    if parsed.diagnostics.error_count != 0 { throw unsupported(root.span) }
    var functions = List<Function>()
    var names = Map<List<u8>, usize>()
    var entry: usize? = none
    for index in root.children.begin..root.children.end {
        let id = parsed.children[index as usize]
        let (identifier, function) = try signature(bytes, parsed, id)
        let position = functions.len()
        if identifier.as_slice() == b"main" { entry = present(position) }
        if names.insert(take identifier, position).is_present() {
            throw CheckError(CheckPhase.Name, node(parsed, id).span, "duplicate function")
        }
        functions.push(function)
    }
    let present(main) = entry else {
        throw CheckError(CheckPhase.Name, Span(root.span.source, 0, 0), "missing entry function 'main'")
    }
    if !functions[main].result.is(Scalar.I32) {
        throw CheckError(CheckPhase.Type, node(parsed, functions[main].declaration).span, "entry function must have no parameters and return i32")
    }
    var expressions = List<Expression?>()
    for item in parsed.nodes.as_slice() {
        let fact = try expression(bytes, parsed, item, functions, names, expressions)
        expressions.push(fact)
    }
    for function in functions.as_slice() {
        let body = node(parsed, function.body)
        let result = try value(expressions, function.body, body.span)
        if !result.scalar.is(function.result) {
            throw CheckError(CheckPhase.Type, body.span, "function body does not match its declared result type")
        }
    }
    CheckedModule(take functions, take expressions, main)
}
