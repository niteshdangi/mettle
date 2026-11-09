import std.ffi.{CStr, CString, FromBytesWithNulError, FromBytesUntilNulError, FromVecWithNulError, NulError}
import core.clone.Clone
import core.cmp.{Ord, PartialEq, PartialOrd}

fn main(): i32 {
    let payload: [u8; 3] = [255u8, 128u8, 65u8]
    let constructed = capture CString.new(std.ffi.os_string_from_bytes(payload).into_bytes())
    let value = match take constructed {
        success(c_string) => c_string,
        failure(_) => { return 1 }
    }
    if value.count_bytes() != 3usize || value.is_empty() { return 2 }
    if !std.ffi.bytes_equal(value.as_bytes(), payload) { return 3 }

    let terminated: [u8; 4] = [255u8, 128u8, 65u8, 0u8]
    if !std.ffi.bytes_equal(value.as_bytes_with_nul(), terminated) { return 4 }
    if value.as_ptr().cast<u8>() != value.as_bytes_with_nul().as_ptr() { return 42 }
    if value.to_string_lossy().as_text() != "\u{fffd}\u{fffd}A" { return 43 }
    let borrowed = value.as_c_str()
    if !std.ffi.bytes_equal(borrowed.to_bytes(), payload) { return 5 }
    if !std.ffi.bytes_equal(borrowed.to_bytes_with_nul(), terminated) { return 6 }
    if borrowed.as_ptr().cast<u8>() != borrowed.to_bytes_with_nul().as_ptr() { return 44 }
    if !borrowed.cmp(borrowed).is_eq() { return 46 }
    if !borrowed.partial_cmp(borrowed).is_present() { return 47 }
    if borrowed.to_str().is_present() { return 7 }
    if borrowed.to_string_lossy().as_text() != "\u{fffd}\u{fffd}A" { return 45 }
    let duplicate = value.clone()
    if !duplicate.eq(borrowed) || !borrowed.eq(duplicate) { return 38 }
    if !duplicate.cmp(value).is_eq() { return 39 }
    if core.hash.hash_one(borrowed) != core.hash.hash_one(value) { return 40 }
    let checked = match take capture CStr.from_bytes_with_nul(terminated) {
        success(c_string) => c_string,
        failure(_) => { return 30 }
    }
    if !std.ffi.bytes_equal(checked.to_bytes(), payload) { return 31 }

    let bad_bytes: [u8; 3] = [65u8, 0u8, 66u8]
    match take capture CString.new(std.ffi.os_string_from_bytes(bad_bytes).into_bytes()) {
        success(_) => { return 8 },
        failure(error) => {
            if error.nul_position() != 1usize { return 9 }
            if !std.ffi.bytes_equal(error.into_vec().as_slice(), bad_bytes) { return 10 }
        }
    }

    let not_terminated: [u8; 2] = [65u8, 66u8]
    match take capture CStr.from_bytes_with_nul(not_terminated) {
        success(_) => { return 11 },
        failure(FromBytesWithNulError.NotNulTerminated) => {},
        failure(_) => { return 12 }
    }
    let no_bytes: [u8; 0] = []
    match take capture CStr.from_bytes_with_nul(no_bytes) {
        success(_) => { return 32 },
        failure(FromBytesWithNulError.NotNulTerminated) => {},
        failure(_) => { return 33 }
    }
    let interior: [u8; 3] = [65u8, 0u8, 0u8]
    match take capture CStr.from_bytes_with_nul(interior) {
        success(_) => { return 13 },
        failure(FromBytesWithNulError.InteriorNul { position }) => {
            if position != 1usize { return 14 }
        },
        failure(_) => { return 15 }
    }

    let prefix: [u8; 2] = [255u8, 0u8]
    let tail: [u8; 2] = [66u8, 67u8]
    let bytes: [u8; 4] = [255u8, 0u8, 66u8, 67u8]
    let prefix_view = match take capture CStr.from_bytes_until_nul(bytes) {
        success(view) => view,
        failure(_) => { return 16 }
    }
    if !std.ffi.bytes_equal(prefix_view.to_bytes_with_nul(), prefix) { return 16 }
    let prefix_payload = prefix_view.to_bytes()
    if prefix_payload.len() != 1usize || prefix_payload[0usize] != 255u8 { return 41 }
    match take capture CStr.from_bytes_until_nul(tail) {
        success(_) => { return 17 },
        failure(FromBytesUntilNulError {}) => {}
    }

    let invalid_owned: [u8; 3] = [65u8, 0u8, 66u8]
    match take capture CString.from_vec_with_nul(
        std.ffi.os_string_from_bytes(invalid_owned).into_bytes()
    ) {
        success(_) => { return 19 },
        failure(error) => {
            if !std.ffi.bytes_equal(error.as_bytes(), invalid_owned) { return 20 }
            if !std.ffi.bytes_equal(error.into_bytes().as_slice(), invalid_owned) { return 21 }
        }
    }
    let unterminated: [u8; 2] = [65u8, 66u8]
    match take capture CString.from_vec_with_nul(
        std.ffi.os_string_from_bytes(unterminated).into_bytes()
    ) {
        success(_) => { return 36 },
        failure(error) => {
            if !std.ffi.bytes_equal(error.as_bytes(), unterminated) { return 37 }
        }
    }

    let empty = std.ffi.os_string_from_bytes([0u8]).into_bytes()
    let empty_c_string = match take capture CString.from_vec_with_nul(empty) {
        success(c_string) => c_string,
        failure(_) => { return 22 }
    }
    if !empty_c_string.is_empty() || empty_c_string.count_bytes() != 0usize { return 23 }
    match take capture CString.new(std.ffi.os_string_from_bytes([65u8, 0u8]).into_bytes()) {
        success(_) => { return 34 },
        failure(error) => {
            if error.nul_position() != 1usize { return 35 }
        }
    }

    let ascii: [u8; 3] = [109u8, 101u8, 116u8]
    let ascii_c_string = match take capture CString.new(
        std.ffi.os_string_from_bytes(ascii).into_bytes()
    ) {
        success(c_string) => c_string,
        failure(_) => { return 24 }
    }
    match take capture ascii_c_string.into_string() {
        success(text) => {
            if !std.ffi.bytes_equal(text.as_bytes(), ascii) { return 25 }
        },
        failure(_) => { return 26 }
    }

    match take capture value.into_string() {
        success(_) => { return 27 },
        failure(error) => {
            if !std.ffi.bytes_equal(error.as_c_str().to_bytes(), payload) { return 28 }
            let recovered = error.into_cstring()
            if !std.ffi.bytes_equal(recovered.as_bytes(), payload) { return 29 }
        }
    }
    0
}
