import alloc.vec

fn indexed<region r>(source: read i32 from r): read i32 from r {
    var xs = vec.new<read i32 from r>()
    xs.push(source)
    xs[0usize]
}

fn main(): i32 {
    let value = 42
    if indexed(read value) == 42 { 0 } else { 1 }
}
