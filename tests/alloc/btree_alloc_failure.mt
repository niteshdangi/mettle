import alloc.alloc.{Allocator, Layout, AllocError, Global}

copy type Limited {
    budget: ptr<mut i32>
    live: ptr<mut i32>
}

extend Limited implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 {
            throw AllocError(layout.size(), layout.align())
        }
        unsafe { *self.budget -= 1 }
        unsafe { *self.live += 1 }
        let mut_global = Global()
        var g = mut_global
        try g.allocate(layout)
    }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe { *self.live -= 1 }
        var g = Global()
        g.deallocate(p, layout)
    }
    mut fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 {
            throw AllocError(new_size, old.align())
        }
        unsafe { *self.budget -= 1 }
        var g = Global()
        try g.grow(p, old, new_size)
    }
    mut fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var g = Global()
        try g.shrink(p, old, new_size)
    }
}

type Counted {
    drops: ptr<mut i32>
    id: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var root_budget = 0
    var root_live = 0
    var root_drops = 0
    let root_counter = core.ptr.from_mut(root_drops)
    {
        var map = alloc.btree.new_in<i32, Counted, Limited>(
            Limited(core.ptr.from_mut(root_budget), core.ptr.from_mut(root_live))
        )
        match capture map.try_insert(0 + 0, Counted(root_counter, 0)) {
            success(_) => { return 1 },
            failure(_) => {}
        }
        if map.len() != 0usize || root_drops != 1 { return 2 }
        root_budget = 64
        let old = map.insert(0 + 0, Counted(root_counter, 0))
        if map.len() != 1usize { return 3 }
        match map.get(0 + 0) {
            present(value) => { if value.id != 0 { return 4 } },
            none => { return 5 }
        }
    }
    if root_drops != 2 || root_live != 0 { return 6 }

    var leaf_budget = 1000
    var leaf_live = 0
    var leaf_drops = 0
    let leaf_counter = core.ptr.from_mut(leaf_drops)
    {
        var map = alloc.btree.new_in<i32, Counted, Limited>(
            Limited(core.ptr.from_mut(leaf_budget), core.ptr.from_mut(leaf_live))
        )
        var i = 0
        while i < 11 {
            let old = map.insert(i + 0, Counted(leaf_counter, i))
            i += 1
        }
        leaf_budget = 1
        match capture map.try_insert(11 + 0, Counted(leaf_counter, 11)) {
            success(_) => { return 7 },
            failure(_) => {}
        }
        if map.len() != 11usize || leaf_drops != 1 { return 8 }
        var expected = 0
        for entry in read map {
            if entry.key != expected || entry.value.id != expected { return 9 }
            expected += 1
        }
        if expected != 11 { return 10 }
        leaf_budget = 64
        let old = map.insert(11 + 0, Counted(leaf_counter, 11))
        expected = 0
        for entry in read map {
            if entry.key != expected || entry.value.id != expected { return 11 }
            expected += 1
        }
        if expected != 12 { return 12 }
    }
    if leaf_drops != 13 || leaf_live != 0 { return 13 }

    var internal_budget = 10000
    var internal_live = 0
    var internal_drops = 0
    let internal_counter = core.ptr.from_mut(internal_drops)
    {
        var map = alloc.btree.new_in<i32, Counted, Limited>(
            Limited(core.ptr.from_mut(internal_budget), core.ptr.from_mut(internal_live))
        )
        // 72 ascending keys leave the degree-6 root full; the next insert
        // must allocate a new internal level before changing the tree.
        var i = 0
        while i < 72 {
            let old = map.insert(i + 0, Counted(internal_counter, i))
            i += 1
        }
        internal_budget = 0
        match capture map.try_insert(72 + 0, Counted(internal_counter, 72)) {
            success(_) => { return 14 },
            failure(_) => {}
        }
        if map.len() != 72usize || internal_drops != 1 { return 15 }
        var expected = 0
        for entry in read map {
            if entry.key != expected || entry.value.id != expected { return 16 }
            expected += 1
        }
        if expected != 72 { return 17 }
        internal_budget = 64
        let old = map.insert(72 + 0, Counted(internal_counter, 72))
        expected = 0
        for entry in read map {
            if entry.key != expected || entry.value.id != expected { return 18 }
            expected += 1
        }
        if expected != 73 { return 19 }
    }
    if internal_drops != 74 || internal_live != 0 { return 20 }
    0
}
