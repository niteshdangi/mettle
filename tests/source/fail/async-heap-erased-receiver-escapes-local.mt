// expect-error: ownership 13:5 returned view escapes local storage
import core.future.Future
interface Source {
    async(heap) fn total(n: i32): i32
}
type Fixed { base: i32; drop {} }
extend Fixed implements Source {
    async fn total(n: i32): i32 { self.base + n }
}
fn escape(): pinned heap any Future<Output = i32> {
    let f = Fixed(1)
    let s: read any Source = read f
    s.total(2)
}
fn main(): i32 { 0 }
