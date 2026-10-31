import core.char.from_u32

fn main(): i32 {
    match from_u32(0x1f642u32) {
        present(value) => { if value != '🙂' { return 1 } },
        none => { return 2 }
    }
    match from_u32(0xd7ffu32) {
        present(value) => { if value != '\u{d7ff}' { return 3 } },
        none => { return 4 }
    }
    match from_u32(0x10ffffu32) {
        present(value) => { if value != '\u{10ffff}' { return 8 } },
        none => { return 9 }
    }
    match from_u32(0xd800u32) {
        present(value) => { let _ = value; return 5 },
        none => {}
    }
    match from_u32(0xdfffu32) {
        present(value) => { let _ = value; return 6 },
        none => {}
    }
    match from_u32(0x110000u32) {
        present(value) => { let _ = value; return 7 },
        none => {}
    }
    0
}
