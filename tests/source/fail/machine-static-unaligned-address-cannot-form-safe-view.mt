// expect-error: constant 2:129 unaligned
@packed(1) copy type Packed { tag: u8; value: i32 }; static VALUE: Packed = Packed(0u8,42); static VIEW: read i32 from static = read VALUE.value; fn main() { 0 }
