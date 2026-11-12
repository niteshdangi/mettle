module owner_slice_allocator;
import owner_slice_allocator.{Record, Probe}
import alloc.alloc.AllocError
import alloc.arc
import alloc.rc
import core.clone.Clone

fn run(): i32 throws AllocError {
    var failed = Record(0, 0, 0, 0, 0usize, 0usize, true)
    let allocator = Probe(core.ptr.from_mut(failed))
    match capture rc.try_new_uninit_slice_in<i32, Probe>(3usize, allocator.clone()) {
        success(_) => { return 1 },
        failure(_) => {}
    }
    match capture arc.try_new_zeroed_slice_in<i32, Probe>(3usize, allocator.clone()) {
        success(_) => { return 2 },
        failure(_) => {}
    }
    match capture rc.try_new_uninit_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        allocator.clone()
    ) {
        success(_) => { return 3 },
        failure(_) => {}
    }
    match capture arc.try_new_zeroed_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        allocator.clone()
    ) {
        success(_) => { return 10 },
        failure(_) => {}
    }
    if failed.attempts != 2 || failed.live != 0 || failed.frees != 0 {
        return 4
    }

    var local_record = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try rc.try_new_uninit_slice_in<u32, Probe>(
            2usize,
            Probe(core.ptr.from_mut(local_record))
        )
        if owner.get().len() != 2usize || local_record.live != 1 { return 5 }
    }
    if local_record.frees != 1 || local_record.live != 0 || local_record.mismatches != 0 {
        return 6
    }

    var atomic = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try arc.try_new_zeroed_slice_in<u32, Probe>(
            2usize,
            Probe(core.ptr.from_mut(atomic))
        )
        if owner.get().len() != 2usize || atomic.live != 1 { return 7 }
        let initialized = unsafe { owner.assume_init() }
        if initialized.get()[0usize] != 0u32 || initialized.get()[1usize] != 0u32 {
            return 8
        }
    }
    if atomic.frees != 1 || atomic.live != 0 || atomic.mismatches != 0 {
        return 9
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
