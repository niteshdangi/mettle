// expect-error: ownership 9:5 access or storage lifetime conflicts with a live exclusive loan

type Child { value: i32; marker: core.marker.PhantomPinned }
type Parent { @pinned child: Child; other: i32 }
fn main() {
    var handle = core.pin.pin(Parent(Child(42,core.marker.PhantomPinned),0))
    let child = handle.project_child()
    let parent = unsafe { handle.get_unchecked_mut() }
    child.get_ref().value + parent.other
}
