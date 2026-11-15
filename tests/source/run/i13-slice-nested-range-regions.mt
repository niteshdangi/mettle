type MutBuffer<region r> { data: mut [u8] from r }

fn consume<region s, region r>(
    mut bufs: mut [MutBuffer<region r>] from s
): Unit {}

fn main(): i32 {
    var first = [1u8, 2u8]
    var second = [3u8, 4u8]
    var buffers = [MutBuffer(mut first), MutBuffer(mut second)]
    var window = mut buffers[..]
    consume(mut window)
    var nested = mut (*window)[..]
    consume(mut nested)
    0
}
