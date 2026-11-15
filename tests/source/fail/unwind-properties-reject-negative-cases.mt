// expect-error: type 31:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 32:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 33:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 34:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 35:5 generic argument does not satisfy Unpin
// expect-error: type 36:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 37:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 38:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 39:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 40:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 41:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 42:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 57:5 unsatisfied interface bound 'Transferable'
// expect-error: type 58:5 unsatisfied interface bound 'Shareable'
// expect-error: type 59:5 generic argument does not satisfy Copy
// expect-error: type 60:5 generic argument does not satisfy Copy
// expect-error: type 64:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 65:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 66:5 unsatisfied interface bound 'UnwindSafe'
// expect-error: type 67:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error: type 68:5 unsatisfied interface bound 'RefUnwindSafe'
// expect-error-count: 21
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

fn reject_additional_view_properties() {
    unwind_safe<ptr<read core.cell.UnsafeCell<i32>>>()
    unwind_safe<mut i32>()
    unwind_safe<pinned mut i32>()
    ref_unwind_safe<mut core.cell.Cell<i32>>()
    ref_unwind_safe<pinned mut core.cell.Cell<i32>>()
}
