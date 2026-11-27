import alloc.hash_map.Map
import alloc.string.String
import alloc.vec.List
import core.text.Text
import mettle_foundation.Span
import mettle_syntax.{ NodeId, NodeKind, Parsed, SyntaxNode }
import mettle_types.Scalar

module cfg;

pub copy enum CheckPhase { Feature, Lex, Name, Type, Attribute }

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
    pub local_count: usize
}

pub copy type FunctionId { pub module_index: usize; pub index: usize }

pub copy enum Binding { Function(FunctionId), Parameter(usize), Local(usize) }

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
    pub items: List<ActiveItem>
}

pub copy type ActiveItem { id: NodeId; offset: u32 }

pub type ExternalModule {
    pub name: List<u8>
    pub span: Span
}

type Declarations {
    functions: List<Function>
    names: Map<List<u8>, usize>
    parameters: List<Map<List<u8>, usize>>
}

copy type Local {
    scalar: Scalar
    binding: Binding
    writable: bool
}

copy type Shadow {
    symbol: usize
    previous: usize
}

type Body {
    expressions: List<Expression?>
    symbols: Map<List<u8>, usize>
    visible: List<usize>
    bindings: List<Local>
    shadows: List<Shadow>
    binary: List<NodeId>
    local_count: usize
}

type Context<region r> {
    source: read SourceModule from r
    owner: FunctionId
    declarations: read List<Declarations> from r
    mounts: read Map<List<u8>, usize> from r
}

