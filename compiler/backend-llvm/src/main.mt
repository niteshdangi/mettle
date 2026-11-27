import alloc.string.{ String, new }
import alloc.vec.{ List, with_capacity }
import core.fmt.Message
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Function, FunctionId, Operation, Program, VerifiedProgram }
import mettle_types.Scalar

module link
pub import link.{ LinkError, link_executable }

pub copy enum OverflowChecks { On, Off }

pub copy enum EmitError {
    MissingEntry,
    CheckedOverflow(Arithmetic, Span),
    UnsupportedArithmetic(Arithmetic, Span)
}

copy enum Value {
    Integer(i32), Boolean(bool), Parameter(usize), Register(usize), Unit
}

fn llvm_type(scalar: Scalar): read Text from static {
    match scalar {
        Scalar.I32 => "i32",
        Scalar.Bool => "i1",
        Scalar.Unit => "void"
    }
}

fn append_format(mut out: String, message: format Message): Unit {
    match capture out.write_fmt(message) {
        success(_) => {},
        failure(_) => core.panic.panic("LLVM IR formatting failed")
    }
}

fn append_value(mut out: String, value: Value): Unit {
    match value {
        Value.Integer(number) => append_format(mut out, f"{number}"),
        Value.Boolean(true) => out.push_str("true"),
        Value.Boolean(false) => out.push_str("false"),
        Value.Parameter(index) => append_format(mut out, f"%p{index}"),
        Value.Register(index) => append_format(mut out, f"%v{index}"),
        Value.Unit => core.panic.panic("LLVM void value used as an operand")
    }
}

fn append_operands(mut out: String, left: Value, right: Value, checked_call: bool): Unit {
    append_value(mut out, left)
    if checked_call { out.push_str(", i32 ") }
    else { out.push_str(", ") }
    append_value(mut out, right)
}

fn append_guard(mut out: String, index: usize): Unit {
    append_format(mut out, f"  br i1 %bad{index}, label %panic, label %checked{index}\n")
    append_format(mut out, f"checked{index}:\n")
}

fn append_division(mut out: String, index: usize, read opcode: Text,
    left: Value, right: Value): bool {
    append_format(mut out, f"  %zero{index} = icmp eq i32 ")
    append_value(mut out, right)
    append_format(mut out, f", 0\n  %min{index} = icmp eq i32 ")
    append_value(mut out, left)
    append_format(mut out, f", -2147483648\n  %negone{index} = icmp eq i32 ")
    append_value(mut out, right)
    append_format(mut out, f", -1\n  %edge{index} = and i1 %min{index}, %negone{index}\n")
    append_format(mut out, f"  %bad{index} = or i1 %zero{index}, %edge{index}\n")
    append_guard(mut out, index)
    append_format(mut out, f"  %v{index} = {opcode} i32 ")
    append_operands(mut out, left, right, false)
    out.push_str("\n")
    true
}

fn append_arithmetic(mut out: String, index: usize, operation: Arithmetic,
    left: Value, right: Value, checks: OverflowChecks): bool {
    let opcode = match operation {
        Arithmetic.Add => "add",
        Arithmetic.Subtract => "sub",
        Arithmetic.Multiply => "mul",
        Arithmetic.Divide => { return append_division(mut out, index, "sdiv", left, right) },
        Arithmetic.Remainder => { return append_division(mut out, index, "srem", left, right) }
    }
    if let OverflowChecks.On = checks {
        append_format(mut out, f"  %pair{index} = call ")
        out.push_str("{ i32, i1 } @llvm.")
        append_format(mut out, f"s{opcode}.with.overflow.i32(i32 ")
        append_operands(mut out, left, right, true)
        append_format(mut out, f")\n  %bad{index} = extractvalue ")
        out.push_str("{ i32, i1 } ")
        append_format(mut out, f"%pair{index}, 1\n")
        append_guard(mut out, index)
        append_format(mut out, f"  %v{index} = extractvalue ")
        out.push_str("{ i32, i1 } ")
        append_format(mut out, f"%pair{index}, 0\n")
        return true
    }
    append_format(mut out, f"  %v{index} = {opcode} i32 ")
    append_operands(mut out, left, right, false)
    out.push_str("\n")
    false
}

