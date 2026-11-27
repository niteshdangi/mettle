import alloc.vec.List
import mettle_foundation.Span
import mettle_types.Scalar

pub copy type FunctionId { pub module_index: usize; pub index: usize }

pub copy enum Arithmetic { Add, Subtract, Multiply, Divide, Remainder }
pub copy enum Comparison { Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual }
pub copy enum Bitwise { And, Or, Xor }
pub copy enum Shift { Left, Right }

pub enum Operation {
    Integer(Scalar, u64), Boolean(bool), Unit,
    Parameter(usize),
    Arithmetic(Arithmetic, Scalar, usize, usize),
    Bitwise(Bitwise, Scalar, usize, usize),
    Shift(Shift, Scalar, Scalar, usize, usize),
    Compare(Comparison, Scalar, usize, usize),
    Cast(Scalar, Scalar, usize),
    Call(FunctionId, List<usize>)
}

pub type Instruction { pub operation: Operation; pub span: Span }
pub type Edge { pub block: usize; pub arguments: List<usize> }
pub enum Terminator { Return(usize), Jump(Edge), Branch(usize, Edge, Edge) }
pub type Block {
    pub parameters: List<Scalar>
    pub instructions: List<Instruction>
    pub terminator: Terminator
    pub span: Span
}
pub type Function {
    pub parameters: List<Scalar>
    pub result: Scalar
    pub blocks: List<Block>
    pub span: Span
}
pub type Module { pub functions: List<Function> }
pub type Program { pub modules: List<Module>; pub entry: FunctionId? }
pub type VerifiedProgram { program: Program }

extend VerifiedProgram {
    pub fn program(): read Program from self { read self.program }
}

pub copy enum Violation {
    Entry, Parameter, Operand, CallTarget, ArgumentCount, ArgumentType,
    Return, BranchCondition, BranchTarget, EdgeArguments, UnreachableBlock
}
pub copy type InvalidIr { pub violation: Violation; pub span: Span }

fn lookup(read program: Program, id: FunctionId): (read Function from program)? {
    if id.module_index >= program.modules.len() { return none }
    let module_ir = read program.modules[id.module_index]
    if id.index >= module_ir.functions.len() { return none }
    present(read module_ir.functions[id.index])
}

fn verify_edge(read function: Function, read values: List<Scalar>, read edge: Edge, span: Span): Unit throws InvalidIr {
    if edge.block == 0usize || edge.block >= function.blocks.len() {
        throw InvalidIr(Violation.BranchTarget, span)
    }
    let parameters = read function.blocks[edge.block].parameters
    if edge.arguments.len() != parameters.len() { throw InvalidIr(Violation.EdgeArguments, span) }
    for index in 0usize..parameters.len() {
        let argument = edge.arguments[index]
        if argument >= values.len() || !values[argument].is(parameters[index]) {
            throw InvalidIr(Violation.EdgeArguments, span)
        }
    }
}

fn verify_integer_operands(read values: List<Scalar>, scalar: Scalar, count: Scalar,
    left: usize, right: usize, span: Span): Scalar throws InvalidIr {
    if left >= values.len() || right >= values.len() ||
        scalar.integer_width() == 0u32 || count.integer_width() == 0u32 ||
        !values[left].is(scalar) || !values[right].is(count) {
        throw InvalidIr(Violation.Operand, span)
    }
    scalar
}

fn verify_block(read program: Program, read function: Function, read block: Block): Unit throws InvalidIr {
    var values = List<Scalar>()
    for parameter in block.parameters.as_slice() { values.push(parameter) }
    for instruction in block.instructions.as_slice() {
        let span = instruction.span
        let result = match read instruction.operation {
            Operation.Integer(scalar, bits) => {
                let width = scalar.integer_width()
                if width == 0u32 || (width < 64u32 && bits >> width != 0u64) {
                    throw InvalidIr(Violation.Operand, span)
                }
                scalar
            },
            Operation.Boolean(_) => Scalar.Bool,
            Operation.Unit => Scalar.Unit,
            Operation.Parameter(index) => {
                if index >= function.parameters.len() { throw InvalidIr(Violation.Parameter, span) }
                function.parameters[index]
            },
            Operation.Arithmetic(_, scalar, left, right) =>
                try verify_integer_operands(values, scalar, scalar, left, right, span),
            Operation.Bitwise(_, scalar, left, right) =>
                try verify_integer_operands(values, scalar, scalar, left, right, span),
            Operation.Shift(_, scalar, count, left, right) =>
                try verify_integer_operands(values, scalar, count, left, right, span),
            Operation.Cast(source, target, operand) => {
                if operand >= values.len() || !values[operand].is(source) ||
                    source.integer_width() == 0u32 || target.integer_width() == 0u32 {
                    throw InvalidIr(Violation.Operand, span)
                }
                target
            },
            Operation.Compare(_, scalar, left, right) => {
                if left >= values.len() || right >= values.len() ||
                    !values[left].is(scalar) || !values[right].is(scalar) {
                    throw InvalidIr(Violation.Operand, span)
                }
                Scalar.Bool
            },
            Operation.Call(target, arguments) => {
                let present(callee) = lookup(program, target) else { throw InvalidIr(Violation.CallTarget, span) }
                if arguments.len() != callee.parameters.len() { throw InvalidIr(Violation.ArgumentCount, span) }
                for index in 0usize..arguments.len() {
                    let argument = arguments[index]
                    if argument >= values.len() || !values[argument].is(callee.parameters[index]) {
                        throw InvalidIr(Violation.ArgumentType, span)
                    }
                }
                callee.result
            }
        }
        values.push(result)
    }
    match read block.terminator {
        Terminator.Return(value) => {
            if value >= values.len() || !values[value].is(function.result) {
                throw InvalidIr(Violation.Return, block.span)
            }
        },
        Terminator.Jump(edge) => { try verify_edge(function, values, edge, block.span) },
        Terminator.Branch(value, yes, no) => {
            if value >= values.len() || !values[value].is(Scalar.Bool) {
                throw InvalidIr(Violation.BranchCondition, block.span)
            }
            if yes.block == no.block { throw InvalidIr(Violation.BranchTarget, block.span) }
            try verify_edge(function, values, yes, block.span)
            try verify_edge(function, values, no, block.span)
        }
    }
}

