alias Target = i64

unsafe fn every_f32_target(value: f32): bool {
    value.to_int_unchecked<i8>() == 15i8 &&
        value.to_int_unchecked<u8>() == 15u8 &&
        value.to_int_unchecked<i16>() == 15i16 &&
        value.to_int_unchecked<u16>() == 15u16 &&
        value.to_int_unchecked<i32>() == 15i32 &&
        value.to_int_unchecked<u32>() == 15u32 &&
        value.to_int_unchecked<i64>() == 15i64 &&
        value.to_int_unchecked<u64>() == 15u64 &&
        value.to_int_unchecked<i128>() == 15i128 &&
        value.to_int_unchecked<u128>() == 15u128 &&
        value.to_int_unchecked<isize>() == 15isize &&
        value.to_int_unchecked<usize>() == 15usize
}

unsafe fn every_f64_target(value: f64): bool {
    value.to_int_unchecked<i8>() == 15i8 &&
        value.to_int_unchecked<u8>() == 15u8 &&
        value.to_int_unchecked<i16>() == 15i16 &&
        value.to_int_unchecked<u16>() == 15u16 &&
        value.to_int_unchecked<i32>() == 15i32 &&
        value.to_int_unchecked<u32>() == 15u32 &&
        value.to_int_unchecked<i64>() == 15i64 &&
        value.to_int_unchecked<u64>() == 15u64 &&
        value.to_int_unchecked<i128>() == 15i128 &&
        value.to_int_unchecked<u128>() == 15u128 &&
        value.to_int_unchecked<isize>() == 15isize &&
        value.to_int_unchecked<usize>() == 15usize
}

fn main(): i32 {
    unsafe {
        if !every_f32_target(15.75f32) || !every_f64_target(15.75f64) {
            return 9
        }
        if 127.75f32.to_int_unchecked<i8>() != 127i8 ||
            (-128.75f64).to_int_unchecked<i8>() != -128i8 {
            return 1
        }
        if 255.75f64.to_int_unchecked<u8>() != 255u8 ||
            (-0.75f32).to_int_unchecked<u8>() != 0u8 {
            return 2
        }
        if 32767.75f64.to_int_unchecked<i16>() != 32767i16 ||
            65535.75f64.to_int_unchecked<u16>() != 65535u16 {
            return 3
        }
        if 2147483647.75f64.to_int_unchecked<i32>() != 2147483647i32 ||
            4294967295.75f64.to_int_unchecked<u32>() != 4294967295u32 {
            return 4
        }
        if (-1024.75f32).to_int_unchecked<i64>() != -1024i64 ||
            1024.75f32.to_int_unchecked<u64>() != 1024u64 ||
            (-1024.75f64).to_int_unchecked<i128>() != -1024i128 ||
            1024.75f64.to_int_unchecked<u128>() != 1024u128 {
            return 5
        }
        if (-1024.75f64).to_int_unchecked<isize>() != -1024isize ||
            1024.75f32.to_int_unchecked<usize>() != 1024usize {
            return 6
        }
        let inferred: i16 = 12.75f64.to_int_unchecked()
        if inferred != 12i16 ||
            f32.to_int_unchecked<Target>(-12.75f32) != -12i64 {
            return 7
        }
        if (-0.0f64).to_int_unchecked<u32>() != 0u32 { return 8 }
        if (-9223372036854775808.0f64).to_int_unchecked<i64>() !=
            -9223372036854775808i64 ||
            9223372036854774784.0f64.to_int_unchecked<i64>() !=
            9223372036854774784i64 ||
            18446744073709549568.0f64.to_int_unchecked<u64>() !=
            18446744073709549568u64 {
            return 10
        }
        let signed_min = -170141183460469231731687303715884105728.0f32
        let unsigned_large = 170141183460469231731687303715884105728.0f64
        if signed_min.to_int_unchecked<i128>() !=
            -170141183460469231731687303715884105728i128 ||
            unsigned_large.to_int_unchecked<u128>() !=
            170141183460469231731687303715884105728u128 {
            return 11
        }
    }
    0
}
