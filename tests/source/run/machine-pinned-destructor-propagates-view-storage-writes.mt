
type Slot<region r> { value: read i32 from r }
type Writer<region a,region b> {
    @pinned marker: core.marker.PhantomPinned
    destination: mut Slot<region b> from a; value: read i32 from b
    drop { self.project_destination().value = self.get_ref().value }
}
fn main() {
    let first = 1
    let second = 42
    var slot = Slot(read first)
    { let handle = core.pin.pin(Writer(core.marker.PhantomPinned,mut slot,read second)) }
    if *slot.value == 42 { 0 } else { 1 }
}
