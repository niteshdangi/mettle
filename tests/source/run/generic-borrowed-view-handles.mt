// profiles: debug release
fn keep<region r, T>(mut view: read [T] from r): read [T] from r {
    let original = view
    view = original
    original
}

fn inspect<region r, T>(mut view: mut [T] from r): usize {
    view.len()
}

fn main(): i32 {
    var values = [10, 20]
    let retained: read [i32]
    {
        var view: read [i32] = read values[..]
        assert(keep(mut view)[0usize] == 10, "infer the stored view element")
        assert(keep<i32>(mut view)[1usize] == 20, "explicit element type")
        retained = keep((mut view))
    }
    assert(retained[0usize] == 10, "retain the original region, not the holder")
    {
        var view: mut [i32] = mut values[..]
        assert(inspect(mut view) == 2usize, "exclusive stored view inference")
        assert(inspect<i32>(mut view) == 2usize, "exclusive explicit element")
        assert(inspect((mut view)) == 2usize, "grouped handle borrow")
        view[0usize] = 11
    }
    values[0usize] - 11
}
