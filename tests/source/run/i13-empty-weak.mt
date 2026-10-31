import alloc.arc
import alloc.boxed
import alloc.rc
import core.borrow.{AsRef, Borrow}
import core.clone.Clone
import core.convert.From
import core.default.Default

type DropCount { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }
@align(64) type Aligned { value: i32 }

fn make<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    let local = make<rc.Weak<i32>>()
    if local.strong_count() != 0usize || local.weak_count() != 0usize { return 1 }
    match take local.upgrade() { present(_) => { return 2 }, none => {} }
    let local_copy = local.clone()
    if local_copy.strong_count() != 0usize || local_copy.weak_count() != 0usize { return 3 }
    if !local.ptr_eq(local_copy) { return 4 }
    let local_raw = local.into_raw()
    let local = unsafe { rc.weak_from_raw(take local_raw) }
    if local.strong_count() != 0usize { return 5 }

    let shared = arc.Weak<i32>.new()
    if shared.strong_count() != 0usize || shared.weak_count() != 0usize { return 6 }
    match take shared.upgrade() { present(_) => { return 7 }, none => {} }
    let shared_copy = shared.clone()
    if shared_copy.strong_count() != 0usize || shared_copy.weak_count() != 0usize { return 8 }
    if !shared.ptr_eq(shared_copy) { return 9 }
    let shared_raw = shared.into_raw()
    let shared = unsafe { arc.weak_from_raw(take shared_raw) }
    if shared.strong_count() != 0usize { return 10 }

    var local_drops = 0
    var local_weak = rc.Weak<DropCount>.new()
    {
        let owner = rc.Rc<DropCount>.new(DropCount(core.ptr.from_mut(local_drops)))
        local_weak = owner.downgrade()
        let duplicate = local_weak.clone()
        if duplicate.strong_count() != 1usize || duplicate.weak_count() != 2usize { return 11 }
    }
    if local_drops != 1 { return 12 }
    match take local_weak.upgrade() { present(_) => { return 13 }, none => {} }

    var shared_drops = 0
    var shared_weak = arc.Weak<DropCount>.new()
    {
        let owner = arc.Arc<DropCount>.new(DropCount(core.ptr.from_mut(shared_drops)))
        shared_weak = owner.downgrade()
        let duplicate = shared_weak.clone()
        if duplicate.strong_count() != 1usize || duplicate.weak_count() != 2usize { return 14 }
    }
    if shared_drops != 1 { return 15 }
    match take shared_weak.upgrade() { present(_) => { return 16 }, none => {} }

    let boxed = boxed.Box<i32>.(Default).default()
    if boxed.(AsRef<i32>).as_ref() != 0 { return 17 }
    if boxed.(Borrow<i32>).borrow() != 0 { return 18 }
    let local_owner = rc.Rc<i32>.(Default).default()
    if local_owner.(AsRef<i32>).as_ref() != 0 { return 19 }
    if local_owner.(Borrow<i32>).borrow() != 0 { return 20 }
    let shared_owner = arc.Arc<i32>.(Default).default()
    if shared_owner.(AsRef<i32>).as_ref() != 0 { return 21 }
    if shared_owner.(Borrow<i32>).borrow() != 0 { return 22 }
    if boxed.Box<i32>.(From<i32>).`from`(31) != 31 { return 23 }
    if rc.Rc<i32>.(From<i32>).`from`(32).get() != 32 { return 24 }
    if arc.Arc<i32>.(From<i32>).`from`(33).get() != 33 { return 25 }

    let zero = boxed.Box<Unit>.new(())
    let _unit = zero.into_inner()
    let aligned = boxed.Box<Aligned>.new(Aligned(42))
    if aligned.as_ptr().addr() % core.mem.align_of<Aligned>() != 0usize { return 26 }
    0
}
