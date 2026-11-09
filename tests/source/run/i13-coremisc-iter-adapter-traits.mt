// profiles: debug release
// Evidence for iterator adapter traits: exact size and double-ended iteration
// through skip, take, step_by, rev, enumerate, zip, peekable and chain.

import core.clone.Clone
import core.borrow.ToOwned
import core.iter
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator}

fn checks_exact(): i32 {
    let base = iter.Range(0i32, 6i32)
    if base.clone().enumerate().len() != 6usize { return 1 }
    if base.clone().rev().len() != 6usize || base.clone().skip(2usize).len() != 4usize { return 2 }
    if base.clone().take_n(3usize).len() != 3usize || base.clone().step_by(2usize).len() != 3usize { return 3 }
    if base.clone().zip(iter.Range(10i32, 12i32)).len() != 2usize { return 4 }
    if base.clone().peekable().len() != 6usize { return 5 }
    0
}

fn checks_double_ended(): i32 {
    let base = iter.Range(0i32, 6i32)
    var enumerated = base.clone().enumerate()
    match enumerated.next_back() {
        present((index, value)) => { if index != 5usize || value != 5 { return 10 } },
        none => { return 10 }
    }
    var skipped = base.clone().skip(2usize)
    if skipped.next_back() != present(5) || skipped.next() != present(2) { return 11 }
    var taken = base.clone().take_n(3usize)
    if taken.next_back() != present(2) || taken.len() != 2usize { return 12 }
    if taken.next() != present(0) || taken.next_back() != present(1) { return 13 }
    var stepped = base.clone().step_by(2usize)
    if stepped.next_back() != present(4) || stepped.next() != present(0) { return 14 }
    var chained = base.clone().take_n(2usize).chain(iter.Range(8i32, 10i32))
    if chained.next_back() != present(9) || chained.next() != present(0) { return 15 }
    var peekable = base.clone().peekable()
    if peekable.next_back() != present(5) { return 16 }
    0
}

fn checks_fused(): i32 {
    var finished = iter.Range(0i32, 1i32).chain(iter.Range(1i32, 1i32))
    if finished.next() != present(0) || finished.next().is_present() || finished.next().is_present() { return 30 }
    0
}

fn checks_peekable_clone(): i32 {
    var peekable = iter.Range(0i32, 3i32).peekable()
    if peekable.peek().copied() != present(0) { return 40 }
    var cloned = peekable.clone()
    var owned = peekable.to_owned()
    if cloned.next() != present(0) || owned.next() != present(0) { return 41 }
    0
}

fn main(): i32 {
    let exact_status = checks_exact()
    if exact_status != 0 { return exact_status }
    let double_status = checks_double_ended()
    if double_status != 0 { return double_status }
    let fused_status = checks_fused()
    if fused_status != 0 { return fused_status }
    checks_peekable_clone()
}
