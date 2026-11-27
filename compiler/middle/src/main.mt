import alloc.vec.List
import mettle_foundation.Span
import mettle_frontend.{ Binding, CheckedModule, SourceModule }
import mettle_frontend as frontend
import mettle_ir.{ Arithmetic, Function, FunctionId, Instruction, InvalidIr, Module, Operation, Program, VerifiedProgram, verify }
import mettle_syntax.{ NodeId, NodeKind, Parsed, SyntaxNode }

pub copy enum LoweringError { Inconsistent(Span), Unsupported(Span), Invalid(InvalidIr) }

fn child(read parsed: Parsed, parent: SyntaxNode, index: usize): NodeId {
    parsed.children[parent.children.begin as usize + index]
}

fn operand(read values: List<usize?>, first: usize, id: NodeId, span: Span): usize throws LoweringError {
    let index = id.index as usize
    if index < first || index - first >= values.len() {
        throw LoweringError.Inconsistent(span)
    }
    let present(value) = values[index - first] else { throw LoweringError.Inconsistent(span) }
    value
}

fn emit(mut output: List<Instruction>, take operation: Operation, span: Span): usize {
    let index = output.len()
    output.push(Instruction(take operation, span))
    index
}

fn arithmetic(read spelling: [u8], span: Span): Arithmetic throws LoweringError {
    if spelling.len() != 1usize { throw LoweringError.Unsupported(span) }
    match spelling[0] {
        b'+' => Arithmetic.Add, b'-' => Arithmetic.Subtract, b'*' => Arithmetic.Multiply,
        b'/' => Arithmetic.Divide, b'%' => Arithmetic.Remainder,
        _ => throw LoweringError.Unsupported(span)
    }
}

fn lower_function(read source: SourceModule, read checked: CheckedModule, read signature: frontend.Function, first: usize): Function throws LoweringError {
    let parsed = read source.syntax
    let body_index = signature.body.index as usize
    let body = parsed.nodes[body_index]
    var instructions = List<Instruction>()
    var values = List<usize?>()
    for index in first..body_index + 1usize {
        let item = parsed.nodes[index]
        let span = item.span
        let present(fact) = checked.expressions[index] else { values.push(none); continue }
        if item.kind.is(NodeKind.Group) {
            values.push(present(try operand(values, first, child(parsed, item, 0), span)))
            continue
        }
        if item.kind.is(NodeKind.Block) && item.children.begin != item.children.end {
            let tail = parsed.children[item.children.end as usize - 1usize]
            if !parsed.nodes[tail.index as usize].semicolon {
                values.push(present(try operand(values, first, tail, span)))
                continue
            }
        }
        let operation = match item.kind {
            NodeKind.Integer => {
                var integer = 0i32
                for digit in source.bytes.as_slice()[span.begin as usize..span.end as usize] {
                    if digit != b'_' { integer = integer * 10i32 + (digit - b'0') as i32 }
                }
                Operation.Integer(integer)
            },
            NodeKind.Boolean => Operation.Boolean(source.bytes[span.begin as usize] == b't'),
            NodeKind.Unit | NodeKind.Block => Operation.Unit,
            NodeKind.Name => {
                let present(Binding.Parameter(parameter)) = fact.binding else { throw LoweringError.Inconsistent(span) }
                Operation.Parameter(parameter)
            },
            NodeKind.Binary => {
                let present(token) = item.operation else { throw LoweringError.Inconsistent(span) }
                let spelling = parsed.tokens[token as usize].span
                let operator = try arithmetic(read source.bytes.as_slice()[spelling.begin as usize..spelling.end as usize], spelling)
                Operation.Arithmetic(operator, try operand(values, first, child(parsed, item, 0), span),
                    try operand(values, first, child(parsed, item, 1), span))
            },
            NodeKind.Call => {
                let present(Binding.Function(target)) = fact.binding else { throw LoweringError.Inconsistent(span) }
                let arguments = parsed.nodes[child(parsed, item, 1).index as usize]
                var operands = List<usize>()
                for position in arguments.children.begin..arguments.children.end {
                    operands.push(try operand(values, first, parsed.children[position as usize], span))
                }
                Operation.Call(FunctionId(target.module_index, target.index), take operands)
            },
            _ => throw LoweringError.Unsupported(span)
        }
        values.push(present(emit(mut instructions, take operation, span)))
    }
    let returned = try operand(values, first, signature.body, body.span)
    var parameters = alloc.vec.new<mettle_types.Scalar>()
    for ty in signature.parameters.as_slice() { parameters.push(ty) }
    Function(take parameters, signature.result, take instructions, returned, body.span)
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
        var first = 0usize
        for signature in facts.functions.as_slice() {
            let body_index = signature.body.index as usize
            if body_index >= facts.expressions.len() || body_index < first {
                throw LoweringError.Inconsistent(Span(0, 0, 0))
            }
            functions.push(try lower_function(source, facts, signature, first))
            first = body_index + 1usize
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
        sources.push(SourceModule(bytes.to_vec(), take syntax, alloc.hash_map.Map<List<u8>, usize>(), index, take items))
    }
    let success(checked) = capture frontend.check_modules(sources, mounts, true) else {
        core.panic.panic("scalar fixture did not check")
    }
    let verified = try lower(sources, checked)
    let program = verified.program()
    let main = read program.modules[0].functions[0]
    let (call, right) = match read main.instructions[main.returned].operation {
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
