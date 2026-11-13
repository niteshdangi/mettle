// profiles: debug release

import core.cmp.{Eq, Ord, PartialEq, PartialOrd}
import core.clone.Clone
import core.borrow.ToOwned
import alloc.string.ToString
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.fmt.Display
import core.fmt.Write
import core.fmt
import core.ops.{Deref, DerefMut}
import core.text.Text

@derive(Clone)
type Pair {
    left: i32
    right: i32
}

type DisplayTail<T: unsized> {
    header: i32
    values: T
}

extend DisplayTail<[i32]> implements Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try i32.(Display).fmt(self.header, mut f)
        for value in self.values {
            try f.write_str(":")
            try i32.(Display).fmt(value, mut f)
        }
    }
}

fn debug_is<T: unsized + Debug>(read value: T, read expected: Text): bool {
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
fn display_fails<T: Display>(read value: T): bool {
    var buffer = [0u8; 1]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(_) => false,
        failure(_) => true
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
    let copied = cell.to_owned()
    {
        var guard = cell.borrow_mut()
        guard.get_mut().left = 11
    }
    if copied.borrow().get_ref().left != 9 ||
        cell.borrow().get_ref().left != 11 {
        return 39
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
        let rendered = guard.to_string()
        if rendered.as_text() != "42" { return 40 }
    }
    {
        var guard = integer.borrow_mut()
        if *guard.deref() != 42 { return 44 }
        if !debug_is(guard, "42") || !display_is(guard, "42") {
            return 30
        }
        let rendered = guard.to_string()
        if rendered.as_text() != "42" { return 41 }
        *guard.get_mut() = 43
    }
    if *integer.borrow().get_ref() != 43 { return 31 }
    {
        var short = [0u8; 17]
        var writer = fmt.buffer_writer(mut short)
        var formatter = fmt.formatter(mut writer, fmt.spec())
        match capture core.cell.RefCell<i32>.(Debug).fmt(integer, mut formatter) {
            success(_) => { return 42 },
            failure(_) => {}
        }
    }
    {
        var recovered = integer.try_borrow_mut().or_panic()
        if *recovered.get_mut() != 43 { return 43 }
    }
    let array_cell = core.cell.RefCell.new([1i32, 2])
    let other_array = core.cell.RefCell.new([1i32, 2])
    let slice_cell: read core.cell.RefCell<[i32]> = read array_cell
    let other_slice: read core.cell.RefCell<[i32]> = read other_array
    if !slice_cell.eq(other_slice) || !slice_cell.cmp(other_slice).is_eq() {
        return 34
    }
    if !debug_is(slice_cell, "RefCell { value: [1, 2] }") { return 35 }
    {
        let guard = slice_cell.borrow()
        if !debug_is(guard, "[1, 2]") { return 36 }
    }
    {
        var guard = slice_cell.borrow_mut()
        guard.get_mut()[0] = 3
        if !debug_is(guard, "[3, 2]") { return 37 }
        if !debug_is(slice_cell, "RefCell { value: \"<borrowed>\" }") {
            return 38
        }
    }
    if slice_cell.eq(other_slice) || !slice_cell.cmp(other_slice).is_gt() ||
        !other_slice.cmp(slice_cell).is_lt() {
        return 52
    }
    if !slice_cell.partial_cmp(slice_cell).or_panic().is_eq() ||
        !slice_cell.partial_cmp(other_slice).or_panic().is_gt() ||
        core.cell.RefCell.new(f32.NAN).partial_cmp(core.cell.RefCell.new(0.0f32)).is_present() {
        return 53
    }
    let tail_cell = core.cell.RefCell.new(DisplayTail(7, [12i32, 34]))
    let tail: read core.cell.RefCell<DisplayTail<[i32]>> = read tail_cell
    {
        let guard = tail.borrow()
        if !display_is(guard, "7:12:34") || !display_fails(guard) {
            return 45
        }
        let rendered = guard.to_string()
        if rendered.as_text() != "7:12:34" { return 46 }
        match take tail.try_borrow_mut() {
            success(_) => { return 47 },
            failure(_) => {}
        }
    }
    {
        var guard = tail.borrow_mut()
        if !display_is(guard, "7:12:34") || !display_fails(guard) {
            return 48
        }
        guard.get_mut().values[0] = 56
        let rendered = guard.to_string()
        if rendered.as_text() != "7:56:34" { return 49 }
        match take tail.try_borrow() {
            success(_) => { return 50 },
            failure(_) => {}
        }
    }
    {
        var recovered = tail.try_borrow_mut().or_panic()
        if recovered.get_ref().values.len() != 2usize ||
            recovered.get_mut().values[0] != 56 {
            return 51
        }
    }
    0
}
