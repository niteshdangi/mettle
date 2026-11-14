// profiles: debug release
import core.iter.BidirectionalIterator
import core.iter.{ ExactSizeIterator, Iterator }
import core.clone.Clone
import core.fmt
import core.fmt.Debug
import core.text.Text

fn sum_read(read part: [i32]): i32 {
    var total = 0
    var i = 0usize
    while i < part.len() { total += part[i]; i += 1usize }
    total
}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    var values = [1, 2, 3, 4, 5, 6, 7]
    {
        let slice: read [i32] = read values

        // chunks: forward iteration yields full groups then the short tail.
        var chunks = slice.chunks(3usize)
        if chunks.size_hint().0 != 3usize || chunks.len() != 3usize { return 1 }
        match take chunks.next() {
            present(part) => { if part.len() != 3usize || sum_read(part) != 6 { return 2 } },
            none => { return 2 }
        }
        match take chunks.next() {
            present(part) => { if part[0usize] != 4 || part[2usize] != 6 { return 3 } },
            none => { return 3 }
        }
        match take chunks.next_back() {
            present(part) => { if part.len() != 1usize || part[0usize] != 7 { return 4 } },
            none => { return 4 }
        }
        if chunks.next().is_present() { return 5 }

        // chunks larger than the slice yield one short chunk.
        var whole = slice.chunks(100usize)
        match take whole.next() {
            present(part) => { if part.len() != 7usize { return 6 } },
            none => { return 6 }
        }
        if whole.next().is_present() { return 7 }

        // chunks_exact drops the tail, exposing it through remainder().
        var exact = slice.chunks_exact(2usize)
        var exact_count = 0usize
        while true {
            match take exact.next() {
                present(part) => { exact_count += 1usize; if part.len() != 2usize { return 8 } },
                none => { break }
            }
        }
        if exact_count != 3usize || exact.remainder().len() != 1usize { return 9 }
        if exact.remainder()[0usize] != 7 { return 10 }

        // rchunks groups from the end; the short chunk comes last.
        var reverse = slice.rchunks(3usize)
        match take reverse.next() {
            present(part) => { if part[0usize] != 5 || part[2usize] != 7 { return 11 } },
            none => { return 11 }
        }
        match take reverse.next() {
            present(part) => { if part.len() != 3usize || part[0usize] != 2 { return 12 } },
            none => { return 12 }
        }
        match take reverse.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 1 { return 13 } },
            none => { return 13 }
        }

        // rchunks_exact keeps only full groups counted from the end.
        var reverse_exact = slice.rchunks_exact(3usize)
        match take reverse_exact.next_back() {
            present(part) => { if part[0usize] != 2 || part[2usize] != 4 { return 14 } },
            none => { return 14 }
        }
        if reverse_exact.remainder().len() != 1usize || reverse_exact.remainder()[0usize] != 1 {
            return 15
        }

        // windows: every contiguous run of length n; none when n exceeds len.
        var windows = slice.windows(5usize)
        if windows.size_hint().0 != 3usize || windows.len() != 3usize { return 16 }
        match take windows.next_back() {
            present(part) => { if part[0usize] != 3 || part[4usize] != 7 { return 17 } },
            none => { return 17 }
        }
        var window_count = 0usize
        for part in slice.windows(7usize) {
            window_count += 1usize
            if part.len() != 7usize || part[6usize] != 7 { return 18 }
        }
        if window_count != 1usize { return 19 }
        if slice.windows(8usize).next().is_present() { return 20 }

        // chunk and window indexing agree with the iterator forms.
        match slice.chunk(2usize, 3usize) {
            present(part) => { if part[0usize] != 7 || part.len() != 1usize { return 21 } },
            none => { return 21 }
        }
        if slice.chunk(3usize, 3usize).is_present() { return 22 }
        match slice.window(4usize, 3usize) {
            present(part) => { if part[2usize] != 7 { return 23 } },
            none => { return 23 }
        }
        if slice.window(5usize, 3usize).is_present() { return 24 }

        // chunk_by splits at every change of predicate result.
        var runs = [1, 1, 2, 3, 3, 3]
        let run_slice: read [i32] = read runs
        var groups = run_slice.chunk_by(fn(read a: i32, read b: i32): bool { a == b })
        var group_count = 0usize
        while true {
            match take groups.next() {
                present(part) => { group_count += 1usize; if part.len() == 0usize { return 25 } },
                none => { break }
            }
        }
        if group_count != 3usize { return 26 }
        var clone_groups = run_slice.chunk_by(fn(read a: i32, read b: i32): bool { a == b })
        match clone_groups.next() {
            present(part) => { if part.len() != 2usize || part[0usize] != 1 { return 27 } },
            none => { return 27 }
        }
        var clone_groups_copy = clone_groups.clone()
        match clone_groups.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 2 { return 28 } },
            none => { return 28 }
        }
        match clone_groups_copy.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 2 { return 28 } },
            none => { return 28 }
        }
    }

    // Mutable chunking writes through every group.
    var mutable_values = [1, 2, 3, 4, 5, 6, 7]
    {
        let mutable = mut mutable_values
        var chunks = mutable.chunks_mut(3usize)
        match take chunks.next() {
            present(part) => { part[0usize] = 10 },
            none => { return 30 }
        }
        match take chunks.next_back() {
            present(part) => { part[0usize] = 70 },
            none => { return 31 }
        }
    }
    if mutable_values[0usize] != 10 || mutable_values[6usize] != 70 || mutable_values[3usize] != 4 {
        return 32
    }

    {
        let mutable = mut mutable_values
        var exact = mutable.chunks_exact_mut(2usize)
        match take exact.next() {
            present(part) => { part[1usize] = 20 },
            none => { return 33 }
        }
        var reverse = mutable.rchunks_mut(4usize)
        match take reverse.next() {
            present(part) => { part[0usize] = 50 },
            none => { return 34 }
        }
    }
    if mutable_values[1usize] != 20 || mutable_values[3usize] != 50 { return 35 }

    // as_chunks and as_rchunks split off fixed-size arrays and a remainder.
    var grid = [1, 2, 3, 4, 5, 6, 7]
    {
        let slice: read [i32] = read grid
        let front = slice.as_chunks<3usize>()
        if front.0.len() != 2usize || front.1.len() != 1usize { return 40 }
        if front.0[1usize][2usize] != 6 || front.1[0usize] != 7 { return 41 }
        let back = slice.as_rchunks<3usize>()
        if back.0.len() != 1usize || back.1.len() != 2usize { return 42 }
        if back.0[0usize] != 1 || back.1[0usize][0usize] != 2 { return 43 }
        let empty = slice.split_at(0usize).0
        let none_parts = empty.as_chunks<2usize>()
        if none_parts.0.len() != 0usize || none_parts.1.len() != 0usize { return 44 }
    }
    {
        let mutable = mut grid
        let parts = mutable.as_chunks_mut<2usize>()
        parts.0[2usize][1usize] = 90
        parts.1[0usize] = 91
    }
    if grid[5usize] != 90 || grid[6usize] != 91 { return 45 }

    // first_chunk / last_chunk / split_*_chunk with a const length.
    let short = [8, 9]
    let short_slice: read [i32] = read short
    if short_slice.first_chunk<3usize>().is_present() { return 46 }
    match short_slice.last_chunk<2usize>() {
        present(part) => { if part[0usize] != 8 { return 47 } },
        none => { return 47 }
    }

    let debug_values = [1, 2, 3, 4, 5]
    let debug_slice: read [i32] = read debug_values
    var debug_chunks = debug_slice.chunks(2usize)
    if !debug_chunks.next().is_present() { return 48 }
    let copied_chunks = debug_chunks.clone()
    if !debug_is(read copied_chunks, "Chunks([3, 4], [5])") { return 49 }
    match take debug_chunks.next_back() {
        present(part) => { if part[0usize] != 5 { return 50 } },
        none => { return 50 }
    }
    var debug_windows = debug_slice.windows(2usize)
    if !debug_windows.next().is_present() { return 51 }
    let copied_windows = debug_windows.clone()
    if !debug_is(read copied_windows, "Windows([2, 3], [3, 4], [4, 5])") {
        return 52
    }
    match take debug_windows.next_back() {
        present(part) => { if part[0usize] != 4 || part[1usize] != 5 { return 53 } },
        none => { return 53 }
    }
    0
}
