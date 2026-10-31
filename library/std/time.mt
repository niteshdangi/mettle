// Monotonic and wall-clock time. `Instant` never goes backwards; `SystemTime`
// can (clock adjustments), so differences are fallible.
import super.sys

// A length of time: whole seconds plus nanoseconds below one second.
pub copy type Duration { secs: u64; nanos: u32 }

pub fn duration(secs: u64, nanos: u32): Duration {
    Duration(secs + (nanos / 1000000000u32) as u64, nanos % 1000000000u32)
}
pub fn from_secs(secs: u64): Duration { Duration(secs, 0u32) }
pub fn from_millis(millis: u64): Duration { Duration(millis / 1000u64, ((millis % 1000u64) * 1000000u64) as u32) }
pub fn from_micros(micros: u64): Duration { Duration(micros / 1000000u64, ((micros % 1000000u64) * 1000u64) as u32) }
pub fn from_nanos(nanos: u64): Duration { Duration(nanos / 1000000000u64, (nanos % 1000000000u64) as u32) }

fn duration_from_secs_float(secs: f64): Duration? {
    if secs.is_nan() || secs.is_infinite() || secs < 0.0f64 { return none }
    if secs >= 18446744073709551616.0f64 { return none }
    let whole = secs as u64
    var fraction = secs - (whole as f64)
    if fraction < 0.0f64 { fraction = 0.0f64 }
    var nanos = (fraction * 1000000000.0f64).round() as u32
    var seconds = whole
    if nanos >= 1000000000u32 {
        nanos = 0u32
        match seconds.checked_add(1u64) {
            present(next) => { seconds = next },
            none => { return none }
        }
    }
    present(Duration(seconds, nanos))
}

fn duration_or_panic(value: Duration?): Duration {
    match value {
        present(duration) => duration,
        none => package.core.panic.panic("duration overflow")
    }
}

extend Duration {
    pub const ZERO: Duration = Duration(0u64, 0u32)
    pub const MAX: Duration = Duration(0xffffffffffffffffu64, 999999999u32)

    pub static fn new(secs: u64, nanos: u32): Duration { duration(secs, nanos) }
    pub static fn from_hours(hours: u64): Duration {
        duration_or_panic(match hours.checked_mul(3600u64) {
            present(secs) => present(Duration(secs, 0u32)),
            none => none
        })
    }
    pub static fn from_mins(mins: u64): Duration {
        duration_or_panic(match mins.checked_mul(60u64) {
            present(secs) => present(Duration(secs, 0u32)),
            none => none
        })
    }
    pub static fn from_nanos_u128(nanos: u128): Duration {
        let secs = nanos / 1000000000u128
        if secs > 0xffffffffffffffffu128 {
            package.core.panic.panic("duration overflow")
        }
        Duration(secs as u64, (nanos % 1000000000u128) as u32)
    }
    pub static fn try_from_secs_f64(secs: f64): Duration? { duration_from_secs_float(secs) }
    pub static fn try_from_secs_f32(secs: f32): Duration? { duration_from_secs_float(secs as f64) }
    pub static fn from_secs_f64(secs: f64): Duration { duration_or_panic(duration_from_secs_float(secs)) }
    pub static fn from_secs_f32(secs: f32): Duration { duration_or_panic(duration_from_secs_float(secs as f64)) }

    pub fn as_secs(): u64 { self.secs }
    pub fn subsec_nanos(): u32 { self.nanos }
    pub fn subsec_millis(): u32 { self.nanos / 1000000u32 }
    pub fn subsec_micros(): u32 { self.nanos / 1000u32 }
    pub fn as_millis(): u128 { self.secs as u128 * 1000u128 + (self.nanos / 1000000u32) as u128 }
    pub fn as_micros(): u128 { self.secs as u128 * 1000000u128 + (self.nanos / 1000u32) as u128 }
    pub fn as_nanos(): u128 { self.secs as u128 * 1000000000u128 + self.nanos as u128 }
    pub fn as_secs_f64(): f64 { (self.secs as f64) + (self.nanos as f64) / 1000000000.0f64 }
    pub fn as_secs_f32(): f32 { self.as_secs_f64() as f32 }
    pub fn is_zero(): bool { self.secs == 0u64 && self.nanos == 0u32 }

    pub fn abs_diff(other: Duration): Duration {
        if self.secs < other.secs || (self.secs == other.secs && self.nanos < other.nanos) {
            match other.checked_sub(self) { present(gap) => gap, none => Duration.ZERO }
        } else {
            match self.checked_sub(other) { present(gap) => gap, none => Duration.ZERO }
        }
    }
    pub fn saturating_add(other: Duration): Duration {
        match self.checked_add(other) { present(sum) => sum, none => Duration.MAX }
    }
    pub fn checked_mul(rhs: u32): Duration? {
        match self.as_nanos().checked_mul(rhs as u128) {
            present(total) => {
                let secs = total / 1000000000u128
                if secs > 0xffffffffffffffffu128 { return none }
                present(Duration(secs as u64, (total % 1000000000u128) as u32))
            },
            none => none
        }
    }
    pub fn saturating_mul(rhs: u32): Duration {
        match self.checked_mul(rhs) { present(product) => product, none => Duration.MAX }
    }
    pub fn checked_div(rhs: u32): Duration? {
        if rhs == 0u32 { return none }
        let total = self.as_nanos() / (rhs as u128)
        present(Duration((total / 1000000000u128) as u64, (total % 1000000000u128) as u32))
    }
    pub fn mul_f64(rhs: f64): Duration { duration_or_panic(duration_from_secs_float(self.as_secs_f64() * rhs)) }
    pub fn mul_f32(rhs: f32): Duration { duration_or_panic(duration_from_secs_float(self.as_secs_f32() as f64 * rhs as f64)) }
    pub fn div_f64(rhs: f64): Duration { duration_or_panic(duration_from_secs_float(self.as_secs_f64() / rhs)) }
    pub fn div_f32(rhs: f32): Duration { duration_or_panic(duration_from_secs_float(self.as_secs_f32() as f64 / rhs as f64)) }
    pub fn div_duration_f64(other: Duration): f64 { self.as_secs_f64() / other.as_secs_f64() }
    pub fn div_duration_f32(other: Duration): f32 { self.as_secs_f32() / other.as_secs_f32() }

    pub fn checked_add(other: Duration): Duration? {
        var nanos = self.nanos + other.nanos
        var carry = 0u64
        if nanos >= 1000000000u32 { nanos -= 1000000000u32; carry = 1u64 }
        match self.secs.checked_add(other.secs) {
            present(s) => match s.checked_add(carry) {
                present(total) => present(Duration(total, nanos)),
                none => none
            },
            none => none
        }
    }

    pub fn checked_sub(other: Duration): Duration? {
        if self.lt(other) { return none }
        var secs = self.secs - other.secs
        var nanos = 0u32
        if self.nanos >= other.nanos {
            nanos = self.nanos - other.nanos
        } else {
            secs -= 1u64
            nanos = self.nanos + 1000000000u32 - other.nanos
        }
        present(Duration(secs, nanos))
    }

    pub fn saturating_sub(other: Duration): Duration {
        match self.checked_sub(other) { present(d) => d, none => Duration(0u64, 0u32) }
    }

    pub fn lt(other: Duration): bool {
        self.secs < other.secs || (self.secs == other.secs && self.nanos < other.nanos)
    }
    pub fn le(other: Duration): bool { !other.lt(self) }
    pub fn same(other: Duration): bool { self.secs == other.secs && self.nanos == other.nanos }
}

