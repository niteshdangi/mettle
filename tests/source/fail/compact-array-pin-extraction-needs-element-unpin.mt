// expect-error: type 3:5 invalid primitive operation or operand types
fn expose(mut value: pinned mut [core.marker.PhantomPinned; 65]): mut [core.marker.PhantomPinned; 65] from value {
    value.get_mut()
}
fn main() { 0 }
