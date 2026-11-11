import alloc.alloc.{ Allocator, Global, Layout, AllocError }
import alloc.binary_heap
import alloc.linked_list
import alloc.vec_deque
import core.clone.Clone
import core.cmp.{ Eq, PartialEq }
import core.default.Default
import std.panic.CatchResult

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

extend Counted implements Clone {
    fn clone(): Counted { Counted(self.value, self.drops) }
}
extend Counted implements PartialEq {
    fn eq(read other: Counted): bool { self.value == other.value }
}
extend Counted implements Eq {}

type AllocRecord {
    allocations: usize
    deallocations: usize
    live: usize
}

copy type AuditAllocator { record: ptr<mut AllocRecord> }

extend AuditAllocator implements Clone {
    fn clone(): AuditAllocator { AuditAllocator(self.record) }
}

unsafe extend AuditAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        if layout.size() != 0usize {
            unsafe {
                (*self.record).allocations += 1usize
                (*self.record).live += 1usize
            }
        }
        pointer
    }

    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
        if layout.size() != 0usize {
            unsafe {
                (*self.record).deallocations += 1usize
                (*self.record).live -= 1usize
            }
        }
    }

    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

type DropBomb {
    value: i32
    drops: ptr<mut usize>
    panic_on_drop: bool
    drop {
        unsafe { *self.drops += 1usize }
        if self.panic_on_drop { panic("deque truncate drop") }
    }
}

