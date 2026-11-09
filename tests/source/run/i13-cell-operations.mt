// profiles: debug release

import core.cmp.{Eq, Ord, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.clone.Clone
import core.text.Text

fn debug_ok<T: Debug>(read value: T) {}
fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}
fn eq_ok<T: Eq>() {}
fn partial_eq_ok<T: PartialEq<T>>() {}
fn ord_ok<T: Ord>() {}
fn partial_ord_ok<T: PartialOrd<T>>() {}
fn send_ok<T: Transferable>() {}

fn cell_operations(): i32 {
    var value = core.cell.Cell.new(4i32)
    if value.get() != 4 { return 1 }
    if value.as_ptr().is_null() { return 15 }
    value.set(5)
    if value.replace(6) != 5 || value.get() != 6 { return 2 }
    if core.cell.Cell.new(12i32).clone().get() != 12 { return 17 }
    var other = core.cell.Cell.new(7i32)
    value.swap(mut other)
    if value.get() != 7 || other.get() != 6 { return 3 }
    if value.`take`() != 7 || value.get() != 0 { return 4 }
    *value.get_mut() = 8
    if value.get() != 8 { return 5 }

    let from = core.cell.Cell<i32>.(From<i32>).from(9)
    if from.get() != 9 { return 6 }
    let defaulted: core.cell.Cell<i32> =
        core.cell.Cell<i32>.(Default).default()
    if defaulted.get() != 0 { return 7 }
    if !(core.cell.Cell.new(1i32) == core.cell.Cell.new(1i32)) { return 8 }
    if core.cell.Cell.new(1i32) >= core.cell.Cell.new(2i32) { return 9 }
    eq_ok<core.cell.Cell<i32>>()
    partial_eq_ok<core.cell.Cell<i32>>()
    ord_ok<core.cell.Cell<i32>>()
    partial_ord_ok<core.cell.Cell<i32>>()
    send_ok<core.cell.Cell<i32>>()
    let debug_cell = core.cell.Cell.new(1i32)
    debug_ok(debug_cell)
    if !debug_is(debug_cell, "Cell { value: 1 }") { return 10 }

    let inner = take core.cell.Cell.new(16i32).into_inner()
    if inner != 16 { return 14 }
    0
}

fn main(): i32 { cell_operations() }
