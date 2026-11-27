import alloc.vec.{ List, with_capacity }
import mettle_foundation.Span
import mettle_frontend.{ Binding, CheckedModule, ModuleLink, SourceModule }
import mettle_frontend as frontend
import mettle_ir.{ Arithmetic, Block, Comparison, Edge, Function, FunctionId, Instruction, InvalidIr, Module, Operation, Program, Terminator, VerifiedProgram, verify }
import mettle_syntax.{ NodeId, NodeKind, Parsed, SyntaxNode }
import mettle_types.Scalar

pub copy enum LoweringError { Inconsistent(Span), Unsupported(Span), Invalid(InvalidIr) }

fn child(read parsed: Parsed, parent: SyntaxNode, index: usize): NodeId {
    parsed.children[parent.children.begin as usize + index]
}

copy type Value { slot: usize; scalar: Scalar }
copy type LocalValue { id: usize; value: Value }
type PendingBlock {
    parameters: List<Scalar>
    instructions: List<Instruction>
    terminator: Terminator?
    span: Span
}

copy enum Work {
    Evaluate(NodeId), Binary(NodeId), Call(NodeId, usize), Chain(NodeId, u32),
    SelectIf(NodeId), SelectShort(NodeId, bool), SelectChain(NodeId, u32), WhileBody(NodeId, usize),
    Bind(NodeId), Assign(NodeId), Return(Span), LeaveScope(usize),
    Unit(Span), Boolean(bool, Span), Discard(Span), Enter(usize), Jump(usize)
}

type Builder {
    blocks: List<PendingBlock>
    current: usize
    values: List<Value>
    locals: List<LocalValue>
    local_indices: List<usize?>
    work: List<Work>
}

extend Builder {
    mut fn add_block(take parameters: List<Scalar>, span: Span): usize {
        let index = self.blocks.len()
        self.blocks.push(PendingBlock(take parameters, List<Instruction>(), none, span))
        index
    }

    mut fn continuation(tail: Scalar?, span: Span): usize {
        var parameters = with_capacity<Scalar>(self.locals.len() + self.values.len() +
            (if tail.is_present() { 1usize } else { 0usize }))
        for binding in self.locals.as_slice() { parameters.push(binding.value.scalar) }
        for value in self.values.as_slice() { parameters.push(value.scalar) }
        if let present(scalar) = tail { parameters.push(scalar) }
        self.add_block(take parameters, span)
    }

    mut fn enter(index: usize): Unit {
        self.current = index
        self.values.clear()
        for position in 0usize..self.locals.len() { self.locals[position].value.slot = position }
        let parameters = read self.blocks[index].parameters
        for position in self.locals.len()..parameters.len() {
            self.values.push(Value(position, parameters[position]))
        }
    }

    fn local_position(id: usize, span: Span): usize throws LoweringError {
        if id >= self.local_indices.len() { throw LoweringError.Inconsistent(span) }
        let present(position) = self.local_indices[id] else { throw LoweringError.Inconsistent(span) }
        position
    }

    mut fn bind(id: usize, value: Value, span: Span): Unit throws LoweringError {
        if id >= self.local_indices.len() || self.local_indices[id].is_present() {
            throw LoweringError.Inconsistent(span)
        }
        self.local_indices[id] = present(self.locals.len())
        self.locals.push(LocalValue(id, value))
    }

    mut fn leave_scope(size: usize): Unit {
        while self.locals.len() > size {
            let binding = self.locals.pop().or_panic()
            self.local_indices[binding.id] = none
        }
    }

    mut fn emit(take operation: Operation, scalar: Scalar, span: Span): Unit {
        let block = mut self.blocks[self.current]
        let slot = block.parameters.len() + block.instructions.len()
        block.instructions.push(Instruction(take operation, span))
        self.values.push(Value(slot, scalar))
    }

    mut fn pop_value(span: Span): Value throws LoweringError {
        let present(value) = self.values.pop() else { throw LoweringError.Inconsistent(span) }
        value
    }

    fn edge(index: usize): Edge {
        var arguments = with_capacity<usize>(self.locals.len() + self.values.len())
        for binding in self.locals.as_slice() { arguments.push(binding.value.slot) }
        for value in self.values.as_slice() { arguments.push(value.slot) }
        Edge(index, take arguments)
    }

    mut fn close(take terminator: Terminator): Unit {
        self.blocks[self.current].terminator = present(take terminator)
    }

    mut fn branch(condition: usize, yes: usize, no: usize): Unit {
        let true_edge = self.edge(yes)
        let false_edge = self.edge(no)
        self.close(Terminator.Branch(condition, take true_edge, take false_edge))
    }

    mut fn select(yes: Work, no: Work, result: Scalar?, span: Span): Unit throws LoweringError {
        let condition = try self.pop_value(span)
        let consequent = self.continuation(none, span)
        let alternative = self.continuation(none, span)
        self.branch(condition.slot, consequent, alternative)
        let joined = if result.is_present() {
            let block = self.continuation(result, span)
            self.work.push(Work.Enter(block))
            self.work.push(Work.Jump(block))
            present(block)
        } else { none }
        self.work.push(no)
        self.work.push(Work.Enter(alternative))
        if let present(block) = joined { self.work.push(Work.Jump(block)) }
        self.work.push(yes)
        self.work.push(Work.Enter(consequent))
    }
}

