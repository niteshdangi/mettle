// expect-error: alignment 6:67 unaligned storage

@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn main() { let value=Packed(0u8,42); let reference=unsafe { read value.value }; *reference }
