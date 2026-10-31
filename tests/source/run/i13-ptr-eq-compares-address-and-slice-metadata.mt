// ptr.eq is safe and compares the address, and for slice pointers the length.
fn main(): i32 {
    var first = 1
    var second = 1
    let a = core.ptr.from_mut(first)
    let b = core.ptr.from_mut(second)
    if !core.ptr.eq(a, a) { return 1 }
    if core.ptr.eq(a, b) { return 2 }
    if !core.ptr.eq(a, a.cast_const()) { return 3 }
    let values = [1, 2, 3]
    let whole: read [i32] = read values
    let prefix: read [i32] = read values[..2]
    let whole_pointer = whole as ptr<read [i32]>
    let prefix_pointer = prefix as ptr<read [i32]>
    if !core.ptr.eq(whole_pointer, whole_pointer) { return 4 }
    if core.ptr.eq(whole_pointer, prefix_pointer) { return 5 }
    0
}
