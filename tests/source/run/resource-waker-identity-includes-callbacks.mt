import core.clone.Clone
import core.future.{RawWaker, RawWakerVTable, Waker}

static LEFT: core.sync.atomic.AtomicUsize = core.sync.atomic.AtomicUsize.new(0usize)
static RIGHT: core.sync.atomic.AtomicUsize = core.sync.atomic.AtomicUsize.new(0usize)

fn release(data: ptr<mut u8>): Unit {}
fn wake_left(data: ptr<mut u8>): Unit {
    let _ = LEFT.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
}
fn wake_right(data: ptr<mut u8>): Unit {
    let _ = RIGHT.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
}
fn clone_left(data: ptr<mut u8>): RawWaker { RawWaker(data, left_table()) }
fn clone_right(data: ptr<mut u8>): RawWaker { RawWaker(data, right_table()) }
fn left_table(): RawWakerVTable {
    RawWakerVTable(clone_left, wake_left, wake_left, release)
}
fn right_table(): RawWakerVTable {
    RawWakerVTable(clone_right, wake_right, wake_right, release)
}

fn main(): i32 {
    // Both tables use static atomic tasks and own no dynamically freed data.
    let left = unsafe { Waker.new(core.ptr.null_mut<u8>(), left_table()) }
    let right = unsafe { Waker.new(core.ptr.null_mut<u8>(), right_table()) }
    let duplicate = left.clone()
    if left.will_wake(read right) || !left.will_wake(read duplicate) { return 1 }
    left.wake_by_ref()
    right.wake_by_ref()
    if LEFT.load(core.sync.atomic.Ordering.SeqCst) != 1usize ||
        RIGHT.load(core.sync.atomic.Ordering.SeqCst) != 1usize {
        return 2
    }
    0
}
