type Buffer<region r> { data: mut [u8] from r }

fn fill<region r>(mut buffers: [Buffer<region r>]) {
    buffers[1].data[0] = 7u8
    buffers[2].data[0] = 9u8
}

fn count<region r, T>(read values: [T] from r): usize { values.len() }

fn inspect<region r, T>(mut values: mut [T] from r): usize { values.len() }

fn buffer_count<region r, region s>(
    mut buffers: mut [Buffer<region r>] from s
): usize {
    inspect(mut buffers)
}

fn main(): i32 {
    var empty = [0u8; 0]
    var first = [0u8; 1]
    var second = [0u8; 1]
    var buffers = [Buffer(mut empty), Buffer(mut first), Buffer(mut second)]
    fill(mut buffers)
    if count(read buffers) != 3usize { return 2 }
    {
        var view: mut [Buffer] = mut buffers[..]
        if buffer_count(mut view) != 3usize { return 3 }
    }
    if first[0] != 7u8 || second[0] != 9u8 { return 1 }
    0
}
