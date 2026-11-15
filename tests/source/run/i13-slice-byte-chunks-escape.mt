// profiles: debug release
import core.cmp.Eq
import core.clone.Clone
import core.iter.FusedIterator

fn equal<T: Eq>(read left: T, read right: T): bool { left == right }

fn require_fused<I: FusedIterator>(mut iterator: I): bool {
    while iterator.next().is_present() {}
    !iterator.next().is_present()
}

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
    if !require_fused(view.escape_ascii()) { return 7 }

    var chunks = view.utf8_chunks()
    let first = match take chunks.next() { present(chunk) => chunk, none => { return 2 } }
    if first.valid() != "a\n" || first.invalid().len() != 1usize || first.invalid()[0usize] != 255u8 { return 3 }
    let first_copy = first.clone()
    if !equal(first, first_copy) { return 7 }
    let invalid_alt_bytes = [97u8, 10u8, 254u8]
    var invalid_alt_chunks = (read invalid_alt_bytes).utf8_chunks()
    let invalid_alt = match take invalid_alt_chunks.next() { present(chunk) => chunk, none => { return 8 } }
    if first == invalid_alt { return 9 }
    let valid_alt_bytes = [98u8, 255u8]
    var valid_alt_chunks = (read valid_alt_bytes).utf8_chunks()
    let valid_alt = match take valid_alt_chunks.next() { present(chunk) => chunk, none => { return 10 } }
    if first == valid_alt { return 11 }
    let second = match take chunks.next() { present(chunk) => chunk, none => { return 4 } }
    if second.valid() != "b" || second.invalid().len() != 0usize { return 5 }
    if chunks.next().is_present() { return 6 }
    0
}
