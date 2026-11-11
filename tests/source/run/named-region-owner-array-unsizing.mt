type Tail<T: unsized> { header: i32; values: T }

fn sliced<region r>(read value: i32 from r): heap [read i32 from r] {
    let array = heap [read value]
    let slice: heap [read i32 from r] = take array
    take slice
}

fn tail_sliced<region r>(read value: i32 from r): heap Tail<[read i32 from r]> {
    let array = heap Tail(7, [read value])
    let slice: heap Tail<[read i32 from r]> = take array
    take slice
}

fn main(): i32 {
    let value = 42
    let slice = sliced(read value)
    if *slice.get()[0usize] != 42 { return 1 }
    let tail = tail_sliced(read value)
    if tail.get().header != 7 || *tail.get().values[0usize] != 42 { return 2 }
    0
}
