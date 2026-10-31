// expect-error: name 4:5 unresolved or inaccessible function 'missing'
// An unresolved call inside an async body is reported, not an internal error.
async fn work(value: i32): i32 {
    missing(value)
    0
}
fn main(): i32 { 0 }
