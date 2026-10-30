// expect-error: ownership 7:5 live exclusive loan

type Holder<F: mut fn(): Unit> { f: F }
fn main(): i32 {
    var v = 1
    var h = Holder(fn(): Unit { v += 1 })
    v = 5
    h.f()
    v
}
