fn main(): i32 {
    var rows = [[0i64; 129]; 2]
    rows[0][1] = 11i64
    rows[1][0] = 42i64
    {
        let all: read [[i64; 129]] = read rows[..]
        let tail: read [[i64; 129]] = read all[1..]
        if tail[0][0] != 42i64 { return 1 }
        let empty: read [[i64; 129]] = read all[2..]
        if empty.len() != 0usize { return 2 }
    }
    let base = core.ptr.from_mut(rows[0])
    let pointer = core.sync.atomic.AtomicPtr<[i64; 129]>.new(base)
    let order = core.sync.atomic.Ordering.Relaxed
    let old = pointer.fetch_ptr_add(1usize, order)
    let next = pointer.load(order)
    if old != base ||
       next.addr() - base.addr() != core.mem.size_of<[i64; 129]>() {
        return 3
    }
    let previous = pointer.fetch_ptr_sub(1usize, order)
    if previous != next || pointer.load(order) != base { return 4 }
    let byte_old = pointer.fetch_byte_add(1usize, order)
    if byte_old != base || pointer.load(order).addr() - base.addr() != 1usize {
        return 5
    }
    0
}
