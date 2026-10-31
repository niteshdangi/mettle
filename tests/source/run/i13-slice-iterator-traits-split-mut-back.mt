// Exclusive splitting from the back, FusedIterator on slice iterators,
// Clone, Default and Debug of slice iterators.
import core.clone.Clone
import core.default.Default
import core.fmt.{Debug, Error, buffer_writer, formatter, spec, written_text}
import core.iter.BidirectionalIterator
import core.iter.FusedIterator
import core.iter.Iterator
import core.iter.ExactSizeIterator

fn fresh<T: Default>(): T { T.(Default).default() }

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
    // split_mut from both ends meets in the middle: [1] 0 [2, 3] 0 [4].
    var data = [1, 0, 2, 3, 0, 4]
    {
        let slice = mut data
        var parts = slice.split_mut(fn(value: read i32): bool { value == 0 })
        match take parts.next_back() {
            present(part) => {
                if part.len() != 1usize || part[0usize] != 4 { return 1 }
                part[0usize] = 40
            },
            none => { return 1 }
        }
        match take parts.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 1 { return 2 } },
            none => { return 2 }
        }
        match take parts.next_back() {
            present(part) => {
                if part.len() != 2usize || part[0usize] != 2 || part[1usize] != 3 { return 3 }
                part[1usize] = 30
            },
            none => { return 3 }
        }
        match take parts.next() { present(_) => { return 4 }, none => {} }
        match take parts.next_back() { present(_) => { return 4 }, none => {} }
    }
    if data[3usize] != 30 || data[5usize] != 40 { return 5 }

    // Inclusive exclusive-splitting yields the delimiter with the piece before it.
    var inclusive = [1, 0, 2, 0, 3]
    {
        let slice = mut inclusive
        var parts = slice.split_inclusive_mut(fn(value: read i32): bool { value == 0 })
        match take parts.next_back() {
            present(part) => { if part.len() != 1usize || part[0usize] != 3 { return 6 } },
            none => { return 6 }
        }
        match take parts.next_back() {
            present(part) => { if part.len() != 2usize || part[0usize] != 2 { return 7 } },
            none => { return 7 }
        }
        match take parts.next() {
            present(part) => { if part.len() != 2usize || part[0usize] != 1 { return 8 } },
            none => { return 8 }
        }
        match take parts.next_back() { present(_) => { return 9 }, none => {} }
    }

    // rev() over rsplit_mut flips the order back to front.
    var reverse = [5, 0, 6]
    {
        let slice = mut reverse
        var parts = slice.rsplit_mut(fn(value: read i32): bool { value == 0 })
        match take parts.next_back() {
            present(part) => { if part.len() != 1usize || part[0usize] != 5 { return 10 } },
            none => { return 10 }
        }
    }

    // Slice iterators carry the FusedIterator marker.
    let numbers = [1, 2, 3, 4]
    if !exhaust(numbers.iter()) { return 11 }
    if !exhaust(numbers.chunks(3usize)) { return 12 }
    if !exhaust(numbers.windows(2usize)) { return 13 }
    if !exhaust(numbers.chunks_exact(3usize)) { return 14 }
    if !exhaust(numbers.rchunks(3usize)) { return 15 }
    if !exhaust(numbers.split(fn(value: read i32): bool { value == 2 })) { return 16 }

    // Clone copies the cursors; the copy resumes where the original stood.
    var iterator = numbers.iter()
    match take iterator.next() { present(_) => {}, none => { return 17 } }
    var copy = iterator.clone()
    if iterator.len() != 3usize || copy.len() != 3usize { return 18 }
    match take iterator.next_back() {
        present(value) => { if value != 4 { return 19 } },
        none => { return 19 }
    }
    if copy.len() != 3usize { return 20 }
    var chunks = numbers.chunks(3usize)
    var chunks_copy = chunks.clone()
    match take chunks.next() { present(_) => {}, none => { return 21 } }
    if chunks.len() != 1usize || chunks_copy.len() != 2usize { return 22 }

    // Default slice iterators are empty.
    var empty = fresh<core.slice.SliceIter<i32>>()
    if empty.len() != 0usize { return 23 }
    match take empty.next() { present(_) => { return 24 }, none => {} }
    var empty_mut = fresh<core.slice.SliceIterMut<i32>>()
    match take empty_mut.next() { present(_) => { return 25 }, none => {} }

    // Debug shows the elements that remain.
    var buffer = [0u8; 64]
    var shown = numbers.iter()
    match take shown.next() { present(_) => {}, none => { return 26 } }
    let n = try render(read shown, mut buffer)
    match written_text(read buffer, n) {
        present(text) => { if text != "SliceIter([2, 3, 4])" { return 27 } },
        none => { return 27 }
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(e) => 99 }
}
