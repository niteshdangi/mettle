import alloc::rc::{Rc, Weak};
type D { c: ptr<mut i32>
    drop { unsafe { *self.c += 1 } } }
fn main(): i32 {
    var n = 0
    let cp = core::ptr::from_mut(n)
    var w: Weak<D>? = none
    {
        let a = alloc::rc::new(D(cp))
        let b = a.retain()
        if a.strong_count() != 2usize || a.weak_count() != 0usize { return 90 }
        w = present(a.downgrade())
        if a.weak_count() != 1usize { return 91 }
        match w { present(ww) => { match ww.upgrade() { present(_) => {}, none => { return 92 } } }, none => { return 93 } }
        if n != 0 { return 94 }
    }
    if n != 1 { return 95 }
    match w { present(ww) => { match ww.upgrade() { present(_) => { return 96 }, none => {} } }, none => { return 97 } }
    let u = alloc::rc::new(D(cp))
    let q = u.retain()
    let r = capture u.try_unwrap()
    match take r { success(_) => { return 98 }, failure(back) => { if back.strong_count() != 2usize { return 99 } } }
    drop_check(cp)
}
fn drop_check(cp: ptr<mut i32>): i32 {
    let s = alloc::rc::new(D(cp))
    match capture s.try_unwrap() { success(d) => {}, failure(_) => { return 100 } }
    0
}
