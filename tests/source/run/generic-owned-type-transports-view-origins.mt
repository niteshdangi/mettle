
fn identity<T>(take value: T): T { take value }
fn enabled<const VALUE: bool = true>(): bool { VALUE }
fn byte<const VALUE: u8 = 42>(): u8 { VALUE }
fn main(): i32 {
    let value = 42
    let borrowed = identity(read value)
    if *borrowed == 42 && enabled() && byte() == b'*' { 0 } else { 1 }
}
