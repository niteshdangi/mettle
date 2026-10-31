// Integer parsing from `Text` without allocation. Like Rust's `from_str_radix`:
// an optional leading `+` (and `-` for signed types), then at least one digit;
// no whitespace and no separators.

import super.cmp.{Eq, Ordering, PartialEq, PartialOrd, Ord}
import super.clone.Clone
import super.convert.{From, TryFrom}
import super.default.Default
import super.fmt.{Debug, Display, Formatter, Error}
import super.hash.{Hash, Hasher}
import super.ops
import super.text.Text

pub copy enum IntErrorKind { Empty, InvalidDigit, PosOverflow, NegOverflow, InvalidRadix }

extend IntErrorKind implements PartialEq {
    fn eq(other: read IntErrorKind): bool { (self as u8) == (other as u8) }
}
extend IntErrorKind implements Eq {}

pub copy type ParseIntError { pub kind: IntErrorKind }
pub copy type Wrapping<T: Copy> { pub value: T }

extend<T: Copy> Wrapping<T> implements From<T> {
    static fn `from`(value: take T): Wrapping<T> { Wrapping(value) }
}
extend<T: Copy + Clone> Wrapping<T> implements Clone {
    fn clone(): Wrapping<T> { Wrapping(self.value.clone()) }
}
extend<T: Copy + Default> Wrapping<T> implements Default {
    static fn default(): Wrapping<T> { Wrapping(T.(Default).default()) }
}
extend<T: Copy + PartialEq> Wrapping<T> implements PartialEq {
    fn eq(other: read Wrapping<T>): bool { self.value == other.value }
}
extend<T: Copy + Eq> Wrapping<T> implements Eq {}
extend<T: Copy + PartialOrd> Wrapping<T> implements PartialOrd {
    fn partial_cmp(other: read Wrapping<T>): Ordering? {
        self.value.partial_cmp(read other.value)
    }
}
extend<T: Copy + Ord> Wrapping<T> implements Ord {
    fn cmp(other: read Wrapping<T>): Ordering { self.value.cmp(read other.value) }
}
extend<T: Copy + Debug> Wrapping<T> implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("Wrapping(")
        try T.(Debug).fmt(self.value, mut f)
        try f.write_str(")")
    }
}
extend<T: Copy + Display> Wrapping<T> implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        try T.(Display).fmt(self.value, mut f)
    }
}
extend<T: Copy + Hash> Wrapping<T> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.value.hash(mut state) }
}

interface WrappingShiftCount: Copy { fn as_wrapping_shift_count(): u32; }
extend u8 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend u16 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend u32 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self } }
extend u64 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend u128 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend usize implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend i8 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend i16 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend i32 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend i64 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend i128 implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }
extend isize implements WrappingShiftCount { fn as_wrapping_shift_count(): u32 { self as u32 } }

