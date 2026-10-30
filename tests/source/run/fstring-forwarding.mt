// expect-exit: 0
// A message forwarded through two `format` levels renders unchanged: bool and
// integer holes, a plain Text argument lifted to a single-text recipe and
// literal text, including a named argument.
import core::fmt::Message;
import core::fmt::buffer_writer;

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
fn main(): i32 {
    var buffer = [0u8; 64]
    let a = 1
    let b = 2
    let n1 = relay(f"{a < b}", mut buffer)
    if !same(read buffer, n1, "true") { return 1 }
    let n2 = relay(message: f"value={42}", mut buffer)
    if !same(read buffer, n2, "value=42") { return 2 }
    let n3 = relay("plain", mut buffer)
    if !same(read buffer, n3, "plain") { return 3 }
    let n4 = relay(f"no holes", mut buffer)
    if !same(read buffer, n4, "no holes") { return 4 }
    0
}