fn verify_function(read program: Program, read function: Function): Unit throws InvalidIr {
    if function.blocks.is_empty() || !function.blocks[0usize].parameters.is_empty() {
        throw InvalidIr(Violation.Entry, function.span)
    }
    var pending = List<usize>()
    var visited = List<bool>()
    visited.resize(function.blocks.len(), false)
    pending.push(0usize)
    var count = 0usize
    while let present(index) = pending.pop() {
        if visited[index] { continue }
        visited[index] = true
        count += 1usize
        let block = read function.blocks[index]
        try verify_block(program, function, block)
        match read block.terminator {
            Terminator.Return(_) => {},
            Terminator.Jump(edge) => pending.push(edge.block),
            Terminator.Branch(_, yes, no) => {
                pending.push(no.block)
                pending.push(yes.block)
            }
        }
    }
    if count != function.blocks.len() {
        for index in 0usize..visited.len() {
            if !visited[index] { throw InvalidIr(Violation.UnreachableBlock, function.blocks[index].span) }
        }
    }
}

pub fn verify(take program: Program): VerifiedProgram throws InvalidIr {
    if let present(entry) = program.entry {
        let present(function) = lookup(program, entry) else {
            throw InvalidIr(Violation.Entry, Span(0, 0, 0))
        }
        if !function.parameters.is_empty() || !function.result.is(Scalar.I32) {
            throw InvalidIr(Violation.Entry, function.span)
        }
    }
    for module_ir in program.modules.as_slice() {
        for function in module_ir.functions.as_slice() {
            try verify_function(program, function)
        }
    }
    VerifiedProgram(take program)
}

@test
fn reject_forward_value(): Unit {
    let span = Span(1, 2, 3)
    var instructions = List<Instruction>()
    instructions.push(Instruction(Operation.Arithmetic(Arithmetic.Add, Scalar.I32, 1, 1), span))
    instructions.push(Instruction(Operation.Integer(Scalar.I32, 2), span))
    var blocks = List<Block>()
    blocks.push(Block(List<Scalar>(), take instructions, Terminator.Return(0), span))
    var functions = List<Function>()
    functions.push(Function(List<Scalar>(), Scalar.I32, take blocks, span))
    var modules = List<Module>()
    modules.push(Module(take functions))
    let failure(error) = capture verify(Program(take modules, none)) else {
        core.panic.panic("verifier admitted an instruction using a future value")
    }

    let Violation.Operand = error.violation else { core.panic.panic("incorrect IR rejection reason") }
    assert(error.span.source == 1 && error.span.begin == 2,
        "invalid operand lost its reason or source position")
}

@test
fn reject_cross_block_argument_type(): Unit {
    let span = Span(1, 2, 3)
    var start = List<Instruction>()
    start.push(Instruction(Operation.Boolean(true), span))
    var blocks = List<Block>()
    blocks.push(Block(List<Scalar>(), take start, Terminator.Jump(Edge(1, alloc.vec.from_array([0usize]))), span))
    blocks.push(Block(alloc.vec.from_array([Scalar.I32]), List<Instruction>(), Terminator.Return(0), span))
    var functions = List<Function>()
    functions.push(Function(List<Scalar>(), Scalar.I32, take blocks, span))
    var modules = List<Module>()
    modules.push(Module(take functions))
    let failure(error) = capture verify(Program(take modules, none)) else {
        core.panic.panic("verifier admitted a bool on an i32 block parameter edge")
    }
    let Violation.EdgeArguments = error.violation else { core.panic.panic("incorrect edge diagnostic") }
}

@test
fn reject_invalid_integer_representation(): Unit {
    let span = Span(1, 2, 3)
    for operation in alloc.vec.from_array([
        Operation.Integer(Scalar.U8, 256),
        Operation.Arithmetic(Arithmetic.Add, Scalar.U32, 0, 0),
        Operation.Shift(Shift.Left, Scalar.U8, Scalar.U32, 0, 0),
        Operation.Cast(Scalar.I32, Scalar.U32, 0),
        Operation.Cast(Scalar.U8, Scalar.Bool, 0)
    ]) {
        let instructions = alloc.vec.from_array([
            Instruction(Operation.Integer(Scalar.U8, 255), span),
            Instruction(take operation, span)
        ])
        let blocks = alloc.vec.from_array([Block(List<Scalar>(), take instructions, Terminator.Return(0), span)])
        let functions = alloc.vec.from_array([Function(List<Scalar>(), Scalar.U8, take blocks, span)])
        let failure(error) = capture verify(Program(alloc.vec.from_array([Module(take functions)]), none)) else {
            core.panic.panic("verifier admitted inconsistent integer IR")
        }
        let Violation.Operand = error.violation else { core.panic.panic("incorrect integer operand diagnostic") }
    }
}
