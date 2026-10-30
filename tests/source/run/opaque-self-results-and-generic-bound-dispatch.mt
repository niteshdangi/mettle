
interface Doubled {
    fn value(): i32;
    fn doubled(): Self where Self: Sized;
}
type Number { value: i32 }
extend Number implements Doubled {
    fn value(): i32 { self.value }
    fn doubled(): Number { Number(self.value * 2) }
}
fn make(value: i32): some Doubled { Number(value) }
fn inspect<T: Doubled>(value: T): i32 { value.value() }
fn main() {
    let value = make(21)
    let doubled = value.doubled()
    if doubled.value() == 42 && inspect(doubled) == 42 { 0 } else { 1 }
}