interface WrappingInteger: Copy {
    fn wrapping_integer_div(rhs: Self): Self;
    fn wrapping_integer_rem(rhs: Self): Self;
    fn wrapping_integer_bitand(rhs: Self): Self;
    fn wrapping_integer_bitor(rhs: Self): Self;
    fn wrapping_integer_bitxor(rhs: Self): Self;
    fn wrapping_integer_not(): Self;
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): Self;
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): Self;
}
extend u8 implements WrappingInteger {
    fn wrapping_integer_div(rhs: u8): u8 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: u8): u8 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: u8): u8 { self & rhs }
    fn wrapping_integer_bitor(rhs: u8): u8 { self | rhs }
    fn wrapping_integer_bitxor(rhs: u8): u8 { self ^ rhs }
    fn wrapping_integer_not(): u8 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): u8 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): u8 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend u16 implements WrappingInteger {
    fn wrapping_integer_div(rhs: u16): u16 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: u16): u16 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: u16): u16 { self & rhs }
    fn wrapping_integer_bitor(rhs: u16): u16 { self | rhs }
    fn wrapping_integer_bitxor(rhs: u16): u16 { self ^ rhs }
    fn wrapping_integer_not(): u16 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): u16 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): u16 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend u32 implements WrappingInteger {
    fn wrapping_integer_div(rhs: u32): u32 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: u32): u32 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: u32): u32 { self & rhs }
    fn wrapping_integer_bitor(rhs: u32): u32 { self | rhs }
    fn wrapping_integer_bitxor(rhs: u32): u32 { self ^ rhs }
    fn wrapping_integer_not(): u32 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): u32 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): u32 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend u64 implements WrappingInteger {
    fn wrapping_integer_div(rhs: u64): u64 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: u64): u64 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: u64): u64 { self & rhs }
    fn wrapping_integer_bitor(rhs: u64): u64 { self | rhs }
    fn wrapping_integer_bitxor(rhs: u64): u64 { self ^ rhs }
    fn wrapping_integer_not(): u64 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): u64 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): u64 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend u128 implements WrappingInteger {
    fn wrapping_integer_div(rhs: u128): u128 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: u128): u128 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: u128): u128 { self & rhs }
    fn wrapping_integer_bitor(rhs: u128): u128 { self | rhs }
    fn wrapping_integer_bitxor(rhs: u128): u128 { self ^ rhs }
    fn wrapping_integer_not(): u128 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): u128 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): u128 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend usize implements WrappingInteger {
    fn wrapping_integer_div(rhs: usize): usize { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: usize): usize { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: usize): usize { self & rhs }
    fn wrapping_integer_bitor(rhs: usize): usize { self | rhs }
    fn wrapping_integer_bitxor(rhs: usize): usize { self ^ rhs }
    fn wrapping_integer_not(): usize { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): usize { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): usize { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend i8 implements WrappingInteger {
    fn wrapping_integer_div(rhs: i8): i8 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: i8): i8 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: i8): i8 { self & rhs }
    fn wrapping_integer_bitor(rhs: i8): i8 { self | rhs }
    fn wrapping_integer_bitxor(rhs: i8): i8 { self ^ rhs }
    fn wrapping_integer_not(): i8 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): i8 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): i8 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend i16 implements WrappingInteger {
    fn wrapping_integer_div(rhs: i16): i16 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: i16): i16 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: i16): i16 { self & rhs }
    fn wrapping_integer_bitor(rhs: i16): i16 { self | rhs }
    fn wrapping_integer_bitxor(rhs: i16): i16 { self ^ rhs }
    fn wrapping_integer_not(): i16 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): i16 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): i16 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend i32 implements WrappingInteger {
    fn wrapping_integer_div(rhs: i32): i32 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: i32): i32 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: i32): i32 { self & rhs }
    fn wrapping_integer_bitor(rhs: i32): i32 { self | rhs }
    fn wrapping_integer_bitxor(rhs: i32): i32 { self ^ rhs }
    fn wrapping_integer_not(): i32 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): i32 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): i32 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend i64 implements WrappingInteger {
    fn wrapping_integer_div(rhs: i64): i64 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: i64): i64 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: i64): i64 { self & rhs }
    fn wrapping_integer_bitor(rhs: i64): i64 { self | rhs }
    fn wrapping_integer_bitxor(rhs: i64): i64 { self ^ rhs }
    fn wrapping_integer_not(): i64 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): i64 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): i64 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend i128 implements WrappingInteger {
    fn wrapping_integer_div(rhs: i128): i128 { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: i128): i128 { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: i128): i128 { self & rhs }
    fn wrapping_integer_bitor(rhs: i128): i128 { self | rhs }
    fn wrapping_integer_bitxor(rhs: i128): i128 { self ^ rhs }
    fn wrapping_integer_not(): i128 { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): i128 { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): i128 { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}
extend isize implements WrappingInteger {
    fn wrapping_integer_div(rhs: isize): isize { self.wrapping_div(rhs) }
    fn wrapping_integer_rem(rhs: isize): isize { self.wrapping_rem(rhs) }
    fn wrapping_integer_bitand(rhs: isize): isize { self & rhs }
    fn wrapping_integer_bitor(rhs: isize): isize { self | rhs }
    fn wrapping_integer_bitxor(rhs: isize): isize { self ^ rhs }
    fn wrapping_integer_not(): isize { !self }
    fn wrapping_integer_shl<Rhs: WrappingShiftCount>(rhs: read Rhs): isize { self.wrapping_shl(rhs.as_wrapping_shift_count()) }
    fn wrapping_integer_shr<Rhs: WrappingShiftCount>(rhs: read Rhs): isize { self.wrapping_shr(rhs.as_wrapping_shift_count()) }
}

// These operations deliberately keep wrapping arithmetic distinct from the
// selected profile's ordinary overflow behavior.
extend<T: WrappingInteger> Wrapping<T> implements ops.Div<Wrapping<T>> {
    type Output = Wrapping<T>
    fn div(rhs: read Wrapping<T>): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_div(self.value, rhs.value))
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.Rem<Wrapping<T>> {
    type Output = Wrapping<T>
    fn rem(rhs: read Wrapping<T>): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_rem(self.value, rhs.value))
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitAnd<Wrapping<T>> {
    type Output = Wrapping<T>
    fn bitand(rhs: read Wrapping<T>): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_bitand(self.value, rhs.value))
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitOr<Wrapping<T>> {
    type Output = Wrapping<T>
    fn bitor(rhs: read Wrapping<T>): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_bitor(self.value, rhs.value))
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitXor<Wrapping<T>> {
    type Output = Wrapping<T>
    fn bitxor(rhs: read Wrapping<T>): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_bitxor(self.value, rhs.value))
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.Not {
    type Output = Wrapping<T>
    fn not(): Wrapping<T> { Wrapping(T.(WrappingInteger).wrapping_integer_not(self.value)) }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.DivAssign<Wrapping<T>> {
    mut fn div_assign(rhs: read Wrapping<T>): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_div(self.value, rhs.value)
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.RemAssign<Wrapping<T>> {
    mut fn rem_assign(rhs: read Wrapping<T>): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_rem(self.value, rhs.value)
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitAndAssign<Wrapping<T>> {
    mut fn bitand_assign(rhs: read Wrapping<T>): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_bitand(self.value, rhs.value)
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitOrAssign<Wrapping<T>> {
    mut fn bitor_assign(rhs: read Wrapping<T>): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_bitor(self.value, rhs.value)
    }
}
extend<T: WrappingInteger> Wrapping<T> implements ops.BitXorAssign<Wrapping<T>> {
    mut fn bitxor_assign(rhs: read Wrapping<T>): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_bitxor(self.value, rhs.value)
    }
}
extend<T: WrappingInteger, Rhs: WrappingShiftCount> Wrapping<T> implements ops.Shl<Rhs> {
    type Output = Wrapping<T>
    fn shl(rhs: read Rhs): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_shl(self.value, rhs))
    }
}
extend<T: WrappingInteger, Rhs: WrappingShiftCount> Wrapping<T> implements ops.Shr<Rhs> {
    type Output = Wrapping<T>
    fn shr(rhs: read Rhs): Wrapping<T> {
        Wrapping(T.(WrappingInteger).wrapping_integer_shr(self.value, rhs))
    }
}
extend<T: WrappingInteger, Rhs: WrappingShiftCount> Wrapping<T> implements ops.ShlAssign<Rhs> {
    mut fn shl_assign(rhs: read Rhs): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_shl(self.value, rhs)
    }
}
extend<T: WrappingInteger, Rhs: WrappingShiftCount> Wrapping<T> implements ops.ShrAssign<Rhs> {
    mut fn shr_assign(rhs: read Rhs): Unit {
        self.value = T.(WrappingInteger).wrapping_integer_shr(self.value, rhs)
    }
}

