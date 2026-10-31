// Duration, Instant and SystemTime operators, ordering, hashing and Debug text.
import core.fmt.{Debug, Error, Write, Formatter, buffer_writer, formatter, spec, written_text}
import core.hash.{Hash, hash_one}
import core.clone.Clone
import core.default.Default
import std.time.{Duration, Instant, SystemTime, from_millis, from_secs, from_nanos}

fn render(value: read Duration, buffer: mut [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}


fn debug_is(value: Duration, expected: Text): bool throws Error {
    var buffer = [0u8; 48]
    let n = try render(read value, mut buffer)
    match written_text(read buffer, n) {
        present(t) => t == expected,
        none => false
    }
}

fn run(): i32 throws Error {
    let a = from_millis(1500u64)
    let b = from_millis(700u64)
    if !(a + b).same(from_millis(2200u64)) { return 1 }
    if !(a - b).same(from_millis(800u64)) { return 2 }
    if !(b * 3u32).same(from_millis(2100u64)) { return 3 }
    if !(a / 3u32).same(from_millis(500u64)) { return 4 }
    var c = a
    c += b
    if !c.same(from_millis(2200u64)) { return 5 }
    c -= from_millis(200u64)
    if !c.same(from_secs(2u64)) { return 6 }
    c *= 2u32
    if !c.same(from_secs(4u64)) { return 7 }
    c /= 4u32
    if !c.same(from_secs(1u64)) { return 8 }

    if !(b < a) || !(a > b) || a == b || !(a == from_millis(1500u64)) { return 9 }
    if !a.clone().same(a) || !Duration.default().is_zero() { return 10 }
    if hash_one(read a) != hash_one(read from_nanos(1500000000u64)) { return 11 }
    if hash_one(read a) == hash_one(read b) { return 12 }

    if !(try debug_is(from_millis(1500u64), "1.5s")) { return 13 }
    if !(try debug_is(from_secs(2u64), "2s")) { return 14 }
    if !(try debug_is(Duration.ZERO, "0s")) { return 15 }
    if !(try debug_is(from_nanos(1u64), "0.000000001s")) { return 16 }
    if !(try debug_is(from_nanos(1010000u64), "0.00101s")) { return 17 }

    let start = Instant.now()
    let later = start + from_secs(2u64)
    if !(later > start) || later - start != from_secs(2u64) { return 18 }
    if (later - from_secs(2u64)) != start { return 19 }
    var moving = start
    moving += from_secs(1u64)
    moving -= from_secs(1u64)
    if moving != start { return 20 }

    let epoch = SystemTime.UNIX_EPOCH
    let stamp = epoch + from_secs(10u64)
    if stamp.unix_secs() != 10i64 || !(stamp > epoch) { return 21 }
    if (stamp - from_secs(10u64)) != epoch { return 22 }
    var edit = epoch
    edit -= from_secs(5u64)
    if edit.unix_secs() != -5i64 || !(edit < epoch) { return 23 }
    edit += from_secs(5u64)
    if edit != epoch { return 24 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 99
    }
}
