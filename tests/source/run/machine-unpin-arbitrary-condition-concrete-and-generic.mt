
interface Ready {}
impl i32 implements Ready {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready> Wrapper<T> implements Unpin {}
fn access<T: Ready>(value: mut Wrapper<T>): mut Wrapper<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn require_unpin<T: Unpin>(value: read T) {}
fn main() {
    var value = Wrapper(40,core::marker::PhantomPinned)
    access(value).value += 2
    require_unpin(value)
    var handle = core::pin::pin(value)
    if handle.get_mut().value == 42 { 0 } else { 1 }
}
