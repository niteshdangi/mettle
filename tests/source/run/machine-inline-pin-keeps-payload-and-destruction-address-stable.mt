
type Stable {
    marker: core.marker.PhantomPinned
    address: ptr<read Stable>
    counter: ptr<mut i32>
    drop {
        let actual = core.ptr.from_ref(self)
        unsafe {
            if self.address == actual { *self.counter += 1 }
            else { *self.counter += 100 }
        }
    }
}
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    {
        var handle = core.pin.pin(Stable(core.marker.PhantomPinned,
                                           core.ptr.null<Stable>(),counter))
        let view = unsafe { handle.as_mut().get_unchecked_mut() }
        view.address = core.ptr.from_ref(view)
        let reference = handle.as_ref().get_ref()
        if reference.address != core.ptr.from_ref(reference) { return 1 }
    }
    if count == 1 { 0 } else { 2 }
}
