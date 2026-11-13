import alloc.vec

fn main(): i32 {
    var values = [1, 2, 3, 4, 5]
    let slice: read [i32] = read values
    unsafe {
        if core.ptr.`read`(slice.as_ptr()) != 1 { return 22 }
    }
    match slice.as_array<5usize>() {
        present(array) => {
            if array[0usize] != 1 || array[4usize] != 5 { return 1 }
        },
        none => { return 2 }
    }
    if slice.as_array<4usize>().is_present() { return 3 }
    match slice.strip_circumfix([1], [5]) {
        present(middle) => {
            if middle.len() != 3usize || middle[0usize] != 2 ||
                middle[2usize] != 4 {
                return 18
            }
        },
        none => { return 19 }
    }
    if slice.strip_circumfix([2], [5]).is_present() { return 20 }

    let chunks = slice.as_chunks<2usize>()
    if chunks.0.len() != 2usize || chunks.0[1usize][0usize] != 3 ||
        chunks.1.len() != 1usize || chunks.1[0usize] != 5 {
        return 4
    }
    let flattened = chunks.0.as_flattened()
    if flattened.len() != 4usize || flattened[0usize] != 1 ||
        flattened[3usize] != 4 {
        return 5
    }

    let reverse_chunks = slice.as_rchunks<2usize>()
    if reverse_chunks.0.len() != 1usize || reverse_chunks.0[0usize] != 1 ||
        reverse_chunks.1.len() != 2usize ||
        reverse_chunks.1[0usize][0usize] != 2 ||
        reverse_chunks.1[1usize][1usize] != 5 {
        return 6
    }

    {
        let mutable = mut values
        let array = mutable.as_mut_array<5usize>()
        match take array {
            present(array) => { array[0usize] = 9 },
            none => { return 7 }
        }
        let parts = mutable.as_chunks_mut<2usize>()
        let flattened = parts.0.as_flattened_mut()
        flattened[1usize] = 8
        parts.1[0usize] = 7
        let pointer = mutable.as_mut_ptr()
        unsafe { core.ptr.write(pointer.add(4usize), 6) }
        let pointer_range = mutable.as_mut_ptr_range()
        unsafe { core.ptr.write(pointer_range.start.add(3usize), 10) }
    }
    if values[0usize] != 9 || values[1usize] != 8 ||
        values[3usize] != 10 || values[4usize] != 6 {
        return 8
    }

    var reverse_values = [1, 2, 3, 4, 5]
    {
        let mutable = mut reverse_values
        let parts = mutable.as_rchunks_mut<2usize>()
        parts.0[0usize] = 0
        parts.1[0usize][0usize] = 7
        parts.1[1usize][1usize] = 9
    }
    if reverse_values[0usize] != 0 || reverse_values[1usize] != 7 ||
        reverse_values[4usize] != 9 {
        return 9
    }

    var exact_chunks = [1, 2, 3, 4]
    let exact_slice: read [i32] = read exact_chunks
    unsafe {
        let groups = exact_slice.as_chunks_unchecked<2usize>()
        if groups.len() != 2usize || groups[1usize][1usize] != 4 {
            return 10
        }
    }
    {
        let mutable = mut exact_chunks
        unsafe {
            let groups = mutable.as_chunks_unchecked_mut<2usize>()
            groups[0usize][0usize] = 6
        }
    }
    if exact_chunks[0usize] != 6 { return 11 }
    var empty: [i32; 0] = []
    let empty_slice: read [i32] = read empty
    let empty_parts = empty_slice.as_chunks<3usize>()
    if !empty_parts.0.is_empty() || !empty_parts.1.is_empty() {
        return 21
    }

    var bytes: [u8; 7] = [32, 65, 98, 32, 9, 67, 13]
    let byte_view: read [u8] = read bytes
    if !byte_view.is_ascii() ||
        byte_view.trim_ascii().len() != 5usize ||
        byte_view.trim_ascii()[0usize] != 65u8 ||
        byte_view.trim_ascii_start()[0usize] != 65u8 ||
        byte_view.trim_ascii_end()[5usize] != 67u8 {
        return 12
    }
    var other: [u8; 3] = [97, 66, 32]
    let other_view: read [u8] = read other
    if !byte_view.subslice(1usize, 4usize).or_panic().eq_ignore_ascii_case(
        other_view.subslice(0usize, 3usize).or_panic()
    ) {
        return 13
    }
    {
        let mutable = mut bytes
        mutable.make_ascii_lowercase()
    }
    if bytes[1usize] != 97u8 || bytes[2usize] != 98u8 { return 14 }
    {
        let mutable = mut bytes
        mutable.make_ascii_uppercase()
    }
    if bytes[1usize] != 65u8 || bytes[2usize] != 66u8 { return 15 }
    var non_ascii: [u8; 2] = [65, 255]
    let non_ascii_view: read [u8] = read non_ascii
    if non_ascii_view.is_ascii() { return 16 }
    let lower = non_ascii_view.to_ascii_lowercase()
    let upper = non_ascii_view.to_ascii_uppercase()
    if lower[0usize] != 97u8 || lower[1usize] != 255u8 ||
        upper[0usize] != 65u8 || upper[1usize] != 255u8 {
        return 17
    }
    0
}
