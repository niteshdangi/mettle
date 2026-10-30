// A pinned receiver implements an interface for a region-parameterized type,
// and a closure in that impl inherits the impl region without redeclaring it.
import core::future::Poll;
interface G { type Output; fn poll(receiver self: take pinned mut Self, x: i32): Poll<Self::Output>; }
type Borrowed<region r> { value: read i32 from r }
fn apply<F: fn(i32): i32>(f: take F): i32 { f(1) }
impl<region r> Borrowed<region r> implements G {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, x: i32): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        let base = *me.value
        Poll::Ready(apply(fn(y: i32): i32 { base + x + y }))
    }
}
fn main(): i32 {
    let seed = 40
    var borrowed = Borrowed(read seed)
    var handle = core::pin::Pin::new(mut borrowed)
    match take handle.as_mut().poll(1) {
        Poll::Ready(value) => { if value == 42 { 0 } else { 1 } },
        Poll::Pending => 2
    }
}
