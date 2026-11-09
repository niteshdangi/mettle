// expect-exit: 0
// profiles: debug release
// Evidence for the V1 atomically counted Arc and Weak operations (alloc.arc).
// Each operation is called and its result checked; drop counts are observed
// through a counter shared by every owner so over- and under-release fail.

import alloc.arc
import core.clone.Clone
import core.cmp.{Eq, PartialEq}
import core.convert.From
import core.default.Default

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

fn drops_of(read counter: arc.Arc<core.sync.atomic.AtomicUsize>): usize {
    counter.get().load(core.sync.atomic.Ordering.SeqCst)
}

fn default_value<T: Default>(): T { T.(Default).default() }
fn from_value<T: From<i32>>(value: i32): T { T.(From<i32>).from(value) }

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
    let converted: arc.Arc<i32> = from_value<arc.Arc<i32>>(33)
    let other = arc.new(33)
    if !(converted == other) { return 103 }
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
