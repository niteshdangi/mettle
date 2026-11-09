import alloc.btree.Entry

type Counted {
    drops: ptr<mut i32>
    id: i32
    drop { unsafe { *self.drops += 1 } }
}

fn exercise(counter: ptr<mut i32>, call_counter: ptr<mut i32>): i32 {
    var map = alloc.btree.new<i32, Counted>()
    {
        let value = map.entry(4 + 0).or_insert(Counted(counter, 4))
        if value.id != 4 { return 1 }
    }
    {
        let value = map.entry(2 + 0).or_insert_with(take fn(): Counted {
            unsafe { *call_counter += 1 }
            Counted(counter, 2)
        })
        if value.id != 2 { return 2 }
    }
    {
        let value = map.entry(4 + 0).and_modify(take fn(mut value: Counted): Unit {
            value.id += 40
        }).or_insert_with(take fn(): Counted {
            unsafe { *call_counter += 100 }
            Counted(counter, 99)
        })
        if value.id != 44 { return 3 }
    }
    if unsafe { *call_counter } != 1 { return 4 }
    {
        match take map.entry(4 + 0) {
            Entry.Occupied(entry) => {
                var occupied = entry
                if *occupied.key() != 4 || occupied.get().id != 44 { return 5 }
                occupied.get_mut().id += 1
                let old = occupied.insert(Counted(counter, 40))
                if old.id != 45 { return 6 }
                let removed = occupied.remove()
                if removed.id != 40 { return 7 }
            },
            Entry.Vacant(_) => { return 8 }
        }
    }
    if map.contains_key(4 + 0) { return 9 }
    {
        match take map.entry(9 + 0) {
            Entry.Occupied(_) => { return 10 },
            Entry.Vacant(entry) => {
                if *entry.key() != 9 { return 11 }
                let value = entry.insert(Counted(counter, 9))
                if value.id != 9 { return 12 }
            }
        }
    }
    {
        match take map.entry(2 + 0) {
            Entry.Occupied(entry) => {
                let value = entry.into_mut()
                value.id += 20
            },
            Entry.Vacant(_) => { return 13 }
        }
    }
    var expected = 2
    for entry in read map {
        if entry.key != expected { return 14 }
        if expected == 2 {
            if entry.value.id != 22 { return 15 }
            expected = 9
        } else {
            if entry.value.id != 9 { return 16 }
            expected = 10
        }
    }
    if expected != 10 { return 17 }
    if unsafe { *counter } != 2 { return 18 }
    0
}

fn main(): i32 {
    var drops = 0
    var calls = 0
    let result = exercise(core.ptr.from_mut(drops), core.ptr.from_mut(calls))
    if result != 0 { return result }
    if drops != 4 { return 19 }
    0
}
