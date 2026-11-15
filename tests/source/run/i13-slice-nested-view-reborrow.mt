copy type ReadBuffer<region r> { data: read [u8] from r }
type MutBuffer<region r> { data: mut [u8] from r }

extend<region r> MutBuffer<region r> {
    mut fn advance(): Unit {
        self.data = self.data.split_at_mut(1usize).1
    }
}

fn read_element<region s, region r>(
    mut bufs: mut [ReadBuffer<region r>] from s
): Unit {
    let first = read (*bufs)[0usize]
    core.mem.drop(take first)
}

fn mutate_element<region s, region r>(
    mut bufs: mut [MutBuffer<region r>] from s
): Unit {
    var first = mut (*bufs)[0usize]
    first.data = first.data.split_at_mut(1usize).1
    core.mem.drop(take first)
}

fn advance_slices<region s, region r>(
    mut bufs: mut [MutBuffer<region r>] from s
): Unit {
    while bufs.len() != 0usize {
        let first = read (*bufs)[0usize]
        core.mem.drop(take first)
        if bufs.len() == 1usize {
            var first = mut (*bufs)[0usize]
            first.advance()
            core.mem.drop(take first)
            return
        }
        let removed = core.slice.split_off_first_mut(mut bufs).or_panic()
        core.mem.drop(take removed)
    }
}

fn main(): i32 {
    var first = [1u8, 2u8, 3u8]
    var second = [4u8, 5u8, 6u8]
    var buffers = [MutBuffer(mut first), MutBuffer(mut second)]
    var window = mut buffers[..]
    mutate_element(mut window)
    if (*window)[0usize].data.len() != 2usize || (*window)[0usize].data[0usize] != 2u8 {
        return 1
    }
    advance_slices(mut window)
    if window.len() != 1usize || (*window)[0usize].data.len() != 2usize ||
        (*window)[0usize].data[0usize] != 5u8 {
        return 2
    }
    0
}
