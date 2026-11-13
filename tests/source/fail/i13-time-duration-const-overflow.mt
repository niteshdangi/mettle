// profiles: debug release
// expect-error: constant 8:29 panic during constant evaluation
// expect-error: constant 9:31 panic during constant evaluation
// expect-error: constant 10:28 panic during constant evaluation
// expect-error-count: 3
import std.time.Duration

const BAD_HOURS: Duration = Duration.from_hours(5124095576030432u64)
const BAD_MINUTES: Duration = Duration.from_mins(307445734561825861u64)
const BAD_WIDE: Duration = Duration.from_nanos_u128(18446744073709551616000000000u128)

fn main(): i32 { 0 }
