// profiles: debug release
import core.ffi.CStr

const fn checked(): bool {
    let bytes = [65u8, 0u8, 66u8]
    match capture CStr.from_bytes_until_nul(bytes) {
        success(value) => if value.count_bytes() != 1usize { return false },
        failure(_) => { return false }
    }
    let empty = [0u8, 65u8]
    match capture CStr.from_bytes_until_nul(empty) {
        success(value) => if !value.is_empty() { return false },
        failure(_) => { return false }
    }
    let absent = [65u8]
    match capture CStr.from_bytes_until_nul(absent) {
        failure(_) => true,
        success(_) => false
    }
}

const CHECKED: bool = checked()
fn main(): i32 { if CHECKED { 0 } else { 1 } }
