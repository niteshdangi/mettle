// expect-error: unsafe 11:13 operation requires an unsafe block or unsafe function
// expect-error: unsafe 14:13 operation requires an unsafe block or unsafe function
// expect-error: unsafe 15:13 operation requires an unsafe block or unsafe function
// expect-error: unsafe 18:13 operation requires an unsafe block or unsafe function
// expect-error-count: 4
import std.ffi.{OsStr, OsString}
import std.ffi.os_str_from_encoded_bytes_unchecked
import std.ffi.os_string_from_encoded_bytes_unchecked
import alloc.vec
fn main(): i32 {
    let _ = OsStr.from_encoded_bytes_unchecked([65u8])
    var bytes = vec.new<u8>()
    bytes.push(65u8)
    let _ = OsString.from_encoded_bytes_unchecked(take bytes)
    let _ = os_str_from_encoded_bytes_unchecked([65u8])
    var more = vec.new<u8>()
    more.push(65u8)
    let _ = os_string_from_encoded_bytes_unchecked(take more)
    0
}
