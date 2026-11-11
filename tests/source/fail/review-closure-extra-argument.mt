// expect-error: type 4:26 unknown or excess argument
fn empty(): Unit {}
fn main(): i32 {
    let c = fn() { empty(1); }
    0
}
