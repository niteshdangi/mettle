// profiles: debug release
// Integer format_into writes the decimal text of every integer type into a
// NumBuffer and returns it. Expected values are computed independently.
import core.num
import core.num.NumBuffer

fn main(): i32 {
    var buffer = NumBuffer<i8>.new()
    if (0i8).format_into(mut buffer) != "0" { return 1 }
    if (-128i8).format_into(mut buffer) != "-128" { return 2 }
    var wide = NumBuffer<i16>.new()
    if (-32768i16).format_into(mut wide) != "-32768" { return 3 }
    var i32_buffer = NumBuffer<i32>.new()
    if (2147483647i32).format_into(mut i32_buffer) != "2147483647" { return 4 }
    var i64_buffer = NumBuffer<i64>.new()
    if (-9223372036854775807i64 - 1i64).format_into(mut i64_buffer) != "-9223372036854775808" { return 5 }
    var i128_buffer = NumBuffer<i128>.new()
    if (-170141183460469231731687303715884105727i128 - 1i128).format_into(mut i128_buffer) != "-170141183460469231731687303715884105728" { return 6 }
    var isize_buffer = NumBuffer<isize>.new()
    if (-1234isize).format_into(mut isize_buffer) != "-1234" { return 7 }
    var u8_buffer = NumBuffer<u8>.new()
    if (255u8).format_into(mut u8_buffer) != "255" { return 8 }
    var u16_buffer = NumBuffer<u16>.new()
    if (65535u16).format_into(mut u16_buffer) != "65535" { return 9 }
    var u32_buffer = NumBuffer<u32>.new()
    if (4294967295u32).format_into(mut u32_buffer) != "4294967295" { return 10 }
    var u64_buffer = NumBuffer<u64>.new()
    if (18446744073709551615u64).format_into(mut u64_buffer) != "18446744073709551615" { return 11 }
    var u128_buffer = NumBuffer<u128>.new()
    if (340282366920938463463374607431768211455u128).format_into(mut u128_buffer) != "340282366920938463463374607431768211455" { return 12 }
    var usize_buffer = NumBuffer<usize>.new()
    if (42usize).format_into(mut usize_buffer) != "42" { return 13 }
    if (1000u32).format_into(mut u32_buffer) != "1000" { return 14 }
    0
}
