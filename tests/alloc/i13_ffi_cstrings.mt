import core.ffi.CStr
import core.cmp.PartialEq
import core.convert.From
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Box
import alloc.ffi.{CString, NulError}
import alloc.string.ToString
import alloc.vec
import core.fmt

fn main(): i32 {
    let borrowed = unsafe { CStr.from_bytes_with_nul_unchecked("a\u{e9}\u{0}".as_bytes()) }
    let owner = borrowed.to_owned()
    if !CStr.(PartialEq).eq(owner.as_c_str(), borrowed) { return 1 }
    let pointer = owner.as_ptr()
    let boxed = owner.into_boxed_c_str()
    let moved = CString.(From<Box<CStr>>).from(take boxed)
    if moved.as_ptr() != pointer { return 2 }
    let raw = moved.into_raw()
    unsafe { *raw = 98i8 }
    let restored = unsafe { CString.from_raw(raw) }
    if restored.to_str().or_panic() != "b\u{e9}" { return 3 }
    let text = match take capture restored.into_string() {
        success(value) => value,
        failure(_) => { return 4 }
    }
    if text.as_text() != "b\u{e9}" || text.as_ptr() != raw.cast_const().cast<u8>() { return 5 }
    var invalid = vec.new<u8>()
    invalid.push(0xffu8)
    let invalid_owner = match take capture CString.new(take invalid) {
        success(value) => value,
        failure(_) => { return 6 }
    }
    let original = invalid_owner.as_ptr()
    match take capture invalid_owner.into_string() {
        success(_) => { return 7 },
        failure(error) => {
            if error.utf8_error().valid_up_to() != 0usize { return 8 }
            if error.into_cstring().as_ptr() != original { return 9 }
        }
    }
    let view: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Borrowed(borrowed)
    let copied = CString.(From<BorrowedOrOwned<region static, CStr>>).from(take view)
    let lossless = copied.to_string_lossy()
    if !lossless.is_borrowed() || lossless.as_ref() != "a\u{e9}" { return 10 }
    let core_view: read core.ffi.CStr = copied.as_c_str()
    if core_view.count_bytes() != 3usize { return 11 }
    let nul_error = match take capture CString.new(vec.from_array([65u8, 0u8, 66u8])) {
        failure(error) => error,
        success(_) => { return 12 }
    }
    if nul_error.to_string().as_text() != "nul byte found in provided data at position: 1" { return 13 }
    if NulError.(core.error.Error).source(nul_error).is_present() { return 14 }
    var storage: [u8; 64] = [0u8; 64]
    var output = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture NulError.(fmt.Debug).fmt(nul_error, mut formatter) {
        success(_) => {},
        failure(_) => { return 15 }
    }
    let written = output.len()
    if fmt.written_text(read storage, written).or_panic() != "NulError(1, [65, 0, 66])" { return 16 }
    var empty: [u8; 0] = []
    var refused = fmt.buffer_writer(mut empty)
    var refused_formatter = fmt.formatter(mut refused, fmt.spec())
    if (capture NulError.(fmt.Debug).fmt(nul_error, mut refused_formatter)).is_success() { return 17 }
    let recovered = nul_error.into_vec()
    if recovered.len() != 3usize || recovered[0usize] != 65u8 ||
        recovered[1usize] != 0u8 || recovered[2usize] != 66u8 { return 18 }
    let terminated = match take capture CString.new(vec.from_array([65u8])) {
        success(value) => value,
        failure(_) => { return 19 }
    }
    let terminated_bytes = terminated.into_bytes_with_nul()
    if terminated_bytes.len() != 2usize || terminated_bytes[0usize] != 65u8 ||
        terminated_bytes[1usize] != 0u8 { return 20 }
    0
}
