@export_name("volatile_large")
unsafe extern "C" fn volatile_large(pointer: ptr<mut [u8; 1025]>): Unit {
    pointer.write_volatile([7u8; 1025])
    let _ = pointer.read_volatile()
}
fn main(): i32 {
    var bytes = [0u8; 1025]
    unsafe {
        volatile_large(core.ptr.from_mut(bytes))
    }
    if bytes[0] == 7u8 && bytes[1024] == 7u8 { 0 } else { 1 }
}
