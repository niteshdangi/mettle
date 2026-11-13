// expect-error: ownership 2:62 cannot move out of a viewed place
fn wrong(read value: pinned mut i32) { let result = unsafe { value.into_inner_unchecked() } }
fn main() { 0 }
