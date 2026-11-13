// profiles: debug release
// expect-error-source: std/time.mt
// expect-error: constant 31:64 panic during constant evaluation
// expect-error-count: 1
import std.time.Duration

const BAD_NORMALIZED: Duration = Duration.new(18446744073709551615u64, 1000000000u32)

fn main(): i32 { 0 }
