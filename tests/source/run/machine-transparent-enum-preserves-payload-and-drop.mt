
type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}
@layout(transparent)
enum Wrapped { Value(Counted,Unit) }
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    { let value = Wrapped.Value(Counted(counter),()) }
    if count == 1 && core.mem.size_of<Wrapped>() ==
                       core.mem.size_of<Counted>() { 0 } else { 1 }
}
