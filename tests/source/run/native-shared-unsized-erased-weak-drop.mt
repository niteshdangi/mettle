import core.clone.Clone

interface Shape { fn area(): i32; }
type Circle {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}
extend Circle implements Shape { fn area(): i32 { 42 } }

fn main(): i32 {
    var dropped = 0
    let count = core.ptr.from_mut(dropped)
    let weak: weak any Shape = {
        let concrete: shared Circle = shared Circle(count)
        let owner: shared any Shape = concrete
        let duplicate = owner.clone()
        if duplicate.get().area() != 42 { return 1 }
        weak owner
    }
    if dropped != 1 || weak.strong_count() != 0usize { return 2 }
    match weak.upgrade() {
        none => {},
        present(_) => { return 3 }
    }

    let local: local weak any Shape = {
        let concrete: local shared Circle = local shared Circle(count)
        let owner: local shared any Shape = concrete
        weak owner
    }
    if dropped != 2 || local.strong_count() != 0usize { return 4 }
    match local.upgrade() {
        none => {},
        present(_) => { return 5 }
    }
    0
}
