import core.num.{IntegerBounds, NonZero, Saturating}
import std.num.{IntegerBounds as StdIntegerBounds}

fn make_nonzero<T: Copy + IntegerBounds>(value: T): NonZero<T>? {
    NonZero<T>.new(value)
}

fn make_std_nonzero<T: Copy + StdIntegerBounds>(value: T): NonZero<T>? {
    NonZero<T>.new(value)
}

interface PrimitiveBits { const BITS: u32; }
extend i8 implements PrimitiveBits { const BITS: u32 = i8.BITS }

const I8_BITS: u32 = i8.(PrimitiveBits).BITS
const LOW: u8 = NonZero<u8>.MIN.get()
const SIGNED_LOW: i16 = NonZero<i16>.MIN.get()
const HIGH: u16 = Saturating<u16>.MAX.value
const MADE: u8 = match NonZero<u8>.new(7u8) {
    present(value) => value.get(),
    none => 0u8
}
const REJECTS_ZERO: bool = NonZero<u8>.new(0u8).is_none()
const ZERO_IS_NONE: bool = match NonZero<u8>.new(0u8) {
    none => true,
    present(_) => false
}
const ROUND_TRIP: u16 =
    Saturating<u16>.from_le(Saturating(0x1234u16).to_le()).value

fn main(): i32 {
    if I8_BITS != 8u32 || LOW != 1u8 || SIGNED_LOW != -32768i16 ||
       HIGH != 65535u16 || MADE != 7u8 || !ZERO_IS_NONE || !REJECTS_ZERO ||
       ROUND_TRIP != 0x1234u16 {
        return 1
    }
    let minimum = Saturating<i16>.MIN
    let maximum = Saturating<u16>.MAX
    match make_nonzero(0u8) {
        present(_) => { return 4 },
        none => {}
    }
    match make_std_nonzero(0u8) {
        present(_) => { return 5 },
        none => {}
    }
    match make_nonzero(9u8) {
        present(value) => {
            if minimum.value == SIGNED_LOW && maximum.value == HIGH &&
               value.get() == 9u8 { 0 } else { 2 }
        },
        none => 3
    }
}
