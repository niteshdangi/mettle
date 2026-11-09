// expect-exit: 0
// profiles: debug release

import core.any.Any
import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert.From
import core.convert.Into
import core.convert.{TryFrom, TryInto}

fn any_ok<T: Any>() {}
fn borrow_ok<T: unsized + Borrow<T>>() {}
fn owned_ok<T: ToOwned>() {}
fn from_ok<T: From<T>>() {}
fn into_ok<T: Into<T>>() {}
fn tryfrom_ok<T: TryFrom<T>>() {}
fn tryinto_ok<T: TryInto<T>>() {}
fn send_ok<T: Transferable>() {}
fn sync_ok<T: Shareable>() {}

fn main(): i32 {
    // iter::Chain = Chained: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    borrow_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    from_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    into_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    send_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    sync_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()
    owned_ok<core.iter.Chained<core.iter.Range<i32>, core.iter.Range<i32>>>()

    // iter::Cloned: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    borrow_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    from_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    into_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    send_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()
    sync_ok<core.iter.Cloned<region static, i32, core.iter.Range<i32>>>()

    // iter::Copied: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    borrow_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    from_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    into_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    send_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()
    sync_ok<core.iter.Copied<region static, i32, core.iter.Range<i32>>>()

    // iter::Enumerate = Enumerated: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    from_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    into_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    send_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    sync_ok<core.iter.Enumerated<core.iter.Range<i32>>>()
    owned_ok<core.iter.Enumerated<core.iter.Range<i32>>>()

    // iter::Filter = Filtered: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    borrow_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    from_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    tryfrom_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    tryinto_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    into_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    send_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()
    sync_ok<core.iter.Filtered<core.iter.Range<i32>, fn(i32): bool>>()

    // iter::FlatMap = FlatMapped: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    borrow_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    from_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    tryinto_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    into_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    send_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()
    sync_ok<core.iter.FlatMapped<core.iter.Range<i32>, core.iter.Range<i32>, fn(i32): core.iter.Range<i32>>>()

    // iter::Flatten: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    borrow_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    from_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    tryfrom_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    tryinto_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    into_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    send_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()
    sync_ok<core.iter.Flatten<core.iter.Range<i32>, core.iter.Once<core.iter.Range<i32>>>>()

    // iter::Map = Mapped: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    borrow_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    from_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    tryfrom_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    tryinto_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    into_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    send_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()
    sync_ok<core.iter.Mapped<i32, core.iter.Range<i32>, fn(i32): i32>>()

    // iter::Peekable: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    from_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    into_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    send_ok<core.iter.Peekable<core.iter.Range<i32>>>()
    sync_ok<core.iter.Peekable<core.iter.Range<i32>>>()

    // iter::Rev = Reversed: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    from_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    into_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    send_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    sync_ok<core.iter.Reversed<core.iter.Range<i32>>>()
    owned_ok<core.iter.Reversed<core.iter.Range<i32>>>()

    // iter::Skip = Skipped: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    from_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    into_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    send_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    sync_ok<core.iter.Skipped<core.iter.Range<i32>>>()
    owned_ok<core.iter.Skipped<core.iter.Range<i32>>>()

    // iter::SkipWhile = SkippedWhile: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    borrow_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    from_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    tryfrom_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    tryinto_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    into_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    send_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()
    sync_ok<core.iter.SkippedWhile<core.iter.Range<i32>, fn(i32): bool>>()

    // iter::StepBy = Stepped: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    from_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    into_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    send_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    sync_ok<core.iter.Stepped<core.iter.Range<i32>>>()
    owned_ok<core.iter.Stepped<core.iter.Range<i32>>>()

    // iter::Take = Limited: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Limited<core.iter.Range<i32>>>()
    borrow_ok<core.iter.Limited<core.iter.Range<i32>>>()
    from_ok<core.iter.Limited<core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Limited<core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Limited<core.iter.Range<i32>>>()
    into_ok<core.iter.Limited<core.iter.Range<i32>>>()
    send_ok<core.iter.Limited<core.iter.Range<i32>>>()
    sync_ok<core.iter.Limited<core.iter.Range<i32>>>()
    owned_ok<core.iter.Limited<core.iter.Range<i32>>>()

    // iter::TakeWhile = TakenWhile: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    borrow_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    from_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    tryfrom_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    tryinto_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    into_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    send_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()
    sync_ok<core.iter.TakenWhile<core.iter.Range<i32>, fn(i32): bool>>()

    // iter::Zip = Zipped: Any Borrow From Into Send Sync ToOwned
    any_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    borrow_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    from_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    tryfrom_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    tryinto_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    into_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    send_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    sync_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()
    owned_ok<core.iter.Zipped<core.iter.Range<i32>, core.iter.Range<i32>>>()

    // slice::Chunks = SliceChunks: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.slice.SliceChunks<region static, i32>>()
    from_ok<core.slice.SliceChunks<region static, i32>>()
    tryfrom_ok<core.slice.SliceChunks<region static, i32>>()
    tryinto_ok<core.slice.SliceChunks<region static, i32>>()
    into_ok<core.slice.SliceChunks<region static, i32>>()
    send_ok<core.slice.SliceChunks<region static, i32>>()
    sync_ok<core.slice.SliceChunks<region static, i32>>()

    // slice::Windows = SliceWindows: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.slice.SliceWindows<region static, i32>>()
    from_ok<core.slice.SliceWindows<region static, i32>>()
    tryfrom_ok<core.slice.SliceWindows<region static, i32>>()
    tryinto_ok<core.slice.SliceWindows<region static, i32>>()
    into_ok<core.slice.SliceWindows<region static, i32>>()
    send_ok<core.slice.SliceWindows<region static, i32>>()
    sync_ok<core.slice.SliceWindows<region static, i32>>()

    // str::Bytes: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.text.Bytes<region static>>()
    from_ok<core.text.Bytes<region static>>()
    tryfrom_ok<core.text.Bytes<region static>>()
    tryinto_ok<core.text.Bytes<region static>>()
    into_ok<core.text.Bytes<region static>>()
    send_ok<core.text.Bytes<region static>>()
    sync_ok<core.text.Bytes<region static>>()

    // str::CharIndices: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.text.CharIndices<region static>>()
    from_ok<core.text.CharIndices<region static>>()
    tryfrom_ok<core.text.CharIndices<region static>>()
    tryinto_ok<core.text.CharIndices<region static>>()
    into_ok<core.text.CharIndices<region static>>()
    send_ok<core.text.CharIndices<region static>>()
    sync_ok<core.text.CharIndices<region static>>()

    // str::Chars: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.text.Chars<region static>>()
    from_ok<core.text.Chars<region static>>()
    tryfrom_ok<core.text.Chars<region static>>()
    tryinto_ok<core.text.Chars<region static>>()
    into_ok<core.text.Chars<region static>>()
    send_ok<core.text.Chars<region static>>()
    sync_ok<core.text.Chars<region static>>()

    // str::Split: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.text.Split<region static>>()
    from_ok<core.text.Split<region static>>()
    tryfrom_ok<core.text.Split<region static>>()
    tryinto_ok<core.text.Split<region static>>()
    into_ok<core.text.Split<region static>>()
    send_ok<core.text.Split<region static>>()
    sync_ok<core.text.Split<region static>>()

    // str::SplitWhitespace: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.text.SplitWhitespace<region static>>()
    from_ok<core.text.SplitWhitespace<region static>>()
    tryfrom_ok<core.text.SplitWhitespace<region static>>()
    tryinto_ok<core.text.SplitWhitespace<region static>>()
    into_ok<core.text.SplitWhitespace<region static>>()
    send_ok<core.text.SplitWhitespace<region static>>()
    sync_ok<core.text.SplitWhitespace<region static>>()

    // btree_set::Iter and hash_set::Iter (= Keys<K, Unit>): Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.btree.Keys<region static, i32, Unit, alloc.alloc.Global>>()
    from_ok<alloc.btree.Keys<region static, i32, Unit, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.Keys<region static, i32, Unit, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.Keys<region static, i32, Unit, alloc.alloc.Global>>()
    into_ok<alloc.btree.Keys<region static, i32, Unit, alloc.alloc.Global>>()

    borrow_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    from_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    tryfrom_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    tryinto_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    into_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    send_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    sync_ok<alloc.hash_map.Keys<region static, i32, Unit>>()
    0
}
