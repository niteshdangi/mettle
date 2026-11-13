// profiles: debug release
import alloc.alloc.{Allocator, Global, Layout, AllocError}
import core.clone.Clone
import core.convert.From
import core.iter.Iterator
import std.panic.CatchResult

type Stats { allocations: usize; live: usize; reject_size: usize; panic_free: bool; panic_at: usize }
copy type Tracking { stats: ptr<mut Stats> }

extend Tracking implements Clone {
    fn clone(): Tracking { Tracking(self.stats) }
}
unsafe extend Tracking implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { (*self.stats).panic_at } != 0usize &&
            unsafe { (*self.stats).allocations == (*self.stats).panic_at } {
            unsafe { (*self.stats).panic_at = 0usize }
            panic("allocate stop")
        }
        if unsafe { (*self.stats).reject_size } != 0usize &&
            layout.size() >= unsafe { (*self.stats).reject_size } {
            throw AllocError(layout.size(), layout.align())
        }
        var global = Global()
        let pointer = try global.allocate(layout)
        if layout.size() != 0usize {
            unsafe { (*self.stats).allocations += 1usize; (*self.stats).live += 1usize }
        }
        pointer
    }
    unsafe mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        if layout.size() != 0usize { unsafe { (*self.stats).live -= 1usize } }
        var global = Global()
        global.deallocate(pointer, layout)
        if unsafe { (*self.stats).panic_free } {
            unsafe { (*self.stats).panic_free = false }
            panic("free stop")
        }
    }
    unsafe mut fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        if unsafe { (*self.stats).reject_size } != 0usize &&
            size >= unsafe { (*self.stats).reject_size } { throw AllocError(size, old.align()) }
        var global = Global()
        let result = try global.grow(pointer, old, size)
        unsafe { (*self.stats).allocations += 1usize }
        result
    }
    unsafe mut fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.shrink(pointer, old, size)
    }
}

type CloneBomb {
    id: i32
    made: ptr<mut usize>
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}
extend CloneBomb implements Clone {
    fn clone(): CloneBomb {
        if self.id == 37 { panic("clone stop") }
        unsafe { *self.made += 1usize }
        CloneBomb(self.id + 0, self.made, self.drops)
    }
}

