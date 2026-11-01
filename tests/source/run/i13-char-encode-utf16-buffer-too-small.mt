import core.char
import std.panic.{ catch_panic, CatchResult }

fn main(): i32 {
    var buffer = [0x1234u16; 1]
    let caught = catch_panic(fn(): Unit {
        let _encoded = '🦀'.encode_utf16(mut buffer)
    })
    match take caught {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message() != "UTF-16 buffer is too small" {
                return 1
            }
        },
        CatchResult.Returned(_) => { return 2 }
    }
    if buffer[0usize] != 0x1234u16 { return 3 }
    0
}
