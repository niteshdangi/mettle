static mut DROPS: usize = 0usize

type Empty {
    drop { unsafe { DROPS += 1usize } }
}

fn main(): i32 {
    var values = alloc.vec.new<i32>()
    var next = 1
    while next <= 6 {
        values.push(next + 0)
        next += 1
    }
    let capacity = values.capacity()
    let pointer = values.as_ptr()
    var visits = 0
    values.retain(fn(value: read i32): bool {
        visits += 1
        assert(value == visits, "retain visits elements in order")
        visits % 2 == 0
    })
    assert(visits == 6, "retain visits each element once")
    assert(values.len() == 3usize, "retain length")
    assert(values[0usize] == 2 && values[1usize] == 4 && values[2usize] == 6, "retain order")
    assert(values.capacity() == capacity && values.as_ptr() == pointer, "retain keeps allocation")

    visits = 0
    values.retain_mut(fn(value: mut i32): bool {
        visits += 1
        value += visits
        visits != 2
    })
    assert(visits == 3, "retain_mut visits each element once")
    assert(values.len() == 2usize, "retain_mut length")
    assert(values[0usize] == 3 && values[1usize] == 9, "retain_mut preserves mutations and order")

    visits = 0
    values.retain(fn(value: read i32): bool {
        visits += 1
        true
    })
    assert(visits == 2 && values.len() == 2usize, "retain all")
    values.retain_mut(fn(value: mut i32): bool { false })
    assert(values.is_empty(), "retain none")
    values.retain(fn(value: read i32): bool {
        visits += 1
        true
    })
    values.retain_mut(fn(value: mut i32): bool {
        visits += 1
        true
    })
    assert(visits == 2, "empty list does not call predicates")

    var units = alloc.vec.new<Unit>()
    units.push(())
    units.push(())
    units.push(())
    visits = 0
    units.retain(fn(value: read Unit): bool {
        visits += 1
        visits == 2
    })
    assert(visits == 3 && units.len() == 1usize, "retain zero-sized elements")
    units.retain_mut(fn(value: mut Unit): bool { false })
    assert(units.is_empty(), "retain_mut zero-sized elements")
    {
        var owned_units = alloc.vec.new<Empty>()
        owned_units.push(Empty())
        owned_units.push(Empty())
        owned_units.push(Empty())
        visits = 0
        owned_units.retain(fn(value: read Empty): bool {
            visits += 1
            visits == 2
        })
        assert(visits == 3 && owned_units.len() == 1usize, "retain zero-sized owners")
        unsafe { assert(DROPS == 2usize, "removed zero-sized owners dropped once") }
        owned_units.retain_mut(fn(value: mut Empty): bool { false })
        unsafe { assert(DROPS == 3usize, "retain_mut zero-sized owner dropped once") }
    }
    unsafe { assert(DROPS == 3usize, "zero-sized owners not double-dropped") }
    0
}
