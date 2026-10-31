import alloc.alloc.{Allocator, Layout, AllocError, Global, layout_unchecked}
import alloc.vec.List
import core.clone.Clone

// Allocator that fails once the shared budget of successful allocations runs out.
copy type Limited {
    budget: ptr<mut i32>
    live: ptr<mut i32>
    alignment_errors: ptr<mut i32>
}

type Retained {
    drops: ptr<mut i32>
    id: i32
    drop { unsafe { *self.drops += 1 } }
}

// Heap insertion needs an ordering; only the id participates.
extend Retained implements core.cmp.PartialEq {
    fn eq(other: read Retained): bool { self.id == other.id }
}
extend Retained implements core.cmp.Eq {}
extend Retained implements core.cmp.PartialOrd {
    fn partial_cmp(other: read Retained): core.cmp.Ordering? { present(self.id.cmp(read other.id)) }
}
extend Retained implements core.cmp.Ord {
    fn cmp(other: read Retained): core.cmp.Ordering { self.id.cmp(read other.id) }
}

extend Limited implements package.core.clone.Clone {
    fn clone(): Limited {
        Limited(self.budget, self.live, self.alignment_errors)
    }
}

fn check_zero_layout(): bool throws AllocError {
    var global = Global()
    // Both layouts use a power-of-two alignment and fit the target size bound.
    let zero = unsafe { layout_unchecked(0usize, 16usize) }
    let empty = try global.allocate(zero)
    if empty.addr() % 16usize != 0usize { return false }
    global.deallocate(empty, zero)
    let grown = try global.grow(empty, zero, 16usize)
    if grown.addr() % 16usize != 0usize { return false }
    let full = unsafe { layout_unchecked(16usize, 16usize) }
    let empty_from_grow = try global.grow(grown, full, 0usize)
    if empty_from_grow.addr() % 16usize != 0usize { return false }
    let grown_again = try global.grow(empty, zero, 16usize)
    let empty_again = try global.shrink(grown_again, full, 0usize)
    empty_again.addr() % 16usize == 0usize
}

extend Limited implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 { throw AllocError(layout.size(), layout.align()) }
        unsafe { *self.budget -= 1 }
        unsafe { *self.live += 1 }
        let mut_global = Global()
        var g = mut_global
        let p = try g.allocate(layout)
        if p.addr() % layout.align() != 0usize {
            unsafe { *self.alignment_errors += 1 }
        }
        p
    }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe { *self.live -= 1 }
        var g = Global()
        g.deallocate(p, layout)
    }
    mut fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 { throw AllocError(new_size, old.align()) }
        unsafe { *self.budget -= 1 }
        var g = Global()
        let q = try g.grow(p, old, new_size)
        if old.size() == 0usize && new_size != 0usize {
            unsafe { *self.live += 1 }
        } else if old.size() != 0usize && new_size == 0usize {
            unsafe { *self.live -= 1 }
        }
        if q.addr() % old.align() != 0usize {
            unsafe { *self.alignment_errors += 1 }
        }
        q
    }
    mut fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var g = Global()
        let q = try g.shrink(p, old, new_size)
        if old.size() != 0usize && new_size == 0usize {
            unsafe { *self.live -= 1 }
        }
        if new_size != 0usize && q.addr() % old.align() != 0usize {
            unsafe { *self.alignment_errors += 1 }
        }
        q
    }
}

