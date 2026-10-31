// expect-exit: 101
import core.panic

fn main(): i32 {
    panic.assert_eq(1, 2, "not equal")
    0
}
