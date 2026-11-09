// expect-exit: 0
// profiles: debug release
// Evidence for the V1 atomically counted Arc and Weak operations (alloc.arc).
// Each operation is called and its result checked; drop counts are observed
// through a counter shared by every owner so over- and under-release fail.

import alloc.arc
import core.clone.Clone
import core.borrow.{AsRef, Borrow}
import core.cmp.{Eq, Ord, PartialEq, PartialOrd}
import core.convert.{From, TryFrom}
import core.default.Default
import core.error.Error
import core.fmt
import core.fmt.{Debug, Display}
import core.hash.hash_one
import core.iter.FromItems
import core.ops.Deref

type Probe {
    drops: arc.Arc<core.sync.atomic.AtomicUsize>
    value: i32
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

type Node {
    parent: arc.Weak<Node>
    value: i32
}

type ArcErrorLeaf {}
extend ArcErrorLeaf implements Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("leaf") }
}
extend ArcErrorLeaf implements Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("leaf") }
}
extend ArcErrorLeaf implements Error {}

type ArcErrorBranch { cause: ArcErrorLeaf }
extend ArcErrorBranch implements Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("branch") }
}
extend ArcErrorBranch implements Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("branch") }
}
extend ArcErrorBranch implements Error {
    fn source<region r>(receiver read self: ArcErrorBranch from r): (read any Error from r)? {
        let cause: read any Error = read self.cause
        present(cause)
    }
}

fn drops_of(read counter: arc.Arc<core.sync.atomic.AtomicUsize>): usize {
    counter.get().load(core.sync.atomic.Ordering.SeqCst)
}

