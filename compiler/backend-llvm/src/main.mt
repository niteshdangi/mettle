import alloc.string.{ String, new }
import alloc.vec.{ List, with_capacity }
import core.fmt.Message
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Function, FunctionId, Operation, Program, VerifiedProgram }
import mettle_types.Scalar

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

fn arithmetic_opcode(operation: Arithmetic, checks: OverflowChecks,
    span: Span): read Text from static throws EmitError {
    let opcode = match operation {
        Arithmetic.Add => "add",
        Arithmetic.Subtract => "sub",
        Arithmetic.Multiply => "mul",
        Arithmetic.Divide | Arithmetic.Remainder =>
            throw EmitError.UnsupportedArithmetic(operation, span)
    }
    if let OverflowChecks.On = checks { throw EmitError.CheckedOverflow(operation, span) }
    opcode
}

fn append_function(mut out: String, read program: Program, id: FunctionId,
    read function: Function, checks: OverflowChecks): Unit throws EmitError {
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
    out.push_str(") {\nentry:\n")

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
                let opcode = try arithmetic_opcode(operation, checks, instruction.span)
                append_format(mut out, f"  %v{index} = {opcode} i32 ")
                append_value(mut out, values[left])
                out.push_str(", ")
                append_value(mut out, values[right])
                out.push_str("\n")
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
    out.push_str("\n}\n\n")
}

pub fn emit_ir(read verified: VerifiedProgram, checks: OverflowChecks): String throws EmitError {
    let program = verified.program()
    let present(entry) = program.entry else { throw EmitError.MissingEntry }
    var out = new()
    for module_index in 0usize..program.modules.len() {
        let module_ir = read program.modules[module_index]
        for index in 0usize..module_ir.functions.len() {
            try append_function(mut out, program, FunctionId(module_index, index),
                module_ir.functions[index], checks)
        }
    }
    let module_index = entry.module_index
    let function_index = entry.index
    out.push_str("define i32 @main() {\nentry:\n")
    append_format(mut out, f"  %result = call i32 @mettle.{module_index}.{function_index}()\n")
    out.push_str("  ret i32 %result\n}\n")
    out
}
