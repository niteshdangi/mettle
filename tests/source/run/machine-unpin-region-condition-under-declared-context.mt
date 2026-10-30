
interface Ready<region r> {}
extend<region r> i32 implements Ready<region r> where region r: static {}
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Ready<region static>> Wrapper<T> implements Unpin {}
fn access<region r, T: Ready<region r>>(value: mut Wrapper<T>): mut Wrapper<T> from value where region r: static {
    var handle = core.pin.Pin.new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core.marker.PhantomPinned)
    access<region static,i32>(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
