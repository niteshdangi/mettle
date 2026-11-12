// profiles: debug release
import core.mem
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.hash.{Hash, Hasher, fnv1a}
import core.borrow.ToOwned
import core.ops.DerefMut
import core.fmt
import core.fmt.{Debug, Error, Formatter}
import core.text.Text

type ManualGuard {
    counter: ptr<mut i32>
    amount: i32
    drop { unsafe { *self.counter += self.amount } }
}

type CloneGuard {
    clones: ptr<mut i32>
    drops: ptr<mut i32>
    amount: i32
    drop { unsafe { *self.drops += self.amount } }
}

extend CloneGuard implements Clone {
    fn clone(): CloneGuard {
        unsafe { *self.clones += 1i32 }
        CloneGuard(self.clones, self.drops, self.amount + 1i32)
    }
}

fn digest<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 32]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    let value = core.mem.ManuallyDrop.new(5i32)
    let cloned = value.clone()
    if cloned != value || cloned.cmp(read value) != Ordering.Equal { return 1 }
    match cloned.partial_cmp(read value) {
        present(ordering) => { if ordering != Ordering.Equal { return 2 } },
        none => { return 2 }
    }
    if digest(read cloned) != digest(read value) { return 3 }
    if !debug_is(read value, "5") { return 4 }
    let copied = value
    if copied != value { return 5 }

    let owned: core.mem.ManuallyDrop<i32> = value.to_owned()
    if owned.into_inner() != 5i32 { return 6 }
    let defaulted: core.mem.ManuallyDrop<i32> =
        core.mem.ManuallyDrop<i32>.(Default).default()
    if defaulted.into_inner() != 0i32 { return 7 }

    var mutable = core.mem.ManuallyDrop.new(7i32)
    let slot: mut i32 = mutable.deref_mut()
    *slot = 9i32
    if mutable.into_inner() != 9i32 { return 8 }

    var count = 0i32
    let counter = core.ptr.from_mut(mut count)
    var guard = core.mem.ManuallyDrop.new(ManualGuard(counter, 3i32))
    unsafe { mut guard.`drop`() }
    if count != 3i32 { return 9 }

    var take_count = 0i32
    {
        var storage = core.mem.ManuallyDrop.new(
            ManualGuard(core.ptr.from_mut(mut take_count), 5i32)
        )
        let taken = unsafe { storage.`take`() }
    }
    if take_count != 5i32 { return 10 }

    var clones = 0i32
    var clone_drops = 0i32
    var original = core.mem.ManuallyDrop.new(
        CloneGuard(core.ptr.from_mut(mut clones), core.ptr.from_mut(mut clone_drops), 1i32)
    )
    let duplicate = original.clone()
    if clones != 1i32 || clone_drops != 0i32 { return 11 }
    {
        let payload = duplicate.into_inner()
        if payload.amount != 2i32 { return 12 }
    }
    if clone_drops != 2i32 { return 13 }
    unsafe { mut original.`drop`() }
    if clone_drops != 3i32 { return 14 }
    0
}
