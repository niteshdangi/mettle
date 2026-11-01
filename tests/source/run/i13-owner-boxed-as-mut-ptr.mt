import alloc.boxed

fn main(): i32 {
    var owner = boxed.new(3i32)
    let raw = owner.as_mut_ptr()
    unsafe { core.ptr.write(raw, 19i32) }
    if *owner.get() != 19i32 { return 1 }
    0
}
