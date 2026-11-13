// expect-exit: 101
// profiles: debug release
import core.outcome

fn main(): i32 {
    let failed: (Outcome<i32, i32>) = failure(1)
    failed.or_panic()
}
