// profiles: debug release
import core.pin

type Immovable {
    value: i32
    marker: core.marker.PhantomPinned
}

static SHARED: Immovable = Immovable(17i32, core.marker.PhantomPinned)
static mut EXCLUSIVE: Immovable = Immovable(19i32, core.marker.PhantomPinned)

fn main(): i32 {
    let shared = core.pin.Pin.static_ref(read SHARED)
    if shared.get_ref().value != 17i32 { return 1 }
    if core.ptr.from_ref(shared.get_ref()) != core.ptr.from_ref(read SHARED) {
        return 2
    }
    {
        var exclusive = unsafe { core.pin.Pin.static_mut(mut EXCLUSIVE) }
        let address = core.ptr.from_ref(exclusive.get_ref())
        unsafe { exclusive.get_unchecked_mut().value = 23i32 }
        if exclusive.get_ref().value != 23i32 ||
            core.ptr.from_ref(exclusive.get_ref()) != address { return 3 }
    }
    if unsafe { EXCLUSIVE.value } != 23i32 { return 4 }
    var ordinary = 29i32
    {
        var checked = core.pin.Pin.new(mut ordinary)
        *checked.get_mut() = 31i32
    }
    if ordinary != 31i32 { return 5 }
    var immovable = Immovable(37i32, core.marker.PhantomPinned)
    let unchecked = unsafe { core.pin.Pin.new_unchecked(mut immovable) }
    if unchecked.get_ref().value != 37i32 { return 6 }
    0
}
