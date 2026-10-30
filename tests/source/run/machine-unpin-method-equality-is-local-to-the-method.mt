
type Blocked { value: i32 }
extend Blocked not Unpin
type Parent<T> {
    value: T
    fn access<U: Unpin>(value: mut T): mut T from value where T = U {
        var handle = core.pin.Pin.new(mut value)
        handle.into_inner()
    }
}
fn main() {
    let parent = Parent(0)
    var value = 41
    *parent.access<i32>(value) += 1
    let unrelated = Parent(Blocked(0))
    if value == 42 { 0 } else { 1 }
}
