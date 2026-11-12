fn check_i8(): i32 {
    var scalar = 5i8
    {
        let view = core.sync.atomic.AtomicI8.from_mut(mut scalar)
        if view.fetch_add(2i8, core.sync.atomic.Ordering.Relaxed) != 5i8 { return 1 }
    }
    if scalar != 7i8 { return 2 }
    var items = [1i8, 2i8, 3i8]
    {
        let atoms = core.sync.atomic.AtomicI8.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9i8, core.sync.atomic.Ordering.Relaxed) != 2i8 { return 3 }
    }
    if items[1usize] != 9i8 || items[0usize] != 1i8 { return 4 }
    var cells = [core.sync.atomic.AtomicI8.new(4i8), core.sync.atomic.AtomicI8.new(6i8)]
    {
        let plain = core.sync.atomic.AtomicI8.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4i8 { return 5 }
        plain[1usize] = 8i8
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8i8 { return 6 }
    var raw = 3i8
    let window = unsafe { core.sync.atomic.AtomicI8.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11i8, core.sync.atomic.Ordering.Relaxed)
    if raw != 11i8 { return 7 }
    0
}

fn check_i16(): i32 {
    var scalar = 5i16
    {
        let view = core.sync.atomic.AtomicI16.from_mut(mut scalar)
        if view.fetch_add(2i16, core.sync.atomic.Ordering.Relaxed) != 5i16 { return 1 }
    }
    if scalar != 7i16 { return 2 }
    var items = [1i16, 2i16, 3i16]
    {
        let atoms = core.sync.atomic.AtomicI16.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9i16, core.sync.atomic.Ordering.Relaxed) != 2i16 { return 3 }
    }
    if items[1usize] != 9i16 || items[0usize] != 1i16 { return 4 }
    var cells = [core.sync.atomic.AtomicI16.new(4i16), core.sync.atomic.AtomicI16.new(6i16)]
    {
        let plain = core.sync.atomic.AtomicI16.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4i16 { return 5 }
        plain[1usize] = 8i16
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8i16 { return 6 }
    var raw = 3i16
    let window = unsafe { core.sync.atomic.AtomicI16.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11i16, core.sync.atomic.Ordering.Relaxed)
    if raw != 11i16 { return 7 }
    0
}

fn check_i32(): i32 {
    var scalar = 5i32
    {
        let view = core.sync.atomic.AtomicI32.from_mut(mut scalar)
        if view.fetch_add(2i32, core.sync.atomic.Ordering.Relaxed) != 5i32 { return 1 }
    }
    if scalar != 7i32 { return 2 }
    var items = [1i32, 2i32, 3i32]
    {
        let atoms = core.sync.atomic.AtomicI32.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9i32, core.sync.atomic.Ordering.Relaxed) != 2i32 { return 3 }
    }
    if items[1usize] != 9i32 || items[0usize] != 1i32 { return 4 }
    var cells = [core.sync.atomic.AtomicI32.new(4i32), core.sync.atomic.AtomicI32.new(6i32)]
    {
        let plain = core.sync.atomic.AtomicI32.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4i32 { return 5 }
        plain[1usize] = 8i32
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8i32 { return 6 }
    var raw = 3i32
    let window = unsafe { core.sync.atomic.AtomicI32.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11i32, core.sync.atomic.Ordering.Relaxed)
    if raw != 11i32 { return 7 }
    0
}

fn check_i64(): i32 {
    var scalar = 5i64
    {
        let view = core.sync.atomic.AtomicI64.from_mut(mut scalar)
        if view.fetch_add(2i64, core.sync.atomic.Ordering.Relaxed) != 5i64 { return 1 }
    }
    if scalar != 7i64 { return 2 }
    var items = [1i64, 2i64, 3i64]
    {
        let atoms = core.sync.atomic.AtomicI64.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9i64, core.sync.atomic.Ordering.Relaxed) != 2i64 { return 3 }
    }
    if items[1usize] != 9i64 || items[0usize] != 1i64 { return 4 }
    var cells = [core.sync.atomic.AtomicI64.new(4i64), core.sync.atomic.AtomicI64.new(6i64)]
    {
        let plain = core.sync.atomic.AtomicI64.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4i64 { return 5 }
        plain[1usize] = 8i64
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8i64 { return 6 }
    var raw = 3i64
    let window = unsafe { core.sync.atomic.AtomicI64.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11i64, core.sync.atomic.Ordering.Relaxed)
    if raw != 11i64 { return 7 }
    0
}

