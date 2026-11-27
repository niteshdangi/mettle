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
    pub exported: bool
}

pub copy type FunctionId { pub module_index: usize; pub index: usize }

pub copy enum Binding { Function(FunctionId), Parameter(usize) }

pub copy type Expression {
    pub scalar: Scalar
    pub binding: Binding?
}

pub type CheckedModule {
    pub functions: List<Function>
    pub expressions: List<Expression?>
    pub entry: usize?
}

pub type SourceModule {
    pub bytes: List<u8>
    pub syntax: Parsed
    pub modules: Map<List<u8>, usize>
    pub package_index: usize
}

pub type ExternalModule {
    pub name: List<u8>
    pub span: Span
}

type Declarations {
    functions: List<Function>
    names: Map<List<u8>, usize>
    locals: List<Map<List<u8>, usize>>
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

fn root_node(read parsed: Parsed): SyntaxNode throws CheckError {
    let present(root_id) = parsed.root else { throw unsupported(Span(0, 0, 0)) }
    let root = node(parsed, root_id)
    if parsed.diagnostics.error_count != 0 { throw unsupported(root.span) }
    root
}

pub fn external_modules(read bytes: [u8], read parsed: Parsed): List<ExternalModule> throws CheckError {
    let root = try root_node(parsed)
    var result = List<ExternalModule>()
    for index in root.children.begin..root.children.end {
        let item = node(parsed, parsed.children[index as usize])
        if !item.kind.is(NodeKind.ModuleDeclaration) { continue }
        let identifier = node(parsed, child(parsed, item, 0))
        if item.children.end - item.children.begin != 1u32 || !identifier.kind.is(NodeKind.Name) {
            throw unsupported(item.span)
        }
        result.push(ExternalModule(try name(bytes, parsed, identifier), item.span))
    }
    result
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
    if offset != 0u32 && read bytes[first.span.begin as usize..first.span.end as usize] != b"pub" {
        throw unsupported(first.span)
    }
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
    (try name(bytes, parsed, identifier), Function(id, body, result, take types, offset != 0u32), take locals)
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

fn module_target(read source: SourceModule, read mounts: Map<List<u8>, usize>, read spelling: List<u8>): usize? {
    if let present(index) = source.modules.get(spelling) { return present(*index) }
    if let present(index) = mounts.get(spelling) { return present(*index) }
    none
}

fn expression(read source: SourceModule, item: SyntaxNode, owner: FunctionId,
    read declarations: List<Declarations>, read mounts: Map<List<u8>, usize>,
    read expressions: List<Expression?>): Expression? throws CheckError {
    let bytes = source.bytes.as_slice()
    let parsed = read source.syntax
    let scope = read declarations[owner.module_index]
    let locals = read scope.locals[owner.index]
    let scalar = match item.kind {
        NodeKind.Integer => try integer(read bytes[item.span.begin as usize..item.span.end as usize], item.span),
        NodeKind.Boolean => Scalar.Bool,
        NodeKind.Unit => Scalar.Unit,
        NodeKind.Name => {
            let identifier = try name(bytes, parsed, item)
            let present(index) = locals.get(identifier) else { return none }
            let index = *index
            return present(Expression(scope.functions[owner.index].parameters[index], present(Binding.Parameter(index))))
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
        NodeKind.If => {
            let condition = child(parsed, item, 0)
            let condition_span = node(parsed, condition).span
            if !(try value(expressions, condition, condition_span)).scalar.is(Scalar.Bool) {
                throw CheckError(CheckPhase.Type, condition_span, "if condition must be bool")
            }
            let consequent = child(parsed, item, 1)
            let consequent_span = node(parsed, consequent).span
            let result = (try value(expressions, consequent, consequent_span)).scalar
            let alternative = if item.children.end - item.children.begin == 3u32 {
                let id = child(parsed, item, 2)
                (try value(expressions, id, node(parsed, id).span)).scalar
            } else { Scalar.Unit }
            if !result.is(alternative) {
                throw CheckError(CheckPhase.Type, consequent_span, "if branches must have the same result type")
            }
            result
        },
        NodeKind.Call => {
            let callee = node(parsed, child(parsed, item, 0))
            let arguments = node(parsed, child(parsed, item, 1))
            var module_index = owner.module_index
            var identifier_node = callee
            if callee.kind.is(NodeKind.Field) {
                let base = node(parsed, child(parsed, callee, 0))
                if !base.kind.is(NodeKind.Name) { throw unsupported(callee.span) }
                let namespace = try name(bytes, parsed, base)
                if locals.get(namespace).is_present() { throw unsupported(callee.span) }
                let present(target) = module_target(source, mounts, namespace) else {
                    throw unsupported(base.span)
                }
                module_index = target
                identifier_node = node(parsed, child(parsed, callee, 1))
            } else if !callee.kind.is(NodeKind.Name) {
                throw unsupported(callee.span)
            }
            let identifier = try name(bytes, parsed, identifier_node)
            if callee.kind.is(NodeKind.Name) && locals.get(identifier).is_present() {
                throw CheckError(CheckPhase.Type, callee.span, "scalar parameter is not callable")
            }
            let target = read declarations[module_index]
            let present(id) = target.names.get(identifier) else {
                throw CheckError(CheckPhase.Name, callee.span, "unresolved function")
            }
            let id = *id
            let signature = read target.functions[id]
            if module_index != owner.module_index && !signature.exported {
                throw CheckError(CheckPhase.Name, callee.span, "function is private")
            }
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
            return present(Expression(signature.result, present(Binding.Function(FunctionId(module_index, id)))))
        },
        NodeKind.Binary => {
            let present(operation) = item.operation else { throw unsupported(item.span) }
            let operator = parsed.tokens[operation as usize].span
            let spelling = read bytes[operator.begin as usize..operator.end as usize]
            let lhs = (try value(expressions, child(parsed, item, 0), item.span)).scalar
            let rhs = (try value(expressions, child(parsed, item, 1), item.span)).scalar
            if spelling == b"&&" || spelling == b"||" {
                if !lhs.is(Scalar.Bool) || !rhs.is(Scalar.Bool) {
                    throw CheckError(CheckPhase.Type, operator, "logical operands must both be bool")
                }
                Scalar.Bool
            } else if spelling == b"==" || spelling == b"!=" || spelling == b"<" ||
                      spelling == b"<=" || spelling == b">" || spelling == b">=" {
                if !lhs.is(rhs) {
                    throw CheckError(CheckPhase.Type, operator, "comparison operands must have the same type")
                }
                Scalar.Bool
            } else if spelling == b"+" || spelling == b"-" || spelling == b"*" ||
                      spelling == b"/" || spelling == b"%" {
                if !lhs.is(Scalar.I32) || !rhs.is(Scalar.I32) {
                    throw CheckError(CheckPhase.Type, operator, "arithmetic operands must both be i32")
                }
                Scalar.I32
            } else {
                throw unsupported(operator)
            }
        },
        _ => { return none }
    }
    present(Expression(scalar, none))
}

fn collect(read source: SourceModule, read mounts: Map<List<u8>, usize>): Declarations throws CheckError {
    let bytes = source.bytes.as_slice()
    let parsed = read source.syntax
    let root = try root_node(parsed)
    var functions = List<Function>()
    var names = Map<List<u8>, usize>()
    var locals = List<Map<List<u8>, usize>>()
    var imports = Map<List<u8>, Unit>()
    for index in root.children.begin..root.children.end {
        let id = parsed.children[index as usize]
        let item = node(parsed, id)
        if item.kind.is(NodeKind.ModuleDeclaration) || item.kind.is(NodeKind.Import) {
            if item.children.end - item.children.begin != 1u32 { throw unsupported(item.span) }
            var identifier = node(parsed, child(parsed, item, 0))
            if item.kind.is(NodeKind.Import) {
                if !identifier.kind.is(NodeKind.ImportPath) || identifier.children.end - identifier.children.begin != 1u32 {
                    throw unsupported(item.span)
                }
                identifier = node(parsed, child(parsed, identifier, 0))
            }
            let spelling = try name(bytes, parsed, identifier)
            if !module_target(source, mounts, spelling).is_present() { throw unsupported(item.span) }
            if item.kind.is(NodeKind.Import) && imports.insert(take spelling, ()).is_present() {
                throw CheckError(CheckPhase.Name, identifier.span, "duplicate import")
            }
            continue
        }
        let (identifier, function, scope) = try signature(bytes, parsed, id)
        let position = functions.len()
        if names.insert(take identifier, position).is_present() {
            throw CheckError(CheckPhase.Name, item.span, "duplicate function")
        }
        functions.push(take function)
        locals.push(take scope)
    }
    Declarations(take functions, take names, take locals)
}

fn check_bodies(read source: SourceModule, module_index: usize,
    read declarations: List<Declarations>, read mounts: Map<List<u8>, usize>): List<Expression?> throws CheckError {
    let parsed = read source.syntax
    let functions = read declarations[module_index].functions
    var expressions = List<Expression?>()
    for index in 0usize..functions.len() {
        let function = read functions[index]
        let body = node(parsed, function.body)
        while expressions.len() <= function.body.index as usize {
            let item = parsed.nodes[expressions.len()]
            let fact = if item.span.begin < body.span.begin { none }
                else { try expression(source, item, FunctionId(module_index, index), declarations, mounts, expressions) }
            expressions.push(fact)
        }
        let result = try value(expressions, function.body, body.span)
        if !result.scalar.is(function.result) {
            throw CheckError(CheckPhase.Type, body.span, "function body does not match its declared result type")
        }
    }
    while expressions.len() < parsed.nodes.len() { expressions.push(none) }
    expressions
}

pub fn check_modules(read sources: List<SourceModule>, read mounts: List<Map<List<u8>, usize>>,
    executable: bool): List<CheckedModule> throws CheckError {
    if sources.is_empty() { throw unsupported(Span(0, 0, 0)) }
    var declarations = List<Declarations>()
    for source in sources.as_slice() { declarations.push(try collect(source, mounts[source.package_index])) }
    var entry: usize? = none
    if executable {
        let parsed = read sources[0].syntax
        let present(main) = declarations[0].names.get(b"main".to_vec()) else {
            let root = try root_node(parsed)
            throw CheckError(CheckPhase.Name, Span(root.span.source, 0, 0), "missing entry function 'main'")
        }
        let index = *main
        let function = read declarations[0].functions[index]
        if !function.result.is(Scalar.I32) || !function.parameters.is_empty() {
            throw CheckError(CheckPhase.Type, node(parsed, function.declaration).span, "entry function must have no parameters and return i32")
        }
        entry = present(index)
    }
    var expressions = List<List<Expression?>>()
    for index in 0usize..sources.len() {
        expressions.push(try check_bodies(sources[index], index, declarations, mounts[sources[index].package_index]))
    }
    expressions.reverse()
    var result = List<CheckedModule>()
    for scope in take declarations {
        result.push(CheckedModule(take scope.functions, expressions.pop().or_panic(), if result.is_empty() { entry } else { none }))
    }
    result
}
