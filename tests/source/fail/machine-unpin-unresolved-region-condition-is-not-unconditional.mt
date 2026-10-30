// expect-error: type 7:18 unsatisfied Unpin condition

interface Ready<region r> {}
type Wrapper<T> { value: T; marker: core::marker::PhantomPinned }
unsafe impl<T: Ready<region static>> Wrapper<T> implements Unpin {}
fn wrong<region r, T: Ready<region r>>(value: mut Wrapper<T>) {
    let handle = core::pin::Pin::new(mut value)
}
fn main() { 0 }
