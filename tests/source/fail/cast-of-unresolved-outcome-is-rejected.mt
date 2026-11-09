// expect-error: type 3:13 invalid scalar conversion
fn main(): i32 {
    let r = failure(9i32) as (i32 throws i32)
    match r { success(v) => v, failure(e) => e }
}
