// expect-error: type 6:5 generic argument does not satisfy Thin
fn require_thin<T: unsized + Thin>(): ptr<read T> {
    core.ptr.null<T>()
}
fn main() {
    require_thin<[i32]>()
}
