// profiles: debug release
const fn utf8(): bool {
    let valid = [65u8, 0xc3u8, 0xa9u8]
    match core.text.from_utf8(valid) {
        success(text) => if text.len() != 3usize { return false },
        failure(_) => { return false }
    }
    let truncated = [65u8, 0xe2u8, 0x82u8]
    match core.text.from_utf8(truncated) {
        failure(error) => {
            if error.valid_up_to() != 1usize { return false }
            match error.error_len() { present(_) => { return false }, none => () }
        },
        success(_) => { return false }
    }
    let surrogate = [0xedu8, 0xa0u8, 0x80u8]
    match core.text.from_utf8(surrogate) {
        failure(error) => match error.error_len() {
            present(length) => error.valid_up_to() == 0usize && length == 1usize,
            none => false
        },
        success(_) => false
    }
}
const UTF8: bool = utf8()
fn main(): i32 { if UTF8 { 0 } else { 1 } }
