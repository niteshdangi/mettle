// expect-error: type 2:52 invalid primitive operation
fn main() { let a = 1i32; let b = 2i64; let same = core.ptr.eq(core.ptr.from_ref(a), core.ptr.from_ref(b)); 0 }