type CloneBomb {
    value: i32
    drops: ptr<mut usize>
    clone_calls: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

extend CloneBomb implements Clone {
    fn clone(): CloneBomb {
        unsafe {
            *self.clone_calls += 1usize
            if *self.clone_calls == 2usize { panic("deque resize clone") }
        }
        CloneBomb(self.value, self.drops, self.clone_calls)
    }
}

fn default_value<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    var default_deque: vec_deque.Deque<i32> =
        default_value<vec_deque.Deque<i32>>()
    var default_list: linked_list.LinkedList<i32> =
        default_value<linked_list.LinkedList<i32>>()
    var default_heap: binary_heap.BinaryHeap<i32> =
        default_value<binary_heap.BinaryHeap<i32>>()
    if !default_deque.is_empty() || !default_list.is_empty() ||
        !default_heap.is_empty() {
        return 1
    }

    var deque_record = AllocRecord(0usize, 0usize, 0usize)
    var source_record = AllocRecord(0usize, 0usize, 0usize)
    {
        var deque = vec_deque.new_in<i32, AuditAllocator>(
            AuditAllocator(core.ptr.from_mut(deque_record))
        )
        var source = vec_deque.new_in<i32, AuditAllocator>(
            AuditAllocator(core.ptr.from_mut(source_record))
        )
        deque.reserve(4usize)
        deque.push_back(1)
        deque.push_back(2)
        deque.push_back(3)
        deque.push_back(4)
        let _first = deque.pop_front()
        let _second = deque.pop_front()
        deque.push_back(5)
        deque.push_back(6)

        source.reserve(4usize)
        source.push_back(7)
        source.push_back(8)
        source.push_back(9)
        source.push_back(10)
        let _discarded = source.pop_front()
        source.push_back(11)
        deque.append(source)
        if !source.is_empty() || deque.len() != 8usize ||
            deque[0usize] != 3 || deque[3usize] != 6 ||
            deque[4usize] != 8 || deque[7usize] != 11 {
            return 2
        }
        if !deque.contains(10) || deque.contains(99) { return 3 }

        let suffix = deque.split_off(4usize)
        if deque.len() != 4usize || suffix.len() != 4usize ||
            suffix[0usize] != 8 || suffix[3usize] != 11 {
            return 4
        }
        deque.truncate(3usize)
        deque.resize(5usize, 99)
        if deque.len() != 5usize || deque[0usize] != 3 ||
            deque[2usize] != 5 || deque[3usize] != 99 ||
            deque[4usize] != 99 || deque.contains(8) {
            return 5
        }
        source.push_front(12)
        if source.len() != 1usize || source[0usize] != 12 { return 6 }
    }
    if deque_record.live != 0usize ||
        deque_record.allocations != deque_record.deallocations ||
        source_record.live != 0usize ||
        source_record.allocations != source_record.deallocations {
        return 7
    }

    var linked_record = AllocRecord(0usize, 0usize, 0usize)
    var linked_drops = 0usize
    {
        var list = linked_list.new_in<Counted, AuditAllocator>(
            AuditAllocator(core.ptr.from_mut(linked_record))
        )
        list.push_back(Counted(1, core.ptr.from_mut(linked_drops)))
        list.push_back(Counted(2, core.ptr.from_mut(linked_drops)))
        list.push_back(Counted(3, core.ptr.from_mut(linked_drops)))
        list.push_back(Counted(4, core.ptr.from_mut(linked_drops)))
        let probe = Counted(3, core.ptr.from_mut(linked_drops))
        if !list.contains(read probe) { return 8 }
        let before_invalid_split = linked_record.allocations
        let invalid = std.panic.catch_panic(fn(): Unit {
            let _tail = list.split_off(5usize)
        })
        match take invalid {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 9 }
        }
        if list.len() != 4usize ||
            linked_record.allocations != before_invalid_split {
            return 10
        }
        let tail = list.split_off(2usize)
        if list.len() != 2usize || tail.len() != 2usize ||
            (*list.get(1usize).unwrap()).value != 2 ||
            (*tail.get(0usize).unwrap()).value != 3 ||
            (*tail.get(1usize).unwrap()).value != 4 {
            return 11
        }
    }
    if linked_drops != 5usize || linked_record.live != 0usize ||
        linked_record.allocations != linked_record.deallocations {
        return 12
    }

    var global_list = linked_list.new<i32>()
    var global_tail = linked_list.new<i32>()
    global_list.push_back(1)
    global_list.push_back(2)
    global_tail.push_back(3)
    global_list.append(global_tail)
    if !global_tail.is_empty() || global_list.len() != 3usize ||
        !global_list.contains(3) || global_list.contains(9) {
        return 13
    }
    if *global_list.get(2usize).unwrap() != 3 { return 14 }

    var counted_drops = 0usize
    {
        var counted = vec_deque.new<Counted>()
        counted.push_back(Counted(1, core.ptr.from_mut(counted_drops)))
        counted.push_back(Counted(2, core.ptr.from_mut(counted_drops)))
        counted.truncate(1usize)
        counted.resize(
            3usize,
            Counted(9, core.ptr.from_mut(counted_drops))
        )
        if counted.len() != 3usize || counted[0usize].value != 1 ||
            counted[1usize].value != 9 || counted[2usize].value != 9 {
            return 15
        }
    }
    if counted_drops != 5usize { return 16 }

    var truncate_drops = 0usize
    {
        var counted = vec_deque.new<DropBomb>()
        counted.push_back(DropBomb(1, core.ptr.from_mut(truncate_drops), false))
        counted.push_back(DropBomb(2, core.ptr.from_mut(truncate_drops), false))
        counted.push_back(DropBomb(3, core.ptr.from_mut(truncate_drops), true))
        counted.push_back(DropBomb(4, core.ptr.from_mut(truncate_drops), false))
        let result = std.panic.catch_panic(fn(): Unit {
            counted.truncate(1usize)
        })
        match take result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 17 }
        }
        if counted.len() != 2usize || counted[0usize].value != 1 ||
            counted[1usize].value != 2 || truncate_drops != 2usize {
            return 18
        }
        counted.clear()
    }
    if truncate_drops != 4usize { return 19 }

    var clone_drops = 0usize
    var clone_calls = 0usize
    {
        var counted = vec_deque.new<CloneBomb>()
        counted.push_back(CloneBomb(
            1,
            core.ptr.from_mut(clone_drops),
            core.ptr.from_mut(clone_calls)
        ))
        let result = std.panic.catch_panic(fn(): Unit {
            counted.resize(
                4usize,
                CloneBomb(
                    9,
                    core.ptr.from_mut(clone_drops),
                    core.ptr.from_mut(clone_calls)
                )
            )
        })
        match take result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 20 }
        }
        if clone_calls != 2usize || counted.len() != 2usize ||
            counted[0usize].value != 1 || counted[1usize].value != 9 {
            return 21
        }
        counted.clear()
    }
    if clone_drops != 3usize { return 22 }
    0
}