fn binary(read spelling: [u8], left: Value, right: Value, span: Span): Operation throws LoweringError {
    let a = left.slot
    let b = right.slot
    let scalar = left.scalar
    if spelling.len() == 2usize && spelling[1usize] == b'=' {
        let comparison = match spelling[0usize] {
            b'=' => Comparison.Equal, b'!' => Comparison.NotEqual,
            b'<' => Comparison.LessEqual, b'>' => Comparison.GreaterEqual,
            _ => { throw LoweringError.Unsupported(span) }
        }
        return Operation.Compare(comparison, scalar, a, b)
    }
    if spelling.len() != 1usize { throw LoweringError.Unsupported(span) }
    if spelling[0usize] == b'<' { return Operation.Compare(Comparison.Less, scalar, a, b) }
    if spelling[0usize] == b'>' { return Operation.Compare(Comparison.Greater, scalar, a, b) }
    let operation = match spelling[0usize] {
        b'+' => Arithmetic.Add, b'-' => Arithmetic.Subtract, b'*' => Arithmetic.Multiply,
        b'/' => Arithmetic.Divide, b'%' => Arithmetic.Remainder,
        _ => { throw LoweringError.Unsupported(span) }
    }
    Operation.Arithmetic(operation, a, b)
}

fn operator(read source: SourceModule, item: SyntaxNode): read [u8] from source throws LoweringError {
    let present(token) = item.operation else { throw LoweringError.Inconsistent(item.span) }
    let span = source.syntax.tokens[token as usize].span
    read source.bytes.as_slice()[span.begin as usize..span.end as usize]
}

