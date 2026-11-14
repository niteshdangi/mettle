import alloc.boxed
import alloc.rc
import alloc.string.String
import core.clone.Clone
import core.cmp.Ord
import core.hash
import core.hash.{Hash, Hasher}
import core.fmt
import core.fmt.Display

fn main(): i32 {
    let b0 = boxed.new(41)
    let c = b0.clone()
    if b0 != c { return 1 }
    var b = boxed.new(42)
    if b <= c { return 2 }
    if !b.get().eq(42) { return 3 }
    var h1 = hash.fnv1a()
    var h2 = hash.fnv1a()
    b.hash(mut h1)
    42.hash(mut h2)
    if h1.finish() != h2.finish() { return 4 }
    let r = rc.new(7)
    let r2 = r.clone()
    if r != r2 || !r.get().eq(7) { return 5 }
    var t = alloc.string.new()
    {
        var f = fmt.formatter(mut t, fmt.spec())
        match capture boxed.Heap<i32>.(Display).fmt(b, mut f) { success(u) => {}, failure(e) => { return 6 } }
    }
    if t.as_text() != "42" { return 7 }
    0
}