fn check_isize(): i32 {
    var scalar = 5isize
    {
        let view = core.sync.atomic.AtomicIsize.from_mut(mut scalar)
        if view.fetch_add(2isize, core.sync.atomic.Ordering.Relaxed) != 5isize { return 1 }
    }
    if scalar != 7isize { return 2 }
    var items = [1isize, 2isize, 3isize]
    {
        let atoms = core.sync.atomic.AtomicIsize.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9isize, core.sync.atomic.Ordering.Relaxed) != 2isize { return 3 }
    }
    if items[1usize] != 9isize || items[0usize] != 1isize { return 4 }
    var cells = [core.sync.atomic.AtomicIsize.new(4isize), core.sync.atomic.AtomicIsize.new(6isize)]
    {
        let plain = core.sync.atomic.AtomicIsize.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4isize { return 5 }
        plain[1usize] = 8isize
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8isize { return 6 }
    var raw = 3isize
    let window = unsafe { core.sync.atomic.AtomicIsize.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11isize, core.sync.atomic.Ordering.Relaxed)
    if raw != 11isize { return 7 }
    0
}

fn check_u8(): i32 {
    var scalar = 5u8
    {
        let view = core.sync.atomic.AtomicU8.from_mut(mut scalar)
        if view.fetch_add(2u8, core.sync.atomic.Ordering.Relaxed) != 5u8 { return 1 }
    }
    if scalar != 7u8 { return 2 }
    var items = [1u8, 2u8, 3u8]
    {
        let atoms = core.sync.atomic.AtomicU8.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9u8, core.sync.atomic.Ordering.Relaxed) != 2u8 { return 3 }
    }
    if items[1usize] != 9u8 || items[0usize] != 1u8 { return 4 }
    var cells = [core.sync.atomic.AtomicU8.new(4u8), core.sync.atomic.AtomicU8.new(6u8)]
    {
        let plain = core.sync.atomic.AtomicU8.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4u8 { return 5 }
        plain[1usize] = 8u8
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8u8 { return 6 }
    var raw = 3u8
    let window = unsafe { core.sync.atomic.AtomicU8.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11u8, core.sync.atomic.Ordering.Relaxed)
    if raw != 11u8 { return 7 }
    0
}

fn check_u16(): i32 {
    var scalar = 5u16
    {
        let view = core.sync.atomic.AtomicU16.from_mut(mut scalar)
        if view.fetch_add(2u16, core.sync.atomic.Ordering.Relaxed) != 5u16 { return 1 }
    }
    if scalar != 7u16 { return 2 }
    var items = [1u16, 2u16, 3u16]
    {
        let atoms = core.sync.atomic.AtomicU16.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9u16, core.sync.atomic.Ordering.Relaxed) != 2u16 { return 3 }
    }
    if items[1usize] != 9u16 || items[0usize] != 1u16 { return 4 }
    var cells = [core.sync.atomic.AtomicU16.new(4u16), core.sync.atomic.AtomicU16.new(6u16)]
    {
        let plain = core.sync.atomic.AtomicU16.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4u16 { return 5 }
        plain[1usize] = 8u16
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8u16 { return 6 }
    var raw = 3u16
    let window = unsafe { core.sync.atomic.AtomicU16.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11u16, core.sync.atomic.Ordering.Relaxed)
    if raw != 11u16 { return 7 }
    0
}

fn check_u32(): i32 {
    var scalar = 5u32
    {
        let view = core.sync.atomic.AtomicU32.from_mut(mut scalar)
        if view.fetch_add(2u32, core.sync.atomic.Ordering.Relaxed) != 5u32 { return 1 }
    }
    if scalar != 7u32 { return 2 }
    var items = [1u32, 2u32, 3u32]
    {
        let atoms = core.sync.atomic.AtomicU32.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9u32, core.sync.atomic.Ordering.Relaxed) != 2u32 { return 3 }
    }
    if items[1usize] != 9u32 || items[0usize] != 1u32 { return 4 }
    var cells = [core.sync.atomic.AtomicU32.new(4u32), core.sync.atomic.AtomicU32.new(6u32)]
    {
        let plain = core.sync.atomic.AtomicU32.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4u32 { return 5 }
        plain[1usize] = 8u32
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8u32 { return 6 }
    var raw = 3u32
    let window = unsafe { core.sync.atomic.AtomicU32.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11u32, core.sync.atomic.Ordering.Relaxed)
    if raw != 11u32 { return 7 }
    0
}

