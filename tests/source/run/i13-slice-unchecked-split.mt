fn main(): i32 {
    var values = [1, 2, 3, 4]
    let slice: read [i32] = read values
    let empty_prefix = unsafe { slice.split_at_unchecked(0usize) }
    if empty_prefix.0.len() != 0usize || empty_prefix.1.len() != 4usize {
        return 1
    }
    let empty_suffix = unsafe { slice.split_at_unchecked(4usize) }
    if empty_suffix.0.len() != 4usize || empty_suffix.1.len() != 0usize {
        return 2
    }
    let halves = unsafe { slice.split_at_unchecked(2usize) }
    if halves.0[1usize] != 2 || halves.1[0usize] != 3 { return 3 }

    {
        let view: mut [i32] = mut values
        let parts = unsafe { view.split_at_mut_unchecked(0usize) }
        if parts.0.len() != 0usize || parts.1.len() != 4usize { return 4 }
    }
    {
        let view: mut [i32] = mut values
        let parts = unsafe { view.split_at_mut_unchecked(4usize) }
        if parts.0.len() != 4usize || parts.1.len() != 0usize { return 5 }
    }
    {
        let view: mut [i32] = mut values
        let parts = unsafe { view.split_at_mut_unchecked(2usize) }
        var left = parts.0
        var right = parts.1
        left[1usize] = 20
        right[0usize] = 30
    }
    if values[0usize] != 1 || values[1usize] != 20 ||
        values[2usize] != 30 || values[3usize] != 4 {
        return 6
    }
    0
}
