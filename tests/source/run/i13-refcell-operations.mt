// profiles: debug release

import core.cmp.{Eq, Ord, PartialEq, PartialOrd}
import core.clone.Clone
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.fmt.Display
import core.fmt
import core.ops.{Deref, DerefMut}
import core.text.Text

@derive(Clone)
type Pair {
    left: i32
    right: i32
}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}
fn display_is<T: Display>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}
fn eq_ok<T: Eq>() {}
fn partial_eq_ok<T: PartialEq<T>>() {}
fn ord_ok<T: Ord>() {}
fn partial_ord_ok<T: PartialOrd<T>>() {}
fn main(): i32 {
    var cell = core.cell.RefCell.new(Pair(1, 2))
    {
        let guard = cell.borrow()
        if guard.get_ref().left != 1 || guard.get_ref().right != 2 {
            return 1
        }
        let cloned = guard.get_ref().clone()
        if cloned.left != 1 || guard.deref().right != 2 {
            return 25
        }
    }

    {
        var guard = cell.borrow_mut()
        guard.deref_mut().left += 1
    }
    if cell.borrow().get_ref().left != 2 { return 6 }

    {
        var guard = cell.borrow_mut()
        guard.get_mut().left += 1
    }
    if cell.borrow().get_ref().left != 3 { return 8 }

    {
        var guard = cell.borrow_mut()
        guard.get_mut().left += 1
        guard.get_mut().right += 1
    }
    if cell.borrow().get_ref().left != 4 ||
        cell.borrow().get_ref().right != 3 {
        return 9
    }

    match cell.try_borrow() {
        success(guard) => { if guard.get_ref().left != 4 { return 10 } },
        failure(_) => { return 11 }
    }
    match take cell.try_borrow_mut() {
        success(guard) => {
            var held = guard
            if held.get_mut().right != 3 { return 32 }
        },
        failure(_) => { return 12 }
    }
    {
        var guard = cell.borrow_mut()
        guard.get_mut().right = 4
    }
    if cell.borrow().get_ref().right != 4 { return 13 }

    let other = core.cell.RefCell.new(Pair(7, 8))
    if cell.as_ptr().is_null() { return 14 }
    if cell.replace(Pair(2, 4)).left != 4 { return 15 }
    if cell.replace_with(fn(mut current: Pair): Pair {
        Pair(current.left + 1, current.right + 1)
    }).left != 2 {
        return 16
    }
    cell.swap(read other)
    if cell.borrow().get_ref().left != 7 ||
        cell.borrow().get_ref().right != 8 ||
        other.borrow().get_ref().left != 3 ||
        other.borrow().get_ref().right != 5 {
        return 17
    }
    *cell.get_mut() = Pair(9, 10)
    if cell.borrow().get_ref().right != 10 { return 18 }
    let cloned = cell.clone()
    if cloned.borrow().get_ref().left != 9 ||
        cloned.borrow().get_ref().right != 10 {
        return 33
    }
    let empty: core.cell.RefCell<i32> = core.cell.RefCell.new(0)
    if empty.`take`() != 0 { return 19 }
    let value = take core.cell.RefCell.new(11i32).into_inner()
    if value != 11 { return 20 }

    let from = core.cell.RefCell<i32>.(From<i32>).from(12)
    if *from.borrow().get_ref() != 12 { return 21 }
    let defaulted: core.cell.RefCell<i32> =
        core.cell.RefCell<i32>.(Default).default()
    if *defaulted.borrow().get_ref() != 0 { return 22 }
    if !(core.cell.RefCell.new(1i32) == core.cell.RefCell.new(1i32)) {
        return 23
    }
    if core.cell.RefCell.new(1i32) >= core.cell.RefCell.new(2i32) {
        return 24
    }
    eq_ok<core.cell.RefCell<i32>>()
    partial_eq_ok<core.cell.RefCell<i32>>()
    ord_ok<core.cell.RefCell<i32>>()
    partial_ord_ok<core.cell.RefCell<i32>>()
    if !debug_is(core.cell.RefCell.new(1i32), "RefCell { value: 1 }") {
        return 28
    }

    let integer = core.cell.RefCell.new(42i32)
    {
        let guard = integer.borrow()
        if !debug_is(guard, "42") || !display_is(guard, "42") {
            return 29
        }
    }
    {
        var guard = integer.borrow_mut()
        if !debug_is(guard, "42") || !display_is(guard, "42") {
            return 30
        }
        *guard.get_mut() = 43
    }
    if *integer.borrow().get_ref() != 43 { return 31 }
    0
}
