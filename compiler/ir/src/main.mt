import alloc.vec.List
import mettle_foundation.Span
import mettle_types.Scalar

pub copy type FunctionId { pub module_index: usize; pub index: usize }

pub copy enum Arithmetic { Add, Subtract, Multiply, Divide, Remainder }

pub enum Operation {
    Integer(i32), Boolean(bool), Unit,
    Parameter(usize),
    Arithmetic(Arithmetic, usize, usize),
    Call(FunctionId, List<usize>)
}

pub type Instruction { pub operation: Operation; pub span: Span }
pub type Function {
    pub parameters: List<Scalar>
    pub result: Scalar
    pub instructions: List<Instruction>
    pub returned: usize
    pub span: Span
}
pub type Module { pub functions: List<Function> }
pub type Program { pub modules: List<Module>; pub entry: FunctionId? }
pub type VerifiedProgram { program: Program }

extend VerifiedProgram {
    pub fn program(): read Program from self { read self.program }
}

pub copy enum Violation { Entry, Parameter, Operand, CallTarget, ArgumentCount, ArgumentType, Return }
pub copy type InvalidIr { pub violation: Violation; pub span: Span }

fn lookup(read program: Program, id: FunctionId): (read Function from program)? {
    if id.module_index >= program.modules.len() { return none }
    let module_ir = read program.modules[id.module_index]
    if id.index >= module_ir.functions.len() { return none }
    present(read module_ir.functions[id.index])
}

fn verify_function(read program: Program, read function: Function): Unit throws InvalidIr {
    var values = List<Scalar>()
    for instruction in function.instructions.as_slice() {
        let span = instruction.span
        let result = match read instruction.operation {
            Operation.Integer(_) => Scalar.I32,
            Operation.Boolean(_) => Scalar.Bool,
            Operation.Unit => Scalar.Unit,
            Operation.Parameter(index) => {
                if index >= function.parameters.len() { throw InvalidIr(Violation.Parameter, span) }
                function.parameters[index]
            },
            Operation.Arithmetic(_, left, right) => {
                if left >= values.len() || right >= values.len() ||
                    !values[left].is(Scalar.I32) || !values[right].is(Scalar.I32) {
                    throw InvalidIr(Violation.Operand, span)
                }
                Scalar.I32
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
    if function.returned >= values.len() || !values[function.returned].is(function.result) {
        throw InvalidIr(Violation.Return, function.span)
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
    instructions.push(Instruction(Operation.Arithmetic(Arithmetic.Add, 1, 1), span))
    instructions.push(Instruction(Operation.Integer(2), span))
    var functions = List<Function>()
    functions.push(Function(List<Scalar>(), Scalar.I32, take instructions, 0, span))
    var modules = List<Module>()
    modules.push(Module(take functions))
    let failure(error) = capture verify(Program(take modules, none)) else {
        core.panic.panic("verifier admitted an instruction using a future value")
    }
    let Violation.Operand = error.violation else { core.panic.panic("incorrect IR rejection reason") }
    assert(error.span.source == 1 && error.span.begin == 2,
        "invalid operand lost its reason or source position")
}
