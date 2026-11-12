// profiles: debug release
// expect-error: type 13:18 unsatisfied interface obligation
// expect-error-count: 1
import core.pin
import core.ops.{Deref, DerefMut}
type Immovable { marker: core.marker.PhantomPinned }
fn writable<T: DerefMut>(mut value: T): mut T.(Deref).Target from value {
    value.deref_mut()
}
fn main(): i32 {
    var value = Immovable(core.marker.PhantomPinned)
    var view = unsafe { core.pin.Pin.new_unchecked(mut value) }
    let target = writable(mut view)
    0
}
