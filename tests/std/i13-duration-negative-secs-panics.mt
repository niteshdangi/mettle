// expect-exit: 101
import std.time.Duration

fn main(): i32 {
    let _ = Duration.from_secs_f64(-1.0f64)
    0
}
