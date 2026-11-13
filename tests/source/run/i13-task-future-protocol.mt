// profiles: debug release
import core.borrow.ToOwned
import core.clone.Clone
import core.cmp.{Ord, PartialEq}
import core.fmt.Debug
import core.future.{Context, Future, Poll, Waker}
import core.hash.hash_one
import core.convert.From
import core.outcome
import alloc.arc.Arc
import std.task.Wake

fn debug<T: Debug>(read value: T): alloc.string.String {
    var output = alloc.string.new()
    {
        var formatter = core.fmt.formatter(mut output, core.fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("Debug formatting failed") }
        }
    }
    output
}

type WakeTarget { wakes: core.sync.atomic.AtomicUsize }
extend WakeTarget implements Wake {
    fn wake(read me: Arc<WakeTarget>): Unit {
        let _ = self.wakes.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
    }
}
unsafe extend WakeTarget implements Transferable {}
unsafe extend WakeTarget implements Shareable {}

type ReadyFuture {}
extend ReadyFuture implements Future {
    type Output = u8
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<u8> {
        Poll.Ready(7u8)
    }
}

fn main(): i32 {
    let ready: Poll<u8> = Poll.Ready(3u8)
    let copied = ready.clone()
    if !ready.is_ready() || copied.is_pending() { return 1 }
    if ready != Poll<u8>.(From<u8>).from(3u8) { return 2 }
    if !(ready < Poll<u8>.Pending) { return 3 }
    if ready.clone() != ready.to_owned() { return 4 }
    if hash_one(read ready) != hash_one(read copied) { return 5 }
    if debug(read ready).as_text() != "Ready(3)" || debug(read Poll<u8>.Pending).as_text() != "Pending" { return 27 }
    if take ready.map(fn(take value: u8): u16 { value as u16 + 1u16 }) !=
       Poll<u16>.Ready(4u16) {
        return 6
    }
    let good_poll: Poll<(Outcome<u8, u16>)> = Poll.Ready(success(3u8))
    match take good_poll.map_ok(fn(take value: u8): u16 { value as u16 + 1u16 }) {
        Poll.Ready(result) => match take result {
            success(value) => { if value != 4u16 { return 13 } },
            failure(_) => { return 13 }
        },
        Poll.Pending => { return 13 }
    }
    let failed_poll: Poll<(Outcome<u16, u8>)> = Poll.Ready(failure(5u8))
    match take failed_poll.map_err(fn(take value: u8): u16 { value as u16 + 1u16 }) {
        Poll.Ready(result) => match take result {
            success(_) => { return 14 },
            failure(value) => { if value != 6u16 { return 14 } }
        },
        Poll.Pending => { return 14 }
    }
    let waker = Waker.noop().clone()
    let duplicate = waker.clone()
    if !waker.will_wake(read duplicate) { return 7 }
    if !waker.uses_vtable(waker.vtable()) { return 8 }
    if waker.data() != core.ptr.null_mut<u8>() { return 12 }
    waker.wake_by_ref()
    let another = unsafe { Waker.new(waker.data(), waker.vtable()) }
    another.wake()
    let raw = waker.clone().into_raw()
    let restored = unsafe { Waker.from_raw(raw) }
    if !waker.will_wake(read restored) { return 9 }
    let release_target = alloc.arc.new(WakeTarget(core.sync.atomic.AtomicUsize.new(0usize)))
    let release_observer = release_target.retain()
    {
        let drop_probe: Waker =
            Waker.(From<Arc<WakeTarget>>).from(release_target)
        if release_observer.strong_count() != 2usize { return 18 }
    }
    if release_observer.strong_count() != 1usize { return 19 }
    var context = Context.from_waker(read waker)
    if !context.waker().will_wake(read waker) { return 10 }
    if debug(read context).as_text() != "Context { waker: Waker }" { return 24 }
    let owned: Waker = waker.to_owned()
    if debug(read owned).as_text() != "Waker" { return 25 }

    var future = core.pin.pin(ReadyFuture())
    match take future.as_mut().poll(mut context) {
        Poll.Ready(value) => { if value != 7u8 { return 11 } },
        Poll.Pending => { return 11 }
    }
    let target = alloc.arc.new(WakeTarget(core.sync.atomic.AtomicUsize.new(0usize)))
    let observer = target.retain()
    let owned_waker: Waker = Waker.(From<Arc<WakeTarget>>).from(target)
    let cloned_waker = owned_waker.clone()
    if observer.strong_count() != 3usize { return 20 }
    owned_waker.wake_by_ref()
    if observer.get().wakes.load(core.sync.atomic.Ordering.Relaxed) != 1usize ||
        observer.strong_count() != 3usize { return 21 }
    cloned_waker.wake()
    if observer.get().wakes.load(core.sync.atomic.Ordering.Relaxed) != 2usize ||
        observer.strong_count() != 2usize { return 22 }
    if debug(read owned_waker).as_text() != "Waker" { return 26 }
    owned_waker.wake()
    if observer.get().wakes.load(core.sync.atomic.Ordering.Relaxed) != 3usize ||
        observer.strong_count() != 1usize { return 23 }
    0
}
