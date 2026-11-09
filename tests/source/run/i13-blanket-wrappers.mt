// expect-exit: 0
// profiles: debug release

import core.any.Any
import core.borrow.Borrow
import core.convert.From
import core.convert.Into
import alloc.string.ToString
import core.fmt.{ Formatter, Message }

fn any_ok<T: Any>() {}
fn borrow_ok<T: unsized + Borrow<T>>() {}
fn from_ok<T: From<T>>() {}
fn into_ok<T: Into<T>>() {}
fn string_ok<T: ToString>() {}

fn main(): i32 {
    any_ok<core.cell.Ref<i32> from static>()
    borrow_ok<core.cell.Ref<i32>>()
    from_ok<core.cell.Ref<i32>>()
    into_ok<core.cell.Ref<i32>>()

    any_ok<core.cell.RefMut<i32> from static>()
    borrow_ok<core.cell.RefMut<i32>>()
    from_ok<core.cell.RefMut<i32>>()
    into_ok<core.cell.RefMut<i32>>()

    any_ok<Message<region static>>()
    borrow_ok<Message<region static>>()
    from_ok<Message<region static>>()
    into_ok<Message<region static>>()

    borrow_ok<Formatter<region static>>()
    from_ok<Formatter<region static>>()
    into_ok<Formatter<region static>>()
    0
}
