fn check_i8(): i32 {
    let cell = core.sync.atomic.AtomicI8.new(5i8)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i8): i8? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9i8, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1i8)
    })
    match first {
        success(old) => { if old != 9i8 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i8 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i8): i8? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10i8 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i8 { return 6 }
    0
}

fn check_i16(): i32 {
    let cell = core.sync.atomic.AtomicI16.new(5i16)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i16): i16? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9i16, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1i16)
    })
    match first {
        success(old) => { if old != 9i16 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i16 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i16): i16? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10i16 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i16 { return 6 }
    0
}

fn check_i32(): i32 {
    let cell = core.sync.atomic.AtomicI32.new(5i32)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i32): i32? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9i32, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1i32)
    })
    match first {
        success(old) => { if old != 9i32 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i32 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i32): i32? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10i32 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i32 { return 6 }
    0
}

fn check_i64(): i32 {
    let cell = core.sync.atomic.AtomicI64.new(5i64)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i64): i64? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9i64, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1i64)
    })
    match first {
        success(old) => { if old != 9i64 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i64 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: i64): i64? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10i64 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10i64 { return 6 }
    0
}

fn check_isize(): i32 {
    let cell = core.sync.atomic.AtomicIsize.new(5isize)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: isize): isize? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9isize, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1isize)
    })
    match first {
        success(old) => { if old != 9isize { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10isize || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: isize): isize? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10isize { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10isize { return 6 }
    0
}

fn check_u8(): i32 {
    let cell = core.sync.atomic.AtomicU8.new(5u8)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u8): u8? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9u8, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1u8)
    })
    match first {
        success(old) => { if old != 9u8 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u8 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u8): u8? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10u8 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u8 { return 6 }
    0
}

fn check_u16(): i32 {
    let cell = core.sync.atomic.AtomicU16.new(5u16)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u16): u16? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9u16, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1u16)
    })
    match first {
        success(old) => { if old != 9u16 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u16 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u16): u16? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10u16 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u16 { return 6 }
    0
}

fn check_u32(): i32 {
    let cell = core.sync.atomic.AtomicU32.new(5u32)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u32): u32? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9u32, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1u32)
    })
    match first {
        success(old) => { if old != 9u32 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u32 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u32): u32? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10u32 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u32 { return 6 }
    0
}

fn check_u64(): i32 {
    let cell = core.sync.atomic.AtomicU64.new(5u64)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u64): u64? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9u64, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1u64)
    })
    match first {
        success(old) => { if old != 9u64 { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u64 || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: u64): u64? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10u64 { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10u64 { return 6 }
    0
}

fn check_usize(): i32 {
    let cell = core.sync.atomic.AtomicUsize.new(5usize)
    let calls = core.sync.atomic.AtomicUsize.new(0usize)
    let first = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: usize): usize? {
        let seen = calls.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        if seen == 0usize { cell.store(9usize, core.sync.atomic.Ordering.SeqCst) }
        present(old + 1usize)
    })
    match first {
        success(old) => { if old != 9usize { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10usize || calls.load(core.sync.atomic.Ordering.Relaxed) < 2usize { return 3 }
    let declined = cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: usize): usize? { none })
    match declined {
        success(_) => { return 4 },
        failure(last) => { if last != 10usize { return 5 } }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed) != 10usize { return 6 }
    0
}

fn check_bool(): i32 {
    let flag = core.sync.atomic.AtomicBool.new(false)
    match flag.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: bool): bool? { present(!old) }) {
        success(old) => { if old { return 1 } },
        failure(_) => { return 2 }
    }
    if !flag.load(core.sync.atomic.Ordering.Relaxed) { return 3 }
    match flag.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: bool): bool? { none }) {
        success(_) => { return 4 },
        failure(last) => { if !last { return 5 } }
    }
    0
}

fn check_ptr(): i32 {
    var slots = [1i32, 2i32]
    let first = core.ptr.from_mut(slots[0usize])
    let address = first.addr()
    let cell = core.sync.atomic.AtomicPtr<i32>.new(first)
    match cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: ptr<mut i32>): (ptr<mut i32>)? { present(unsafe { old.add(1usize) }) }) {
        success(old) => { if old.addr() != address { return 1 } },
        failure(_) => { return 2 }
    }
    if cell.load(core.sync.atomic.Ordering.Relaxed).addr() != address + 4usize { return 3 }
    match cell.fetch_update(core.sync.atomic.Ordering.SeqCst, core.sync.atomic.Ordering.Relaxed, fn(old: ptr<mut i32>): (ptr<mut i32>)? { none }) {
        success(_) => { return 4 },
        failure(last) => { if last.addr() != address + 4usize { return 5 } }
    }
    0
}

fn main(): i32 {
    var code = 0i32
    code = check_i8()
    if code != 0 { return 100i32 + code }
    code = check_i16()
    if code != 0 { return 200i32 + code }
    code = check_i32()
    if code != 0 { return 300i32 + code }
    code = check_i64()
    if code != 0 { return 400i32 + code }
    code = check_isize()
    if code != 0 { return 500i32 + code }
    code = check_u8()
    if code != 0 { return 600i32 + code }
    code = check_u16()
    if code != 0 { return 700i32 + code }
    code = check_u32()
    if code != 0 { return 800i32 + code }
    code = check_u64()
    if code != 0 { return 900i32 + code }
    code = check_usize()
    if code != 0 { return 1000i32 + code }
    code = check_bool()
    if code != 0 { return 1100i32 + code }
    code = check_ptr()
    if code != 0 { return 1200i32 + code }
    0
}
