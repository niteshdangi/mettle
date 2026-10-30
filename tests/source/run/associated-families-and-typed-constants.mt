
interface Family {
    type Item<T: Copy>: Copy;
    const FLAG: bool;
}
type Number {}
extend Number implements Family {
    type Item<T: Copy> = (T, T)
    const FLAG = true
}
fn duplicate<T: Copy>(value: T): Number.(Family).Item<T> { (value,value) }
fn enabled<T: Family>(value: T): bool { T.FLAG }
fn main() {
    let pair = duplicate(21)
    if pair.0 + pair.1 == 42 && enabled(Number()) &&
        Number.(Family).FLAG { 0 } else { 1 }
}
