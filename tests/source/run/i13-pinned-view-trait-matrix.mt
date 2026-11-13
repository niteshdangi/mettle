// profiles: debug release
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.fmt
import core.fmt.{Debug, Display}
import core.hash.{Hash, Hasher, fnv1a}
import core.ops.{Deref, DerefMut}
import core.text.Text

fn hash_of<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}

fn rendered<T: Debug + Display>(read value: T, read debug: Text, read display: Text): bool {
    var buffer = [0u8; 32]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let debug_length = writer.len()
    var other = [0u8; 32]
    var other_writer = fmt.buffer_writer(mut other)
    var other_formatter = fmt.formatter(mut other_writer, fmt.spec())
    match capture T.(Display).fmt(value, mut other_formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let display_length = other_writer.len()
    match (fmt.written_text(read buffer, debug_length), fmt.written_text(read other, display_length)) {
        (present(first), present(second)) => first == debug && second == display,
        _ => false
    }
}

fn main(): i32 {
    var low = 1i32
    var high = 2i32
    var same = 1i32
    let pinned_low = core.pin.Pin.new(read low)
    let pinned_high = core.pin.Pin.new(read high)
    let pinned_same = core.pin.Pin.new(read same)
    if pinned_low != pinned_same || pinned_low == pinned_high { return 1 }
    if !(pinned_low < pinned_high) || pinned_high.cmp(pinned_low) != Ordering.Greater { return 2 }
    if pinned_low.cmp(pinned_same) != Ordering.Equal || pinned_low.partial_cmp(pinned_high) != present(Ordering.Less) { return 3 }
    if pinned_low.clone() != pinned_low { return 4 }
    if hash_of(pinned_low) != hash_of(1i32) || hash_of(pinned_low) == hash_of(pinned_high) { return 5 }
    if !rendered(pinned_low, "1", "1") { return 6 }
    if *pinned_low.deref() != 1 { return 7 }

    var target = 5i32
    var exclusive = core.pin.Pin.new(mut target)
    if exclusive == pinned_low || exclusive < pinned_low { return 8 }
    if !rendered(exclusive, "5", "5") { return 9 }
    *exclusive.deref_mut() += 1
    if *exclusive.deref() != 6 || exclusive != core.pin.Pin.new(read 6i32) { return 10 }
    0
}
