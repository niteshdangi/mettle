// expect-error: constant 5:14 assert_unchecked precondition is false
// expect-error: constant 9:14 unreachable_unchecked reached during constant evaluation

const fn invalid_assertion(): i32 {
    unsafe { core.hint.assert_unchecked(false) }
    1
}
const fn reached_unreachable(): i32 {
    unsafe { core.hint.unreachable_unchecked() }
}
const INVALID: i32 = invalid_assertion()
const UNREACHABLE: i32 = reached_unreachable()
fn main(): i32 { 0 }
