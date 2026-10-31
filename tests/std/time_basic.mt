// Monotonic and wall clocks, durations and sleep.
import std.time.{from_millis, from_secs, from_nanos, duration}

fn main(): i32 {
    let d = duration(1u64, 500000000u32)
    if d.as_millis() != 1500u128 || d.as_nanos() != 1500000000u128 { return 1 }
    if !from_millis(1500u64).same(d) || !from_nanos(1500000000u64).same(d) { return 2 }
    match from_secs(1u64).checked_sub(from_millis(1500u64)) { present(x) => { return 3 }, none => {} }
    if !from_secs(1u64).saturating_sub(from_secs(2u64)).is_zero() { return 4 }
    match from_millis(900u64).checked_add(from_millis(300u64)) {
        present(x) => { if !x.same(from_millis(1200u64)) { return 5 } },
        none => { return 6 }
    }
    if !std.time.Duration.ZERO.is_zero() || !std.time.Duration.MAX.same(duration(0xffffffffffffffffu64, 999999999u32)) {
        return 13
    }
    if !std.time.Duration.from_hours(2u64).same(from_secs(7200u64)) { return 14 }
    if !std.time.Duration.from_mins(3u64).same(from_secs(180u64)) { return 15 }
    if !std.time.Duration.from_nanos_u128(1500000000u128).same(d) { return 16 }
    let from_float = std.time.Duration.from_secs_f64(1.5f64)
    if !from_float.same(d) || from_float.as_secs_f64() < 1.5f64 || from_float.as_secs_f64() > 1.5000001f64 {
        return 17
    }
    match std.time.Duration.try_from_secs_f64(-1.0f64) { present(_) => { return 18 }, none => {} }
    match from_secs(2u64).checked_mul(3u32) {
        present(product) => { if !product.same(from_secs(6u64)) { return 19 } },
        none => { return 19 }
    }
    match std.time.Duration.MAX.checked_mul(2u32) { present(_) => { return 20 }, none => {} }
    match from_secs(6u64).checked_div(3u32) {
        present(quotient) => { if !quotient.same(from_secs(2u64)) { return 21 } },
        none => { return 21 }
    }
    match from_secs(1u64).checked_div(0u32) { present(_) => { return 22 }, none => {} }
    if !from_secs(2u64).saturating_add(from_secs(3u64)).same(from_secs(5u64)) { return 23 }
    if !std.time.Duration.MAX.saturating_add(from_secs(1u64)).same(std.time.Duration.MAX) { return 24 }
    if !from_secs(5u64).abs_diff(from_secs(2u64)).same(from_secs(3u64)) { return 25 }
    if !from_secs(2u64).abs_diff(from_secs(5u64)).same(from_secs(3u64)) { return 26 }
    let scaled = from_secs(2u64).mul_f64(1.5f64)
    if !scaled.same(from_secs(3u64)) { return 27 }
    if from_secs(3u64).div_duration_f64(from_secs(2u64)) < 1.5f64 ||
        from_secs(3u64).div_duration_f64(from_secs(2u64)) > 1.5000001f64 {
        return 28
    }
    let early = std.time.now()
    let later = std.time.now()
    match later.checked_duration_since(early) { none => { return 29 }, present(_) => {} }
    match early.checked_duration_since(later) {
        present(gap) => { if !gap.is_zero() { return 30 } },
        none => {}
    }
    if !later.saturating_duration_since(early).lt(from_secs(10u64)) { return 31 }
    let t0 = std.time.now()
    std.time.sleep(from_millis(30u64))
    let waited = t0.elapsed()
    if waited.lt(from_millis(30u64)) { return 7 }
    if !waited.lt(from_secs(10u64)) { return 8 }
    let t1 = std.time.now()
    if t1.lt(t0) { return 9 }
    // The wall clock is after 2020 and orders against the epoch.
    let wall = std.time.system_now()
    let since = capture wall.duration_since(std.time.unix_epoch())
    match take since { success(s) => { if s.as_secs() < 1577836800u64 { return 10 } }, failure(e) => { return 11 } }
    let back = capture std.time.unix_epoch().duration_since(wall)
    if back.is_success() { return 12 }
    0
}
