// expect-error: ownership 2:128 cannot be passed
fn forget<T>(value: take T) { core.mem.forget(take value) }; unsafe extern "C" fn callback(count: i32,args: ...): i32 { forget(take args); 0 }; fn main() { 0 }
