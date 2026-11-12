fn check_i32(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicI32.new(12i32)
    if value.load(relaxed) != 12i32 { return 1 }
    value.store(10i32, release)
    if value.swap(12i32, order) != 10i32 { return 2 }
    if value.fetch_add(10i32, order) != 12i32 || value.load(relaxed) != 22i32 { return 3 }
    if value.fetch_sub(10i32, order) != 22i32 || value.load(relaxed) != 12i32 { return 4 }
    if value.fetch_and(10i32, order) != 12i32 || value.load(relaxed) != 8i32 { return 5 }
    value.store(12i32, relaxed)
    if value.fetch_or(10i32, order) != 12i32 || value.load(relaxed) != 14i32 { return 6 }
    value.store(12i32, relaxed)
    if value.fetch_xor(10i32, order) != 12i32 || value.load(relaxed) != 6i32 { return 7 }
    value.store(12i32, relaxed)
    if value.fetch_nand(10i32, order) != 12i32 || value.load(relaxed) != -9i32 { return 8 }
    value.store(12i32, relaxed)
    if value.fetch_max(10i32, order) != 12i32 || value.load(relaxed) != 12i32 { return 9 }
    if value.fetch_min(10i32, order) != 12i32 || value.load(relaxed) != 10i32 { return 10 }
    if value.fetch_max(12i32, order) != 10i32 || value.load(relaxed) != 12i32 { return 11 }
    let wrap = core.sync.atomic.AtomicI32.new(2147483647i32)
    if wrap.fetch_add(1i32, order) != 2147483647i32 || wrap.load(relaxed) != -2147483648i32 { return 12 }
    if wrap.fetch_sub(1i32, order) != -2147483648i32 || wrap.load(relaxed) != 2147483647i32 { return 13 }
    let cas = core.sync.atomic.AtomicI32.new(12i32)
    let hit = match cas.compare_exchange(12i32, 10i32, order, relaxed) {
        success(old) => old == 12i32, failure(_) => false
    }
    let miss = match cas.compare_exchange(12i32, 0i32, order, relaxed) {
        success(_) => false, failure(old) => old == 10i32
    }
    if !hit || !miss || cas.load(relaxed) != 10i32 { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10i32, 12i32, order, relaxed) {
            success(old) => { if old != 10i32 { return 15 }; break },
            failure(old) => { if old != 10i32 || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12i32 { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10i32, 0i32, order, relaxed) {
        success(_) => false, failure(old) => old == 12i32
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicI32.new(12i32)
    let slot = owned.get_mut()
    *slot = 10i32
    if owned.load(relaxed) != 10i32 { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12i32) }
    if owned.load(relaxed) != 12i32 { return 20 }
    if owned.into_inner() != 12i32 { return 21 }
    0
}

fn check_isize(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicIsize.new(12isize)
    if value.load(relaxed) != 12isize { return 1 }
    value.store(10isize, release)
    if value.swap(12isize, order) != 10isize { return 2 }
    if value.fetch_add(10isize, order) != 12isize || value.load(relaxed) != 22isize { return 3 }
    if value.fetch_sub(10isize, order) != 22isize || value.load(relaxed) != 12isize { return 4 }
    if value.fetch_and(10isize, order) != 12isize || value.load(relaxed) != 8isize { return 5 }
    value.store(12isize, relaxed)
    if value.fetch_or(10isize, order) != 12isize || value.load(relaxed) != 14isize { return 6 }
    value.store(12isize, relaxed)
    if value.fetch_xor(10isize, order) != 12isize || value.load(relaxed) != 6isize { return 7 }
    value.store(12isize, relaxed)
    if value.fetch_nand(10isize, order) != 12isize || value.load(relaxed) != -9isize { return 8 }
    value.store(12isize, relaxed)
    if value.fetch_max(10isize, order) != 12isize || value.load(relaxed) != 12isize { return 9 }
    if value.fetch_min(10isize, order) != 12isize || value.load(relaxed) != 10isize { return 10 }
    if value.fetch_max(12isize, order) != 10isize || value.load(relaxed) != 12isize { return 11 }
    let wrap = core.sync.atomic.AtomicIsize.new(9223372036854775807isize)
    if wrap.fetch_add(1isize, order) != 9223372036854775807isize || wrap.load(relaxed) != -9223372036854775808isize { return 12 }
    if wrap.fetch_sub(1isize, order) != -9223372036854775808isize || wrap.load(relaxed) != 9223372036854775807isize { return 13 }
    let cas = core.sync.atomic.AtomicIsize.new(12isize)
    let hit = match cas.compare_exchange(12isize, 10isize, order, relaxed) {
        success(old) => old == 12isize, failure(_) => false
    }
    let miss = match cas.compare_exchange(12isize, 0isize, order, relaxed) {
        success(_) => false, failure(old) => old == 10isize
    }
    if !hit || !miss || cas.load(relaxed) != 10isize { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10isize, 12isize, order, relaxed) {
            success(old) => { if old != 10isize { return 15 }; break },
            failure(old) => { if old != 10isize || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12isize { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10isize, 0isize, order, relaxed) {
        success(_) => false, failure(old) => old == 12isize
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicIsize.new(12isize)
    let slot = owned.get_mut()
    *slot = 10isize
    if owned.load(relaxed) != 10isize { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12isize) }
    if owned.load(relaxed) != 12isize { return 20 }
    if owned.into_inner() != 12isize { return 21 }
    0
}

fn check_usize(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicUsize.new(12usize)
    if value.load(relaxed) != 12usize { return 1 }
    value.store(10usize, release)
    if value.swap(12usize, order) != 10usize { return 2 }
    if value.fetch_add(10usize, order) != 12usize || value.load(relaxed) != 22usize { return 3 }
    if value.fetch_sub(10usize, order) != 22usize || value.load(relaxed) != 12usize { return 4 }
    if value.fetch_and(10usize, order) != 12usize || value.load(relaxed) != 8usize { return 5 }
    value.store(12usize, relaxed)
    if value.fetch_or(10usize, order) != 12usize || value.load(relaxed) != 14usize { return 6 }
    value.store(12usize, relaxed)
    if value.fetch_xor(10usize, order) != 12usize || value.load(relaxed) != 6usize { return 7 }
    value.store(12usize, relaxed)
    if value.fetch_nand(10usize, order) != 12usize || value.load(relaxed) != 18446744073709551607usize { return 8 }
    value.store(12usize, relaxed)
    if value.fetch_max(10usize, order) != 12usize || value.load(relaxed) != 12usize { return 9 }
    if value.fetch_min(10usize, order) != 12usize || value.load(relaxed) != 10usize { return 10 }
    if value.fetch_max(12usize, order) != 10usize || value.load(relaxed) != 12usize { return 11 }
    let wrap = core.sync.atomic.AtomicUsize.new(18446744073709551615usize)
    if wrap.fetch_add(1usize, order) != 18446744073709551615usize || wrap.load(relaxed) != 0usize { return 12 }
    if wrap.fetch_sub(1usize, order) != 0usize || wrap.load(relaxed) != 18446744073709551615usize { return 13 }
    let cas = core.sync.atomic.AtomicUsize.new(12usize)
    let hit = match cas.compare_exchange(12usize, 10usize, order, relaxed) {
        success(old) => old == 12usize, failure(_) => false
    }
    let miss = match cas.compare_exchange(12usize, 0usize, order, relaxed) {
        success(_) => false, failure(old) => old == 10usize
    }
    if !hit || !miss || cas.load(relaxed) != 10usize { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10usize, 12usize, order, relaxed) {
            success(old) => { if old != 10usize { return 15 }; break },
            failure(old) => { if old != 10usize || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12usize { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10usize, 0usize, order, relaxed) {
        success(_) => false, failure(old) => old == 12usize
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicUsize.new(12usize)
    let slot = owned.get_mut()
    *slot = 10usize
    if owned.load(relaxed) != 10usize { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12usize) }
    if owned.load(relaxed) != 12usize { return 20 }
    if owned.into_inner() != 12usize { return 21 }
    0
}

fn check_i64(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicI64.new(12i64)
    if value.load(relaxed) != 12i64 { return 1 }
    value.store(10i64, release)
    if value.swap(12i64, order) != 10i64 { return 2 }
    if value.fetch_add(10i64, order) != 12i64 || value.load(relaxed) != 22i64 { return 3 }
    if value.fetch_sub(10i64, order) != 22i64 || value.load(relaxed) != 12i64 { return 4 }
    if value.fetch_and(10i64, order) != 12i64 || value.load(relaxed) != 8i64 { return 5 }
    value.store(12i64, relaxed)
    if value.fetch_or(10i64, order) != 12i64 || value.load(relaxed) != 14i64 { return 6 }
    value.store(12i64, relaxed)
    if value.fetch_xor(10i64, order) != 12i64 || value.load(relaxed) != 6i64 { return 7 }
    value.store(12i64, relaxed)
    if value.fetch_nand(10i64, order) != 12i64 || value.load(relaxed) != -9i64 { return 8 }
    value.store(12i64, relaxed)
    if value.fetch_max(10i64, order) != 12i64 || value.load(relaxed) != 12i64 { return 9 }
    if value.fetch_min(10i64, order) != 12i64 || value.load(relaxed) != 10i64 { return 10 }
    if value.fetch_max(12i64, order) != 10i64 || value.load(relaxed) != 12i64 { return 11 }
    let wrap = core.sync.atomic.AtomicI64.new(9223372036854775807i64)
    if wrap.fetch_add(1i64, order) != 9223372036854775807i64 || wrap.load(relaxed) != -9223372036854775808i64 { return 12 }
    if wrap.fetch_sub(1i64, order) != -9223372036854775808i64 || wrap.load(relaxed) != 9223372036854775807i64 { return 13 }
    let cas = core.sync.atomic.AtomicI64.new(12i64)
    let hit = match cas.compare_exchange(12i64, 10i64, order, relaxed) {
        success(old) => old == 12i64, failure(_) => false
    }
    let miss = match cas.compare_exchange(12i64, 0i64, order, relaxed) {
        success(_) => false, failure(old) => old == 10i64
    }
    if !hit || !miss || cas.load(relaxed) != 10i64 { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10i64, 12i64, order, relaxed) {
            success(old) => { if old != 10i64 { return 15 }; break },
            failure(old) => { if old != 10i64 || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12i64 { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10i64, 0i64, order, relaxed) {
        success(_) => false, failure(old) => old == 12i64
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicI64.new(12i64)
    let slot = owned.get_mut()
    *slot = 10i64
    if owned.load(relaxed) != 10i64 { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12i64) }
    if owned.load(relaxed) != 12i64 { return 20 }
    if owned.into_inner() != 12i64 { return 21 }
    0
}

fn check_u32(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicU32.new(12u32)
    if value.load(relaxed) != 12u32 { return 1 }
    value.store(10u32, release)
    if value.swap(12u32, order) != 10u32 { return 2 }
    if value.fetch_add(10u32, order) != 12u32 || value.load(relaxed) != 22u32 { return 3 }
    if value.fetch_sub(10u32, order) != 22u32 || value.load(relaxed) != 12u32 { return 4 }
    if value.fetch_and(10u32, order) != 12u32 || value.load(relaxed) != 8u32 { return 5 }
    value.store(12u32, relaxed)
    if value.fetch_or(10u32, order) != 12u32 || value.load(relaxed) != 14u32 { return 6 }
    value.store(12u32, relaxed)
    if value.fetch_xor(10u32, order) != 12u32 || value.load(relaxed) != 6u32 { return 7 }
    value.store(12u32, relaxed)
    if value.fetch_nand(10u32, order) != 12u32 || value.load(relaxed) != 4294967287u32 { return 8 }
    value.store(12u32, relaxed)
    if value.fetch_max(10u32, order) != 12u32 || value.load(relaxed) != 12u32 { return 9 }
    if value.fetch_min(10u32, order) != 12u32 || value.load(relaxed) != 10u32 { return 10 }
    if value.fetch_max(12u32, order) != 10u32 || value.load(relaxed) != 12u32 { return 11 }
    let wrap = core.sync.atomic.AtomicU32.new(4294967295u32)
    if wrap.fetch_add(1u32, order) != 4294967295u32 || wrap.load(relaxed) != 0u32 { return 12 }
    if wrap.fetch_sub(1u32, order) != 0u32 || wrap.load(relaxed) != 4294967295u32 { return 13 }
    let cas = core.sync.atomic.AtomicU32.new(12u32)
    let hit = match cas.compare_exchange(12u32, 10u32, order, relaxed) {
        success(old) => old == 12u32, failure(_) => false
    }
    let miss = match cas.compare_exchange(12u32, 0u32, order, relaxed) {
        success(_) => false, failure(old) => old == 10u32
    }
    if !hit || !miss || cas.load(relaxed) != 10u32 { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10u32, 12u32, order, relaxed) {
            success(old) => { if old != 10u32 { return 15 }; break },
            failure(old) => { if old != 10u32 || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12u32 { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10u32, 0u32, order, relaxed) {
        success(_) => false, failure(old) => old == 12u32
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicU32.new(12u32)
    let slot = owned.get_mut()
    *slot = 10u32
    if owned.load(relaxed) != 10u32 { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12u32) }
    if owned.load(relaxed) != 12u32 { return 20 }
    if owned.into_inner() != 12u32 { return 21 }
    0
}

fn check_u64(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let value = core.sync.atomic.AtomicU64.new(12u64)
    if value.load(relaxed) != 12u64 { return 1 }
    value.store(10u64, release)
    if value.swap(12u64, order) != 10u64 { return 2 }
    if value.fetch_add(10u64, order) != 12u64 || value.load(relaxed) != 22u64 { return 3 }
    if value.fetch_sub(10u64, order) != 22u64 || value.load(relaxed) != 12u64 { return 4 }
    if value.fetch_and(10u64, order) != 12u64 || value.load(relaxed) != 8u64 { return 5 }
    value.store(12u64, relaxed)
    if value.fetch_or(10u64, order) != 12u64 || value.load(relaxed) != 14u64 { return 6 }
    value.store(12u64, relaxed)
    if value.fetch_xor(10u64, order) != 12u64 || value.load(relaxed) != 6u64 { return 7 }
    value.store(12u64, relaxed)
    if value.fetch_nand(10u64, order) != 12u64 || value.load(relaxed) != 18446744073709551607u64 { return 8 }
    value.store(12u64, relaxed)
    if value.fetch_max(10u64, order) != 12u64 || value.load(relaxed) != 12u64 { return 9 }
    if value.fetch_min(10u64, order) != 12u64 || value.load(relaxed) != 10u64 { return 10 }
    if value.fetch_max(12u64, order) != 10u64 || value.load(relaxed) != 12u64 { return 11 }
    let wrap = core.sync.atomic.AtomicU64.new(18446744073709551615u64)
    if wrap.fetch_add(1u64, order) != 18446744073709551615u64 || wrap.load(relaxed) != 0u64 { return 12 }
    if wrap.fetch_sub(1u64, order) != 0u64 || wrap.load(relaxed) != 18446744073709551615u64 { return 13 }
    let cas = core.sync.atomic.AtomicU64.new(12u64)
    let hit = match cas.compare_exchange(12u64, 10u64, order, relaxed) {
        success(old) => old == 12u64, failure(_) => false
    }
    let miss = match cas.compare_exchange(12u64, 0u64, order, relaxed) {
        success(_) => false, failure(old) => old == 10u64
    }
    if !hit || !miss || cas.load(relaxed) != 10u64 { return 14 }
    var spins = 0i32
    loop {
        match cas.compare_exchange_weak(10u64, 12u64, order, relaxed) {
            success(old) => { if old != 10u64 { return 15 }; break },
            failure(old) => { if old != 10u64 || spins > 1000000 { return 16 }; spins += 1 }
        }
    }
    if cas.load(relaxed) != 12u64 { return 17 }
    let weak_miss = match cas.compare_exchange_weak(10u64, 0u64, order, relaxed) {
        success(_) => false, failure(old) => old == 12u64
    }
    if !weak_miss { return 18 }
    var owned = core.sync.atomic.AtomicU64.new(12u64)
    let slot = owned.get_mut()
    *slot = 10u64
    if owned.load(relaxed) != 10u64 { return 19 }
    let address = owned.as_ptr()
    unsafe { address.`write`(12u64) }
    if owned.load(relaxed) != 12u64 { return 20 }
    if owned.into_inner() != 12u64 { return 21 }
    0
}

fn check_bool(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    let flag = core.sync.atomic.AtomicBool.new(true)
    if !flag.load(relaxed) { return 1 }
    flag.store(false, release)
    if flag.swap(true, order) || !flag.load(relaxed) { return 2 }
    if !flag.fetch_and(false, order) || flag.load(relaxed) { return 3 }
    if flag.fetch_or(true, order) || !flag.load(relaxed) { return 4 }
    if !flag.fetch_xor(true, order) || flag.load(relaxed) { return 5 }
    flag.store(true, relaxed)
    if !flag.fetch_nand(true, order) || flag.load(relaxed) { return 6 }
    let hit = match flag.compare_exchange(false, true, order, relaxed) {
        success(old) => !old, failure(_) => false
    }
    let miss = match flag.compare_exchange(false, true, order, relaxed) {
        success(_) => false, failure(old) => old
    }
    if !hit || !miss { return 7 }
    var spins = 0i32
    loop {
        match flag.compare_exchange_weak(true, false, order, relaxed) {
            success(old) => { if !old { return 8 }; break },
            failure(old) => { if !old || spins > 1000000 { return 9 }; spins += 1 }
        }
    }
    if flag.load(relaxed) { return 10 }
    var owned = core.sync.atomic.AtomicBool.new(false)
    let slot = owned.get_mut()
    *slot = true
    if !owned.load(relaxed) { return 11 }
    if !owned.into_inner() { return 12 }
    0
}

fn check_ptr(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let release = core.sync.atomic.Ordering.Release
    var first = [1i32, 2i32, 3i32]
    var second = 9i32
    let base = core.ptr.from_mut(first[0usize])
    let other = core.ptr.from_mut(second)
    let cell = core.sync.atomic.AtomicPtr<i32>.new(base)
    if cell.load(relaxed) != base { return 1 }
    cell.store(other, release)
    if cell.swap(base, order) != other || cell.load(relaxed) != base { return 2 }
    if cell.fetch_ptr_add(2usize, order) != base { return 3 }
    if cell.fetch_ptr_sub(1usize, order).addr() != base.addr() + 8usize { return 4 }
    if cell.load(relaxed).addr() != base.addr() + 4usize { return 5 }
    if cell.fetch_byte_add(4usize, order).addr() != base.addr() + 4usize { return 6 }
    if cell.fetch_byte_sub(8usize, order).addr() != base.addr() + 8usize { return 7 }
    if cell.load(relaxed) != base { return 8 }
    let hit = match cell.compare_exchange(base, other, order, relaxed) {
        success(old) => old == base, failure(_) => false
    }
    let miss = match cell.compare_exchange(base, base, order, relaxed) {
        success(_) => false, failure(old) => old == other
    }
    if !hit || !miss { return 9 }
    var spins = 0i32
    loop {
        match cell.compare_exchange_weak(other, base, order, relaxed) {
            success(old) => { if old != other { return 10 }; break },
            failure(old) => { if old != other || spins > 1000000 { return 11 }; spins += 1 }
        }
    }
    if cell.load(relaxed) != base { return 12 }
    var owned = core.sync.atomic.AtomicPtr<i32>.new(base)
    let slot = owned.get_mut()
    *slot = other
    if owned.load(relaxed) != other { return 13 }
    let address = owned.as_ptr()
    unsafe { address.`write`(base) }
    if owned.load(relaxed) != base { return 14 }
    if owned.into_inner() != base { return 15 }
    0
}

fn main(): i32 {
    var code = 0i32
    code = check_i32()
    if code != 0 { return 100i32 + code }
    code = check_isize()
    if code != 0 { return 200i32 + code }
    code = check_usize()
    if code != 0 { return 300i32 + code }
    code = check_i64()
    if code != 0 { return 400i32 + code }
    code = check_u32()
    if code != 0 { return 500i32 + code }
    code = check_u64()
    if code != 0 { return 600i32 + code }
    code = check_bool()
    if code != 0 { return 700i32 + code }
    code = check_ptr()
    if code != 0 { return 800i32 + code }
    let probe = core.sync.atomic.AtomicU32.new(1u32)
    probe.store(2u32, core.sync.atomic.Ordering.SeqCst)
    if probe.load(core.sync.atomic.Ordering.Acquire) != 2u32 ||
       probe.load(core.sync.atomic.Ordering.SeqCst) != 2u32 { return 900 }
    0
}
