// profiles: debug release
import alloc.string.{String, from_utf16be, from_utf16le, from_utf16be_lossy, from_utf16le_lossy}

fn main(): i32 {
    match capture from_utf16be([0u8, 65u8, 0xd8u8, 0x3du8, 0xdeu8, 0u8]) {
        success(text) => { if text.as_text() != "A\u{1f600}" { return 1 } },
        failure(_) => { return 2 }
    }
    match capture String.from_utf16le([65u8, 0u8, 0x3du8, 0xd8u8, 0u8, 0xdeu8]) {
        success(text) => { if text.as_text() != "A\u{1f600}" { return 3 } },
        failure(_) => { return 4 }
    }
    match capture from_utf16le([65u8]) {
        success(_) => { return 5 },
        failure(error) => { if error.index != 0usize { return 6 } }
    }
    match capture String.from_utf16be([0u8, 65u8, 0u8]) {
        success(_) => { return 7 },
        failure(error) => { if error.index != 1usize { return 8 } }
    }
    if from_utf16be_lossy([0xd8u8, 0u8, 0u8, 65u8, 1u8]).as_text() != "\u{fffd}A\u{fffd}" { return 9 }
    if String.from_utf16le_lossy([0u8, 0xdcu8]).as_text() != "\u{fffd}" { return 10 }
    if from_utf16le_lossy([0xffu8, 0xfeu8, 65u8, 0u8]).as_text() != "\u{feff}A" { return 11 }
    if String.from_utf16be_lossy([0u8, 65u8]).as_text() != "A" { return 12 }
    0
}
