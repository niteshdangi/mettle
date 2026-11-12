// profiles: debug release
import std.time.Duration

const NORMALIZED: Duration = Duration.new(2u64, 1500000000u32)
const HOURS: Duration = Duration.from_hours(5124095576030431u64)
const MINUTES: Duration = Duration.from_mins(307445734561825860u64)
const WIDE: Duration = Duration.from_nanos_u128(18446744073709551615999999999u128)
const ZERO: Duration = Duration.ZERO
const MAXIMUM: Duration = Duration.MAX
const RATIO32: f32 = Duration.new(1u64, 500000000u32).div_duration_f32(Duration.new(3u64, 0u32))
const RATIO64: f64 = Duration.new(1u64, 500000000u32).div_duration_f64(Duration.new(3u64, 0u32))
const fn normalized_parts(): bool {
    NORMALIZED.as_secs() == 3u64 && NORMALIZED.subsec_nanos() == 500000000u32
}
const NORMALIZATION: bool = normalized_parts()

fn main(): i32 {
    if !NORMALIZATION || !NORMALIZED.same(Duration.new(3u64, 500000000u32)) { return 1 }
    if HOURS.as_secs() != 18446744073709551600u64 ||
        MINUTES.as_secs() != 18446744073709551600u64 { return 2 }
    if !WIDE.same(MAXIMUM) || !ZERO.is_zero() { return 3 }
    if MAXIMUM.checked_add(Duration.new(0u64, 1u32)).is_present() { return 4 }
    if RATIO32 != 0.5f32 || RATIO64 != 0.5f64 { return 5 }
    if !ZERO.div_duration_f64(ZERO).is_nan() { return 6 }
    if !NORMALIZED.div_duration_f32(ZERO).is_infinite() { return 7 }
    0
}
