// profiles: debug release
import core.pin
import core.cmp.{Ord, Ordering, PartialEq, PartialOrd}
import core.future.{Context, Future, Poll, noop_waker}
import core.hash.{Hash, Hasher, fnv1a}
import core.ops.{Deref, DerefMut}

type Left { value: i32 }
type Right { value: i32 }

extend Left implements PartialEq<Right> {
    fn eq(read other: Right): bool { self.value == other.value }
}
extend Left implements PartialOrd<Right> {
    fn partial_cmp(read other: Right): Ordering? {
        self.value.partial_cmp(read other.value)
    }
}

fn equal<A: PartialEq<B>, B>(read left: A, read right: B): bool {
    left.eq(right)
}
fn less<A: PartialOrd<B>, B>(read left: A, read right: B): bool {
    left.lt(right)
}
fn compare<T: Ord>(read left: T, read right: T): Ordering {
    left.cmp(right)
}
fn replace<D: DerefMut>(mut value: D, take replacement: D.(Deref).Target): Unit
where D.(Deref).Target: Sized {
    *value.deref_mut() = replacement
}
fn digest<T: Hash>(read value: T): u64 {
    var state = fnv1a()
    value.hash(mut state)
    state.finish()
}

type Ready {
    value: i32
    address: usize
    marker: core.marker.PhantomPinned
}
extend Ready implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        if core.ptr.from_ref(self.get_ref()).addr() != self.get_ref().address {
            return Poll.Ready(-1i32)
        }
        Poll.Ready(self.get_ref().value)
    }
}
fn poll_handle<F: Future>(mut value: F, mut cx: Context): Poll<F.(Future).Output> {
    F.(Future).poll(unsafe { core.pin.Pin.new_unchecked(mut value) }, mut cx)
}

fn main(): i32 {
    let left = Left(3i32)
    let right = Right(3i32)
    var exclusive_left = Left(2i32)
    var exclusive_right = Right(3i32)
    let first = core.pin.Pin.new(read left)
    let second = core.pin.Pin.new(read right)
    let third = core.pin.Pin.new(mut exclusive_left)
    let fourth = core.pin.Pin.new(mut exclusive_right)
    if !equal(read first, read second) || !equal(read first, read fourth) ||
        !less(read third, read second) || !less(read third, read fourth) {
        return 1
    }
    var number = 5i32
    let expected = 13i32
    var later = 17i32
    {
        var view = core.pin.Pin.new(mut number)
        let next = core.pin.Pin.new(mut later)
        replace(mut view, 13i32)
        if *view.deref() != 13i32 || digest(read view) != digest(read expected) ||
            compare(read view, read next) != Ordering.Less {
            return 2
        }
    }
    if number != 13i32 { return 3 }
    var ready = Ready(19i32, 0usize, core.marker.PhantomPinned)
    var view = unsafe { core.pin.Pin.new_unchecked(mut ready) }
    let address = core.ptr.from_ref(view.get_ref()).addr()
    unsafe { view.get_unchecked_mut().address = address }
    let waker = noop_waker()
    var context = Context.from_waker(read waker)
    match poll_handle(mut view, mut context) {
        Poll.Ready(value) => { if value != 19i32 { return 4 } },
        Poll.Pending => { return 5 }
    }
    0
}
