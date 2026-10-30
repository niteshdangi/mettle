// expect-error: type 11:5 Unpin

type Blocked { value: i32 }
impl Blocked not Unpin;
type Parent<T> {
    value: T
    fn demand(): Unit where T: Unpin {}
}
fn main() {
    let parent = Parent(Blocked(0))
    parent.demand()
    0
}
