// expect-error: attribute 2:12 an unaligned packed field cannot be structurally pinned
@packed(1) type Packed { @pinned value: i64 }
fn main() { 0 }
