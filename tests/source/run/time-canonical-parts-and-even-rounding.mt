import std.time
import std.time.Duration
import std.panic.{catch_panic, CatchResult}

fn main(): i32 {
    if Duration.from_secs_f64(0.0009765625f64).subsec_nanos() != 976562u32 { return 1 }
    if Duration.from_secs_f32(0.0009765625f32).subsec_nanos() != 976562u32 { return 2 }
    if Duration.from_secs_f64(0.0029296875f64).subsec_nanos() != 2929688u32 { return 3 }
    if !Duration.from_secs_f64(-0.0f64).is_zero() { return 4 }
    if !Duration.from_secs_f64(f64.from_bits(1u64)).is_zero() { return 5 }
    let a = time.system_time_from_parts(0i64, 1000000000u32)
    let b = time.system_time_from_parts(1i64, 0u32)
    if a != b || a < b || a > b { return 6 }
    match take capture a.duration_since(b) {
        success(duration) => { if !duration.is_zero() { return 7 } },
        failure(_) => { return 8 }
    }
    let overflow = catch_panic(fn(): Unit {
        let _time = time.system_time_from_parts(9223372036854775807i64, 1000000000u32)
    })
    match overflow { CatchResult.Panicked(_) => {}, _ => { return 9 } }
    0
}
