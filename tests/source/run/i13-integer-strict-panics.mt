// profiles: debug release
// Every strict integer operation panics on overflow or an invalid operand in
// both profiles with the runtime arithmetic panic code 1, at a narrow and the
// widest width of each signedness.
import std.panic.{ catch_panic, CatchResult }

fn panics(body: fn(): Unit): bool {
    match take catch_panic(body) {
        CatchResult.Panicked(info) => info.code() == 1,
        CatchResult.Returned(_) => false
    }
}

fn signed(): i32 {
    if !panics(fn(): Unit { let _x = i8.MAX.strict_add(1i8) }) { return 1 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_sub(1i8) }) { return 2 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_mul(-1i8) }) { return 3 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_div(-1i8) }) { return 4 }
    if !panics(fn(): Unit { let _x = 1i8.strict_div(0i8) }) { return 5 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_rem(-1i8) }) { return 6 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_div_euclid(-1i8) }) { return 7 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_rem_euclid(-1i8) }) { return 8 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_neg() }) { return 9 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_abs() }) { return 10 }
    if !panics(fn(): Unit { let _x = 1i8.strict_shl(8u32) }) { return 11 }
    if !panics(fn(): Unit { let _x = 1i8.strict_shr(8u32) }) { return 12 }
    if !panics(fn(): Unit { let _x = 2i8.strict_pow(7u32) }) { return 13 }
    if !panics(fn(): Unit { let _x = i8.MAX.strict_add_unsigned(1u8) }) { return 14 }
    if !panics(fn(): Unit { let _x = i8.MIN.strict_sub_unsigned(1u8) }) { return 15 }
    if !panics(fn(): Unit { let _x = i128.MAX.strict_add(1i128) }) { return 16 }
    if !panics(fn(): Unit { let _x = i128.MIN.strict_neg() }) { return 17 }
    if !panics(fn(): Unit { let _x = 1i128.strict_shl(128u32) }) { return 18 }
    if !panics(fn(): Unit { let _x = i128.MIN.strict_div(-1i128) }) { return 19 }
    0
}

fn unsigned(): i32 {
    if !panics(fn(): Unit { let _x = u8.MAX.strict_add(1u8) }) { return 31 }
    if !panics(fn(): Unit { let _x = 0u8.strict_sub(1u8) }) { return 32 }
    if !panics(fn(): Unit { let _x = 16u8.strict_mul(16u8) }) { return 33 }
    if !panics(fn(): Unit { let _x = 1u8.strict_div(0u8) }) { return 34 }
    if !panics(fn(): Unit { let _x = 1u8.strict_rem(0u8) }) { return 35 }
    if !panics(fn(): Unit { let _x = 1u8.strict_div_euclid(0u8) }) { return 36 }
    if !panics(fn(): Unit { let _x = 1u8.strict_rem_euclid(0u8) }) { return 37 }
    if !panics(fn(): Unit { let _x = 1u8.strict_neg() }) { return 38 }
    if !panics(fn(): Unit { let _x = 1u8.strict_shl(8u32) }) { return 39 }
    if !panics(fn(): Unit { let _x = 1u8.strict_shr(9u32) }) { return 40 }
    if !panics(fn(): Unit { let _x = 2u8.strict_pow(8u32) }) { return 41 }
    if !panics(fn(): Unit { let _x = u8.MAX.strict_add_signed(1i8) }) { return 42 }
    if !panics(fn(): Unit { let _x = 0u8.strict_sub_signed(1i8) }) { return 43 }
    if !panics(fn(): Unit { let _x = u128.MAX.strict_mul(2u128) }) { return 44 }
    if !panics(fn(): Unit { let _x = 1u128.strict_neg() }) { return 45 }
    // Zero is the one strict negation of an unsigned value that succeeds.
    if panics(fn(): Unit { let _x = 0u8.strict_neg() }) { return 46 }
    0
}

fn main(): i32 {
    let s = signed()
    if s != 0 { return s }
    unsigned()
}
