import alloc.arc
import alloc.rc
import core.any.Any

type Marker {}
type Other { value: i32 }
@align(64) type Aligned { counter: ptr<mut i32>; value: i32; drop { unsafe { *self.counter += 1 } } }

// Zero-sized and over-aligned payloads keep their dangling or aligned pointer
// across a downcast, and a mismatch hands the same owner back.
fn main(): i32 {
    {
        let erased: heap any Any = heap Marker()
        let wrong = capture erased.downcast<Other>()
        let erased = match take wrong {
            success(_) => { return 1 },
            failure(owner) => owner
        }
        let right = capture erased.downcast<Marker>()
        match take right {
            success(owner) => { if owner.as_ptr().addr() % core.mem.align_of<Marker>() != 0usize { return 2 } },
            failure(_) => { return 3 }
        }
    }
    {
        let erased: rc.Rc<any Any> = rc.new(Marker())
        let right = capture erased.downcast<Marker>()
        match take right {
            success(owner) => { if owner.strong_count() != 1usize { return 4 } },
            failure(_) => { return 5 }
        }
    }
    {
        let erased: arc.Arc<any Any> = arc.new(Marker())
        let wrong = capture erased.downcast<Other>()
        match take wrong {
            success(_) => { return 6 },
            failure(owner) => { if owner.strong_count() != 1usize { return 7 } }
        }
    }

    var drops = 0
    {
        let erased: heap any Any = heap Aligned(core.ptr.from_mut(drops), 5)
        let right = capture erased.downcast<Aligned>()
        match take right {
            success(owner) => {
                if owner.as_ptr().addr() % 64usize != 0usize || owner.get().value != 5 { return 8 }
            },
            failure(_) => { return 9 }
        }
    }
    if drops != 1 { return 10 }
    {
        let erased: rc.Rc<any Any> = rc.new(Aligned(core.ptr.from_mut(drops), 6))
        let right = capture erased.downcast<Aligned>()
        match take right {
            success(owner) => {
                if owner.as_ptr().addr() % 64usize != 0usize || owner.get().value != 6 { return 11 }
            },
            failure(_) => { return 12 }
        }
    }
    if drops != 2 { return 13 }
    {
        let erased: arc.Arc<any Any> = arc.new(Aligned(core.ptr.from_mut(drops), 7))
        let right = capture erased.downcast<Aligned>()
        match take right {
            success(owner) => {
                if owner.as_ptr().addr() % 64usize != 0usize || owner.get().value != 7 { return 14 }
            },
            failure(_) => { return 15 }
        }
    }
    if drops != 3 { return 16 }
    0
}
