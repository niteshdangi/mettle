// profiles: debug release
fn main(): i32 {
    let source = [97u8, 10u8, 255u8, 98u8]
    let view: read [u8] = read source
    var escaped = view.escape_ascii()
    var rendered = [0u8; 8]
    var count = 0usize
    while true {
        match escaped.next() {
            present(byte) => { rendered[count] = byte; count += 1usize },
            none => { break }
        }
    }
    if count != 8usize || rendered[0usize] != 97u8 || rendered[1usize] != 92u8 || rendered[2usize] != 110u8 || rendered[7usize] != 98u8 { return 1 }

    var chunks = view.utf8_chunks()
    let first = match take chunks.next() { present(chunk) => chunk, none => { return 2 } }
    if first.valid() != "a\n" || first.invalid().len() != 1usize || first.invalid()[0usize] != 255u8 { return 3 }
    let second = match take chunks.next() { present(chunk) => chunk, none => { return 4 } }
    if second.valid() != "b" || second.invalid().len() != 0usize { return 5 }
    if chunks.next().is_present() { return 6 }
    0
}
