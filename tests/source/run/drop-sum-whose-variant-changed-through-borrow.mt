// A value whose variant changes through a `mut` borrow drops by its current
// variant, not by the variant it had when it was stored.
type Guard { p: ptr<mut i32>; drop { unsafe { *self.p = *self.p + 1 } } }
type Holder { inner: Guard? }
fn fill(slot: mut Guard?, p: ptr<mut i32>) { slot = present(Guard(p)) }
fn fill_field(holder: mut Holder, p: ptr<mut i32>) { holder.inner = present(Guard(p)) }
fn clear(slot: mut Guard?) { slot = none }

fn main(): i32 {
    var filled = 0
    { var o: Guard? = none; fill(mut o, core.ptr.from_mut(filled)) }
    if filled != 1 { return 1 }
    var nested = 0
    { var h = Holder(none); fill_field(mut h, core.ptr.from_mut(nested)) }
    if nested != 1 { return 2 }
    var cleared = 0
    {
        var o: Guard? = present(Guard(core.ptr.from_mut(cleared)))
        clear(mut o)
        if cleared != 1 { return 3 }
    }
    if cleared != 1 { return 4 }
    0
}
