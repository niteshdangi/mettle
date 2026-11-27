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
    pub scalar: Scalar?
    pub binding: Binding?
    pub integer: u64?
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

copy enum ValueType { Concrete(Scalar), Integer(usize) }
copy type Fact { scalar: ValueType?; binding: Binding? }
copy type IntegerType { parent: usize; size: usize; scalar: Scalar? }
type IntegerTypes { entries: List<IntegerType> }

copy type Local {
    scalar: ValueType?
    binding: Binding
    writable: bool
}

copy type Shadow {
    symbol: usize
    previous: usize
}

type Body {
    expressions: List<Fact?>
    integers: IntegerTypes
    literals: List<(NodeId, u128)>
    symbols: Map<List<u8>, usize>
    visible: List<usize>
    bindings: List<Local>
    shadows: List<Shadow>
    binary: List<NodeId>
    local_count: usize
}

extend IntegerTypes {
    mut fn fresh(): ValueType {
        let index = self.entries.len()
        self.entries.push(IntegerType(index, 1usize, none))
        ValueType.Integer(index)
    }

    mut fn root_of(index: usize): usize {
        var root = index
        while self.entries[root].parent != root {
            let parent = self.entries[root].parent
            let grandparent = self.entries[parent].parent
            self.entries[root].parent = grandparent
            root = grandparent
        }
        root
    }

    mut fn known(value: ValueType): Scalar? {
        match value {
            ValueType.Concrete(scalar) => present(scalar),
            ValueType.Integer(index) => {
                let root = self.root_of(index)
                self.entries[root].scalar
            }
        }
    }

    mut fn constrain_integer(index: usize, scalar: Scalar): bool {
        if scalar.integer_width() == 0u32 { return false }
        let root = self.root_of(index)
        if let present(previous) = self.entries[root].scalar { return previous.is(scalar) }
        self.entries[root].scalar = present(scalar)
        true
    }

    mut fn unify(left: ValueType, right: ValueType): bool {
        match (left, right) {
            (ValueType.Concrete(a), ValueType.Concrete(b)) => a.is(b),
            (ValueType.Concrete(scalar), ValueType.Integer(index)) => self.constrain_integer(index, scalar),
            (ValueType.Integer(index), ValueType.Concrete(scalar)) => self.constrain_integer(index, scalar),
            (ValueType.Integer(a), ValueType.Integer(b)) => {
                var a_root = self.root_of(a)
                var b_root = self.root_of(b)
                if a_root == b_root { return true }
                if self.entries[a_root].size < self.entries[b_root].size {
                    let swap = a_root
                    a_root = b_root
                    b_root = swap
                }
                let a_type = self.entries[a_root].scalar
                let b_type = self.entries[b_root].scalar
                if let present(a_scalar) = a_type, let present(b_scalar) = b_type, !a_scalar.is(b_scalar) {
                    return false
                }
                self.entries[b_root].parent = a_root
                let size = self.entries[b_root].size
                self.entries[a_root].size += size
                if a_type.is_none() { self.entries[a_root].scalar = b_type }
                true
            }
        }
    }
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
        present(Local(present(ValueType.Concrete(scope.functions[self.owner.index].parameters[index])), Binding.Parameter(index), false))
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
    if let present(scalar) = integer_type(spelling) { scalar }
    else if spelling == b"bool" { Scalar.Bool }
    else if spelling == b"Unit" { Scalar.Unit }
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

fn integer_type(read spelling: [u8]): Scalar? {
    if read spelling == b"i32" { present(Scalar.I32) }
    else if read spelling == b"u8" { present(Scalar.U8) }
    else if read spelling == b"u32" { present(Scalar.U32) }
    else if read spelling == b"usize" { present(Scalar.Usize) }
    else { none }
}

fn integer(read bytes: [u8], span: Span): (Scalar?, u128) throws CheckError {
    var position = 0usize
    var radix = 10u128
    if bytes.len() >= 2usize && bytes[0] == b'0' {
        radix = match bytes[1] {
            b'x' => 16u128, b'o' => 8u128, b'b' => 2u128, _ => 10u128
        }
        if radix != 10u128 { position = 2usize }
    }
    var magnitude = 0u128
    var needs_digit = true
    var has_digit = false
    let maximum = 340282366920938463463374607431768211455u128
    let limit = maximum / radix
    let last_digit = maximum % radix
    while position < bytes.len() {
        let byte = bytes[position]
        if byte == b'_' {
            if radix == 10u128 && needs_digit {
                throw CheckError(CheckPhase.Lex, span, "numeric separators must occur between digits")
            }
            needs_digit = true
            position += 1usize
            continue
        }
        let digit = if byte >= b'0' && byte <= b'9' { (byte - b'0') as u128 }
            else if radix == 16u128 && byte >= b'a' && byte <= b'f' { (byte - b'a') as u128 + 10u128 }
            else if radix == 16u128 && byte >= b'A' && byte <= b'F' { (byte - b'A') as u128 + 10u128 }
            else { break }
        if digit >= radix { throw CheckError(CheckPhase.Lex, span, "malformed integer literal") }
        if magnitude > limit || (magnitude == limit && digit > last_digit) {
            throw CheckError(CheckPhase.Type, span, "integer literal exceeds 128 bits")
        }
        magnitude = magnitude * radix + digit
        needs_digit = false
        has_digit = true
        position += 1usize
    }
    if radix == 10u128 && needs_digit {
        throw CheckError(CheckPhase.Lex, span, "numeric separators must occur between digits")
    }
    if !has_digit { throw CheckError(CheckPhase.Lex, span, "integer literal requires digits") }
    if position == bytes.len() { return (none, magnitude) }
    let suffix = read bytes[position..bytes.len()]
    if let present(scalar) = integer_type(suffix) { return (present(scalar), magnitude) }
    if suffix == b"i8" || suffix == b"i16" || suffix == b"i64" || suffix == b"i128" ||
        suffix == b"isize" || suffix == b"u16" || suffix == b"u64" || suffix == b"u128" {
        throw unsupported(span)
    }
    throw CheckError(CheckPhase.Lex, span, "malformed integer literal")
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

fn require_type(mut body: Body, value: ValueType?, expected: ValueType, span: Span): Unit throws CheckError {
    let present(actual) = value else { return }
    if body.integers.unify(actual, expected) { return }
    let expected = if let present(scalar) = body.integers.known(expected) { scalar } else { Scalar.I32 }
    let found = if let present(scalar) = body.integers.known(actual) { scalar } else { Scalar.I32 }
    let message = match (expected, found) {
        (Scalar.I32, Scalar.Bool) => "expected i32, found bool",
        (Scalar.I32, Scalar.Unit) => "expected i32, found Unit",
        (Scalar.Bool, Scalar.I32) => "expected bool, found i32",
        (Scalar.Bool, Scalar.Unit) => "expected bool, found Unit",
        (Scalar.Unit, Scalar.I32) => "expected Unit, found i32",
        (Scalar.Unit, Scalar.Bool) => "expected Unit, found bool",
        _ => "scalar type does not match the expected type"
    }
    throw CheckError(CheckPhase.Type, span, message)
}

pub fn literal_condition(read source: SourceModule, id: NodeId): bool? {
    let parsed = read source.syntax
    var item = node(parsed, id)
    if item.kind.is(NodeKind.Conditions) {
        var all_true = true
        for index in item.children.begin..item.children.end {
            let value = literal_condition(source, parsed.children[index as usize])
            if let present(literal) = value {
                if !literal { return present(false) }
            } else { all_true = false }
        }
        return if all_true { present(true) } else { none }
    }
    while item.kind.is(NodeKind.Group) { item = node(parsed, child(parsed, item, 0)) }
    if !item.kind.is(NodeKind.Boolean) { return none }
    present(source.bytes[item.span.begin as usize] == b't')
}

fn expression<region r>(read context: Context<region r>, mut body: Body, id: NodeId, reachable: bool): ValueType? throws CheckError {
    let bytes = context.source.bytes.as_slice()
    let parsed = read context.source.syntax
    let item = node(parsed, id)
    var binding: Binding? = none
    let scalar = match item.kind {
        NodeKind.Integer => {
            let (suffix, magnitude) = try integer(read bytes[item.span.begin as usize..item.span.end as usize], item.span)
            body.literals.push((id, magnitude))
            present(if let present(scalar) = suffix { ValueType.Concrete(scalar) } else { body.integers.fresh() })
        },
        NodeKind.Boolean => present(ValueType.Concrete(Scalar.Bool)),
        NodeKind.Unit => present(ValueType.Concrete(Scalar.Unit)),
        NodeKind.Cast => {
            let source = try expression(context, mut body, child(parsed, item, 0), reachable)
            let target = try scalar_type(bytes, node(parsed, child(parsed, item, 1)))
            if target.integer_width() == 0u32 { throw unsupported(item.span) }
            if let present(value) = source {
                if let present(scalar) = body.integers.known(value), scalar.integer_width() == 0u32 {
                    throw unsupported(item.span)
                }
                present(ValueType.Concrete(target))
            } else { none }
        },
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
        NodeKind.Group => try expression(context, mut body, child(parsed, item, 0), reachable),
        NodeKind.Block => {
            let mark = body.shadows.len()
            var result = present(ValueType.Concrete(Scalar.Unit))
            for index in item.children.begin..item.children.end {
                let id = parsed.children[index as usize]
                let scalar = try expression(context, mut body, id, reachable && result.is_present())
                if result.is_present() {
                    result = if scalar.is_present() && node(parsed, id).semicolon { present(ValueType.Concrete(Scalar.Unit)) } else { scalar }
                }
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
            let actual = try expression(context, mut body, initializer, reachable)
            let scalar = if let present(expected) = annotation {
                try require_type(mut body, actual, ValueType.Concrete(expected), item.span)
                present(ValueType.Concrete(expected))
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
            if actual.is_present() { present(ValueType.Concrete(Scalar.Unit)) } else { none }
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
            let actual = try expression(context, mut body, rhs, reachable)
            let identifier = try name(bytes, parsed, target)
            let present(found) = context.resolve(body, identifier) else {
                throw CheckError(CheckPhase.Name, target.span, "unresolved value")
            }
            if let present(expected) = found.scalar {
                try require_type(mut body, actual, expected, item.span)
                if !simple, let present(scalar) = body.integers.known(expected), scalar.integer_width() == 0u32 {
                    throw CheckError(CheckPhase.Type, item.span, "operator is not available for this scalar type")
                }
            } else if actual.is_present() {
                throw CheckError(CheckPhase.Type, item.span, "assignment requires a value of type Never")
            }
            if !found.writable {
                throw CheckError(CheckPhase.Type, item.span, "cannot assign immutable binding more than once")
            }
            var place = lhs
            while node(parsed, place).kind.is(NodeKind.Group) {
                body.expressions[place.index as usize] = present(Fact(found.scalar, none))
                place = child(parsed, node(parsed, place), 0)
            }
            body.expressions[place.index as usize] = present(Fact(found.scalar, present(found.binding)))
            binding = present(found.binding)
            if actual.is_present() && found.scalar.is_present() { present(ValueType.Concrete(Scalar.Unit)) } else { none }
        },
        NodeKind.Return => {
            let actual = if item.children.begin == item.children.end {
                present(ValueType.Concrete(Scalar.Unit))
            } else { try expression(context, mut body, child(parsed, item, 0), reachable) }
            let expected = context.declarations[context.owner.module_index].functions[context.owner.index].result
            if reachable { try require_type(mut body, actual, ValueType.Concrete(expected), item.span) }
            none
        },
        NodeKind.Conditions => {
            var active = true
            var can_skip = false
            var completes = true
            for index in item.children.begin..item.children.end {
                let id = parsed.children[index as usize]
                let span = node(parsed, id).span
                let clause = try expression(context, mut body, id, reachable && active)
                if let present(value) = clause, !body.integers.unify(value, ValueType.Concrete(Scalar.Bool)) {
                    throw CheckError(CheckPhase.Type, span, "conditional clause must be bool")
                }
                if active {
                    if clause.is_none() && !can_skip { completes = false }
                    let literal = literal_condition(context.source, id)
                    active = clause.is_present() && literal != present(false)
                    can_skip = can_skip || literal != present(true)
                }
            }
            if completes { present(ValueType.Concrete(Scalar.Bool)) } else { none }
        },
        NodeKind.While => {
            if item.children.end - item.children.begin != 2u32 { throw unsupported(item.span) }
            let condition = child(parsed, item, 0)
            let scalar = try expression(context, mut body, condition, reachable)
            try require_type(mut body, scalar, ValueType.Concrete(Scalar.Bool), item.span)
            let literal = literal_condition(context.source, condition)
            let _ = try expression(context, mut body, child(parsed, item, 1),
                reachable && scalar.is_present() && literal != present(false))
            if scalar.is_present() && literal != present(true) { present(ValueType.Concrete(Scalar.Unit)) } else { none }
        },
        NodeKind.If => {
            let condition = child(parsed, item, 0)
            let condition_span = node(parsed, condition).span
            let condition_type = try expression(context, mut body, condition, reachable)
            if let present(value) = condition_type, !body.integers.unify(value, ValueType.Concrete(Scalar.Bool)) {
                throw CheckError(CheckPhase.Type, condition_span, "if condition must be bool")
            }
            let consequent = child(parsed, item, 1)
            let consequent_span = node(parsed, consequent).span
            let literal = literal_condition(context.source, condition)
            let live = reachable && condition_type.is_present()
            let result = try expression(context, mut body, consequent, live && literal != present(false))
            let alternative = if item.children.end - item.children.begin == 3u32 {
                try expression(context, mut body, child(parsed, item, 2), live && literal != present(true))
            } else { present(ValueType.Concrete(Scalar.Unit)) }
            if let present(left) = result, let present(right) = alternative, !body.integers.unify(left, right) {
                throw CheckError(CheckPhase.Type, consequent_span, "if branches must have the same result type")
            }
            if condition_type.is_none() || (literal == present(true) && result.is_none()) ||
                (literal == present(false) && alternative.is_none()) { none }
            else if result.is_present() { result }
            else { alternative }
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
            var completes = true
            for index in 0usize..signature.parameters.len() {
                let argument = child(parsed, arguments, index as u32)
                let span = node(parsed, argument).span
                let actual = try expression(context, mut body, argument, reachable && completes)
                if let present(value) = actual, !body.integers.unify(value, ValueType.Concrete(signature.parameters[index])) {
                    throw CheckError(CheckPhase.Type, span, "argument does not match the parameter type")
                }
                completes = completes && actual.is_present()
            }
            binding = present(Binding.Function(FunctionId(module_index, id)))
            if completes { present(ValueType.Concrete(signature.result)) } else { none }
        },
        NodeKind.Binary => {
            let mark = body.binary.len()
            var left = child(parsed, item, 0)
            while node(parsed, left).kind.is(NodeKind.Binary) {
                let next = child(parsed, node(parsed, left), 0)
                body.binary.push(left)
                left = next
            }
            var lhs = try expression(context, mut body, left, reachable)
            while body.binary.len() > mark {
                let nested = body.binary.pop().or_panic()
                let binary = node(parsed, nested)
                lhs = try binary_rhs(context, mut body, binary, lhs, reachable)
                body.expressions[nested.index as usize] = present(Fact(lhs, none))
            }
            try binary_rhs(context, mut body, item, lhs, reachable)
        },
        _ => { throw unsupported(item.span) }
    }
    body.expressions[id.index as usize] = present(Fact(scalar, binding))
    scalar
}

fn binary_rhs<region r>(read context: Context<region r>, mut body: Body, item: SyntaxNode,
    lhs: ValueType?, reachable: bool): ValueType? throws CheckError {
    let bytes = context.source.bytes.as_slice()
    let parsed = read context.source.syntax
    let operator = try operator_span(parsed, item)
    let spelling = read bytes[operator.begin as usize..operator.end as usize]
    let logical = spelling == b"&&" || spelling == b"||"
    let literal = if logical { literal_condition(context.source, child(parsed, item, 0)) } else { none }
    let skips = literal == present(spelling == b"||")
    let rhs = try expression(context, mut body, child(parsed, item, 1), reachable && lhs.is_present() && !skips)
    if logical {
        let left_bool = if let present(left) = lhs { body.integers.unify(left, ValueType.Concrete(Scalar.Bool)) } else { true }
        let right_bool = if let present(right) = rhs { body.integers.unify(right, ValueType.Concrete(Scalar.Bool)) } else { true }
        if !left_bool || !right_bool {
            throw CheckError(CheckPhase.Type, operator, "logical operands must both be bool")
        }
        if literal.is_present() && !skips && rhs.is_none() { none } else { lhs }
    } else if spelling == b"==" || spelling == b"!=" || spelling == b"<" ||
              spelling == b"<=" || spelling == b">" || spelling == b">=" {
        if let present(left) = lhs, let present(right) = rhs {
            if !body.integers.unify(left, right) {
                throw CheckError(CheckPhase.Type, operator, "comparison operands must have the same type")
            }
            return present(ValueType.Concrete(Scalar.Bool))
        }
        none
    } else if spelling == b"+" || spelling == b"-" || spelling == b"*" ||
              spelling == b"/" || spelling == b"%" {
        if let present(left) = lhs, let present(scalar) = body.integers.known(left), scalar.integer_width() == 0u32 {
            throw CheckError(CheckPhase.Type, operator, "arithmetic operands must be integers of the same type")
        }
        if let present(right) = rhs, let present(scalar) = body.integers.known(right), scalar.integer_width() == 0u32 {
            throw CheckError(CheckPhase.Type, operator, "arithmetic operands must be integers of the same type")
        }
        if let present(left) = lhs, let present(right) = rhs {
            if !body.integers.unify(left, right) {
                throw CheckError(CheckPhase.Type, operator, "arithmetic operands must be integers of the same type")
            }
            return lhs
        }
        none
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
    var body = Body(List<Fact?>(), IntegerTypes(List<IntegerType>()), List<(NodeId, u128)>(),
        Map<List<u8>, usize>(), List<usize>(), List<Local>(), List<Shadow>(), List<NodeId>(), 0usize)
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
        let result = try expression(context, mut body, function.body, true)
        if let present(value) = result, !body.integers.unify(value, ValueType.Concrete(function.result)) {
            throw CheckError(CheckPhase.Type, node(parsed, function.body).span, "function body does not match its declared result type")
        }
        counts.push(body.local_count)
    }
    var integers = take body.integers
    let drafts = take body.expressions
    let literals = take body.literals
    var expressions = List<Expression?>()
    expressions.reserve_exact(parsed.nodes.len())
    for draft in take drafts {
        let expression = if let present(fact) = draft {
            let scalar = if let present(value) = fact.scalar {
                if let present(known) = integers.known(value) { present(known) } else { present(Scalar.I32) }
            } else { none }
            present(Expression(scalar, fact.binding, none))
        } else { none }
        expressions.push(expression)
    }
    for (id, magnitude) in take literals {
        let expression = expressions[id.index as usize]
        let present(fact) = expression else { panic("missing checked literal") }
        let present(scalar) = fact.scalar else { panic("missing checked literal type") }
        let width = if scalar.is(Scalar.I32) { 31u32 } else { scalar.integer_width() }
        if magnitude >> width != 0u128 {
            let message = match scalar {
                Scalar.I32 => "integer literal is outside the i32 range",
                Scalar.U8 => "integer literal is outside the u8 range",
                Scalar.U32 => "integer literal is outside the u32 range",
                Scalar.Usize => "integer literal is outside the usize range",
                _ => panic("literal inferred as a non-integer")
            }
            throw CheckError(CheckPhase.Type, node(parsed, id).span, message)
        }
        expressions[id.index as usize] = present(Expression(present(scalar), fact.binding, present(magnitude as u64)))
    }
    (take expressions, take counts)
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
    let present(actual) = fact.scalar else { panic("expected a scalar binding fact") }
    assert(index == expected && actual.is(scalar), "wrong local identity or type")
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
    let present(scalar) = discard_fact.scalar else { panic("discard did not complete") }
    assert(discard_fact.binding.is_none() && scalar.is(Scalar.Unit), "discard introduced a local")
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
