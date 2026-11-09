// expect-exit: 101
// profiles: debug release
import core.outcome

fn main(): i32 {
    let passed: (Outcome<i32, i32>) = success(1)
    passed.expect_err("failure required")
}
