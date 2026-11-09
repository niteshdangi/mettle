
interface Ready {}
type AddressSensitive { marker: core.marker.PhantomPinned }
extend AddressSensitive implements Ready {}
fn make(): some Ready { AddressSensitive(core.marker.PhantomPinned) }
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Ready> Wrapper<T> implements Unpin {}
fn access<T: Ready>(mut value: Wrapper<T>): mut Wrapper<T> from value {
    var handle = core.pin.Pin.new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(make(),core.marker.PhantomPinned)
    let first = access(value)
    var handle = core.pin.Pin.new(mut value)
    let second = handle.get_mut()
    0
}
