import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.rc
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

type Payload {
    record: ptr<mut Record>
    value: i32
    drop { unsafe { (*self.record).payload_drops += 1 } }
}

type Probe { record: ptr<mut Record> }

extend Probe implements Allocator {
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

    mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
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
        global.deallocate(pointer, layout)
    }

    mut fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
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

        let owner = rc.Rc<[Payload], Probe>.(From<vec.List<Payload, Probe>>).`from`(values)
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
        let owner = rc.Rc<[i32], Probe>.(From<vec.List<i32, Probe>>).`from`(empty)
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
    let zero_sized_owner = rc.Rc<[Unit]>.(From<vec.List<Unit>>).`from`(zero_sized)
    if zero_sized_owner.get().len() != 3usize { return 7 }
    0
}
