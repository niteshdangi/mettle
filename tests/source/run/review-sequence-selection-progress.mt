// profiles: debug release
import core.cmp.{Ord, Ordering}
fn main(): i32 {
    var tokens = [0usize; 256]
    var ranks = [usize.MAX; 256]
    var i = 0usize
    while i < 256usize { tokens[i] = i; i += 1usize }
    var low = 0usize
    var rank = 0usize
    while 256usize - low > 2usize {
        let mid = low + (256usize - low) / 2usize
        ranks[tokens[low]] = rank
        ranks[tokens[mid]] = rank + 1usize
        rank += 2usize
        let xs: mut [usize] = mut tokens
        xs.swap(mid, 255usize)
        let pivot = ranks[xs[255usize]]
        var lower = low
        var scan = low
        var greater = 255usize
        while scan < greater {
            let value = ranks[xs[scan]]
            if value < pivot { xs.swap(scan, lower); lower += 1usize; scan += 1usize }
            else if value > pivot { greater -= 1usize; xs.swap(scan, greater) }
            else { scan += 1usize }
        }
        xs.swap(greater, 255usize)
        low = greater + 1usize
    }
    while low < 256usize { ranks[tokens[low]] = rank; rank += 1usize; low += 1usize }
    var comparisons = 0usize
    {
        let xs: mut [usize] = mut ranks
        let selected = xs.select_nth_unstable_by(255usize, fn(read a: usize, read b: usize): Ordering {
            comparisons += 1usize
            a.cmp(b)
        })
        assert(*selected.1 == 255usize, "correct rank")
        var j = 0usize
        while j < selected.0.len() { assert(selected.0[j] <= *selected.1, "prefix partition"); j += 1usize }
    }
    assert(comparisons < 16384usize, "deterministic bad pivots must trigger bounded linear fallback")
    0
}
