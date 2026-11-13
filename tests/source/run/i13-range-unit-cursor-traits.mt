// profiles: debug release
import core.borrow.ToOwned
import core.clone.Clone
import core.cmp.{Eq, Ordering, PartialEq, PartialOrd}
import core.borrow.{AsMut, AsRef}
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.hash.{Hash, Hasher, fnv1a}
import core.iter
import core.text.Text
import std.io.Cursor

fn hash_of<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn default_of<T: Default>(): T { T.(Default).default() }
fn as_slice<T: AsRef<[i32]>>(read value: T): usize { T.(AsRef<[i32]>).as_ref(value).len() }

fn main(): i32 {
    if hash_of(iter.range(1i32, 4i32)) != hash_of(iter.range(1i32, 4i32)) ||
        hash_of(iter.range(1i32, 4i32)) == hash_of(iter.range(1i32, 5i32)) { return 1 }
    if hash_of(iter.range_inclusive(1i32, 4i32)) == hash_of(iter.range_inclusive(1i32, 5i32)) { return 2 }
    if !debug_is(iter.range(1i32, 4i32), "Range { start: 1, end: 4 }") { return 3 }
    if !debug_is(iter.range_inclusive(1i32, 4i32), "RangeInclusive { start: 1, end: 4, done: false }") { return 4 }

    let unit = ()
    if !unit.eq(()) || unit.partial_cmp(()) != present(Ordering.Equal) || hash_of(unit) != hash_of(()) { return 5 }

    var cursor = Cursor.new([1u8, 2u8, 3u8])
    let twin = cursor.clone()
    if twin != cursor { return 6 }
    cursor.set_position(1u64)
    if twin == cursor || !debug_is(twin, "Cursor { inner: [1, 2, 3], position: 0 }") { return 7 }
    let empty: Cursor<[u8; 2]> = default_of()
    if empty.position() != 0u64 { return 8 }

    var numbers = [1i32, 2i32, 3i32]
    if as_slice(numbers) != 3usize { return 9 }
    [i32; 3].(AsMut<[i32]>).as_mut(mut numbers)[0usize] = 5
    if numbers[0usize] != 5 { return 10 }
    let owned: [i32; 3] = numbers.to_owned()
    if owned != numbers { return 11 }
    let slice_owned = [i32].(ToOwned).to_owned(read numbers[0usize..2usize])
    if slice_owned.len() != 2usize { return 12 }
    if "text".to_owned() != "text" { return 13 }
    0
}
