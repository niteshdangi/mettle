fn seed(): i32 { 12345 } // bench-edit-point

fn integrate(steps: i32): f64 {
    let count = steps as f64
    let width = 1.0f64 / count
    var sum = 0.0f64
    var index = 0
    while index < steps {
        let x = (index as f64 + 0.5f64) * width
        sum += 4.0f64 / (1.0f64 + x * x)
        index += 1
    }
    sum * width
}

fn main(): i32 {
    let pi = integrate(50000000 + seed())
    let scaled = (pi * 1000000.0f64) as i64
    (scaled % 128i64) as i32
}
