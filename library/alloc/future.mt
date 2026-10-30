// Explicit heap erasure for owned futures. The dispatch table and allocation
// are private implementation details, not a stable ABI.
import super.alloc.Global;
import super.boxed;
import package.core.future.{Context, Future, Poll};

// Owns a single, permanently located future. Moving this handle does not
// move its payload. The constructor accepts only Static futures because the
// erased handle does not retain a source region.
pub type Erased<T> {
    data: ptr<mut u8>
    poll: fn(ptr<mut u8>, mut Context): Poll<T>
    release: fn(ptr<mut u8>): Unit
    drop { (self.release)(self.data) }
}

// Allocates once; no polling or body effects occur during construction.
pub fn erase<T, F: Future<Output = T> + Static>(future: take F): Erased<T> {
    let storage = boxed.new(future).into_raw()
    Erased(storage.0.cast<u8>(), poll_impl<T, F>, release_impl<F>)
}

fn poll_impl<T, F: Future<Output = T>>(data: ptr<mut u8>, cx: mut Context): Poll<T> {
    // The allocation remains owned by Erased even if poll unwinds. Its unique
    // payload is never moved and is destroyed there before the block is freed.
    unsafe { core.pin.Pin.new_unchecked(mut *data.cast<F>()).poll(mut cx) }
}

fn release_impl<F>(data: ptr<mut u8>): Unit {
    unsafe { let _owner = boxed.from_raw_in(data.cast<F>(), Global()) }
}

extend<T> Erased<T> implements Future {
    type Output = T
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<T> {
        let me = unsafe { self.get_unchecked_mut() }
        (me.poll)(me.data, mut cx)
    }
}
