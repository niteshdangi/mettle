import core.num.{IntegerBounds, NonZero, Saturating}
import std.num.{IntegerBounds as StdIntegerBounds}

fn make_nonzero<T: Copy + IntegerBounds>(value: T): NonZero<T>? {
    NonZero<T>.new(value)
}

fn make_std_nonzero<T: Copy + StdIntegerBounds>(value: T): NonZero<T>? {
    NonZero<T>.new(value)
}

const LOW: u8 = NonZero<u8>.MIN.get()
const SIGNED_LOW: i16 = NonZero<i16>.MIN.get()
const HIGH: u16 = Saturating<u16>.MAX.value
const MADE: u8 = match NonZero<u8>.new(7u8) {
    present(value) => value.get(),
    none => 0u8
}
const ROUND_TRIP: u16 =
    Saturating<u16>.from_le(Saturating(0x1234u16).to_le()).value
const REJECTS_ZERO: bool = NonZero<u8>.new(0u8).is_none()

fn main(): i32 {
    if LOW != 1u8 || SIGNED_LOW != -32768i16 ||
       HIGH != 65535u16 || MADE != 7u8 || ROUND_TRIP != 0x1234u16 || !REJECTS_ZERO {
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
