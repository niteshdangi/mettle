// expect-exit: 0
// Hole boundaries and escapes: comparisons stay inside one hole, a `>` in one
// hole cannot close a `<` in another, `{{`/`}}` are literal braces, and each
// hole is evaluated exactly once in source order.
import core.fmt.Message;
import core.fmt.buffer_writer;

fn emit(message: format Message, buffer: mut [u8]): usize {
    var out = buffer_writer(mut buffer)
    let ignored = capture message.write_to(mut out)
    out.len()
}
fn log(message: format Message, buffer: mut [u8]): usize { emit(message, mut buffer) }
fn relay(message: format Message, buffer: mut [u8]): usize { log(message, mut buffer) }

fn same(buffer: read [u8], length: usize, expected: read Text): bool {
    let want = expected.as_bytes()
    if length != want.len() { return false }
    var i = 0usize
    while i < length {
        if buffer[i] != want[i] { return false }
        i += 1usize
    }
    true
}
fn next(counter: mut i32): i32 {
    counter += 1
    counter
}
fn main(): i32 {
    var buffer = [0u8; 64]
    let a = 1
    let b = 2
    let c = 5
    let d = 3
    let n1 = emit(f"{a < b} {c > (d)}", mut buffer)
    if !same(read buffer, n1, "true true") { return 1 }
    let n2 = emit(f"{{{a < b}}}", mut buffer)
    if !same(read buffer, n2, "{true}") { return 2 }
    var counter = 0
    let n3 = emit(f"{next(mut counter)},{next(mut counter)},{next(mut counter)}", mut buffer)
    if !same(read buffer, n3, "1,2,3") { return 3 }
    if counter != 3 { return 4 }
    let word: read Text = "hi"
    let n4 = emit(f"{word}!{'x'}\n", mut buffer)
    if !same(read buffer, n4, "hi!x\n") { return 5 }
    0
}
