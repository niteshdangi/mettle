// flags: --sanitize address

type Child {
    original: usize; counter: ptr<mut i32>; marker: core.marker.PhantomPinned
    drop {
        let address = core.ptr.from_ref(self).addr()
        if address == self.original { unsafe { *self.counter += 1 } }
    }
}
type Parent<T: Copy> {
    @pinned child: Child
    spare: T; counter: ptr<mut i32>
    drop {
        let child = self.project_child()
        let address = core.ptr.from_ref(child.get_ref()).addr()
        if address == child.get_ref().original {
            unsafe { *self.get_ref().counter += 10 }
        }
    }
}
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    {
        var handle = core.pin.pin(
            Parent(Child(0usize,counter,core.marker.PhantomPinned),31,counter))
        {
            var child = handle.project_child()
            let address = core.ptr.from_ref(child.get_ref()).addr()
            unsafe { child.get_unchecked_mut().original = address }
        }
        let spare = handle.project_spare()
        *spare += 1
    }
    if count == 11 { 0 } else { 1 }
}
