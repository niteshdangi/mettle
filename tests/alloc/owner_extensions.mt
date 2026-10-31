import core.clone.Clone

type RcCycle { pub link: alloc.rc.Weak<RcCycle> }
type ArcCycle { pub link: alloc.arc.Weak<ArcCycle> }

fn main(): i32 {
    var boxed = alloc.boxed.new_uninit<i32>()
    let _written = boxed.get_mut().write(42)
    let initialized = unsafe { boxed.assume_init() }
    if *initialized.get() != 42 { return 1 }
    let raw_box = initialized.into_raw()
    let rebuilt_box = unsafe { alloc.boxed.from_raw(raw_box.0) }
    if *rebuilt_box.get() != 42 { return 2 }

    var zero_box = alloc.boxed.new_zeroed<i32>()
    let initialized_zero = unsafe { zero_box.assume_init() }
    if *initialized_zero.get() != 0 { return 3 }
    let leaked = alloc.boxed.new(17).leak()
    if unsafe { *leaked } != 17 { return 4 }

    var rc_uninit = alloc.rc.new_uninit<i32>()
    match take rc_uninit.get_mut() {
        present(slot) => { let _rc_written = slot.write(33) },
        none => { return 23 }
    }
    let rc_initialized = unsafe { rc_uninit.assume_init() }
    if *rc_initialized.get() != 33 { return 5 }
    var rc_zero = alloc.rc.new_zeroed<i32>()
    let rc_zero_initialized = unsafe { rc_zero.assume_init() }
    if *rc_zero_initialized.get() != 0 { return 6 }

    var rc = alloc.rc.new(10)
    var rc_other = rc.clone()
    {
        let value = rc.make_mut()
        *value = 11
    }
    if *rc.get() != 11 || *rc_other.get() != 10 { return 7 }
    if rc_other.unwrap_or_clone() != 10 { return 8 }
    let raw_rc = rc.into_raw()
    let second_raw_rc = unsafe { alloc.rc.increment_strong_count(read raw_rc) }
    unsafe { alloc.rc.decrement_strong_count(second_raw_rc) }
    let rebuilt_rc = unsafe { alloc.rc.from_raw(raw_rc) }
    if *rebuilt_rc.get() != 11 { return 9 }
    let raw_rc_weak = rebuilt_rc.downgrade().into_raw()
    let rebuilt_rc_weak = unsafe { alloc.rc.weak_from_raw(raw_rc_weak) }
    match rebuilt_rc_weak.upgrade() {
        present(owner) => { if *owner.get() != 11 { return 10 } },
        none => { return 11 }
    }
    let cyclic_rc = alloc.rc.new_cyclic<RcCycle>(
        take fn(w: read alloc.rc.Weak<RcCycle>): RcCycle { RcCycle(w.retain()) }
    )
    match cyclic_rc.get().link.upgrade() {
        present(owner) => { if !owner.ptr_eq(cyclic_rc) { return 12 } },
        none => { return 13 }
    }

    var arc_uninit = alloc.arc.new_uninit<i32>()
    match take arc_uninit.get_mut() {
        present(slot) => { let _arc_written = slot.write(55) },
        none => { return 24 }
    }
    let arc_initialized = unsafe { arc_uninit.assume_init() }
    if *arc_initialized.get() != 55 { return 14 }
    var arc_zero = alloc.arc.new_zeroed<i32>()
    let arc_zero_initialized = unsafe { arc_zero.assume_init() }
    if *arc_zero_initialized.get() != 0 { return 15 }

    var arc = alloc.arc.new(20)
    var arc_other = arc.clone()
    {
        let value = arc.make_mut()
        *value = 21
    }
    if *arc.get() != 21 || *arc_other.get() != 20 { return 16 }
    if arc_other.unwrap_or_clone() != 20 { return 17 }
    let raw_arc = arc.into_raw()
    let second_raw_arc = unsafe { alloc.arc.increment_strong_count(read raw_arc) }
    unsafe { alloc.arc.decrement_strong_count(second_raw_arc) }
    let rebuilt_arc = unsafe { alloc.arc.from_raw(raw_arc) }
    if *rebuilt_arc.get() != 21 { return 18 }
    let raw_arc_weak = rebuilt_arc.downgrade().into_raw()
    let rebuilt_arc_weak = unsafe { alloc.arc.weak_from_raw(raw_arc_weak) }
    match rebuilt_arc_weak.upgrade() {
        present(owner) => { if *owner.get() != 21 { return 19 } },
        none => { return 20 }
    }
    let cyclic_arc = alloc.arc.new_cyclic<ArcCycle>(
        take fn(w: read alloc.arc.Weak<ArcCycle>): ArcCycle { ArcCycle(w.retain()) }
    )
    match cyclic_arc.get().link.upgrade() {
        present(owner) => { if !owner.ptr_eq(cyclic_arc) { return 21 } },
        none => { return 22 }
    }
    0
}
