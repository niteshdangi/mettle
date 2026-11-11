// profiles: debug release
import core.default.Default
import core.iter
import core.iter.{BidirectionalIterator, Iterator}

fn fresh<T: Default>(): T { T.(Default).default() }

fn default_views<region r>(read anchor: i32 from r): bool {
    let _ = anchor
    var cloned: iter.Cloned<region r, i32, iter.Empty<read i32 from r>> = fresh()
    var copied: iter.Copied<region r, i32, iter.Empty<read i32 from r>> = fresh()
    cloned.next().is_none() && copied.next().is_none()
}

fn main(): i32 {
    let anchor = 0i32
    assert(default_views(read anchor), "borrowed adapter defaults inherit the inner default")
    var reversed: iter.Reversed<iter.Empty<i32>> = fresh()
    assert(reversed.next().is_none() && reversed.next_back().is_none(), "reverse default inherits inner default")
    0
}
