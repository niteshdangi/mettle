// A dereference through a raw pointer captures the pointer, so writes reach
// the original storage and reads observe later changes.
fn main(): i32 {
    var counter = 5
    let p = core.ptr.from_mut(counter)
    let bump = take fn(): i32 {
        unsafe { *p = *p + 1 }
        unsafe { *p }
    }
    let borrowed = fn(): i32 { unsafe { *p } }
    if bump() != 6 || counter != 6 { return 1 }
    counter = 40
    if borrowed() != 40 || bump() != 41 || counter != 41 { return 2 }
    0
}