fn evaluate(mut builder: Builder, read source: SourceModule, read checked: CheckedModule,
    id: NodeId): Unit throws LoweringError {
    let parsed = read source.syntax
    let item = parsed.nodes[id.index as usize]
    let span = item.span
    let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(span) }
    match item.kind {
        NodeKind.Group => builder.work.push(Work.Evaluate(child(parsed, item, 0))),
        NodeKind.Block => {
            let first = item.children.begin
            let last = item.children.end
            var position = last
            builder.work.push(Work.LeaveScope(builder.locals.len()))
            if first == last || parsed.nodes[parsed.children[(last - 1u32) as usize].index as usize].semicolon {
                builder.work.push(Work.Unit(span))
            }
            while position > first {
                position -= 1u32
                let statement = parsed.children[position as usize]
                if position + 1u32 != last || parsed.nodes[statement.index as usize].semicolon {
                    builder.work.push(Work.Discard(span))
                }
                builder.work.push(Work.Evaluate(statement))
            }
        },
        NodeKind.If => {
            builder.work.push(Work.SelectIf(id))
            builder.work.push(Work.Evaluate(child(parsed, item, 0)))
        },
        NodeKind.While => {
            let header = builder.continuation(none, span)
            let edge = builder.edge(header)
            builder.close(Terminator.Jump(take edge))
            builder.enter(header)
            builder.work.push(Work.WhileBody(id, header))
            builder.work.push(Work.Evaluate(child(parsed, item, 0)))
        },
        NodeKind.Conditions => builder.work.push(Work.Chain(id, item.children.begin)),
        NodeKind.Binary => {
            let spelling = try operator(source, item)
            let right = child(parsed, item, 1)
            if spelling == b"&&" || spelling == b"||" {
                builder.work.push(Work.SelectShort(id, spelling == b"&&"))
            } else {
                builder.work.push(Work.Binary(id))
                builder.work.push(Work.Evaluate(right))
            }
            builder.work.push(Work.Evaluate(child(parsed, item, 0)))
        },
        NodeKind.Call => {
            let arguments = parsed.nodes[child(parsed, item, 1).index as usize]
            var position = arguments.children.end
            builder.work.push(Work.Call(id, (position - arguments.children.begin) as usize))
            while position > arguments.children.begin {
                position -= 1u32
                builder.work.push(Work.Evaluate(parsed.children[position as usize]))
            }
        },
        NodeKind.Integer => {
            var integer = 0i32
            for digit in source.bytes.as_slice()[span.begin as usize..span.end as usize] {
                if digit != b'_' { integer = integer * 10i32 + (digit - b'0') as i32 }
            }
            builder.emit(Operation.Integer(integer), Scalar.I32, span)
        },
        NodeKind.Boolean => builder.emit(Operation.Boolean(source.bytes[span.begin as usize] == b't'), Scalar.Bool, span),
        NodeKind.Unit => builder.emit(Operation.Unit, Scalar.Unit, span),
        NodeKind.Binding => {
            builder.work.push(Work.Bind(id))
            builder.work.push(Work.Evaluate(parsed.children[(item.children.end - 1u32) as usize]))
        },
        NodeKind.Assign => {
            builder.work.push(Work.Assign(id))
            builder.work.push(Work.Evaluate(child(parsed, item, 1)))
        },
        NodeKind.Return => {
            builder.work.push(Work.Return(span))
            if item.children.begin == item.children.end {
                builder.work.push(Work.Unit(span))
            } else {
                builder.work.push(Work.Evaluate(child(parsed, item, 0)))
            }
        },
        NodeKind.Name => {
            match fact.binding {
                present(Binding.Parameter(parameter)) => {
                    let present(scalar) = fact.scalar else { throw LoweringError.Inconsistent(span) }
                    builder.emit(Operation.Parameter(parameter), scalar, span)
                },
                present(Binding.Local(id)) => {
                    let position = try builder.local_position(id, span)
                    let value = builder.locals[position].value
                    builder.values.push(value)
                },
                _ => { throw LoweringError.Inconsistent(span) }
            }
        },
        _ => { throw LoweringError.Unsupported(span) }
    }
}

