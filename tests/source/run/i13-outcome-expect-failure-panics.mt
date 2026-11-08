// expect-exit: 101
// profiles: debug release
import core.outcome

fn main(): i32 {
    let failed: (i32 throws i32) = failure(1)
    failed.expect("success required")
}
