// expect-error: ownership 16:5 access or storage lifetime conflicts with a live read loan
pub interface Within<region r> {}
extend<region r, F> F implements Within<region r> {}
type Anchor { value: i32 }
type Hub<region s> { anchor: read Anchor from s }
extend<region s> Hub<region s> {
    fn run<F: fn(): i32 + Within<region s>>(receiver read self: Hub<region s> from s, take f: F): i32 { f() }
}
fn main(): i32 {
    let anchor = Anchor(1)
    let hub = Hub(read anchor)
    var result: i32 = 0
    {
        let inner = Anchor(2)
        result = hub.run(fn(): i32 { inner.value })
    }
    result + hub.anchor.value
}