fn default_value<T: Default>(): T { T.(Default).default() }
fn from_value<T: From<i32>>(value: i32): T { T.(From<i32>).from(value) }
fn error_source<region r, E: Error>(read value: E from r): (read any Error from r)? {
    E.(Error).source(value)
}
fn borrow_i32<T: Borrow<i32>>(read value: T): i32 {
    *T.(Borrow<i32>).borrow(value)
}
fn debug_is<T: Debug>(read value: T, read expected: core.text.Text): bool {
    var buffer = [0u8; 64]
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
fn display_is<T: unsized + Display>(read value: T, read expected: core.text.Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

// new, retain, clone, downgrade and the count and identity queries
fn checks_construction_and_counts(): i32 {
    let owner = arc.new(7)
    if owner.strong_count() != 1usize || owner.weak_count() != 0usize { return 10 }
    if *owner.get() != 7 { return 11 }
    let sharing = owner.retain()
    if owner.strong_count() != 2usize || !owner.ptr_eq(sharing) { return 12 }
    let cloned = owner.clone()
    if cloned.strong_count() != 3usize { return 13 }
    core.mem.drop(cloned)
    if owner.strong_count() != 2usize { return 14 }
    let observer = owner.downgrade()
    if owner.weak_count() != 1usize || observer.weak_count() != 1usize { return 15 }
    let second_observer = observer.clone()
    if owner.weak_count() != 2usize || !observer.ptr_eq(second_observer) { return 16 }
    if observer.strong_count() != 2usize { return 17 }
    let other = arc.new(7)
    if owner.ptr_eq(other) { return 18 }
    if owner.as_ptr() != sharing.as_ptr() { return 19 }
    let fresh = arc.new_weak<i32>()
    if fresh.strong_count() != 0usize || fresh.weak_count() != 0usize { return 20 }
    if fresh.upgrade().is_present() { return 21 }
    if !fresh.ptr_eq(arc.new_weak<i32>()) { return 22 }
    0
}

// upgrade succeeds only while a strong owner exists; dropping the last owner
// drops the payload exactly once.
fn checks_weak_and_drops(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let observer = {
        let owner = arc.new(Probe(drops.retain(), 3))
        let observer = owner.downgrade()
        match observer.upgrade() {
            present(strong) => {
                if strong.strong_count() != 2usize { return 30 }
                if strong.get().value != 3 { return 31 }
            },
            none => { return 32 }
        }
        if owner.strong_count() != 1usize || observer.weak_count() != 1usize { return 33 }
        if drops_of(drops) != 0usize { return 34 }
        observer
    }
    if drops_of(drops) != 1usize { return 35 }
    if observer.strong_count() != 0usize || observer.weak_count() != 0usize { return 36 }
    if observer.upgrade().is_present() { return 37 }

    // a weak handle keeps the allocation alive without keeping the payload
    let weak_only = {
        let owner = arc.new(Probe(drops.retain(), 4))
        owner.downgrade()
    }
    if drops_of(drops) != 2usize || weak_only.upgrade().is_present() { return 38 }
    0
}

// Weak::as_ptr remains the payload address; an empty Weak carries no count.
fn checks_empty_weak_and_pointers(): i32 {
    let owner = arc.new(21)
    let observer = owner.downgrade()
    if observer.as_ptr() != owner.as_ptr() { return 40 }
    let empty = arc.new_weak<i32>()
    if empty.as_ptr() != core.ptr.null_mut<i32>().cast_const() { return 41 }
    let empty_copy = empty.clone()
    if empty_copy.strong_count() != 0usize { return 42 }
    0
}

// Raw ownership tokens: into_raw/from_raw round-trip one count, and
// increment/decrement adjust the strong count explicitly.
fn checks_raw_handles(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let owner = arc.new(Probe(drops.retain(), 5))
    let raw = owner.into_raw()
    if raw.as_ptr() == core.ptr.null_mut<Probe>() { return 50 }
    let restored = unsafe { arc.from_raw(raw) }
    if restored.strong_count() != 1usize || restored.get().value != 5 { return 51 }
    let token = restored.into_raw()
    let second = unsafe { arc.increment_strong_count(read token) }
    if drops_of(drops) != 0usize { return 52 }
    unsafe { arc.decrement_strong_count(take token) }
    let survivor = unsafe { arc.from_raw(second) }
    if survivor.strong_count() != 1usize || drops_of(drops) != 0usize { return 53 }
    core.mem.drop(survivor)
    if drops_of(drops) != 1usize { return 54 }

    let weak_owner = arc.new(9)
    let weak_handle = weak_owner.downgrade()
    let weak_raw = weak_handle.into_raw()
    let weak_back = unsafe { arc.weak_from_raw(weak_raw) }
    if weak_back.weak_count() != 1usize { return 55 }
    0
}

// get_mut, make_mut, try_unwrap, into_inner and unwrap_or_clone require
// exclusive ownership; otherwise the handle or the payload stays shared.
fn checks_unique_access(): i32 {
    var solo = arc.new(10)
    match take solo.get_mut() {
        present(value) => { *value = 11 },
        none => { return 60 }
    }
    if *solo.get() != 11 { return 61 }
    let held = solo.retain()
    match take solo.get_mut() {
        present(_) => { return 62 },
        none => {}
    }
    core.mem.drop(held)

    var copy_on_write = arc.new(20)
    let twin = copy_on_write.retain()
    let mutable = copy_on_write.make_mut()
    *mutable = 21
    if *copy_on_write.get() != 21 || *twin.get() != 20 { return 63 }
    if copy_on_write.ptr_eq(twin) { return 64 }

    let single = arc.new(30)
    let unwrapped = capture single.try_unwrap()
    match take unwrapped {
        success(value) => { if value != 30 { return 65 } },
        failure(_) => { return 66 }
    }
    let twice = arc.new(31)
    let also = twice.retain()
    let refused = capture twice.try_unwrap()
    match take refused {
        success(_) => { return 67 },
        failure(back) => { if back.strong_count() != 2usize { return 68 } }
    }
    // the refused handle was dropped above, so `also` is the sole owner again
    match take also.into_inner() {
        present(value) => { if value != 31 { return 69 } },
        none => { return 77 }
    }
    let lone = arc.new(40)
    match take lone.into_inner() {
        present(value) => { if value != 40 { return 70 } },
        none => { return 71 }
    }
    let cloneable = arc.new(50)
    let other = cloneable.retain()
    if cloneable.unwrap_or_clone() != 50 { return 72 }
    if other.strong_count() != 1usize { return 73 }
    0
}

// Constructors for uninitialized and zeroed payloads, and the slice forms.
fn checks_uninit_and_slices(): i32 {
    var uninit = arc.new_uninit<i32>()
    match take uninit.get_mut() {
        present(slot) => { *slot = core.mem.MaybeUninit<i32>.new(14) },
        none => { return 80 }
    }
    let initialized = unsafe { uninit.assume_init() }
    if *initialized.get() != 14 { return 81 }

    let zeroed = arc.new_zeroed<i32>()
    let zero = unsafe { zeroed.assume_init() }
    if *zero.get() != 0 { return 82 }

    var slots = arc.new_uninit_slice<i32>(3usize)
    match take slots.get_mut() {
        present(view) => {
            var index = 0usize
            while index < 3usize {
                view[index] = core.mem.MaybeUninit<i32>.new(index as i32 + 1)
                index += 1usize
            }
        },
        none => { return 83 }
    }
    let values = unsafe { slots.assume_init() }
    if values.get().len() != 3usize || values.get()[2usize] != 3 { return 84 }

    let zero_slots = arc.new_zeroed_slice<i32>(2usize)
    let zeros = unsafe { zero_slots.assume_init() }
    if zeros.get()[0usize] != 0 || zeros.get()[1usize] != 0 { return 85 }

    let text = arc.copy_text("ok")
    if text.get().as_bytes().len() != 2usize { return 86 }
    0
}

// Cyclic construction hands the constructor a weak handle that is empty
// until the payload is installed; the finished payload points back.
fn checks_cyclic_and_pin(): i32 {
    let child = arc.new_cyclic(fn(read me: arc.Weak<Node>): Node {
        if me.upgrade().is_present() { panic("upgrade before payload init") }
        Node(me.clone(), 2)
    })
    if child.get().value != 2 || child.weak_count() != 1usize { return 90 }
    if child.get().parent.strong_count() != 1usize { return 91 }

    let fixed = arc.pin(Node(arc.new_weak<Node>(), 12))
    if fixed.get_ref().value != 12 { return 92 }
    let pinned_copy = fixed.retain()
    if !fixed.ptr_eq(pinned_copy) { return 93 }
    0
}

// Defaults and conversions from owned values.
fn checks_defaults_and_conversions(): i32 {
    let defaulted: arc.Arc<i32> = default_value<arc.Arc<i32>>()
    if *defaulted.get() != 0 { return 100 }
    let empty_slice: arc.Arc<[i32]> = default_value<arc.Arc<[i32]>>()
    if empty_slice.get().len() != 0usize { return 101 }
    let empty_text: arc.Arc<core.text.Text> = default_value<arc.Arc<core.text.Text>>()
    if empty_text.get().as_bytes().len() != 0usize { return 102 }
    let default_weak: arc.Weak<i32> = default_value<arc.Weak<i32>>()
    if default_weak.strong_count() != 0usize || default_weak.weak_count() != 0usize {
        return 103
    }
    if !debug_is(read default_weak, "(Weak)") { return 104 }
    let converted: arc.Arc<i32> = from_value<arc.Arc<i32>>(33)
    let other = arc.new(33)
    if !(converted == other) { return 105 }
    let boxed = alloc.boxed.new(34)
    let from_box = arc.Arc<i32>.(From<alloc.boxed.Box<i32>>).from(boxed)
    if *from_box.get() != 34 { return 119 }

    let low = arc.new(3)
    let high = arc.new(4)
    if !(low < high) || low.cmp(read high) != core.cmp.Ordering.Less { return 106 }
    if low.partial_cmp(read high) != present(core.cmp.Ordering.Less) { return 107 }
    if *arc.Arc<i32>.(Deref).deref(read high) != 4 { return 108 }
    if *arc.Arc<i32>.(AsRef<i32>).as_ref(read high) != 4 { return 109 }
    if borrow_i32(read high) != 4 { return 110 }
    if hash_one(read high) != hash_one(read 4i32) { return 111 }
    if !debug_is(read high, "4") || !display_is(read high, "4") {
        return 112
    }
    let error = arc.new(ArcErrorBranch(ArcErrorLeaf()))
    if !display_is(read error, "branch") { return 126 }
    match error_source(read error) {
        present(source) => { if !display_is(source, "leaf") { return 127 } },
        none => { return 128 }
    }

    let from_array = arc.Arc<[i32]>.(From<[i32; 3]>).from([4, 5, 6])
    if from_array.get().len() != 3usize || from_array.get()[2usize] != 6 {
        return 113
    }
    let slice_source = [11, 12, 13]
    let slice_view: read [i32] = read slice_source
    let from_slice = arc.Arc<[i32]>.(From<read [i32]>).from(slice_view)
    if from_slice.get()[0usize] != 11 || from_slice.get()[2usize] != 13 {
        return 120
    }
    var mutable_source = [14, 15]
    let mutable_view: mut [i32] = mut mutable_source
    let from_mut_slice = arc.Arc<[i32]>.(From<mut [i32]>).from(take mutable_view)
    if from_mut_slice.get()[0usize] != 14 || from_mut_slice.get()[1usize] != 15 {
        return 121
    }
    let text_owner = arc.Arc<core.text.Text>.(From<read core.text.Text>).from("sync")
    let bytes_owner = arc.Arc<[u8]>.(From<arc.Arc<core.text.Text>>).from(text_owner)
    if bytes_owner.get().len() != 4usize || bytes_owner.get()[0usize] != b's' {
        return 122
    }
    var mutable_text_bytes = [b'o', b'k']
    let mutable_text = match take core.text.from_utf8_mut(mut mutable_text_bytes) {
        present(value) => value,
        none => { return 124 }
    }
    let mutable_text_owner = arc.Arc<core.text.Text>.(From<mut core.text.Text>).from(
        take mutable_text
    )
    if mutable_text_owner.get().as_bytes()[1usize] != b'k' { return 125 }
    let string_owner = arc.Arc<core.text.Text>.(From<alloc.string.String>).from(
        alloc.string.from_text("text")
    )
    if string_owner.get().as_bytes().len() != 4usize { return 123 }
    match arc.Arc<[i32; 3]>.(TryFrom<arc.Arc<[i32]>>).try_from(from_array) {
        success(array) => {
            if array.get()[0usize] != 4 || array.get()[2usize] != 6 { return 115 }
        },
        failure(_) => { return 116 }
    }
    let wrong_values = alloc.vec.List<i32>.(From<[i32; 2]>).from([9, 10])
    let wrong_length = arc.Arc<[i32]>.(From<alloc.vec.List<i32>>).from(wrong_values)
    match arc.Arc<[i32; 3]>.(TryFrom<arc.Arc<[i32]>>).try_from(wrong_length) {
        success(_) => { return 117 },
        failure(original) => {
            if original.get().len() != 2usize || original.get()[1usize] != 10 {
                return 118
            }
        }
    }
    let list = alloc.vec.List<i32>.(From<[i32; 2]>).from([7, 8])
    let from_items = arc.Arc<[i32]>.(FromItems<i32>).from_iter(list.into_iter())
    if from_items.get().len() != 2usize || from_items.get()[1usize] != 8 {
        return 114
    }

    0
}

fn main(): i32 {
    let first = checks_construction_and_counts()
    if first != 0 { return first }
    let second = checks_weak_and_drops()
    if second != 0 { return second }
    let third = checks_empty_weak_and_pointers()
    if third != 0 { return third }
    let fourth = checks_raw_handles()
    if fourth != 0 { return fourth }
    let fifth = checks_unique_access()
    if fifth != 0 { return fifth }
    let sixth = checks_uninit_and_slices()
    if sixth != 0 { return sixth }
    let seventh = checks_cyclic_and_pin()
    if seventh != 0 { return seventh }
    checks_defaults_and_conversions()
}
