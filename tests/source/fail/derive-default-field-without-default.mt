// expect-error: type 5:23 unsatisfied interface obligation
// expect-error-count: 1
type Plain { x: i32 }
@derive(Default)
type Holder { a: i32; inner: Plain }
fn main(): i32 { 0 }
