// profiles: debug release

import core.clone.Clone
import core.fmt.{Debug, Error as FmtError, Formatter, Write, formatter, spec}
import core.iter
import core.iter.Iterator
import core.text.Text

type Counter { count: usize }
extend Counter implements Write {
    mut fn write_str(read text: Text): Unit throws FmtError {
        self.count += text.as_bytes().len()
    }
}

type EmptyRefs<region r> {}
extend<region r> EmptyRefs<region r> implements Iterator {
    type Item = read i32 from r
    mut fn next(): (read i32 from r)? { none }
}
extend<region r> EmptyRefs<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("EmptyRefs") }
}

fn debug_len<T: Debug>(read value: T): usize throws FmtError {
    var sink = Counter(0usize)
    {
        var f = formatter(mut sink, spec())
        try T.(Debug).fmt(value, mut f)
    }
    sink.count
}

fn emits<T: Debug>(read value: T): bool {
    let result = capture debug_len(value)
    match take result {
        success(length) => length > 0usize,
        failure(_) => false
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
    if !emits(read base) { return 1 }
    if !emits(read base.clone().map(fn(take value: i32): i32 { value + 1 })) { return 2 }
    if !emits(read base.clone().filter(fn(read value: i32): bool { value > 1 })) { return 3 }
    if !emits(read base.clone().enumerate()) { return 4 }
    if !emits(read base.clone().zip(iter.range(4i32, 8i32))) { return 5 }
    if !emits(read base.clone().chain(iter.range(4i32, 8i32))) { return 6 }
    if !emits(read base.clone().take_n(2usize)) { return 7 }
    if !emits(read base.clone().skip(2usize)) { return 8 }
    if !emits(read base.clone().step_by(2usize)) { return 9 }
    if !emits(read base.clone().take_while(fn(read value: i32): bool { value < 3 })) { return 10 }
    if !emits(read base.clone().skip_while(fn(read value: i32): bool { value < 2 })) { return 11 }
    if !emits(read base.clone().peekable()) { return 12 }
    if !emits(read base.clone().rev()) { return 13 }
    let flattened = base.clone().map(fn(take value: i32): iter.Range<i32> { iter.range(0i32, value) }).flatten()
    if !emits(read flattened) { return 14 }
    let anchor = 0i32
    if !emits(read cloned_empty(read anchor)) { return 15 }
    if !emits(read copied_empty(read anchor)) { return 16 }
    let flat_mapped = base.clone().flat_map(fn(take value: i32): iter.Range<i32> { iter.range(0i32, value) })
    if !emits(read flat_mapped) { return 17 }
    if !emits(read iter.range_inclusive(0i32, 4i32)) { return 18 }
    0
}
