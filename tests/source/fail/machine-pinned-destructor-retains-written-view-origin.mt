// expect-error: ownership 14:5 access or storage conflicts with a live read loan

type Slot<region r> { value: read i32 from r }
type Writer<region a,region b> {
    @pinned marker: core.marker.PhantomPinned
    destination: mut Slot<region b> from a; value: read i32 from b
    drop { self.project_destination().value = self.get_ref().value }
}
fn main() {
    let first = 1
    var second = 42
    var slot = Slot(read first)
    { let handle = core.pin.pin(Writer(core.marker.PhantomPinned,mut slot,read second)) }
    second = 0
    *slot.value
}
