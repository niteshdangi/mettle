// profiles: debug release
// Required constants exercise both Text literals and constructed UTF-8 views.

import core.num
import core.num.{FromText, IntErrorKind, ParseIntError}
import core.text.from_utf8_unchecked

const fn has_kind<T: Copy>(result: Outcome<T, ParseIntError>, expected: IntErrorKind): bool {
    match result {
        success(_) => false,
        failure(error) => (error.kind as u8) == (expected as u8)
    }
}

macro parser_constants {
    ($name:ident, $result:ident, $type:ident) => {
        const fn $name(): i32 {
            let signed = $type.MIN < 0 as $type
            var maximum = [0x66u8; ($type.BITS / 4u32) as usize]
            if signed { maximum[0usize] = 0x37u8 }
            let maximum_text = unsafe { from_utf8_unchecked(maximum) }
            match capture num.from_str_radix<$type>(maximum_text, 16u32) {
                success(value) => { if value != $type.MAX { return 1 } },
                failure(_) => { return 1 }
            }
            let zero_bytes = [0x30u8]
            let zero = unsafe { from_utf8_unchecked(zero_bytes) }
            match capture num.from_str_radix<$type>(zero, 10u32) {
                success(value) => { if value != 0 as $type { return 2 } },
                failure(_) => { return 2 }
            }
            match capture num.parse<$type>("+7") {
                success(value) => { if value != 7 as $type { return 3 } },
                failure(_) => { return 3 }
            }
            match capture num.parse_radix<$type>("7F", 16u32) {
                success(value) => { if value != 127 as $type { return 4 } },
                failure(_) => { return 4 }
            }
            match capture $type.(FromText).from_text_radix("z", 36u32) {
                success(value) => { if value != 35 as $type { return 5 } },
                failure(_) => { return 5 }
            }
            match capture num.from_str_radix<$type>("101", 2u32) {
                success(value) => { if value != 5 as $type { return 6 } },
                failure(_) => { return 6 }
            }

            if !has_kind(capture num.from_str_radix<$type>("", 10u32), IntErrorKind.Empty) ||
               !has_kind(capture num.from_str_radix<$type>("+", 10u32), IntErrorKind.InvalidDigit) ||
               !has_kind(capture num.from_str_radix<$type>("-", 10u32), IntErrorKind.InvalidDigit) {
                return 7
            }
            if !has_kind(capture num.from_str_radix<$type>("1_0", 10u32), IntErrorKind.InvalidDigit) ||
               !has_kind(capture num.from_str_radix<$type>(" 1", 10u32), IntErrorKind.InvalidDigit) ||
               !has_kind(capture num.from_str_radix<$type>("0x1", 16u32), IntErrorKind.InvalidDigit) ||
               !has_kind(capture num.from_str_radix<$type>("\u{e9}", 36u32), IntErrorKind.InvalidDigit) ||
               !has_kind(capture num.from_str_radix<$type>("2", 2u32), IntErrorKind.InvalidDigit) {
                return 8
            }
            if signed {
                match capture num.from_str_radix<$type>("-0", 10u32) {
                    success(value) => { if value != 0 as $type { return 9 } },
                    failure(_) => { return 9 }
                }
                var minimum = [0x30u8; ($type.BITS / 4u32) as usize + 1usize]
                minimum[0usize] = 0x2du8
                minimum[1usize] = 0x38u8
                let minimum_text = unsafe { from_utf8_unchecked(minimum) }
                match capture num.from_str_radix<$type>(minimum_text, 16u32) {
                    success(value) => { if value != $type.MIN { return 10 } },
                    failure(_) => { return 10 }
                }
                var below = minimum
                below[($type.BITS / 4u32) as usize] = 0x31u8
                let below_text = unsafe { from_utf8_unchecked(below) }
                if !has_kind(capture num.from_str_radix<$type>(below_text, 16u32), IntErrorKind.NegOverflow) {
                    return 11
                }
                var above = [0x30u8; ($type.BITS / 4u32) as usize]
                above[0usize] = 0x38u8
                let above_text = unsafe { from_utf8_unchecked(above) }
                if !has_kind(capture num.from_str_radix<$type>(above_text, 16u32), IntErrorKind.PosOverflow) {
                    return 12
                }
            } else {
                if !has_kind(capture num.from_str_radix<$type>("-0", 10u32), IntErrorKind.InvalidDigit) {
                    return 14
                }
                var above = [0x30u8; ($type.BITS / 4u32) as usize + 1usize]
                above[0usize] = 0x31u8
                let above_text = unsafe { from_utf8_unchecked(above) }
                if !has_kind(capture num.from_str_radix<$type>(above_text, 16u32), IntErrorKind.PosOverflow) {
                    return 15
                }
            }
            var invalid = [0x30u8; ($type.BITS / 4u32) as usize + 2usize]
            invalid[0usize] = 0x31u8
            invalid[($type.BITS / 4u32) as usize + 1usize] = 0x67u8
            let invalid_text = unsafe { from_utf8_unchecked(invalid) }
            if !has_kind(capture num.from_str_radix<$type>(invalid_text, 16u32), IntErrorKind.InvalidDigit) {
                return 13
            }
            0
        }
        const $result: i32 = $name()
    };
}

parser_constants!(parse_i8, I8_RESULT, i8)
parser_constants!(parse_i16, I16_RESULT, i16)
parser_constants!(parse_i32, I32_RESULT, i32)
parser_constants!(parse_i64, I64_RESULT, i64)
parser_constants!(parse_i128, I128_RESULT, i128)
parser_constants!(parse_isize, ISIZE_RESULT, isize)
parser_constants!(parse_u8, U8_RESULT, u8)
parser_constants!(parse_u16, U16_RESULT, u16)
parser_constants!(parse_u32, U32_RESULT, u32)
parser_constants!(parse_u64, U64_RESULT, u64)
parser_constants!(parse_u128, U128_RESULT, u128)
parser_constants!(parse_usize, USIZE_RESULT, usize)

const fn literal_extrema(): bool {
    match capture num.from_str_radix<u128>("340282366920938463463374607431768211455", 10u32) {
        success(value) => { if value != u128.MAX { return false } },
        failure(_) => { return false }
    }
    match capture num.from_str_radix<i128>("-170141183460469231731687303715884105728", 10u32) {
        success(value) => value == i128.MIN,
        failure(_) => false
    }
}

const LITERAL_EXTREMA: bool = literal_extrema()

fn main(): i32 {
    let codes = [
        I8_RESULT, I16_RESULT, I32_RESULT, I64_RESULT, I128_RESULT, ISIZE_RESULT,
        U8_RESULT, U16_RESULT, U32_RESULT, U64_RESULT, U128_RESULT, USIZE_RESULT
    ]
    var index = 0usize
    while index < 12usize {
        if codes[index] != 0 { return codes[index] }
        index += 1usize
    }
    if !LITERAL_EXTREMA { return 17 }
    0
}
