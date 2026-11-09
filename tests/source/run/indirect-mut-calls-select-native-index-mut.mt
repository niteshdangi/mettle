
module core {
    pub module ops {
        pub interface Index<Key> {
            type Output;
            fn index(take key: Key): read Self.Output;
        }
        pub interface IndexMut<Key> {
            type Output;
            mut fn index_mut(take key: Key): mut Self.Output;
        }
    }
}
type Slot<T> { value: T }
extend<T> Slot<T> implements core.ops.Index<i32> {
    type Output = T
    fn index(take key: i32): read T { read self.value }
}
extend<T> Slot<T> implements core.ops.IndexMut<i32> {
    type Output = T
    mut fn index_mut(take key: i32): mut T { mut self.value }
}
fn increment(mut value: i32): Unit { value += 1 }
fn answer(): i32 { 42 }
fn main(): i32 {
    var number = Slot(41)
    let update: fn(mut i32): Unit = increment
    update(number[0])
    let mutable_pointer: mut fn(): i32 = answer
    var callbacks = Slot(mutable_pointer)
    if callbacks[0]() == 42 && number.value == 42 { 0 } else { 1 }
}
