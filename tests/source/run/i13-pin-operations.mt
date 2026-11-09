// profiles: debug release

import core.future.{Context, Future, Poll, noop_waker}
import alloc.boxed
import core.cmp.{Eq, Ord, PartialEq, PartialOrd}
import core.clone.Clone
import core.fmt.{Debug, Display}
import core.hash.{Hash, Hasher, fnv1a}
import core.pin

type Pair {
    left: i32
    right: i32
}

type Ready {
    value: i32
}

extend Ready implements Future {
    type Output = i32

    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        Poll.Ready(unsafe { self.get_unchecked_mut() }.value)
    }
}

fn left(read pair: Pair): read i32 from pair {
    read pair.left
}

fn left_mut(mut pair: Pair): mut i32 from pair {
    mut pair.left
}

fn eq_ok<T: Eq>() {}
fn partial_eq_ok<T: PartialEq<T>>() {}
fn ord_ok<T: Ord>() {}
fn partial_ord_ok<T: PartialOrd<T>>() {}
fn clone_ok<T: Clone>() {}
fn copy_ok<T: Copy>() {}
fn debug_ok<T: Debug>() {}
fn display_ok<T: Display>() {}
fn hash_ok<T: Hash>() {}
fn send_ok<T: Transferable>() {}
fn share_ok<T: Shareable>() {}
fn hash_matches<T: Hash>(read value: T, expected: i32): bool {
    var actual = fnv1a()
    value.hash(mut actual)
    var baseline = fnv1a()
    expected.hash(mut baseline)
    actual.finish() == baseline.finish()
}

fn main(): i32 {
    // Pinned locals are not moved until their pin handles leave scope.
    var value = 1i32
    var `pinned` = core.pin.Pin.new(mut value)
    if *`pinned`.get_ref() != 1 { return 1 }
    *`pinned`.get_mut() = 2
    if *`pinned`.as_ref().get_ref() != 2 { return 2 }
    *`pinned`.as_mut().get_mut() = 3
    if *`pinned`.get_ref() != 3 { return 3 }
    `pinned`.set(4)
    if *`pinned`.get_ref() != 4 { return 4 }
    if *take `pinned`.into_ref().get_ref() != 4 { return 5 }
    var unpin_value = 5i32
    let unpin_pin = core.pin.Pin.new(mut unpin_value)
    *take unpin_pin.into_inner() = 6
    if unpin_value != 6 { return 16 }

    var boxed = boxed.pin(5i32)
    {
        var pinned_box = core.pin.Pin.new(mut boxed)
        *pinned_box.as_deref_mut().get_mut() = 6
    }
    if *boxed.get_ref() != 6 { return 12 }

    var unchecked_value = 6i32
    {
        var unchecked = unsafe {
            core.pin.Pin.new_unchecked(mut unchecked_value)
        }
        unsafe { *unchecked.get_unchecked_mut() = 7 }
    }
    if unchecked_value != 7 { return 6 }
    {
        let restored = unsafe {
            take core.pin.Pin.new_unchecked(mut unchecked_value).into_inner_unchecked()
        }
        *restored = 8
    }
    if unchecked_value != 8 { return 7 }

    var pair = Pair(9, 10)
    {
        let pair_pin = unsafe { core.pin.Pin.new_unchecked(mut pair) }
        let first = unsafe { pair_pin.map_unchecked(left) }
        if *first.get_ref() != 9 { return 8 }
    }
    {
        var mut_pair_pin = unsafe { core.pin.Pin.new_unchecked(mut pair) }
        let first_mut = unsafe { mut_pair_pin.map_unchecked_mut(left_mut) }
        *unsafe { first_mut.get_unchecked_mut() } = 11
    }
    if pair.left != 11 { return 9 }

    let waker = noop_waker()
    var context = Context.from_waker(read waker)
    var future = Ready(12)
    var future_pin = unsafe { core.pin.Pin.new_unchecked(mut future) }
    match future_pin.poll(mut context) {
        Poll.Ready(value) => { if value != 12 { return 10 } },
        Poll.Pending => { return 11 }
    }

    let first = core.pin.Pin.new(read value)
    let second = core.pin.Pin.new(read value)
    let later = core.pin.Pin.new(read unchecked_value)
    if first != second || !(first < later) { return 13 }
    let cloned = first.clone()
    if cloned != first { return 14 }
    if !hash_matches(first, value) { return 15 }
    eq_ok<pinned read i32 from static>()
    partial_eq_ok<pinned read i32 from static>()
    ord_ok<pinned read i32 from static>()
    partial_ord_ok<pinned read i32 from static>()
    clone_ok<pinned read i32 from static>()
    copy_ok<pinned read i32 from static>()
    debug_ok<pinned read i32 from static>()
    display_ok<pinned read i32 from static>()
    hash_ok<pinned read i32 from static>()
    send_ok<pinned read i32 from static>()
    share_ok<pinned read i32 from static>()
    0
}
