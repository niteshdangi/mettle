import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.rc
import alloc.arc
import alloc.boxed.Heap
import alloc.vec
import core.convert.From

type Record {
    allocations: i32
    deallocations: i32
    source_frees: i32
    owner_frees: i32
    live: i32
    mismatches: i32
    first_size: usize
    first_align: usize
    second_size: usize
    second_align: usize
    payload_drops: i32
}

@align(64)
type Aligned { value: i32 }

type Payload {
    record: ptr<mut Record>
    value: i32
    drop { unsafe { (*self.record).payload_drops += 1 } }
}

type Probe { record: ptr<mut Record> }

unsafe extend Probe implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe {
            (*self.record).allocations += 1
            (*self.record).live += 1
            if (*self.record).allocations == 1 {
                (*self.record).first_size = layout.size()
                (*self.record).first_align = layout.align()
            } else {
                (*self.record).second_size = layout.size()
                (*self.record).second_align = layout.align()
            }
        }
        pointer
    }

    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if layout.size() == (*self.record).first_size &&
                layout.align() == (*self.record).first_align {
                (*self.record).source_frees += 1
            } else if layout.size() == (*self.record).second_size &&
                layout.align() == (*self.record).second_align {
                (*self.record).owner_frees += 1
            } else {
                (*self.record).mismatches += 1
            }
            (*self.record).deallocations += 1
            (*self.record).live -= 1
        }
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }

    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

fn main(): i32 {
    var record = Record(0, 0, 0, 0, 0, 0, 0usize, 0usize, 0usize, 0usize, 0)
    let record_ptr = core.ptr.from_mut(record)
    {
        var values = vec.with_capacity_in<Payload, Probe>(2usize, Probe(record_ptr))
        values.push(Payload(record_ptr, 13))
        values.push(Payload(record_ptr, 29))
        if record.allocations != 1 || record.live != 1 { return 1 }

        let owner = rc.LocalShared<[Payload], Probe>.(From<vec.List<Payload, Probe>>).from(values)
        if owner.get().len() != 2usize ||
            owner.get()[0usize].value != 13 ||
            owner.get()[1usize].value != 29 {
            return 2
        }
        if record.allocations != 2 || record.deallocations != 1 ||
            record.source_frees != 1 || record.owner_frees != 0 ||
            record.live != 1 || record.mismatches != 0 ||
            record.payload_drops != 0 {
            return 3
        }
    }
    if record.deallocations != 2 || record.source_frees != 1 ||
        record.owner_frees != 1 || record.live != 0 ||
        record.mismatches != 0 || record.payload_drops != 2 {
        return 4
    }

    var empty_record = Record(0, 0, 0, 0, 0, 0, 0usize, 0usize, 0usize, 0usize, 0)
    let empty_ptr = core.ptr.from_mut(empty_record)
    {
        let empty = vec.new_in<i32, Probe>(Probe(empty_ptr))
        let owner = rc.LocalShared<[i32], Probe>.(From<vec.List<i32, Probe>>).from(empty)
        if owner.get().len() != 0usize || empty_record.allocations != 1 ||
            empty_record.deallocations != 0 || empty_record.live != 1 {
            return 5
        }
    }
    if empty_record.allocations != 1 || empty_record.deallocations != 1 ||
        empty_record.live != 0 || empty_record.mismatches != 0 {
        return 6
    }

    var zero_sized = vec.new<Unit>()
    zero_sized.push(())
    zero_sized.push(())
    zero_sized.push(())
    let zero_sized_owner = rc.LocalShared<[Unit]>.(From<vec.List<Unit>>).from(zero_sized)
    if zero_sized_owner.get().len() != 3usize { return 7 }

    var boxed_record = Record(0, 0, 0, 0, 0, 0, 0usize, 0usize, 0usize, 0usize, 0)
    let boxed_ptr = core.ptr.from_mut(boxed_record)
    {
        var values = vec.with_capacity_in<Payload, Probe>(2usize, Probe(boxed_ptr))
        values.push(Payload(boxed_ptr, 37))
        values.push(Payload(boxed_ptr, 43))
        let source = values.into_heap_slice()
        let owner = rc.LocalShared<[Payload], Probe>.(From<Heap<[Payload], Probe>>).from(source)
        if owner.get().len() != 2usize || owner.get()[0usize].value != 37 ||
            owner.get()[1usize].value != 43 || boxed_record.allocations != 2 ||
            boxed_record.source_frees != 1 || boxed_record.payload_drops != 0 { return 8 }
    }
    if boxed_record.payload_drops != 2 || boxed_record.owner_frees != 1 ||
        boxed_record.live != 0 || boxed_record.mismatches != 0 { return 9 }

    var atomic_record = Record(0, 0, 0, 0, 0, 0, 0usize, 0usize, 0usize, 0usize, 0)
    let atomic_ptr = core.ptr.from_mut(atomic_record)
    {
        var values = vec.with_capacity_in<Payload, Probe>(2usize, Probe(atomic_ptr))
        values.push(Payload(atomic_ptr, 47))
        values.push(Payload(atomic_ptr, 53))
        let source = values.into_heap_slice()
        let owner = arc.Shared<[Payload], Probe>.(From<Heap<[Payload], Probe>>).from(source)
        if owner.get().len() != 2usize || owner.get()[0usize].value != 47 ||
            owner.get()[1usize].value != 53 || atomic_record.allocations != 2 ||
            atomic_record.source_frees != 1 || atomic_record.payload_drops != 0 { return 10 }
    }
    if atomic_record.payload_drops != 2 || atomic_record.owner_frees != 1 ||
        atomic_record.live != 0 || atomic_record.mismatches != 0 { return 11 }

    let source: Heap<any core.any.Any> = heap Aligned(61)
    let erased = rc.LocalShared<any core.any.Any>.(From<Heap<any core.any.Any>>).from(source)
    match take erased.downcast<Aligned>() {
        success(owner) => {
            if owner.get().value != 61 || owner.as_ptr().addr() % 64usize != 0usize { return 12 }
        },
        failure(_) => { return 13 }
    }
    let atomic_source: Heap<any core.any.Any> = heap Aligned(67)
    let atomic_erased = arc.Shared<any core.any.Any>.(From<Heap<any core.any.Any>>).from(atomic_source)
    if !core.any.is<Aligned>(atomic_erased.get()) ||
        atomic_erased.as_ptr().addr() % 64usize != 0usize { return 14 }
    let units = vec.from_array([(), (), ()]).into_heap_slice()
    let shared_units = arc.Shared<[Unit]>.(From<Heap<[Unit]>>).from(units)
    if shared_units.get().len() != 3usize { return 15 }
    let empty = vec.new<i32>().into_heap_slice()
    let shared_empty = rc.LocalShared<[i32]>.(From<Heap<[i32]>>).from(empty)
    if shared_empty.get().len() != 0usize { return 16 }
    0
}
