fn main(): i32 {
    var values = [10, 20, 30, 40]
    {
        let slice = mut values
        match slice.get_disjoint_mut<2usize>([0usize, 3usize]) {
            present(parts) => {
                let tmp = *parts[0usize]
                *parts[0usize] = *parts[1usize]
                *parts[1usize] = tmp
            },
            none => { return 1 }
        }
        if !slice.get_disjoint_mut<2usize>([1usize, 1usize]).is_none() { return 2 }
        if !slice.get_disjoint_mut<2usize>([0usize, 4usize]).is_none() { return 3 }
        if !slice.get_disjoint_mut<1usize>([99usize]).is_none() { return 4 }
        match slice.get_disjoint_mut<0usize>([]) {
            present(_) => {},
            none => { return 5 }
        }
    }
    if values[0usize] != 40 || values[3usize] != 10 || values[1usize] != 20 { return 6 }
    {
        let slice = mut values
        let parts = unsafe { slice.get_disjoint_unchecked_mut<3usize>([2usize, 0usize, 1usize]) }
        *parts[0usize] += 1
        *parts[1usize] += 2
        *parts[2usize] += 3
    }
    if values[2usize] != 31 || values[0usize] != 42 || values[1usize] != 23 { return 7 }
    0
}
