// Monotonic and wall-clock time. `Instant` never goes backwards; `SystemTime`
// can (clock adjustments), so differences are fallible.
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.hash.{Hash, Hasher}
import core.ops.{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Sub, SubAssign}
import core.fmt.{Debug, Display, Formatter}
import core.outcome
import super.sys
import core.clone.Clone

// A length of time: whole seconds plus nanoseconds below one second.
pub copy type Duration { secs: u64; nanos: u32 }

pub const fn duration(secs: u64, nanos: u32): Duration {
    let normalized_secs = match secs.checked_add((nanos / 1000000000u32) as u64) {
        present(value) => value,
        none => core.panic.panic("overflow when constructing duration")
    }
    Duration(normalized_secs, nanos % 1000000000u32)
}
pub fn from_secs(secs: u64): Duration { Duration(secs, 0u32) }
pub fn from_millis(millis: u64): Duration { Duration(millis / 1000u64, ((millis % 1000u64) * 1000000u64) as u32) }
pub fn from_micros(micros: u64): Duration { Duration(micros / 1000000u64, ((micros % 1000000u64) * 1000u64) as u32) }
pub fn from_nanos(nanos: u64): Duration { Duration(nanos / 1000000000u64, (nanos % 1000000000u64) as u32) }

extend Duration {
    pub const ZERO: Duration = Duration(0u64, 0u32)
    pub const MAX: Duration = Duration(18446744073709551615u64, 999999999u32)

    pub static const fn new(secs: u64, nanos: u32): Duration { duration(secs, nanos) }
    pub const fn as_secs(): u64 { self.secs }
    pub const fn subsec_nanos(): u32 { self.nanos }
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

    pub static const fn from_hours(hours: u64): Duration {
        match hours.checked_mul(3600u64) {
            present(secs) => Duration(secs, 0u32),
            none => core.panic.panic("overflow when constructing duration")
        }
    }

    pub static const fn from_mins(minutes: u64): Duration {
        match minutes.checked_mul(60u64) {
            present(secs) => Duration(secs, 0u32),
            none => core.panic.panic("overflow when constructing duration")
        }
    }

    pub static const fn from_nanos_u128(nanos: u128): Duration {
        let secs = nanos / 1000000000u128
        if secs > 18446744073709551615u128 {
            core.panic.panic("overflow when constructing duration")
        }
        Duration(secs as u64, (nanos % 1000000000u128) as u32)
    }

    pub static fn try_from_secs_f32(seconds: f32): (Outcome<Duration, TryFromFloatSecsError>) {
        Duration.try_from_secs_f64(seconds as f64)
    }

    pub static fn try_from_secs_f64(seconds: f64): (Outcome<Duration, TryFromFloatSecsError>) {
        if seconds.is_nan() || seconds.is_infinite() || seconds < 0.0f64 ||
           seconds >= 18446744073709551616.0f64 {
            return failure(TryFromFloatSecsError())
        }
        let bits = seconds.to_bits()
        let exponent = ((bits >> 52u32) & 2047u64) as i32
        var significand = bits & 4503599627370495u64
        var shift = -1074i32
        if exponent != 0 {
            significand |= 4503599627370496u64
            shift = exponent - 1075
        }
        let scaled = significand as u128 * 1000000000u128
        var total = 0u128
        if shift >= 0 {
            total = scaled << (shift as u32)
        } else {
            let right = (-shift) as u32
            if right < 128u32 {
                total = scaled >> right
                let remainder = scaled & ((1u128 << right) - 1u128)
                let halfway = 1u128 << (right - 1u32)
                if remainder > halfway || (remainder == halfway && total % 2u128 != 0u128) {
                    total += 1u128
                }
            }
        }
        let secs = total / 1000000000u128
        if secs > 18446744073709551615u128 {
            failure(TryFromFloatSecsError())
        } else {
            success(Duration(secs as u64, (total % 1000000000u128) as u32))
        }
    }

    pub static fn from_secs_f32(seconds: f32): Duration {
        Duration.from_secs_f64(seconds as f64)
    }

    pub static fn from_secs_f64(seconds: f64): Duration {
        match Duration.try_from_secs_f64(seconds) {
            success(value) => value,
            failure(error) => core.panic.panic("invalid floating-point duration")
        }
    }

    pub fn mul_f32(rhs: f32): Duration { Duration.from_secs_f32(self.as_secs_f32() * rhs) }
    pub fn mul_f64(rhs: f64): Duration { Duration.from_secs_f64(self.as_secs_f64() * rhs) }
    pub fn div_f32(rhs: f32): Duration { Duration.from_secs_f32(self.as_secs_f32() / rhs) }
    pub fn div_f64(rhs: f64): Duration { Duration.from_secs_f64(self.as_secs_f64() / rhs) }
    pub const fn div_duration_f32(rhs: Duration): f32 { self.as_secs_f32() / rhs.as_secs_f32() }
    pub const fn div_duration_f64(rhs: Duration): f64 { self.as_secs_f64() / rhs.as_secs_f64() }
}

