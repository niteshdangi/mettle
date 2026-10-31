import core.char.from_u32

fn main(): i32 {
    match from_u32(0x1f642u32) {
        present(value) => { if value != '🙂' { return 1 } },
        none => { return 2 }
    }
    match from_u32(0xd800u32) {
        present(value) => { let _ = value; return 3 },
        none => {}
    }
    match from_u32(0x110000u32) {
        present(value) => { let _ = value; return 4 },
        none => {}
    }
    0
}
