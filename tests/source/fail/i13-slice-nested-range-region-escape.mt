// expect-error: region 4:64 view region or invariant payload
copy type ReadBuffer<region r> { data: read u8 from r }

fn invalid<region r>(read fallback: u8 from r): read u8 from r {
    let value = 1u8
    let values = [ReadBuffer(read value)]
    let window = read values[..]
    let _ = fallback
    (*window)[0usize].data
}

fn main(): i32 { 0 }
