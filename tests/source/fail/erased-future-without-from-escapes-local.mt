// expect-error: region 5:44 erased owner payload borrow
import core.future.Future
type Fixed { base: i32; drop {} }
extend Fixed { async fn total(n: i32): i32 { self.base + n } }
fn escape(): heap any Future<Output = i32> {
    let f = Fixed(1)
    heap f.total(2)
}
fn main(): i32 { 0 }
