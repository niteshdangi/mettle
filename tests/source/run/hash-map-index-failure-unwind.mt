import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.hash_map
import std.panic.{catch_panic, CatchResult}
import core.hash.{Hash, Hasher}

type State {
    calls: i32
    fail_at: i32
    live: i32
    drops: i32
    panic_drop: bool
    panic_deallocate: bool
    panic_hash: i32
}

type HashKey { number: i32; state: ptr<mut State> }
extend HashKey implements PartialEq {
    fn eq(read other: HashKey): bool { self.number == other.number }
}
extend HashKey implements Hash {
    fn hash<H: Hasher>(mut hasher: H): Unit {
        unsafe {
            if (*self.state).panic_hash > 0 {
                (*self.state).panic_hash -= 1
                if (*self.state).panic_hash == 0 { panic("map rehash") }
            }
        }
        self.number.hash(mut hasher)
    }
}

copy type FailingAllocator { state: ptr<mut State> }
unsafe extend FailingAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.state).calls += 1
            if (*self.state).calls == (*self.state).fail_at {
                throw AllocError(layout.size(), layout.align())
            }
        }
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe { (*self.state).live += 1 }
        pointer
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        let should_panic = unsafe { (*self.state).panic_deallocate }
        var global = Global()
        unsafe {
            (*self.state).panic_deallocate = false
            global.deallocate(pointer, layout)
            (*self.state).live -= 1
        }
        if should_panic { panic("map deallocation") }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.state).calls += 1
            if (*self.state).calls == (*self.state).fail_at {
                throw AllocError(size, old.align())
            }
        }
        var global = Global()
        unsafe { try global.grow(pointer, old, size) }
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.shrink(pointer, old, size) }
    }
}

type Value {
    number: i32
    state: ptr<mut State>
    drop {
        unsafe {
            (*self.state).drops += 1
            if (*self.state).panic_drop {
                (*self.state).panic_drop = false
                panic("map value drop")
            }
        }
    }
}

fn main(): i32 {
    var state = State(0, 0, 0, 0, false, false, 0)
    let pointer = core.ptr.from_mut(state)
    {
        var map = hash_map.new_in<i32, Value, FailingAllocator>(FailingAllocator(pointer))
        var key = 0
        while key < 6 {
            map.insert(key + 0, Value(key * 10, pointer))
            key += 1
        }
        let capacity = map.capacity()
        let live = state.live
        state.fail_at = state.calls + 1
        match capture map.try_reserve(100usize) {
            success(_) => { return 1 },
            failure(_) => {}
        }
        state.fail_at = state.calls + 2
        match capture map.try_reserve(100usize) {
            success(_) => { return 2 },
            failure(_) => {}
        }
        state.fail_at = state.calls + 3
        match capture map.try_reserve(100usize) {
            success(_) => { return 16 },
            failure(_) => {}
        }
        state.fail_at = 0
        if state.live != live || map.capacity() != capacity || map.len() != 6usize { return 3 }
        key = 0
        while key < 6 {
            if map.get(key).or_panic().number != key * 10 { return 4 }
            key += 1
        }

        var calls = 0
        var removed = 0
        let calls_pointer = core.ptr.from_mut(calls)
        let removed_pointer = core.ptr.from_mut(removed)
        match take catch_panic(fn(): Unit {
            map.retain(fn(read key: i32, mut value: Value): bool {
                unsafe { *calls_pointer += 1 }
                if unsafe { *calls_pointer } == 3 { panic("map predicate") }
                let keep = key % 2 != 0
                if !keep { unsafe { *removed_pointer += 1 } }
                keep
            })
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 5 }
        }
        if calls != 3 || map.len() != 6usize - removed as usize { return 6 }
        var found = 0
        key = 0
        while key < 6 {
            match map.get(key) {
                present(value) => {
                    if value.number != key * 10 { return 7 }
                    found += 1
                },
                none => {}
            }
            key += 1
        }
        if found as usize != map.len() { return 8 }
        state.panic_drop = true
        match take catch_panic(fn(): Unit { map.clear() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 9 }
        }
        if !map.is_empty() || map.get(1).is_present() || state.drops != 6 { return 10 }
        map.insert(9, Value(90, pointer))
        map.insert(10, Value(100, pointer))
        state.panic_drop = true
        match take catch_panic(fn(): Unit { let remaining = map.drain() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 21 }
        }
        if !map.is_empty() || state.drops != 8 { return 22 }
        map.insert(7, Value(70, pointer))
        if map.get(7).or_panic().number != 70 { return 11 }
        map.clear()
        state.panic_deallocate = true
        match take catch_panic(fn(): Unit { map.shrink_to(0usize) }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 12 }
        }
        if !map.is_empty() || map.capacity() != 0usize { return 13 }
        map.insert(8, Value(80, pointer))
        if map.get(8).or_panic().number != 80 { return 14 }
    }
    if state.live != 0 || state.drops != 10 { return 15 }
    match take catch_panic(fn(): Unit {
        var doomed = hash_map.new_in<i32, Value, FailingAllocator>(FailingAllocator(pointer))
        doomed.insert(1, Value(10, pointer))
        doomed.insert(2, Value(20, pointer))
        unsafe { (*pointer).panic_drop = true }
    }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 23 }
    }
    if state.live != 0 || state.drops != 12 { return 24 }
    {
        var map = hash_map.new_in<HashKey, Value, FailingAllocator>(FailingAllocator(pointer))
        var i = 0
        while i < 6 {
            map.insert(HashKey(i, pointer), Value(i * 10, pointer))
            i += 1
        }
        let capacity = map.capacity()
        let live = state.live
        state.panic_hash = 3
        match take catch_panic(fn(): Unit { map.reserve(100usize) }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 17 }
        }
        if map.len() != 6usize || map.capacity() != capacity || state.live != live || state.drops != 12 { return 18 }
        i = 0
        while i < 6 {
            if map.get(HashKey(i, pointer)).or_panic().number != i * 10 { return 19 }
            i += 1
        }
        map.insert(HashKey(6, pointer), Value(60, pointer))
        state.panic_hash = 4
        match take catch_panic(fn(): Unit {
            let _ = map.insert(HashKey(7, pointer), Value(70, pointer))
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 25 }
        }
        if map.len() != 7usize || map.capacity() != capacity || state.live != live || state.drops != 13 { return 26 }
        i = 0
        while i < 7 {
            if map.get(HashKey(i, pointer)).or_panic().number != i * 10 { return 27 }
            i += 1
        }
        if map.get(HashKey(7, pointer)).is_present() { return 28 }
        state.panic_deallocate = true
        match take catch_panic(fn(): Unit { map.reserve(100usize) }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 29 }
        }
        if map.capacity() <= capacity || map.len() != 7usize || state.live != live || state.drops != 13 { return 30 }
        i = 0
        while i < 7 {
            if map.get(HashKey(i, pointer)).or_panic().number != i * 10 { return 31 }
            i += 1
        }
    }
    if state.live != 0 || state.drops != 20 { return 20 }
    match take catch_panic(fn(): Unit {
        var doomed = hash_map.new_in<i32, Value, FailingAllocator>(FailingAllocator(pointer))
        doomed.insert(1, Value(10, pointer))
        doomed.insert(2, Value(20, pointer))
        unsafe { (*pointer).panic_deallocate = true }
    }) {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 32 }
    }
    if state.live != 0 || state.drops != 22 { return 33 }
    0
}
