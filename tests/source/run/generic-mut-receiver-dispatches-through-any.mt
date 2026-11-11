module source_helpers;
import core.future.Future
interface Bump { mut fn bump(by: i32): i32; fn get(): i32; }
type N { v: i32 }
extend N implements Bump {
    mut fn bump(by: i32): i32 { self.v += by; self.v }
    fn get(): i32 { self.v }
}
fn twice<T: unsized + Bump>(mut x: T): i32 { x.bump(1); x.bump(2) }
async fn read_value(read v: i32): i32 { v + 1 }
async fn outer<region r>(read v: i32 from r): i32 {
    let f: pinned heap any Future<Output = i32> from r = pinned heap read_value(v)
    await f
}
fn drive<F: Future>(take future: F): F.Output {
    source_helpers.drive!(future)
}
fn main(): i32 {
    var n = N(1)
    let e: mut any Bump = mut n
    if twice(e) != 4 { return 1 }
    var h: heap any Bump = heap N(10)
    if twice(h.get_mut()) != 13 { return 2 }
    let x = 41
    if drive(outer(read x)) != 42 { return 3 }
    0
}
