// expect-error: ownership 13:30 live exclusive loan
type Buffer<region r> { data: mut [u8] from r }

fn conflict<region s, region r>(
    mut bufs: mut [Buffer<region r>] from s
): usize {
    var held: (mut Buffer<region r> from s)? = none
    var count = 0usize
    while count < 2usize {
        if count == 0usize {
            held = present(mut (*bufs)[0usize])
        } else {
            let first = read (*bufs)[0usize]
            core.mem.drop(take first)
        }
        count += 1usize
    }
    match take held {
        present(first) => first.data.len(),
        none => 0usize
    }
}

fn main(): i32 { 0 }
