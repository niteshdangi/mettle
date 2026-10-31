import core.clone.Clone

type Item {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}

fn main(): i32 {
    var dropped = 0
    let count = core.ptr.from_mut(dropped)
    let observer: weak [Item] = {
        let concrete: shared [Item; 2] = shared [Item(count), Item(count)]
        let owner: shared [Item] = concrete
        let duplicate = owner.clone()
        if owner.strong_count() != 2usize || duplicate.get().len() != 2usize {
            return 1
        }
        weak owner
    }
    if dropped != 2 || observer.strong_count() != 0usize { return 2 }
    match observer.upgrade() {
        none => {},
        present(_) => { return 3 }
    }

    let counted: local weak [i32] = {
        let concrete: local shared [i32; 3] = local shared [4, 5, 6]
        let owner: local shared [i32] = concrete
        weak owner
    }
    if counted.strong_count() != 0usize { return 4 }
    match counted.upgrade() {
        none => {},
        present(_) => { return 5 }
    }
    0
}