fn append_function(mut out: String, read program: Program, id: FunctionId,
    read function: Function, checks: OverflowChecks): bool {
    let module_index = id.module_index
    let function_index = id.index
    let result_type = llvm_type(function.result)
    append_format(mut out, f"define internal {result_type} @mettle.{module_index}.{function_index}(")
    var first = true
    for index in 0usize..function.parameters.len() {
        let scalar = function.parameters[index]
        if scalar.is(Scalar.Unit) { continue }
        if !first { out.push_str(", ") }
        first = false
        let ty = llvm_type(scalar)
        append_format(mut out, f"{ty} %p{index}")
    }
    out.push_str(") uwtable {\nentry:\n")

    var can_panic = false
    var values: List<Value> = with_capacity<Value>(function.instructions.len())
    for index in 0usize..function.instructions.len() {
        let instruction = read function.instructions[index]
        let value = match read instruction.operation {
            Operation.Integer(number) => Value.Integer(number),
            Operation.Boolean(flag) => Value.Boolean(flag),
            Operation.Unit => Value.Unit,
            Operation.Parameter(parameter) =>
                if function.parameters[parameter].is(Scalar.Unit) { Value.Unit }
                else { Value.Parameter(parameter) },
            Operation.Arithmetic(operation, left, right) => {
                if append_arithmetic(mut out, index, operation, values[left], values[right], checks) {
                    can_panic = true
                }
                Value.Register(index)
            },
            Operation.Call(target, arguments) => {
                let callee = read program.modules[target.module_index].functions[target.index]
                let target_module = target.module_index
                let target_function = target.index
                let ty = llvm_type(callee.result)
                let returns_unit = callee.result.is(Scalar.Unit)
                if returns_unit { out.push_str("  ") }
                else { append_format(mut out, f"  %v{index} = ") }
                append_format(mut out, f"call {ty} @mettle.{target_module}.{target_function}(")
                var first_argument = true
                for position in 0usize..arguments.len() {
                    let scalar = callee.parameters[position]
                    if scalar.is(Scalar.Unit) { continue }
                    if !first_argument { out.push_str(", ") }
                    first_argument = false
                    out.push_str(llvm_type(scalar))
                    out.push_str(" ")
                    append_value(mut out, values[arguments[position]])
                }
                out.push_str(")\n")
                if returns_unit { Value.Unit } else { Value.Register(index) }
            }
        }
        values.push(value)
    }
    out.push_str("  ret ")
    out.push_str(result_type)
    if !function.result.is(Scalar.Unit) {
        out.push_str(" ")
        append_value(mut out, values[function.returned])
    }
    out.push_str("\n")
    if can_panic {
        out.push_str("panic:\n  call void @mettle_rt_panic(i32 1)\n  unreachable\n")
    }
    out.push_str("}\n\n")
    can_panic
}

pub fn emit_ir(read verified: VerifiedProgram, checks: OverflowChecks): String throws EmitError {
    let program = verified.program()
    let present(entry) = program.entry else { throw EmitError.MissingEntry }
    var out = new()
    var can_panic = false
    for module_index in 0usize..program.modules.len() {
        let module_ir = read program.modules[module_index]
        for index in 0usize..module_ir.functions.len() {
            if append_function(mut out, program, FunctionId(module_index, index),
                module_ir.functions[index], checks) {
                can_panic = true
            }
        }
    }
    let module_index = entry.module_index
    let function_index = entry.index
    if can_panic {
        if let OverflowChecks.On = checks {
            out.push_str("declare { i32, i1 } @llvm.sadd.with.overflow.i32(i32, i32)\n")
            out.push_str("declare { i32, i1 } @llvm.ssub.with.overflow.i32(i32, i32)\n")
            out.push_str("declare { i32, i1 } @llvm.smul.with.overflow.i32(i32, i32)\n")
        }
        out.push_str("declare void @mettle_rt_panic(i32) noreturn\n")
        out.push_str("declare i32 @mettle_rt_main(ptr, ptr)\n\n")
        out.push_str("define internal void @mettle.entry(ptr %slot) uwtable {\nentry:\n")
        append_format(mut out, f"  %result = call i32 @mettle.{module_index}.{function_index}()\n")
        out.push_str("  store i32 %result, ptr %slot\n  ret void\n}\n\n")
        out.push_str("define i32 @main() uwtable {\nentry:\n  %slot = alloca i32\n")
        out.push_str("  store i32 0, ptr %slot\n  %status = call i32 @mettle_rt_main(ptr %slot, ptr @mettle.entry)\n")
        out.push_str("  %result = load i32, ptr %slot\n  %failed = icmp ne i32 %status, 0\n")
        out.push_str("  %exit = select i1 %failed, i32 %status, i32 %result\n  ret i32 %exit\n}\n")
    } else {
        out.push_str("define i32 @main() {\nentry:\n")
        append_format(mut out, f"  %result = call i32 @mettle.{module_index}.{function_index}()\n")
        out.push_str("  ret i32 %result\n}\n")
    }
    out
}
