import alloc.boxed
import alloc.string
import core.error.Error
import core.fmt
import core.fmt.Debug
import core.fmt.Display
import core.fmt.Formatter
import core.hash.Hasher
import core.iter.{ BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator, collect, once }
import core.text.Text

type ByteSum { total: u64 }
extend ByteSum implements Hasher {
    mut fn write(read bytes: [u8]): Unit {
        var index = 0usize
        while index < bytes.len() {
            self.total += bytes[index] as u64
            index += 1usize
        }
    }
    fn finish(): u64 { self.total }
}

type LocalError {}
type OuterError { cause: LocalError }
extend LocalError implements Debug {
    fn fmt(mut f: Formatter): Unit throws fmt.Error { try f.write_str("local") }
}
extend LocalError implements Display {
    fn fmt(mut f: Formatter): Unit throws fmt.Error { try f.write_str("local") }
}
extend LocalError implements Error {}
extend OuterError implements Debug {
    fn fmt(mut f: Formatter): Unit throws fmt.Error {
        var builder = try f.debug_struct("OuterError")
        try builder.field("cause", read self.cause)
        try builder.finish()
    }
}
extend OuterError implements Display {
    fn fmt(mut f: Formatter): Unit throws fmt.Error { try f.write_str("outer") }
}
extend OuterError implements Error {
    fn source<region r>(
        receiver read self: OuterError from r
    ): (read any Error from r)? {
        let cause: read any Error = read self.cause
        present(cause)
    }
}

type DropItem {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn check_boxed_iterator<I: Iterator<Item = i32> + BidirectionalIterator + ExactSizeIterator + FusedIterator + unsized>(
    take items: boxed.Box<I>
): bool {
    var values = items
    if values.len() != 4usize { return false }
    match take values.next() {
        present(first) => { if first != 0 { return false } },
        none => { return false }
    }
    match take values.next_back() {
        present(last) => { if last != 3 { return false } },
        none => { return false }
    }
    if values.len() != 2usize { return false }
    match take values.next() {
        present(middle) => { if middle != 1 { return false } },
        none => { return false }
    }
    if values.len() != 1usize { return false }
    match take values.next() {
        present(last) => { if last != 2 { return false } },
        none => { return false }
    }
    match take values.next() { none => {}, present(_) => { return false } }
    match take values.next() { none => true, present(_) => false }
}

fn main(): i32 {
    var hasher = boxed.new(ByteSum(0u64))
    hasher.write_u8(5u8)
    hasher.write_u16(0x0201u16)
    if hasher.finish() != 8u64 { return 1 }

    let error = boxed.new(OuterError(LocalError()))
    if error.source().is_none() { return 2 }

    if !check_boxed_iterator(boxed.new(0i32..4i32)) { return 3 }

    var values: boxed.Box<[i32]> = collect(
        once(1i32).chain(once(2i32)).chain(once(3i32))
    )
    var total = 0i32
    for value in read values { total += *value }
    for value in mut values { *value += 4i32 }
    for value in read values { total += *value }
    if total != 24i32 { return 4 }

    let collected_chars: boxed.Box<Text> = collect(
        once('o').chain(once('k'))
    )
    if collected_chars.get() != "ok" { return 5 }

    let chars = ['r', 'e']
    let borrowed_chars: boxed.Box<Text> = collect(
        once(read chars[0usize]).chain(once(read chars[1usize]))
    )
    if borrowed_chars.get() != "re" { return 6 }

    let collected_parts: boxed.Box<Text> = collect(
        once("box").chain(once("ed"))
    )
    if collected_parts.get() != "boxed" { return 7 }

    let collected_strings: boxed.Box<Text> = collect(
        once(string.from_text("str")).chain(once(string.from_text("ing")))
    )
    if collected_strings.get() != "string" { return 8 }

    let collected_boxes: boxed.Box<Text> = collect(
        once(boxed.copy_text("boxed")).chain(once(boxed.copy_text(" text")))
    )
    if collected_boxes.get() != "boxed text" { return 9 }

    var drops = 0
    {
        let items: boxed.Box<[DropItem]> = collect(
            once(DropItem(core.ptr.from_mut(drops)))
            .chain(once(DropItem(core.ptr.from_mut(drops))))
            .chain(once(DropItem(core.ptr.from_mut(drops))))
        )
        for item in take items { break }
    }
    if drops != 3 { return 10 }
    0
}
