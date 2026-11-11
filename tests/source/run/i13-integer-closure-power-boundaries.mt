// profiles: debug release
import core.num
import core.panic.panic

fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(_) => false }
}

macro signed_power_boundaries {
    ($name:ident, $type:ident) => {
        fn $name(): Unit {
            let base = -2 as $type
            let exact = $type.BITS - 1u32
            if base.checked_pow(exact) != present($type.MIN) { panic("negative power exact minimum") }
            if base.wrapping_pow(exact) != $type.MIN { panic("negative power exact wrapping") }
            let exact_pair = base.overflowing_pow(exact)
            if exact_pair.0 != $type.MIN || exact_pair.1 { panic("negative power exact overflow flag") }
            if base.saturating_pow(exact) != $type.MIN { panic("negative power exact saturation") }

            let negative_one = -1 as $type
            if negative_one.checked_pow(u32.MAX) != present(negative_one) { panic("maximum exponent checked") }
            if negative_one.wrapping_pow(u32.MAX) != negative_one { panic("maximum exponent wrapping") }
            let large_pair = negative_one.overflowing_pow(u32.MAX)
            if large_pair.0 != negative_one || large_pair.1 { panic("maximum exponent overflow flag") }
            if negative_one.saturating_pow(u32.MAX) != negative_one { panic("maximum exponent saturation") }
        }
    };
}

macro unsigned_power_boundaries {
    ($name:ident, $type:ident) => {
        fn $name(): Unit {
            let base = 2 as $type
            let high_bit = ($type.MAX / 2 as $type) + 1 as $type
            let exact = $type.BITS - 1u32
            if base.checked_pow(exact) != present(high_bit) { panic("unsigned power exact high bit") }
            if base.wrapping_pow(exact) != high_bit { panic("unsigned power exact wrapping") }
            let exact_pair = base.overflowing_pow(exact)
            if exact_pair.0 != high_bit || exact_pair.1 { panic("unsigned power exact overflow flag") }
            if base.saturating_pow(exact) != high_bit { panic("unsigned power exact saturation") }

            if !missing(base.checked_pow(u32.MAX)) { panic("maximum exponent checked overflow") }
            if base.wrapping_pow(u32.MAX) != 0 as $type { panic("maximum exponent modular power") }
            let large_pair = base.overflowing_pow(u32.MAX)
            if large_pair.0 != 0 as $type || !large_pair.1 { panic("maximum exponent retained overflow") }
            if base.saturating_pow(u32.MAX) != $type.MAX { panic("maximum exponent saturated power") }
        }
    };
}

signed_power_boundaries!(signed8, i8)
signed_power_boundaries!(signed16, i16)
signed_power_boundaries!(signed32, i32)
signed_power_boundaries!(signed64, i64)
signed_power_boundaries!(signed128, i128)
signed_power_boundaries!(signed_size, isize)
unsigned_power_boundaries!(unsigned8, u8)
unsigned_power_boundaries!(unsigned16, u16)
unsigned_power_boundaries!(unsigned32, u32)
unsigned_power_boundaries!(unsigned64, u64)
unsigned_power_boundaries!(unsigned128, u128)
unsigned_power_boundaries!(unsigned_size, usize)

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
