// profiles: debug release
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.fmt
import core.hash.{Hash, Hasher, fnv1a}
import core.ptr.NonNull

fn hash_of<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}



fn from_mut<region r, V: core.convert.From<mut i32 from r>>(take value: mut i32 from r): V { V.(core.convert.From<mut i32 from r>).from(take value) }
fn from_read<region r, V: core.convert.From<read i32 from r>>(take value: read i32 from r): V { V.(core.convert.From<read i32 from r>).from(take value) }

fn main(): i32 {
    var values = [1i32, 2i32]
    let first = NonNull.new(values.as_mut_ptr()).unwrap()
    let second = unsafe { first.add(1usize) }
    let copied = first
    if first != copied || first == second || !(first < second) || !(second > first) { return 1 }
    if first.cmp(second) != Ordering.Less || second.cmp(first) != Ordering.Greater { return 2 }
    if first.cmp(copied) != Ordering.Equal || first.partial_cmp(second) != present(Ordering.Less) { return 3 }
    if hash_of(first) != hash_of(copied) || hash_of(first) == hash_of(second) { return 4 }
    if first.clone() != first { return 5 }
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture NonNull<i32>.(core.fmt.Debug).fmt(first, mut formatter) {
        success(unit) => {},
        failure(error) => { return 6 }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(text) => if !text.starts_with("0x") { return 7 },
        none => { return 8 }
    }
    var target = 5i32
    let mutable: NonNull<i32> = from_mut(mut target)
    let viewed: NonNull<i32> = from_read(read target)
    if mutable != viewed || unsafe { *mutable.as_ptr() } != 5 { return 9 }
    0
}