fn clock(which: i32): Duration {
    var out = [0i64; 2]
    let r = unsafe { sys.mettle_rt_clock(which, core.ptr.from_mut(out).cast<i64>()) }
    if r != 0 { package.core.panic.panic("clock_gettime failed") }
    Duration(out[0usize] as u64, out[1usize] as u32)
}

// A point on the monotonic clock.
pub copy type Instant { since_start: Duration }

pub fn now(): Instant { Instant(clock(0)) }

extend Instant {
    pub fn elapsed(): Duration { now().duration_since(self) }
    // Zero if `earlier` is later (the clock is monotonic, so only for misuse).
    pub fn duration_since(earlier: Instant): Duration { self.since_start.saturating_sub(earlier.since_start) }
    pub fn checked_duration_since(earlier: Instant): Duration? {
        self.since_start.checked_sub(earlier.since_start)
    }
    pub fn saturating_duration_since(earlier: Instant): Duration {
        self.since_start.saturating_sub(earlier.since_start)
    }
    pub fn checked_add(d: Duration): Instant? {
        match self.since_start.checked_add(d) { present(t) => present(Instant(t)), none => none }
    }
    pub fn lt(other: Instant): bool { self.since_start.lt(other.since_start) }
}

// A point on the wall clock, as seconds and nanoseconds from the Unix epoch
// (negative seconds precede it).
pub copy type SystemTime { secs: i64; nanos: u32 }

pub fn system_time_from_parts(secs: i64, nanos: u32): SystemTime { SystemTime(secs, nanos) }

pub fn unix_epoch(): SystemTime { SystemTime(0i64, 0u32) }

pub fn system_now(): SystemTime {
    var out = [0i64; 2]
    let r = unsafe { sys.mettle_rt_clock(1, core.ptr.from_mut(out).cast<i64>()) }
    if r != 0 { package.core.panic.panic("clock_gettime failed") }
    SystemTime(out[0usize], out[1usize] as u32)
}

pub copy type SystemTimeError { backwards_by: Duration }

extend SystemTime {
    pub fn unix_secs(): i64 { self.secs }
    pub fn subsec_nanos(): u32 { self.nanos }

    // Time elapsed from `earlier`; fails with the (positive) distance if the
    // wall clock puts `earlier` after `self`.
    pub fn duration_since(earlier: SystemTime): Duration throws SystemTimeError {
        let a = self.total()
        let b = earlier.total()
        if a >= b { return from_i128(a - b) }
        throw SystemTimeError(from_i128(b - a))
    }

    pub fn checked_add(d: Duration): SystemTime? {
        let t = self.total() + d.as_nanos() as i128
        present(from_total(t))
    }

    fn total(): i128 { self.secs as i128 * 1000000000i128 + self.nanos as i128 }
}

fn from_i128(n: i128): Duration {
    Duration((n / 1000000000i128) as u64, (n % 1000000000i128) as u32)
}

fn from_total(n: i128): SystemTime {
    var secs = n / 1000000000i128
    var nanos = n % 1000000000i128
    if nanos < 0i128 { nanos += 1000000000i128; secs -= 1i128 }
    SystemTime(secs as i64, nanos as u32)
}

// Blocks the calling thread for at least `d`.
pub fn sleep(d: Duration): Unit {
    unsafe { sys.mettle_rt_sleep(d.secs, d.nanos) }
}
