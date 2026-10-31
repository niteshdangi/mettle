fn main(): i32 {
    var values = [5, 1, 3, 2, 4]
    {
        let slice: read [i32] = read values
        if slice.is_empty() || slice.len() != 5usize { return 1 }
        match slice.get(0usize) {
            present(value) => { if *value != 5 { return 2 } },
            none => { return 2 }
        }
        match slice.first() {
            present(value) => { if *value != 5 { return 3 } },
            none => { return 3 }
        }
        match slice.last() {
            present(value) => { if *value != 4 { return 4 } },
            none => { return 4 }
        }
        if !slice.contains(3) || !slice.starts_with([5, 1]) ||
            !slice.ends_with([2, 4]) || slice.is_sorted() {
            return 5
        }
        match capture slice.binary_search(3) {
            success(index) => { if index != 2usize { return 6 } },
            failure(_) => { return 6 }
        }
        match slice.subslice(1usize, 4usize) {
            present(part) => {
                if part.len() != 3usize || part[0usize] != 1 { return 7 }
            },
            none => { return 7 }
        }
        match slice.window(1usize, 3usize) {
            present(part) => {
                if part.len() != 3usize || part[2usize] != 2 { return 8 }
            },
            none => { return 8 }
        }
        match slice.chunk(1usize, 2usize) {
            present(part) => {
                if part.len() != 2usize || part[0usize] != 3 { return 9 }
            },
            none => { return 9 }
        }
    }

    values.sort_unstable()
    if values[0usize] != 1 || values[4usize] != 5 { return 10 }
    {
        let mutable = mut values
        mutable.swap(0usize, 4usize)
        mutable.reverse()
    }
    if values[0usize] != 1 || values[4usize] != 5 { return 11 }

    var destination = [0, 0, 0, 0, 0]
    {
        let source = read values
        let output = mut destination
        output.copy_from_slice(source)
        if output[0usize] != 1 || output[4usize] != 5 { return 12 }
        output.fill(9)
    }
    if destination[0usize] != 9 || destination[4usize] != 9 { return 13 }
    0
}
