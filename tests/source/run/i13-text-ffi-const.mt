// profiles: debug release
import core.ffi.CStr

const fn c_views(): bool {
    let bytes = [65u8, 0xc3u8, 0xa9u8, 0u8]
    let view = unsafe { CStr.from_bytes_with_nul_unchecked(bytes) }
    if view.count_bytes() != 3usize || view.is_empty() { return false }
    if view.to_bytes_with_nul().len() != 4usize || view.to_bytes()[2usize] != 0xa9u8 { return false }
    match view.to_str() {
        success(text) => if text.len() != 3usize { return false },
        failure(_) => { return false }
    }
    let scanned = unsafe { CStr.from_ptr(view.as_ptr()) }
    if scanned.count_bytes() != 3usize || scanned.to_bytes()[0usize] != 65u8 { return false }
    let empty_bytes = [0u8]
    let empty = unsafe { CStr.from_bytes_with_nul_unchecked(empty_bytes) }
    empty.is_empty() && empty.count_bytes() == 0usize && empty.to_bytes().len() == 0usize
}

const fn utf8(): bool {
    match core.text.from_utf8([65u8, 0xc3u8, 0xa9u8]) {
        success(text) => if text.len() != 3usize || text.as_bytes()[2usize] != 0xa9u8 { return false },
        failure(_) => { return false }
    }
    match core.text.from_utf8([65u8, 0xe2u8, 0x82u8]) {
        failure(error) => {
            if error.valid_up_to() != 1usize { return false }
            match error.error_len() { present(_) => { return false }, none => () }
        },
        success(_) => { return false }
    }
    match core.text.from_utf8([0xedu8, 0xa0u8, 0x80u8]) {
        failure(error) => match error.error_len() {
            present(length) => error.valid_up_to() == 0usize && length == 1usize,
            none => false
        },
        success(_) => false
    }
}

const fn text_views(): bool {
    let bytes = [9u8, 65u8, 0xc3u8, 0xa9u8, 32u8, 10u8]
    let lower = [9u8, 97u8, 0xc3u8, 0xa9u8, 32u8, 10u8]
    let value = match core.text.from_utf8(bytes) {
        success(text) => text,
        failure(_) => { return false }
    }
    let other = match core.text.from_utf8(lower) {
        success(text) => text,
        failure(_) => { return false }
    }
    if !value.eq_ignore_ascii_case(other) { return false }
    if value.trim_ascii_start().len() != 5usize || value.trim_ascii_end().len() != 4usize { return false }
    let trimmed = value.trim_ascii()
    if trimmed.len() != 3usize || trimmed.as_bytes()[0usize] != 65u8 ||
        trimmed.as_bytes()[2usize] != 0xa9u8 { return false }
    match value.split_at_checked(3usize) { present(_) => { return false }, none => () }
    match value.split_at_checked(7usize) { present(_) => { return false }, none => () }
    match value.split_at_checked(2usize) {
        present(parts) => if parts.0.len() != 2usize || parts.1.len() != 4usize { return false },
        none => { return false }
    }
    var mutable_bytes = [65u8, 66u8, 0xc3u8, 0xa9u8]
    let mutable = match take core.text.from_utf8_mut(mut mutable_bytes) {
        success(text) => text,
        failure(_) => { return false }
    }
    let parts = mutable.split_at_mut(2usize)
    parts.0.len() == 2usize && parts.1.len() == 2usize && parts.1.as_bytes()[0usize] == 0xc3u8
}

const C_VIEWS: bool = c_views()
const UTF8: bool = utf8()
const TEXT_VIEWS: bool = text_views()
fn main(): i32 { if C_VIEWS && UTF8 && TEXT_VIEWS { 0 } else { 1 } }
