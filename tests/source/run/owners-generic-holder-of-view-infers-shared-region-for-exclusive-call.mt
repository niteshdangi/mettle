
type Holder<T> { item: T? }
extend<T> Holder<T> {
    mut fn put(take value: T) { self.item = present(value) }
}
fn fill<region a>(mut h: Holder<read i32 from a>, read v: i32 from a) {
    h.put(read v)
}
fn main() {
    var x = 1
    let y = 2
    var h = Holder(item: present(read x))
    fill(mut h, read y)
    match h.item { present(v) => *v - 2, none => 1 }
}
