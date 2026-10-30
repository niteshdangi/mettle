
unsafe extern "C" fn callback(count: i32,args: ...): i32 {
    core::mem::forget(take args)
    count
}
fn main() { unsafe { callback(0,42i32) } }
