// Monotonic and wall-clock time. `Instant` never goes backwards; `SystemTime`
// can (clock adjustments), so differences are fallible.
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.default.Default
import package.core.hash.{Hash, Hasher}
import package.core.ops.{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Sub, SubAssign}
import super.sys
import package.core.clone.Clone

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
        if self.before(other) { return none }
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

    // Strictly shorter than `other`; the public order is PartialOrd/Ord.
    fn before(other: Duration): bool {
        self.secs < other.secs || (self.secs == other.secs && self.nanos < other.nanos)
    }
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

// The operators panic on overflow, as Rust's do; the checked and saturating
// methods report it instead.
fn add_durations(a: Duration, b: Duration): Duration {
    match a.checked_add(b) {
        present(d) => d,
        none => package.core.panic.panic("overflow when adding durations")
    }
}

fn sub_durations(a: Duration, b: Duration): Duration {
    match a.checked_sub(b) {
        present(d) => d,
        none => package.core.panic.panic("overflow when subtracting durations")
    }
}

extend Duration {
    pub fn checked_mul(rhs: u32): Duration? {
        let total = self.as_nanos() * (rhs as u128)
        let secs = total / 1000000000u128
        if secs > 18446744073709551615u128 { return none }
        present(Duration(secs as u64, (total % 1000000000u128) as u32))
    }

    pub fn checked_div(rhs: u32): Duration? {
        if rhs == 0u32 { return none }
        let quotient = self.as_nanos() / (rhs as u128)
        present(Duration((quotient / 1000000000u128) as u64, (quotient % 1000000000u128) as u32))
    }

    pub fn saturating_add(other: Duration): Duration {
        match self.checked_add(other) { present(d) => d, none => Duration(18446744073709551615u64, 999999999u32) }
    }

    pub fn saturating_mul(rhs: u32): Duration {
        match self.checked_mul(rhs) { present(d) => d, none => Duration(18446744073709551615u64, 999999999u32) }
    }

    pub fn abs_diff(other: Duration): Duration {
        if self.before(other) { sub_durations(other, self) } else { sub_durations(self, other) }
    }

    pub fn as_secs_f64(): f64 { (self.secs as f64) + (self.nanos as f64) / 1000000000.0f64 }
    pub fn as_secs_f32(): f32 { (self.secs as f32) + (self.nanos as f32) / 1000000000.0f32 }
}

extend Duration implements PartialEq {
    fn eq(other: read Duration): bool { self.same(other) }
}

extend Duration implements Eq {}

extend Duration implements Default {
    static fn default(): Duration { Duration(0u64, 0u32) }
}

extend Duration implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        self.secs.hash(mut state)
        self.nanos.hash(mut state)
    }
}

extend Duration implements Add<Duration> {
    type Output = Duration
    fn add(rhs: read Duration): Duration { add_durations(self, rhs) }
}

extend Duration implements Sub<Duration> {
    type Output = Duration
    fn sub(rhs: read Duration): Duration { sub_durations(self, rhs) }
}

fn mul_durations(a: Duration, rhs: u32): Duration {
    match a.checked_mul(rhs) {
        present(d) => d,
        none => package.core.panic.panic("overflow when multiplying duration by scalar")
    }
}

fn div_durations(a: Duration, rhs: u32): Duration {
    match a.checked_div(rhs) {
        present(d) => d,
        none => package.core.panic.panic("divide by zero error when dividing duration by scalar")
    }
}

extend Duration implements Mul<u32> {
    type Output = Duration
    fn mul(rhs: read u32): Duration { mul_durations(self, rhs) }
}

extend Duration implements Div<u32> {
    type Output = Duration
    fn div(rhs: read u32): Duration { div_durations(self, rhs) }
}

extend Duration implements AddAssign<Duration> {
    mut fn add_assign(rhs: read Duration): Unit {
        let sum = add_durations(self, rhs)
        self.secs = sum.secs
        self.nanos = sum.nanos
    }
}

extend Duration implements SubAssign<Duration> {
    mut fn sub_assign(rhs: read Duration): Unit {
        let difference = sub_durations(self, rhs)
        self.secs = difference.secs
        self.nanos = difference.nanos
    }
}

extend Duration implements MulAssign<u32> {
    mut fn mul_assign(rhs: read u32): Unit {
        let product = mul_durations(self, rhs)
        self.secs = product.secs
        self.nanos = product.nanos
    }
}

