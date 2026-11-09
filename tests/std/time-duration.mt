// Duration arithmetic and accessors, Instant ordering and SystemTime offsets.
import std.io.{Error}
import std.time.{Duration, Instant, SystemTime, from_millis, from_micros, from_nanos, from_secs, duration, unix_epoch, now}

fn run(): i32 throws Error {
    let d = duration(3u64, 250000000u32)
    if d.as_secs() != 3u64 || d.subsec_nanos() != 250000000u32 { return 1 }
    if d.subsec_millis() != 250u32 || d.subsec_micros() != 250000u32 { return 2 }
    if d.as_millis() != 3250u128 || d.as_micros() != 3250000u128 { return 3 }
    if d.as_nanos() != 3250000000u128 { return 4 }
    if from_millis(1500u64).as_millis() != 1500u128 || from_micros(2500000u64).subsec_millis() != 500u32 { return 5 }
    if from_nanos(1700000000u64).as_secs() != 1u64 || from_secs(9u64).as_secs() != 9u64 { return 6 }
    if !from_secs(0u64).is_zero() || d.is_zero() { return 7 }
    if d.as_secs_f64() != 3.25f64 { return 8 }

    let sum = d.saturating_add(from_millis(750u64))
    if sum.as_millis() != 4000u128 { return 9 }
    let diff = d.saturating_sub(from_secs(10u64))
    if !diff.is_zero() { return 10 }
    if d.abs_diff(from_secs(1u64)).as_millis() != 2250u128 { return 11 }
    match from_secs(2u64).checked_mul(3u32) {
        present(six) => { if six.as_secs_f32() != 6.0f32 { return 12 } },
        none => { return 12 }
    }
    match from_secs(7u64).checked_div(2u32) {
        present(half) => { if half.as_millis() != 3500u128 { return 13 } },
        none => { return 13 }
    }

    let big = from_secs(18446744073709551615u64)
    match big.checked_add(from_secs(1u64)) {
        present(_) => { return 14 },
        none => {}
    }
    match d.checked_sub(from_secs(4u64)) {
        present(_) => { return 15 },
        none => {}
    }
    match from_secs(5u64).checked_sub(from_secs(2u64)) {
        present(rest) => { if rest.as_secs() != 3u64 { return 16 } },
        none => { return 16 }
    }

    let start = now()
    let later = start.checked_add(from_millis(5u64))
    match later {
        present(instant) => { if instant.duration_since(start).as_millis() != 5u128 { return 17 } },
        none => { return 17 }
    }
    if !start.saturating_duration_since(start).is_zero() { return 18 }
    if start.elapsed().as_secs() > 60u64 { return 19 }

    let epoch = unix_epoch()
    match epoch.checked_add(from_secs(100u64)) {
        present(after) => {
            let gap = capture after.duration_since(epoch)
            match take gap {
                success(elapsed) => { if elapsed.as_secs() != 100u64 { return 20 } },
                failure(_) => { return 20 }
            }
        },
        none => { return 20 }
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
