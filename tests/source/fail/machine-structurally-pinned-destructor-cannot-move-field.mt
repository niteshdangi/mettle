// expect-error-count: 1
// expect-error: ownership 7:24 cannot move out of a viewed place

type Child { value: i32; marker: core.marker.PhantomPinned }
type Parent {
    @pinned child: Child
    drop { let moved = self.get_ref().child }
}
fn main() { 0 }