extend<region r> Context<region r> {
    fn resolve(read body: Body, read spelling: List<u8>): Local? {
        if let present(symbol) = body.symbols.get(spelling) {
            let visible = body.visible[*symbol]
            if visible != 0usize { return present(body.bindings[visible - 1usize]) }
        }
        let scope = read self.declarations[self.owner.module_index]
        let present(index) = scope.parameters[self.owner.index].get(spelling) else { return none }
        let index = *index
        present(Local(scope.functions[self.owner.index].parameters[index], Binding.Parameter(index), false))
    }
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

pub fn active_items(read bytes: [u8], read parsed: Parsed, read features: List<String>): List<ActiveItem> throws CheckError {
    let root = try root_node(parsed)
    var items = List<ActiveItem>()
    for index in root.children.begin..root.children.end {
        let id = parsed.children[index as usize]
        let item = node(parsed, id)
        let count = item.children.end - item.children.begin
        var offset = 0u32
        var active = true
        while offset < count {
            let attribute = node(parsed, child(parsed, item, offset))
            if !attribute.kind.is(NodeKind.Attribute) { break }
            let identifier = node(parsed, child(parsed, attribute, 0))
            let spelling = read bytes[identifier.span.begin as usize..identifier.span.end as usize]
            if item.kind.is(NodeKind.Function) &&
                (spelling == b"test" || spelling == b"bench" || spelling == b"ignore" || spelling == b"should_panic") {
                offset += 1u32
                continue
            }
            if spelling != b"cfg" {
                throw unsupported(attribute.span)
            }
            if attribute.children.end - attribute.children.begin != 2u32 {
                throw CheckError(CheckPhase.Attribute, attribute.span, "cfg requires one predicate")
            }
            let arguments = node(parsed, child(parsed, attribute, 1))
            if !arguments.kind.is(NodeKind.TokenTree) {
                throw CheckError(CheckPhase.Attribute, attribute.span, "cfg requires one predicate")
            }
            let tokens = read parsed.tokens.as_slice()[arguments.tokens.begin as usize..arguments.tokens.end as usize]
            let included = try cfg.included(bytes, tokens, features, attribute.span)
            active = active && included
            offset += 1u32
        }
        if active { items.push(ActiveItem(id, offset)) }
    }
    items
}

pub fn external_modules(read source: SourceModule): List<ExternalModule> throws CheckError {
    let bytes = source.bytes.as_slice()
    let parsed = read source.syntax
    var result = List<ExternalModule>()
    for declaration in source.items.as_slice() {
        let item = node(parsed, declaration.id)
        if !item.kind.is(NodeKind.ModuleDeclaration) { continue }
        let identifier = node(parsed, child(parsed, item, declaration.offset))
        if item.children.end - item.children.begin != declaration.offset + 1u32 || !identifier.kind.is(NodeKind.Name) {
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

fn signature(read bytes: [u8], read parsed: Parsed, declaration: ActiveItem): (List<u8>, Function, Map<List<u8>, usize>) throws CheckError {
    let item = node(parsed, declaration.id)
    if !item.kind.is(NodeKind.Function) { throw unsupported(item.span) }
    let first = node(parsed, child(parsed, item, declaration.offset))
    let exported = first.kind.is(NodeKind.Visibility)
    let offset = declaration.offset + if exported { 1u32 } else { 0u32 }
    if exported && read bytes[first.span.begin as usize..first.span.end as usize] != b"pub" {
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
    (try name(bytes, parsed, identifier), Function(declaration.id, body, result, take types, exported, 0usize), take locals)
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

fn module_target(read source: SourceModule, read mounts: Map<List<u8>, usize>, read spelling: List<u8>): usize? {
    if let present(index) = source.modules.get(spelling) { return present(*index) }
    if let present(index) = mounts.get(spelling) { return present(*index) }
    none
}

fn operator_span(read parsed: Parsed, item: SyntaxNode): Span throws CheckError {
    let present(operation) = item.operation else { throw unsupported(item.span) }
    parsed.tokens[operation as usize].span
}

fn require_type(actual: Scalar, expected: Scalar, span: Span): Unit throws CheckError {
    if actual.is(expected) { return }
    let message = match expected {
        Scalar.I32 => if actual.is(Scalar.Bool) { "expected i32, found bool" } else { "expected i32, found Unit" },
        Scalar.Bool => if actual.is(Scalar.I32) { "expected bool, found i32" } else { "expected bool, found Unit" },
        Scalar.Unit => if actual.is(Scalar.I32) { "expected Unit, found i32" } else { "expected Unit, found bool" }
    }
    throw CheckError(CheckPhase.Type, span, message)
}

fn expression<region r>(read context: Context<region r>, mut body: Body, id: NodeId): Scalar throws CheckError {
    let bytes = context.source.bytes.as_slice()
    let parsed = read context.source.syntax
    let item = node(parsed, id)
    var binding: Binding? = none
    let scalar = match item.kind {
        NodeKind.Integer => try integer(read bytes[item.span.begin as usize..item.span.end as usize], item.span),
        NodeKind.Boolean => Scalar.Bool,
        NodeKind.Unit => Scalar.Unit,
        NodeKind.Name => {
            let identifier = try name(bytes, parsed, item)
            let present(found) = context.resolve(body, identifier) else {
                if context.declarations[context.owner.module_index].names.get(identifier).is_present() {
                    throw unsupported(item.span)
                }
                throw CheckError(CheckPhase.Name, item.span, "unresolved value")
            }
            binding = present(found.binding)
            found.scalar
        },
        NodeKind.Group => try expression(context, mut body, child(parsed, item, 0)),
        NodeKind.Block => {
            let mark = body.shadows.len()
            var result = Scalar.Unit
            for index in item.children.begin..item.children.end {
                let id = parsed.children[index as usize]
                let scalar = try expression(context, mut body, id)
                result = if node(parsed, id).semicolon { Scalar.Unit } else { scalar }
            }
            while body.shadows.len() > mark {
                let shadow = body.shadows.pop().or_panic()
                body.visible[shadow.symbol] = shadow.previous
            }
            result
        },
        NodeKind.Binding => {
            let pattern = node(parsed, child(parsed, item, 0))
            let wildcard = pattern.kind.is(NodeKind.PatternWildcard)
            if !wildcard && !pattern.kind.is(NodeKind.Name) { throw unsupported(pattern.span) }
            let count = item.children.end - item.children.begin
            let op = try operator_span(parsed, item)
            let writable = read bytes[op.begin as usize..op.end as usize] == b"var"
            if count < 2u32 || count > 3u32 { throw unsupported(item.span) }
            let initializer = child(parsed, item, count - 1u32)
            let initial = node(parsed, initializer)
            if initial.kind.is(NodeKind.LetElse) { throw unsupported(initial.span) }
            let annotation = if count == 3u32 {
                present(try scalar_type(bytes, node(parsed, child(parsed, item, 1))))
            } else { none }
            let index = body.local_count
            if !wildcard { body.local_count += 1usize }
            let actual = try expression(context, mut body, initializer)
            let scalar = if let present(expected) = annotation {
                try require_type(actual, expected, item.span)
                expected
            } else { actual }
            if !wildcard {
                let identifier = try name(bytes, parsed, pattern)
                let symbol = if let present(slot) = body.symbols.get(identifier) { *slot } else {
                    let _ = body.symbols.insert(take identifier, body.visible.len())
                    body.visible.push(0usize)
                    body.visible.len() - 1usize
                }
                body.shadows.push(Shadow(symbol, body.visible[symbol]))
                body.bindings.push(Local(scalar, Binding.Local(index), writable))
                body.visible[symbol] = body.bindings.len()
                binding = present(Binding.Local(index))
            }
            Scalar.Unit
        },
        NodeKind.Assign => {
            let operator = try operator_span(parsed, item)
            let spelling = read bytes[operator.begin as usize..operator.end as usize]
            let simple = spelling == b"="
            if !simple && spelling != b"+=" && spelling != b"-=" && spelling != b"*=" &&
                spelling != b"/=" && spelling != b"%=" { throw unsupported(operator) }
            let lhs = child(parsed, item, 0)
            let rhs = child(parsed, item, 1)
            var target = node(parsed, lhs)
            while target.kind.is(NodeKind.Group) { target = node(parsed, child(parsed, target, 0)) }
            if !target.kind.is(NodeKind.Name) { throw unsupported(target.span) }
            let actual = try expression(context, mut body, rhs)
            let identifier = try name(bytes, parsed, target)
            let present(found) = context.resolve(body, identifier) else {
                throw CheckError(CheckPhase.Name, target.span, "unresolved value")
            }
            try require_type(actual, found.scalar, item.span)
            if !simple && !found.scalar.is(Scalar.I32) {
                throw CheckError(CheckPhase.Type, item.span, "operator is not available for this scalar type")
            }
            if !found.writable {
                throw CheckError(CheckPhase.Type, item.span, "cannot assign immutable binding more than once")
            }
            var place = lhs
            while node(parsed, place).kind.is(NodeKind.Group) {
                body.expressions[place.index as usize] = present(Expression(found.scalar, none))
                place = child(parsed, node(parsed, place), 0)
            }
            body.expressions[place.index as usize] = present(Expression(found.scalar, present(found.binding)))
            binding = present(found.binding)
            Scalar.Unit
        },
        NodeKind.Conditions => {
            for index in item.children.begin..item.children.end {
                let id = parsed.children[index as usize]
                let span = node(parsed, id).span
                if !(try expression(context, mut body, id)).is(Scalar.Bool) {
                    throw CheckError(CheckPhase.Type, span, "conditional clause must be bool")
                }
            }
            Scalar.Bool
        },
        NodeKind.If => {
            let condition = child(parsed, item, 0)
            let condition_span = node(parsed, condition).span
            if !(try expression(context, mut body, condition)).is(Scalar.Bool) {
                throw CheckError(CheckPhase.Type, condition_span, "if condition must be bool")
            }
            let consequent = child(parsed, item, 1)
            let consequent_span = node(parsed, consequent).span
            let result = try expression(context, mut body, consequent)
            let alternative = if item.children.end - item.children.begin == 3u32 {
                try expression(context, mut body, child(parsed, item, 2))
            } else { Scalar.Unit }
            if !result.is(alternative) {
                throw CheckError(CheckPhase.Type, consequent_span, "if branches must have the same result type")
            }
            result
        },
        NodeKind.Call => {
            let callee = node(parsed, child(parsed, item, 0))
            let arguments = node(parsed, child(parsed, item, 1))
            var module_index = context.owner.module_index
            var identifier_node = callee
            if callee.kind.is(NodeKind.Field) {
                let base = node(parsed, child(parsed, callee, 0))
                if !base.kind.is(NodeKind.Name) { throw unsupported(callee.span) }
                let namespace = try name(bytes, parsed, base)
                if context.resolve(body, namespace).is_present() { throw unsupported(callee.span) }
                let present(target) = module_target(context.source, context.mounts, namespace) else {
                    throw unsupported(base.span)
                }
                module_index = target
                identifier_node = node(parsed, child(parsed, callee, 1))
            } else if !callee.kind.is(NodeKind.Name) {
                throw unsupported(callee.span)
            }
            let identifier = try name(bytes, parsed, identifier_node)
            if callee.kind.is(NodeKind.Name) && context.resolve(body, identifier).is_present() {
                throw CheckError(CheckPhase.Type, callee.span, "expression is not callable")
            }
            let target = read context.declarations[module_index]
            let present(id) = target.names.get(identifier) else {
                throw CheckError(CheckPhase.Name, callee.span, "unresolved function")
            }
            let id = *id
            let signature = read target.functions[id]
            if module_index != context.owner.module_index && !signature.exported {
                throw CheckError(CheckPhase.Name, callee.span, "function is private")
            }
            if arguments.children.end - arguments.children.begin != signature.parameters.len() as u32 {
                throw CheckError(CheckPhase.Type, item.span, "function argument count does not match its parameters")
            }
            for index in 0usize..signature.parameters.len() {
                let argument = child(parsed, arguments, index as u32)
                let span = node(parsed, argument).span
                let actual = try expression(context, mut body, argument)
                if !actual.is(signature.parameters[index]) {
                    throw CheckError(CheckPhase.Type, span, "argument does not match the parameter type")
                }
            }
            binding = present(Binding.Function(FunctionId(module_index, id)))
            signature.result
        },
        NodeKind.Binary => {
            let mark = body.binary.len()
            var left = child(parsed, item, 0)
            while node(parsed, left).kind.is(NodeKind.Binary) {
                let next = child(parsed, node(parsed, left), 0)
                body.binary.push(left)
                left = next
            }
            var lhs = try expression(context, mut body, left)
            while body.binary.len() > mark {
                let nested = body.binary.pop().or_panic()
                let binary = node(parsed, nested)
                let rhs = try expression(context, mut body, child(parsed, binary, 1))
                lhs = try binary_type(bytes, try operator_span(parsed, binary), lhs, rhs)
                body.expressions[nested.index as usize] = present(Expression(lhs, none))
            }
            let rhs = try expression(context, mut body, child(parsed, item, 1))
            try binary_type(bytes, try operator_span(parsed, item), lhs, rhs)
        },
        _ => { throw unsupported(item.span) }
    }
    body.expressions[id.index as usize] = present(Expression(scalar, binding))
    scalar
}

fn binary_type(read bytes: [u8], operator: Span, lhs: Scalar, rhs: Scalar): Scalar throws CheckError {
    let spelling = read bytes[operator.begin as usize..operator.end as usize]
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
}

fn collect(read source: SourceModule, read mounts: Map<List<u8>, usize>): Declarations throws CheckError {
    let bytes = source.bytes.as_slice()
    let parsed = read source.syntax
    var functions = List<Function>()
    var names = Map<List<u8>, usize>()
    var parameters = List<Map<List<u8>, usize>>()
    var imports = Map<List<u8>, Unit>()
    for declaration in source.items.as_slice() {
        let item = node(parsed, declaration.id)
        if item.kind.is(NodeKind.ModuleDeclaration) || item.kind.is(NodeKind.Import) {
            if item.children.end - item.children.begin != declaration.offset + 1u32 { throw unsupported(item.span) }
            var identifier = node(parsed, child(parsed, item, declaration.offset))
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
        let (identifier, function, scope) = try signature(bytes, parsed, declaration)
        let position = functions.len()
        if names.insert(take identifier, position).is_present() {
            throw CheckError(CheckPhase.Name, item.span, "duplicate function")
        }
        functions.push(take function)
        parameters.push(take scope)
    }
    Declarations(take functions, take names, take parameters)
}

fn check_bodies(read source: SourceModule, module_index: usize,
    read declarations: List<Declarations>, read mounts: Map<List<u8>, usize>): (List<Expression?>, List<usize>) throws CheckError {
    let parsed = read source.syntax
    let functions = read declarations[module_index].functions
    var body = Body(List<Expression?>(), Map<List<u8>, usize>(), List<usize>(), List<Local>(), List<Shadow>(), List<NodeId>(), 0usize)
    body.expressions.reserve_exact(parsed.nodes.len())
    for _ in 0usize..parsed.nodes.len() { body.expressions.push(none) }
    var counts = List<usize>()
    for index in 0usize..functions.len() {
        let function = read functions[index]
        let context = Context(read source, FunctionId(module_index, index), read declarations, read mounts)
        body.symbols.clear()
        body.visible.clear()
        body.bindings.clear()
        body.local_count = 0usize
        let result = try expression(context, mut body, function.body)
        if !result.is(function.result) {
            throw CheckError(CheckPhase.Type, node(parsed, function.body).span, "function body does not match its declared result type")
        }
        counts.push(body.local_count)
    }
    (take body.expressions, take counts)
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
    var bodies = List<(List<Expression?>, List<usize>)>()
    for index in 0usize..sources.len() {
        bodies.push(try check_bodies(sources[index], index, declarations, mounts[sources[index].package_index]))
    }
    bodies.reverse()
    var result = List<CheckedModule>()
    for scope in take declarations {
        let (expressions, counts) = bodies.pop().or_panic()
        var functions = take scope.functions
        for index in 0usize..functions.len() { functions[index].local_count = counts[index] }
        result.push(CheckedModule(take functions, take expressions, if result.is_empty() { entry } else { none }))
    }
    result
}

fn check_test_source(read source: [u8]): (Parsed, CheckedModule) throws CheckError {
    let parsed = mettle_syntax.parse(source, 0u32)
    let items = try active_items(source, parsed, List<String>())
    var sources = List<SourceModule>()
    sources.push(SourceModule(source.to_vec(), take parsed, Map<List<u8>, usize>(), 0usize, take items))
    var mounts = List<Map<List<u8>, usize>>()
    mounts.push(Map<List<u8>, usize>())
    var checked = try check_modules(sources, mounts, false)
    let input = sources.pop().or_panic()
    (take input.syntax, checked.pop().or_panic())
}

fn assert_local(read checked: CheckedModule, id: NodeId, expected: usize, scalar: Scalar): Unit {
    let stored = checked.expressions[id.index as usize]
    let fact = stored.or_panic()
    let present(Binding.Local(index)) = fact.binding else { panic("expected a local binding fact") }
    assert(index == expected && fact.scalar.is(scalar), "wrong local identity or type")
}

@test
fn scalar_local_facts(): Unit {
    let (parsed, checked) = (capture check_test_source(
        b"fn first(x: i32): i32 { var x: i32 = { let inner = x; inner }; x += 2; x -= 1; x *= 3; x /= 2; x %= 2; (x) = { let x = true; let _ = x; 5 }; let x = x; x }\nfn second(): bool { let flag = false; flag }"
    )).or_panic()
    let first = read checked.functions[0usize]
    let second = read checked.functions[1usize]
    assert(first.local_count == 4usize && second.local_count == 1usize, "local counts include a discard or cross function boundaries")
    let block = node(parsed, first.body)
    let outer = child(parsed, block, 0u32)
    assert_local(checked, outer, 0usize, Scalar.Unit)
    let initial = node(parsed, child(parsed, node(parsed, outer), 2u32))
    let inner = child(parsed, initial, 0u32)
    assert_local(checked, inner, 1usize, Scalar.Unit)
    let parameter = child(parsed, node(parsed, inner), 1u32)
    let parameter_fact = checked.expressions[parameter.index as usize]
    let present(Binding.Parameter(index)) = parameter_fact.or_panic().binding else {
        panic("initializer did not resolve the shadowed parameter")
    }
    assert(index == 0usize, "wrong parameter identity")
    assert_local(checked, child(parsed, initial, 1u32), 1usize, Scalar.I32)
    for offset in 1u32..7u32 { assert_local(checked, child(parsed, block, offset), 0usize, Scalar.Unit) }
    let replacement = node(parsed, child(parsed, node(parsed, child(parsed, block, 6u32)), 1u32))
    assert_local(checked, child(parsed, replacement, 0u32), 2usize, Scalar.Unit)
    let discard = child(parsed, replacement, 1u32)
    let stored = checked.expressions[discard.index as usize]
    let discard_fact = stored.or_panic()
    assert(discard_fact.binding.is_none() && discard_fact.scalar.is(Scalar.Unit), "discard introduced a local")
    assert_local(checked, child(parsed, node(parsed, discard), 1u32), 2usize, Scalar.Bool)
    let shadow = child(parsed, block, 7u32)
    assert_local(checked, shadow, 3usize, Scalar.Unit)
    assert_local(checked, child(parsed, node(parsed, shadow), 1u32), 0usize, Scalar.I32)
    assert_local(checked, child(parsed, block, 8u32), 3usize, Scalar.I32)
    assert_local(checked, child(parsed, node(parsed, second.body), 1u32), 0usize, Scalar.Bool)
}

@test
fn scalar_local_diagnostics(): Unit {
    let cases = [
        ("fn f(): i32 { let n = 1; n += 2; n }", CheckPhase.Type, "n += 2", "cannot assign immutable binding more than once"),
        ("fn f(): i32 { var n = 1; n = false; n }", CheckPhase.Type, "n = false", "expected i32, found bool"),
        ("fn f(): bool { let n: bool = 1; n }", CheckPhase.Type, "let n: bool = 1", "expected bool, found i32"),
        ("fn f(): bool { var n = true; n %= false; n }", CheckPhase.Type, "n %= false", "operator is not available for this scalar type"),
        ("fn f(): i32 { let n = n; n }", CheckPhase.Name, "n", "unresolved value"),
        ("fn f(): i32 { let _ = { let hidden = 1; hidden }; hidden }", CheckPhase.Name, "hidden", "unresolved value"),
        ("fn f(): i32 { 1 }\nfn g(): Unit { let _ = f }", CheckPhase.Feature, "f", "native semantic checking does not support this construct yet"),
        ("fn f(): Unit { var n: i32; () }", CheckPhase.Feature, "i32", "native semantic checking does not support this construct yet"),
        ("fn f(): i32 { var n = 1; n &= 2; n }", CheckPhase.Feature, "&=", "native semantic checking does not support this construct yet")
    ]
    for (source, phase, lexeme, message) in read cases {
        let failure(error) = capture check_test_source(source.as_bytes()) else { panic("invalid scalar local accepted") }
        let span = error.span
        let bytes = source.as_bytes()
        assert((error.phase as u32) == (phase as u32) && error.message == message &&
            read bytes[span.begin as usize..span.end as usize] == lexeme.as_bytes(), "wrong local diagnostic")
    }
}
