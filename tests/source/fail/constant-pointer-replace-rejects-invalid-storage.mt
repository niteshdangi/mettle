// expect-error: constant 7:14 constant value is not fully initialized
// expect-error: constant 11:14 constant pointer is dangling, misaligned or out of bounds
// expect-error: constant 20:14 constant value is not fully initialized
const fn uninitialized(): i32 {
    var storage = core.mem.MaybeUninit<i32>.uninit()
    let pointer = storage.as_mut_ptr()
    unsafe { pointer.replace(7i32) }
}

const fn dangling(): i32 {
    unsafe { core.ptr.null_mut<i32>().replace(7i32) }
}

const UNINITIALIZED: i32 = uninitialized()
const DANGLING: i32 = dangling()
fn main(): i32 { 0 }

const fn unchecked_extraction(): i32 {
    let storage = core.mem.MaybeUninit<i32>.uninit()
    unsafe { storage.assume_init() }
}
const EXTRACTED: i32 = unchecked_extraction()
