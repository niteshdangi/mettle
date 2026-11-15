fn increment(value: i32): i32 { value + 1 }
fn interior(): core.cell.UnsafeCell<i32> { core.cell.UnsafeCell.new(7i32) }
unsafe extern "C" fn foreign(value: i32): i32 { value }
fn freeze<T: Freeze>(take value: T): T { value }

copy type CallerLocation<region r> {
    file: read [u8] from r
    line: u64
    column: u64
}
@track_caller
fn locate(): CallerLocation<region static> {
    core.intrinsics.caller_location<CallerLocation<region static>>()
}
@track_caller
fn forwarded_location(): CallerLocation<region static> { locate() }
@layout(i64)
copy enum Tagged { Low = -9, High = 23 }

fn main(): i32 {
    let function: fn(i32): i32 = increment
    let address = core.intrinsics.fn_addr(function)
    if address == 0usize { return 1 }
    if function(4i32) != 5i32 { return 2 }
    let native: fn(): core.cell.UnsafeCell<i32> = interior
    let frozen = freeze(native)
    let value = frozen()
    if unsafe { *value.get() } != 7 { return 3 }
    let c_function: unsafe extern "C" fn(i32): i32 = foreign
    if unsafe { freeze(c_function)(9i32) } != 9 { return 4 }
    let first = locate()
    let second = forwarded_location()
    if second.line != first.line + 1u64 { return 5 }
    let indirect: fn(): CallerLocation<region static> = locate
    let same_function: fn(): CallerLocation<region static> = locate
    let adapted = indirect()
    if adapted.line == 0u64 || adapted.line >= first.line { return 6 }
    if core.intrinsics.fn_addr(indirect) !=
       core.intrinsics.fn_addr(same_function) { return 7 }
    if core.intrinsics.variant_ordinal<Tagged>(Tagged.High) != 1usize ||
       core.intrinsics.variant_ordinal<Tagged>(Tagged.Low) != 0usize { return 8 }
    0
}
