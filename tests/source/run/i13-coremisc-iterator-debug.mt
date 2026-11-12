// profiles: debug release

import core.clone.Clone
import core.fmt
import core.fmt.{Debug, Error as FmtError, Formatter, formatter, spec}
import core.iter
import core.iter.Iterator
import core.text.Text

type EmptyRefs<region r> {}
extend<region r> EmptyRefs<region r> implements Iterator {
    type Item = read i32 from r
    mut fn next(): (read i32 from r)? { none }
}
extend<region r> EmptyRefs<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("EmptyRefs") }
}

fn emits<T: Debug>(read value: T, read expected: Text): bool {
    var storage = [0u8; 256]
    var sink = fmt.buffer_writer(mut storage)
    {
        var f = formatter(mut sink, spec())
        match capture T.(Debug).fmt(value, mut f) {
            success(_) => {},
            failure(_) => { return false }
        }
    }
    match fmt.written_text(read storage, sink.len()) {
        present(actual) => actual == expected,
        none => false
    }
}

fn cloned_empty<region r>(read anchor: i32 from r): iter.Cloned<region r, i32, EmptyRefs<region r>> {
    let _ = anchor
    EmptyRefs().cloned()
}

fn copied_empty<region r>(read anchor: i32 from r): iter.Copied<region r, i32, EmptyRefs<region r>> {
    let _ = anchor
    EmptyRefs().copied()
}

fn main(): i32 {
    let base = iter.range(0i32, 4i32)
    if !emits(read base, "Range { start: 0, end: 4 }") { return 1 }
    if !emits(read base.clone().map(fn(take value: i32): i32 { value + 1 }),
        "Mapped { iter: Range { start: 0, end: 4 } }") { return 2 }
    if !emits(read base.clone().filter(fn(read value: i32): bool { value > 1 }),
        "Filtered { iter: Range { start: 0, end: 4 } }") { return 3 }
    if !emits(read base.clone().enumerate(),
        "Enumerated { iter: Range { start: 0, end: 4 }, index: 0 }") { return 4 }
    if !emits(read base.clone().zip(iter.range(4i32, 8i32)),
        "Zipped { first: Range { start: 0, end: 4 }, second: Range { start: 4, end: 8 } }") { return 5 }
    if !emits(read base.clone().chain(iter.range(4i32, 8i32)),
        "Chained { first: Range { start: 0, end: 4 }, second: present(Range { start: 4, end: 8 }), first_live: true }") { return 6 }
    if !emits(read base.clone().take_n(2usize),
        "Limited { iter: Range { start: 0, end: 4 }, remaining: 2 }") { return 7 }
    if !emits(read base.clone().skip(2usize),
        "Skipped { iter: Range { start: 0, end: 4 }, pending: 2 }") { return 8 }
    if !emits(read base.clone().step_by(2usize),
        "Stepped { iter: Range { start: 0, end: 4 }, step: 2, first: true }") { return 9 }
    if !emits(read base.clone().take_while(fn(read value: i32): bool { value < 3 }),
        "TakenWhile { iter: Range { start: 0, end: 4 }, done: false }") { return 10 }
    if !emits(read base.clone().skip_while(fn(read value: i32): bool { value < 2 }),
        "SkippedWhile { iter: Range { start: 0, end: 4 }, started: false }") { return 11 }
    if !emits(read base.clone().peekable(),
        "Peekable { iter: Range { start: 0, end: 4 }, slot: none, filled: false }") { return 12 }
    if !emits(read base.clone().rev(),
        "Reversed { iter: Range { start: 0, end: 4 } }") { return 13 }
    let flattened = base.clone().map(fn(take value: i32): iter.Range<i32> { iter.range(0i32, value) }).flatten()
    if !emits(read flattened,
        "Flatten { outer: Mapped { iter: Range { start: 0, end: 4 } }, front: none, back: none, outer_done: false }") { return 14 }
    let anchor = 0i32
    if !emits(read cloned_empty(read anchor), "Cloned { iter: EmptyRefs }") { return 15 }
    if !emits(read copied_empty(read anchor), "Copied { iter: EmptyRefs }") { return 16 }
    let flat_mapped = base.clone().flat_map(fn(take value: i32): iter.Range<i32> { iter.range(0i32, value) })
    if !emits(read flat_mapped,
        "FlatMapped { outer: Range { start: 0, end: 4 }, front: none, back: none, outer_done: false }") { return 17 }
    if !emits(read iter.range_inclusive(0i32, 4i32),
        "RangeInclusive { start: 0, end: 4, done: false }") { return 18 }
    0
}
