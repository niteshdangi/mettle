module owner_slice_allocator;
import owner_slice_allocator.{Record, Probe}
import alloc.alloc.AllocError
import alloc.boxed
import core.clone.Clone

fn run(): i32 throws AllocError {
    var failed = Record(0, 0, 0, 0, 0usize, 0usize, true)
    let fail_allocator = Probe(core.ptr.from_mut(failed))
    match capture boxed.try_new_uninit_slice_in<i32, Probe>(
        3usize,
        fail_allocator.clone()
    ) {
        success(_) => { return 1 },
        failure(error) => {
            if error.size != 12usize || error.align != 4usize { return 2 }
        }
    }
    match capture boxed.try_new_zeroed_slice_in<i32, Probe>(
        3usize,
        fail_allocator.clone()
    ) {
        success(_) => { return 3 },
        failure(error) => {
            if error.size != 12usize || error.align != 4usize { return 4 }
        }
    }
    match capture boxed.try_new_uninit_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        fail_allocator.clone()
    ) {
        success(_) => { return 9 },
        failure(error) => {
            if error.align != 4usize { return 10 }
        }
    }
    if failed.attempts != 2 || failed.live != 0 || failed.frees != 0 {
        return 5
    }

    var successful = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try boxed.try_new_zeroed_slice_in<u32, Probe>(
            3usize,
            Probe(core.ptr.from_mut(successful))
        )
        if owner.get().len() != 3usize || successful.size != 12usize ||
            successful.align != 4usize || successful.live != 1 {
            return 6
        }
        let initialized = unsafe { owner.assume_init() }
        if initialized.get()[0usize] != 0u32 || initialized.get()[2usize] != 0u32 {
            return 7
        }
    }
    if successful.frees != 1 || successful.live != 0 ||
        successful.mismatches != 0 {
        return 8
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
