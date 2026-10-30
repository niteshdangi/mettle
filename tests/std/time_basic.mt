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
