interface Category {
    fn category(): usize;
}

extend<const N: usize> [i32; N] implements Category {
    fn category(): usize { 1usize }
}

extend<region r, const N: usize> read [i32; N] from r implements Category {
    fn category(): usize { 2usize }
}

extend<F: fn(i32): bool> F implements Category {
    fn category(): usize { 3usize }
}

fn classify<T: Category>(value: read T): usize {
    value.category()
}

fn main(): i32 {
    let values = [1, 2, 3]
    assert(classify(read values) == 1usize, "generic array does not overlap callable")
    let view = read values
    assert(classify(read view) == 2usize, "generic array view does not overlap callable")
    let predicate = fn(value: i32): bool { value > 0 }
    assert(classify(read predicate) == 3usize, "callable blanket still selected")
    0
}
