// Integer parsing from `Text` without allocation. Like Rust's `from_str_radix`:
// an optional leading `+` (and `-` for signed types), then at least one digit;
// no whitespace and no separators.

import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.clone.Clone
import super.convert.{From, TryFrom}
import super.default.Default
import super.error.{Error as CoreError}
import super.fmt.{Binary, Debug, Display, Error, Formatter, LowerHex, Octal, UpperHex}
import super.hash.{Hash, Hasher}
import super.iter.{Iterator, Phantom, Product, Sum}
import super.slice
import super.ops.{Add, AddAssign, BitAnd, BitAndAssign, BitOr, BitOrAssign}
import super.ops.{BitXor, BitXorAssign, Div, DivAssign, Mul, MulAssign}
import super.ops.{Neg, Not, Rem, RemAssign, Shl, ShlAssign}
import super.ops.{Shr, ShrAssign, Sub, SubAssign}
import super.text.{from_utf8_unchecked, FromStr, Text}

pub copy enum IntErrorKind {
    Empty, InvalidDigit, PosOverflow, NegOverflow, InvalidRadix, Zero
}

extend IntErrorKind implements PartialEq {
    fn eq(read other: IntErrorKind): bool { (self as u8) == (other as u8) }
}
extend IntErrorKind implements Eq {}
extend IntErrorKind implements Clone {
    fn clone(): IntErrorKind { self }
}
extend IntErrorKind implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { state.write_u8(self as u8) }
}
extend IntErrorKind implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            IntErrorKind.Empty => try f.write_str("Empty"),
            IntErrorKind.InvalidDigit => try f.write_str("InvalidDigit"),
            IntErrorKind.PosOverflow => try f.write_str("PosOverflow"),
            IntErrorKind.NegOverflow => try f.write_str("NegOverflow"),
            IntErrorKind.Zero => try f.write_str("Zero"),
            IntErrorKind.InvalidRadix => try f.write_str("InvalidRadix")
        }
    }
}

pub copy type ParseIntError { pub kind: IntErrorKind }

extend ParseIntError implements PartialEq {
    fn eq(read other: ParseIntError): bool { self.kind == other.kind }
}
extend ParseIntError implements Eq {}
extend ParseIntError implements Clone {
    fn clone(): ParseIntError { ParseIntError(self.kind.clone()) }
}
extend ParseIntError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("ParseIntError")
        try debug.field("kind", read self.kind)
        try debug.finish()
    }
}
extend ParseIntError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self.kind {
            IntErrorKind.Empty => try f.write_str("cannot parse integer from empty string"),
            IntErrorKind.InvalidDigit => try f.write_str("invalid digit found in string"),
            IntErrorKind.PosOverflow => try f.write_str("number too large to fit in target type"),
            IntErrorKind.NegOverflow => try f.write_str("number too small to fit in target type"),
            IntErrorKind.Zero => try f.write_str("number would be zero for non-zero type"),
            IntErrorKind.InvalidRadix => try f.write_str("radix must be within 2..=36")
        }
    }
}
extend ParseIntError implements CoreError {}
pub copy type Wrapping<T: Copy> { pub value: T }

extend<T: Copy + Default> Wrapping<T> implements Default {
    static fn default(): Wrapping<T> {
        Wrapping(T.(Default).default())
    }
}

