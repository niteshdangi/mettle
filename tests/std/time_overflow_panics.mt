// expect-exit: 101
// expect-stderr: overflow when subtracting durations
import std.time.from_secs

fn main(): i32 {
    let underflow = from_secs(1u64) - from_secs(2u64)
    underflow.as_secs() as i32
}
