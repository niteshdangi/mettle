// profiles: debug release
import core.ffi.{CStr, FromBytesWithNulError}

const fn checked(): bool {
    let valid = [65u8, 0xc3u8, 0xa9u8, 0u8]
    match capture CStr.from_bytes_with_nul(valid) {
        success(value) => if value.count_bytes() != 3usize || value.is_empty() { return false },
        failure(_) => { return false }
    }
    let empty = [0u8]
    match capture CStr.from_bytes_with_nul(empty) {
        success(value) => if !value.is_empty() || value.count_bytes() != 0usize { return false },
        failure(_) => { return false }
    }
    let interior = [65u8, 0u8, 0u8]
    match capture CStr.from_bytes_with_nul(interior) {
        failure(FromBytesWithNulError.InteriorNul { position }) => if position != 1usize { return false },
        _ => { return false }
    }
    let unterminated = [65u8]
    match capture CStr.from_bytes_with_nul(unterminated) {
        failure(FromBytesWithNulError.NotNulTerminated) => {},
        _ => { return false }
    }
    let absent: [u8; 0] = []
    match capture CStr.from_bytes_with_nul(absent) {
        failure(FromBytesWithNulError.NotNulTerminated) => true,
        _ => false
    }
}

const CHECKED: bool = checked()
fn main(): i32 { if CHECKED { 0 } else { 1 } }
