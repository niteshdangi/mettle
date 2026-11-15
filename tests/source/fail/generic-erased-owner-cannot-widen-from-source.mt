// expect-error: region 6:5 erased owner payload view does not outlive
// expect-error: region 11:25 view region or invariant payload
interface Show { fn value(): i32; }

fn erase_static<region r, T: Show>(take value: T from r): heap any Show {
    heap value
}

fn extend_owner_borrow<region r>(
    read owner: heap any Show from r
): read any Show from r {
    read owner
}

fn main(): i32 { 0 }
