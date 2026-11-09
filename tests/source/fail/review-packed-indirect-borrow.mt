// expect-error: alignment 9:13 unaligned storage cannot form an ordinary view

@packed(1)
copy type Packed { tag:u8; value:i32 }
fn inspect(read value:i32):i32 { value }
fn main() {
    let value = Packed(0u8,42)
    let pointer:fn(read i32):i32 = inspect
    pointer(value.value) - 42
}