fn check_u64(): i32 {
    var scalar = 5u64
    {
        let view = core.sync.atomic.AtomicU64.from_mut(mut scalar)
        if view.fetch_add(2u64, core.sync.atomic.Ordering.Relaxed) != 5u64 { return 1 }
    }
    if scalar != 7u64 { return 2 }
    var items = [1u64, 2u64, 3u64]
    {
        let atoms = core.sync.atomic.AtomicU64.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9u64, core.sync.atomic.Ordering.Relaxed) != 2u64 { return 3 }
    }
    if items[1usize] != 9u64 || items[0usize] != 1u64 { return 4 }
    var cells = [core.sync.atomic.AtomicU64.new(4u64), core.sync.atomic.AtomicU64.new(6u64)]
    {
        let plain = core.sync.atomic.AtomicU64.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4u64 { return 5 }
        plain[1usize] = 8u64
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8u64 { return 6 }
    var raw = 3u64
    let window = unsafe { core.sync.atomic.AtomicU64.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11u64, core.sync.atomic.Ordering.Relaxed)
    if raw != 11u64 { return 7 }
    0
}

fn check_usize(): i32 {
    var scalar = 5usize
    {
        let view = core.sync.atomic.AtomicUsize.from_mut(mut scalar)
        if view.fetch_add(2usize, core.sync.atomic.Ordering.Relaxed) != 5usize { return 1 }
    }
    if scalar != 7usize { return 2 }
    var items = [1usize, 2usize, 3usize]
    {
        let atoms = core.sync.atomic.AtomicUsize.from_mut_slice(mut items)
        if atoms.len() != 3usize || atoms[1usize].swap(9usize, core.sync.atomic.Ordering.Relaxed) != 2usize { return 3 }
    }
    if items[1usize] != 9usize || items[0usize] != 1usize { return 4 }
    var cells = [core.sync.atomic.AtomicUsize.new(4usize), core.sync.atomic.AtomicUsize.new(6usize)]
    {
        let plain = core.sync.atomic.AtomicUsize.get_mut_slice(mut cells)
        if plain.len() != 2usize || plain[0usize] != 4usize { return 5 }
        plain[1usize] = 8usize
    }
    if cells[1usize].load(core.sync.atomic.Ordering.Relaxed) != 8usize { return 6 }
    var raw = 3usize
    let window = unsafe { core.sync.atomic.AtomicUsize.from_ptr(core.ptr.from_mut(raw)) }
    window.store(11usize, core.sync.atomic.Ordering.Relaxed)
    if raw != 11usize { return 7 }
    0
}

fn check_bool(): i32 {
    var scalar = false
    {
        let view = core.sync.atomic.AtomicBool.from_mut(mut scalar)
        if view.fetch_or(true, core.sync.atomic.Ordering.Relaxed) { return 1 }
    }
    if !scalar { return 2 }
    var items = [false, true]
    {
        let atoms = core.sync.atomic.AtomicBool.from_mut_slice(mut items)
        if atoms.len() != 2usize || !atoms[1usize].swap(false, core.sync.atomic.Ordering.Relaxed) { return 3 }
    }
    if items[1usize] || items[0usize] { return 4 }
    var cells = [core.sync.atomic.AtomicBool.new(true), core.sync.atomic.AtomicBool.new(false)]
    {
        let plain = core.sync.atomic.AtomicBool.get_mut_slice(mut cells)
        if plain.len() != 2usize || !plain[0usize] { return 5 }
        plain[1usize] = true
    }
    if !cells[1usize].load(core.sync.atomic.Ordering.Relaxed) { return 6 }
    var raw = false
    let window = unsafe { core.sync.atomic.AtomicBool.from_ptr(core.ptr.from_mut(raw)) }
    window.store(true, core.sync.atomic.Ordering.Relaxed)
    if !raw { return 7 }
    0
}

fn check_ptr(): i32 {
    var first = 1i32
    var second = 2i32
    let a = core.ptr.from_mut(first)
    let b = core.ptr.from_mut(second)
    let a_address = a.addr()
    let b_address = b.addr()
    var scalar = a
    {
        let view = core.sync.atomic.AtomicPtr<i32>.from_mut(mut scalar)
        if view.swap(b, core.sync.atomic.Ordering.Relaxed).addr() != a_address { return 1 }
    }
    if scalar.addr() != b_address { return 2 }
    var raw = scalar
    let window = unsafe { core.sync.atomic.AtomicPtr<i32>.from_ptr(core.ptr.from_mut(raw)) }
    if window.load(core.sync.atomic.Ordering.Relaxed).addr() != b_address { return 3 }
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
