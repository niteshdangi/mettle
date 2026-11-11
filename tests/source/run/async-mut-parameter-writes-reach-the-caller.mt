module source_helpers;
import core.future.Future
type C { v: i32 }
async fn bump(mut c: C, by: i32): i32 {
    c.v = c.v + by
    c.v
}
fn drive<F: Future<Output = i32>>(take future: F): i32 {
    source_helpers.drive!(future)
}
fn main(): i32 {
    var c = C(1)
    if drive(bump(mut c, 2)) != 3 { return 1 }
    if c.v != 3 { return 2 }
    0
}
