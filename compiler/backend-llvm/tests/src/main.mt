import alloc.vec.{ List, from_array }
import mettle_backend_llvm.{ EmitError, OverflowChecks, emit_ir }
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Function, FunctionId, Instruction, Module, Operation, Program, verify }
import mettle_types.Scalar
import std.io
import std.io.Writer

fn main(): i32 {
    let span = Span(1, 0, 1)
    var entry_ops = List<Instruction>()
    entry_ops.push(Instruction(Operation.Boolean(true), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 0), from_array([0usize])), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 1), List<usize>()), span))
    entry_ops.push(Instruction(Operation.Integer(2147483647), span))
    entry_ops.push(Instruction(Operation.Integer(2), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 2), from_array([2usize, 3, 1, 4])), span))

    var bool_ops = List<Instruction>()
    bool_ops.push(Instruction(Operation.Parameter(0), span))
    var unit_ops = List<Instruction>()
    unit_ops.push(Instruction(Operation.Unit, span))
    var scalar_ops = List<Instruction>()
    scalar_ops.push(Instruction(Operation.Parameter(1), span))
    scalar_ops.push(Instruction(Operation.Parameter(3), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Add, 0, 1), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Multiply, 2, 1), span))
    scalar_ops.push(Instruction(Operation.Integer(-40), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Subtract, 3, 4), span))

    var entry = List<Function>()
    entry.push(Function(List<Scalar>(), Scalar.I32, take entry_ops, 5, span))
    var helpers = List<Function>()
    helpers.push(Function(from_array([Scalar.Bool]), Scalar.Bool, take bool_ops, 0, span))
    helpers.push(Function(List<Scalar>(), Scalar.Unit, take unit_ops, 0, span))
    helpers.push(Function(from_array([Scalar.Unit, Scalar.I32, Scalar.Bool, Scalar.I32]),
        Scalar.I32, take scalar_ops, 5, span))
    var modules = List<Module>()
    modules.push(Module(take entry))
    modules.push(Module(take helpers))

    let program = (capture verify(Program(take modules, present(FunctionId(0, 0))))).or_panic()
    let artifact = (capture emit_ir(program, OverflowChecks.Off)).or_panic()
    var stdout = io.stdout()
    (capture stdout.write_all(artifact.as_bytes())).or_panic();
    (capture stdout.flush()).or_panic();
    0
}

@test
fn reject_arithmetic_without_required_checks(): Unit {
    let span = Span(1, 5, 6)
    for operation in [Arithmetic.Add, Arithmetic.Divide, Arithmetic.Remainder] {
        var instructions = List<Instruction>()
        instructions.push(Instruction(Operation.Integer(-2147483648), span))
        instructions.push(Instruction(Operation.Integer(-1), span))
        instructions.push(Instruction(Operation.Arithmetic(operation, 0, 1), span))
        var functions = List<Function>()
        functions.push(Function(List<Scalar>(), Scalar.I32, take instructions, 2, span))
        var modules = List<Module>()
        modules.push(Module(take functions))
        let program = (capture verify(Program(take modules, present(FunctionId(0, 0))))).or_panic()

        match operation {
            Arithmetic.Add => {
                let failure(EmitError.CheckedOverflow(Arithmetic.Add, actual)) =
                    capture emit_ir(program, OverflowChecks.On) else {
                    core.panic.panic("checked overflow was not rejected")
                }
                assert(actual.source == 1 && actual.begin == 5 && actual.end == 6, "lost overflow span")
            },
            Arithmetic.Divide | Arithmetic.Remainder => {
                let failure(EmitError.UnsupportedArithmetic(actual_op, actual)) =
                    capture emit_ir(program, OverflowChecks.Off) else {
                    core.panic.panic("unchecked division or remainder was not rejected")
                }
                match (operation, actual_op) {
                    (Arithmetic.Divide, Arithmetic.Divide) | (Arithmetic.Remainder, Arithmetic.Remainder) => {},
                    _ => core.panic.panic("wrong unsupported operation")
                }
                assert(actual.source == 1 && actual.begin == 5 && actual.end == 6, "lost arithmetic span")
            },
            _ => core.panic.panic("unexpected test operation")
        }
    }
}
