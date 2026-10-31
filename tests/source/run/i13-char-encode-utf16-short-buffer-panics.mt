// expect-exit: 101

fn main(): i32 {
    var buf = [0u16]
    let _ = '🦀'.encode_utf16(mut buf)
    0
}
