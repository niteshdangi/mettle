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

pub type Function {
    pub declaration: NodeId
    pub body: NodeId
    pub result: Scalar
    pub parameters: List<Scalar>
}

pub copy enum Binding { Function(usize), Parameter(usize) }

pub copy type Expression {
    pub scalar: Scalar
    pub binding: Binding?
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

fn scalar_type(read bytes: [u8], annotation: SyntaxNode): Scalar throws CheckError {
    if !annotation.kind.is(NodeKind.TypeName) || annotation.children.end - annotation.children.begin != 1u32 {
        throw unsupported(annotation.span)
    }
    let spelling = read bytes[annotation.span.begin as usize..annotation.span.end as usize]
    if spelling == "i32".as_bytes() { Scalar.I32 }
    else if spelling == "bool".as_bytes() { Scalar.Bool }
    else if spelling == "Unit".as_bytes() { Scalar.Unit }
    else { throw unsupported(annotation.span) }
}

fn signature(read bytes: [u8], read parsed: Parsed, id: NodeId): (List<u8>, Function, Map<List<u8>, usize>) throws CheckError {
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
        || !node(parsed, body).kind.is(NodeKind.Block)) {
        throw unsupported(item.span)
    }
    var types = List<Scalar>()
    var locals = Map<List<u8>, usize>()
    for index in parameters.children.begin..parameters.children.end {
        let parameter = node(parsed, parsed.children[index as usize])
        if !parameter.kind.is(NodeKind.Parameter) || parameter.children.end - parameter.children.begin != 2u32 {
            throw unsupported(parameter.span)
        }
        let binding = node(parsed, child(parsed, parameter, 0))
        if !binding.kind.is(NodeKind.Name) { throw unsupported(binding.span) }
        let spelling = try name(bytes, parsed, binding)
        if locals.insert(take spelling, types.len()).is_present() {
            throw CheckError(CheckPhase.Name, binding.span, "duplicate parameter")
        }
        types.push(try scalar_type(bytes, node(parsed, child(parsed, parameter, 1))))
    }
    let result = try scalar_type(bytes, annotation)
    (try name(bytes, parsed, identifier), Function(id, body, result, take types), take locals)
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
    read functions: List<Function>, read names: Map<List<u8>, usize>, owner: usize,
    read locals: Map<List<u8>, usize>,
    read expressions: List<Expression?>): Expression? throws CheckError {
    let scalar = match item.kind {
        NodeKind.Integer => try integer(read bytes[item.span.begin as usize..item.span.end as usize], item.span),
        NodeKind.Boolean => Scalar.Bool,
        NodeKind.Unit => Scalar.Unit,
        NodeKind.Name => {
            let identifier = try name(bytes, parsed, item)
            let present(index) = locals.get(identifier) else { return none }
            let index = *index
            return present(Expression(functions[owner].parameters[index], present(Binding.Parameter(index))))
        },
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
            if !callee.kind.is(NodeKind.Name) { throw unsupported(item.span) }
            let identifier = try name(bytes, parsed, callee)
            if locals.get(identifier).is_present() {
                throw CheckError(CheckPhase.Type, callee.span, "scalar parameter is not callable")
            }
            let present(id) = names.get(identifier) else {
                throw CheckError(CheckPhase.Name, callee.span, "unresolved function")
            }
            let id = *id
            let signature = read functions[id]
            if arguments.children.end - arguments.children.begin != signature.parameters.len() as u32 {
                throw CheckError(CheckPhase.Type, item.span, "function argument count does not match its parameters")
            }
            for index in 0usize..signature.parameters.len() {
                let argument = child(parsed, arguments, index as u32)
                let span = node(parsed, argument).span
                let actual = try value(expressions, argument, span)
                if !actual.scalar.is(signature.parameters[index]) {
                    throw CheckError(CheckPhase.Type, span, "argument does not match the parameter type")
                }
            }
            return present(Expression(signature.result, present(Binding.Function(id))))
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
    var locals = List<Map<List<u8>, usize>>()
    var entry: usize? = none
    for index in root.children.begin..root.children.end {
        let id = parsed.children[index as usize]
        let (identifier, function, scope) = try signature(bytes, parsed, id)
        let position = functions.len()
        if identifier.as_slice() == b"main" { entry = present(position) }
        if names.insert(take identifier, position).is_present() {
            throw CheckError(CheckPhase.Name, node(parsed, id).span, "duplicate function")
        }
        functions.push(take function)
        locals.push(take scope)
    }
    let present(main) = entry else {
        throw CheckError(CheckPhase.Name, Span(root.span.source, 0, 0), "missing entry function 'main'")
    }
    if !functions[main].result.is(Scalar.I32) || !functions[main].parameters.is_empty() {
        throw CheckError(CheckPhase.Type, node(parsed, functions[main].declaration).span, "entry function must have no parameters and return i32")
    }
    var expressions = List<Expression?>()
    for index in 0usize..functions.len() {
        let function = read functions[index]
        let body = node(parsed, function.body)
        while expressions.len() <= function.body.index as usize {
            let item = parsed.nodes[expressions.len()]
            let fact = if item.span.begin < body.span.begin { none }
                else { try expression(bytes, parsed, item, functions, names, index, locals[index], expressions) }
            expressions.push(fact)
        }
        let result = try value(expressions, function.body, body.span)
        if !result.scalar.is(function.result) {
            throw CheckError(CheckPhase.Type, body.span, "function body does not match its declared result type")
        }
    }
    while expressions.len() < parsed.nodes.len() { expressions.push(none) }
    CheckedModule(take functions, take expressions, main)
}
