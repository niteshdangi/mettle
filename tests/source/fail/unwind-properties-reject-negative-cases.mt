// expect-error: type 26:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 27:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 28:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 29:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 30:5 generic argument does not satisfy Unpin
// expect-error: type 31:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 32:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 33:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 34:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 35:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 36:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 37:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 52:5 unsatisfied interface bound 'Transferable'
// expect-error: type 53:5 unsatisfied interface bound 'Shareable'
// expect-error: type 54:5 generic argument does not satisfy Copy
// expect-error: type 55:5 generic argument does not satisfy Copy
// expect-error-count: 16
import core.marker.Unpin
import core.panic.{RefUnwindSafe, UnwindSafe}

fn unwind_safe<T: UnwindSafe>() {}
fn ref_unwind_safe<T: RefUnwindSafe>() {}
fn unpin<T: Unpin>() {}

fn main(): i32 {
    unwind_safe<core.cell.RefMut<i32>>()
    ref_unwind_safe<core.cell.Cell<i32>>()
    unwind_safe<std.io.Error>()
    ref_unwind_safe<std.io.Error>()
    unpin<core.marker.PhantomPinned>()
    unwind_safe<ptr<mut core.cell.Cell<i32>>>()
    ref_unwind_safe<core.marker.PhantomData<core.cell.Cell<i32>>>()
    ref_unwind_safe<read core.cell.Cell<i32> from static>()
    ref_unwind_safe<mut core.cell.Cell<i32> from static>()
    ref_unwind_safe<ptr<read core.cell.Cell<i32>>>()
    ref_unwind_safe<ptr<mut core.cell.Cell<i32>>>()
    unwind_safe<mut i32 from static>()
    0
}

type NotTransferable {}
extend NotTransferable not Transferable
type NotShareable {}
extend NotShareable not Shareable
type NonCopy { value: i32 }

fn transferable<T: Transferable>() {}
fn shareable<T: Shareable>() {}
fn require_copy<T: Copy>() {}

fn reject_conditional_properties() {
    transferable<core.marker.PhantomData<NotTransferable>>()
    shareable<core.marker.PhantomData<NotShareable>>()
    require_copy<std.sync.mpsc.SendError<NonCopy>>()
    require_copy<std.sync.mpsc.TrySendError<NonCopy>>()
}