pub copy type TryFromFloatSecsError {}

extend TryFromFloatSecsError implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try f.write_str("TryFromFloatSecsError")
    }
}

extend Duration implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try f.write_str("Duration { secs: ")
        try u64.(Display).fmt(self.secs, mut f)
        try f.write_str(", nanos: ")
        try u32.(Display).fmt(self.nanos, mut f)
        try f.write_str(" }")
    }
}
fn clock(which: i32): Duration {
    var out = [0i64; 2]
    let r = unsafe { sys.mettle_rt_clock(which, core.ptr.from_mut(out).cast<i64>()) }
    if r != 0 { core.panic.panic("clock_gettime failed") }
    Duration(out[0usize] as u64, out[1usize] as u32)
}

// A point on the monotonic clock.
pub copy type Instant { since_start: Duration }

pub fn now(): Instant { Instant(clock(0)) }

extend Instant {
    pub static fn now(): Instant { std.time.now() }
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

pub fn system_time_from_parts(secs: i64, nanos: u32): SystemTime {
    let normalized = match secs.checked_add((nanos / 1000000000u32) as i64) {
        present(value) => value,
        none => core.panic.panic("overflow when constructing system time")
    }
    SystemTime(normalized, nanos % 1000000000u32)
}

pub fn unix_epoch(): SystemTime { SystemTime(0i64, 0u32) }

pub fn system_now(): SystemTime {
    var out = [0i64; 2]
    let r = unsafe { sys.mettle_rt_clock(1, core.ptr.from_mut(out).cast<i64>()) }
    if r != 0 { core.panic.panic("clock_gettime failed") }
    SystemTime(out[0usize], out[1usize] as u32)
}

pub copy type SystemTimeError { backwards_by: Duration }

extend SystemTime {
    pub static fn now(): SystemTime { system_now() }
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
        checked_system_time(t)
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

fn checked_system_time(n: i128): SystemTime? {
    if n < -9223372036854775808i128 * 1000000000i128 ||
       n > 9223372036854775807i128 * 1000000000i128 + 999999999i128 {
        return none
    }
    present(from_total(n))
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
        none => core.panic.panic("overflow when adding durations")
    }
}

fn sub_durations(a: Duration, b: Duration): Duration {
    match a.checked_sub(b) {
        present(d) => d,
        none => core.panic.panic("overflow when subtracting durations")
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

    pub const fn as_secs_f64(): f64 { (self.secs as f64) + (self.nanos as f64) / 1000000000.0f64 }
    pub const fn as_secs_f32(): f32 { (self.secs as f32) + (self.nanos as f32) / 1000000000.0f32 }
}

extend Duration implements PartialEq {
    fn eq(read other: Duration): bool { self.same(other) }
}

extend Duration implements Eq {}

extend Duration implements Default {
    static fn default(): Duration { Duration(0u64, 0u32) }
}

extend Duration implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.secs.hash(mut state)
        self.nanos.hash(mut state)
    }
}

extend Duration implements Add<Duration> {
    type Output = Duration
    fn add(read rhs: Duration): Duration { add_durations(self, rhs) }
}

extend Duration implements Sub<Duration> {
    type Output = Duration
    fn sub(read rhs: Duration): Duration { sub_durations(self, rhs) }
}

fn mul_durations(a: Duration, rhs: u32): Duration {
    match a.checked_mul(rhs) {
        present(d) => d,
        none => core.panic.panic("overflow when multiplying duration by scalar")
    }
}

fn div_durations(a: Duration, rhs: u32): Duration {
    match a.checked_div(rhs) {
        present(d) => d,
        none => core.panic.panic("divide by zero error when dividing duration by scalar")
    }
}

extend Duration implements Mul<u32> {
    type Output = Duration
    fn mul(read rhs: u32): Duration { mul_durations(self, rhs) }
}

extend u32 implements Mul<Duration> {
    type Output = Duration
    fn mul(read rhs: Duration): Duration { mul_durations(rhs, self) }
}

extend Duration implements Div<u32> {
    type Output = Duration
    fn div(read rhs: u32): Duration { div_durations(self, rhs) }
}

