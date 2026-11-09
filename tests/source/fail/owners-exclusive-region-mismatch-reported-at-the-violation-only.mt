// expect-error: region 9:5 invariant payload does not satisfy

type Holder<T> { item: T? }
extend<T> Holder<T> {
    mut fn put(take value: T) { self.item = present(value) }
}
fn fill<region a>(mut h: Holder<read i32 from a>) {
    let loc = 5
    h.put(read loc)
}
fn main() { var x = 1; var h = Holder(item: present(read x)); fill(mut h); 0 }
