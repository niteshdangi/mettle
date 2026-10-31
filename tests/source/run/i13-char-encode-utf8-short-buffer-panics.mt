// expect-exit: 101

fn main(): i32 {
    var buf = [0u8, 0u8, 0u8]
    let _ = '🦀'.encode_utf8(mut buf)
    0
}
