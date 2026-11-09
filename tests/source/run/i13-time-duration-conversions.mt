// profiles: debug release
import core.cmp.PartialEq
import core.fmt.Debug
import core.hash.hash_one
import std.time.Duration
import std.time.{Instant, SystemTime}
import std.time.from_secs
import std.time.unix_epoch

fn debug<T: Debug>(read value: T): Unit {}

fn main(): i32 {
    if !Duration.new(0u64, 0u32).is_zero() { return 1 }
    if Duration.new(18446744073709551615u64, 999999999u32).as_secs() !=
       18446744073709551615u64 ||
       Duration.new(18446744073709551615u64, 999999999u32).subsec_nanos() != 999999999u32 {
        return 2
    }
    if !Duration.new(1u64, 1500000000u32).same(Duration.new(2u64, 500000000u32)) {
        return 3
    }
    if !Duration.from_hours(2u64).same(from_secs(7200u64)) { return 4 }
    if !Duration.from_mins(3u64).same(from_secs(180u64)) { return 5 }
    if !Duration.from_nanos_u128(1500000001u128).same(Duration.new(1u64, 500000001u32)) {
        return 6
    }
    if !Duration.from_secs_f32(1.25f32).same(Duration.new(1u64, 250000000u32)) {
        return 7
    }
    if !Duration.from_secs_f64(1.5f64).same(Duration.new(1u64, 500000000u32)) {
        return 8
    }
    match Duration.try_from_secs_f32(0.125f32) {
        success(value) => { if !value.same(Duration.new(0u64, 125000000u32)) { return 9 } },
        failure(error) => { return 9 }
    }
    match Duration.try_from_secs_f64(-1.0f64) {
        success(value) => { return 10 },
        failure(error) => { debug(read error) }
    }
    match Duration.try_from_secs_f64(18446744073709551616.0f64) {
        success(value) => { return 22 },
        failure(error) => {}
    }
    match Duration.try_from_secs_f64(0.0000000006f64) {
        success(value) => {
            if !value.same(Duration.new(0u64, 1u32)) { return 23 }
        },
        failure(error) => { return 23 }
    }
    if !Duration.new(2u64, 0u32).mul_f32(1.5f32).same(Duration.new(3u64, 0u32)) {
        return 11
    }
    if !Duration.new(3u64, 0u32).mul_f64(1.5f64).same(Duration.new(4u64, 500000000u32)) {
        return 12
    }
    if !Duration.new(3u64, 0u32).div_f32(2.0f32).same(Duration.new(1u64, 500000000u32)) {
        return 13
    }
    if !Duration.new(3u64, 0u32).div_f64(2.0f64).same(Duration.new(1u64, 500000000u32)) {
        return 14
    }
    if Duration.new(1u64, 0u32).div_duration_f32(Duration.new(2u64, 0u32)) != 0.5f32 {
        return 15
    }
    if Duration.new(1u64, 0u32).div_duration_f64(Duration.new(2u64, 0u32)) != 0.5f64 {
        return 16
    }
    debug(read Duration.new(1u64, 2u32))
    debug(read Instant.now())
    debug(read SystemTime.now())
    let duration_value = Duration.new(1u64, 2u32)
    let copied_duration = duration_value
    if !duration_value.same(copied_duration) { return 19 }
    let instant = Instant.now()
    let copied_instant = instant
    if !(instant == copied_instant) { return 20 }
    if hash_one(read instant) != hash_one(read copied_instant) { return 24 }
    if instant.checked_sub(Duration.new(18446744073709551615u64, 999999999u32)).is_present() {
        return 25
    }
    let system_time = SystemTime.now()
    let copied_system_time = system_time
    if !(system_time == copied_system_time) { return 21 }
    var epoch = unix_epoch()
    epoch += Duration.new(2u64, 0u32)
    if epoch.unix_secs() != 2i64 { return 17 }
    epoch -= Duration.new(1u64, 0u32)
    if epoch.unix_secs() != 1i64 { return 18 }
    0
}
