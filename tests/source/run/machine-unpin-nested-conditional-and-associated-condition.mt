
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = i32; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family<Item=i32>> Wrapper<T> implements Unpin {}
type Outer<T> { nested: Wrapper<T> }
fn access<T: Family<Item=i32>>(value: mut Outer<T>): mut Outer<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Outer(Wrapper(Source(),core::marker::PhantomPinned))
    let result = access(value)
    var handle = core::pin::Pin::new(mut value)
    let inner = handle.get_mut()
    0
}
