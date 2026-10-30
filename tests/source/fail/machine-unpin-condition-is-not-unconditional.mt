// expect-error: type 9:17 unsatisfied Unpin condition

interface Ready {}
impl i32 implements Ready {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core::pin::pin(Wrapper(false,core::marker::PhantomPinned))
    let wrong = handle.get_mut()
    0
}
