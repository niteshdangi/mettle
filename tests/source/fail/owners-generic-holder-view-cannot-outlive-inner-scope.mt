// expect-error: ownership 14:5 live read loan

type Holder<T> { item: T? }
impl<T> Holder<T> {
    mut fn put(value: take T) { self.item = present(value) }
}
fn fill<region a>(h: mut Holder<read i32 from a>, v: read i32 from a) { h.put(read v) }
fn main(): i32 {
    var x = 1
    var h = Holder(item: present(read x))
    {
        let y = 2
        fill(mut h, read y)
    }
    match h.item { present(v) => *v, none => 0 }
}
