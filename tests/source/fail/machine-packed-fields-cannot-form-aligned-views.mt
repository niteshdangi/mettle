// expect-error: alignment 7:47 unaligned storage

@layout(C)
@packed(1)
copy type Packed { tag: u8; value: i32 }
fn inspect(read value: i32): i32 { value }
fn main() { let value=Packed(0u8,42); inspect(value.value) }
