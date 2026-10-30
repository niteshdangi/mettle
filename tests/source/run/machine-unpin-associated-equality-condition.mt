
interface Family { type Item; }
type Source {}
impl Source implements Family { type Item = i32; }
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Family> Wrapper<T> implements Unpin where <T implements Family>::Item = i32 {}
fn access<T: Family>(value: mut Wrapper<T>): mut Wrapper<T> from value where <T implements Family>::Item = i32 {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(Source(),core::marker::PhantomPinned)
    let result = access(value)
    0
}
