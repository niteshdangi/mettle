import alloc.string.{ String, new }
import alloc.vec.{ List, with_capacity }
import core.fmt.Message
import mettle_foundation.Span
import mettle_ir.{ Arithmetic, Block, Comparison, Function, FunctionId, Operation, Program,
    Terminator, VerifiedProgram }
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
    Integer(i32), Boolean(bool), Parameter(usize), BlockParameter(usize, usize), Register(usize), Unit
}

copy type Incoming { block: usize; alternate: bool }
type BlockInfo { base: usize; last_guard: usize?; incoming: List<Incoming> }

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
        Value.BlockParameter(block, index) => append_format(mut out, f"%arg{block}.{index}"),
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
    left: Value, right: Value): Unit {
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
}

fn append_arithmetic(mut out: String, index: usize, operation: Arithmetic,
    left: Value, right: Value, checks: OverflowChecks): Unit {
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
        return
    }
    append_format(mut out, f"  %v{index} = {opcode} i32 ")
    append_operands(mut out, left, right, false)
    out.push_str("\n")
}

fn unit_comparison(comparison: Comparison): bool {
    match comparison {
        Comparison.Equal | Comparison.LessEqual | Comparison.GreaterEqual => true,
        Comparison.NotEqual | Comparison.Less | Comparison.Greater => false
    }
}

fn append_compare(mut out: String, index: usize, comparison: Comparison, scalar: Scalar,
    left: Value, right: Value): Unit {
    let signed = scalar.is(Scalar.I32)
    let predicate: read Text = match comparison {
        Comparison.Equal => "eq",
        Comparison.NotEqual => "ne",
        Comparison.Less => if signed { "slt" } else { "ult" },
        Comparison.LessEqual => if signed { "sle" } else { "ule" },
        Comparison.Greater => if signed { "sgt" } else { "ugt" },
        Comparison.GreaterEqual => if signed { "sge" } else { "uge" }
    }
    let ty = llvm_type(scalar)
    append_format(mut out, f"  %v{index} = icmp {predicate} {ty} ")
    append_operands(mut out, left, right, false)
    out.push_str("\n")
}

fn value_at(read block: Block, block_id: usize, base: usize, index: usize): Value {
    if index < block.parameters.len() { return Value.BlockParameter(block_id, index) }
    let instruction = index - block.parameters.len()
    match read block.instructions[instruction].operation {
        Operation.Integer(number) => Value.Integer(number),
        Operation.Boolean(flag) => Value.Boolean(flag),
        Operation.Unit => Value.Unit,
        Operation.Parameter(parameter) => Value.Parameter(parameter),
        Operation.Compare(comparison, scalar, _, _) => {
            if scalar.is(Scalar.Unit) { Value.Boolean(unit_comparison(comparison)) }
            else { Value.Register(base + instruction) }
        },
        Operation.Arithmetic(_, _, _) | Operation.Call(_, _) => Value.Register(base + instruction)
    }
}

fn plan_blocks(read function: Function, checks: OverflowChecks): List<BlockInfo> {
    var blocks = with_capacity<BlockInfo>(function.blocks.len())
    var base = 0usize
    for block in function.blocks.as_slice() {
        var last_guard: usize? = none
        for index in 0usize..block.instructions.len() {
            match read block.instructions[index].operation {
                Operation.Arithmetic(operation, _, _) => match (operation, checks) {
                    (Arithmetic.Divide, _) | (Arithmetic.Remainder, _) | (_, OverflowChecks.On) =>
                        { last_guard = present(base + index) },
                    _ => {}
                },
                _ => {}
            }
        }
        blocks.push(BlockInfo(base, last_guard, List<Incoming>()))
        base += block.instructions.len()
    }
    for id in 0usize..function.blocks.len() {
        match read function.blocks[id].terminator {
            Terminator.Return(_) => {},
            Terminator.Jump(edge) => blocks[edge.block].incoming.push(Incoming(id, false)),
            Terminator.Branch(_, yes, no) => {
                blocks[yes.block].incoming.push(Incoming(id, false))
                blocks[no.block].incoming.push(Incoming(id, true))
            }
        }
    }
    blocks
}

