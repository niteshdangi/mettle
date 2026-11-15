// expect-error: type 12:5 unsatisfied interface bound 'Shareable'
// expect-error: type 13:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 14:5 generic argument does not satisfy Unpin
import core.marker.Unpin
import core.panic.RefUnwindSafe

fn shareable<T: Shareable>() {}
fn ref_unwind_safe<T: RefUnwindSafe>() {}
fn unpin<T: Unpin>() {}

fn main(): i32 {
    shareable<core.marker.PhantomData<core.cell.UnsafeCell<i32>>>()
    ref_unwind_safe<core.marker.PhantomData<core.cell.UnsafeCell<i32>>>()
    unpin<core.marker.PhantomData<core.marker.PhantomPinned>>()
    0
}