extend Duration implements AddAssign<Duration> {
    mut fn add_assign(read rhs: Duration): Unit {
        self = add_durations(self, rhs)
    }
}

extend Duration implements SubAssign<Duration> {
    mut fn sub_assign(read rhs: Duration): Unit {
        self = sub_durations(self, rhs)
    }
}

extend Duration implements MulAssign<u32> {
    mut fn mul_assign(read rhs: u32): Unit {
        self = mul_durations(self, rhs)
    }
}

extend Duration implements DivAssign<u32> {
    mut fn div_assign(read rhs: u32): Unit {
        self = div_durations(self, rhs)
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
    fn eq(read other: Instant): bool { self.since_start.same(other.since_start) }
}

extend Instant implements Eq {}

extend Instant implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.since_start.hash(mut state) }
}

extend Instant implements Add<Duration> {
    type Output = Instant
    fn add(read rhs: Duration): Instant { Instant(add_durations(self.since_start, rhs)) }
}

extend Instant implements Sub<Duration> {
    type Output = Instant
    fn sub(read rhs: Duration): Instant { Instant(sub_durations(self.since_start, rhs)) }
}

extend Instant implements Sub<Instant> {
    type Output = Duration
    fn sub(read rhs: Instant): Duration { self.duration_since(rhs) }
}

extend Instant implements AddAssign<Duration> {
    mut fn add_assign(read rhs: Duration): Unit {
        self.since_start = add_durations(self.since_start, rhs)
    }
}

extend Instant implements SubAssign<Duration> {
    mut fn sub_assign(read rhs: Duration): Unit {
        self.since_start = sub_durations(self.since_start, rhs)
    }
}

extend SystemTime {
    pub fn checked_sub(d: Duration): SystemTime? {
        let t = self.total() - d.as_nanos() as i128
        checked_system_time(t)
    }

    pub fn elapsed(): Duration throws SystemTimeError {
        try system_now().duration_since(self)
    }
}

extend SystemTime implements PartialEq {
    fn eq(read other: SystemTime): bool { self.secs == other.secs && self.nanos == other.nanos }
}

extend SystemTime implements Eq {}

extend SystemTime implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.secs.hash(mut state)
        self.nanos.hash(mut state)
    }
}

extend Instant implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try f.write_str("Instant { since_start: ")
        try self.since_start.fmt(mut f)
        try f.write_str(" }")
    }
}

extend SystemTime implements Debug {
    fn fmt(mut f: Formatter): Unit throws core.fmt.Error {
        try f.write_str("SystemTime { secs: ")
        try i64.(Display).fmt(self.secs, mut f)
        try f.write_str(", nanos: ")
        try u32.(Display).fmt(self.nanos, mut f)
        try f.write_str(" }")
    }
}

extend SystemTime implements Add<Duration> {
    type Output = SystemTime
    fn add(read rhs: Duration): SystemTime {
        match self.checked_add(rhs) {
            present(t) => t,
            none => core.panic.panic("overflow when adding duration to system time")
        }
    }
}

extend SystemTime implements Sub<Duration> {
    type Output = SystemTime
    fn sub(read rhs: Duration): SystemTime {
        match self.checked_sub(rhs) {
            present(t) => t,
            none => core.panic.panic("overflow when subtracting duration from system time")
        }
    }
}

extend SystemTime implements AddAssign<Duration> {
    mut fn add_assign(read rhs: Duration): Unit {
        self = self + rhs
    }
}

extend SystemTime implements SubAssign<Duration> {
    mut fn sub_assign(read rhs: Duration): Unit {
        self = self - rhs
    }
}

// Durations and instants order by length; system times by position on the
// wall clock (seconds, then nanoseconds).
extend Duration implements PartialOrd {
    fn partial_cmp(read other: Duration): Ordering? { present(self.cmp(other)) }
}
extend Duration implements Ord {
    fn cmp(read other: Duration): Ordering {
        if self.before(other) { Ordering.Less } else if other.before(self) { Ordering.Greater } else { Ordering.Equal }
    }
}
extend Instant implements PartialOrd {
    fn partial_cmp(read other: Instant): Ordering? { present(self.cmp(other)) }
}
extend Instant implements Ord {
    fn cmp(read other: Instant): Ordering { self.since_start.cmp(read other.since_start) }
}
extend SystemTime implements PartialOrd {
    fn partial_cmp(read other: SystemTime): Ordering? { present(self.cmp(other)) }
}
extend SystemTime implements Ord {
    fn cmp(read other: SystemTime): Ordering {
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
