
interface Readable { fn value(): i32; }
interface Factory { type Item: Readable; fn create(): Self.Item; }
copy type Number { value: i32 }
extend Number implements Readable { fn value(): i32 { self.value } }
type Maker {}
extend Maker implements Factory {
    type Item = Number
    fn create(): Number { Number(42) }
}
fn make(): some Factory { Maker() }
fn main() {
    let factory = make()
    let item = factory.create()
    if item.value() == 42 { 0 } else { 1 }
}
