
interface Family {
    type Item<T: Copy>: Copy;
    const FLAG: bool;
}
type Number {}
impl Number implements Family {
    type Item<T: Copy> = (T, T)
    const FLAG = true
}
fn duplicate<T: Copy>(value: T): <Number implements Family>::Item<T> { (value,value) }
fn enabled<T: Family>(value: T): bool { T::FLAG }
fn main() {
    let pair = duplicate(21)
    if pair.0 + pair.1 == 42 && enabled(Number()) &&
        <Number implements Family>::FLAG { 0 } else { 1 }
}
