
type Payload<T: Copy> {
    value: T; marker: core::marker::PhantomPinned
    fn inspect(receiver self: take pinned mut Self): T {
        self.get_ref().value
    }
}
fn main() {
    var handle = core::pin::pin(Payload(42,core::marker::PhantomPinned))
    let first = handle.as_mut().inspect()
    let second = handle.as_mut().inspect()
    if first == 42 && second == 42 { 0 } else { 1 }
}
