import alloc.vec.{ List, from_array }
import mettle_backend_llvm.{ LinkError, OverflowChecks, emit_ir, link_executable }
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Block, Comparison, Edge, Function, FunctionId, Instruction, Module,
    Operation, Program, Terminator, verify }
import mettle_types.Scalar
import std.env
import std.ffi.os_str_from_text
import std.io
import std.io.Writer
import std.path.path_from_os_str

fn main(): i32 {
    let args = env.args_os()
    if args.len() == 1 { return cross_module() }
    if args.len() == 6 && args[1].as_os_str().same(os_str_from_text("link")) {
        return match take capture link_executable(path_from_os_str(args[2].as_os_str()),
            path_from_os_str(args[3].as_os_str()), path_from_os_str(args[4].as_os_str()),
            path_from_os_str(args[5].as_os_str())) {
            success(_) => 0,
            failure(LinkError.Io(error)) => {
                assert(error.kind().is(io.ErrorKind.NotFound), "expected missing Clang or runtime")
                2
            },
            failure(LinkError.Failed(status)) =>
                if let present(code) = status.code() { code }
                else if let present(signal) = status.signal() { 128 + signal }
                else { core.panic.panic("missing tool exit status") },
            failure(LinkError.UnsupportedHost) => 3
        }
    }
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
    if case.same(os_str_from_text("cfg")) { return guarded_join(checks) }
    1
}

fn cross_module(): i32 { emit_cross_module(2147483647, -40, OverflowChecks.Off) }

fn cross_module_checked(checks: OverflowChecks): i32 { emit_cross_module(5, -28, checks) }

fn straight_line(take parameters: List<Scalar>, result: Scalar,
    take instructions: List<Instruction>, returned: usize, span: Span): Function {
    Function(take parameters, result,
        from_array([Block(List<Scalar>(), take instructions, Terminator.Return(returned), span)]), span)
}

fn emit_cross_module(left: i32, bias: i32, checks: OverflowChecks): i32 {
    let span = Span(1, 0, 1)
    var entry_ops = List<Instruction>()
    entry_ops.push(Instruction(Operation.Boolean(true), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 0), from_array([0usize])), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 1), List<usize>()), span))
    entry_ops.push(Instruction(Operation.Integer(Scalar.I32, left as u32 as u64), span))
    entry_ops.push(Instruction(Operation.Integer(Scalar.I32, 2), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 2), from_array([2usize, 3, 1, 4])), span))

    var bool_ops = List<Instruction>()
    bool_ops.push(Instruction(Operation.Parameter(0), span))
    var unit_ops = List<Instruction>()
    unit_ops.push(Instruction(Operation.Unit, span))
    var scalar_ops = List<Instruction>()
    scalar_ops.push(Instruction(Operation.Parameter(1), span))
    scalar_ops.push(Instruction(Operation.Parameter(3), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Add, Scalar.I32, 0, 1), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Multiply, Scalar.I32, 2, 1), span))
    scalar_ops.push(Instruction(Operation.Integer(Scalar.I32, bias as u32 as u64), span))
    scalar_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Subtract, Scalar.I32, 3, 4), span))

    var entry = List<Function>()
    entry.push(straight_line(List<Scalar>(), Scalar.I32, take entry_ops, 5, span))
    var helpers = List<Function>()
    helpers.push(straight_line(from_array([Scalar.Bool]), Scalar.Bool, take bool_ops, 0, span))
    helpers.push(straight_line(List<Scalar>(), Scalar.Unit, take unit_ops, 0, span))
    helpers.push(straight_line(from_array([Scalar.Unit, Scalar.I32, Scalar.Bool, Scalar.I32]),
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
    entry_ops.push(Instruction(Operation.Integer(Scalar.I32, left as u32 as u64), span))
    entry_ops.push(Instruction(Operation.Integer(Scalar.I32, right as u32 as u64), span))
    entry_ops.push(Instruction(Operation.Call(FunctionId(1, 0), from_array([0usize, 1])), span))
    var helper_ops = List<Instruction>()
    helper_ops.push(Instruction(Operation.Parameter(0), span))
    helper_ops.push(Instruction(Operation.Parameter(1), span))
    helper_ops.push(Instruction(Operation.Arithmetic(operation, Scalar.I32, 0, 1), span))
    let returned = match operation {
        Arithmetic.Divide | Arithmetic.Remainder => 2usize,
        _ => {
            helper_ops.push(Instruction(Operation.Integer(Scalar.I32, 1000000000), span))
            helper_ops.push(Instruction(Operation.Arithmetic(Arithmetic.Divide, Scalar.I32, 2, 3), span))
            4usize
        }
    }
    var entries = List<Function>()
    entries.push(straight_line(List<Scalar>(), Scalar.I32, take entry_ops, 2, span))
    var helpers = List<Function>()
    helpers.push(straight_line(from_array([Scalar.I32, Scalar.I32]), Scalar.I32, take helper_ops, returned, span))
    write_artifact(Program(from_array([Module(take entries), Module(take helpers)]),
        present(FunctionId(0, 0))), checks)
}

fn guarded_join(checks: OverflowChecks): i32 {
    let span = Span(1, 0, 1)
    let start = Block(List<Scalar>(), from_array([
        Instruction(Operation.Boolean(false), span),
        Instruction(Operation.Boolean(true), span),
        Instruction(Operation.Compare(Comparison.Less, Scalar.Bool, 0, 1), span),
        Instruction(Operation.Integer(Scalar.I32, 38), span),
        Instruction(Operation.Integer(Scalar.I32, 43), span),
        Instruction(Operation.Unit, span)
    ]), Terminator.Branch(2, Edge(1, from_array([3usize, 5])), Edge(2, from_array([4usize, 5]))), span)
    let guarded = Block(from_array([Scalar.I32, Scalar.Unit]), from_array([
        Instruction(Operation.Integer(Scalar.I32, 2), span),
        Instruction(Operation.Arithmetic(Arithmetic.Add, Scalar.I32, 0, 2), span),
        Instruction(Operation.Integer(Scalar.I32, 1), span),
        Instruction(Operation.Arithmetic(Arithmetic.Divide, Scalar.I32, 3, 4), span),
        Instruction(Operation.Compare(Comparison.GreaterEqual, Scalar.Unit, 1, 1), span)
    ]), Terminator.Branch(6, Edge(3, from_array([5usize, 1])), Edge(2, from_array([0usize, 1]))), span)
    let alternate = Block(from_array([Scalar.I32, Scalar.Unit]), List<Instruction>(),
        Terminator.Jump(Edge(3, from_array([0usize, 1]))), span)
    let junction = Block(from_array([Scalar.I32, Scalar.Unit]), from_array([
        Instruction(Operation.Integer(Scalar.I32, 42), span),
        Instruction(Operation.Compare(Comparison.Less, Scalar.I32, 0, 2), span)
    ]), Terminator.Branch(3, Edge(1, from_array([0usize, 1])), Edge(4, from_array([0usize]))), span)
    let exit = Block(from_array([Scalar.I32]), List<Instruction>(), Terminator.Return(0), span)
    let function = Function(List<Scalar>(), Scalar.I32,
        from_array([take start, take guarded, take alternate, take junction, take exit]), span)
    write_artifact(Program(from_array([Module(from_array([take function]))]),
        present(FunctionId(0, 0))), checks)
}