extend Wrapping<u8> {
    pub fn reverse_bits(): Wrapping<u8> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u16> {
    pub fn reverse_bits(): Wrapping<u16> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u32> {
    pub fn reverse_bits(): Wrapping<u32> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u64> {
    pub fn reverse_bits(): Wrapping<u64> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u128> {
    pub fn reverse_bits(): Wrapping<u128> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<usize> {
    pub fn reverse_bits(): Wrapping<usize> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i8> {
    pub fn reverse_bits(): Wrapping<i8> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i16> {
    pub fn reverse_bits(): Wrapping<i16> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i32> {
    pub fn reverse_bits(): Wrapping<i32> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i64> {
    pub fn reverse_bits(): Wrapping<i64> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i128> {
    pub fn reverse_bits(): Wrapping<i128> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<isize> {
    pub fn reverse_bits(): Wrapping<isize> {
        Wrapping(self.value.reverse_bits())
    }
}

fn digit_value(byte: u8): u32 {
    if byte >= 0x30u8 && byte <= 0x39u8 { return (byte - 0x30u8) as u32 }
    if byte >= 0x61u8 && byte <= 0x7au8 { return (byte - 0x61u8) as u32 + 10u32 }
    if byte >= 0x41u8 && byte <= 0x5au8 { return (byte - 0x41u8) as u32 + 10u32 }
    99u32
}

fn failure_of(kind: IntErrorKind): ParseIntError { ParseIntError(kind) }

// Parses the magnitude of `text` into at most `limit`; `negative` selects which
// overflow kind to report. `signed` allows a leading `-`.
fn parse_magnitude(text: read Text, radix: u32, signed: bool, limit_pos: u128, limit_neg: u128): u128 throws ParseIntError {
    if radix < 2u32 || radix > 36u32 { throw failure_of(IntErrorKind.InvalidRadix) }
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw failure_of(IntErrorKind.Empty) }
    var i = 0usize
    var negative = false
    if bytes[0] == 0x2bu8 {
        i = 1usize
    } else {
        if bytes[0] == 0x2du8 && signed { i = 1usize; negative = true }
    }
    if i == bytes.len() { throw failure_of(IntErrorKind.InvalidDigit) }
    let limit = if negative { limit_neg } else { limit_pos }
    var value = 0u128
    var overflowed = false
    while i < bytes.len() {
        let digit = digit_value(bytes[i])
        if digit >= radix { throw failure_of(IntErrorKind.InvalidDigit) }
        if !overflowed {
            match value.checked_mul(radix as u128) {
                present(scaled) => {
                    match scaled.checked_add(digit as u128) {
                        present(next) => { value = next },
                        none => { overflowed = true }
                    }
                },
                none => { overflowed = true }
            }
            if value > limit { overflowed = true }
        }
        i += 1usize
    }
    if overflowed {
        throw failure_of(if negative { IntErrorKind.NegOverflow } else { IntErrorKind.PosOverflow })
    }
    // The sign travels in the top bit of the caller's wide cast: encode via negative flag.
    if negative { value.wrapping_neg() } else { value }
}

pub interface FromText: Sized {
    static fn from_text_radix(text: read Text, radix: u32): Self throws ParseIntError;
    static fn from_text(text: read Text): Self throws ParseIntError {
        try Self.(FromText).from_text_radix(text, 10u32)
    }
}

pub fn parse<T: FromText>(text: read Text): T throws ParseIntError {
    try T.(FromText).from_text(text)
}
extend Text {
    pub fn parse<T: FromText>(): T throws ParseIntError { try parse<T>(read self) }
}
pub fn parse_radix<T: FromText>(text: read Text, radix: u32): T throws ParseIntError {
    try T.(FromText).from_text_radix(text, radix)
}

pub fn from_str_radix<T: FromText>(
    text: read Text, radix: u32
): T throws ParseIntError {
    try parse_radix<T>(text, radix)
}

extend i8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 127u128, 128u128)
        raw as i64 as i8
    }
}
extend i16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 32767u128, 32768u128)
        raw as i64 as i16
    }
}
extend i32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 2147483647u128, 2147483648u128)
        raw as i64 as i32
    }
}
extend i64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as i64
    }
}
extend isize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): isize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as isize
    }
}
extend u8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 255u128, 0u128)
        raw as u8
    }
}
extend u16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 65535u128, 0u128)
        raw as u16
    }
}
extend u32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 4294967295u128, 0u128)
        raw as u32
    }
}
extend u64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 18446744073709551615u128, 0u128)
        raw as u64
    }
}
extend usize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): usize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, ((-1isize) as usize) as u128, 0u128)
        raw as usize
    }
}
extend i128 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i128 throws ParseIntError {
        let raw = try parse_magnitude(
            text, radix, true,
            170141183460469231731687303715884105727u128,
            170141183460469231731687303715884105728u128)
        raw as i128
    }
}
extend u128 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u128 throws ParseIntError {
        try parse_magnitude(
            text, radix, false,
            340282366920938463463374607431768211455u128, 0u128)
    }
}
extend Wrapping<u8> implements ops.Add<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn add(rhs: read Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<u8> implements ops.Sub<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn sub(rhs: read Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<u8> implements ops.Mul<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn mul(rhs: read Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<u8> implements ops.AddAssign<Wrapping<u8>> {
    mut fn add_assign(rhs: read Wrapping<u8>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<u8> implements ops.SubAssign<Wrapping<u8>> {
    mut fn sub_assign(rhs: read Wrapping<u8>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<u8> implements ops.MulAssign<Wrapping<u8>> {
    mut fn mul_assign(rhs: read Wrapping<u8>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<u8> implements ops.Neg {
    type Output = Wrapping<u8>
    fn neg(): Wrapping<u8> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u16> implements ops.Add<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn add(rhs: read Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<u16> implements ops.Sub<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn sub(rhs: read Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<u16> implements ops.Mul<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn mul(rhs: read Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<u16> implements ops.AddAssign<Wrapping<u16>> {
    mut fn add_assign(rhs: read Wrapping<u16>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<u16> implements ops.SubAssign<Wrapping<u16>> {
    mut fn sub_assign(rhs: read Wrapping<u16>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<u16> implements ops.MulAssign<Wrapping<u16>> {
    mut fn mul_assign(rhs: read Wrapping<u16>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<u16> implements ops.Neg {
    type Output = Wrapping<u16>
    fn neg(): Wrapping<u16> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u32> implements ops.Add<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn add(rhs: read Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<u32> implements ops.Sub<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn sub(rhs: read Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<u32> implements ops.Mul<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn mul(rhs: read Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<u32> implements ops.AddAssign<Wrapping<u32>> {
    mut fn add_assign(rhs: read Wrapping<u32>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<u32> implements ops.SubAssign<Wrapping<u32>> {
    mut fn sub_assign(rhs: read Wrapping<u32>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<u32> implements ops.MulAssign<Wrapping<u32>> {
    mut fn mul_assign(rhs: read Wrapping<u32>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<u32> implements ops.Neg {
    type Output = Wrapping<u32>
    fn neg(): Wrapping<u32> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u64> implements ops.Add<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn add(rhs: read Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<u64> implements ops.Sub<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn sub(rhs: read Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<u64> implements ops.Mul<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn mul(rhs: read Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<u64> implements ops.AddAssign<Wrapping<u64>> {
    mut fn add_assign(rhs: read Wrapping<u64>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<u64> implements ops.SubAssign<Wrapping<u64>> {
    mut fn sub_assign(rhs: read Wrapping<u64>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<u64> implements ops.MulAssign<Wrapping<u64>> {
    mut fn mul_assign(rhs: read Wrapping<u64>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<u64> implements ops.Neg {
    type Output = Wrapping<u64>
    fn neg(): Wrapping<u64> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u128> implements ops.Add<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn add(rhs: read Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<u128> implements ops.Sub<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn sub(rhs: read Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<u128> implements ops.Mul<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn mul(rhs: read Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<u128> implements ops.AddAssign<Wrapping<u128>> {
    mut fn add_assign(rhs: read Wrapping<u128>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<u128> implements ops.SubAssign<Wrapping<u128>> {
    mut fn sub_assign(rhs: read Wrapping<u128>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<u128> implements ops.MulAssign<Wrapping<u128>> {
    mut fn mul_assign(rhs: read Wrapping<u128>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<u128> implements ops.Neg {
    type Output = Wrapping<u128>
    fn neg(): Wrapping<u128> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<usize> implements ops.Add<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn add(rhs: read Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<usize> implements ops.Sub<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn sub(rhs: read Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<usize> implements ops.Mul<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn mul(rhs: read Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<usize> implements ops.AddAssign<Wrapping<usize>> {
    mut fn add_assign(rhs: read Wrapping<usize>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<usize> implements ops.SubAssign<Wrapping<usize>> {
    mut fn sub_assign(rhs: read Wrapping<usize>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<usize> implements ops.MulAssign<Wrapping<usize>> {
    mut fn mul_assign(rhs: read Wrapping<usize>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<usize> implements ops.Neg {
    type Output = Wrapping<usize>
    fn neg(): Wrapping<usize> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i8> implements ops.Add<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn add(rhs: read Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<i8> implements ops.Sub<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn sub(rhs: read Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<i8> implements ops.Mul<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn mul(rhs: read Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<i8> implements ops.AddAssign<Wrapping<i8>> {
    mut fn add_assign(rhs: read Wrapping<i8>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<i8> implements ops.SubAssign<Wrapping<i8>> {
    mut fn sub_assign(rhs: read Wrapping<i8>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<i8> implements ops.MulAssign<Wrapping<i8>> {
    mut fn mul_assign(rhs: read Wrapping<i8>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<i8> implements ops.Neg {
    type Output = Wrapping<i8>
    fn neg(): Wrapping<i8> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i16> implements ops.Add<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn add(rhs: read Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<i16> implements ops.Sub<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn sub(rhs: read Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<i16> implements ops.Mul<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn mul(rhs: read Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<i16> implements ops.AddAssign<Wrapping<i16>> {
    mut fn add_assign(rhs: read Wrapping<i16>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<i16> implements ops.SubAssign<Wrapping<i16>> {
    mut fn sub_assign(rhs: read Wrapping<i16>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<i16> implements ops.MulAssign<Wrapping<i16>> {
    mut fn mul_assign(rhs: read Wrapping<i16>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<i16> implements ops.Neg {
    type Output = Wrapping<i16>
    fn neg(): Wrapping<i16> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i32> implements ops.Add<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn add(rhs: read Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<i32> implements ops.Sub<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn sub(rhs: read Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<i32> implements ops.Mul<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn mul(rhs: read Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<i32> implements ops.AddAssign<Wrapping<i32>> {
    mut fn add_assign(rhs: read Wrapping<i32>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<i32> implements ops.SubAssign<Wrapping<i32>> {
    mut fn sub_assign(rhs: read Wrapping<i32>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<i32> implements ops.MulAssign<Wrapping<i32>> {
    mut fn mul_assign(rhs: read Wrapping<i32>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<i32> implements ops.Neg {
    type Output = Wrapping<i32>
    fn neg(): Wrapping<i32> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i64> implements ops.Add<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn add(rhs: read Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<i64> implements ops.Sub<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn sub(rhs: read Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<i64> implements ops.Mul<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn mul(rhs: read Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<i64> implements ops.AddAssign<Wrapping<i64>> {
    mut fn add_assign(rhs: read Wrapping<i64>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<i64> implements ops.SubAssign<Wrapping<i64>> {
    mut fn sub_assign(rhs: read Wrapping<i64>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<i64> implements ops.MulAssign<Wrapping<i64>> {
    mut fn mul_assign(rhs: read Wrapping<i64>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<i64> implements ops.Neg {
    type Output = Wrapping<i64>
    fn neg(): Wrapping<i64> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i128> implements ops.Add<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn add(rhs: read Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<i128> implements ops.Sub<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn sub(rhs: read Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<i128> implements ops.Mul<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn mul(rhs: read Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<i128> implements ops.AddAssign<Wrapping<i128>> {
    mut fn add_assign(rhs: read Wrapping<i128>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<i128> implements ops.SubAssign<Wrapping<i128>> {
    mut fn sub_assign(rhs: read Wrapping<i128>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<i128> implements ops.MulAssign<Wrapping<i128>> {
    mut fn mul_assign(rhs: read Wrapping<i128>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<i128> implements ops.Neg {
    type Output = Wrapping<i128>
    fn neg(): Wrapping<i128> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<isize> implements ops.Add<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn add(rhs: read Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}
extend Wrapping<isize> implements ops.Sub<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn sub(rhs: read Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}
extend Wrapping<isize> implements ops.Mul<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn mul(rhs: read Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}
extend Wrapping<isize> implements ops.AddAssign<Wrapping<isize>> {
    mut fn add_assign(rhs: read Wrapping<isize>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}
extend Wrapping<isize> implements ops.SubAssign<Wrapping<isize>> {
    mut fn sub_assign(rhs: read Wrapping<isize>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}
extend Wrapping<isize> implements ops.MulAssign<Wrapping<isize>> {
    mut fn mul_assign(rhs: read Wrapping<isize>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}
extend Wrapping<isize> implements ops.Neg {
    type Output = Wrapping<isize>
    fn neg(): Wrapping<isize> { Wrapping(self.value.wrapping_neg()) }
}

// ---- Bit isolation, carrying arithmetic and signed difference ----------
// Widths up to 64 bits widen into 128-bit arithmetic; the 128-bit types use
// the schoolbook helpers below so no operation depends on a wider primitive.

fn widening_mul_u128(a: u128, b: u128): (u128, u128) {
    let mask = 0xffffffffffffffffu128
    let a_low = a & mask
    let a_high = a >> 64u128
    let b_low = b & mask
    let b_high = b >> 64u128
    let low_low = a_low * b_low
    let low_high = a_low * b_high
    let high_low = a_high * b_low
    let high_high = a_high * b_high
    let middle = (low_low >> 64u128) + (low_high & mask) + (high_low & mask)
    let low = (low_low & mask) | middle.wrapping_shl(64u32)
    let high = high_high + (low_high >> 64u128) + (high_low >> 64u128) + (middle >> 64u128)
    (low, high)
}

// `a * b + carry + add` as (low, high); the sum always fits in 256 bits.
fn wide_mul_add_u128(a: u128, b: u128, carry: u128, add: u128): (u128, u128) {
    let (low, high) = widening_mul_u128(a, b)
    let (low_carried, first) = low.overflowing_add(carry)
    let (low_added, second) = low_carried.overflowing_add(add)
    (low_added, high + (first as u128) + (second as u128))
}

// Signed 256-bit product plus two sign-extended addends as (unsigned low, signed high).
fn wide_mul_add_i128(a: i128, b: i128, carry: i128, add: i128): (u128, i128) {
    let (low, high) = widening_mul_u128(a as u128, b as u128)
    var signed_high = high as i128
    if a < 0i128 { signed_high = signed_high.wrapping_sub(b) }
    if b < 0i128 { signed_high = signed_high.wrapping_sub(a) }
    let (low_carried, first) = low.overflowing_add(carry as u128)
    let (low_added, second) = low_carried.overflowing_add(add as u128)
    let carry_sign = if carry < 0i128 { -1i128 } else { 0i128 }
    let add_sign = if add < 0i128 { -1i128 } else { 0i128 }
    let adjusted = signed_high.wrapping_add(carry_sign).wrapping_add(add_sign)
    (low_added, adjusted.wrapping_add(first as i128).wrapping_add(second as i128))
}

extend u8 {
    pub fn highest_one(): u32? { if self == 0u8 { none } else { present(u8.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0u8 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): u8 {
        if self == 0u8 { 0u8 } else { 1u8.wrapping_shl(u8.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): u8 { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { u8.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: u8): i8? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0i8) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: u8, carry: bool): (u8, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as u8)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: u8, borrow: bool): (u8, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as u8)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: u8, carry: u8): (u8, u8) { self.carrying_mul_add(rhs, carry, 0u8) }
    pub fn carrying_mul_add(rhs: u8, carry: u8, add: u8): (u8, u8) {
        let wide = (self as u128) * (rhs as u128) + (carry as u128) + (add as u128)
        (wide as u8, (wide >> (u8.BITS as u128)) as u8)
    }
}
extend u16 {
    pub fn highest_one(): u32? { if self == 0u16 { none } else { present(u16.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0u16 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): u16 {
        if self == 0u16 { 0u16 } else { 1u16.wrapping_shl(u16.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): u16 { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { u16.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: u16): i16? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0i16) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: u16, carry: bool): (u16, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as u16)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: u16, borrow: bool): (u16, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as u16)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: u16, carry: u16): (u16, u16) { self.carrying_mul_add(rhs, carry, 0u16) }
    pub fn carrying_mul_add(rhs: u16, carry: u16, add: u16): (u16, u16) {
        let wide = (self as u128) * (rhs as u128) + (carry as u128) + (add as u128)
        (wide as u16, (wide >> (u16.BITS as u128)) as u16)
    }
}
extend u32 {
    pub fn highest_one(): u32? { if self == 0u32 { none } else { present(u32.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0u32 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): u32 {
        if self == 0u32 { 0u32 } else { 1u32.wrapping_shl(u32.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): u32 { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { u32.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: u32): i32? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0i32) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: u32, carry: bool): (u32, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as u32)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: u32, borrow: bool): (u32, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as u32)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: u32, carry: u32): (u32, u32) { self.carrying_mul_add(rhs, carry, 0u32) }
    pub fn carrying_mul_add(rhs: u32, carry: u32, add: u32): (u32, u32) {
        let wide = (self as u128) * (rhs as u128) + (carry as u128) + (add as u128)
        (wide as u32, (wide >> (u32.BITS as u128)) as u32)
    }
}
extend u64 {
    pub fn highest_one(): u32? { if self == 0u64 { none } else { present(u64.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0u64 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): u64 {
        if self == 0u64 { 0u64 } else { 1u64.wrapping_shl(u64.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): u64 { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { u64.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: u64): i64? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0i64) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: u64, carry: bool): (u64, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as u64)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: u64, borrow: bool): (u64, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as u64)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: u64, carry: u64): (u64, u64) { self.carrying_mul_add(rhs, carry, 0u64) }
    pub fn carrying_mul_add(rhs: u64, carry: u64, add: u64): (u64, u64) {
        let wide = (self as u128) * (rhs as u128) + (carry as u128) + (add as u128)
        (wide as u64, (wide >> (u64.BITS as u128)) as u64)
    }
}
extend u128 {
    pub fn highest_one(): u32? { if self == 0u128 { none } else { present(u128.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0u128 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): u128 {
        if self == 0u128 { 0u128 } else { 1u128.wrapping_shl(u128.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): u128 { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { u128.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: u128): i128? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0i128) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: u128, carry: bool): (u128, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as u128)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: u128, borrow: bool): (u128, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as u128)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: u128, carry: u128): (u128, u128) { self.carrying_mul_add(rhs, carry, 0u128) }
    pub fn carrying_mul_add(rhs: u128, carry: u128, add: u128): (u128, u128) {
        wide_mul_add_u128(self, rhs, carry, add)
    }
}
extend usize {
    pub fn highest_one(): u32? { if self == 0usize { none } else { present(usize.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0usize { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): usize {
        if self == 0usize { 0usize } else { 1usize.wrapping_shl(usize.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): usize { self & self.wrapping_neg() }
    pub fn bit_width(): u32 { usize.BITS - self.leading_zeros() }
    pub fn checked_signed_diff(rhs: usize): isize? {
        let diff = self.wrapping_sub(rhs).cast_signed()
        if (self >= rhs) == (diff < 0isize) { none } else { present(diff) }
    }
    pub fn carrying_add(rhs: usize, carry: bool): (usize, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as usize)
        (total, first || second)
    }
    pub fn borrowing_sub(rhs: usize, borrow: bool): (usize, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as usize)
        (total, first || second)
    }
    pub fn carrying_mul(rhs: usize, carry: usize): (usize, usize) { self.carrying_mul_add(rhs, carry, 0usize) }
    pub fn carrying_mul_add(rhs: usize, carry: usize, add: usize): (usize, usize) {
        let wide = (self as u128) * (rhs as u128) + (carry as u128) + (add as u128)
        (wide as usize, (wide >> (usize.BITS as u128)) as usize)
    }
}
extend i8 {
    pub fn highest_one(): u32? { if self == 0i8 { none } else { present(i8.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0i8 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): i8 {
        if self == 0i8 { 0i8 } else { 1i8.wrapping_shl(i8.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): i8 { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: i8, carry: bool): (i8, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as i8)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: i8, borrow: bool): (i8, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as i8)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: i8, carry: i8): (u8, i8) { self.carrying_mul_add(rhs, carry, 0i8) }
    pub fn carrying_mul_add(rhs: i8, carry: i8, add: i8): (u8, i8) {
        let wide = (self as i128) * (rhs as i128) + (carry as i128) + (add as i128)
        (wide as u8, (wide >> (i8.BITS as i128)) as i8)
    }
}
extend i16 {
    pub fn highest_one(): u32? { if self == 0i16 { none } else { present(i16.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0i16 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): i16 {
        if self == 0i16 { 0i16 } else { 1i16.wrapping_shl(i16.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): i16 { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: i16, carry: bool): (i16, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as i16)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: i16, borrow: bool): (i16, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as i16)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: i16, carry: i16): (u16, i16) { self.carrying_mul_add(rhs, carry, 0i16) }
    pub fn carrying_mul_add(rhs: i16, carry: i16, add: i16): (u16, i16) {
        let wide = (self as i128) * (rhs as i128) + (carry as i128) + (add as i128)
        (wide as u16, (wide >> (i16.BITS as i128)) as i16)
    }
}
extend i32 {
    pub fn highest_one(): u32? { if self == 0i32 { none } else { present(i32.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0i32 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): i32 {
        if self == 0i32 { 0i32 } else { 1i32.wrapping_shl(i32.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): i32 { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: i32, carry: bool): (i32, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as i32)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: i32, borrow: bool): (i32, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as i32)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: i32, carry: i32): (u32, i32) { self.carrying_mul_add(rhs, carry, 0i32) }
    pub fn carrying_mul_add(rhs: i32, carry: i32, add: i32): (u32, i32) {
        let wide = (self as i128) * (rhs as i128) + (carry as i128) + (add as i128)
        (wide as u32, (wide >> (i32.BITS as i128)) as i32)
    }
}
extend i64 {
    pub fn highest_one(): u32? { if self == 0i64 { none } else { present(i64.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0i64 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): i64 {
        if self == 0i64 { 0i64 } else { 1i64.wrapping_shl(i64.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): i64 { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: i64, carry: bool): (i64, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as i64)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: i64, borrow: bool): (i64, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as i64)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: i64, carry: i64): (u64, i64) { self.carrying_mul_add(rhs, carry, 0i64) }
    pub fn carrying_mul_add(rhs: i64, carry: i64, add: i64): (u64, i64) {
        let wide = (self as i128) * (rhs as i128) + (carry as i128) + (add as i128)
        (wide as u64, (wide >> (i64.BITS as i128)) as i64)
    }
}
extend i128 {
    pub fn highest_one(): u32? { if self == 0i128 { none } else { present(i128.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0i128 { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): i128 {
        if self == 0i128 { 0i128 } else { 1i128.wrapping_shl(i128.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): i128 { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: i128, carry: bool): (i128, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as i128)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: i128, borrow: bool): (i128, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as i128)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: i128, carry: i128): (u128, i128) { self.carrying_mul_add(rhs, carry, 0i128) }
    pub fn carrying_mul_add(rhs: i128, carry: i128, add: i128): (u128, i128) {
        wide_mul_add_i128(self, rhs, carry, add)
    }
}
extend isize {
    pub fn highest_one(): u32? { if self == 0isize { none } else { present(isize.BITS - 1u32 - self.leading_zeros()) } }
    pub fn lowest_one(): u32? { if self == 0isize { none } else { present(self.trailing_zeros()) } }
    pub fn isolate_highest_one(): isize {
        if self == 0isize { 0isize } else { 1isize.wrapping_shl(isize.BITS - 1u32 - self.leading_zeros()) }
    }
    pub fn isolate_lowest_one(): isize { self & self.wrapping_neg() }
    pub fn carrying_add(rhs: isize, carry: bool): (isize, bool) {
        let (partial, first) = self.overflowing_add(rhs)
        let (total, second) = partial.overflowing_add(carry as isize)
        (total, first != second)
    }
    pub fn borrowing_sub(rhs: isize, borrow: bool): (isize, bool) {
        let (partial, first) = self.overflowing_sub(rhs)
        let (total, second) = partial.overflowing_sub(borrow as isize)
        (total, first != second)
    }
    pub fn carrying_mul(rhs: isize, carry: isize): (usize, isize) { self.carrying_mul_add(rhs, carry, 0isize) }
    pub fn carrying_mul_add(rhs: isize, carry: isize, add: isize): (usize, isize) {
        let wide = (self as i128) * (rhs as i128) + (carry as i128) + (add as i128)
        (wide as usize, (wide >> (isize.BITS as i128)) as isize)
    }
}

// ---- Integer conversions ------------------------------------------------
// `From` is lossless on every target; every other ordered pair of distinct
// integer types converts through `TryFrom` with `TryFromIntError`. The pointer
// sized types follow the portable guarantee of at least 16 bits.

pub copy type TryFromIntError {}

extend TryFromIntError implements Clone { fn clone(): TryFromIntError { TryFromIntError() } }
extend TryFromIntError implements PartialEq { fn eq(other: read TryFromIntError): bool { true } }
extend TryFromIntError implements Eq {}
extend TryFromIntError implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error { try f.write_str("TryFromIntError(())") }
}
extend TryFromIntError implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("out of range integral type conversion attempted")
    }
}

extend u8 implements TryFrom<u16> {
    type Error = TryFromIntError
    static fn try_from(value: take u16): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u8 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (u8 throws TryFromIntError) {
        match value.checked_cast<u8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements From<u8> { static fn `from`(value: take u8): u16 { value as u16 } }
extend u16 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (u16 throws Never) { success(value as u16) }
}
extend u16 implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u16 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (u16 throws TryFromIntError) {
        match value.checked_cast<u16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements From<u8> { static fn `from`(value: take u8): u32 { value as u32 } }
extend u32 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (u32 throws Never) { success(value as u32) }
}
extend u32 implements From<u16> { static fn `from`(value: take u16): u32 { value as u32 } }
extend u32 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (u32 throws Never) { success(value as u32) }
}
extend u32 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u32 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (u32 throws TryFromIntError) {
        match value.checked_cast<u32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements From<u8> { static fn `from`(value: take u8): u64 { value as u64 } }
extend u64 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (u64 throws Never) { success(value as u64) }
}
extend u64 implements From<u16> { static fn `from`(value: take u16): u64 { value as u64 } }
extend u64 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (u64 throws Never) { success(value as u64) }
}
extend u64 implements From<u32> { static fn `from`(value: take u32): u64 { value as u64 } }
extend u64 implements TryFrom<u32> {
    type Error = Never
    static fn try_from(value: take u32): (u64 throws Never) { success(value as u64) }
}
extend u64 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u64 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (u64 throws TryFromIntError) {
        match value.checked_cast<u64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements From<u8> { static fn `from`(value: take u8): u128 { value as u128 } }
extend u128 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (u128 throws Never) { success(value as u128) }
}
extend u128 implements From<u16> { static fn `from`(value: take u16): u128 { value as u128 } }
extend u128 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (u128 throws Never) { success(value as u128) }
}
extend u128 implements From<u32> { static fn `from`(value: take u32): u128 { value as u128 } }
extend u128 implements TryFrom<u32> {
    type Error = Never
    static fn try_from(value: take u32): (u128 throws Never) { success(value as u128) }
}
extend u128 implements From<u64> { static fn `from`(value: take u64): u128 { value as u128 } }
extend u128 implements TryFrom<u64> {
    type Error = Never
    static fn try_from(value: take u64): (u128 throws Never) { success(value as u128) }
}
extend u128 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend u128 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (u128 throws TryFromIntError) {
        match value.checked_cast<u128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements From<u8> { static fn `from`(value: take u8): usize { value as usize } }
extend usize implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (usize throws Never) { success(value as usize) }
}
extend usize implements From<u16> { static fn `from`(value: take u16): usize { value as usize } }
extend usize implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (usize throws Never) { success(value as usize) }
}
extend usize implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<i8> {
    type Error = TryFromIntError
    static fn try_from(value: take i8): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend usize implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (usize throws TryFromIntError) {
        match value.checked_cast<usize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<u8> {
    type Error = TryFromIntError
    static fn try_from(value: take u8): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<u16> {
    type Error = TryFromIntError
    static fn try_from(value: take u16): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<i16> {
    type Error = TryFromIntError
    static fn try_from(value: take i16): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i8 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (i8 throws TryFromIntError) {
        match value.checked_cast<i8>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements From<u8> { static fn `from`(value: take u8): i16 { value as i16 } }
extend i16 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (i16 throws Never) { success(value as i16) }
}
extend i16 implements TryFrom<u16> {
    type Error = TryFromIntError
    static fn try_from(value: take u16): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements From<i8> { static fn `from`(value: take i8): i16 { value as i16 } }
extend i16 implements TryFrom<i8> {
    type Error = Never
    static fn try_from(value: take i8): (i16 throws Never) { success(value as i16) }
}
extend i16 implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i16 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (i16 throws TryFromIntError) {
        match value.checked_cast<i16>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements From<u8> { static fn `from`(value: take u8): i32 { value as i32 } }
extend i32 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (i32 throws Never) { success(value as i32) }
}
extend i32 implements From<u16> { static fn `from`(value: take u16): i32 { value as i32 } }
extend i32 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (i32 throws Never) { success(value as i32) }
}
extend i32 implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements From<i8> { static fn `from`(value: take i8): i32 { value as i32 } }
extend i32 implements TryFrom<i8> {
    type Error = Never
    static fn try_from(value: take i8): (i32 throws Never) { success(value as i32) }
}
extend i32 implements From<i16> { static fn `from`(value: take i16): i32 { value as i32 } }
extend i32 implements TryFrom<i16> {
    type Error = Never
    static fn try_from(value: take i16): (i32 throws Never) { success(value as i32) }
}
extend i32 implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i32 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (i32 throws TryFromIntError) {
        match value.checked_cast<i32>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i64 implements From<u8> { static fn `from`(value: take u8): i64 { value as i64 } }
extend i64 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (i64 throws Never) { success(value as i64) }
}
extend i64 implements From<u16> { static fn `from`(value: take u16): i64 { value as i64 } }
extend i64 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (i64 throws Never) { success(value as i64) }
}
extend i64 implements From<u32> { static fn `from`(value: take u32): i64 { value as i64 } }
extend i64 implements TryFrom<u32> {
    type Error = Never
    static fn try_from(value: take u32): (i64 throws Never) { success(value as i64) }
}
extend i64 implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (i64 throws TryFromIntError) {
        match value.checked_cast<i64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i64 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (i64 throws TryFromIntError) {
        match value.checked_cast<i64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i64 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (i64 throws TryFromIntError) {
        match value.checked_cast<i64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i64 implements From<i8> { static fn `from`(value: take i8): i64 { value as i64 } }
extend i64 implements TryFrom<i8> {
    type Error = Never
    static fn try_from(value: take i8): (i64 throws Never) { success(value as i64) }
}
extend i64 implements From<i16> { static fn `from`(value: take i16): i64 { value as i64 } }
extend i64 implements TryFrom<i16> {
    type Error = Never
    static fn try_from(value: take i16): (i64 throws Never) { success(value as i64) }
}
extend i64 implements From<i32> { static fn `from`(value: take i32): i64 { value as i64 } }
extend i64 implements TryFrom<i32> {
    type Error = Never
    static fn try_from(value: take i32): (i64 throws Never) { success(value as i64) }
}
extend i64 implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (i64 throws TryFromIntError) {
        match value.checked_cast<i64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i64 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (i64 throws TryFromIntError) {
        match value.checked_cast<i64>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i128 implements From<u8> { static fn `from`(value: take u8): i128 { value as i128 } }
extend i128 implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<u16> { static fn `from`(value: take u16): i128 { value as i128 } }
extend i128 implements TryFrom<u16> {
    type Error = Never
    static fn try_from(value: take u16): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<u32> { static fn `from`(value: take u32): i128 { value as i128 } }
extend i128 implements TryFrom<u32> {
    type Error = Never
    static fn try_from(value: take u32): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<u64> { static fn `from`(value: take u64): i128 { value as i128 } }
extend i128 implements TryFrom<u64> {
    type Error = Never
    static fn try_from(value: take u64): (i128 throws Never) { success(value as i128) }
}
extend i128 implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (i128 throws TryFromIntError) {
        match value.checked_cast<i128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i128 implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (i128 throws TryFromIntError) {
        match value.checked_cast<i128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend i128 implements From<i8> { static fn `from`(value: take i8): i128 { value as i128 } }
extend i128 implements TryFrom<i8> {
    type Error = Never
    static fn try_from(value: take i8): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<i16> { static fn `from`(value: take i16): i128 { value as i128 } }
extend i128 implements TryFrom<i16> {
    type Error = Never
    static fn try_from(value: take i16): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<i32> { static fn `from`(value: take i32): i128 { value as i128 } }
extend i128 implements TryFrom<i32> {
    type Error = Never
    static fn try_from(value: take i32): (i128 throws Never) { success(value as i128) }
}
extend i128 implements From<i64> { static fn `from`(value: take i64): i128 { value as i128 } }
extend i128 implements TryFrom<i64> {
    type Error = Never
    static fn try_from(value: take i64): (i128 throws Never) { success(value as i128) }
}
extend i128 implements TryFrom<isize> {
    type Error = TryFromIntError
    static fn try_from(value: take isize): (i128 throws TryFromIntError) {
        match value.checked_cast<i128>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements From<u8> { static fn `from`(value: take u8): isize { value as isize } }
extend isize implements TryFrom<u8> {
    type Error = Never
    static fn try_from(value: take u8): (isize throws Never) { success(value as isize) }
}
extend isize implements TryFrom<u16> {
    type Error = TryFromIntError
    static fn try_from(value: take u16): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<u32> {
    type Error = TryFromIntError
    static fn try_from(value: take u32): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<u64> {
    type Error = TryFromIntError
    static fn try_from(value: take u64): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<u128> {
    type Error = TryFromIntError
    static fn try_from(value: take u128): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<usize> {
    type Error = TryFromIntError
    static fn try_from(value: take usize): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements From<i8> { static fn `from`(value: take i8): isize { value as isize } }
extend isize implements TryFrom<i8> {
    type Error = Never
    static fn try_from(value: take i8): (isize throws Never) { success(value as isize) }
}
extend isize implements From<i16> { static fn `from`(value: take i16): isize { value as isize } }
extend isize implements TryFrom<i16> {
    type Error = Never
    static fn try_from(value: take i16): (isize throws Never) { success(value as isize) }
}
extend isize implements TryFrom<i32> {
    type Error = TryFromIntError
    static fn try_from(value: take i32): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<i64> {
    type Error = TryFromIntError
    static fn try_from(value: take i64): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}
extend isize implements TryFrom<i128> {
    type Error = TryFromIntError
    static fn try_from(value: take i128): (isize throws TryFromIntError) {
        match value.checked_cast<isize>() {
            present(narrowed) => success(narrowed),
            none => failure(TryFromIntError())
        }
    }
}

// Signed `abs` traps on the minimum value like the other operators; the
// non-trapping forms are `checked_abs`, `wrapping_abs`, `saturating_abs` and
// `overflowing_abs`.
extend i8 { pub fn abs(): i8 { self.strict_abs() } }
extend i16 { pub fn abs(): i16 { self.strict_abs() } }
extend i32 { pub fn abs(): i32 { self.strict_abs() } }
extend i64 { pub fn abs(): i64 { self.strict_abs() } }
extend i128 { pub fn abs(): i128 { self.strict_abs() } }
extend isize { pub fn abs(): isize { self.strict_abs() } }
