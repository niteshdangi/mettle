// expect-error: constant 7:12 call to non-const function 'effect' in a constant expression
// A constant evaluation drops values by running their destructors, so a destructor that is not constant-evaluable is rejected.
fn effect(): Unit {}

type Guard {
    value: i32
    drop { effect() }
}

const fn build(): i32 {
    let guard = Guard(1)
    guard.value
}
const RESULT: i32 = build()
fn main(): i32 { RESULT }
