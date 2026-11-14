
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
interface StartingValue { const START: Self; }
extend u8 implements StartingValue { const START = 1 }
fn starting_value<T: StartingValue>(): T { T.(StartingValue).START }
fn main() {
    let pair = duplicate(21)
    if pair.0 + pair.1 == 42 && enabled(Number()) &&
        Number.(Family).FLAG && starting_value<u8>() == 1u8 { 0 } else { 1 }
}
