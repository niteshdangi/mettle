import core.iter
import core.iter.Iterator
import core.iter.BidirectionalIterator

fn evens(read x: i32): bool { x % 2 == 0 }
fn main(): i32 {
    let pulls = core.cell.Cell.new(0)
    // laziness: building adapters pulls nothing
    var lazy = iter.range(0, 100).map(fn(take x: i32): i32 { pulls.set(pulls.get() + 1); x * 3 }).take_n(5usize)
    if pulls.get() != 0 { return 1 }
    var got = 0
    match take lazy.next() { present(v) => { got = v }, none => { return 2 } }
    if pulls.get() != 1 || got != 0 { return 3 }
    if lazy.count() != 4usize || pulls.get() != 5 { return 4 }
    // short circuit
    var calls = core.cell.Cell.new(0)
    var s = iter.range(0, 10)
    let found = s.any(fn(take x: i32): bool { calls.set(calls.get() + 1); x == 3 })
    if !found || calls.get() != 4 { return 5 }
    match take s.next() { present(v) => { if v != 4 { return 6 } }, none => { return 6 } }
    var s2 = iter.range(0, 10)
    if s2.all(fn(take x: i32): bool { x < 2 }) { return 7 }
    match take s2.next() { present(v) => { if v != 3 { return 8 } }, none => { return 8 } }
    var s3 = iter.range(5, 10)
    match take s3.find(fn(read x: i32): bool { x % 4 == 0 }) { present(v) => { if v != 8 { return 9 } }, none => { return 9 } }
    var s4 = iter.range(5, 10)
    match take s4.position(fn(take x: i32): bool { x == 7 }) { present(v) => { if v != 2usize { return 10 } }, none => { return 10 } }
    // empty
    var e = iter.empty<i32>()
    if e.count() != 0usize { return 11 }
    if iter.sum(iter.empty<i32>()) != 0 || iter.product(iter.empty<i32>()) != 1 { return 12 }
    if iter.max(iter.empty<i32>()).is_present() { return 13 }
    if iter.sum(iter.range_inclusive(1, 10)) != 55 || iter.product(iter.range_inclusive(1u64, 10u64)) != 3628800u64 { return 14 }
    if iter.max(iter.range(0, 5).map(fn(take x: i32): i32 { (x * 7) % 5 })).unwrap() != 4 { return 15 }
    if iter.min(iter.range(3, 5)).unwrap() != 3 { return 16 }
    // adapters
    if iter.range(0, 10).filter(evens).fold(0, fn(take a: i32, take x: i32): i32 { a + x }) != 20 { return 17 }
    var z = iter.range(0, 3).zip(iter.range(10, 20))
    if z.count() != 3usize { return 18 }
    var en = iter.range(7, 9).enumerate()
    match take en.next() { present(p) => { if p.0 != 0usize || p.1 != 7 { return 19 } }, none => { return 19 } }
    let ch = iter.range(0, 3).chain(iter.range(10, 12)).count()
    if ch != 5usize { return 20 }
    if iter.sum(iter.range(0, 10).skip(7usize)) != 24 { return 21 }
    if iter.sum(iter.range(0, 10).step_by(3usize)) != 18 { return 22 }
    if iter.sum(iter.range(0, 10).take_while(fn(read x: i32): bool { x < 4 })) != 6 { return 23 }
    if iter.sum(iter.range(0, 10).skip_while(fn(read x: i32): bool { x < 8 })) != 17 { return 24 }
    if iter.sum(iter.range(0, 5).rev().take_n(2usize)) != 7 { return 25 }
    if iter.sum(iter.range_inclusive(1i128, 3i128)) != 6i128 ||
       iter.product(iter.range_inclusive(1u128, 3u128)) != 6u128 { return 34 }
    if iter.sum(iter.once(1.5f32).chain(iter.once(2.5f32))) != 4.0f32 ||
       iter.product(iter.once(2.0f64).chain(iter.once(3.0f64))) != 6.0f64 { return 35 }
    var pk = iter.range(0, 3).peekable()
    match take pk.peek() { present(v) => { if *v != 0 { return 26 } }, none => { return 26 } }
    match take pk.next() { present(v) => { if v != 0 { return 27 } }, none => { return 27 } }
    match take pk.next() { present(v) => { if v != 1 { return 28 } }, none => { return 28 } }
    if iter.range(0, 3).last().unwrap() != 2 || iter.range(0, 3).nth(1usize).unwrap() != 1 || iter.range(0, 3).nth(3usize).is_present() { return 29 }
    var once = iter.once(5)
    if once.count() != 1usize { return 30 }
    var n = 0
    for x in iter.range(0, 4) { n += x }
    for x in iter.range(0, 4).map(fn(take x: i32): i32 { x * 2 }) { n += x }
    if n != 18 { return 31 }
    var gen = iter.from_fn(fn(): i32? { let v = calls.get(); if v < 6 { calls.set(v + 1); present(v) } else { none } })
    if gen.count() != 2usize { return 32 }
    if iter.range_inclusive(250u8, 255u8).count() != 6usize { return 33 }
    0
}
