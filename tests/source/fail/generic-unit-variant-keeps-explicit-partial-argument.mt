// expect-error: type 5:19 explicit generic variant argument does not match expected type
enum Choice<A, B> { Empty; First(A); Second(B) }
fn accept(take value: Choice<i32, bool>): Unit { let _ = value }
fn main(): i32 {
    let partial = Choice<u8, _>.Empty
    accept(take partial)
    0
}
