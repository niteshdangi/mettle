import alloc.alloc.{ Allocator, Global, Layout, AllocError }
import alloc.binary_heap
import alloc.linked_list
import alloc.vec
import alloc.vec.List
import alloc.vec_deque
import std.panic.CatchResult

type AllocationRecord {
    allocations: usize
    deallocations: usize
    live: usize
}

copy type TrackingAllocator { record: ptr<mut AllocationRecord> }

unsafe extend TrackingAllocator implements Allocator {
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

    mut unsafe fn grow(
        pointer: ptr<mut u8>,
        old: Layout,
        new_size: usize
    ): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut unsafe fn shrink(
        pointer: ptr<mut u8>,
        old: Layout,
        new_size: usize
    ): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

type DropBomb {
    value: i32
    drops: ptr<mut usize>
    panic_on_drop: bool
    drop {
        unsafe { *self.drops += 1usize }
        if self.panic_on_drop { panic("deque retain_back drop") }
    }
}

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn main(): i32 {
    var list = vec.new<i32>()
    {
        let last = list.push_mut(4)
        *last = 5
    }
    {
        let inserted = list.insert_mut(0usize, 2)
        *inserted = 3
    }
    if list.len() != 2usize || list[0usize] != 3 || list[1usize] != 5 {
        return 1
    }

    var allocation_record = AllocationRecord(0usize, 0usize, 0usize)
    var flattened_drops = 0usize
    {
        var arrays = vec.new_in<[Counted; 2], TrackingAllocator>(
            TrackingAllocator(core.ptr.from_mut(allocation_record))
        )
        arrays.reserve_exact(2usize)
        arrays.push([
            Counted(1, core.ptr.from_mut(flattened_drops)),
            Counted(2, core.ptr.from_mut(flattened_drops))
        ])
        arrays.push([
            Counted(3, core.ptr.from_mut(flattened_drops)),
            Counted(4, core.ptr.from_mut(flattened_drops))
        ])
        let array_capacity = arrays.capacity()
        var flattened = arrays.into_flattened()
        if flattened.len() != 4usize || flattened.capacity() != array_capacity * 2usize ||
            flattened[0usize].value != 1 || flattened[3usize].value != 4 {
            return 23
        }
    }
    if allocation_record.allocations != 1usize ||
        allocation_record.deallocations != 1usize ||
        allocation_record.live != 0usize || flattened_drops != 4usize {
        return 24
    }

    var raw_drops = 0usize
    var raw_owner = vec.new<Counted>()
    raw_owner.reserve_exact(4usize)
    raw_owner.push(Counted(7, core.ptr.from_mut(raw_drops)))
    raw_owner.push(Counted(9, core.ptr.from_mut(raw_drops)))
    let raw_parts = raw_owner.into_raw_parts()
    var restored = unsafe {
        List<Counted>.from_raw_parts(raw_parts.0, raw_parts.1, raw_parts.2)
    }
    if restored.len() != 2usize || restored.capacity() < 4usize ||
        restored[0usize].value != 7 || restored[1usize].value != 9 {
        return 26
    }
    restored.clear()
    if raw_drops != 2usize { return 27 }

    var zero_arrays = vec.new<[i32; 0]>()
    zero_arrays.push([])
    let zero_flattened = zero_arrays.into_flattened()
    if !zero_flattened.is_empty() || zero_flattened.capacity() != 0usize {
        return 25
    }

    var deque = vec_deque.with_capacity<i32>(5usize)
    if deque.capacity() < 5usize { return 2 }
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    let _first = deque.pop_front()
    let _second = deque.pop_front()
    {
        let last = deque.push_back_mut(4)
        *last = 40
    }
    {
        let first = deque.push_front_mut(2)
        *first = 20
    }
    deque.push_back(5)
    deque.swap(0usize, 3usize)
    {
        let inserted = deque.insert_mut(2usize, 30)
        *inserted = 31
    }
    if deque.len() != 5usize || deque[0usize] != 5 ||
        deque[1usize] != 3 || deque[2usize] != 31 ||
        deque[3usize] != 40 || deque[4usize] != 20 {
        return 3
    }
    deque.retain_back(3usize)
    if deque.len() != 3usize || deque[0usize] != 31 ||
        deque[1usize] != 40 || deque[2usize] != 20 {
        return 4
    }

    var drops = 0usize
    {
        var dropping = vec_deque.new<DropBomb>()
        dropping.push_back(DropBomb(1, core.ptr.from_mut(drops), false))
        dropping.push_back(DropBomb(2, core.ptr.from_mut(drops), true))
        dropping.push_back(DropBomb(3, core.ptr.from_mut(drops), false))
        dropping.push_back(DropBomb(4, core.ptr.from_mut(drops), false))
        let result = std.panic.catch_panic(fn(): Unit {
            dropping.retain_back(2usize)
        })
        match take result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 10 }
        }
        if dropping.len() != 2usize || dropping[0usize].value != 3 ||
            dropping[1usize].value != 4 || drops != 2usize {
            return 11
        }
        dropping.clear()
    }
    if drops != 4usize { return 12 }

    var list_nodes = linked_list.new<i32>()
    {
        let first = list_nodes.push_front_mut(1)
        *first = 2
    }
    {
        let last = list_nodes.push_back_mut(4)
        *last = 5
    }
    if list_nodes.len() != 2usize ||
        *list_nodes.get(0usize).unwrap() != 2 ||
        *list_nodes.get(1usize).unwrap() != 5 {
        return 13
    }

    var left = binary_heap.new<i32>()
    var right = binary_heap.new<i32>()
    left.push(10)
    left.push(2)
    right.push(8)
    right.push(4)
    left.append(right)
    if !right.is_empty() || left.len() != 4usize { return 14 }
    let expected_values = [10, 8, 4, 2]
    let expected: read [i32] = read expected_values
    var index = 0usize
    while index < expected.len() {
        match take left.pop() {
            present(value) => {
                if value != expected[index] { return 15 }
            },
            none => { return 16 }
        }
        index += 1usize
    }
    if !left.is_empty() { return 17 }
    0
}