fn lower_function(read source: SourceModule, read checked: CheckedModule, read signature: frontend.Function): Function throws LoweringError {
    let parsed = read source.syntax
    let span = parsed.nodes[signature.body.index as usize].span
    var local_indices = List<usize?>()
    local_indices.resize(signature.local_count, none)
    var builder = Builder(List<PendingBlock>(), 0usize, List<Value>(), List<LocalValue>(), take local_indices, List<Work>())
    let _ = builder.add_block(List<Scalar>(), span)
    builder.work.push(Work.Evaluate(signature.body))
    while let present(task) = builder.work.pop() {
        if builder.blocks[builder.current].terminator.is_present() {
            match task {
                Work.Enter(block) => builder.enter(block),
                Work.LeaveScope(size) => builder.leave_scope(size),
                _ => {}
            }
            continue
        }
        match task {
            Work.Evaluate(id) => { try evaluate(mut builder, source, checked, id) },
            Work.Unit(at) => builder.emit(Operation.Unit, Scalar.Unit, at),
            Work.Boolean(value, at) => builder.emit(Operation.Boolean(value), Scalar.Bool, at),
            Work.Discard(at) => { let _ = try builder.pop_value(at) },
            Work.LeaveScope(size) => builder.leave_scope(size),
            Work.Return(at) => {
                let returned = try builder.pop_value(at)
                builder.close(Terminator.Return(returned.slot))
            },
            Work.Bind(id) => {
                let at = parsed.nodes[id.index as usize].span
                let value = try builder.pop_value(at)
                let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(at) }
                match fact.binding {
                    present(Binding.Local(slot)) => { try builder.bind(slot, value, at) },
                    none => {},
                    _ => { throw LoweringError.Inconsistent(at) }
                }
                builder.emit(Operation.Unit, Scalar.Unit, at)
            },
            Work.Assign(id) => {
                let item = parsed.nodes[id.index as usize]
                let at = item.span
                let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(at) }
                let present(Binding.Local(slot)) = fact.binding else { throw LoweringError.Inconsistent(at) }
                let position = try builder.local_position(slot, at)
                let right = try builder.pop_value(at)
                let spelling = try operator(source, item)
                let value = if spelling == b"=" { right } else {
                    let left = builder.locals[position].value
                    let operation = try binary(read spelling[0usize..spelling.len() - 1usize], left, right, at)
                    builder.emit(take operation, left.scalar, at)
                    try builder.pop_value(at)
                }
                builder.locals[position].value = value
                builder.emit(Operation.Unit, Scalar.Unit, at)
            },
            Work.Enter(block) => builder.enter(block),
            Work.Jump(block) => {
                let edge = builder.edge(block)
                builder.close(Terminator.Jump(take edge))
            },
            Work.Binary(id) => {
                let item = parsed.nodes[id.index as usize]
                let right = try builder.pop_value(item.span)
                let left = try builder.pop_value(item.span)
                let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(item.span) }
                let present(scalar) = fact.scalar else { throw LoweringError.Inconsistent(item.span) }
                let operation = try binary(try operator(source, item), left, right, item.span)
                builder.emit(take operation, scalar, item.span)
            },
            Work.Call(id, count) => {
                let item = parsed.nodes[id.index as usize]
                let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(item.span) }
                let present(scalar) = fact.scalar else { throw LoweringError.Inconsistent(item.span) }
                let present(Binding.Function(target)) = fact.binding else { throw LoweringError.Inconsistent(item.span) }
                var arguments = List<usize>()
                arguments.resize(count, 0usize)
                var index = count
                while index > 0usize {
                    index -= 1usize
                    arguments[index] = (try builder.pop_value(item.span)).slot
                }
                builder.emit(Operation.Call(FunctionId(target.module_index, target.index), take arguments), scalar, item.span)
            },
            Work.Chain(id, position) => {
                let item = parsed.nodes[id.index as usize]
                if position >= item.children.end { throw LoweringError.Inconsistent(item.span) }
                if position + 1u32 < item.children.end {
                    builder.work.push(Work.SelectChain(id, position + 1u32))
                }
                builder.work.push(Work.Evaluate(parsed.children[position as usize]))
            },
            Work.SelectIf(id) => {
                let item = parsed.nodes[id.index as usize]
                let present(fact) = checked.expressions[id.index as usize] else { throw LoweringError.Inconsistent(item.span) }
                let yes = Work.Evaluate(child(parsed, item, 1))
                let no = if item.children.end - item.children.begin == 3u32 {
                    Work.Evaluate(child(parsed, item, 2))
                } else { Work.Unit(item.span) }
                if let present(literal) = frontend.literal_condition(source, child(parsed, item, 0)) {
                    let _ = try builder.pop_value(item.span)
                    builder.work.push(if literal { yes } else { no })
                } else { try builder.select(yes, no, fact.scalar, item.span) }
            },
            Work.WhileBody(id, header) => {
                let item = parsed.nodes[id.index as usize]
                let condition = try builder.pop_value(item.span)
                if let present(literal) = frontend.literal_condition(source, child(parsed, item, 0)) {
                    if !literal {
                        builder.emit(Operation.Unit, Scalar.Unit, item.span)
                        continue
                    }
                } else {
                    let body_block = builder.continuation(none, item.span)
                    let exit_block = builder.continuation(none, item.span)
                    builder.branch(condition.slot, body_block, exit_block)
                    builder.work.push(Work.Unit(item.span))
                    builder.work.push(Work.Enter(exit_block))
                    builder.enter(body_block)
                }
                builder.work.push(Work.Jump(header))
                builder.work.push(Work.Discard(item.span))
                builder.work.push(Work.Evaluate(child(parsed, item, 1)))
            },
            Work.SelectShort(id, and) => {
                let item = parsed.nodes[id.index as usize]
                let right = child(parsed, item, 1)
                let at = item.span
                if let present(literal) = frontend.literal_condition(source, child(parsed, item, 0)) {
                    if literal == and {
                        let _ = try builder.pop_value(at)
                        builder.work.push(Work.Evaluate(right))
                    }
                } else if and { try builder.select(Work.Evaluate(right), Work.Boolean(false, at), present(Scalar.Bool), at) }
                else { try builder.select(Work.Boolean(true, at), Work.Evaluate(right), present(Scalar.Bool), at) }
            },
            Work.SelectChain(id, position) => {
                let at = parsed.nodes[id.index as usize].span
                if let present(literal) = frontend.literal_condition(source, parsed.children[(position - 1u32) as usize]) {
                    if literal {
                        let _ = try builder.pop_value(at)
                        builder.work.push(Work.Chain(id, position))
                    }
                } else { try builder.select(Work.Chain(id, position), Work.Boolean(false, at), present(Scalar.Bool), at) }
            },
        }
    }
    if !builder.blocks[builder.current].terminator.is_present() {
        let returned = try builder.pop_value(span)
        if !builder.values.is_empty() { throw LoweringError.Inconsistent(span) }
        builder.close(Terminator.Return(returned.slot))
    }
    if !builder.locals.is_empty() { throw LoweringError.Inconsistent(span) }
    var blocks = List<Block>()
    for pending in take builder.blocks {
        let present(terminator) = take pending.terminator else { throw LoweringError.Inconsistent(pending.span) }
        blocks.push(Block(take pending.parameters, take pending.instructions, take terminator, pending.span))
    }
    var parameters = List<Scalar>()
    for scalar in signature.parameters.as_slice() { parameters.push(scalar) }
    Function(take parameters, signature.result, take blocks, span)
}

