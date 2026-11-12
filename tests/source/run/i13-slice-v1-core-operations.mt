import core.iter.BidirectionalIterator
import core.iter.Iterator
import core.cmp.{Ord, Ordering}

fn main(): i32 {
    var values = [1, 2, 3, 4, 5]
    let slice: read [i32] = read values
    if unsafe { *slice.get_unchecked(2usize) } != 3 { return 20 }
    let pointer_range: core.iter.Range<ptr<read i32>> = slice.as_ptr_range()
    let _ = pointer_range
    let first_chunk = slice.first_chunk<2usize>()
    match first_chunk {
        present(chunk) => { if chunk[0usize] != 1 || chunk[1usize] != 2 { return 77 } },
        none => { return 77 }
    }
    let last_chunk = slice.last_chunk<2usize>()
    match last_chunk {
        present(chunk) => { if chunk[0usize] != 4 || chunk[1usize] != 5 { return 78 } },
        none => { return 78 }
    }
    let first_parts = slice.split_first_chunk<2usize>()
    match first_parts {
        present(parts) => {
            if parts.0[1usize] != 2 || parts.1.len() != 3usize || parts.1[0usize] != 3 {
                return 79
            }
        },
        none => { return 79 }
    }
    let last_parts = slice.split_last_chunk<2usize>()
    match last_parts {
        present(parts) => {
            if parts.0.len() != 3usize || parts.0[2usize] != 3 || parts.1[0usize] != 4 {
                return 80
            }
        },
        none => { return 80 }
    }
    match slice.split_first() {
        present(parts) => {
            if *parts.0 != 1 || parts.1.len() != 4usize || parts.1[0usize] != 2 {
                return 1
            }
        },
        none => { return 1 }
    }
    match slice.split_last() {
        present(parts) => {
            if *parts.0 != 5 || parts.1.len() != 4usize || parts.1[3usize] != 4 {
                return 2
            }
        },
        none => { return 2 }
    }
    match slice.strip_prefix([1, 2]) {
        present(rest) => { if rest.len() != 3usize || rest[0usize] != 3 { return 3 } },
        none => { return 3 }
    }
    match slice.strip_suffix([4, 5]) {
        present(rest) => { if rest.len() != 3usize || rest[2usize] != 3 { return 4 } },
        none => { return 4 }
    }

    var chunks = slice.chunks(2usize)
    match chunks.next() {
        present(part) => { if part.len() != 2usize || part[0usize] != 1 { return 5 } },
        none => { return 5 }
    }
    match chunks.next_back() {
        present(part) => { if part.len() != 1usize || part[0usize] != 5 { return 6 } },
        none => { return 6 }
    }
    match chunks.next() {
        present(part) => { if part[0usize] != 3 { return 7 } },
        none => { return 7 }
    }
    match chunks.next() { none => {}, present(_) => { return 8 } }
    var exact_chunks = slice.chunks_exact(2usize)
    match exact_chunks.next_back() {
        present(part) => { if part[0usize] != 3 || part[1usize] != 4 { return 41 } },
        none => { return 41 }
    }
    if exact_chunks.remainder().len() != 1usize ||
        exact_chunks.remainder()[0usize] != 5 {
        return 42
    }
    var reverse_chunks = slice.rchunks(2usize)
    match reverse_chunks.next() {
        present(part) => { if part[0usize] != 4 || part[1usize] != 5 { return 43 } },
        none => { return 43 }
    }
    match reverse_chunks.next_back() {
        present(part) => { if part.len() != 1usize || part[0usize] != 1 { return 44 } },
        none => { return 44 }
    }
    var reverse_exact = slice.rchunks_exact(2usize)
    match reverse_exact.next() {
        present(part) => { if part[0usize] != 4 || part[1usize] != 5 { return 45 } },
        none => { return 45 }
    }
    if reverse_exact.remainder().len() != 1usize ||
        reverse_exact.remainder()[0usize] != 1 {
        return 46
    }

    var windows = slice.windows(3usize)
    match windows.next() {
        present(part) => { if part[0usize] != 1 || part[2usize] != 3 { return 9 } },
        none => { return 9 }
    }
    match windows.next() {
        present(part) => { if part[0usize] != 2 || part[2usize] != 4 { return 10 } },
        none => { return 10 }
    }

    {
        let mutable = mut values
        unsafe { *mutable.get_unchecked_mut(0usize) = 11 }
        if mutable[0usize] != 11 { return 20 }
        let chunk = mutable.first_chunk_mut<2usize>()
        match take chunk {
            present(values) => { values[0usize] = 12 },
            none => { return 81 }
        }
        if mutable[0usize] != 12 || mutable[1usize] != 2 { return 81 }
        let parts = mutable.split_first_chunk_mut<2usize>()
        match take parts {
            present(values) => { values.0[1usize] = 22; values.1[0usize] = 33 },
            none => { return 82 }
        }
        if mutable[0usize] != 12 || mutable[1usize] != 22 || mutable[2usize] != 33 {
            return 82
        }
        let last = mutable.last_chunk_mut<2usize>()
        match take last {
            present(values) => { values[1usize] = 55 },
            none => { return 83 }
        }
        if mutable[3usize] != 4 || mutable[4usize] != 55 { return 83 }
        let tail = mutable.split_last_chunk_mut<2usize>()
        match take tail {
            present(values) => { values.0[0usize] = 14; values.1[0usize] = 44 },
            none => { return 84 }
        }
        if mutable[0usize] != 14 || mutable[2usize] != 33 ||
            mutable[3usize] != 44 || mutable[4usize] != 55 { return 84 }
        match take mutable.split_first_mut() {
            present(parts) => { *parts.0 = 10; parts.1[0usize] = 20 },
            none => { return 11 }
        }
        mutable.rotate_left(2usize)
        if mutable[0usize] != 33 || mutable[4usize] != 20 { return 12 }
        mutable.rotate_right(2usize)
        if mutable[0usize] != 10 || mutable[1usize] != 20 { return 13 }
        mutable.copy_within(0usize, 3usize, 1usize)
        if mutable[1usize] != 10 || mutable[3usize] != 33 { return 14 }
        mutable.fill_with(fn(): i32 { 7 })
        if mutable[0usize] != 7 || mutable[4usize] != 7 { return 15 }
        {
            var mutable_chunks = mutable.chunks_mut(2usize)
            match take mutable_chunks.next_back() {
                present(part) => {
                    if part.len() != 1usize { return 23 }
                    part[0usize] = 6
                },
                none => { return 23 }
            }
            match take mutable_chunks.next() {
                present(part) => { part[1usize] = 8 },
                none => { return 24 }
            }
        }
        if mutable[1usize] != 8 || mutable[4usize] != 6 { return 25 }
        {
            var exact = mutable.chunks_exact_mut(2usize)
            match take exact.next() {
                present(part) => { part[0usize] = 3 },
                none => { return 47 }
            }
            let remainder = exact.remainder()
            if remainder.len() != 1usize { return 48 }
            remainder[0usize] = 5
        }
        if mutable[0usize] != 3 || mutable[4usize] != 5 { return 47 }
        {
            var reverse = mutable.rchunks_mut(2usize)
            match take reverse.next_back() {
                present(part) => { if part.len() != 1usize { return 49 }; part[0usize] = 4 },
                none => { return 49 }
            }
        }
        if mutable[0usize] != 4 { return 49 }
        {
            var reverse = mutable.rchunks_exact_mut(2usize)
            let remainder = reverse.remainder()
            if remainder.len() != 1usize { return 50 }
            remainder[0usize] = 2
        }
        if mutable[0usize] != 2 { return 50 }
        var iter = mutable.iter_mut()
        match take iter.next() { present(_) => {}, none => { return 21 } }
        let remaining = take iter.into_slice()
        if remaining.len() != 4usize { return 22 }
    }

    var source = [8, 9]
    {
        let left = mut values[0usize..2usize]
        let right = mut source
        left.swap_with_slice(right)
    }
    if values[0usize] != 8 || values[1usize] != 9 ||
        source[0usize] != 2 || source[1usize] != 8 {
        return 16
    }
    {
        let output = mut values[2usize..4usize]
        output.clone_from_slice([4, 5])
    }
    if values[2usize] != 4 || values[3usize] != 5 { return 17 }

    var empty: [i32; 0] = []
    let empty_slice: read [i32] = read empty
    if empty_slice.split_first().is_present() || empty_slice.windows(1usize).next().is_present() {
        return 18
    }
    let empty_chunk = empty_slice.first_chunk<1usize>()
    if empty_chunk.is_present() { return 85 }
    var singleton = [42]
    let one: read [i32] = read singleton
    match one.split_last() {
        present(parts) => { if *parts.0 != 42 || !parts.1.is_empty() { return 19 } },
        none => { return 19 }
    }
    var array = [4, 5, 6]
    let refs = array.each_ref()
    if *refs[0usize] != 4 || *refs[2usize] != 6 { return 26 }
    {
        let refs_mut = array.each_mut()
        *refs_mut[0usize] = 7
        *refs_mut[2usize] = 9
    }
    if array[0usize] != 7 || array[2usize] != 9 { return 27 }
    let split_values = [1, 0, 2, 0, 3]
    let split_slice: read [i32] = read split_values
    var split = split_slice.split(fn(read value: i32): bool { value == 0 })
    match split.next() { present(part) => { if part.len() != 1usize || part[0usize] != 1 { return 51 } }, none => { return 51 } }
    match split.next_back() { present(part) => { if part[0usize] != 3 { return 52 } }, none => { return 52 } }
    match split.next() { present(part) => { if part[0usize] != 2 { return 53 } }, none => { return 53 } }
    match split.next() { present(_) => { return 54 }, none => {} }
    var split_limit = split_slice.splitn(2usize, fn(read value: i32): bool { value == 0 })
    match split_limit.next() { present(part) => { if part[0usize] != 1 { return 55 } }, none => { return 55 } }
    match split_limit.next() {
        present(part) => { if part.len() != 3usize || part[0usize] != 2 { return 56 } },
        none => { return 56 }
    }
    var reverse_limit = split_slice.rsplitn(2usize, fn(read value: i32): bool { value == 0 })
    match reverse_limit.next() { present(part) => { if part[0usize] != 3 { return 57 } }, none => { return 57 } }
    match reverse_limit.next() {
        present(part) => { if part.len() != 3usize || part[0usize] != 1 { return 58 } },
        none => { return 58 }
    }
    var inclusive = split_slice.split_inclusive(fn(read value: i32): bool { value == 0 })
    match inclusive.next() {
        present(part) => { if part.len() != 2usize || part[1usize] != 0 { return 59 } },
        none => { return 59 }
    }
    match inclusive.next_back() {
        present(part) => { if part[0usize] != 3 || part.len() != 1usize { return 60 } },
        none => { return 60 }
    }
    match inclusive.next() { present(part) => { if part[0usize] != 2 { return 61 } }, none => { return 61 } }
    match inclusive.next() { present(_) => { return 62 }, none => {} }
    var grouped = [1, 1, 2, 3, 3]
    {
        let grouped_slice: read [i32] = read grouped
        var groups = grouped_slice.chunk_by(fn(read a: i32, read b: i32): bool { a == b })
        match groups.next() { present(part) => { if part.len() != 2usize { return 63 } }, none => { return 63 } }
        match groups.next_back() { present(part) => { if part.len() != 2usize { return 64 } }, none => { return 64 } }
        match groups.next() { present(part) => { if part[0usize] != 2 { return 65 } }, none => { return 65 } }
    }
    var grouped_mut = mut grouped
    {
        var groups = grouped_mut.chunk_by_mut(fn(read a: i32, read b: i32): bool { a == b })
        match take groups.next() { present(part) => { part[0usize] = 9 }, none => { return 66 } }
    }
    if grouped[0usize] != 9 { return 67 }
    var split_mut_values = [1, 0, 2]
    {
        let mutable = mut split_mut_values
        var parts = mutable.split_mut(fn(read value: i32): bool { value == 0 })
        match take parts.next() {
            present(part) => { part[0usize] = 7 },
            none => { return 68 }
        }
    }
    if split_mut_values[0usize] != 7 { return 69 }
    var inclusive_mut_values = [1, 0, 2]
    {
        let mutable = mut inclusive_mut_values
        var parts = mutable.split_inclusive_mut(fn(read value: i32): bool { value == 0 })
        match take parts.next() {
            present(part) => { part[0usize] = 8; part[1usize] = 9 },
            none => { return 70 }
        }
    }
    if inclusive_mut_values[0usize] != 8 || inclusive_mut_values[1usize] != 9 { return 71 }
    var selected = [9, 1, 7, 3, 5]
    {
        let mutable = mut selected
        let parts = take mutable.select_nth_unstable(2usize)
        if *parts.1 != 5 || parts.0.len() != 2usize || parts.2.len() != 2usize {
            return 72
        }
        if parts.0[0usize] >= *parts.1 || parts.2[1usize] <= *parts.1 { return 73 }
    }
    var keyed = [6, 2, 4, 1, 5]
    {
        let mutable = mut keyed
        let parts = take mutable.select_nth_unstable_by(
            1usize,
            fn(read a: i32, read b: i32): Ordering { a.cmp(b) }
        )
        if *parts.1 != 2 { return 74 }
    }
    var projected = [6, 2, 4, 1, 5]
    {
        let mutable = mut projected
        let parts = take mutable.select_nth_unstable_by_key(
            3usize,
            fn(read value: i32): i32 { value }
        )
        if *parts.1 != 5 { return 75 }
    }
    0
}
