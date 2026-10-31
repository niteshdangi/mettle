import alloc.vec

type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}

fn main(): i32 {
    var drops = 0
    {
        var values = vec.new<Counted>()
        values.push(Counted(core.ptr.from_mut(drops)))
        values.push(Counted(core.ptr.from_mut(drops)))
        match values.pop_if(fn(item: read Counted): bool { item.counter == core.ptr.null_mut<i32>() }) {
            present(_) => { return 1 },
            none => {}
        }
        if drops != 0 || values.len() != 2usize { return 2 }
        match values.pop_if(fn(item: read Counted): bool { item.counter != core.ptr.null_mut<i32>() }) {
            present(item) => { let _kept = item },
            none => { return 3 }
        }
        if drops != 0 || values.len() != 1usize { return 4 }
        match values.pop_if(fn(item: read Counted): bool { item.counter != core.ptr.null_mut<i32>() }) {
            none => { return 5 },
            present(_) => {}
        }
        if drops != 1 || values.len() != 0usize { return 6 }
        match values.pop_if(fn(item: read Counted): bool { item.counter != core.ptr.null_mut<i32>() }) {
            present(_) => { return 7 },
            none => {}
        }
    }
    if drops != 2 { return 8 }
    0
}
