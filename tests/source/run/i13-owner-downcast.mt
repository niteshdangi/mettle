import alloc.arc
import alloc.rc
import core.any.Any

type DropCount { counter: ptr<mut i32>; value: i32; drop { unsafe { *self.counter += 1 } } }
type Other { value: i32 }

// Successful downcasts keep the single owner; mismatches hand it back
// unchanged, and the payload drops exactly once in each case.
fn main(): i32 {
    var box_drops = 0
    {
        let erased: heap any Any = heap DropCount(core.ptr.from_mut(box_drops), 7)
        let wrong = capture erased.downcast<Other>()
        let erased = match take wrong {
            success(_) => { return 1 },
            failure(owner) => owner
        }
        if box_drops != 0 { return 2 }
        let right = capture erased.downcast<DropCount>()
        match take right {
            success(owner) => { if owner.get().value != 7 { return 3 } },
            failure(_) => { return 4 }
        }
    }
    if box_drops != 1 { return 5 }

    var rc_drops = 0
    {
        let erased: rc.Rc<any Any> = rc.new(DropCount(core.ptr.from_mut(rc_drops), 8))
        let second = erased.retain()
        let wrong = capture erased.downcast<Other>()
        let erased = match take wrong {
            success(_) => { return 6 },
            failure(owner) => owner
        }
        if erased.strong_count() != 2usize { return 7 }
        let right = capture second.downcast<DropCount>()
        match take right {
            success(owner) => {
                if owner.get().value != 8 || owner.strong_count() != 2usize { return 8 }
            },
            failure(_) => { return 9 }
        }
        if rc_drops != 0 { return 10 }
    }
    if rc_drops != 1 { return 11 }

    var arc_drops = 0
    {
        let erased: arc.Arc<any Any> = arc.new(DropCount(core.ptr.from_mut(arc_drops), 9))
        let wrong = capture erased.downcast<Other>()
        let erased = match take wrong {
            success(_) => { return 12 },
            failure(owner) => owner
        }
        let right = capture erased.downcast<DropCount>()
        match take right {
            success(owner) => { if owner.get().value != 9 { return 13 } },
            failure(_) => { return 14 }
        }
    }
    if arc_drops != 1 { return 15 }
    0
}
