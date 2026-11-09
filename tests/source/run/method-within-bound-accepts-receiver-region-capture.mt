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
    hub.run(fn(): i32 { anchor.value }) - 1
}
