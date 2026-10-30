// expect-error: region 9:5 invariant payload does not satisfy

type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>) {
    let loc = 5
    h.put(read loc)
}
fn main() { var x = 1; var h = Holder(item: present(read x)); fill(mut h); 0 }
