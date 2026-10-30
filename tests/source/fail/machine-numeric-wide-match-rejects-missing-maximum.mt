// expect-error: type 3:11 non-exhaustive match

fn main(){match 0u128 { 0..340282366920938463463374607431768211455 => 0 }}
