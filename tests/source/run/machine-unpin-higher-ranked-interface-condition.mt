
interface Ready<region r> {}
impl<region r> i32 implements Ready<region r> {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: for<region r> Ready<region r>> Wrapper<T> implements Unpin {}
fn access<T: for<region r> Ready<region r>>(value: mut Wrapper<T>): mut Wrapper<T> from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core::marker::PhantomPinned)
    access(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
