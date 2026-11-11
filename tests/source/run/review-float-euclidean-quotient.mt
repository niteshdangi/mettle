fn main(): i32 {
    let large64 = 18446744073709551616.0f64
    let large32 = 33554432.0f32
    if (-1.0f64).div_euclid(large64) != -1.0f64 { return 1 }
    if (-1.0f64).div_euclid(-large64) != 1.0f64 { return 2 }
    if (-1.0f32).div_euclid(large32) != -1.0f32 { return 3 }
    if (-1.0f32).div_euclid(-large32) != 1.0f32 { return 4 }
    if 7.0f64.div_euclid(3.0f64) != 2.0f64 { return 5 }
    if (-7.0f64).div_euclid(3.0f64) != -3.0f64 { return 6 }
    if 7.0f64.div_euclid(-3.0f64) != -2.0f64 { return 7 }
    if (-7.0f64).div_euclid(-3.0f64) != 3.0f64 { return 8 }
    if (-7.0f64).rem_euclid(3.0f64) != 2.0f64 { return 9 }
    0
}
