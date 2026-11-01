// expect-error: unsafe 4:5 operation requires an unsafe block or unsafe function

fn main(): i32 {
    1.0f64.to_int_unchecked<i32>()
}
