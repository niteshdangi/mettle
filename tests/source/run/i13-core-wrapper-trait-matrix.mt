// profiles: debug release
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd, Reverse}
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.future.Poll
import core.hash.{Hash, Hasher, fnv1a}
import core.iter.{FromItems, OwnedIterable}
import core.ops.{Deref, DerefMut}
import core.text.Text

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
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

fn hash_of<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}

fn convert<T: From<i32>>(value: i32): T { T.(From<i32>).from(value) }
fn default_of<T: Default>(): T { T.(Default).default() }

fn ordered<T: Ord + Eq + PartialOrd + PartialEq>(read low: T, read high: T): bool {
    low == low && low != high && low < high && high > low &&
        low.cmp(high) == Ordering.Less && high.cmp(low) == Ordering.Greater &&
        low.cmp(low) == Ordering.Equal &&
        low.partial_cmp(high) == present(Ordering.Less)
}

fn main(): i32 {
    let some: i32? = convert(3)
    let nothing: i32? = default_of()
    if some == nothing || some != present(3) || !ordered(nothing, some) { return 1 }
    if hash_of(some) == hash_of(nothing) || hash_of(some) != hash_of(present(3)) { return 2 }
    if !debug_is(some, "present(3)") || !debug_is(nothing, "none") { return 3 }
    if some.clone() != some { return 17 }
    var total = 0
    for value in some { total += *value }
    for value in nothing { total += 100 }
    if total != 3 { return 4 }

    let good: (Outcome<i32, i32>) = success(1)
    let worse: (Outcome<i32, i32>) = failure(1)
    let same: (Outcome<i32, i32>) = success(1)
    if good == worse || good != same || !ordered(good, worse) { return 5 }
    if hash_of(good) == hash_of(worse) || hash_of(good) != hash_of(same) { return 6 }
    if !debug_is(good, "success(1)") || !debug_is(worse, "failure(1)") { return 7 }
    var seen = 0
    for value in good { seen += *value }
    for value in worse { seen += 100 }
    if seen != 1 { return 8 }

    let ready = Poll.Ready(5)
    let pending: Poll<i32> = Poll.Pending
    let converted: Poll<i32> = convert(5)
    if ready == pending || ready.clone() != converted || !ordered(ready, pending) { return 9 }
    if hash_of(ready) == hash_of(pending) || hash_of(ready) != hash_of(converted) { return 10 }
    if !debug_is(ready, "Ready(5)") || !debug_is(pending, "Pending") { return 11 }

    var held = core.mem.ManuallyDrop.new(7)
    *held.deref_mut() += 1
    if *held.deref() != 8 || held != core.mem.ManuallyDrop.new(8) { return 12 }
    if !ordered(core.mem.ManuallyDrop.new(1), core.mem.ManuallyDrop.new(2)) { return 13 }
    if hash_of(held) != hash_of(8) || !debug_is(held, "8") { return 14 }

    let low = Reverse(1)
    let high = Reverse(2)
    if !ordered(high, low) || hash_of(low) != hash_of(Reverse(1)) { return 15 }
    let defaulted: Reverse<i32> = default_of()
    if defaulted.value != 0 || !debug_is(low, "Reverse(1)") { return 16 }
    0
}
