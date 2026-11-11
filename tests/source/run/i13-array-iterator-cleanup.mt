// profiles: debug release
import core.iter.{BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator, OwnedIterable}
import core.panic.panic
import std.panic.{catch_panic, CatchResult}

type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
copy type Counts { a: i32; b: i32; c: i32; d: i32 }
type DropBomb {
    log: ptr<mut i32>
    fail: bool
    drop {
        unsafe { *self.log += 1 }
        if self.fail { panic("array iterator drop stop") }
    }
}
static mut EMPTY_DROPS: usize = 0usize
type Empty { drop { unsafe { EMPTY_DROPS += 1usize } } }

fn exhausted<I: FusedIterator>(mut items: I): bool {
    items.next().is_none() && items.next().is_none()
}

fn main(): i32 {
    var counts = Counts(0, 0, 0, 0)
    {
        var items = [
            Guard(mut counts.a), Guard(mut counts.b),
            Guard(mut counts.c), Guard(mut counts.d)
        ].into_iter()
        assert(items.len() == 4usize, "owned array exact length")
        match take items.next() { present(item) => {}, none => { return 1 } }
        var moved = items
        match take moved.next_back() { present(item) => {}, none => { return 2 } }
        assert(moved.len() == 2usize && moved.size_hint() == (2usize, present(2usize)), "moved iterator retains common bounds")
    }
    assert(counts.a == 1 && counts.b == 1 && counts.c == 1 && counts.d == 1, "drop partially consumed moved array once")
    var short = [7i32, 9i32].into_iter()
    assert(short.next() == present(7) && short.next_back() == present(9), "array ends do not cross")
    assert(short.len() == 0usize && exhausted(mut short) && short.next_back().is_none(), "fused array exhaustion")
    let empty: [i32; 0usize] = []
    var empty_items = empty.into_iter()
    assert(empty_items.len() == 0usize && exhausted(mut empty_items) && empty_items.next_back().is_none(), "zero-length owned array")
    {
        var items = [Empty(), Empty(), Empty()].into_iter()
        match take items.next() { present(item) => {}, none => { return 3 } }
        match take items.next_back() { present(item) => {}, none => { return 4 } }
        assert(items.len() == 1usize, "zero-sized elements share remaining count")
    }
    assert(unsafe { EMPTY_DROPS } == 3usize, "zero-sized values drop once")
    counts = Counts(0, 0, 0, 0)
    let a = core.ptr.from_mut(counts.a)
    let b = core.ptr.from_mut(counts.b)
    let c = core.ptr.from_mut(counts.c)
    let d = core.ptr.from_mut(counts.d)
    let result = catch_panic(fn(): Unit {
        var items = [DropBomb(a, false), DropBomb(b, true), DropBomb(c, false), DropBomb(d, false)].into_iter()
        match take items.next() { present(item) => {}, none => {} }
        core.mem.`drop`(items)
    })
    match take result {
        CatchResult.Panicked(info) => assert(info.message() == "array iterator drop stop", "preserve destructor panic"),
        CatchResult.Returned(_) => { return 5 }
    }
    assert(counts.a == 1 && counts.b == 1 && counts.c == 1 && counts.d == 1, "panic drops every remaining array element once")
    0
}