fn incoming_value(read block: Block, alternate: bool, index: usize): usize {
    match read block.terminator {
        Terminator.Jump(edge) => edge.arguments[index],
        Terminator.Branch(_, yes, no) => if alternate { no.arguments[index] } else { yes.arguments[index] },
        Terminator.Return(_) => core.panic.panic("LLVM predecessor has no edge")
    }
}

fn append_phis(mut out: String, read function: Function, read blocks: List<BlockInfo>,
    block_id: usize): Unit {
    let info = read blocks[block_id]
    let block = read function.blocks[block_id]
    for index in 0usize..block.parameters.len() {
        let scalar = block.parameters[index]
        if scalar.is(Scalar.Unit) { continue }
        let ty = llvm_type(scalar)
        append_format(mut out, f"  %arg{block_id}.{index} = phi {ty} ")
        var first = true
        for incoming in info.incoming.as_slice() {
            if !first { out.push_str(", ") }
            first = false
            let source = incoming.block
            let predecessor = read function.blocks[source]
            let argument = incoming_value(predecessor, incoming.alternate, index)
            let plan = read blocks[source]
            out.push_str("[ ")
            append_value(mut out, value_at(predecessor, source, plan.base, argument))
            if let present(guard) = plan.last_guard {
                append_format(mut out, f", %checked{guard} ]")
            } else {
                append_format(mut out, f", %b{source} ]")
            }
        }
        out.push_str("\n")
    }
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
    out.push_str(") uwtable {\n")
    let blocks = plan_blocks(function, checks)
    var can_panic = false
    for block_id in 0usize..function.blocks.len() {
        let block = read function.blocks[block_id]
        let info = read blocks[block_id]
        append_format(mut out, f"b{block_id}:\n")
        append_phis(mut out, function, blocks, block_id)
        append_block(mut out, program, block, block_id, info.base, function.result, checks)
        if let present(_) = info.last_guard { can_panic = true }
    }
    if can_panic {
        out.push_str("panic:\n  call void @mettle_rt_panic(i32 1)\n  unreachable\n")
    }
    out.push_str("}\n\n")
    can_panic
}

fn append_block(mut out: String, read program: Program, read block: Block, block_id: usize,
    base: usize, result: Scalar, checks: OverflowChecks): Unit {
    for offset in 0usize..block.instructions.len() {
        let index = base + offset
        let instruction = read block.instructions[offset]
        match read instruction.operation {
            Operation.Integer(_) | Operation.Boolean(_) | Operation.Unit | Operation.Parameter(_) => {},
            Operation.Arithmetic(operation, left, right) => {
                append_arithmetic(mut out, index, operation,
                    value_at(block, block_id, base, left), value_at(block, block_id, base, right), checks)
            },
            Operation.Compare(comparison, scalar, left, right) => {
                if !scalar.is(Scalar.Unit) {
                    append_compare(mut out, index, comparison, scalar,
                        value_at(block, block_id, base, left), value_at(block, block_id, base, right))
                }
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
                    append_value(mut out, value_at(block, block_id, base, arguments[position]))
                }
                out.push_str(")\n")
            }
        }
    }
    match read block.terminator {
        Terminator.Return(returned) => {
            out.push_str("  ret ")
            out.push_str(llvm_type(result))
            if !result.is(Scalar.Unit) {
                out.push_str(" ")
                append_value(mut out, value_at(block, block_id, base, returned))
            }
            out.push_str("\n")
        },
        Terminator.Jump(edge) => {
            let target = edge.block
            append_format(mut out, f"  br label %b{target}\n")
        },
        Terminator.Branch(condition, yes, no) => {
            let true_block = yes.block
            let false_block = no.block
            out.push_str("  br i1 ")
            append_value(mut out, value_at(block, block_id, base, condition))
            append_format(mut out, f", label %b{true_block}, label %b{false_block}\n")
        }
    }
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
