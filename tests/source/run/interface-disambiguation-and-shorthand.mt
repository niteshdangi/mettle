
interface Readable { fn value(): i32; }
interface Alternate { fn value(): i32; }
type Number implements Readable {
    value: i32
    fn value(): i32 { self.value }
}
impl Number implements Alternate { fn value(): i32 { self.value + 1 } }
fn inspect<T: Readable>(value: T): i32 { value.value() }
fn main() {
    let value = Number(42)
    if inspect(value) == 42 &&
        <Number implements Alternate>::value(value) == 43 { 0 } else { 1 }
}
