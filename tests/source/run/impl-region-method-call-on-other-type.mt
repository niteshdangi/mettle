type Counter { n: i32 }
impl Counter {
    mut fn bump(): Unit { self.n += 1 }
}
pub interface Within<region r> {}
impl<region r, F> F implements Within<region r> {}
type Hub<region s> { counter: read Counter from s; total: i32 }
impl<region s> Hub<region s> {
    fn peek(receiver self: read Hub<region s> from s): i32 { self.counter.n + self.total }
    fn run<F: fn(): i32 + Within<region s>>(receiver self: read Hub<region s> from s, f: take F): i32 {
        let local = Counter(1)
        let a = self.peek()
        a + local.n + f()
    }
}
fn main(): i32 {
    let c = Counter(2)
    let hub = Hub(read c, 3)
    hub.run(fn(): i32 { 4 }) - 11
}
