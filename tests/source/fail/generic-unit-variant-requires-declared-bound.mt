// expect-error: type 5:15 generic argument does not satisfy Copy
type NonCopy {}
enum Choice<T: Copy> { Empty; Value(T) }
fn main(): i32 {
    let bad = Choice<NonCopy>.Empty
    let _ = bad
    0
}
