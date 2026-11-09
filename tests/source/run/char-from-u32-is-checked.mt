import core.char.from_u32

fn main(): i32 {
    match from_u32(0x1f642u32) {
        present(value) => { if value != '🙂' { return 1 } },
        none => { return 2 }
    }
    0
}
