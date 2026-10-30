
type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>, v: read i32 from a) {
    h.put(read v)
}
fn main() {
    var x = 1
    let y = 2
    var h = Holder(item: present(read x))
    fill(mut h, read y)
    match h.item { present(v) => *v - 2, none => 1 }
}
