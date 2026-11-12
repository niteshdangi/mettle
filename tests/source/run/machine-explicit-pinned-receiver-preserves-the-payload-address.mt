
type Payload<T: Copy> {
    value: T; marker: core.marker.PhantomPinned
    fn inspect(receiver take self: pinned mut Self): (T, usize) {
        (self.get_ref().value, core.ptr.from_ref(self.get_ref()).addr())
    }
}
fn main() {
    var handle = core.pin.pin(Payload(42,core.marker.PhantomPinned))
    let address = core.ptr.from_ref(handle.as_ref().get_ref()).addr()
    let first = handle.as_mut().inspect()
    let second = handle.as_mut().inspect()
    if first.0 == 42 && second.0 == 42 &&
       first.1 == address && second.1 == address { 0 } else { 1 }
}
