// profiles: debug release
import core.future.{Context, Poll, RawWaker, RawWakerVTable, Waker}

fn clone_raw(data: ptr<mut u8>): RawWaker { RawWaker(data, table()) }
fn noop(data: ptr<mut u8>): Unit {}
const fn table(): RawWakerVTable { RawWakerVTable(clone_raw, noop, noop, noop) }

const READY: bool = Poll<i32>.Ready(3).is_ready()
const PENDING: bool = Poll<i32>.Pending.is_pending()
static FROM_RAW: Waker = unsafe {
    Waker.from_raw(RawWaker(core.ptr.null_mut<u8>(), table()))
}
static FROM_PARTS: Waker = unsafe {
    Waker.new(core.ptr.null_mut<u8>(), table())
}

const fn retained_waker(): read Waker from static {
    let context = Context.from_waker(Waker.noop())
    context.waker()
}

const RETAINED: read Waker from static = retained_waker()

fn main(): i32 {
    if !READY || !PENDING { return 1 }
    if !FROM_RAW.will_wake(read FROM_PARTS) { return 2 }
    if !RETAINED.will_wake(Waker.noop()) { return 3 }
    if core.ptr.from_ref(Waker.noop()) != core.ptr.from_ref(RETAINED) { return 4 }
    RETAINED.wake_by_ref()
    0
}
