// profiles: debug release
import core.cmp.{Ord, PartialEq}
import core.ffi.{CStr, FromBytesWithNulError}
import core.fmt
import core.iter.{range_from, RangeFrom}
import core.ops.Index

fn main(): i32 {
    let bytes = [65u8, 0xffu8, 0xe2u8, 0x82u8, 0u8]
    let value = match capture CStr.from_bytes_with_nul(bytes) {
        success(view) => view,
        failure(_) => { return 1 }
    }
    if value.count_bytes() != 4usize || value.is_empty() { return 2 }
    if value.to_bytes_with_nul().len() != 5usize || value.to_bytes()[1usize] != 0xffu8 { return 3 }
    let pointer = value.as_ptr()
    let recovered = unsafe { CStr.from_ptr(pointer) }
    if !CStr.(PartialEq).eq(value, recovered) || !value.cmp(recovered).is_eq() { return 4 }
    let tail = CStr.(Index<RangeFrom<usize>>).index(value, range_from(4usize))
    if !tail.is_empty() || tail.to_bytes_with_nul().len() != 1usize { return 5 }
    match value.to_str() {
        success(_) => { return 6 },
        failure(error) => {
            if error.valid_up_to() != 1usize || error.error_len() != present(1usize) { return 7 }
        }
    }
    let prefix_bytes = [65u8, 0u8, 66u8]
    let prefixed = match capture CStr.from_bytes_until_nul(prefix_bytes) {
        success(view) => view,
        failure(_) => { return 8 }
    }
    if prefixed.count_bytes() != 1usize { return 9 }
    let interior = [65u8, 0u8, 0u8]
    match capture CStr.from_bytes_with_nul(interior) {
        failure(FromBytesWithNulError.InteriorNul { position }) => if position != 1usize { return 10 },
        _ => { return 11 }
    }
    let unterminated = [65u8]
    match capture CStr.from_bytes_with_nul(unterminated) {
        failure(FromBytesWithNulError.NotNulTerminated) => {},
        _ => { return 12 }
    }
    match capture CStr.from_bytes_until_nul(unterminated) {
        failure(_) => {},
        _ => { return 13 }
    }
    var storage: [u8; 64] = [0u8; 64]
    var output = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture CStr.(fmt.Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return 14 }
    }
    let written = output.len()
    if fmt.written_text(read storage, written).unwrap() != "CStr(\"A\u{fffd}\u{fffd}\")" { return 15 }
    var empty: [u8; 0] = []
    var refused = fmt.buffer_writer(mut empty)
    var refused_formatter = fmt.formatter(mut refused, fmt.spec())
    match capture CStr.(fmt.Debug).fmt(value, mut refused_formatter) {
        failure(_) => {},
        success(_) => { return 16 }
    }
    0
}
