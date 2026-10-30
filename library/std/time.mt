// Monotonic and wall-clock time. `Instant` never goes backwards; `SystemTime`
// can (clock adjustments), so differences are fallible.
import super.sys;

// A length of time: whole seconds plus nanoseconds below one second.
pub copy type Duration { secs: u64; nanos: u32 }

pub fn duration(secs: u64, nanos: u32): Duration {
    Duration(secs + (nanos / 1000000000u32) as u64, nanos % 1000000000u32)
}
pub fn from_secs(secs: u64): Duration { Duration(secs, 0u32) }
pub fn from_millis(millis: u64): Duration { Duration(millis / 1000u64, ((millis % 1000u64) * 1000000u64) as u32) }
pub fn from_micros(micros: u64): Duration { Duration(micros / 1000000u64, ((micros % 1000000u64) * 1000u64) as u32) }
pub fn from_nanos(nanos: u64): Duration { Duration(nanos / 1000000000u64, (nanos % 1000000000u64) as u32) }

extend Duration {
    pub fn as_secs(): u64 { self.secs }
    pub fn subsec_nanos(): u32 { self.nanos }
    pub fn subsec_millis(): u32 { self.nanos / 1000000u32 }
    pub fn subsec_micros(): u32 { self.nanos / 1000u32 }
    pub fn as_millis(): u128 { self.secs as u128 * 1000u128 + (self.nanos / 1000000u32) as u128 }
    pub fn as_micros(): u128 { self.secs as u128 * 1000000u128 + (self.nanos / 1000u32) as u128 }
    pub fn as_nanos(): u128 { self.secs as u128 * 1000000000u128 + self.nanos as u128 }
    pub fn is_zero(): bool { self.secs == 0u64 && self.nanos == 0u32 }

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
