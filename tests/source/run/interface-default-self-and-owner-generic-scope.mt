
interface Add<Rhs = Self> { fn add(rhs: read Rhs): i32; }
interface Pair<A = i32, B = A> { fn combine(value: read B): i32; }
type Number { value: i32 }
impl Number implements Add {
    fn add(rhs: read Number): i32 { self.value + rhs.value }
}
impl Number implements Pair {
    fn combine(value: read i32): i32 { self.value + value }
}
fn add<T: Add>(left: T, right: T): i32 { left.add(right) }
fn call<A: Pair>(value: A): i32 { value.combine(21) }
fn main(): i32 {
    let value = Number(21)
    if add(value,value) == 42 && call(value) == 42 { 0 } else { 1 }
}
