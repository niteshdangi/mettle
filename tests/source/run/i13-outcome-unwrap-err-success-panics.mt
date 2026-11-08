// expect-exit: 101
// profiles: debug release
import core.outcome

fn main(): i32 {
    let passed: (i32 throws i32) = success(1)
    passed.unwrap_err()
}
