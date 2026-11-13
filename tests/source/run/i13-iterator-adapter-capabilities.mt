// profiles: debug release
import core.clone.Clone
import core.default.Default
import core.iter
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator}

fn default_of<T: Default>(): T { T.(Default).default() }
fn exact_len<I: ExactSizeIterator>(read value: I): usize { value.len() }

fn main(): i32 {
    let values = [1i32, 2i32, 3i32]

    var cloned = values.iter().cloned()
    if exact_len(cloned) != 3usize || cloned.next_back() != present(3) || cloned.next() != present(1) { return 1 }
    var copied = values.iter().copied()
    if exact_len(copied) != 3usize || copied.next_back() != present(3) { return 2 }

    var peeked = iter.range(0i32, 4i32).peekable()
    if exact_len(peeked) != 4usize || *peeked.peek().unwrap() != 0 || exact_len(peeked) != 4usize { return 3 }
    if peeked.next_back() != present(3) || exact_len(peeked) != 3usize { return 4 }
    var forked = peeked.clone()
    if forked.next() != present(0) || peeked.next() != present(0) || forked.next() != peeked.next() { return 5 }

    var flat = iter.range(1i32, 4i32).map(fn(take value: i32): iter.Range<i32> { iter.range(0i32, value) }).flatten()
    if flat.next_back() != present(2) || flat.next() != present(0) { return 6 }

    var empty_flat: iter.Flatten<iter.Range<i32>, iter.Empty<iter.Range<i32>>> = default_of()
    if empty_flat.next().is_present() { return 7 }
    var empty_rev: iter.Reversed<iter.Empty<i32>> = default_of()
    if empty_rev.next().is_present() { return 8 }
    var empty_cloned: iter.Cloned<region static, i32, iter.Empty<read i32 from static>> = default_of()
    if empty_cloned.next().is_present() { return 9 }
    var empty_copied: iter.Copied<region static, i32, iter.Empty<read i32 from static>> = default_of()
    if empty_copied.next().is_present() { return 10 }
    0
}
