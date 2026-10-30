
type Owned { value: i32 }
fn identity<T>(value: take T): T { take value }
fn count<T: Copy>(value: T, remaining: i32): T {
    if remaining == 0 { value } else { count(value,remaining - 1) }
}
fn answer<const VALUE: i32 = 20 + 22>(): i32 { VALUE }
fn main(): i32 {
    let owned = identity(Owned(answer()))
    if owned.value == 42 && count(42,3) == 42 &&
       answer::<{20 + 22}>() == answer::<42>() { 0 } else { 1 }
}
