// profiles: debug release

macro integer_constants {
    ($name:ident, $verified:ident, $type:ident) => {
        const fn $name(): bool {
            let two = 2 as $type
            let nine = 9 as $type
            let zero = 0 as $type
            let one = 1 as $type
            if two.wrapping_pow(3u32) != 8 as $type { return false }
            if two.saturating_pow(3u32) != 8 as $type { return false }
            match two.checked_pow(3u32) {
                present(value) => { if value != 8 as $type { return false } },
                none => { return false }
            }
            let power = two.overflowing_pow(3u32)
            if power.0 != 8 as $type || power.1 { return false }
            if nine.wrapping_div(two) != 4 as $type { return false }
            if nine.wrapping_div_euclid(two) != 4 as $type { return false }
            if nine.wrapping_rem(two) != one { return false }
            if nine.wrapping_rem_euclid(two) != one { return false }
            if nine.saturating_div(two) != 4 as $type { return false }
            let quotient = nine.overflowing_div(two)
            let quotient_euclid = nine.overflowing_div_euclid(two)
            let remainder = nine.overflowing_rem(two)
            let remainder_euclid = nine.overflowing_rem_euclid(two)
            if quotient.0 != 4 as $type || quotient.1 { return false }
            if quotient_euclid.0 != 4 as $type || quotient_euclid.1 { return false }
            if remainder.0 != one || remainder.1 { return false }
            if remainder_euclid.0 != one || remainder_euclid.1 { return false }
            if zero.wrapping_pow(0u32) != one { return false }
            if one.wrapping_pow(u32.MAX) != one { return false }
            if two.wrapping_pow(u32.MAX) != zero { return false }
            if two.saturating_pow(u32.MAX) != $type.MAX { return false }
            match two.checked_pow(u32.MAX) {
                present(_) => { return false },
                none => {}
            }
            let huge = two.overflowing_pow(u32.MAX)
            if huge.0 != zero || !huge.1 { return false }
            let add = $type.MAX.overflowing_add(one)
            if add.0 != $type.MIN || !add.1 { return false }
            if $type.MAX.wrapping_add(one) != $type.MIN { return false }
            match $type.MAX.checked_add(one) {
                present(_) => { return false },
                none => {}
            }
            match nine.checked_add(two) {
                present(value) => { if value != 11 as $type { return false } },
                none => { return false }
            }
            let exact_add = nine.overflowing_add(two)
            if exact_add.0 != 11 as $type || exact_add.1 { return false }
            match nine.checked_div(zero) {
                present(_) => { return false },
                none => {}
            }
            if $type.MIN < zero {
                let negative_one = -1 as $type
                let negative_nine = -9 as $type
                if negative_nine.wrapping_div(two) != -4 as $type { return false }
                if negative_nine.wrapping_div_euclid(two) != -5 as $type { return false }
                if negative_nine.wrapping_rem(two) != negative_one { return false }
                if negative_nine.wrapping_rem_euclid(two) != one { return false }
                if $type.MIN.wrapping_div(negative_one) != $type.MIN { return false }
                if $type.MIN.wrapping_rem(negative_one) != zero { return false }
                if $type.MIN.saturating_div(negative_one) != $type.MAX { return false }
                match $type.MIN.checked_div(negative_one) {
                    none => {}, present(_) => { return false }
                }
                match $type.MIN.checked_div_euclid(negative_one) {
                    none => {}, present(_) => { return false }
                }
                match $type.MIN.checked_rem(negative_one) {
                    none => {}, present(_) => { return false }
                }
                match $type.MIN.checked_rem_euclid(negative_one) {
                    none => {}, present(_) => { return false }
                }
                let minimum_div = $type.MIN.overflowing_div(negative_one)
                let minimum_div_euclid = $type.MIN.overflowing_div_euclid(negative_one)
                let minimum_rem = $type.MIN.overflowing_rem(negative_one)
                let minimum_rem_euclid = $type.MIN.overflowing_rem_euclid(negative_one)
                if minimum_div.0 != $type.MIN || !minimum_div.1 { return false }
                if minimum_div_euclid.0 != $type.MIN || !minimum_div_euclid.1 { return false }
                if minimum_rem.0 != zero || !minimum_rem.1 { return false }
                if minimum_rem_euclid.0 != zero || !minimum_rem_euclid.1 { return false }
                if negative_one.wrapping_pow(u32.MAX) != negative_one { return false }
            }
            true
        }
        const $verified: bool = $name()
    };
}

integer_constants!(signed8, I8_OK, i8)
integer_constants!(signed16, I16_OK, i16)
integer_constants!(signed32, I32_OK, i32)
integer_constants!(signed64, I64_OK, i64)
integer_constants!(signed128, I128_OK, i128)
integer_constants!(signed_size, ISIZE_OK, isize)
integer_constants!(unsigned8, U8_OK, u8)
integer_constants!(unsigned16, U16_OK, u16)
integer_constants!(unsigned32, U32_OK, u32)
integer_constants!(unsigned64, U64_OK, u64)
integer_constants!(unsigned128, U128_OK, u128)
integer_constants!(unsigned_size, USIZE_OK, usize)

fn main(): i32 {
    if I8_OK && I16_OK && I32_OK && I64_OK && I128_OK && ISIZE_OK &&
       U8_OK && U16_OK && U32_OK && U64_OK && U128_OK && USIZE_OK { 0 } else { 1 }
}
