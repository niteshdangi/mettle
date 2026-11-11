// expect-error: type 4:56 Sized contract

interface Token {}
fn hide<T: Token + unsized>(read value: T): some Token { value }
fn main(): i32 { 0 }