extend Duration implements DivAssign<u32> {
    mut fn div_assign(rhs: read u32): Unit {
        let quotient = div_durations(self, rhs)
        self.secs = quotient.secs
        self.nanos = quotient.nanos
    }
}

extend Instant {
    pub fn checked_sub(d: Duration): Instant? {
        match self.since_start.checked_sub(d) { present(t) => present(Instant(t)), none => none }
    }
    pub fn checked_duration_since(earlier: Instant): Duration? {
        self.since_start.checked_sub(earlier.since_start)
    }
    pub fn saturating_duration_since(earlier: Instant): Duration { self.duration_since(earlier) }
}

extend Instant implements PartialEq {
    fn eq(other: read Instant): bool { self.since_start.same(other.since_start) }
}

extend Instant implements Eq {}

extend Instant implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.since_start.hash(mut state) }
}

extend Instant implements Add<Duration> {
    type Output = Instant
    fn add(rhs: read Duration): Instant { Instant(add_durations(self.since_start, rhs)) }
}

extend Instant implements Sub<Duration> {
    type Output = Instant
    fn sub(rhs: read Duration): Instant { Instant(sub_durations(self.since_start, rhs)) }
}

extend Instant implements Sub<Instant> {
    type Output = Duration
    fn sub(rhs: read Instant): Duration { self.duration_since(rhs) }
}

extend Instant implements AddAssign<Duration> {
    mut fn add_assign(rhs: read Duration): Unit {
        self.since_start = add_durations(self.since_start, rhs)
    }
}

extend Instant implements SubAssign<Duration> {
    mut fn sub_assign(rhs: read Duration): Unit {
        self.since_start = sub_durations(self.since_start, rhs)
    }
}

extend SystemTime {
    pub fn checked_sub(d: Duration): SystemTime? {
        let t = self.total() - d.as_nanos() as i128
        present(from_total(t))
    }

    pub fn elapsed(): Duration throws SystemTimeError {
        try system_now().duration_since(self)
    }
}

extend SystemTime implements PartialEq {
    fn eq(other: read SystemTime): bool { self.secs == other.secs && self.nanos == other.nanos }
}

extend SystemTime implements Eq {}

extend SystemTime implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        self.secs.hash(mut state)
        self.nanos.hash(mut state)
    }
}

extend SystemTime implements Add<Duration> {
    type Output = SystemTime
    fn add(rhs: read Duration): SystemTime {
        match self.checked_add(rhs) {
            present(t) => t,
            none => package.core.panic.panic("overflow when adding duration to system time")
        }
    }
}

extend SystemTime implements Sub<Duration> {
    type Output = SystemTime
    fn sub(rhs: read Duration): SystemTime {
        match self.checked_sub(rhs) {
            present(t) => t,
            none => package.core.panic.panic("overflow when subtracting duration from system time")
        }
    }
}

// Durations and instants order by length; system times by position on the
// wall clock (seconds, then nanoseconds).
extend Duration implements PartialOrd {
    fn partial_cmp(other: read Duration): Ordering? { present(self.cmp(other)) }
}
extend Duration implements Ord {
    fn cmp(other: read Duration): Ordering {
        if self.before(other) { Ordering.Less } else if other.before(self) { Ordering.Greater } else { Ordering.Equal }
    }
}
extend Instant implements PartialOrd {
    fn partial_cmp(other: read Instant): Ordering? { present(self.cmp(other)) }
}
extend Instant implements Ord {
    fn cmp(other: read Instant): Ordering { self.since_start.cmp(read other.since_start) }
}
extend SystemTime implements PartialOrd {
    fn partial_cmp(other: read SystemTime): Ordering? { present(self.cmp(other)) }
}
extend SystemTime implements Ord {
    fn cmp(other: read SystemTime): Ordering {
        if self.secs != other.secs { self.secs.cmp(read other.secs) } else { self.nanos.cmp(read other.nanos) }
    }
}

// Value types duplicate by copy; owners clone their buffers.
extend Duration implements Clone {
    fn clone(): Duration { self }
}
extend Instant implements Clone {
    fn clone(): Instant { self }
}
extend SystemTime implements Clone {
    fn clone(): SystemTime { self }
}
