// Duration, Instant and SystemTime arithmetic: operators, checked and
// saturating forms, equality, hashing and float conversion.
import core.cmp
import core.cmp.{Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.hash.hash_one
import std.io.Error
import std.time.{Duration, Instant, SystemTime, duration, from_millis, from_nanos, from_secs, now, system_now, unix_epoch}

fn run(): i32 throws Error {
    let one_and_half = from_millis(1500u64)
    let two = from_secs(2u64)

    // Operators on Duration.
    if !(one_and_half + from_millis(500u64)).same(two) { return 1 }
    if !(two - one_and_half).same(from_millis(500u64)) { return 2 }
    if !(from_millis(250u64) * 3u32).same(from_millis(750u64)) { return 3 }
    if !(two / 4u32).same(from_millis(500u64)) { return 4 }
    var accumulator = from_secs(1u64)
    accumulator += from_millis(600u64)
    if !accumulator.same(from_millis(1600u64)) { return 5 }
    accumulator -= from_millis(100u64)
    accumulator *= 2u32
    if !accumulator.same(from_secs(3u64)) { return 6 }
    accumulator /= 3u32
    if !accumulator.same(from_secs(1u64)) { return 7 }

    // Equality, default and hashing agree with the representation.
    if !(from_nanos(1500000000u64) == one_and_half) { return 8 }
    if from_secs(1u64) == one_and_half { return 9 }
    if !Duration.(Default).default().is_zero() { return 10 }
    if hash_one(read one_and_half) != hash_one(read from_millis(1500u64)) { return 11 }

    // Checked and saturating forms report overflow instead of wrapping.
    let max_secs = from_secs(18446744073709551615u64)
    match max_secs.checked_mul(2u32) {
        present(d) => { return 12 },
        none => {}
    }
    match two.checked_mul(3u32) {
        present(d) => { if !d.same(from_secs(6u64)) { return 13 } },
        none => { return 14 }
    }
    match two.checked_div(0u32) {
        present(d) => { return 15 },
        none => {}
    }
    if !max_secs.saturating_add(from_secs(1u64)).same(duration(18446744073709551615u64, 999999999u32)) {
        return 16
    }
    if !max_secs.saturating_mul(2u32).same(duration(18446744073709551615u64, 999999999u32)) {
        return 17
    }
    if !one_and_half.abs_diff(two).same(from_millis(500u64)) { return 18 }
    if !two.abs_diff(one_and_half).same(from_millis(500u64)) { return 19 }
    if one_and_half.as_secs_f64() != 1.5f64 { return 20 }
    if from_millis(250u64).as_secs_f32() != 0.25f32 { return 21 }

    // Instant arithmetic keeps the monotonic ordering.
    let start = now()
    let later = start + from_secs(1u64)
    if !(later - start).same(from_secs(1u64)) { return 22 }
    if !(start - from_secs(0u64) == start) { return 23 }
    match start.checked_duration_since(later) {
        present(d) => { return 24 },
        none => {}
    }
    match later.checked_duration_since(start) {
        present(d) => { if !d.same(from_secs(1u64)) { return 25 } },
        none => { return 25 }
    }
    if !start.saturating_duration_since(later).is_zero() { return 26 }
    var moved = start
    moved += from_secs(2u64)
    moved -= from_millis(500u64)
    if !(moved - start).same(from_millis(1500u64)) { return 27 }
    if !(start == start) || start == later { return 28 }

    // SystemTime arithmetic, equality and elapsed time.
    let epoch = unix_epoch()
    let ten = epoch + from_secs(10u64)
    if ten.unix_secs() != 10i64 { return 29 }
    if !(ten - from_secs(10u64) == epoch) { return 30 }
    match ten.checked_sub(from_secs(20u64)) {
        present(t) => { if t.unix_secs() != -10i64 { return 31 } },
        none => { return 32 }
    }
    if hash_one(read epoch) != hash_one(read unix_epoch()) { return 33 }
    let since = capture system_now().elapsed()
    match take since {
        success(d) => { if d.as_secs() > 60u64 { return 34 } },
        failure(e) => { return 35 }
    }
    if ordering() != 0 { return ordering() }
    0
}

// Duration, Instant and SystemTime order through PartialOrd/Ord: operators,
// cmp, and the Ord-based min/max/clamp.
fn ordering(): i32 {
    let short = from_millis(1500u64)
    let long = duration(2u64, 0u32)
    let same = duration(1u64, 500000000u32)
    if !(short < long) || short > long || !(short <= same) || !(short >= same) { return 40 }
    if short.cmp(read long) != Ordering.Less || long.cmp(read short) != Ordering.Greater { return 41 }
    if short.cmp(read same) != Ordering.Equal || short.partial_cmp(read long) != present(Ordering.Less) { return 42 }
    // take consumes Copy values too, so each call gets its own copies.
    let (s1, l1, s2, l2, s3, l3) = (short, long, short, long, short, long)
    if cmp.max(s1, l1) != long || cmp.min(s2, l2) != short { return 43 }
    if cmp.clamp(from_secs(9u64), s3, l3) != long { return 44 }
    let earlier = now()
    let later = earlier + from_millis(5u64)
    if !(earlier < later) || later.cmp(read earlier) != Ordering.Greater || !(earlier <= earlier) { return 45 }
    let epoch = unix_epoch()
    let after = epoch + from_nanos(1u64)
    if !(epoch < after) || after.cmp(read epoch) != Ordering.Greater { return 46 }
    if (epoch - duration(1u64, 0u32)).cmp(read epoch) != Ordering.Less { return 47 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
