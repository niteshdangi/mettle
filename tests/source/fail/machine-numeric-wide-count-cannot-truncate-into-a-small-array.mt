// expect-error: limit 2:26 array length limit exceeded
fn main() { let values = [0;340282366920938463463374607431768211455u128]; 0 }
