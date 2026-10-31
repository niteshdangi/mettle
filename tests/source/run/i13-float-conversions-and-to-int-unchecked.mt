import core.convert
import core.convert.From
import core.float

fn main(): i32 {
    let truncated: i32 = unsafe { 3.9f64.to_int_unchecked<i32>() }
    if truncated != 3 { return 1 }
    let negative: i8 = unsafe { (-7.5f32).to_int_unchecked<i8>() }
    if negative != -7i8 { return 2 }
    let wide: u64 = unsafe { 4294967296.0f64.to_int_unchecked<u64>() }
    if wide != 4294967296u64 { return 3 }
    if f64.(From<i32>).`from`(-3i32) != -3.0f64 { return 4 }
    if f64.(From<f32>).`from`(1.5f32) != 1.5f64 { return 5 }
    if f64.(From<u32>).`from`(4294967295u32) != 4294967295.0f64 { return 6 }
    if f32.(From<u16>).`from`(65535u16) != 65535.0f32 { return 7 }
    let via_into: f64 = 7u8.into()
    if via_into != 7.0f64 { return 8 }
    0
}
