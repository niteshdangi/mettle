// expect-exit: 0
// profiles: debug release

import core.any.Any
import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert.From
import core.convert.Into
import core.convert.{TryFrom, TryInto}
import alloc.string.ToString
import alloc.boxed.Heap
import core.cmp.Descending
import core.num.Wrapping
import core.ptr.NonNull
import alloc.rc.LocalShared
import alloc.rc.Weak
import core.iter.Range
import core.iter.RangeInclusive

fn any_ok<T: Any>() {}
fn borrow_ok<T: unsized + Borrow<T>>() {}
fn owned_ok<T: ToOwned>() {}
fn from_ok<T: From<T>>() {}
fn into_ok<T: Into<T>>() {}
fn tryfrom_ok<T: TryFrom<T>>() {}
fn tryinto_ok<T: TryInto<T>>() {}
fn string_ok<T: ToString>() {}
fn send_ok<T: Transferable>() {}
fn sync_ok<T: Shareable>() {}

fn main(): i32 {
    // alloc.boxed.Heap: Any Borrow From Into Send Sync ToOwned ToString
    any_ok<Heap<i32>>()
    borrow_ok<Heap<i32>>()
    from_ok<Heap<i32>>()
    tryfrom_ok<Heap<i32>>()
    tryinto_ok<Heap<i32>>()
    into_ok<Heap<i32>>()
    send_ok<Heap<i32>>()
    sync_ok<Heap<i32>>()
    owned_ok<Heap<i32>>()
    string_ok<Heap<i32>>()

    // core.cell.Cell: Any Borrow From Into Send ToOwned (Sync is negative, see fail tests)
    any_ok<core.cell.Cell<i32>>()
    borrow_ok<core.cell.Cell<i32>>()
    from_ok<core.cell.Cell<i32>>()
    tryfrom_ok<core.cell.Cell<i32>>()
    tryinto_ok<core.cell.Cell<i32>>()
    into_ok<core.cell.Cell<i32>>()
    send_ok<core.cell.Cell<i32>>()

    // core.cell.RefCell: Any Borrow From Into Send ToOwned (Sync is negative, see fail tests)
    any_ok<core.cell.RefCell<i32>>()
    borrow_ok<core.cell.RefCell<i32>>()
    from_ok<core.cell.RefCell<i32>>()
    tryfrom_ok<core.cell.RefCell<i32>>()
    tryinto_ok<core.cell.RefCell<i32>>()
    into_ok<core.cell.RefCell<i32>>()
    send_ok<core.cell.RefCell<i32>>()

    // core.cmp.Descending: Any Borrow From Into Send Sync ToOwned
    any_ok<Descending<i32>>()
    borrow_ok<Descending<i32>>()
    from_ok<Descending<i32>>()
    tryfrom_ok<Descending<i32>>()
    tryinto_ok<Descending<i32>>()
    into_ok<Descending<i32>>()
    send_ok<Descending<i32>>()
    sync_ok<Descending<i32>>()

    // core.mem.ManuallyDrop: Any Borrow From Into Send Sync ToOwned
    any_ok<core.mem.ManuallyDrop<i32>>()
    borrow_ok<core.mem.ManuallyDrop<i32>>()
    from_ok<core.mem.ManuallyDrop<i32>>()
    tryfrom_ok<core.mem.ManuallyDrop<i32>>()
    tryinto_ok<core.mem.ManuallyDrop<i32>>()
    into_ok<core.mem.ManuallyDrop<i32>>()
    send_ok<core.mem.ManuallyDrop<i32>>()
    sync_ok<core.mem.ManuallyDrop<i32>>()

    // core.num.Wrapping: Any Borrow From Into Send Sync ToOwned ToString
    any_ok<Wrapping<i32>>()
    borrow_ok<Wrapping<i32>>()
    from_ok<Wrapping<i32>>()
    tryfrom_ok<Wrapping<i32>>()
    tryinto_ok<Wrapping<i32>>()
    into_ok<Wrapping<i32>>()
    send_ok<Wrapping<i32>>()
    sync_ok<Wrapping<i32>>()
    owned_ok<Wrapping<i32>>()
    string_ok<Wrapping<i32>>()

    // core.ptr.NonNull: Any Borrow From Into ToOwned (Send/Sync are negative, see fail tests)
    any_ok<NonNull<i32>>()
    borrow_ok<NonNull<i32>>()
    from_ok<NonNull<i32>>()
    tryfrom_ok<NonNull<i32>>()
    tryinto_ok<NonNull<i32>>()
    into_ok<NonNull<i32>>()

    // alloc.rc.LocalShared: Any Borrow From Into ToOwned ToString (Send/Sync are negative, see fail tests)
    any_ok<LocalShared<i32>>()
    borrow_ok<LocalShared<i32>>()
    from_ok<LocalShared<i32>>()
    tryfrom_ok<LocalShared<i32>>()
    tryinto_ok<LocalShared<i32>>()
    into_ok<LocalShared<i32>>()
    owned_ok<LocalShared<i32>>()
    string_ok<LocalShared<i32>>()

    // alloc.rc.Weak: Any Borrow From Into ToOwned (Send/Sync are negative, see fail tests)
    any_ok<Weak<i32>>()
    borrow_ok<Weak<i32>>()
    from_ok<Weak<i32>>()
    tryfrom_ok<Weak<i32>>()
    tryinto_ok<Weak<i32>>()
    into_ok<Weak<i32>>()
    owned_ok<Weak<i32>>()

    // core.iter.Range / RangeInclusive (ops::Range, ops::RangeInclusive):
    // Any Borrow From Into Send Sync ToOwned
    any_ok<Range<i32>>()
    borrow_ok<Range<i32>>()
    from_ok<Range<i32>>()
    tryfrom_ok<Range<i32>>()
    tryinto_ok<Range<i32>>()
    into_ok<Range<i32>>()
    send_ok<Range<i32>>()
    sync_ok<Range<i32>>()
    owned_ok<Range<i32>>()

    any_ok<RangeInclusive<i32>>()
    borrow_ok<RangeInclusive<i32>>()
    from_ok<RangeInclusive<i32>>()
    tryfrom_ok<RangeInclusive<i32>>()
    tryinto_ok<RangeInclusive<i32>>()
    into_ok<RangeInclusive<i32>>()
    send_ok<RangeInclusive<i32>>()
    sync_ok<RangeInclusive<i32>>()
    owned_ok<RangeInclusive<i32>>()
    0
}
