import alloc.vec.{ List, from_array }
import mettle_backend_llvm.{ OverflowChecks, emit_ir }
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Function, FunctionId, Instruction, Module, Operation, Program, verify }
import mettle_types.Scalar
import std.env
import std.ffi.os_str_from_text
import std.io
import std.io.Writer

fn main(): i32 {
    let args = env.args_os()
    if args.len() == 1 { return cross_module() }
    if args.len() != 3 { return 1 }
    let mode = args[1].as_os_str()
    let checks = if mode.same(os_str_from_text("on")) { OverflowChecks.On }
        else if mode.same(os_str_from_text("off")) { OverflowChecks.Off }
        else { return 1 }
    let case = args[2].as_os_str()
    if case.same(os_str_from_text("add")) { return arithmetic(Arithmetic.Add, 2147483647, 1, checks) }
    if case.same(os_str_from_text("sub")) { return arithmetic(Arithmetic.Subtract, -2147483648, 1, checks) }
    if case.same(os_str_from_text("mul")) { return arithmetic(Arithmetic.Multiply, 1073741824, 3, checks) }
    if case.same(os_str_from_text("div")) { return arithmetic(Arithmetic.Divide, -85, 2, checks) }
    if case.same(os_str_from_text("rem")) { return arithmetic(Arithmetic.Remainder, -87, 45, checks) }
    if case.same(os_str_from_text("div-zero")) { return arithmetic(Arithmetic.Divide, 17, 0, checks) }
    if case.same(os_str_from_text("rem-zero")) { return arithmetic(Arithmetic.Remainder, 17, 0, checks) }
    if case.same(os_str_from_text("div-min")) { return arithmetic(Arithmetic.Divide, -2147483648, -1, checks) }
    if case.same(os_str_from_text("rem-min")) { return arithmetic(Arithmetic.Remainder, -2147483648, -1, checks) }
    if case.same(os_str_from_text("safe")) { return cross_module_checked(checks) }
    1
}

fn cross_module(): i32 { emit_cross_module(2147483647, -40, OverflowChecks.Off) }

fn cross_module_checked(checks: OverflowChecks): i32 { emit_cross_module(5, -28, checks) }

fn emit_cross_module(left: i32, bias: i32, checks: OverflowChecks): i32 {
    let span = Span(1, 0, 1)
    var entry_ops = List<Instruction>()
    entry_ops.push(Instruction(Operation.Boolean(true), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 0), from_array([0usize])), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 1), List<usize>()), span))
    entry_ops.push(Instruction(Operation.Integer(left), span))
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
    scalar_ops.push(Instruction(Operation.Integer(bias), span))
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

    write_artifact(Program(take modules, present(FunctionId(0, 0))), checks)
}

fn write_artifact(take input: Program, checks: OverflowChecks): i32 {
    let program = (capture verify(take input)).or_panic()
    let artifact = (capture emit_ir(program, checks)).or_panic()
    var stdout = io.stdout()
    (capture stdout.write_all(artifact.as_bytes())).or_panic();
    (capture stdout.flush()).or_panic();
    0
}

fn arithmetic(operation: Arithmetic, left: i32, right: i32, checks: OverflowChecks): i32 {
    let span = Span(1, 0, 1)
    var entry_ops = List<Instruction>()
    entry_ops.push(Instruction(Operation.Integer(left), span))
    entry_ops.push(Instruction(Operation.Integer(right), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 0), from_array([0usize, 1])), span))
    var helper_ops = List<Instruction>()
    helper_ops.push(Instruction(Operation.Parameter(0), span))
    helper_ops.push(Instruction(Operation.Parameter(1), span))
    helper_ops.push(Instruction(Operation.Arithmetic(operation, 0, 1), span))
    let returned = match operation {
        Arithmetic.Divide | Arithmetic.Remainder => 2usize,
        _ => {
            helper_ops.push(Instruction(Operation.Integer(1000000000), span))
            helper_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Divide, 2, 3), span))
            4usize
        }
    }
    var entries = List<Function>()
    entries.push(Function(List<Scalar>(), Scalar.I32, take entry_ops, 2, span))
    var helpers = List<Function>()
    helpers.push(Function(from_array([Scalar.I32, Scalar.I32]), Scalar.I32, take helper_ops, returned, span))
    write_artifact(Program(from_array([Module(take entries), Module(take helpers)]),
        present(FunctionId(0, 0))), checks)
}
