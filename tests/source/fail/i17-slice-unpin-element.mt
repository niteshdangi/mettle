// expect-error: type 6:5 generic argument does not satisfy Unpin

fn require_unpin<T: unsized + Unpin>(): Unit {}

fn main(): i32 {
    require_unpin<[core.marker.PhantomPinned]>()
    0
}
