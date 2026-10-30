// A pinned receiver implements an interface for a region-parameterized type,
// and a closure in that extension inherits the extension region. A type recursing
// through a function-pointer field compares equal to itself when viewed by a
// generic callee.
import core.future.Poll
interface G { type Output; fn poll(receiver self: take pinned mut Self, x: i32): Poll<Self.Output>; }
type Borrowed<region r> { value: read i32 from r }
fn apply<F: fn(i32): i32>(f: take F): i32 { f(1) }
extend<region r> Borrowed<region r> implements G {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, x: i32): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        let base = *me.value
        Poll.Ready(apply(fn(y: i32): i32 { base + x + y }))
    }
}
copy type V { clone: fn(ptr<mut u8>): R }
copy type R { data: ptr<mut u8>; v: V }
fn same(data: ptr<mut u8>): R { R(data, V(same)) }
fn gr<T>(w: read R): bool { w.data == core.ptr.null_mut<u8>() }
fn er(slot: ptr<mut u8>): bool { unsafe { gr<i32>(read *slot.cast<R>()) } }
fn main(): i32 {
    var r = same(core.ptr.null_mut<u8>())
    if !er(core.ptr.from_mut(r).cast<u8>()) { return 3 }
    let seed = 40
    var borrowed = Borrowed(read seed)
    var handle = core.pin.Pin.new(mut borrowed)
    match take handle.as_mut().poll(1) {
        Poll.Ready(value) => { if value == 42 { 0 } else { 1 } },
        Poll.Pending => 2
    }
}
