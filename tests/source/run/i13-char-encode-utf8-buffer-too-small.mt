// profiles: debug release
// Evidence that char::encode_utf8 panics (code 101) and leaves a short buffer
// unchanged when the scalar needs more bytes than the buffer holds.
import core.char
import std.panic.{ catch_panic, CatchResult }

fn main(): i32 {
    var buffer = [0x12u8; 3]
    let caught = catch_panic(fn(): Unit {
        let _encoded = '\u{1f600}'.encode_utf8(mut buffer)
    })
    match take caught {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message() != "UTF-8 buffer is too small" {
                return 1
            }
        },
        CatchResult.Returned(_) => { return 2 }
    }
    if buffer[0usize] != 0x12u8 || buffer[2usize] != 0x12u8 { return 3 }
    0
}
