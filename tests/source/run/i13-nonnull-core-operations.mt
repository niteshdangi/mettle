// NonNull wraps a raw pointer that is never null.
fn main(): i32 {
    let null: ptr<mut i32> = core.ptr.null_mut()
    match core.ptr.NonNull.new(null) { present(n) => { return 1 }, none => {} }
    var values = [10, 20, 30, 40]
    let base = core.ptr.NonNull.from_mut(values)
    let first = base.cast<i32>()
    let third = unsafe { first.add(2usize) }
    if unsafe { third.`read`() } != 30 { return 2 }
    unsafe { third.write(31) }
    if values[2] != 31 { return 3 }
    if unsafe { third.offset_from(first) } != 2isize { return 4 }
    if unsafe { third.offset_from_unsigned(first) } != 2usize { return 5 }
    let back = unsafe { third.sub(1usize) }
    if unsafe { back.`read`() } != 20 { return 6 }
    if first == third || first != first.clone() { return 7 }
    if first.addr() == 0usize || !first.is_aligned() { return 8 }
    if first.align_offset(1usize) != 0usize { return 9 }
    let old = unsafe { first.replace(11) }
    if old != 10 || values[0] != 11 { return 10 }
    unsafe { first.swap(back) }
    if values[0] != 20 || values[1] != 11 { return 11 }
    let dangling = core.ptr.NonNull<i32>.dangling()
    if dangling.addr() != core.mem.align_of<i32>() { return 12 }
    let span = core.ptr.NonNull.slice_from_raw_parts(first, 3usize)
    if span.len() != 3usize || span.is_empty() { return 13 }
    var third_mut = third
    let seen = unsafe { third_mut.as_mut() }
    if *seen != 31 { return 14 }
    0
}
