// FusedIterator markers, adapter Clone and Default, and adapter Debug text.
import core.clone.Clone
import core.default.Default
import core.fmt.{Debug, Error, buffer_writer, formatter, spec, written_text}
import core.iter
import core.iter.BidirectionalIterator
import core.iter.FusedIterator
import core.iter.Iterator

fn fresh<T: Default>(): T { T.(Default).default() }

// Compiles only for iterators that carry the FusedIterator marker.
fn exhaust<I: FusedIterator>(items: take I): bool {
    var source = items
    while true {
        match take source.next() { present(_) => {}, none => { break } }
    }
    match take source.next() { present(_) => false, none => true }
}

fn render<T: Debug>(value: read T, buffer: mut [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}

fn run(): i32 throws Error {
    // Marker coverage: source iterators and adapters over fused sources.
    if !exhaust(iter.range(0, 3)) { return 1 }
    if !exhaust(iter.range(0, 3).enumerate()) { return 2 }
    if !exhaust(iter.range(0, 5).step_by(2usize)) { return 3 }
    if !exhaust(iter.range(0, 5).skip(2usize).take_n(2usize)) { return 4 }
    if !exhaust(iter.range(0, 3).zip(iter.range(5, 9))) { return 5 }
    if !exhaust(iter.range(0, 3).chain(iter.range(7, 9))) { return 6 }
    if !exhaust(iter.range(0, 3).rev()) { return 7 }
    if !exhaust(iter.once(1)) { return 8 }
    if !exhaust(iter.empty<i32>()) { return 9 }
    if !exhaust(iter.range(0, 6).map(fn(x: take i32): i32 { x + 1 })) { return 10 }
    if !exhaust(iter.range(0, 6).filter(fn(x: read i32): bool { x % 2 == 0 })) { return 11 }
    if !exhaust(iter.range(0, 6).peekable()) { return 12 }
    let numbers = [1, 2, 3]
    if !exhaust(numbers.iter()) { return 13 }

    // A fused adapter never polls a source that already ended.
    var fused = iter.from_fn(fn(): i32? { none }).fuse()
    match take fused.next() { present(_) => { return 14 }, none => {} }

    // Clone duplicates the cursor: advancing one copy leaves the other alone.
    var base = iter.range(10, 14).enumerate()
    match take base.next() { present(_) => {}, none => { return 15 } }
    var copy = base.clone()
    match take base.next() {
        present(pair) => { if pair.0 != 1usize || pair.1 != 11 { return 16 } },
        none => { return 16 }
    }
    match take copy.next() {
        present(pair) => { if pair.0 != 1usize || pair.1 != 11 { return 17 } },
        none => { return 17 }
    }
    var limited = iter.range(0, 9).skip(1usize).step_by(2usize).take_n(3usize)
    var limited_copy = limited.clone()
    if limited.count() != 3usize { return 18 }
    match take limited_copy.next_back() {
        present(value) => { if value != 5 { return 19 } },
        none => { return 19 }
    }
    var chained = iter.range(0, 2).chain(iter.range(5, 7))
    match take chained.next() { present(_) => {}, none => { return 20 } }
    var chained_copy = chained.clone()
    if chained.count() != 3usize || chained_copy.count() != 3usize { return 21 }
    var zipped = iter.range(0, 3).zip(iter.range(4, 9))
    var zipped_copy = zipped.clone()
    if zipped.count() != 3usize || zipped_copy.count() != 3usize { return 22 }

    // Default adapters wrap default sources and start unconsumed.
    var default_enumerated = fresh<iter.Enumerated<iter.Range<i32>>>()
    match take default_enumerated.next() { present(_) => { return 23 }, none => {} }
    var default_empty = fresh<iter.Empty<i32>>()
    match take default_empty.next() { present(_) => { return 24 }, none => {} }
    var default_chain = fresh<iter.Chained<iter.Range<i32>, iter.Range<i32>>>()
    match take default_chain.next() { present(_) => { return 25 }, none => {} }
    var default_limit = fresh<iter.Limited<iter.Range<i32>>>()
    match take default_limit.next() { present(_) => { return 26 }, none => {} }
    var default_skip = fresh<iter.Skipped<iter.Range<i32>>>()
    match take default_skip.next() { present(_) => { return 27 }, none => {} }
    var default_zip = fresh<iter.Zipped<iter.Range<i32>, iter.Range<i32>>>()
    match take default_zip.next() { present(_) => { return 28 }, none => {} }

    // Debug names the adapter and prints the wrapped iterator.
    var buffer = [0u8; 128]
    let enumerated = iter.range(0, 3).enumerate()
    let n = try render(read enumerated, mut buffer)
    match written_text(read buffer, n) {
        present(text) => { if text != "Enumerated { iter: 0..3, count: 0 }" { return 30 } },
        none => { return 30 }
    }
    let limit = iter.range(0, 9).take_n(4usize)
    let m = try render(read limit, mut buffer)
    match written_text(read buffer, m) {
        present(text) => { if text != "Limited { iter: 0..9, remaining: 4 }" { return 31 } },
        none => { return 31 }
    }
    let inclusive = iter.range_inclusive(1, 4)
    let k = try render(read inclusive, mut buffer)
    match written_text(read buffer, k) {
        present(text) => { if text != "1..=4" { return 32 } },
        none => { return 32 }
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(e) => 99 }
}
