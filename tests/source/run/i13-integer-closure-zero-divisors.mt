// profiles: debug release
import core.num
import core.panic.panic
import std.panic.{catch_panic, CatchResult}

fn arithmetic_panic(body: fn(): Unit): bool {
    match take catch_panic(body) {
        CatchResult.Panicked(info) => info.code() == 1,
        CatchResult.Returned(_) => false
    }
}

macro zero_divisors {
    ($name:ident, $type:ident) => {
        fn $name(): Unit {
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).wrapping_div(0 as $type) }) {
                panic("wrapping_div zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).wrapping_rem(0 as $type) }) {
                panic("wrapping_rem zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).wrapping_div_euclid(0 as $type) }) {
                panic("wrapping_div_euclid zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).wrapping_rem_euclid(0 as $type) }) {
                panic("wrapping_rem_euclid zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).overflowing_div(0 as $type) }) {
                panic("overflowing_div zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).overflowing_rem(0 as $type) }) {
                panic("overflowing_rem zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).overflowing_div_euclid(0 as $type) }) {
                panic("overflowing_div_euclid zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).overflowing_rem_euclid(0 as $type) }) {
                panic("overflowing_rem_euclid zero divisor")
            }
            if !arithmetic_panic(fn(): Unit { let _result = (1 as $type).saturating_div(0 as $type) }) {
                panic("saturating_div zero divisor")
            }
        }
    };
}

zero_divisors!(signed8, i8)
zero_divisors!(signed16, i16)
zero_divisors!(signed32, i32)
zero_divisors!(signed64, i64)
zero_divisors!(signed128, i128)
zero_divisors!(signed_size, isize)
zero_divisors!(unsigned8, u8)
zero_divisors!(unsigned16, u16)
zero_divisors!(unsigned32, u32)
zero_divisors!(unsigned64, u64)
zero_divisors!(unsigned128, u128)
zero_divisors!(unsigned_size, usize)

fn main(): i32 {
    signed8()
    signed16()
    signed32()
    signed64()
    signed128()
    signed_size()
    unsigned8()
    unsigned16()
    unsigned32()
    unsigned64()
    unsigned128()
    unsigned_size()
    0
}