extend Wrapping<i8> implements Sum {
    static fn zero(): Wrapping<i8> { Wrapping(0i8) }
    fn plus(take other: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<i16> implements Sum {
    static fn zero(): Wrapping<i16> { Wrapping(0i16) }
    fn plus(take other: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<i32> implements Sum {
    static fn zero(): Wrapping<i32> { Wrapping(0i32) }
    fn plus(take other: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<i64> implements Sum {
    static fn zero(): Wrapping<i64> { Wrapping(0i64) }
    fn plus(take other: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<i128> implements Sum {
    static fn zero(): Wrapping<i128> { Wrapping(0i128) }
    fn plus(take other: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<isize> implements Sum {
    static fn zero(): Wrapping<isize> { Wrapping(0isize) }
    fn plus(take other: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<u8> implements Sum {
    static fn zero(): Wrapping<u8> { Wrapping(0u8) }
    fn plus(take other: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<u16> implements Sum {
    static fn zero(): Wrapping<u16> { Wrapping(0u16) }
    fn plus(take other: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<u32> implements Sum {
    static fn zero(): Wrapping<u32> { Wrapping(0u32) }
    fn plus(take other: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<u64> implements Sum {
    static fn zero(): Wrapping<u64> { Wrapping(0u64) }
    fn plus(take other: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<u128> implements Sum {
    static fn zero(): Wrapping<u128> { Wrapping(0u128) }
    fn plus(take other: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}
extend Wrapping<usize> implements Sum {
    static fn zero(): Wrapping<usize> { Wrapping(0usize) }
    fn plus(take other: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_add(other.value))
    }
}

extend Wrapping<i8> implements Product {
    static fn one(): Wrapping<i8> { Wrapping(1i8) }
    fn times(take other: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<i16> implements Product {
    static fn one(): Wrapping<i16> { Wrapping(1i16) }
    fn times(take other: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<i32> implements Product {
    static fn one(): Wrapping<i32> { Wrapping(1i32) }
    fn times(take other: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<i64> implements Product {
    static fn one(): Wrapping<i64> { Wrapping(1i64) }
    fn times(take other: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<i128> implements Product {
    static fn one(): Wrapping<i128> { Wrapping(1i128) }
    fn times(take other: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<isize> implements Product {
    static fn one(): Wrapping<isize> { Wrapping(1isize) }
    fn times(take other: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<u8> implements Product {
    static fn one(): Wrapping<u8> { Wrapping(1u8) }
    fn times(take other: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<u16> implements Product {
    static fn one(): Wrapping<u16> { Wrapping(1u16) }
    fn times(take other: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<u32> implements Product {
    static fn one(): Wrapping<u32> { Wrapping(1u32) }
    fn times(take other: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<u64> implements Product {
    static fn one(): Wrapping<u64> { Wrapping(1u64) }
    fn times(take other: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<u128> implements Product {
    static fn one(): Wrapping<u128> { Wrapping(1u128) }
    fn times(take other: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}
extend Wrapping<usize> implements Product {
    static fn one(): Wrapping<usize> { Wrapping(1usize) }
    fn times(take other: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_mul(other.value))
    }
}

extend<region r> Wrapping<i8> implements Sum<read Wrapping<i8> from r> {
    static fn zero(): Wrapping<i8> { Wrapping(0i8) }
    fn plus(take other: read Wrapping<i8> from r): Wrapping<i8> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<i16> implements Sum<read Wrapping<i16> from r> {
    static fn zero(): Wrapping<i16> { Wrapping(0i16) }
    fn plus(take other: read Wrapping<i16> from r): Wrapping<i16> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<i32> implements Sum<read Wrapping<i32> from r> {
    static fn zero(): Wrapping<i32> { Wrapping(0i32) }
    fn plus(take other: read Wrapping<i32> from r): Wrapping<i32> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<i64> implements Sum<read Wrapping<i64> from r> {
    static fn zero(): Wrapping<i64> { Wrapping(0i64) }
    fn plus(take other: read Wrapping<i64> from r): Wrapping<i64> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<i128> implements Sum<read Wrapping<i128> from r> {
    static fn zero(): Wrapping<i128> { Wrapping(0i128) }
    fn plus(take other: read Wrapping<i128> from r): Wrapping<i128> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<isize> implements Sum<read Wrapping<isize> from r> {
    static fn zero(): Wrapping<isize> { Wrapping(0isize) }
    fn plus(take other: read Wrapping<isize> from r): Wrapping<isize> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<u8> implements Sum<read Wrapping<u8> from r> {
    static fn zero(): Wrapping<u8> { Wrapping(0u8) }
    fn plus(take other: read Wrapping<u8> from r): Wrapping<u8> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<u16> implements Sum<read Wrapping<u16> from r> {
    static fn zero(): Wrapping<u16> { Wrapping(0u16) }
    fn plus(take other: read Wrapping<u16> from r): Wrapping<u16> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<u32> implements Sum<read Wrapping<u32> from r> {
    static fn zero(): Wrapping<u32> { Wrapping(0u32) }
    fn plus(take other: read Wrapping<u32> from r): Wrapping<u32> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<u64> implements Sum<read Wrapping<u64> from r> {
    static fn zero(): Wrapping<u64> { Wrapping(0u64) }
    fn plus(take other: read Wrapping<u64> from r): Wrapping<u64> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<u128> implements Sum<read Wrapping<u128> from r> {
    static fn zero(): Wrapping<u128> { Wrapping(0u128) }
    fn plus(take other: read Wrapping<u128> from r): Wrapping<u128> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}
extend<region r> Wrapping<usize> implements Sum<read Wrapping<usize> from r> {
    static fn zero(): Wrapping<usize> { Wrapping(0usize) }
    fn plus(take other: read Wrapping<usize> from r): Wrapping<usize> {
        let value = *other
        Wrapping(self.value.wrapping_add(value.value))
    }
}

extend<region r> Wrapping<i8> implements Product<read Wrapping<i8> from r> {
    static fn one(): Wrapping<i8> { Wrapping(1i8) }
    fn times(take other: read Wrapping<i8> from r): Wrapping<i8> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<i16> implements Product<read Wrapping<i16> from r> {
    static fn one(): Wrapping<i16> { Wrapping(1i16) }
    fn times(take other: read Wrapping<i16> from r): Wrapping<i16> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<i32> implements Product<read Wrapping<i32> from r> {
    static fn one(): Wrapping<i32> { Wrapping(1i32) }
    fn times(take other: read Wrapping<i32> from r): Wrapping<i32> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<i64> implements Product<read Wrapping<i64> from r> {
    static fn one(): Wrapping<i64> { Wrapping(1i64) }
    fn times(take other: read Wrapping<i64> from r): Wrapping<i64> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<i128> implements Product<read Wrapping<i128> from r> {
    static fn one(): Wrapping<i128> { Wrapping(1i128) }
    fn times(take other: read Wrapping<i128> from r): Wrapping<i128> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<isize> implements Product<read Wrapping<isize> from r> {
    static fn one(): Wrapping<isize> { Wrapping(1isize) }
    fn times(take other: read Wrapping<isize> from r): Wrapping<isize> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<u8> implements Product<read Wrapping<u8> from r> {
    static fn one(): Wrapping<u8> { Wrapping(1u8) }
    fn times(take other: read Wrapping<u8> from r): Wrapping<u8> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<u16> implements Product<read Wrapping<u16> from r> {
    static fn one(): Wrapping<u16> { Wrapping(1u16) }
    fn times(take other: read Wrapping<u16> from r): Wrapping<u16> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<u32> implements Product<read Wrapping<u32> from r> {
    static fn one(): Wrapping<u32> { Wrapping(1u32) }
    fn times(take other: read Wrapping<u32> from r): Wrapping<u32> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<u64> implements Product<read Wrapping<u64> from r> {
    static fn one(): Wrapping<u64> { Wrapping(1u64) }
    fn times(take other: read Wrapping<u64> from r): Wrapping<u64> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<u128> implements Product<read Wrapping<u128> from r> {
    static fn one(): Wrapping<u128> { Wrapping(1u128) }
    fn times(take other: read Wrapping<u128> from r): Wrapping<u128> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}
extend<region r> Wrapping<usize> implements Product<read Wrapping<usize> from r> {
    static fn one(): Wrapping<usize> { Wrapping(1usize) }
    fn times(take other: read Wrapping<usize> from r): Wrapping<usize> {
        let value = *other
        Wrapping(self.value.wrapping_mul(value.value))
    }
}

extend Wrapping<i8> implements Add<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn add(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<i8> implements Sub<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn sub(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<i8> implements Mul<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn mul(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<i8> implements Div<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn div(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<i8> implements Rem<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn rem(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<i8> implements BitAnd<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn bitand(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<i8> implements BitOr<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn bitor(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<i8> implements BitXor<Wrapping<i8>> {
    type Output = Wrapping<i8>
    fn bitxor(read rhs: Wrapping<i8>): Wrapping<i8> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<i8> implements Shl<usize> {
    type Output = Wrapping<i8>
    fn shl(read rhs: usize): Wrapping<i8> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<i8> implements Shr<usize> {
    type Output = Wrapping<i8>
    fn shr(read rhs: usize): Wrapping<i8> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<i8> implements AddAssign<Wrapping<i8>> {
    mut fn add_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<i8> implements AddAssign<i8> {
    mut fn add_assign(read rhs: i8): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<i8> implements SubAssign<Wrapping<i8>> {
    mut fn sub_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<i8> implements SubAssign<i8> {
    mut fn sub_assign(read rhs: i8): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<i8> implements MulAssign<Wrapping<i8>> {
    mut fn mul_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<i8> implements MulAssign<i8> {
    mut fn mul_assign(read rhs: i8): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<i8> implements DivAssign<Wrapping<i8>> {
    mut fn div_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<i8> implements DivAssign<i8> {
    mut fn div_assign(read rhs: i8): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<i8> implements RemAssign<Wrapping<i8>> {
    mut fn rem_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<i8> implements RemAssign<i8> {
    mut fn rem_assign(read rhs: i8): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<i8> implements BitAndAssign<Wrapping<i8>> {
    mut fn bitand_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<i8> implements BitAndAssign<i8> {
    mut fn bitand_assign(read rhs: i8): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<i8> implements BitOrAssign<Wrapping<i8>> {
    mut fn bitor_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<i8> implements BitOrAssign<i8> {
    mut fn bitor_assign(read rhs: i8): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<i8> implements BitXorAssign<Wrapping<i8>> {
    mut fn bitxor_assign(read rhs: Wrapping<i8>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<i8> implements BitXorAssign<i8> {
    mut fn bitxor_assign(read rhs: i8): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<i8> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<i8> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<i8> implements Neg {
    type Output = Wrapping<i8>
    fn neg(): Wrapping<i8> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i8> implements Not {
    type Output = Wrapping<i8>
    fn not(): Wrapping<i8> { Wrapping(!self.value) }
}

extend Wrapping<i16> implements Add<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn add(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<i16> implements Sub<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn sub(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<i16> implements Mul<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn mul(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<i16> implements Div<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn div(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<i16> implements Rem<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn rem(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<i16> implements BitAnd<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn bitand(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<i16> implements BitOr<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn bitor(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<i16> implements BitXor<Wrapping<i16>> {
    type Output = Wrapping<i16>
    fn bitxor(read rhs: Wrapping<i16>): Wrapping<i16> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<i16> implements Shl<usize> {
    type Output = Wrapping<i16>
    fn shl(read rhs: usize): Wrapping<i16> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<i16> implements Shr<usize> {
    type Output = Wrapping<i16>
    fn shr(read rhs: usize): Wrapping<i16> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<i16> implements AddAssign<Wrapping<i16>> {
    mut fn add_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<i16> implements AddAssign<i16> {
    mut fn add_assign(read rhs: i16): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<i16> implements SubAssign<Wrapping<i16>> {
    mut fn sub_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<i16> implements SubAssign<i16> {
    mut fn sub_assign(read rhs: i16): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<i16> implements MulAssign<Wrapping<i16>> {
    mut fn mul_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<i16> implements MulAssign<i16> {
    mut fn mul_assign(read rhs: i16): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<i16> implements DivAssign<Wrapping<i16>> {
    mut fn div_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<i16> implements DivAssign<i16> {
    mut fn div_assign(read rhs: i16): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<i16> implements RemAssign<Wrapping<i16>> {
    mut fn rem_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<i16> implements RemAssign<i16> {
    mut fn rem_assign(read rhs: i16): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<i16> implements BitAndAssign<Wrapping<i16>> {
    mut fn bitand_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<i16> implements BitAndAssign<i16> {
    mut fn bitand_assign(read rhs: i16): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<i16> implements BitOrAssign<Wrapping<i16>> {
    mut fn bitor_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<i16> implements BitOrAssign<i16> {
    mut fn bitor_assign(read rhs: i16): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<i16> implements BitXorAssign<Wrapping<i16>> {
    mut fn bitxor_assign(read rhs: Wrapping<i16>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<i16> implements BitXorAssign<i16> {
    mut fn bitxor_assign(read rhs: i16): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<i16> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<i16> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<i16> implements Neg {
    type Output = Wrapping<i16>
    fn neg(): Wrapping<i16> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i16> implements Not {
    type Output = Wrapping<i16>
    fn not(): Wrapping<i16> { Wrapping(!self.value) }
}

extend Wrapping<i32> implements Add<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn add(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<i32> implements Sub<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn sub(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<i32> implements Mul<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn mul(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<i32> implements Div<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn div(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<i32> implements Rem<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn rem(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<i32> implements BitAnd<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn bitand(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<i32> implements BitOr<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn bitor(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<i32> implements BitXor<Wrapping<i32>> {
    type Output = Wrapping<i32>
    fn bitxor(read rhs: Wrapping<i32>): Wrapping<i32> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<i32> implements Shl<usize> {
    type Output = Wrapping<i32>
    fn shl(read rhs: usize): Wrapping<i32> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<i32> implements Shr<usize> {
    type Output = Wrapping<i32>
    fn shr(read rhs: usize): Wrapping<i32> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<i32> implements AddAssign<Wrapping<i32>> {
    mut fn add_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<i32> implements AddAssign<i32> {
    mut fn add_assign(read rhs: i32): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<i32> implements SubAssign<Wrapping<i32>> {
    mut fn sub_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<i32> implements SubAssign<i32> {
    mut fn sub_assign(read rhs: i32): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<i32> implements MulAssign<Wrapping<i32>> {
    mut fn mul_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<i32> implements MulAssign<i32> {
    mut fn mul_assign(read rhs: i32): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<i32> implements DivAssign<Wrapping<i32>> {
    mut fn div_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<i32> implements DivAssign<i32> {
    mut fn div_assign(read rhs: i32): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<i32> implements RemAssign<Wrapping<i32>> {
    mut fn rem_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<i32> implements RemAssign<i32> {
    mut fn rem_assign(read rhs: i32): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<i32> implements BitAndAssign<Wrapping<i32>> {
    mut fn bitand_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<i32> implements BitAndAssign<i32> {
    mut fn bitand_assign(read rhs: i32): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<i32> implements BitOrAssign<Wrapping<i32>> {
    mut fn bitor_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<i32> implements BitOrAssign<i32> {
    mut fn bitor_assign(read rhs: i32): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<i32> implements BitXorAssign<Wrapping<i32>> {
    mut fn bitxor_assign(read rhs: Wrapping<i32>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<i32> implements BitXorAssign<i32> {
    mut fn bitxor_assign(read rhs: i32): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<i32> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<i32> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<i32> implements Neg {
    type Output = Wrapping<i32>
    fn neg(): Wrapping<i32> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i32> implements Not {
    type Output = Wrapping<i32>
    fn not(): Wrapping<i32> { Wrapping(!self.value) }
}

extend Wrapping<i64> implements Add<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn add(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<i64> implements Sub<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn sub(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<i64> implements Mul<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn mul(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<i64> implements Div<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn div(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<i64> implements Rem<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn rem(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<i64> implements BitAnd<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn bitand(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<i64> implements BitOr<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn bitor(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<i64> implements BitXor<Wrapping<i64>> {
    type Output = Wrapping<i64>
    fn bitxor(read rhs: Wrapping<i64>): Wrapping<i64> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<i64> implements Shl<usize> {
    type Output = Wrapping<i64>
    fn shl(read rhs: usize): Wrapping<i64> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<i64> implements Shr<usize> {
    type Output = Wrapping<i64>
    fn shr(read rhs: usize): Wrapping<i64> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<i64> implements AddAssign<Wrapping<i64>> {
    mut fn add_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<i64> implements AddAssign<i64> {
    mut fn add_assign(read rhs: i64): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<i64> implements SubAssign<Wrapping<i64>> {
    mut fn sub_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<i64> implements SubAssign<i64> {
    mut fn sub_assign(read rhs: i64): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<i64> implements MulAssign<Wrapping<i64>> {
    mut fn mul_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<i64> implements MulAssign<i64> {
    mut fn mul_assign(read rhs: i64): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<i64> implements DivAssign<Wrapping<i64>> {
    mut fn div_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<i64> implements DivAssign<i64> {
    mut fn div_assign(read rhs: i64): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<i64> implements RemAssign<Wrapping<i64>> {
    mut fn rem_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<i64> implements RemAssign<i64> {
    mut fn rem_assign(read rhs: i64): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<i64> implements BitAndAssign<Wrapping<i64>> {
    mut fn bitand_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<i64> implements BitAndAssign<i64> {
    mut fn bitand_assign(read rhs: i64): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<i64> implements BitOrAssign<Wrapping<i64>> {
    mut fn bitor_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<i64> implements BitOrAssign<i64> {
    mut fn bitor_assign(read rhs: i64): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<i64> implements BitXorAssign<Wrapping<i64>> {
    mut fn bitxor_assign(read rhs: Wrapping<i64>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<i64> implements BitXorAssign<i64> {
    mut fn bitxor_assign(read rhs: i64): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<i64> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<i64> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<i64> implements Neg {
    type Output = Wrapping<i64>
    fn neg(): Wrapping<i64> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i64> implements Not {
    type Output = Wrapping<i64>
    fn not(): Wrapping<i64> { Wrapping(!self.value) }
}

extend Wrapping<i128> implements Add<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn add(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<i128> implements Sub<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn sub(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<i128> implements Mul<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn mul(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<i128> implements Div<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn div(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<i128> implements Rem<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn rem(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<i128> implements BitAnd<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn bitand(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<i128> implements BitOr<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn bitor(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<i128> implements BitXor<Wrapping<i128>> {
    type Output = Wrapping<i128>
    fn bitxor(read rhs: Wrapping<i128>): Wrapping<i128> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<i128> implements Shl<usize> {
    type Output = Wrapping<i128>
    fn shl(read rhs: usize): Wrapping<i128> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<i128> implements Shr<usize> {
    type Output = Wrapping<i128>
    fn shr(read rhs: usize): Wrapping<i128> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<i128> implements AddAssign<Wrapping<i128>> {
    mut fn add_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<i128> implements AddAssign<i128> {
    mut fn add_assign(read rhs: i128): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<i128> implements SubAssign<Wrapping<i128>> {
    mut fn sub_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<i128> implements SubAssign<i128> {
    mut fn sub_assign(read rhs: i128): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<i128> implements MulAssign<Wrapping<i128>> {
    mut fn mul_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<i128> implements MulAssign<i128> {
    mut fn mul_assign(read rhs: i128): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<i128> implements DivAssign<Wrapping<i128>> {
    mut fn div_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<i128> implements DivAssign<i128> {
    mut fn div_assign(read rhs: i128): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<i128> implements RemAssign<Wrapping<i128>> {
    mut fn rem_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<i128> implements RemAssign<i128> {
    mut fn rem_assign(read rhs: i128): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<i128> implements BitAndAssign<Wrapping<i128>> {
    mut fn bitand_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<i128> implements BitAndAssign<i128> {
    mut fn bitand_assign(read rhs: i128): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<i128> implements BitOrAssign<Wrapping<i128>> {
    mut fn bitor_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<i128> implements BitOrAssign<i128> {
    mut fn bitor_assign(read rhs: i128): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<i128> implements BitXorAssign<Wrapping<i128>> {
    mut fn bitxor_assign(read rhs: Wrapping<i128>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<i128> implements BitXorAssign<i128> {
    mut fn bitxor_assign(read rhs: i128): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<i128> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<i128> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<i128> implements Neg {
    type Output = Wrapping<i128>
    fn neg(): Wrapping<i128> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<i128> implements Not {
    type Output = Wrapping<i128>
    fn not(): Wrapping<i128> { Wrapping(!self.value) }
}

extend Wrapping<isize> implements Add<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn add(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<isize> implements Sub<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn sub(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<isize> implements Mul<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn mul(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<isize> implements Div<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn div(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<isize> implements Rem<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn rem(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<isize> implements BitAnd<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn bitand(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<isize> implements BitOr<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn bitor(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<isize> implements BitXor<Wrapping<isize>> {
    type Output = Wrapping<isize>
    fn bitxor(read rhs: Wrapping<isize>): Wrapping<isize> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<isize> implements Shl<usize> {
    type Output = Wrapping<isize>
    fn shl(read rhs: usize): Wrapping<isize> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<isize> implements Shr<usize> {
    type Output = Wrapping<isize>
    fn shr(read rhs: usize): Wrapping<isize> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<isize> implements AddAssign<Wrapping<isize>> {
    mut fn add_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<isize> implements AddAssign<isize> {
    mut fn add_assign(read rhs: isize): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<isize> implements SubAssign<Wrapping<isize>> {
    mut fn sub_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<isize> implements SubAssign<isize> {
    mut fn sub_assign(read rhs: isize): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<isize> implements MulAssign<Wrapping<isize>> {
    mut fn mul_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<isize> implements MulAssign<isize> {
    mut fn mul_assign(read rhs: isize): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<isize> implements DivAssign<Wrapping<isize>> {
    mut fn div_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<isize> implements DivAssign<isize> {
    mut fn div_assign(read rhs: isize): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<isize> implements RemAssign<Wrapping<isize>> {
    mut fn rem_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<isize> implements RemAssign<isize> {
    mut fn rem_assign(read rhs: isize): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<isize> implements BitAndAssign<Wrapping<isize>> {
    mut fn bitand_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<isize> implements BitAndAssign<isize> {
    mut fn bitand_assign(read rhs: isize): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<isize> implements BitOrAssign<Wrapping<isize>> {
    mut fn bitor_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<isize> implements BitOrAssign<isize> {
    mut fn bitor_assign(read rhs: isize): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<isize> implements BitXorAssign<Wrapping<isize>> {
    mut fn bitxor_assign(read rhs: Wrapping<isize>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<isize> implements BitXorAssign<isize> {
    mut fn bitxor_assign(read rhs: isize): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<isize> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<isize> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<isize> implements Neg {
    type Output = Wrapping<isize>
    fn neg(): Wrapping<isize> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<isize> implements Not {
    type Output = Wrapping<isize>
    fn not(): Wrapping<isize> { Wrapping(!self.value) }
}

extend Wrapping<u8> implements Add<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn add(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<u8> implements Sub<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn sub(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<u8> implements Mul<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn mul(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<u8> implements Div<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn div(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<u8> implements Rem<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn rem(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<u8> implements BitAnd<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn bitand(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<u8> implements BitOr<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn bitor(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<u8> implements BitXor<Wrapping<u8>> {
    type Output = Wrapping<u8>
    fn bitxor(read rhs: Wrapping<u8>): Wrapping<u8> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<u8> implements Shl<usize> {
    type Output = Wrapping<u8>
    fn shl(read rhs: usize): Wrapping<u8> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<u8> implements Shr<usize> {
    type Output = Wrapping<u8>
    fn shr(read rhs: usize): Wrapping<u8> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<u8> implements AddAssign<Wrapping<u8>> {
    mut fn add_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<u8> implements AddAssign<u8> {
    mut fn add_assign(read rhs: u8): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<u8> implements SubAssign<Wrapping<u8>> {
    mut fn sub_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<u8> implements SubAssign<u8> {
    mut fn sub_assign(read rhs: u8): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<u8> implements MulAssign<Wrapping<u8>> {
    mut fn mul_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<u8> implements MulAssign<u8> {
    mut fn mul_assign(read rhs: u8): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<u8> implements DivAssign<Wrapping<u8>> {
    mut fn div_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<u8> implements DivAssign<u8> {
    mut fn div_assign(read rhs: u8): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<u8> implements RemAssign<Wrapping<u8>> {
    mut fn rem_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<u8> implements RemAssign<u8> {
    mut fn rem_assign(read rhs: u8): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<u8> implements BitAndAssign<Wrapping<u8>> {
    mut fn bitand_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<u8> implements BitAndAssign<u8> {
    mut fn bitand_assign(read rhs: u8): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<u8> implements BitOrAssign<Wrapping<u8>> {
    mut fn bitor_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<u8> implements BitOrAssign<u8> {
    mut fn bitor_assign(read rhs: u8): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<u8> implements BitXorAssign<Wrapping<u8>> {
    mut fn bitxor_assign(read rhs: Wrapping<u8>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<u8> implements BitXorAssign<u8> {
    mut fn bitxor_assign(read rhs: u8): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<u8> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<u8> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<u8> implements Neg {
    type Output = Wrapping<u8>
    fn neg(): Wrapping<u8> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u8> implements Not {
    type Output = Wrapping<u8>
    fn not(): Wrapping<u8> { Wrapping(!self.value) }
}

extend Wrapping<u16> implements Add<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn add(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<u16> implements Sub<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn sub(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<u16> implements Mul<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn mul(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<u16> implements Div<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn div(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<u16> implements Rem<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn rem(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<u16> implements BitAnd<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn bitand(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<u16> implements BitOr<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn bitor(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<u16> implements BitXor<Wrapping<u16>> {
    type Output = Wrapping<u16>
    fn bitxor(read rhs: Wrapping<u16>): Wrapping<u16> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<u16> implements Shl<usize> {
    type Output = Wrapping<u16>
    fn shl(read rhs: usize): Wrapping<u16> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<u16> implements Shr<usize> {
    type Output = Wrapping<u16>
    fn shr(read rhs: usize): Wrapping<u16> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<u16> implements AddAssign<Wrapping<u16>> {
    mut fn add_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<u16> implements AddAssign<u16> {
    mut fn add_assign(read rhs: u16): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<u16> implements SubAssign<Wrapping<u16>> {
    mut fn sub_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<u16> implements SubAssign<u16> {
    mut fn sub_assign(read rhs: u16): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<u16> implements MulAssign<Wrapping<u16>> {
    mut fn mul_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<u16> implements MulAssign<u16> {
    mut fn mul_assign(read rhs: u16): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<u16> implements DivAssign<Wrapping<u16>> {
    mut fn div_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<u16> implements DivAssign<u16> {
    mut fn div_assign(read rhs: u16): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<u16> implements RemAssign<Wrapping<u16>> {
    mut fn rem_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<u16> implements RemAssign<u16> {
    mut fn rem_assign(read rhs: u16): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<u16> implements BitAndAssign<Wrapping<u16>> {
    mut fn bitand_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<u16> implements BitAndAssign<u16> {
    mut fn bitand_assign(read rhs: u16): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<u16> implements BitOrAssign<Wrapping<u16>> {
    mut fn bitor_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<u16> implements BitOrAssign<u16> {
    mut fn bitor_assign(read rhs: u16): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<u16> implements BitXorAssign<Wrapping<u16>> {
    mut fn bitxor_assign(read rhs: Wrapping<u16>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<u16> implements BitXorAssign<u16> {
    mut fn bitxor_assign(read rhs: u16): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<u16> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<u16> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<u16> implements Neg {
    type Output = Wrapping<u16>
    fn neg(): Wrapping<u16> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u16> implements Not {
    type Output = Wrapping<u16>
    fn not(): Wrapping<u16> { Wrapping(!self.value) }
}

extend Wrapping<u32> implements Add<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn add(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<u32> implements Sub<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn sub(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<u32> implements Mul<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn mul(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<u32> implements Div<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn div(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<u32> implements Rem<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn rem(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<u32> implements BitAnd<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn bitand(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<u32> implements BitOr<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn bitor(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<u32> implements BitXor<Wrapping<u32>> {
    type Output = Wrapping<u32>
    fn bitxor(read rhs: Wrapping<u32>): Wrapping<u32> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<u32> implements Shl<usize> {
    type Output = Wrapping<u32>
    fn shl(read rhs: usize): Wrapping<u32> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<u32> implements Shr<usize> {
    type Output = Wrapping<u32>
    fn shr(read rhs: usize): Wrapping<u32> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<u32> implements AddAssign<Wrapping<u32>> {
    mut fn add_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<u32> implements AddAssign<u32> {
    mut fn add_assign(read rhs: u32): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<u32> implements SubAssign<Wrapping<u32>> {
    mut fn sub_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<u32> implements SubAssign<u32> {
    mut fn sub_assign(read rhs: u32): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<u32> implements MulAssign<Wrapping<u32>> {
    mut fn mul_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<u32> implements MulAssign<u32> {
    mut fn mul_assign(read rhs: u32): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<u32> implements DivAssign<Wrapping<u32>> {
    mut fn div_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<u32> implements DivAssign<u32> {
    mut fn div_assign(read rhs: u32): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<u32> implements RemAssign<Wrapping<u32>> {
    mut fn rem_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<u32> implements RemAssign<u32> {
    mut fn rem_assign(read rhs: u32): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<u32> implements BitAndAssign<Wrapping<u32>> {
    mut fn bitand_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<u32> implements BitAndAssign<u32> {
    mut fn bitand_assign(read rhs: u32): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<u32> implements BitOrAssign<Wrapping<u32>> {
    mut fn bitor_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<u32> implements BitOrAssign<u32> {
    mut fn bitor_assign(read rhs: u32): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<u32> implements BitXorAssign<Wrapping<u32>> {
    mut fn bitxor_assign(read rhs: Wrapping<u32>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<u32> implements BitXorAssign<u32> {
    mut fn bitxor_assign(read rhs: u32): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<u32> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<u32> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<u32> implements Neg {
    type Output = Wrapping<u32>
    fn neg(): Wrapping<u32> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u32> implements Not {
    type Output = Wrapping<u32>
    fn not(): Wrapping<u32> { Wrapping(!self.value) }
}

extend Wrapping<u64> implements Add<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn add(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<u64> implements Sub<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn sub(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<u64> implements Mul<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn mul(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<u64> implements Div<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn div(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<u64> implements Rem<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn rem(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<u64> implements BitAnd<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn bitand(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<u64> implements BitOr<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn bitor(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<u64> implements BitXor<Wrapping<u64>> {
    type Output = Wrapping<u64>
    fn bitxor(read rhs: Wrapping<u64>): Wrapping<u64> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<u64> implements Shl<usize> {
    type Output = Wrapping<u64>
    fn shl(read rhs: usize): Wrapping<u64> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<u64> implements Shr<usize> {
    type Output = Wrapping<u64>
    fn shr(read rhs: usize): Wrapping<u64> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<u64> implements AddAssign<Wrapping<u64>> {
    mut fn add_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<u64> implements AddAssign<u64> {
    mut fn add_assign(read rhs: u64): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<u64> implements SubAssign<Wrapping<u64>> {
    mut fn sub_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<u64> implements SubAssign<u64> {
    mut fn sub_assign(read rhs: u64): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<u64> implements MulAssign<Wrapping<u64>> {
    mut fn mul_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<u64> implements MulAssign<u64> {
    mut fn mul_assign(read rhs: u64): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<u64> implements DivAssign<Wrapping<u64>> {
    mut fn div_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<u64> implements DivAssign<u64> {
    mut fn div_assign(read rhs: u64): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<u64> implements RemAssign<Wrapping<u64>> {
    mut fn rem_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<u64> implements RemAssign<u64> {
    mut fn rem_assign(read rhs: u64): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<u64> implements BitAndAssign<Wrapping<u64>> {
    mut fn bitand_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<u64> implements BitAndAssign<u64> {
    mut fn bitand_assign(read rhs: u64): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<u64> implements BitOrAssign<Wrapping<u64>> {
    mut fn bitor_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<u64> implements BitOrAssign<u64> {
    mut fn bitor_assign(read rhs: u64): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<u64> implements BitXorAssign<Wrapping<u64>> {
    mut fn bitxor_assign(read rhs: Wrapping<u64>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<u64> implements BitXorAssign<u64> {
    mut fn bitxor_assign(read rhs: u64): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<u64> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<u64> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<u64> implements Neg {
    type Output = Wrapping<u64>
    fn neg(): Wrapping<u64> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u64> implements Not {
    type Output = Wrapping<u64>
    fn not(): Wrapping<u64> { Wrapping(!self.value) }
}

extend Wrapping<u128> implements Add<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn add(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<u128> implements Sub<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn sub(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<u128> implements Mul<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn mul(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<u128> implements Div<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn div(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<u128> implements Rem<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn rem(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<u128> implements BitAnd<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn bitand(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<u128> implements BitOr<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn bitor(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<u128> implements BitXor<Wrapping<u128>> {
    type Output = Wrapping<u128>
    fn bitxor(read rhs: Wrapping<u128>): Wrapping<u128> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<u128> implements Shl<usize> {
    type Output = Wrapping<u128>
    fn shl(read rhs: usize): Wrapping<u128> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<u128> implements Shr<usize> {
    type Output = Wrapping<u128>
    fn shr(read rhs: usize): Wrapping<u128> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<u128> implements AddAssign<Wrapping<u128>> {
    mut fn add_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<u128> implements AddAssign<u128> {
    mut fn add_assign(read rhs: u128): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<u128> implements SubAssign<Wrapping<u128>> {
    mut fn sub_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<u128> implements SubAssign<u128> {
    mut fn sub_assign(read rhs: u128): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<u128> implements MulAssign<Wrapping<u128>> {
    mut fn mul_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<u128> implements MulAssign<u128> {
    mut fn mul_assign(read rhs: u128): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<u128> implements DivAssign<Wrapping<u128>> {
    mut fn div_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<u128> implements DivAssign<u128> {
    mut fn div_assign(read rhs: u128): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<u128> implements RemAssign<Wrapping<u128>> {
    mut fn rem_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<u128> implements RemAssign<u128> {
    mut fn rem_assign(read rhs: u128): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<u128> implements BitAndAssign<Wrapping<u128>> {
    mut fn bitand_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<u128> implements BitAndAssign<u128> {
    mut fn bitand_assign(read rhs: u128): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<u128> implements BitOrAssign<Wrapping<u128>> {
    mut fn bitor_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<u128> implements BitOrAssign<u128> {
    mut fn bitor_assign(read rhs: u128): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<u128> implements BitXorAssign<Wrapping<u128>> {
    mut fn bitxor_assign(read rhs: Wrapping<u128>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<u128> implements BitXorAssign<u128> {
    mut fn bitxor_assign(read rhs: u128): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<u128> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<u128> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<u128> implements Neg {
    type Output = Wrapping<u128>
    fn neg(): Wrapping<u128> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<u128> implements Not {
    type Output = Wrapping<u128>
    fn not(): Wrapping<u128> { Wrapping(!self.value) }
}

extend Wrapping<usize> implements Add<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn add(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_add(rhs.value))
    }
}

extend Wrapping<usize> implements Sub<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn sub(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_sub(rhs.value))
    }
}

extend Wrapping<usize> implements Mul<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn mul(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_mul(rhs.value))
    }
}

extend Wrapping<usize> implements Div<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn div(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_div(rhs.value))
    }
}

extend Wrapping<usize> implements Rem<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn rem(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value.wrapping_rem(rhs.value))
    }
}

extend Wrapping<usize> implements BitAnd<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn bitand(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value & rhs.value)
    }
}

extend Wrapping<usize> implements BitOr<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn bitor(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value | rhs.value)
    }
}

extend Wrapping<usize> implements BitXor<Wrapping<usize>> {
    type Output = Wrapping<usize>
    fn bitxor(read rhs: Wrapping<usize>): Wrapping<usize> {
        Wrapping(self.value ^ rhs.value)
    }
}

extend Wrapping<usize> implements Shl<usize> {
    type Output = Wrapping<usize>
    fn shl(read rhs: usize): Wrapping<usize> {
        Wrapping(self.value.wrapping_shl(rhs as u32))
    }
}

extend Wrapping<usize> implements Shr<usize> {
    type Output = Wrapping<usize>
    fn shr(read rhs: usize): Wrapping<usize> {
        Wrapping(self.value.wrapping_shr(rhs as u32))
    }
}

extend Wrapping<usize> implements AddAssign<Wrapping<usize>> {
    mut fn add_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value.wrapping_add(rhs.value)
    }
}

extend Wrapping<usize> implements AddAssign<usize> {
    mut fn add_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_add(rhs)
    }
}

extend Wrapping<usize> implements SubAssign<Wrapping<usize>> {
    mut fn sub_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value.wrapping_sub(rhs.value)
    }
}

extend Wrapping<usize> implements SubAssign<usize> {
    mut fn sub_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_sub(rhs)
    }
}

extend Wrapping<usize> implements MulAssign<Wrapping<usize>> {
    mut fn mul_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value.wrapping_mul(rhs.value)
    }
}

extend Wrapping<usize> implements MulAssign<usize> {
    mut fn mul_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_mul(rhs)
    }
}

extend Wrapping<usize> implements DivAssign<Wrapping<usize>> {
    mut fn div_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value.wrapping_div(rhs.value)
    }
}

extend Wrapping<usize> implements DivAssign<usize> {
    mut fn div_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_div(rhs)
    }
}

extend Wrapping<usize> implements RemAssign<Wrapping<usize>> {
    mut fn rem_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value.wrapping_rem(rhs.value)
    }
}

extend Wrapping<usize> implements RemAssign<usize> {
    mut fn rem_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_rem(rhs)
    }
}

extend Wrapping<usize> implements BitAndAssign<Wrapping<usize>> {
    mut fn bitand_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value & rhs.value
    }
}

extend Wrapping<usize> implements BitAndAssign<usize> {
    mut fn bitand_assign(read rhs: usize): Unit {
        self.value = self.value & rhs
    }
}

extend Wrapping<usize> implements BitOrAssign<Wrapping<usize>> {
    mut fn bitor_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value | rhs.value
    }
}

extend Wrapping<usize> implements BitOrAssign<usize> {
    mut fn bitor_assign(read rhs: usize): Unit {
        self.value = self.value | rhs
    }
}

extend Wrapping<usize> implements BitXorAssign<Wrapping<usize>> {
    mut fn bitxor_assign(read rhs: Wrapping<usize>): Unit {
        self.value = self.value ^ rhs.value
    }
}

extend Wrapping<usize> implements BitXorAssign<usize> {
    mut fn bitxor_assign(read rhs: usize): Unit {
        self.value = self.value ^ rhs
    }
}

extend Wrapping<usize> implements ShlAssign<usize> {
    mut fn shl_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shl(rhs as u32)
    }
}

extend Wrapping<usize> implements ShrAssign<usize> {
    mut fn shr_assign(read rhs: usize): Unit {
        self.value = self.value.wrapping_shr(rhs as u32)
    }
}

extend Wrapping<usize> implements Neg {
    type Output = Wrapping<usize>
    fn neg(): Wrapping<usize> { Wrapping(self.value.wrapping_neg()) }
}

extend Wrapping<usize> implements Not {
    type Output = Wrapping<usize>
    fn not(): Wrapping<usize> { Wrapping(!self.value) }
}

extend<T: Copy + Clone> Wrapping<T> implements Clone {
    fn clone(): Wrapping<T> { Wrapping(self.value.clone()) }
}

extend<T: Copy + PartialEq> Wrapping<T> implements PartialEq {
    fn eq(read other: Wrapping<T>): bool { self.value == other.value }
}
extend<T: Copy + Eq> Wrapping<T> implements Eq {}
extend<T: Copy + PartialOrd> Wrapping<T> implements PartialOrd {
    fn partial_cmp(read other: Wrapping<T>): Ordering? {
        self.value.partial_cmp(read other.value)
    }
}
extend<T: Copy + Ord> Wrapping<T> implements Ord {
    fn cmp(read other: Wrapping<T>): Ordering {
        self.value.cmp(read other.value)
    }
}
extend<T: Copy + Hash> Wrapping<T> implements Hash {
    fn hash<State: Hasher>(mut state: State): Unit {
        self.value.hash(mut state)
    }
}
extend<T: Copy + Debug> Wrapping<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Debug).fmt(read self.value, mut f)
    }
}
extend<T: Copy + Display> Wrapping<T> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Display).fmt(read self.value, mut f)
    }
}
extend<T: Copy + Binary> Wrapping<T> implements Binary {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Binary).fmt(read self.value, mut f)
    }
}
extend<T: Copy + Octal> Wrapping<T> implements Octal {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Octal).fmt(read self.value, mut f)
    }
}
extend<T: Copy + LowerHex> Wrapping<T> implements LowerHex {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(LowerHex).fmt(read self.value, mut f)
    }
}
extend<T: Copy + UpperHex> Wrapping<T> implements UpperHex {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(UpperHex).fmt(read self.value, mut f)
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
fn parse_magnitude(read text: Text, radix: u32, signed: bool, limit_pos: u128, limit_neg: u128): u128 throws ParseIntError {
    if radix < 2u32 || radix > 36u32 { super.panic.panic("radix must be within 2..=36") }
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
    static fn from_text_radix(read text: Text, radix: u32): Self throws ParseIntError;
}

pub fn parse<T: FromText>(read text: Text): T throws ParseIntError {
    try T.(FromText).from_text_radix(text, 10u32)
}
pub fn parse_radix<T: FromText>(read text: Text, radix: u32): T throws ParseIntError {
    try T.(FromText).from_text_radix(text, radix)
}

pub fn from_str_radix<T: FromText>(
    read text: Text, radix: u32
): T throws ParseIntError {
    try parse_radix<T>(text, radix)
}

extend i8 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): i8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 127u128, 128u128)
        raw as i64 as i8
    }
}
extend i16 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): i16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 32767u128, 32768u128)
        raw as i64 as i16
    }
}
extend i32 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): i32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 2147483647u128, 2147483648u128)
        raw as i64 as i32
    }
}
extend i64 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): i64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as i64
    }
}
extend isize implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): isize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as isize
    }
}
extend u8 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): u8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 255u128, 0u128)
        raw as u8
    }
}
extend u16 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): u16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 65535u128, 0u128)
        raw as u16
    }
}
extend u32 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): u32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 4294967295u128, 0u128)
        raw as u32
    }
}
extend u64 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): u64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 18446744073709551615u128, 0u128)
        raw as u64
    }
}
extend usize implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): usize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, ((-1isize) as usize) as u128, 0u128)
        raw as usize
    }
}
extend i128 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): i128 throws ParseIntError {
        let raw = try parse_magnitude(
            text, radix, true,
            170141183460469231731687303715884105727u128,
            170141183460469231731687303715884105728u128)
        raw as i128
    }
}
extend u128 implements FromText {
    static fn from_text_radix(read text: Text, radix: u32): u128 throws ParseIntError {
        try parse_magnitude(
            text, radix, false,
            340282366920938463463374607431768211455u128, 0u128)
    }
}

// Primitive operator implementations, so integers and bool satisfy the
// operator interfaces in generic code. Each expands to the operator itself;
// overflow and shift-count behavior is the operator's. Views of the operands
// (`read i32`) implement the same interfaces as the values.
macro integer_binary_trait {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend $type implements $trait<$type> {
            type Output = $type
            fn $method(read rhs: $type): $type { self $operator rhs }
        }
        extend<region lhs_region> read $type from lhs_region implements $trait<$type> {
            type Output = $type
            fn $method(read rhs: $type): $type { *self $operator rhs }
        }
        extend<region rhs_region> $type implements $trait<read $type from rhs_region> {
            type Output = $type
            fn $method(read rhs: read $type from rhs_region): $type { self $operator *rhs }
        }
        extend<region lhs_region, region rhs_region> read $type from lhs_region implements $trait<read $type from rhs_region> {
            type Output = $type
            fn $method(read rhs: read $type from rhs_region): $type { *self $operator *rhs }
        }
    };
}

macro integer_assignment_trait {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend $type implements $trait<$type> {
            mut fn $method(read rhs: $type): Unit { self = self $operator rhs }
        }
        extend<region rhs_region> $type implements $trait<read $type from rhs_region> {
            mut fn $method(read rhs: read $type from rhs_region): Unit { self = self $operator *rhs }
        }
    };
}

macro integer_unary_trait {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend $type implements $trait {
            type Output = $type
            fn $method(): $type { $operator self }
        }
        extend<region receiver_region> read $type from receiver_region implements $trait {
            type Output = $type
            fn $method(): $type { $operator (*self) }
        }
    };
}

// A shift count of any integer type (or a view of one), converted for the
// native u32-count shift. The low seven bits are kept, so release masking is
// unchanged; a count that is negative or does not fit u32 gets bit 31 set, so
// it stays out of range for every width and the debug check still fires.
interface ShiftCount { fn shift_count(): u32; }

macro integer_shift_count {
    ($($type:ident),*) => {
        $(
            extend $type implements ShiftCount {
                fn shift_count(): u32 {
                    let low = self as u32
                    if self >= 0 && (self as u128) <= 4294967295u128 { low } else { low | 0x80000000u32 }
                }
            }
            extend<region count_region> read $type from count_region implements ShiftCount {
                fn shift_count(): u32 { (*self).shift_count() }
            }
        )*
    };
}

integer_shift_count!(i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize)

// Shifts accept any integer count type, like the shift operators.
macro integer_shift_traits {
    ($type:ident) => {
        extend<C: ShiftCount> $type implements Shl<C> {
            type Output = $type
            fn shl(read rhs: C): $type { self << rhs.shift_count() }
        }
        extend<region lhs_region, C: ShiftCount> read $type from lhs_region implements Shl<C> {
            type Output = $type
            fn shl(read rhs: C): $type { *self << rhs.shift_count() }
        }
        extend<C: ShiftCount> $type implements Shr<C> {
            type Output = $type
            fn shr(read rhs: C): $type { self >> rhs.shift_count() }
        }
        extend<region lhs_region, C: ShiftCount> read $type from lhs_region implements Shr<C> {
            type Output = $type
            fn shr(read rhs: C): $type { *self >> rhs.shift_count() }
        }
        extend<C: ShiftCount> $type implements ShlAssign<C> {
            mut fn shl_assign(read rhs: C): Unit { self = self << rhs.shift_count() }
        }
        extend<C: ShiftCount> $type implements ShrAssign<C> {
            mut fn shr_assign(read rhs: C): Unit { self = self >> rhs.shift_count() }
        }
    };
}

macro integer_operator_traits {
    ($($type:ident),*) => {
        $(
            integer_binary_trait!($type, Add, add, +)
            integer_binary_trait!($type, Sub, sub, -)
            integer_binary_trait!($type, Mul, mul, *)
            integer_binary_trait!($type, Div, div, /)
            integer_binary_trait!($type, Rem, rem, %)
            integer_binary_trait!($type, BitAnd, bitand, &)
            integer_binary_trait!($type, BitOr, bitor, |)
            integer_binary_trait!($type, BitXor, bitxor, ^)
            integer_assignment_trait!($type, AddAssign, add_assign, +)
            integer_assignment_trait!($type, SubAssign, sub_assign, -)
            integer_assignment_trait!($type, MulAssign, mul_assign, *)
            integer_assignment_trait!($type, DivAssign, div_assign, /)
            integer_assignment_trait!($type, RemAssign, rem_assign, %)
            integer_assignment_trait!($type, BitAndAssign, bitand_assign, &)
            integer_assignment_trait!($type, BitOrAssign, bitor_assign, |)
            integer_assignment_trait!($type, BitXorAssign, bitxor_assign, ^)
            integer_unary_trait!($type, Not, not, !)
            integer_shift_traits!($type)
        )*
    };
}

integer_operator_traits!(i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize)
integer_unary_trait!(i8, Neg, neg, -)
integer_unary_trait!(i16, Neg, neg, -)
integer_unary_trait!(i32, Neg, neg, -)
integer_unary_trait!(i64, Neg, neg, -)
integer_unary_trait!(i128, Neg, neg, -)
integer_unary_trait!(isize, Neg, neg, -)
integer_binary_trait!(bool, BitAnd, bitand, &)
integer_binary_trait!(bool, BitOr, bitor, |)
integer_binary_trait!(bool, BitXor, bitxor, ^)
integer_assignment_trait!(bool, BitAndAssign, bitand_assign, &)
integer_assignment_trait!(bool, BitOrAssign, bitor_assign, |)
integer_assignment_trait!(bool, BitXorAssign, bitxor_assign, ^)
integer_unary_trait!(bool, Not, not, !)

// The failure of a checked integer conversion whose value is out of range.
pub copy type TryFromIntError { }

extend TryFromIntError implements PartialEq {
    fn eq(read other: TryFromIntError): bool { true }
}
extend TryFromIntError implements Eq {}
extend TryFromIntError implements Clone {
    fn clone(): TryFromIntError { self }
}
extend TryFromIntError implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { }
}
extend TryFromIntError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("TryFromIntError(())")
    }
}
extend TryFromIntError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("out of range integral type conversion attempted")
    }
}
extend TryFromIntError implements CoreError {}

// Lossless integer widenings (and bool as 0 or 1).
macro integer_from {
    ($target:ident; $($source:ident),*) => {
        $(
            extend $target implements From<$source> {
                static fn from(take value: $source): $target { value as $target }
            }
            extend $target implements TryFrom<$source> {
                type Error = Never
                static fn try_from(take value: $source): Outcome<$target, Never> {
                    success(value as $target)
                }
            }
        )*
    };
}

integer_from!(u16; u8, bool)
integer_from!(u32; u8, u16, bool)
integer_from!(u64; u8, u16, u32, bool)
integer_from!(u128; u8, u16, u32, u64, bool)
integer_from!(usize; u8, u16, bool)
integer_from!(i16; u8, i8, bool)
integer_from!(i32; u8, u16, i8, i16, bool)
integer_from!(i64; u8, u16, u32, i8, i16, i32, bool)
integer_from!(i128; u8, u16, u32, u64, i8, i16, i32, i64, bool)
integer_from!(isize; u8, i8, i16, bool)
integer_from!(u8; bool)
integer_from!(i8; bool)

// Every other integer pair converts only when the value fits.
macro integer_try_from {
    ($target:ident; $($source:ident),*) => {
        $(
            extend $target implements TryFrom<$source> {
                type Error = TryFromIntError
                static fn try_from(take value: $source): Outcome<$target, TryFromIntError> {
                    match value.checked_cast<$target>() {
                        present(converted) => success(converted),
                        none => failure(TryFromIntError())
                    }
                }
            }
        )*
    };
}

integer_try_from!(u8; u16, u32, u64, u128, usize, i8, i16, i32, i64, i128, isize)
integer_try_from!(u16; u32, u64, u128, usize, i8, i16, i32, i64, i128, isize)
integer_try_from!(u32; u64, u128, usize, i8, i16, i32, i64, i128, isize)
integer_try_from!(u64; u128, usize, i8, i16, i32, i64, i128, isize)
integer_try_from!(u128; usize, i8, i16, i32, i64, i128, isize)
integer_try_from!(usize; u32, u64, u128, i8, i16, i32, i64, i128, isize)
integer_try_from!(i8; u8, u16, u32, u64, u128, usize, i16, i32, i64, i128, isize)
integer_try_from!(i16; u16, u32, u64, u128, usize, i32, i64, i128, isize)
integer_try_from!(i32; u32, u64, u128, usize, i64, i128, isize)
integer_try_from!(i64; u64, u128, usize, i128, isize)
integer_try_from!(i128; u128, usize, isize)
integer_try_from!(isize; u16, u32, u64, u128, usize, i32, i64, i128)

// Reference forms of the Wrapping operators: each delegates to the value
// implementation above, so wrapping and shift-count behavior stay in one place.
macro wrapping_reference_binary {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend<region lhs_region> read Wrapping<$type> from lhs_region implements $trait<Wrapping<$type>> {
            type Output = Wrapping<$type>
            fn $method(read rhs: Wrapping<$type>): Wrapping<$type> { *self $operator rhs }
        }
        extend<region rhs_region> Wrapping<$type> implements $trait<read Wrapping<$type> from rhs_region> {
            type Output = Wrapping<$type>
            fn $method(read rhs: read Wrapping<$type> from rhs_region): Wrapping<$type> { self $operator *rhs }
        }
        extend<region lhs_region, region rhs_region> read Wrapping<$type> from lhs_region implements $trait<read Wrapping<$type> from rhs_region> {
            type Output = Wrapping<$type>
            fn $method(read rhs: read Wrapping<$type> from rhs_region): Wrapping<$type> { *self $operator *rhs }
        }
    };
}

macro wrapping_reference_assignment {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend<region rhs_region> Wrapping<$type> implements $trait<read Wrapping<$type> from rhs_region> {
            mut fn $method(read rhs: read Wrapping<$type> from rhs_region): Unit { self = self $operator *rhs }
        }
        extend<region rhs_region> Wrapping<$type> implements $trait<read $type from rhs_region> {
            mut fn $method(read rhs: read $type from rhs_region): Unit { self = self $operator Wrapping(*rhs) }
        }
    };
}

macro wrapping_reference_shift {
    ($type:ident, $trait:ident, $method:ident, $assign:ident, $assign_method:ident, $operator:tt) => {
        extend<region lhs_region> read Wrapping<$type> from lhs_region implements $trait<usize> {
            type Output = Wrapping<$type>
            fn $method(read rhs: usize): Wrapping<$type> { *self $operator rhs }
        }
        extend<region rhs_region> Wrapping<$type> implements $trait<read usize from rhs_region> {
            type Output = Wrapping<$type>
            fn $method(read rhs: read usize from rhs_region): Wrapping<$type> { self $operator *rhs }
        }
        extend<region lhs_region, region rhs_region> read Wrapping<$type> from lhs_region implements $trait<read usize from rhs_region> {
            type Output = Wrapping<$type>
            fn $method(read rhs: read usize from rhs_region): Wrapping<$type> { *self $operator *rhs }
        }
        extend<region rhs_region> Wrapping<$type> implements $assign<read usize from rhs_region> {
            mut fn $assign_method(read rhs: read usize from rhs_region): Unit { self = self $operator *rhs }
        }
    };
}

macro wrapping_reference_unary {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend<region receiver_region> read Wrapping<$type> from receiver_region implements $trait {
            type Output = Wrapping<$type>
            fn $method(): Wrapping<$type> { $operator (*self) }
        }
    };
}

macro wrapping_reference_operators {
    ($($type:ident),*) => {
        $(
            wrapping_reference_binary!($type, Add, add, +)
            wrapping_reference_binary!($type, Sub, sub, -)
            wrapping_reference_binary!($type, Mul, mul, *)
            wrapping_reference_binary!($type, Div, div, /)
            wrapping_reference_binary!($type, Rem, rem, %)
            wrapping_reference_binary!($type, BitAnd, bitand, &)
            wrapping_reference_binary!($type, BitOr, bitor, |)
            wrapping_reference_binary!($type, BitXor, bitxor, ^)
            wrapping_reference_assignment!($type, AddAssign, add_assign, +)
            wrapping_reference_assignment!($type, SubAssign, sub_assign, -)
            wrapping_reference_assignment!($type, MulAssign, mul_assign, *)
            wrapping_reference_assignment!($type, DivAssign, div_assign, /)
            wrapping_reference_assignment!($type, RemAssign, rem_assign, %)
            wrapping_reference_assignment!($type, BitAndAssign, bitand_assign, &)
            wrapping_reference_assignment!($type, BitOrAssign, bitor_assign, |)
            wrapping_reference_assignment!($type, BitXorAssign, bitxor_assign, ^)
            wrapping_reference_shift!($type, Shl, shl, ShlAssign, shl_assign, <<)
            wrapping_reference_shift!($type, Shr, shr, ShrAssign, shr_assign, >>)
            wrapping_reference_unary!($type, Not, not, !)
        )*
    };
}

wrapping_reference_operators!(i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize)
wrapping_reference_unary!(i8, Neg, neg, -)
wrapping_reference_unary!(i16, Neg, neg, -)
wrapping_reference_unary!(i32, Neg, neg, -)
wrapping_reference_unary!(i64, Neg, neg, -)
wrapping_reference_unary!(i128, Neg, neg, -)
wrapping_reference_unary!(isize, Neg, neg, -)

macro integer_from_str {
    ($($target:ident),*) => {
        $(
            extend $target implements FromStr {
                type Error = ParseIntError
                static fn from_str(read input: Text): $target throws ParseIntError {
                    try parse_radix<$target>(input, 10u32)
                }
            }
        )*
    };
}

integer_from_str!(i8, i16, i32, i64, i128, isize, u8, u16, u32, u64, u128, usize)

// The failure of parsing a `bool` from text other than "true" or "false".
pub copy type ParseBoolError { }
extend ParseBoolError implements PartialEq {
    fn eq(read other: ParseBoolError): bool { true }
}
extend ParseBoolError implements Eq {}
extend ParseBoolError implements Clone {
    fn clone(): ParseBoolError { self }
}
extend ParseBoolError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("ParseBoolError")
    }
}
extend ParseBoolError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("provided string was not `true` or `false`")
    }
}
extend ParseBoolError implements CoreError {}

extend bool implements FromStr {
    type Error = ParseBoolError
    static fn from_str(read input: Text): bool throws ParseBoolError {
        if input.eq("true") { true } else if input.eq("false") { false } else { throw ParseBoolError() }
    }
}

macro bool_try_from {
    ($($source:ident),*) => {
        $(
            extend bool implements TryFrom<$source> {
                type Error = TryFromIntError
                static fn try_from(take value: $source): Outcome<bool, TryFromIntError> {
                    if value == 0 { success(false) } else if value == 1 { success(true) } else { failure(TryFromIntError()) }
                }
            }
        )*
    };
}

bool_try_from!(i8, i16, i32, i64, i128, u8, u16, u32, u64, u128)

extend bool {
    pub fn then<T, F: take fn(): T>(take f: F): T? {
        if self { present(f()) } else { none }
    }
    pub fn ok_or<E>(take error: E): (Outcome<Unit, E>) {
        if self { success(()) } else { failure(error) }
    }
    pub fn ok_or_else<E, F: take fn(): E>(take error: F): (Outcome<Unit, E>) {
        if self { success(()) } else { failure(error()) }
    }
}

pub type EscapeDefault { bytes: [u8; 4]; length: usize; position: usize }
extend EscapeDefault implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.position >= self.length { return none }
        let value = self.bytes[self.position]
        self.position += 1usize
        present(value)
    }
}

fn escape_hex_nibble(value: u8): u8 {
    if value < 10u8 { 0x30u8 + value } else { 0x61u8 + value - 10u8 }
}

fn escape_default_byte(byte: u8): EscapeDefault {
    let short: u8 = match byte {
        0x09u8 => 0x74u8,
        0x0au8 => 0x6eu8,
        0x0du8 => 0x72u8,
        0x5cu8 => 0x5cu8,
        0x27u8 => 0x27u8,
        0x22u8 => 0x22u8,
        _ => 0u8
    }
    if short != 0u8 { return EscapeDefault([0x5cu8, short, 0u8, 0u8], 2usize, 0usize) }
    if byte >= 0x20u8 && byte <= 0x7eu8 { return EscapeDefault([byte, 0u8, 0u8, 0u8], 1usize, 0usize) }
    EscapeDefault([0x5cu8, 0x78u8, escape_hex_nibble(byte >> 4u8), escape_hex_nibble(byte & 0x0fu8)], 4usize, 0usize)
}

extend u8 {
    pub fn escape_ascii(): EscapeDefault { escape_default_byte(self) }
}

// Non-zero integers; the wrapped value is never zero.
pub copy type NonZero<T: Copy> { value: T }

extend<T: Copy + Default + PartialEq> NonZero<T> {
    pub static fn new(value: T): NonZero<T>? {
        if value == T.(Default).default() { none } else { present(NonZero(value)) }
    }
    pub static unsafe fn new_unchecked(value: T): NonZero<T> { NonZero(value) }
}

macro nonzero_common {
    ($type:ident) => {
        extend NonZero<$type> {
            pub fn get(): $type { self.value }
            pub fn leading_zeros(): u32 { self.value.leading_zeros() }
            pub fn trailing_zeros(): u32 { self.value.trailing_zeros() }
            pub fn count_ones(): NonZero<u32> { NonZero(self.value.count_ones()) }
            pub fn checked_add(other: $type): NonZero<$type>? {
                match self.value.checked_add(other) {
                    present(sum) => { if sum == 0 { none } else { present(NonZero(sum)) } },
                    none => none
                }
            }
            pub fn checked_mul(other: NonZero<$type>): NonZero<$type>? {
                match self.value.checked_mul(other.value) {
                    present(product) => present(NonZero(product)),
                    none => none
                }
            }
            pub fn checked_pow(exponent: u32): NonZero<$type>? {
                match self.value.checked_pow(exponent) {
                    present(power) => present(NonZero(power)),
                    none => none
                }
            }
        }
        extend $type implements BitOr<NonZero<$type>> {
            type Output = NonZero<$type>
            fn bitor(read rhs: NonZero<$type>): NonZero<$type> { NonZero(self | rhs.value) }
        }
        extend NonZero<$type> implements BitOr<$type> {
            type Output = NonZero<$type>
            fn bitor(read rhs: $type): NonZero<$type> { NonZero(self.value | rhs) }
        }
        extend NonZero<$type> implements Clone {
            fn clone(): NonZero<$type> { self }
        }
        extend NonZero<$type> implements PartialEq {
            fn eq(read other: NonZero<$type>): bool { self.value == other.value }
        }
        extend NonZero<$type> implements Eq {}
        extend NonZero<$type> implements PartialOrd {
            fn partial_cmp(read other: NonZero<$type>): Ordering? { self.value.partial_cmp(read other.value) }
        }
        extend NonZero<$type> implements Ord {
            fn cmp(read other: NonZero<$type>): Ordering { self.value.cmp(read other.value) }
        }
        extend NonZero<$type> implements Hash {
            fn hash<State: Hasher>(mut state: State): Unit { self.value.hash(mut state) }
        }
        extend NonZero<$type> implements Debug {
            fn fmt(mut f: Formatter): Unit throws Error { try $type.(Debug).fmt(read self.value, mut f) }
        }
        extend NonZero<$type> implements Display {
            fn fmt(mut f: Formatter): Unit throws Error { try $type.(Display).fmt(read self.value, mut f) }
        }
        extend NonZero<$type> implements FromStr {
            type Error = ParseIntError
            static fn from_str(read input: Text): NonZero<$type> throws ParseIntError {
                let value = try parse_radix<$type>(input, 10u32)
                if value == 0 { throw ParseIntError(IntErrorKind.Zero) }
                NonZero(value)
            }
        }
        extend $type implements From<NonZero<$type>> {
            static fn from(take value: NonZero<$type>): $type { value.value }
        }
    };
}

macro nonzero_unsigned {
    ($type:ident) => {
        extend NonZero<$type> {
            pub fn is_power_of_two(): bool { self.value.is_power_of_two() }
            pub fn saturating_add(other: $type): NonZero<$type> { NonZero(self.value.saturating_add(other)) }
            pub fn saturating_mul(other: NonZero<$type>): NonZero<$type> {
                NonZero(self.value.saturating_mul(other.value))
            }
            pub fn saturating_pow(exponent: u32): NonZero<$type> { NonZero(self.value.saturating_pow(exponent)) }
        }
        extend $type implements Div<NonZero<$type>> {
            type Output = $type
            fn div(read rhs: NonZero<$type>): $type { self / rhs.value }
        }
        extend $type implements Rem<NonZero<$type>> {
            type Output = $type
            fn rem(read rhs: NonZero<$type>): $type { self % rhs.value }
        }
        extend $type implements DivAssign<NonZero<$type>> {
            mut fn div_assign(read rhs: NonZero<$type>): Unit { self = self / rhs.value }
        }
        extend $type implements RemAssign<NonZero<$type>> {
            mut fn rem_assign(read rhs: NonZero<$type>): Unit { self = self % rhs.value }
        }
    };
}

macro nonzero_signed {
    ($type:ident, $unsigned:ident) => {
        extend NonZero<$type> {
            pub fn abs(): NonZero<$type> { NonZero(self.value.abs()) }
            pub fn unsigned_abs(): NonZero<$unsigned> { NonZero(self.value.unsigned_abs()) }
            pub fn is_positive(): bool { self.value > 0 }
            pub fn is_negative(): bool { self.value < 0 }
        }
        extend NonZero<$type> implements Neg {
            type Output = NonZero<$type>
            fn neg(): NonZero<$type> { NonZero(-self.value) }
        }
    };
}

// Lossless NonZero widenings mirror the `From` pairs between the integers.
macro nonzero_from {
    ($target:ident; $($source:ident),*) => {
        $(
            extend NonZero<$target> implements From<NonZero<$source>> {
                static fn from(take value: NonZero<$source>): NonZero<$target> {
                    NonZero(value.value as $target)
                }
            }
        )*
    };
}

nonzero_common!(i8)
nonzero_common!(i16)
nonzero_common!(i32)
nonzero_common!(i64)
nonzero_common!(i128)
nonzero_common!(isize)
nonzero_common!(u8)
nonzero_common!(u16)
nonzero_common!(u32)
nonzero_common!(u64)
nonzero_common!(u128)
nonzero_common!(usize)

nonzero_unsigned!(u8)
nonzero_unsigned!(u16)
nonzero_unsigned!(u32)
nonzero_unsigned!(u64)
nonzero_unsigned!(u128)
nonzero_unsigned!(usize)

nonzero_signed!(i8, u8)
nonzero_signed!(i16, u16)
nonzero_signed!(i32, u32)
nonzero_signed!(i64, u64)
nonzero_signed!(i128, u128)
nonzero_signed!(isize, usize)

nonzero_from!(u16; u8)
nonzero_from!(u32; u8, u16)
nonzero_from!(u64; u8, u16, u32)
nonzero_from!(u128; u8, u16, u32, u64)
nonzero_from!(usize; u8, u16)
nonzero_from!(i16; u8, i8)
nonzero_from!(i32; u8, u16, i8, i16)
nonzero_from!(i64; u8, u16, u32, i8, i16, i32)
nonzero_from!(i128; u8, u16, u32, u64, i8, i16, i32, i64)
nonzero_from!(isize; u8, i8, i16)

// Decimal text of an integer, formatted into a fixed buffer that holds the longest value.
pub type NumBuffer<T> { bytes: [u8; 40]; marker: Phantom<T> }

extend<T> NumBuffer<T> {
    pub static fn new(): NumBuffer<T> { NumBuffer([0u8; 40], Phantom<T>()) }
}

fn write_decimal<T>(mut buffer: NumBuffer<T>, negative: bool, magnitude: u128): usize {
    var position = 40usize
    var rest = magnitude
    if rest == 0u128 {
        position -= 1usize
        buffer.bytes[position] = 0x30u8
    }
    while rest > 0u128 {
        position -= 1usize
        buffer.bytes[position] = 0x30u8 + (rest % 10u128) as u8
        rest = rest / 10u128
    }
    if negative {
        position -= 1usize
        buffer.bytes[position] = 0x2du8
    }
    position
}

fn decimal_text<T>(read buffer: NumBuffer<T>, start: usize): read Text from buffer {
    unsafe { from_utf8_unchecked(unsafe { slice.subslice_unchecked(read buffer.bytes, start, 40usize) }) }
}

macro integer_format_into {
    (signed $type:ident) => {
        extend $type {
            pub fn format_into(mut buffer: NumBuffer<$type>): read Text from buffer {
                let wide = self as i128
                let magnitude = if wide < 0i128 { wide.wrapping_neg() as u128 } else { wide as u128 }
                let start = write_decimal(mut buffer, wide < 0i128, magnitude)
                decimal_text(read buffer, start)
            }
        }
    };
    (unsigned $type:ident) => {
        extend $type {
            pub fn format_into(mut buffer: NumBuffer<$type>): read Text from buffer {
                let start = write_decimal(mut buffer, false, self as u128)
                decimal_text(read buffer, start)
            }
        }
    };
}

integer_format_into!(signed i8)
integer_format_into!(signed i16)
integer_format_into!(signed i32)
integer_format_into!(signed i64)
integer_format_into!(signed i128)
integer_format_into!(signed isize)
integer_format_into!(unsigned u8)
integer_format_into!(unsigned u16)
integer_format_into!(unsigned u32)
integer_format_into!(unsigned u64)
integer_format_into!(unsigned u128)
integer_format_into!(unsigned usize)