fn main(): i32 {
    var stats = Stats(0usize, 0usize, 0usize, false, 0usize)
    let state = core.ptr.from_mut(stats)
    {
        var exact = alloc.vec_deque.new_in<i32, Tracking>(Tracking(state))
        exact.reserve_exact(1usize)
        if exact.capacity() != 1usize || stats.allocations != 1usize { return 1 }
    }
    if stats.live != 0usize { return 2 }
    {
        var values = alloc.vec_deque.new_in<i32, Tracking>(Tracking(state))
        values.reserve_exact(4usize)
        values.push_back(1)
        values.push_back(2)
        values.push_back(3)
        values.push_back(4)
        let pointer = core.ptr.from_ref(*values.front().or_panic())
        let allocations = stats.allocations
        stats.reject_size = 36usize
        match capture values.try_reserve(5usize) {
            success(_) => { return 3 },
            failure(_) => {}
        }
        if values.capacity() != 4usize || stats.allocations != allocations ||
            core.ptr.from_ref(*values.front().or_panic()) != pointer { return 4 }
        stats.reject_size = 0usize
    }
    var capacity = 1usize
    while capacity <= 6usize {
        var head = 0usize
        while head < capacity {
            var length = 0usize
            while length <= capacity {
                var values = alloc.vec_deque.new_in<i32, Tracking>(Tracking(state))
                values.reserve_exact(capacity)
                var index = 0usize
                while index < capacity { values.push_back(index as i32); index += 1usize }
                index = 0usize
                while index < head {
                    let old = values.pop_front()
                    values.push_back((capacity + index) as i32)
                    index += 1usize
                }
                values.truncate(length)
                let allocations = stats.allocations
                stats.reject_size = capacity * 4usize
                {
                    let contiguous = values.make_contiguous()
                    if contiguous.len() != length { return 5 }
                    index = 0usize
                    while index < length {
                        if contiguous[index] != (head + index) as i32 { return 6 }
                        index += 1usize
                    }
                }
                if stats.allocations != allocations { return 7 }
                stats.reject_size = 0usize
                length += 1usize
            }
            head += 1usize
        }
        capacity += 1usize
    }
    if stats.live != 0usize { return 8 }
    {
        var values = alloc.vec_deque.new_in<i32, Tracking>(Tracking(state))
        values.reserve_exact(4usize)
        values.push_back(1)
        values.push_back(2)
        stats.panic_free = true
        let shrunk = std.panic.catch_panic(fn(): Unit { values.shrink_to_fit() })
        match take shrunk {
            CatchResult.Panicked(info) => { if info.message() != "free stop" { return 16 } },
            CatchResult.Returned(_) => { return 17 }
        }
        if values.capacity() != 2usize {
            unsafe { core.mem.forget(take values) }
            return 18
        }
        if values[0usize] != 1 || values[1usize] != 2 || stats.live != 1usize { return 19 }
        values.clear()
        stats.panic_free = true
        let emptied = std.panic.catch_panic(fn(): Unit { values.shrink_to_fit() })
        match take emptied {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 20 }
        }
        if values.capacity() != 0usize {
            unsafe { core.mem.forget(take values) }
            return 21
        }
        if stats.live != 0usize { return 22 }
    }
    {
        var values = alloc.hash_map.new_in<i32, i32, Tracking>(Tracking(state))
        let old = values.insert(1, 10)
        stats.panic_free = true
        let resized = std.panic.catch_panic(fn(): Unit { values.reserve(10usize) })
        match take resized {
            CatchResult.Panicked(info) => { if info.message() != "free stop" { return 23 } },
            CatchResult.Returned(_) => { return 24 }
        }
        if values.capacity() < 11usize {
            unsafe { core.mem.forget(take values) }
            return 25
        }
        if *values.get(1).or_panic() != 10 { return 26 }
        values.clear()
        stats.panic_free = true
        let emptied = std.panic.catch_panic(fn(): Unit { values.shrink_to_fit() })
        match take emptied {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 27 }
        }
        if values.capacity() != 0usize {
            unsafe { core.mem.forget(take values) }
            return 28
        }
        if values.get(1).is_present() { return 29 }
    }
    if stats.live != 0usize { return 30 }
    var zst = alloc.vec_deque.new<Unit>()
    match capture zst.try_reserve(0xffffffffffffffffusize) {
        success(_) => {},
        failure(_) => { return 9 }
    }
    zst.push_front(())
    zst.push_back(())
    zst.push_back(())
    if zst.len() != 3usize { return 10 }
    var converted = alloc.vec_deque.Deque<Unit>.(From<alloc.vec.List<Unit>>).from(alloc.vec.new<Unit>())
    converted.push_front(())
    converted.push_back(())
    converted.push_back(())
    if converted.len() != 3usize { return 11 }
    var made = 0usize
    var drops = 0usize
    {
        var tree = alloc.btree.new_in<i32, CloneBomb, Tracking>(Tracking(state))
        var key = 0
        while key < 60 {
            let old = tree.insert(key + 0, CloneBomb(key + 0, core.ptr.from_mut(made), core.ptr.from_mut(drops)))
            key += 1
        }
        let live = stats.live
        let cloned = std.panic.catch_panic(fn(): Unit { let cloned_tree = tree.clone() })
        match take cloned {
            CatchResult.Panicked(info) => { if info.message() != "clone stop" { return 12 } },
            CatchResult.Returned(_) => { return 13 }
        }
        if made == 0usize || drops != made || stats.live != live || tree.len() != 60usize { return 14 }
        stats.panic_at = stats.allocations + 1usize
        let allocation = std.panic.catch_panic(fn(): Unit { let cloned_tree = tree.clone() })
        match take allocation {
            CatchResult.Panicked(info) => { if info.message() != "allocate stop" { return 31 } },
            CatchResult.Returned(_) => { return 32 }
        }
        if drops != made || stats.live != live || tree.len() != 60usize { return 33 }
        tree.clear()
        if drops != made + 60usize || stats.live != 0usize { return 15 }
    }
    0
}
