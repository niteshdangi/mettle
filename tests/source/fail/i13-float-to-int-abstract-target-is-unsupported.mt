// expect-error: feature 4:14 unchecked float conversion requires a concrete integer target

fn convert<Int>(value: f64): Int {
    unsafe { value.to_int_unchecked<Int>() }
}

fn main(): i32 { convert<i32>(1.0f64) }