pub fn lower(read sources: List<SourceModule>, read checked: List<CheckedModule>): VerifiedProgram throws LoweringError {
    if sources.len() != checked.len() { throw LoweringError.Inconsistent(Span(0, 0, 0)) }
    var modules = List<Module>()
    var entry: FunctionId? = none
    for index in 0usize..sources.len() {
        let source = read sources[index]
        let facts = read checked[index]
        if facts.expressions.len() != source.syntax.nodes.len() {
            throw LoweringError.Inconsistent(Span(0, 0, 0))
        }

        if let present(selected) = facts.entry {
            if entry.is_present() { throw LoweringError.Inconsistent(Span(0, 0, 0)) }
            entry = present(FunctionId(index, selected))
        }
        var functions = List<Function>()
        for signature in facts.functions.as_slice() {
            let body_index = signature.body.index as usize
            if body_index >= facts.expressions.len() {
                throw LoweringError.Inconsistent(Span(0, 0, 0))
            }
            functions.push(try lower_function(source, facts, signature))
        }
        modules.push(Module(take functions))
    }
    match take capture verify(Program(take modules, entry)) {
        success(verified) => verified,
        failure(error) => throw LoweringError.Invalid(error)
    }
}

@test
fn cross_module_scalar_call(): Unit throws LoweringError {
    let app = "fn main(): i32 { dependency.double(21) - 42 }".as_bytes()
    let library = "pub fn double(n: i32): i32 { n * 2 }".as_bytes()
    var sources = List<SourceModule>()
    var mounts = List<alloc.hash_map.Map<List<u8>, usize>>()
    var dependencies = alloc.hash_map.Map<List<u8>, usize>()
    let _ = dependencies.insert(b"dependency".to_vec(), 1usize)
    mounts.push(take dependencies)
    mounts.push(alloc.hash_map.Map<List<u8>, usize>())
    for bytes in [app, library] {
        let index = sources.len()
        let syntax = mettle_syntax.parse(bytes, index as u32)
        let success(items) = capture frontend.active_items(bytes, syntax, List<alloc.string.String>()) else {
            core.panic.panic("could not select fixture declarations")
        }
        sources.push(SourceModule(bytes.to_vec(), take syntax, alloc.hash_map.Map<List<u8>, ModuleLink>(), index, none, take items))
    }
    let success(checked) = capture frontend.check_modules(sources, mounts, true) else {
        core.panic.panic("scalar fixture did not check")
    }
    let verified = try lower(sources, checked)
    let program = verified.program()
    let main = read program.modules[0].functions[0].blocks[0]
    let returned = match read main.terminator {
        Terminator.Return(value) => value,
        _ => core.panic.panic("expected a direct return")
    }
    let (call, right) = match read main.instructions[returned].operation {
        Operation.Arithmetic(Arithmetic.Subtract, call, right) => (call, right),
        _ => core.panic.panic("expected subtraction at the return")
    }
    match read main.instructions[right].operation {
        Operation.Integer(42) => (),
        _ => core.panic.panic("expected integer right operand 42")
    }
    let argument = match read main.instructions[call].operation {
        Operation.Call(target, operands) => {
            assert(target.module_index == 1 && target.index == 0, "call lost its module identity")
            assert(operands.len() == 1, "incorrect argument count")
            operands[0]
        },
        _ => core.panic.panic("expected a resolved call")
    }
    match read main.instructions[argument].operation {
        Operation.Integer(21) => (),
        _ => core.panic.panic("expected integer argument 21")
    }
}
