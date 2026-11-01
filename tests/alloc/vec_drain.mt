type DropCount {
    counter: ptr<mut i32>
    id: i32
    drop { unsafe { *self.counter += 1 } }
}

fn main(): i32 {
    var values = alloc.vec.new<i32>()
    var i = 0
    while i < 6 {
        values.push(i + 0)
        i += 1
    }
    {
        var removed = values.drain(1usize..5usize)
        match removed.next() {
            present(value) => { if value != 1 { return 1 } },
            none => { return 2 }
        }
        match removed.next_back() {
            present(value) => { if value != 4 { return 3 } },
            none => { return 4 }
        }
    }
    if values.len() != 2usize || values[0usize] != 0 || values[1usize] != 5 {
        return 5
    }

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var owned = alloc.vec.new<DropCount>()
        owned.push(DropCount(counter, 0))
        owned.push(DropCount(counter, 1))
        owned.push(DropCount(counter, 2))
        owned.push(DropCount(counter, 3))
        owned.push(DropCount(counter, 4))
        {
            var removed = owned.drain(1usize..4usize)
            match removed.next() {
                present(value) => { if value.id != 1 { return 6 } },
                none => { return 7 }
            }
        }
        if drops != 3 || owned.len() != 2usize { return 8 }
        if owned[0usize].id != 0 || owned[1usize].id != 4 { return 9 }
    }
    if drops != 5 { return 10 }
    0
}