fn main(): i32 {
    var budget = 3
    var live = 0
    var alignment_errors = 0
    let a = Limited(core.ptr.from_mut(budget), core.ptr.from_mut(live),
                    core.ptr.from_mut(alignment_errors))
    {
        var v = alloc.vec.new_in<i32, Limited>(a)
        var i = 0
        var failed = 0
        while i < 1000 {
            match capture v.try_push(i + 0) {
                success(_) => {},
                failure(_) => { failed += 1; break }
            }
            i += 1
        }
        if failed != 1 || v.len() == 0usize { return 1 }
        let kept = v.len()
        match capture v.try_reserve(1000000usize) { success(_) => { return 2 }, failure(_) => {} }
        if v.len() != kept { return 3 }
        var j = 0usize
        while j < kept { if v[j] != (j as i32) { return 4 }; j += 1usize }
    }
    if live != 0 { return 5 }

    var budget2 = 0
    var live2 = 0
    let b = Limited(core.ptr.from_mut(budget2), core.ptr.from_mut(live2),
                    core.ptr.from_mut(alignment_errors))
    match capture alloc.boxed.try_new_in(5, b.clone()) {
        success(_) => { return 6 },
        failure(_) => {}
    }
    match capture alloc.boxed.try_new_uninit_in<i32, Limited>(b.clone()) {
        success(_) => { return 33 },
        failure(_) => {}
    }
    match capture alloc.boxed.try_new_zeroed_in<i32, Limited>(b.clone()) {
        success(_) => { return 34 },
        failure(_) => {}
    }
    match capture alloc.rc.try_new_uninit_in<i32, Limited>(b.clone()) {
        success(_) => { return 35 },
        failure(_) => {}
    }
    match capture alloc.rc.try_new_zeroed_in<i32, Limited>(b.clone()) {
        success(_) => { return 36 },
        failure(_) => {}
    }
    match capture alloc.rc.try_new_cyclic_in<i32, Limited>(
        b.clone(), take fn(w: read alloc.rc.Weak<i32, Limited>): i32 { 1 }
    ) {
        success(_) => { return 37 },
        failure(_) => {}
    }
    match capture alloc.arc.try_new_uninit_in<i32, Limited>(b.clone()) {
        success(_) => { return 38 },
        failure(_) => {}
    }
    match capture alloc.arc.try_new_zeroed_in<i32, Limited>(b.clone()) {
        success(_) => { return 39 },
        failure(_) => {}
    }
    match capture alloc.arc.try_new_cyclic_in<i32, Limited>(
        b.clone(), take fn(w: read alloc.arc.Weak<i32, Limited>): i32 { 1 }
    ) {
        success(_) => { return 40 },
        failure(_) => {}
    }
    if live2 != 0 { return 41 }
    var m = alloc.hash_map.new_in<i32, i32, Limited>(
        Limited(core.ptr.from_mut(budget2), core.ptr.from_mut(live2),
                core.ptr.from_mut(alignment_errors))
    )
    match capture m.try_insert(1, 2) { success(_) => { return 7 }, failure(_) => {} }
    if m.len() != 0usize { return 8 }

    var budget3 = 0
    var live3 = 0
    var retained_drops = 0
    {
        var v = alloc.vec.new_in<Retained, Limited>(
            Limited(core.ptr.from_mut(budget3), core.ptr.from_mut(live3),
                    core.ptr.from_mut(alignment_errors))
        )
        match capture v.try_push(Retained(core.ptr.from_mut(retained_drops), 42)) {
            success(_) => { return 9 },
            failure(error) => {
                if error.value.id != 42 || retained_drops != 0 { return 10 }
            }
        }
        if retained_drops != 1 { return 11 }
    }
    if live3 != 0 { return 12 }
    if alignment_errors != 0 { return 13 }

    var push_drops = 0
    {
        var deque = alloc.vec_deque.new_in<Retained, Limited>(
            Limited(core.ptr.from_mut(budget3), core.ptr.from_mut(live3),
                    core.ptr.from_mut(alignment_errors))
        )
        match capture deque.try_push_back(Retained(core.ptr.from_mut(push_drops), 43)) {
            success(_) => { return 19 },
            failure(error) => {
                if error.value.id != 43 || push_drops != 0 { return 20 }
            }
        }
    }
    if push_drops != 1 { return 21 }
    push_drops = 0
    {
        var list = alloc.linked_list.new_in<Retained, Limited>(
            Limited(core.ptr.from_mut(budget3), core.ptr.from_mut(live3),
                    core.ptr.from_mut(alignment_errors))
        )
        match capture list.try_push_front(Retained(core.ptr.from_mut(push_drops), 44)) {
            success(_) => { return 22 },
            failure(error) => {
                if error.value.id != 44 || push_drops != 0 { return 23 }
            }
        }
    }
    if push_drops != 1 { return 24 }
    push_drops = 0
    {
        var queue = alloc.binary_heap.new_in<Retained, Limited>(
            Limited(core.ptr.from_mut(budget3), core.ptr.from_mut(live3),
                    core.ptr.from_mut(alignment_errors))
        )
        match capture queue.try_push(Retained(core.ptr.from_mut(push_drops), 45)) {
            success(_) => { return 25 },
            failure(error) => {
                if error.value.id != 45 || push_drops != 0 { return 26 }
            }
        }
    }
    if push_drops != 1 { return 27 }
    if live3 != 0 { return 28 }

    var budget4 = 100
    var live4 = 0
    {
        var text = alloc.string.with_capacity_in(
            8usize,
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        text.push_str("owner")
    }
    {
        var deque = alloc.vec_deque.new_in<i32, Limited>(
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        deque.push_back(1)
    }
    {
        var list = alloc.linked_list.new_in<i32, Limited>(
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        list.push_back(1)
    }
    {
        var queue = alloc.binary_heap.with_capacity_in<i32, Limited>(
            4usize,
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        queue.push(1)
    }
    var weak_owner: alloc.arc.Weak<i32, Limited>? = none
    {
        let owner = alloc.arc.new_in(
            1,
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        weak_owner = present(owner.downgrade())
    }
    if live4 != 1 { return 29 }
    weak_owner = none
    if live4 != 0 { return 30 }
    {
        var map = alloc.hash_map.new_in<i32, i32, Limited>(
            Limited(core.ptr.from_mut(budget4), core.ptr.from_mut(live4),
                    core.ptr.from_mut(alignment_errors))
        )
        let previous = map.insert(1, 2)
    }
    if live4 != 0 { return 14 }
    if alignment_errors != 0 { return 15 }

    match capture check_zero_layout() {
        success(aligned) => { if !aligned { return 16 } },
        failure(_) => { return 17 }
    }
    0
}
